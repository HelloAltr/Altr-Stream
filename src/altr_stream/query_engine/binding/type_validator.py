"""Schema-aware type validator for AltrQL v0.4.

Maps physical schema types into logical categories and validates operator/operand
compatibility, strict temporal literal checking, range bounds vs field type,
and strict rejection of NULL comparison operators.
"""

from __future__ import annotations

from typing import Union

from altr_stream.domain.schema import StandardDataType
from altr_stream.query_engine.domain.ast import (
    BooleanLiteral,
    ComparisonConstraint,
    CompoundAndConstraint,
    FloatLiteral,
    IntegerLiteral,
    LiteralValue,
    NullLiteral,
    Range,
    StringLiteral,
    TemporalLiteral,
    ValueSet,
)
from altr_stream.query_engine.domain.bound_ast import BoundFieldPath, LogicalTypeCategory
from altr_stream.query_engine.domain.errors import TypeCompatibilityError
from altr_stream.query_engine.domain.operators import ComparisonOperator, StringOperator


def to_logical_category(dtype: StandardDataType) -> LogicalTypeCategory:
    """Map normalized StandardDataType into high-level logical categories for AltrQL validation."""
    if dtype in (
        StandardDataType.INTEGER,
        StandardDataType.BIGINT,
        StandardDataType.SMALLINT,
        StandardDataType.FLOAT,
        StandardDataType.DECIMAL,
    ):
        return LogicalTypeCategory.NUMERIC

    if dtype in (
        StandardDataType.STRING,
        StandardDataType.UUID,
    ):
        return LogicalTypeCategory.STRING

    if dtype == StandardDataType.BOOLEAN:
        return LogicalTypeCategory.BOOLEAN

    if dtype in (
        StandardDataType.DATE,
        StandardDataType.TIME,
        StandardDataType.TIMESTAMP,
        StandardDataType.TIMESTAMPTZ,
    ):
        return LogicalTypeCategory.TEMPORAL

    return LogicalTypeCategory.UNKNOWN


def validate_field_operator_and_operand(
    field: BoundFieldPath,
    operator: Union[ComparisonOperator, StringOperator],
    operand: Union[LiteralValue, ValueSet, Range],
) -> None:
    """Validate that an operator and operand are compatible with a schema-bound field.

    Raises:
        TypeCompatibilityError: If operator or operand types are incompatible with the field type.
    """
    # 1. NULL with Operators (valid for all field types with EQ/NEQ)
    if isinstance(operand, NullLiteral):
        if isinstance(operator, StringOperator):
            raise TypeCompatibilityError(
                f"Operator '{operator.value}' requires STRING literal operand, got 'NullLiteral'."
            )
        if operator in (
            ComparisonOperator.GT,
            ComparisonOperator.LT,
            ComparisonOperator.GTE,
            ComparisonOperator.LTE,
        ):
            raise TypeCompatibilityError(
                f"Ordering operator '{operator.value}' is not supported with NULL on field '{field.full_path}'."
            )
        # ComparisonOperator.EQ and ComparisonOperator.NEQ with NullLiteral are valid for all field types
        return

    # 2. Reject unsupported schema types for non-NULL operations (e.g. JSON, ARRAY, BINARY)
    if field.logical_category == LogicalTypeCategory.UNKNOWN:
        raise TypeCompatibilityError(
            f"Field '{field.full_path}' has unsupported AltrQL comparison type '{field.data_type.value}'."
        )

    # 3. String Operators (STARTS, ENDS, HAS, NOT HAS)
    if isinstance(operator, StringOperator):
        if field.logical_category != LogicalTypeCategory.STRING:
            raise TypeCompatibilityError(
                f"Operator '{operator.value}' is not compatible with field '{field.full_path}' of type {field.logical_category.value}."
            )
        if isinstance(operand, ValueSet):
            _validate_value_set(field, operand)
        elif not isinstance(operand, StringLiteral):
            raise TypeCompatibilityError(
                f"Operator '{operator.value}' requires STRING literal operand, got '{operand.__class__.__name__}'."
            )
        return

    # 4. Comparison Operators (=, !=, >, <, >=, <=)
    is_ordering = operator in (
        ComparisonOperator.GT,
        ComparisonOperator.LT,
        ComparisonOperator.GTE,
        ComparisonOperator.LTE,
    )

    if is_ordering:
        if field.logical_category == LogicalTypeCategory.BOOLEAN:
            raise TypeCompatibilityError(
                f"Ordering operator '{operator.value}' is not supported for BOOLEAN field '{field.full_path}'."
            )

    # 5. Validate Operand Compatibility
    if isinstance(operand, Range):
        _validate_range(field, operand)
    elif isinstance(operand, ValueSet):
        _validate_value_set(field, operand)
    elif isinstance(operand, (IntegerLiteral, FloatLiteral)):
        if field.logical_category != LogicalTypeCategory.NUMERIC:
            raise TypeCompatibilityError(
                f"Cannot compare {field.logical_category.value} field '{field.full_path}' with NUMERIC literal."
            )
    elif isinstance(operand, StringLiteral):
        if field.logical_category != LogicalTypeCategory.STRING:
            raise TypeCompatibilityError(
                f"Cannot compare {field.logical_category.value} field '{field.full_path}' with STRING literal without explicit type conversion."
            )
    elif isinstance(operand, BooleanLiteral):
        if field.logical_category != LogicalTypeCategory.BOOLEAN:
            raise TypeCompatibilityError(
                f"Cannot compare {field.logical_category.value} field '{field.full_path}' with BOOLEAN literal."
            )
    elif isinstance(operand, TemporalLiteral):
        if field.logical_category != LogicalTypeCategory.TEMPORAL:
            temp_desc = operand.keyword.value if operand.keyword else f"@{operand.value}"
            raise TypeCompatibilityError(
                f"Cannot compare {field.logical_category.value} field '{field.full_path}' with TEMPORAL literal '{temp_desc}'."
            )


def _validate_range(field: BoundFieldPath, rng: Range) -> None:
    """Ensure range bounds match the field's logical type category."""
    start = rng.start
    end = rng.end

    if field.logical_category == LogicalTypeCategory.BOOLEAN:
        raise TypeCompatibilityError(
            f"Ranges are not supported on BOOLEAN field '{field.full_path}'."
        )

    if field.logical_category == LogicalTypeCategory.NUMERIC:
        if not (isinstance(start, (IntegerLiteral, FloatLiteral)) and isinstance(end, (IntegerLiteral, FloatLiteral))):
            raise TypeCompatibilityError(
                f"Range on NUMERIC field '{field.full_path}' must have numeric bounds, got '{start.kind}'..'{end.kind}'."
            )

    elif field.logical_category == LogicalTypeCategory.STRING:
        if not (isinstance(start, StringLiteral) and isinstance(end, StringLiteral)):
            raise TypeCompatibilityError(
                f"Range on STRING field '{field.full_path}' must have string bounds, got '{start.kind}'..'{end.kind}'."
            )

    elif field.logical_category == LogicalTypeCategory.TEMPORAL:
        if not (isinstance(start, TemporalLiteral) and isinstance(end, TemporalLiteral)):
            raise TypeCompatibilityError(
                f"Range on TEMPORAL field '{field.full_path}' must have temporal bounds, got '{start.kind.upper()}'..'{end.kind.upper()}'."
            )


def _validate_value_set(field: BoundFieldPath, vs: ValueSet) -> None:
    """Ensure all elements of a ValueSet match the field's logical type category."""
    for el in vs.elements:
        if isinstance(el, NullLiteral):
            continue
        elif isinstance(el, Range):
            _validate_range(field, el)
        elif isinstance(el, ComparisonConstraint):
            _validate_comparison_constraint(field, el)
        elif isinstance(el, CompoundAndConstraint):
            if field.logical_category == LogicalTypeCategory.BOOLEAN:
                raise TypeCompatibilityError(
                    f"Compound constraints are not supported on BOOLEAN field '{field.full_path}'."
                )
            for c in el.constraints:
                _validate_comparison_constraint(field, c)
        elif isinstance(el, (IntegerLiteral, FloatLiteral)):
            if field.logical_category != LogicalTypeCategory.NUMERIC:
                raise TypeCompatibilityError(
                    f"ValueSet element {el.value} is incompatible with {field.logical_category.value} field '{field.full_path}'."
                )
        elif isinstance(el, StringLiteral):
            if field.logical_category != LogicalTypeCategory.STRING:
                raise TypeCompatibilityError(
                    f"ValueSet element '{el.value}' (STRING) is incompatible with {field.logical_category.value} field '{field.full_path}'."
                )
        elif isinstance(el, BooleanLiteral):
            if field.logical_category != LogicalTypeCategory.BOOLEAN:
                raise TypeCompatibilityError(
                    f"ValueSet element {el.value} (BOOLEAN) is incompatible with {field.logical_category.value} field '{field.full_path}'."
                )
        elif isinstance(el, TemporalLiteral):
            if field.logical_category != LogicalTypeCategory.TEMPORAL:
                temp_desc = el.keyword.value if el.keyword else f"@{el.value}"
                raise TypeCompatibilityError(
                    f"ValueSet element '{temp_desc}' (TEMPORAL) is incompatible with {field.logical_category.value} field '{field.full_path}'."
                )


def _validate_comparison_constraint(field: BoundFieldPath, constraint: ComparisonConstraint) -> None:
    """Ensure a comparison constraint is valid for the field type."""
    is_ordering = constraint.operator in (
        ComparisonOperator.GT,
        ComparisonOperator.LT,
        ComparisonOperator.GTE,
        ComparisonOperator.LTE,
    )
    if is_ordering and field.logical_category == LogicalTypeCategory.BOOLEAN:
        raise TypeCompatibilityError(
            f"Ordering operator '{constraint.operator.value}' is not supported for BOOLEAN field '{field.full_path}'."
        )

    val = constraint.value
    if isinstance(val, NullLiteral):
        if is_ordering:
            raise TypeCompatibilityError(
                f"Ordering operator '{constraint.operator.value}' is not supported with NULL on field '{field.full_path}'."
            )
        return
    elif isinstance(val, (IntegerLiteral, FloatLiteral)):
        if field.logical_category != LogicalTypeCategory.NUMERIC:
            raise TypeCompatibilityError(
                f"Constraint value {val.value} is incompatible with {field.logical_category.value} field '{field.full_path}'."
            )
    elif isinstance(val, StringLiteral):
        if field.logical_category != LogicalTypeCategory.STRING:
            raise TypeCompatibilityError(
                f"Constraint value '{val.value}' (STRING) is incompatible with {field.logical_category.value} field '{field.full_path}'."
            )
    elif isinstance(val, BooleanLiteral):
        if field.logical_category != LogicalTypeCategory.BOOLEAN:
            raise TypeCompatibilityError(
                f"Constraint value {val.value} (BOOLEAN) is incompatible with {field.logical_category.value} field '{field.full_path}'."
            )
    elif isinstance(val, TemporalLiteral):
        if field.logical_category != LogicalTypeCategory.TEMPORAL:
            temp_desc = val.keyword.value if val.keyword else f"@{val.value}"
            raise TypeCompatibilityError(
                f"Constraint value '{temp_desc}' (TEMPORAL) is incompatible with {field.logical_category.value} field '{field.full_path}'."
            )


def validate_assignment_value(field: BoundFieldPath, value: LiteralValue) -> None:
    """Validate that a literal value assigned in a mutation payload is compatible with the target field's schema type.

    Raises:
        TypeCompatibilityError: If the literal value is incompatible with the field's schema data type.
    """
    # 1. NULL assignment is valid for nullable fields (including JSON/UNKNOWN)
    if isinstance(value, NullLiteral):
        if not field.nullable:
            raise TypeCompatibilityError(
                f"Cannot assign NULL to non-nullable field '{field.full_path}'."
            )
        return

    # 2. Reject unsupported schema types for non-NULL mutations (e.g. JSON, ARRAY, BINARY)
    if field.logical_category == LogicalTypeCategory.UNKNOWN:
        raise TypeCompatibilityError(
            f"Field '{field.full_path}' has unsupported AltrQL mutation type '{field.data_type.value}'."
        )

    # NUMERIC fields (INTEGER, FLOAT, BIGINT, SMALLINT, DECIMAL)
    if field.logical_category == LogicalTypeCategory.NUMERIC:
        if not isinstance(value, (IntegerLiteral, FloatLiteral)):
            raise TypeCompatibilityError(
                f"Cannot assign {value.__class__.__name__} to NUMERIC field '{field.full_path}'."
            )
        return

    # STRING fields (STRING, UUID)
    if field.logical_category == LogicalTypeCategory.STRING:
        if not isinstance(value, StringLiteral):
            raise TypeCompatibilityError(
                f"Cannot assign {value.__class__.__name__} to STRING field '{field.full_path}'."
            )
        return

    # BOOLEAN fields
    if field.logical_category == LogicalTypeCategory.BOOLEAN:
        if not isinstance(value, BooleanLiteral):
            raise TypeCompatibilityError(
                f"Cannot assign {value.__class__.__name__} to BOOLEAN field '{field.full_path}'."
            )
        return

    # TEMPORAL fields (DATE, TIME, TIMESTAMP, TIMESTAMPTZ)
    if field.logical_category == LogicalTypeCategory.TEMPORAL:
        if not isinstance(value, TemporalLiteral):
            raise TypeCompatibilityError(
                f"Cannot assign {value.__class__.__name__} to TEMPORAL field '{field.full_path}'. Expected @YYYY-MM-DD, TODAY, or NOW."
            )
        return

    raise TypeCompatibilityError(
        f"Cannot assign {value.__class__.__name__} to field '{field.full_path}' of type {field.logical_category.value}."
    )
