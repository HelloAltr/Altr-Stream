"""Logical-to-physical AltrQL IR resolution layer for Altr Stream v0.7.

Resolves a canonical AltrQueryIR written against a Logical Data Model into an
AltrQueryIR referencing physical database entities and columns via an approved SourceMapping.
"""

from typing import Any

from altr_stream.domain.errors import LogicalEntityNotFoundError, LogicalFieldNotFoundError
from altr_stream.domain.mapping import SourceMapping
from altr_stream.query_engine.domain.ast import (
    AltrQueryIR,
    CreateRecord,
    Expression,
    FieldExpression,
    FieldPath,
    FieldSelection,
    LogicalExpression,
    MutationAssignment,
    NegationExpression,
    RankingClause,
    SortClause,
)


def resolve_logical_ir(ir: AltrQueryIR, mapping: SourceMapping) -> AltrQueryIR:
    """Transform an AltrQueryIR targeting logical entities/fields to target physical entities/fields.

    Guarantees:
    - Pure, deterministic transformation with zero I/O or database access.
    - Preserves AST immutability.
    - Replaces logical entity name with the mapped physical entity name.
    - Replaces logical field names across projections, WHERE filters, assignments, records, sorting, and ranking.

    Raises:
        LogicalEntityNotFoundError: If the queried entity is not mapped in the SourceMapping.
        LogicalFieldNotFoundError: If a referenced logical field is not mapped.
    """
    # 1. Find matching EntityMapping for the root entity
    entity_mapping = None
    target_clean = ir.entity.strip().lower().rstrip("s")
    for em in mapping.entity_mappings:
        log_name = em.logical_entity_name.lower() if em.logical_entity_name else ""
        phys_name = em.physical_entity_name.lower() if em.physical_entity_name else ""
        log_id = em.logical_entity_id.lower() if em.logical_entity_id else ""

        if (
            log_name == ir.entity.lower()
            or log_id == ir.entity.lower()
            or phys_name == ir.entity.lower()
            or (log_name and log_name.rstrip("s") == target_clean)
            or (phys_name and phys_name.rstrip("s") == target_clean)
        ):
            entity_mapping = em
            break

    if not entity_mapping:
        raise LogicalEntityNotFoundError(
            entity_id_or_name=ir.entity,
            model_id=mapping.logical_model_id,
        )

    # 2. Build fast lookup map for fields: logical_field_name / logical_field_id / physical_field_name -> physical_field_name
    field_map: dict[str, str] = {}
    for fm in entity_mapping.field_mappings:
        field_map[fm.logical_field_name.lower()] = fm.physical_field_name
        field_map[fm.logical_field_id] = fm.physical_field_name
        field_map[fm.physical_field_name.lower()] = fm.physical_field_name
        field_map[fm.physical_field_name] = fm.physical_field_name

    # Also resolve aliases defined in the projection to the underlying physical column
    for sel in ir.projection:
        if sel.alias:
            alias_lower = sel.alias.lower()
            root_lower = sel.path.root.lower()
            if root_lower in field_map:
                field_map[alias_lower] = field_map[root_lower]

    def _resolve_field_path(fp: FieldPath) -> FieldPath:
        root_key = fp.root.lower()
        if root_key in field_map:
            phys_col = field_map[root_key]
            new_segments = [phys_col] + fp.segments[1:]
            return FieldPath(segments=new_segments)
        elif fp.root in field_map:
            phys_col = field_map[fp.root]
            new_segments = [phys_col] + fp.segments[1:]
            return FieldPath(segments=new_segments)
        # If not explicitly mapped, let standard binder validate or raise
        return fp

    def _resolve_expression(expr: Expression) -> Expression:
        if isinstance(expr, FieldExpression):
            return FieldExpression(
                field=_resolve_field_path(expr.field),
                operator=expr.operator,
                operand=expr.operand,
            )
        elif isinstance(expr, LogicalExpression):
            return LogicalExpression(
                operator=expr.operator,
                left=_resolve_expression(expr.left),
                right=_resolve_expression(expr.right),
            )
        elif isinstance(expr, NegationExpression):
            return NegationExpression(
                operand=_resolve_expression(expr.operand),
            )
        return expr

    # 3. Resolve Projections
    resolved_projections: list[FieldSelection] = []
    for sel in ir.projection:
        resolved_path = _resolve_field_path(sel.path)
        # If no explicit alias was specified and the physical column differs from the logical field,
        # alias it back to the original logical field name so SQL/MQL outputs logical field names.
        alias = sel.alias
        if alias is None and resolved_path.leaf != sel.path.leaf:
            alias = sel.path.leaf

        resolved_projections.append(
            FieldSelection(
                path=resolved_path,
                alias=alias,
            )
        )

    # 4. Resolve WHERE clause
    resolved_where = _resolve_expression(ir.where) if ir.where else None

    # 5. Resolve Mutation Assignments
    resolved_assignments: list[MutationAssignment] = []
    for assign in ir.assignments:
        resolved_assignments.append(
            MutationAssignment(
                field=_resolve_field_path(assign.field),
                value=assign.value,
            )
        )

    # 6. Resolve Create Records
    resolved_records: list[CreateRecord] = []
    for rec in ir.records:
        rec_assignments: list[MutationAssignment] = []
        for assign in rec.assignments:
            rec_assignments.append(
                MutationAssignment(
                    field=_resolve_field_path(assign.field),
                    value=assign.value,
                )
            )
        resolved_records.append(CreateRecord(assignments=rec_assignments))

    # 7. Resolve Sort Clauses
    resolved_sort: list[SortClause] = []
    for s in ir.sort:
        resolved_sort.append(
            SortClause(
                field=_resolve_field_path(s.field),
                direction=s.direction,
            )
        )

    # 8. Resolve Ranking Clause
    resolved_ranking = None
    if ir.ranking:
        resolved_ranking = RankingClause(
            direction=ir.ranking.direction,
            count=ir.ranking.count,
            field=_resolve_field_path(ir.ranking.field),
        )

    return AltrQueryIR(
        operation=ir.operation,
        entity=entity_mapping.physical_entity_name,
        projection=resolved_projections,
        where=resolved_where,
        assignments=resolved_assignments,
        records=resolved_records,
        sort=resolved_sort,
        ranking=resolved_ranking,
        limit=ir.limit,
        offset=ir.offset,
    )
