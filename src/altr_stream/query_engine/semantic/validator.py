"""Semantic validator for AltrQL Intermediate Representation (IR).

Enforces language invariants, AST structure rules, range type compatibility,
ranking count bounds, and mutual exclusivity constraints.
"""

from __future__ import annotations

from typing import Set

from altr_stream.query_engine.domain.ast import (
    AltrQueryIR,
    BooleanLiteral,
    ComparisonConstraint,
    CompoundAndConstraint,
    Expression,
    FieldExpression,
    FloatLiteral,
    IntegerLiteral,
    LiteralValue,
    LogicalExpression,
    LogicalOperator,
    MutationAssignment,
    NegationExpression,
    NullLiteral,
    QueryOperation,
    Range,
    StringLiteral,
    TemporalLiteral,
    ValueSet,
    ValueSetElement,
)
from altr_stream.query_engine.domain.errors import AltrQuerySemanticError
from altr_stream.query_engine.domain.operators import StringOperator


def validate_ir(ir: AltrQueryIR) -> None:
    """Validate all structural and semantic invariants of an AltrQueryIR tree.

    Raises:
        AltrQuerySemanticError: If any semantic rule or AST invariant is violated.
    """
    if ir.operation == QueryOperation.READ:
        if len(ir.assignments) > 0:
            raise AltrQuerySemanticError("Mutation assignments are not allowed on READ queries.")
        _validate_projections(ir)
        _validate_ranking(ir)
        _validate_offset(ir)
        _validate_sort_and_ranking_mutual_exclusion(ir)
        if ir.where is not None:
            _validate_expression(ir.where)

    elif ir.operation == QueryOperation.CREATE:
        if len(ir.records) < 1 and len(ir.assignments) < 1:
            raise AltrQuerySemanticError("CREATE operation requires at least 1 record or field assignment.")
        if len(ir.records) > 0:
            for record in ir.records:
                if len(record.assignments) < 1:
                    raise AltrQuerySemanticError("Record in CREATE batch cannot be empty.")
                _validate_mutation_assignments(record.assignments)
        elif len(ir.assignments) > 0:
            _validate_mutation_assignments(ir.assignments)
        if len(ir.projection) > 0:
            raise AltrQuerySemanticError("Projection is not allowed on CREATE operations.")
        if ir.where is not None:
            raise AltrQuerySemanticError("WHERE clause is not allowed on CREATE operations.")
        if len(ir.sort) > 0 or ir.ranking is not None:
            raise AltrQuerySemanticError("SORT/ranking clauses are not allowed on CREATE operations.")
        if ir.offset is not None:
            raise AltrQuerySemanticError("OFFSET clause is not allowed on CREATE operations.")

    elif ir.operation == QueryOperation.UPDATE:
        if len(ir.assignments) < 1:
            raise AltrQuerySemanticError("UPDATE operation requires at least 1 field assignment.")
        _validate_mutation_assignments(ir.assignments)
        if len(ir.projection) > 0:
            raise AltrQuerySemanticError("Projection is not allowed on UPDATE operations.")
        if len(ir.sort) > 0 or ir.ranking is not None:
            raise AltrQuerySemanticError("SORT/ranking clauses are not allowed on UPDATE operations.")
        if ir.offset is not None:
            raise AltrQuerySemanticError("OFFSET clause is not allowed on UPDATE operations.")
        if ir.where is not None:
            _validate_expression(ir.where)

    elif ir.operation == QueryOperation.DELETE:
        if len(ir.assignments) > 0:
            raise AltrQuerySemanticError("Mutation assignments are not allowed on DELETE operations.")
        if len(ir.projection) > 0:
            raise AltrQuerySemanticError("Projection is not allowed on DELETE operations.")
        if len(ir.sort) > 0 or ir.ranking is not None:
            raise AltrQuerySemanticError("SORT/ranking clauses are not allowed on DELETE operations.")
        if ir.offset is not None:
            raise AltrQuerySemanticError("OFFSET clause is not allowed on DELETE operations.")
        if ir.where is not None:
            _validate_expression(ir.where)


def _validate_mutation_assignments(assignments: list[MutationAssignment]) -> None:
    """Ensure mutation assignment fields are unique across the payload."""
    seen_fields: Set[str] = set()
    for assign in assignments:
        field_str = assign.field.full_path
        if field_str in seen_fields:
            raise AltrQuerySemanticError(
                f"Duplicate assignment for field '{field_str}' found in mutation payload."
            )
        seen_fields.add(field_str)


def _validate_projections(ir: AltrQueryIR) -> None:
    """Ensure projection aliases are unique across all selections."""
    seen_aliases: Set[str] = set()
    for selection in ir.projection:
        if selection.alias is not None:
            if selection.alias in seen_aliases:
                raise AltrQuerySemanticError(
                    f"Duplicate projection alias '{selection.alias}' found in query projection."
                )
            seen_aliases.add(selection.alias)


def _validate_ranking(ir: AltrQueryIR) -> None:
    """Ensure ranking count is strictly greater than zero."""
    if ir.ranking is not None:
        if ir.ranking.count <= 0:
            raise AltrQuerySemanticError(
                f"Ranking count must be a positive integer greater than 0, got {ir.ranking.count}."
            )


def _validate_offset(ir: AltrQueryIR) -> None:
    """Ensure OFFSET is non-negative."""
    if ir.offset is not None:
        if ir.offset < 0:
            raise AltrQuerySemanticError(
                f"OFFSET must be non-negative (>= 0), got {ir.offset}."
            )


def _validate_sort_and_ranking_mutual_exclusion(ir: AltrQueryIR) -> None:
    """Enforce mutual exclusivity of SORT and TOP/BOTTOM ranking in v0.1."""
    if len(ir.sort) > 0 and ir.ranking is not None:
        raise AltrQuerySemanticError(
            "Cannot combine 'SORT' with 'TOP'/'BOTTOM' ranking clause in AltrQL v0.1."
        )


def _validate_expression(expr: Expression) -> None:
    """Recursively validate logical, negation, and field expressions."""
    if isinstance(expr, LogicalExpression):
        if expr.left is None or expr.right is None:
            raise AltrQuerySemanticError(
                "LogicalExpression requires both left and right operand expressions."
            )
        _validate_expression(expr.left)
        _validate_expression(expr.right)

    elif isinstance(expr, NegationExpression):
        if expr.operand is None:
            raise AltrQuerySemanticError(
                "NegationExpression requires an operand expression."
            )
        _validate_expression(expr.operand)

    elif isinstance(expr, FieldExpression):
        _validate_field_expression(expr)


def _validate_field_expression(expr: FieldExpression) -> None:
    """Validate operator and operand compatibility on a field expression."""
    operand = expr.operand

    if isinstance(expr.operator, StringOperator):
        # String operators (STARTS, ENDS, HAS, NOT HAS) require string literals or string value sets
        if isinstance(operand, (IntegerLiteral, FloatLiteral, BooleanLiteral, NullLiteral, TemporalLiteral, Range)):
            raise AltrQuerySemanticError(
                f"String operator '{expr.operator.value}' cannot be used with operand of type '{operand.__class__.__name__}'."
            )
        elif isinstance(operand, ValueSet):
            _validate_value_set(operand)
            for elem in operand.elements:
                if not isinstance(elem, StringLiteral):
                    raise AltrQuerySemanticError(
                        f"String operator '{expr.operator.value}' cannot be used with non-string element '{elem.__class__.__name__}' in value set."
                    )
        elif isinstance(operand, StringLiteral):
            pass

    if isinstance(operand, Range):
        _validate_range(operand)
    elif isinstance(operand, ValueSet):
        _validate_value_set(operand)


def _validate_value_set(value_set: ValueSet) -> None:
    """Validate non-empty value sets and child constraint invariants."""
    if len(value_set.elements) < 1:
        raise AltrQuerySemanticError("ValueSet cannot be empty.")

    for elem in value_set.elements:
        _validate_value_set_element(elem)


def _validate_value_set_element(elem: ValueSetElement) -> None:
    """Validate elements inside a value set."""
    if isinstance(elem, Range):
        _validate_range(elem)
    elif isinstance(elem, CompoundAndConstraint):
        if len(elem.constraints) < 2:
            raise AltrQuerySemanticError(
                "CompoundAndConstraint must contain at least 2 comparison constraints."
            )
        for c in elem.constraints:
            _validate_literal_value(c.value)
    elif isinstance(elem, ComparisonConstraint):
        _validate_literal_value(elem.value)
    elif isinstance(elem, (StringLiteral, IntegerLiteral, FloatLiteral, BooleanLiteral, NullLiteral, TemporalLiteral)):
        _validate_literal_value(elem)


def _validate_literal_value(lit: LiteralValue) -> None:
    """Literal values are inherently valid instances of LiteralValue."""
    pass


def _validate_range(rng: Range) -> None:
    """Validate range bounds compatibility and ordering.

    Supported categories:
    - Numeric (Integer / Float mixed): start <= end
    - String (String ↔ String): start <= end
    - Temporal (Temporal ↔ Temporal): valid

    Rejected:
    - Boolean and Null bounds
    - Incompatible cross-category bounds (e.g. String ↔ Integer)
    """
    start = rng.start
    end = rng.end

    # 1. Reject boolean and null bounds
    if isinstance(start, (BooleanLiteral, NullLiteral)) or isinstance(end, (BooleanLiteral, NullLiteral)):
        raise AltrQuerySemanticError(
            f"Range cannot have boolean or null bounds: '{start.kind}'..'{end.kind}'."
        )

    # 2. Numeric bounds (Integer / Float mixed)
    is_start_num = isinstance(start, (IntegerLiteral, FloatLiteral))
    is_end_num = isinstance(end, (IntegerLiteral, FloatLiteral))

    if is_start_num and is_end_num:
        if float(start.value) > float(end.value):
            raise AltrQuerySemanticError(
                f"Range start ({start.value}) must be less than or equal to end ({end.value})."
            )
        return

    # 3. String bounds
    if isinstance(start, StringLiteral) and isinstance(end, StringLiteral):
        if start.value > end.value:
            raise AltrQuerySemanticError(
                f"Range start ('{start.value}') must be less than or equal to end ('{end.value}')."
            )
        return

    # 4. Temporal bounds
    if isinstance(start, TemporalLiteral) and isinstance(end, TemporalLiteral):
        if start.value is not None and end.value is not None:
            if start.value > end.value:
                raise AltrQuerySemanticError(
                    f"Range start (@{start.value}) must be less than or equal to end (@{end.value})."
                )
        return

    # 5. Incompatible categories
    raise AltrQuerySemanticError(
        f"Incompatible range bound types: '{start.kind}' and '{end.kind}'."
    )
