"""QueryPlanner orchestrator for compiling logical AltrQL queries into source-bound physical plans."""

from __future__ import annotations

import logging
from typing import Any

from altr_stream.application.registry_service import RegistryService
from altr_stream.application.schema_service import SchemaService
from altr_stream.application.source_service import SourceService
from altr_stream.domain.errors import (
    AltrStreamError,
    MappingValidationError,
    NoActiveSourceMappingError,
    SourceNotFoundError,
)
from altr_stream.domain.mapping import MappingStatus
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
)
from altr_stream.query_engine.planning.selector import (
    SourceSelector,
    coerce_source_type,
    extract_logical_context,
)

logger = logging.getLogger(__name__)


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
        logical_model_id: str,
    ) -> FederatedQueryPlan:
        """Discover all compatible active candidates and compile a multi-source FederatedQueryPlan.

        Guarantees:
        1. Evaluates all active source mappings for the logical entity.
        2. Rejects incompatible sources with detailed diagnostic reasons.
        3. Generates distinct, lowered physical plans for every eligible source.
        4. Strips source-level LIMIT, OFFSET, and TOP truncation from physical plans so that
           all matching rows are retrieved and global pagination/sorting is performed at the merger layer.
        """
        # 1. Extract logical plan context
        context = extract_logical_context(ir, logical_model_id)

        # 2. Discover active candidate mappings for the target logical entity
        resolution_result = await self._registry_service.resolve_logical_entity(
            model_id=logical_model_id,
            entity_name=ir.entity,
        )

        if not resolution_result.candidates:
            raise NoActiveSourceMappingError(
                entity_name=ir.entity,
                model_id=logical_model_id,
            )

        # 3. Select all compatible physical candidates deterministically
        eligible_candidates, evaluations = self._selector.select_all_eligible_sources(
            context=context,
            candidates=resolution_result.candidates,
        )

        physical_plans: list[PhysicalQueryPlan] = []

        # Prepare physical IR without individual LIMIT/OFFSET truncation
        # The merger layer owns final global sorting, LIMIT, and OFFSET pagination.
        updates: dict[str, Any] = {
            "limit": None,
            "offset": None,
        }
        if ir.ranking:
            # If ranking was used without explicit sort, convert to sort clause for pushdown without count truncation
            if not ir.sort:
                direction = SortDirection.DESC if ir.ranking.direction == RankingDirection.TOP else SortDirection.ASC
                updates["sort"] = [SortClause(field=ir.ranking.field, direction=direction)]
            updates["ranking"] = None

        plan_ir = ir.model_copy(update=updates)

        # 4. Compile physical plan for each eligible datasource
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
            execution_mode="federated",
        )

    async def create_physical_plan(
        self,
        ir: AltrQueryIR,
        logical_model_id: str,
    ) -> PhysicalQueryPlan:
        """Discover candidate sources, select one deterministically, and lower to a single PhysicalQueryPlan."""
        federated_plan = await self.create_federated_plan(ir, logical_model_id)
        return federated_plan.physical_plans[0]

