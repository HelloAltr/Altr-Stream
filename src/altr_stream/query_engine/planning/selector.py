"""Source selection engine for deterministic, capability-aware physical source resolution."""

from __future__ import annotations

from typing import Any

from altr_stream.domain.connector import ParameterStyle, SourceCapabilities
from altr_stream.domain.errors import (
    IncompleteFieldMappingError,
    NoActiveSourceMappingError,
    SourceCapabilityMismatchError,
)
from altr_stream.domain.mapping import ResolvedSourceCandidate
from altr_stream.domain.schema import (
    EntitySchema,
    FieldSchema,
    SourceSchema,
    are_datatypes_compatible,
)
from altr_stream.domain.source import Source, SourceType
from altr_stream.query_engine.domain.ast import (
    AltrQueryIR,
    Expression,
    FieldExpression,
    LogicalExpression,
    NegationExpression,
    QueryOperation,
)
from altr_stream.query_engine.planning.models import (
    CandidateEvaluation,
    EphemeralFieldProjection,
    EphemeralLogicalProjection,
    LogicalPlanContext,
    SourceExclusionInfo,
    SourceExclusionReason,
    SourceExecutionStatus,
)


def get_static_source_capabilities(source_type: SourceType) -> SourceCapabilities:
    """Return verified static SourceCapabilities for a given source type without database I/O."""
    if source_type == SourceType.POSTGRESQL:
        return SourceCapabilities(
            schema_discovery=True,
            read=True,
            write=True,
            cdc=False,
            batch_execution=True,
            streaming=False,
            custom_query=True,
            supports_transactions=True,
            supports_returning=True,
            supports_date_only_equality=True,
            parameter_style=ParameterStyle.POSITIONAL_NUMERIC,
            max_batch_size=1000,
            entity_types=["TABLE", "VIEW"],
            supported_operations=["SELECT", "INSERT", "UPDATE", "DELETE", "SCHEMA_DISCOVERY"],
        )
    elif source_type == SourceType.MYSQL:
        return SourceCapabilities(
            schema_discovery=True,
            read=True,
            write=True,
            cdc=False,
            batch_execution=True,
            streaming=False,
            custom_query=True,
            supports_transactions=True,
            supports_returning=False,
            supports_date_only_equality=True,
            parameter_style=ParameterStyle.POSITIONAL_FORMAT,
            max_batch_size=1000,
            entity_types=["TABLE", "VIEW"],
            supported_operations=["SELECT", "INSERT", "UPDATE", "DELETE", "SCHEMA_DISCOVERY"],
        )
    elif source_type == SourceType.SQLITE:
        return SourceCapabilities(
            schema_discovery=True,
            read=True,
            write=True,
            cdc=False,
            batch_execution=True,
            streaming=False,
            custom_query=True,
            supports_transactions=True,
            supports_returning=True,
            supports_date_only_equality=True,
            parameter_style=ParameterStyle.POSITIONAL_QMARK,
            max_batch_size=1000,
            entity_types=["TABLE", "VIEW"],
            supported_operations=["SELECT", "INSERT", "UPDATE", "DELETE", "SCHEMA_DISCOVERY"],
        )
    elif source_type == SourceType.MONGODB:
        return SourceCapabilities(
            schema_discovery=True,
            read=True,
            write=True,
            cdc=False,
            batch_execution=True,
            streaming=False,
            custom_query=True,
            supports_transactions=True,
            supports_returning=True,
            supports_date_only_equality=True,
            parameter_style=ParameterStyle.DOCUMENT_BSON,
            max_batch_size=1000,
            entity_types=["COLLECTION"],
            supported_operations=["find", "insert_many", "update_many", "delete_many", "SCHEMA_DISCOVERY"],
        )
    # Default fallback
    return SourceCapabilities(custom_query=True)


def extract_logical_context(ir: AltrQueryIR, logical_model_id: str | None = None) -> LogicalPlanContext:
    """Extract all referenced logical entities and fields from an AST into a planning context."""
    projected: list[str] = []
    alias_to_canonical: dict[str, str] = {}
    if not ir.is_wildcard_projection:
        for sel in ir.projection:
            projected.append(sel.path.root)
            if sel.alias:
                alias_to_canonical[sel.alias.lower()] = sel.path.root
    else:
        for sel in ir.projection:
            if sel.alias:
                alias_to_canonical[sel.alias.lower()] = sel.path.root

    filter_fields: list[str] = []

    def _collect_expr_fields(expr: Expression | None) -> None:
        if expr is None:
            return
        if isinstance(expr, FieldExpression):
            filter_fields.append(expr.field.root)
        elif isinstance(expr, LogicalExpression):
            _collect_expr_fields(expr.left)
            _collect_expr_fields(expr.right)
        elif isinstance(expr, NegationExpression):
            _collect_expr_fields(expr.operand)

    _collect_expr_fields(ir.where)

    mutation_fields: list[str] = []
    for a in ir.assignments:
        mutation_fields.append(a.field.root)
    for rec in ir.records:
        for a in rec.assignments:
            mutation_fields.append(a.field.root)

    sort_fields: list[str] = []
    for s in ir.sort:
        root_name = s.field.root
        sort_fields.append(alias_to_canonical.get(root_name.lower(), root_name))
    if ir.ranking:
        root_name = ir.ranking.field.root
        sort_fields.append(alias_to_canonical.get(root_name.lower(), root_name))

    return LogicalPlanContext(
        logical_model_id=logical_model_id,
        target_entity=ir.entity,
        operation=ir.operation,
        is_wildcard=ir.is_wildcard_projection,
        projected_fields=projected,
        filter_fields=filter_fields,
        mutation_fields=mutation_fields,
        sort_fields=sort_fields,
        requires_returning=ir.operation in (QueryOperation.CREATE, QueryOperation.UPDATE, QueryOperation.DELETE),
        requires_transactions=False,
    )


def coerce_source_type(val: SourceType | str) -> SourceType:
    """Coerce string or enum to SourceType enum safely."""
    if isinstance(val, SourceType):
        return val
    try:
        return SourceType(val.upper())
    except (ValueError, KeyError):
        return SourceType[val.upper()]


class SourceSelector:
    """Evaluates candidate source mappings against query requirements and applies deterministic selection."""

    def evaluate_candidates(
        self,
        context: LogicalPlanContext,
        candidates: list[ResolvedSourceCandidate],
    ) -> tuple[list[ResolvedSourceCandidate], list[CandidateEvaluation]]:
        """Evaluate and filter candidate mappings by field coverage and connector capabilities."""
        evaluations: list[CandidateEvaluation] = []
        eligible_candidates: list[ResolvedSourceCandidate] = []

        referenced_fields = {f.lower() for f in context.all_referenced_fields}

        for cand in candidates:
            mapped_fields = {fm.logical_field_name.lower() for fm in cand.field_mappings if fm.logical_field_name}
            mapped_fields.update(fm.physical_field_name.lower() for fm in cand.field_mappings if fm.physical_field_name)
            unmapped = [
                f for f in referenced_fields
                if f not in mapped_fields and f.rstrip("s") not in {mf.rstrip("s") for mf in mapped_fields}
            ]
            missing_caps: list[str] = []

            source_type_enum = coerce_source_type(cand.source_type)
            caps = get_static_source_capabilities(source_type_enum)

            # Check field coverage
            if unmapped:
                evaluations.append(
                    CandidateEvaluation(
                        source_id=cand.source_id,
                        source_name=cand.source_name,
                        source_type=source_type_enum,
                        mapping_id=cand.mapping_id,
                        physical_entity_name=cand.physical_entity_name,
                        is_eligible=False,
                        rejection_reason=f"Candidate does not map required logical field(s): {', '.join(unmapped)}",
                        unmapped_fields=unmapped,
                        missing_capabilities=[],
                    )
                )
                continue

            # Check capabilities
            if context.operation in (QueryOperation.CREATE, QueryOperation.UPDATE, QueryOperation.DELETE):
                if not caps.custom_query:
                    missing_caps.append("custom_query")

            if missing_caps:
                evaluations.append(
                    CandidateEvaluation(
                        source_id=cand.source_id,
                        source_name=cand.source_name,
                        source_type=source_type_enum,
                        mapping_id=cand.mapping_id,
                        physical_entity_name=cand.physical_entity_name,
                        is_eligible=False,
                        rejection_reason=f"Candidate lacks required capabilities: {', '.join(missing_caps)}",
                        unmapped_fields=[],
                        missing_capabilities=missing_caps,
                    )
                )
                continue

            # Candidate is eligible
            evaluations.append(
                CandidateEvaluation(
                    source_id=cand.source_id,
                    source_name=cand.source_name,
                    source_type=source_type_enum,
                    mapping_id=cand.mapping_id,
                    physical_entity_name=cand.physical_entity_name,
                    is_eligible=True,
                    rejection_reason=None,
                    unmapped_fields=[],
                    missing_capabilities=[],
                )
            )
            eligible_candidates.append(cand)

        return eligible_candidates, evaluations

    def select_all_eligible_sources(
        self,
        context: LogicalPlanContext,
        candidates: list[ResolvedSourceCandidate],
    ) -> tuple[list[ResolvedSourceCandidate], list[CandidateEvaluation]]:
        """Select all compatible physical candidate sources deterministically for federated execution.

        Raises:
            NoActiveSourceMappingError: If no candidates were provided.
            IncompleteFieldMappingError: If all candidates were rejected due to unmapped fields.
            SourceCapabilityMismatchError: If all candidates were rejected due to unsupported capabilities.
        """
        if not candidates:
            raise NoActiveSourceMappingError(
                entity_name=context.target_entity,
                model_id=context.logical_model_id,
            )

        eligible, evaluations = self.evaluate_candidates(context, candidates)

        if not eligible:
            # Diagnose rejection reason
            unmapped_all: set[str] = set()
            caps_all: set[str] = set()
            for ev in evaluations:
                unmapped_all.update(ev.unmapped_fields)
                caps_all.update(ev.missing_capabilities)

            if unmapped_all:
                raise IncompleteFieldMappingError(
                    entity_name=context.target_entity,
                    unmapped_fields=sorted(list(unmapped_all)),
                )
            elif caps_all:
                raise SourceCapabilityMismatchError(
                    entity_name=context.target_entity,
                    capability=", ".join(sorted(list(caps_all))),
                )
            else:
                raise NoActiveSourceMappingError(
                    entity_name=context.target_entity,
                    model_id=context.logical_model_id,
                )

        # Deterministic stable sort: (source_id ASC, mapping_id ASC)
        sorted_eligible = sorted(
            eligible,
            key=lambda c: (c.source_id, c.mapping_id),
        )

        return sorted_eligible, evaluations

    def select_source(
        self,
        context: LogicalPlanContext,
        candidates: list[ResolvedSourceCandidate],
    ) -> tuple[ResolvedSourceCandidate, list[CandidateEvaluation]]:
        """Select exactly one physical candidate source deterministically.

        Raises:
            NoActiveSourceMappingError: If no candidates were provided.
            IncompleteFieldMappingError: If all candidates were rejected due to unmapped fields.
            SourceCapabilityMismatchError: If all candidates were rejected due to unsupported capabilities.
        """
        sorted_eligible, evaluations = self.select_all_eligible_sources(context, candidates)
        return sorted_eligible[0], evaluations

    def synthesize_ephemeral_projection(
        self,
        context: LogicalPlanContext,
        matching_sources: list[tuple[Source, SourceSchema, EntitySchema]],
        excluded_sources: list[SourceExclusionInfo] | None = None,
    ) -> EphemeralLogicalProjection:
        """Synthesize a conservative in-memory logical projection from discovered physical entities.

        Rules:
        1. MongoDB '_id' is excluded from unmapped discovery unless explicitly requested.
        2. In wildcard mode (GET entity;), compute the common-field intersection across all matching sources.
        3. Verify datatype compatibility for each common field.
        4. In explicit-field mode (GET entity { a, b };), verify each matching source has all requested fields.
           Sources missing requested fields are recorded as EXCLUDED with reason INCOMPLETE_FIELD_MAPPING.
        5. Returns an EphemeralLogicalProjection containing canonical fields and participation partitioning.
        """
        all_excluded: list[SourceExclusionInfo] = list(excluded_sources or [])
        if not matching_sources:
            return EphemeralLogicalProjection(
                entity_name=context.target_entity,
                canonical_fields=[],
                participating_sources=[],
                excluded_sources=all_excluded,
                is_ephemeral=True,
            )

        # Build field map per source (excluding internal _id for MongoDB)
        source_field_maps: dict[str, dict[str, FieldSchema]] = {}
        for src, schema, entity in matching_sources:
            f_map: dict[str, FieldSchema] = {}
            for f in entity.fields:
                if f.name == "_id" and src.type == SourceType.MONGODB:
                    continue
                f_map[f.name.lower()] = f
            source_field_maps[src.id] = f_map

        participating_sources: list[str] = []
        canonical_fields: list[EphemeralFieldProjection] = []

        if context.is_wildcard:
            # 1. Wildcard mode: Compute intersection of field names across all matching sources
            # Deterministic field order from the first source
            first_src, _, first_entity = matching_sources[0]
            first_fields = [f for f in first_entity.fields if not (f.name == "_id" and first_src.type == SourceType.MONGODB)]

            # Intersection set of lowercase names
            common_lower = set(source_field_maps[first_src.id].keys())
            for src, _, _ in matching_sources[1:]:
                common_lower = common_lower.intersection(source_field_maps[src.id].keys())

            for f in first_fields:
                f_lower = f.name.lower()
                if f_lower not in common_lower:
                    continue

                # Check datatype compatibility across all sources
                base_type = f.data_type
                is_compat = True
                src_field_names: dict[str, str] = {}

                for src, _, _ in matching_sources:
                    src_f = source_field_maps[src.id][f_lower]
                    src_field_names[src.id] = src_f.name
                    if not are_datatypes_compatible(base_type, src_f.data_type):
                        is_compat = False
                        break

                if not is_compat:
                    # Incompatible datatypes across sources for this field -> omit from canonical projection
                    continue

                canonical_fields.append(
                    EphemeralFieldProjection(
                        name=f.name,
                        data_type=base_type.value if hasattr(base_type, "value") else str(base_type),
                        is_primary_key=f.is_primary_key,
                        source_field_names=src_field_names,
                    )
                )

            participating_sources = [src.id for src, _, _ in matching_sources]

        else:
            # 2. Explicit field selection mode (e.g. GET users { id, name, department };)
            # Check if each matching source satisfies all referenced logical fields
            referenced = list(context.projected_fields) if context.projected_fields else list(context.all_referenced_fields)

            for src, schema, entity in matching_sources:
                src_f_map = source_field_maps[src.id]
                missing_fields = [
                    ref_f for ref_f in referenced
                    if ref_f.lower() not in src_f_map
                ]
                src_type_str = src.type.value if hasattr(src.type, "value") else str(src.type)
                if missing_fields:
                    all_excluded.append(
                        SourceExclusionInfo(
                            source_id=src.id,
                            source_name=src.name,
                            source_type=src_type_str,
                            physical_entity=entity.name,
                            status=SourceExecutionStatus.EXCLUDED.value,
                            reason_code=SourceExclusionReason.INCOMPLETE_FIELD_MAPPING.value,
                            message=f"Physical entity '{entity.name}' in source '{src.name}' does not contain requested field(s): {', '.join(missing_fields)}.",
                        )
                    )
                else:
                    participating_sources.append(src.id)

            if participating_sources:
                # Build canonical fields for participating sources
                for ref_f in referenced:
                    ref_lower = ref_f.lower()
                    src_field_names: dict[str, str] = {}
                    base_type = None
                    is_pk = False

                    for src_id in participating_sources:
                        src_f = source_field_maps[src_id][ref_lower]
                        src_field_names[src_id] = src_f.name
                        if base_type is None:
                            base_type = src_f.data_type
                            is_pk = src_f.is_primary_key

                    canonical_fields.append(
                        EphemeralFieldProjection(
                            name=ref_f,
                            data_type=base_type.value if (base_type and hasattr(base_type, "value")) else "STRING",
                            is_primary_key=is_pk,
                            source_field_names=src_field_names,
                        )
                    )

        return EphemeralLogicalProjection(
            entity_name=context.target_entity,
            canonical_fields=canonical_fields,
            participating_sources=participating_sources,
            excluded_sources=all_excluded,
            is_ephemeral=True,
        )


def synthesize_ephemeral_projection(
    context: LogicalPlanContext,
    matching_sources: list[tuple[Source, SourceSchema, EntitySchema]],
    excluded_sources: list[SourceExclusionInfo] | None = None,
) -> EphemeralLogicalProjection:
    """Convenience helper to synthesize an EphemeralLogicalProjection."""
    return SourceSelector().synthesize_ephemeral_projection(
        context=context,
        matching_sources=matching_sources,
        excluded_sources=excluded_sources,
    )


