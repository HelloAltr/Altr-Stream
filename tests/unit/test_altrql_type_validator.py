"""Unit tests for AltrQL Type Validator (Phase D)."""

import pytest

from altr_stream.domain.schema import StandardDataType
from altr_stream.query_engine.binding.type_validator import (
    to_logical_category,
    validate_assignment_value,
    validate_field_operator_and_operand,
)
from altr_stream.query_engine.domain.ast import (
    BooleanLiteral,
    ComparisonConstraint,
    CompoundAndConstraint,
    FieldPath,
    FloatLiteral,
    IntegerLiteral,
    NullLiteral,
    Range,
    StringLiteral,
    TemporalKeyword,
    TemporalLiteral,
    ValueSet,
)
from altr_stream.query_engine.domain.bound_ast import BoundFieldPath, LogicalTypeCategory
from altr_stream.query_engine.domain.errors import TypeCompatibilityError
from altr_stream.query_engine.domain.operators import ComparisonOperator, StringOperator


def create_bound_field(name: str, data_type: StandardDataType, nullable: bool = False) -> BoundFieldPath:
    category = to_logical_category(data_type)
    return BoundFieldPath(
        path=FieldPath(segments=[name]),
        data_type=data_type,
        logical_category=category,
        native_type="test_native_type",
        nullable=nullable,
    )


# --- Category Mapping Tests ---


def test_logical_category_mapping():
    assert to_logical_category(StandardDataType.INTEGER) == LogicalTypeCategory.NUMERIC
    assert to_logical_category(StandardDataType.BIGINT) == LogicalTypeCategory.NUMERIC
    assert to_logical_category(StandardDataType.FLOAT) == LogicalTypeCategory.NUMERIC
    assert to_logical_category(StandardDataType.STRING) == LogicalTypeCategory.STRING
    assert to_logical_category(StandardDataType.UUID) == LogicalTypeCategory.STRING
    assert to_logical_category(StandardDataType.BOOLEAN) == LogicalTypeCategory.BOOLEAN
    assert to_logical_category(StandardDataType.TIMESTAMP) == LogicalTypeCategory.TEMPORAL
    assert to_logical_category(StandardDataType.DATE) == LogicalTypeCategory.TEMPORAL
    assert to_logical_category(StandardDataType.JSON) == LogicalTypeCategory.UNKNOWN


# --- Numeric Tests ---


def test_numeric_field_valid_comparisons():
    field = create_bound_field("age", StandardDataType.INTEGER)

    validate_field_operator_and_operand(field, ComparisonOperator.EQ, IntegerLiteral(value=25))
    validate_field_operator_and_operand(field, ComparisonOperator.GT, FloatLiteral(value=25.5))
    validate_field_operator_and_operand(field, ComparisonOperator.LTE, IntegerLiteral(value=100))


def test_numeric_field_invalid_string_operand():
    field = create_bound_field("age", StandardDataType.INTEGER)

    with pytest.raises(TypeCompatibilityError) as exc_info:
        validate_field_operator_and_operand(field, ComparisonOperator.EQ, StringLiteral(value="twenty"))
    assert "STRING" in str(exc_info.value)
    assert "NUMERIC" in str(exc_info.value)


def test_numeric_field_invalid_operator():
    field = create_bound_field("age", StandardDataType.INTEGER)

    with pytest.raises(TypeCompatibilityError) as exc_info:
        validate_field_operator_and_operand(
            field, StringOperator.STARTS, StringLiteral(value="2")
        )
    assert "STARTS" in str(exc_info.value)


# --- String Tests ---


def test_string_field_valid_comparisons():
    field = create_bound_field("name", StandardDataType.STRING)

    validate_field_operator_and_operand(field, ComparisonOperator.EQ, StringLiteral(value="Alice"))
    validate_field_operator_and_operand(field, StringOperator.STARTS, StringLiteral(value="Al"))
    validate_field_operator_and_operand(field, StringOperator.ENDS, StringLiteral(value="ce"))
    validate_field_operator_and_operand(field, StringOperator.HAS, StringLiteral(value="lic"))


def test_string_field_invalid_numeric_operand():
    field = create_bound_field("name", StandardDataType.STRING)

    with pytest.raises(TypeCompatibilityError) as exc_info:
        validate_field_operator_and_operand(field, ComparisonOperator.EQ, IntegerLiteral(value=123))
    assert "NUMERIC" in str(exc_info.value)
    assert "STRING" in str(exc_info.value)


# --- Boolean Tests ---


def test_boolean_field_valid_comparisons():
    field = create_bound_field("is_active", StandardDataType.BOOLEAN)

    validate_field_operator_and_operand(field, ComparisonOperator.EQ, BooleanLiteral(value=True))
    validate_field_operator_and_operand(field, ComparisonOperator.NEQ, BooleanLiteral(value=False))


def test_boolean_field_invalid_ordering_operator():
    field = create_bound_field("is_active", StandardDataType.BOOLEAN)

    with pytest.raises(TypeCompatibilityError) as exc_info:
        validate_field_operator_and_operand(field, ComparisonOperator.GT, BooleanLiteral(value=True))
    assert ">" in str(exc_info.value)


# --- Temporal Tests ---


def test_temporal_field_valid_comparisons():
    field = create_bound_field("created_at", StandardDataType.TIMESTAMP)

    validate_field_operator_and_operand(
        field, ComparisonOperator.GT, TemporalLiteral(keyword=TemporalKeyword.TODAY)
    )
    validate_field_operator_and_operand(
        field, ComparisonOperator.LTE, TemporalLiteral(keyword=TemporalKeyword.NOW)
    )
    validate_field_operator_and_operand(
        field, ComparisonOperator.EQ, TemporalLiteral(value="2026-01-01")
    )
    validate_field_operator_and_operand(
        field, ComparisonOperator.GTE, TemporalLiteral(value="1999-12-31")
    )


def test_temporal_field_rejects_string_literal():
    field = create_bound_field("created_at", StandardDataType.TIMESTAMP)

    with pytest.raises(TypeCompatibilityError) as exc_info:
        validate_field_operator_and_operand(
            field, ComparisonOperator.EQ, StringLiteral(value="2026-01-01")
        )
    assert "STRING" in str(exc_info.value)
    assert "TEMPORAL" in str(exc_info.value)


def test_numeric_field_rejects_temporal_iso_date_literal():
    field = create_bound_field("age", StandardDataType.INTEGER)

    with pytest.raises(TypeCompatibilityError) as exc_info:
        validate_field_operator_and_operand(
            field, ComparisonOperator.EQ, TemporalLiteral(value="2026-01-01")
        )
    assert "Cannot compare NUMERIC field 'age' with TEMPORAL literal '@2026-01-01'" in str(exc_info.value)


# --- Strict NULL Semantics Tests ---


def test_null_literal_allowed_for_equality_and_inequality():
    nullable_field = create_bound_field("optional_val", StandardDataType.STRING, nullable=True)
    non_nullable_field = create_bound_field("required_val", StandardDataType.STRING, nullable=False)

    # EQ and NEQ with NULL are valid on any field
    validate_field_operator_and_operand(nullable_field, ComparisonOperator.EQ, NullLiteral())
    validate_field_operator_and_operand(non_nullable_field, ComparisonOperator.NEQ, NullLiteral())
    validate_field_operator_and_operand(non_nullable_field, ComparisonOperator.EQ, NullLiteral())


def test_null_literal_rejected_with_ordering_and_string_operators():
    field = create_bound_field("age", StandardDataType.INTEGER, nullable=True)
    str_field = create_bound_field("name", StandardDataType.STRING, nullable=True)

    with pytest.raises(TypeCompatibilityError) as exc_info1:
        validate_field_operator_and_operand(field, ComparisonOperator.GT, NullLiteral())
    assert "Ordering operator '>' is not supported with NULL" in str(exc_info1.value)

    with pytest.raises(TypeCompatibilityError) as exc_info2:
        validate_field_operator_and_operand(str_field, StringOperator.HAS, NullLiteral())
    assert "requires STRING literal operand" in str(exc_info2.value)


# --- Range & ValueSet Tests ---


def test_numeric_range_compatibility():
    field = create_bound_field("age", StandardDataType.INTEGER)
    valid_range = Range(start=IntegerLiteral(value=18), end=FloatLiteral(value=65.5))
    validate_field_operator_and_operand(field, ComparisonOperator.EQ, valid_range)


def test_invalid_range_type_for_field():
    field = create_bound_field("age", StandardDataType.INTEGER)
    invalid_range = Range(start=StringLiteral(value="A"), end=StringLiteral(value="Z"))

    with pytest.raises(TypeCompatibilityError) as exc_info:
        validate_field_operator_and_operand(field, ComparisonOperator.EQ, invalid_range)
    assert "string" in str(exc_info.value)
    assert "NUMERIC" in str(exc_info.value)


def test_value_set_validation():
    field = create_bound_field("id", StandardDataType.INTEGER)
    valid_value_set = ValueSet(
        elements=[
            IntegerLiteral(value=1),
            IntegerLiteral(value=2),
            Range(start=IntegerLiteral(value=5), end=IntegerLiteral(value=10)),
        ]
    )
    validate_field_operator_and_operand(field, ComparisonOperator.EQ, valid_value_set)


def test_value_set_heterogeneous_invalid_type():
    field = create_bound_field("id", StandardDataType.INTEGER)
    invalid_value_set = ValueSet(
        elements=[
            IntegerLiteral(value=1),
            StringLiteral(value="invalid"),
        ]
    )
    with pytest.raises(TypeCompatibilityError) as exc_info:
        validate_field_operator_and_operand(field, ComparisonOperator.EQ, invalid_value_set)
    assert "STRING" in str(exc_info.value)
    assert "NUMERIC" in str(exc_info.value)


def test_compound_and_constraint_validation():
    field = create_bound_field("age", StandardDataType.INTEGER)
    compound = CompoundAndConstraint(
        constraints=[
            ComparisonConstraint(operator=ComparisonOperator.GTE, value=IntegerLiteral(value=18)),
            ComparisonConstraint(operator=ComparisonOperator.LTE, value=IntegerLiteral(value=30)),
        ]
    )
    validate_field_operator_and_operand(field, ComparisonOperator.EQ, compound)


# --- JSON & Unknown Category NULL Tests ---


def test_json_field_allows_null_equality_and_inequality():
    json_field = create_bound_field("metadata", StandardDataType.JSON, nullable=True)

    # Both EQ and NEQ with NullLiteral must succeed
    validate_field_operator_and_operand(json_field, ComparisonOperator.EQ, NullLiteral())
    validate_field_operator_and_operand(json_field, ComparisonOperator.NEQ, NullLiteral())


def test_json_field_rejects_null_with_ordering_or_string_operators():
    json_field = create_bound_field("metadata", StandardDataType.JSON, nullable=True)

    with pytest.raises(TypeCompatibilityError) as exc_info1:
        validate_field_operator_and_operand(json_field, ComparisonOperator.GT, NullLiteral())
    assert "Ordering operator '>' is not supported with NULL" in str(exc_info1.value)

    with pytest.raises(TypeCompatibilityError) as exc_info2:
        validate_field_operator_and_operand(json_field, StringOperator.HAS, NullLiteral())
    assert "Operator 'HAS' requires STRING literal operand, got 'NullLiteral'" in str(exc_info2.value)


def test_json_field_rejects_non_null_comparisons():
    json_field = create_bound_field("metadata", StandardDataType.JSON, nullable=True)

    with pytest.raises(TypeCompatibilityError) as exc_info1:
        validate_field_operator_and_operand(json_field, ComparisonOperator.EQ, StringLiteral(value="{}"))
    assert "unsupported AltrQL comparison type 'JSON'" in str(exc_info1.value)

    with pytest.raises(TypeCompatibilityError) as exc_info2:
        validate_field_operator_and_operand(json_field, ComparisonOperator.EQ, IntegerLiteral(value=42))
    assert "unsupported AltrQL comparison type 'JSON'" in str(exc_info2.value)


def test_json_field_allows_null_assignment_when_nullable():
    json_field = create_bound_field("metadata", StandardDataType.JSON, nullable=True)
    validate_assignment_value(json_field, NullLiteral())


def test_json_field_rejects_null_assignment_when_non_nullable():
    non_null_json = create_bound_field("metadata", StandardDataType.JSON, nullable=False)
    with pytest.raises(TypeCompatibilityError) as exc_info:
        validate_assignment_value(non_null_json, NullLiteral())
    assert "Cannot assign NULL to non-nullable field 'metadata'" in str(exc_info.value)


def test_json_field_rejects_non_null_assignment():
    json_field = create_bound_field("metadata", StandardDataType.JSON, nullable=True)

    with pytest.raises(TypeCompatibilityError) as exc_info1:
        validate_assignment_value(json_field, StringLiteral(value="{}"))
    assert "unsupported AltrQL mutation type 'JSON'" in str(exc_info1.value)

    with pytest.raises(TypeCompatibilityError) as exc_info2:
        validate_assignment_value(json_field, IntegerLiteral(value=100))
    assert "unsupported AltrQL mutation type 'JSON'" in str(exc_info2.value)

