"""AST and IR normalizer for AltrQL v0.3.

Performs deterministic structural canonicalization:
- Recursively normalizes logical expressions and unary negations.
- Preserves explicit grouping and binary tree structure without lossy reordering.
- Preserves FieldExpression, ValueSet, Range, and Constraint structures as-is without premature lowering.
"""

from __future__ import annotations

from altr_stream.query_engine.domain.ast import (
    AltrQueryIR,
    CreateRecord,
    Expression,
    FieldExpression,
    LogicalExpression,
    NegationExpression,
    QueryOperation,
)


def normalize_ir(ir: AltrQueryIR) -> AltrQueryIR:
    """Canonicalize an AltrQueryIR tree into its normalized structural representation.

    Guarantees:
    - Pure, deterministic transformation.
    - Idempotence: normalize_ir(normalize_ir(ir)) == normalize_ir(ir).
    - Preserves all field expressions, projections, assignments, records, sorts, rankings, and offsets.
    """
    normalized_where = _normalize_expression(ir.where) if ir.where is not None else None

    if ir.records:
        normalized_records = [
            CreateRecord(assignments=list(rec.assignments))
            for rec in ir.records
        ]
    elif ir.operation == QueryOperation.CREATE and ir.assignments:
        normalized_records = [CreateRecord(assignments=list(ir.assignments))]
    else:
        normalized_records = []

    return AltrQueryIR(
        operation=ir.operation,
        entity=ir.entity,
        projection=list(ir.projection),
        where=normalized_where,
        assignments=list(ir.assignments),
        records=normalized_records,
        sort=list(ir.sort),
        ranking=ir.ranking,
        offset=ir.offset,
    )


def _normalize_expression(expr: Expression) -> Expression:
    """Recursively normalize logical, negation, and field expressions."""
    if isinstance(expr, FieldExpression):
        return FieldExpression(
            field=expr.field,
            operator=expr.operator,
            operand=expr.operand,
        )

    if isinstance(expr, NegationExpression):
        return NegationExpression(
            operand=_normalize_expression(expr.operand),
        )

    if isinstance(expr, LogicalExpression):
        return LogicalExpression(
            operator=expr.operator,
            left=_normalize_expression(expr.left),
            right=_normalize_expression(expr.right),
        )

    return expr
