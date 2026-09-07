"""Pure, deterministic schema binder for AltrQL v0.1.

Binds a canonical AltrQueryIR AST against a SourceSchema snapshot to produce a
strongly-typed, schema-annotated BoundAltrQueryIR without side effects or database access.
"""

from __future__ import annotations

from typing import List, Optional

from altr_stream.domain.schema import EntitySchema, SourceSchema
from altr_stream.query_engine.binding.resolver import resolve_entity, resolve_field_path
from altr_stream.query_engine.binding.type_validator import (
    to_logical_category,
    validate_field_operator_and_operand,
)
from altr_stream.query_engine.domain.ast import (
    AltrQueryIR,
    Expression,
    FieldExpression,
    LogicalExpression,
)
from altr_stream.query_engine.domain.bound_ast import (
    BoundAltrQueryIR,
    BoundEntity,
    BoundExpression,
    BoundFieldExpression,
    BoundFieldPath,
    BoundFieldSelection,
    BoundLogicalExpression,
    BoundRankingClause,
    BoundSortClause,
)


def bind_altrql(ir: AltrQueryIR, schema: SourceSchema) -> BoundAltrQueryIR:
    """Bind a canonical AltrQueryIR against an in-memory SourceSchema snapshot.

    Guarantees:
    - Pure, deterministic transformation with zero I/O or database access.
    - Preserves input AltrQueryIR immutability.
    - Validates entity, projection, WHERE, SORT, and ranking field paths.
    - Enforces schema operator and operand type compatibility.

    Raises:
        UnknownEntityError: If the target entity does not exist in schema.
        UnknownFieldError: If a referenced field path cannot be resolved.
        TypeCompatibilityError: If operator or operand types conflict with field types.
    """
    # 1. Resolve Entity
    entity_schema = resolve_entity(ir.entity, schema)
    bound_entity = BoundEntity(
        name=entity_schema.name,
        namespace=entity_schema.namespace,
        entity_type=entity_schema.entity_type,
        comment=entity_schema.comment,
    )

    # 2. Resolve Projections
    bound_projections: List[BoundFieldSelection] = []
    for sel in ir.projection:
        field_schema = resolve_field_path(sel.path, entity_schema)
        bound_field = BoundFieldPath(
            path=sel.path,
            data_type=field_schema.data_type,
            logical_category=to_logical_category(field_schema.data_type),
            native_type=field_schema.native_data_type,
            nullable=field_schema.nullable,
            is_primary_key=field_schema.is_primary_key,
        )
        bound_projections.append(
            BoundFieldSelection(
                field=bound_field,
                alias=sel.alias,
            )
        )

    # 3. Resolve and Type-Validate WHERE Clause
    bound_where: Optional[BoundExpression] = None
    if ir.where is not None:
        bound_where = _bind_expression(ir.where, entity_schema)

    # 4. Resolve SORT Clauses
    bound_sort: List[BoundSortClause] = []
    for sc in ir.sort:
        field_schema = resolve_field_path(sc.field, entity_schema)
        bound_field = BoundFieldPath(
            path=sc.field,
            data_type=field_schema.data_type,
            logical_category=to_logical_category(field_schema.data_type),
            native_type=field_schema.native_data_type,
            nullable=field_schema.nullable,
            is_primary_key=field_schema.is_primary_key,
        )
        bound_sort.append(
            BoundSortClause(
                field=bound_field,
                direction=sc.direction,
            )
        )

    # 5. Resolve Ranking Clause
    bound_ranking: Optional[BoundRankingClause] = None
    if ir.ranking is not None:
        field_schema = resolve_field_path(ir.ranking.field, entity_schema)
        bound_field = BoundFieldPath(
            path=ir.ranking.field,
            data_type=field_schema.data_type,
            logical_category=to_logical_category(field_schema.data_type),
            native_type=field_schema.native_data_type,
            nullable=field_schema.nullable,
            is_primary_key=field_schema.is_primary_key,
        )
        bound_ranking = BoundRankingClause(
            direction=ir.ranking.direction,
            count=ir.ranking.count,
            field=bound_field,
        )

    # 6. Construct BoundAltrQueryIR
    return BoundAltrQueryIR(
        entity=bound_entity,
        projection=bound_projections,
        where=bound_where,
        sort=bound_sort,
        ranking=bound_ranking,
        offset=ir.offset,
        source_id=schema.source_id,
        source_name=schema.source_name,
    )


def _bind_expression(expr: Expression, entity: EntitySchema) -> BoundExpression:
    """Recursively resolve and type-validate expressions."""
    if isinstance(expr, FieldExpression):
        field_schema = resolve_field_path(expr.field, entity)
        bound_field = BoundFieldPath(
            path=expr.field,
            data_type=field_schema.data_type,
            logical_category=to_logical_category(field_schema.data_type),
            native_type=field_schema.native_data_type,
            nullable=field_schema.nullable,
            is_primary_key=field_schema.is_primary_key,
        )
        validate_field_operator_and_operand(bound_field, expr.operator, expr.operand)
        return BoundFieldExpression(
            field=bound_field,
            operator=expr.operator,
            operand=expr.operand,
        )

    if isinstance(expr, LogicalExpression):
        bound_operands = [_bind_expression(child, entity) for child in expr.operands]
        return BoundLogicalExpression(
            operator=expr.operator,
            operands=bound_operands,
        )

    raise TypeError(f"Unexpected expression type during binding: {type(expr)}")
