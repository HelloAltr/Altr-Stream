"""AST and IR normalizer for AltrQL v0.1.

Performs deterministic structural canonicalization:
- Collapses single-operand LogicalExpressions into their inner operand.
- Flattens nested same-operator AND/OR expression trees.
- Preserves FieldExpression, ValueSet, Range, and Constraint structures as-is without premature lowering.
"""

from __future__ import annotations

from typing import List

from altr_stream.query_engine.domain.ast import (
    AltrQueryIR,
    Expression,
    FieldExpression,
    LogicalExpression,
)


def normalize_ir(ir: AltrQueryIR) -> AltrQueryIR:
    """Canonicalize an AltrQueryIR tree into its normalized structural representation.

    Guarantees:
    - Pure, deterministic transformation.
    - Idempotence: normalize_ir(normalize_ir(ir)) == normalize_ir(ir).
    - Preserves all field expressions, projections, assignments, sorts, rankings, and offsets.
    """
    normalized_where = _normalize_expression(ir.where) if ir.where is not None else None

    return AltrQueryIR(
        operation=ir.operation,
        entity=ir.entity,
        projection=list(ir.projection),
        where=normalized_where,
        assignments=list(ir.assignments),
        sort=list(ir.sort),
        ranking=ir.ranking,
        offset=ir.offset,
    )


def _normalize_expression(expr: Expression) -> Expression:
    """Recursively normalize logical and field expressions."""
    if isinstance(expr, FieldExpression):
        return FieldExpression(
            field=expr.field,
            operator=expr.operator,
            operand=expr.operand,
        )

    if isinstance(expr, LogicalExpression):
        # 1. Recursively normalize all child operands
        normalized_children: List[Expression] = [
            _normalize_expression(child) for child in expr.operands
        ]

        # 2. Flatten nested same-operator expressions
        flattened: List[Expression] = []
        for child in normalized_children:
            if isinstance(child, LogicalExpression) and child.operator == expr.operator:
                flattened.extend(child.operands)
            else:
                flattened.append(child)

        # 3. Collapse single-operand logical expressions
        if len(flattened) == 1:
            return flattened[0]

        return LogicalExpression(
            operator=expr.operator,
            operands=flattened,
        )

    return expr
