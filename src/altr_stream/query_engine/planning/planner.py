"""QueryPlanner orchestrator for compiling logical AltrQL queries into source-bound physical plans."""

from __future__ import annotations

import logging
from typing import TYPE_CHECKING, Any

if TYPE_CHECKING:
    from altr_stream.application.registry_service import RegistryService
    from altr_stream.application.schema_service import SchemaService
    from altr_stream.application.source_service import SourceService
from altr_stream.domain.errors import (
    AltrStreamError,
    IncompleteFieldMappingError,
    LogicalEntityNotFoundError,
    LogicalModelNotFoundError,
    MappingValidationError,
    NoActiveSourceMappingError,
    PhysicalEntityNotFoundError,
    SourceCapabilityMismatchError,
    SourceNotFoundError,
)
from altr_stream.domain.mapping import (
    EntityMapping,
    FieldMapping,
    MappingProvenance,
    MappingStatus,
    ResolvedSourceCandidate,
    SourceMapping,
)
from altr_stream.domain.schema import StandardDataType
from altr_stream.query_engine.binding.binder import bind_altrql
from altr_stream.query_engine.binding.logical_resolver import resolve_logical_ir
from altr_stream.query_engine.classification.classifier import classify_query
from altr_stream.query_engine.domain.ast import (
    AltrQueryIR,
    RankingDirection,
    SortClause,
    SortDirection,
)
from altr_stream.query_engine.lowering import get_lowerer
from altr_stream.query_engine.planning.models import (
    CandidateEvaluation,
    FederatedQueryPlan,
    PhysicalQueryPlan,
    SourceExclusionInfo,
    SourceExclusionReason,
    SourceExecutionStatus,
)
from altr_stream.query_engine.planning.selector import (
    SourceSelector,
    coerce_source_type,
    extract_logical_context,
)

logger = logging.getLogger(__name__)


def _compute_federated_plan_ir_updates(ir: AltrQueryIR) -> dict[str, Any]:
    """Compute safe IR updates for individual physical query lowering in federated mode.

    Safety Rules:
    - If the query contains a deterministic sort (ir.sort or ir.ranking) AND an explicit limit
      (ir.limit or ir.ranking.count), push down bounded limit = (offset or 0) + limit.
    - If the query does NOT have a sort, or is offset-only (no limit), do NOT push down per-source limits.
    - Physical queries NEVER receive physical offset (offset remains None), preserving authoritative
      global offset slicing at the federated merger.
    """
    has_sort = bool(ir.sort or ir.ranking)
    has_limit = (ir.limit is not None and ir.limit >= 0) or (
        ir.ranking is not None and ir.ranking.count is not None and ir.ranking.count >= 0
    )

    updates: dict[str, Any] = {
        "offset": None,
    }

    if has_sort and has_limit:
        limit_val = ir.limit if ir.limit is not None else (ir.ranking.count if ir.ranking else 0)
        offset_val = ir.offset if ir.offset is not None and ir.offset > 0 else 0
        updates["limit"] = offset_val + limit_val
    else:
        updates["limit"] = None

    if ir.ranking:
        if not ir.sort:
            direction = (
                SortDirection.DESC
                if ir.ranking.direction == RankingDirection.TOP
                else SortDirection.ASC
            )
            updates["sort"] = [SortClause(field=ir.ranking.field, direction=direction)]
        updates["ranking"] = None

    return updates


class QueryPlanner:
    """Orchestrates source-agnostic logical query planning, candidate evaluation, and physical compilation."""

    def __init__(
        self,
        registry_service: RegistryService,
        schema_service: SchemaService,
        source_service: SourceService,
        selector: SourceSelector | None = None,
    ):
        self._registry_service = registry_service
        self._schema_service = schema_service
        self._source_service = source_service
        self._selector = selector or SourceSelector()

    async def create_federated_plan(
        self,
        ir: AltrQueryIR,
        logical_model_id: str | None = None,
    ) -> FederatedQueryPlan:
        """Discover all compatible active candidates and compile a multi-source FederatedQueryPlan.

        Execution paths:
        - Path A: If registered LogicalModel mappings exist for the entity, plan against registered mappings.
        - Path B: If entity is not in persistent LogicalModel, discover matching physical schemas (ephemeral projection).
        """
        # 1. Extract logical plan context
        context = extract_logical_context(ir, logical_model_id)

        # 2. Try Path A: Discover active candidate mappings for the target logical entity in registered models
        candidates: list[ResolvedSourceCandidate] = []
        if logical_model_id:
            try:
                resolution_result = await self._registry_service.resolve_logical_entity(
                    model_id=logical_model_id,
                    entity_name=ir.entity,
                )
                candidates = resolution_result.candidates
            except (LogicalEntityNotFoundError, LogicalModelNotFoundError, NoActiveSourceMappingError, Exception) as e:
                logger.debug("Path A resolution failed for entity '%s' in model '%s': %s", ir.entity, logical_model_id, e)
                candidates = []

        if candidates:
            # =================================================================
            # Path A: Persistent Logical Model Execution
            # =================================================================
            eligible_candidates, evaluations = self._selector.select_all_eligible_sources(
                context=context,
                candidates=candidates,
            )

            # Map rejected candidate evaluations to SourceExclusionInfo
            excluded_sources: list[SourceExclusionInfo] = []
            for ev in evaluations:
                if not ev.is_eligible:
                    reason = SourceExclusionReason.NO_ACTIVE_MAPPING.value
                    if ev.unmapped_fields:
                        reason = SourceExclusionReason.INCOMPLETE_FIELD_MAPPING.value
                    elif ev.missing_capabilities:
                        reason = SourceExclusionReason.SOURCE_CAPABILITY_MISMATCH.value

                    excluded_sources.append(
                        SourceExclusionInfo(
                            source_id=ev.source_id,
                            source_name=ev.source_name,
                            source_type=ev.source_type.value,
                            physical_entity=ev.physical_entity_name,
                            status=SourceExecutionStatus.EXCLUDED.value,
                            reason_code=reason,
                            message=ev.rejection_reason or "Source candidate is not eligible.",
                        )
                    )

            physical_plans: list[PhysicalQueryPlan] = []

            # Prepare physical IR with safe bounded pagination pushdown
            # The merger layer owns final global sorting, LIMIT, and OFFSET pagination.
            updates = _compute_federated_plan_ir_updates(ir)
            plan_ir = ir.model_copy(update=updates)

            for cand in eligible_candidates:
                mapping = await self._registry_service.get_source_mapping(cand.mapping_id)
                if mapping.status != MappingStatus.ACTIVE:
                    continue

                schema = await self._schema_service.get_latest_schema(cand.source_id)
                if not schema:
                    continue

                resolved_ir = resolve_logical_ir(plan_ir, mapping)
                bound_ir = bind_altrql(resolved_ir, schema)
                classification = classify_query(bound_ir)

                source_type_enum = coerce_source_type(cand.source_type)
                lowerer = get_lowerer(source_type_enum)
                physical_query = lowerer.lower(bound_ir)

                logical_to_physical: dict[str, str] = {}
                physical_to_logical: dict[str, str] = {}
                for fm in cand.field_mappings:
                    logical_to_physical[fm.logical_field_name] = fm.physical_field_name
                    physical_to_logical[fm.physical_field_name] = fm.logical_field_name

                plan = PhysicalQueryPlan(
                    logical_model_id=logical_model_id,
                    target_entity=ir.entity,
                    selected_source_id=cand.source_id,
                    selected_source_name=cand.source_name,
                    selected_source_type=source_type_enum,
                    selected_mapping_id=cand.mapping_id,
                    physical_entity_name=cand.physical_entity_name,
                    resolved_ir=resolved_ir,
                    bound_ir=bound_ir,
                    classification=classification,
                    physical_query=physical_query,
                    logical_to_physical_map=logical_to_physical,
                    physical_to_logical_map=physical_to_logical,
                    candidates_evaluated=evaluations,
                )
                physical_plans.append(plan)

            if not physical_plans:
                raise NoActiveSourceMappingError(
                    entity_name=ir.entity,
                    model_id=logical_model_id,
                )

            logger.info(
                "Compiled federated query plan for '%s' across %d physical sources (%s)",
                ir.entity,
                len(physical_plans),
                ", ".join(p.selected_source_id for p in physical_plans),
            )

            return FederatedQueryPlan(
                logical_model_id=logical_model_id,
                target_entity=ir.entity,
                logical_ir=ir,
                physical_plans=physical_plans,
                candidates_evaluated=evaluations,
                excluded_sources=excluded_sources,
                execution_mode="federated",
                is_ephemeral=False,
            )

        # =================================================================
        # Path B: Ephemeral Physical Entity Discovery
        # =================================================================
        matching, discovery_excluded = await self._schema_service.find_sources_with_physical_entity(ir.entity)

        if not matching:
            if discovery_excluded:
                raise PhysicalEntityNotFoundError(
                    f"Physical entity '{ir.entity}' was not found in any active physical data source."
                )
            raise NoActiveSourceMappingError(
                entity_name=ir.entity,
                model_id=logical_model_id or "",
            )

        ephemeral_proj = self._selector.synthesize_ephemeral_projection(
            context=context,
            matching_sources=matching,
            excluded_sources=discovery_excluded,
        )

        if not ephemeral_proj.participating_sources or not ephemeral_proj.canonical_fields:
            if context.projected_fields:
                raise IncompleteFieldMappingError(
                    entity_name=ir.entity,
                    unmapped_fields=context.projected_fields,
                )
            raise PhysicalEntityNotFoundError(
                f"No common fields could be synthesized across candidate sources for physical entity '{ir.entity}'."
            )

        updates = _compute_federated_plan_ir_updates(ir)
        plan_ir = ir.model_copy(update=updates)

        physical_plans = []
        evaluations = []
        participating_set = set(ephemeral_proj.participating_sources)
        sorted_matching = sorted(
            [m for m in matching if m[0].id in participating_set],
            key=lambda x: x[0].id,
        )

        for src, schema, entity in sorted_matching:
            source_type_enum = coerce_source_type(src.type)
            field_mappings: list[FieldMapping] = []
            logical_to_physical: dict[str, str] = {}
            physical_to_logical: dict[str, str] = {}

            em_id = f"ephemeral_em_{src.id}_{entity.name}"
            sm_id = f"ephemeral_sm_{src.id}_{logical_model_id or 'ephemeral'}"

            for efp in ephemeral_proj.canonical_fields:
                if src.id in efp.source_field_names:
                    phys_f_name = efp.source_field_names[src.id]
                    f_obj = entity.get_field(phys_f_name)
                    p_type = f_obj.data_type if f_obj else StandardDataType.STRING
                    try:
                        l_type = StandardDataType(efp.data_type)
                    except ValueError:
                        l_type = p_type

                    field_mappings.append(
                        FieldMapping(
                            entity_mapping_id=em_id,
                            logical_field_id=f"ephemeral_lf_{efp.name}",
                            logical_field_name=efp.name,
                            physical_field_name=phys_f_name,
                        )
                    )
                    logical_to_physical[efp.name] = phys_f_name
                    physical_to_logical[phys_f_name] = efp.name

            entity_mapping = EntityMapping(
                id=em_id,
                source_mapping_id=sm_id,
                logical_entity_id=ir.entity,
                logical_entity_name=ir.entity,
                physical_entity_name=entity.name,
                field_mappings=field_mappings,
            )
            source_mapping = SourceMapping(
                id=sm_id,
                logical_model_id=logical_model_id or "ephemeral",
                source_id=src.id,
                entity_mappings=[entity_mapping],
                status=MappingStatus.ACTIVE,
                provenance=MappingProvenance.SYSTEM,
            )

            resolved_ir = resolve_logical_ir(plan_ir, source_mapping)
            bound_ir = bind_altrql(resolved_ir, schema)
            classification = classify_query(bound_ir)
            lowerer = get_lowerer(source_type_enum)
            physical_query = lowerer.lower(bound_ir)

            ev = CandidateEvaluation(
                source_id=src.id,
                source_name=src.name,
                source_type=source_type_enum,
                mapping_id=source_mapping.id,
                physical_entity_name=entity.name,
                is_eligible=True,
                rejection_reason=None,
                unmapped_fields=[],
                missing_capabilities=[],
            )
            evaluations.append(ev)

            plan = PhysicalQueryPlan(
                logical_model_id=logical_model_id or "ephemeral",
                target_entity=ir.entity,
                selected_source_id=src.id,
                selected_source_name=src.name,
                selected_source_type=source_type_enum,
                selected_mapping_id=source_mapping.id,
                physical_entity_name=entity.name,
                resolved_ir=resolved_ir,
                bound_ir=bound_ir,
                classification=classification,
                physical_query=physical_query,
                logical_to_physical_map=logical_to_physical,
                physical_to_logical_map=physical_to_logical,
                candidates_evaluated=[ev],
            )
            physical_plans.append(plan)

        if not physical_plans:
            raise PhysicalEntityNotFoundError(
                f"No physical plans could be compiled for discovered physical entity '{ir.entity}'."
            )

        logger.info(
            "Compiled ephemeral federated query plan for '%s' across %d physical sources (%s) with %d excluded",
            ir.entity,
            len(physical_plans),
            ", ".join(p.selected_source_id for p in physical_plans),
            len(ephemeral_proj.excluded_sources),
        )

        return FederatedQueryPlan(
            logical_model_id=logical_model_id or "ephemeral",
            target_entity=ir.entity,
            logical_ir=ir,
            physical_plans=physical_plans,
            candidates_evaluated=evaluations,
            excluded_sources=ephemeral_proj.excluded_sources,
            execution_mode="federated",
            is_ephemeral=True,
            ephemeral_projection=ephemeral_proj,
        )

    async def create_physical_plan(
        self,
        ir: AltrQueryIR,
        logical_model_id: str,
    ) -> PhysicalQueryPlan:
        """Discover candidate sources, select one deterministically, and lower to a single PhysicalQueryPlan."""
        federated_plan = await self.create_federated_plan(ir, logical_model_id)
        return federated_plan.physical_plans[0]

