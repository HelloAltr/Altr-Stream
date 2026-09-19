"""AltrQL language REST API endpoints."""

import time
from typing import Any
from fastapi import APIRouter, Depends, Response, status

from altr_stream.application.query_service import QueryService
from altr_stream.application.registry_service import RegistryService
from altr_stream.application.schema_service import SchemaService
from altr_stream.application.source_service import SourceService
from altr_stream.domain.errors import (
    AltrStreamError,
    MappingValidationError,
    MissingPlanningContextError,
    NoActiveSourceMappingError,
    SourceNotFoundError,
)
from altr_stream.domain.mapping import EntityMapping, MappingStatus, SourceMapping
from altr_stream.domain.query import QueryResult
from altr_stream.presentation.api.dependencies import (
    get_query_planner,
    get_query_service,
    get_registry_service,
    get_schema_service,
    get_source_service,
)
from altr_stream.presentation.api.dtos import (
    AltrQLBindRequestDTO,
    AltrQLBindResponseDTO,
    AltrQLErrorDetailDTO,
    AltrQLExecuteRequestDTO,
    AltrQLExecuteResponseDTO,
    AltrQLParseRequestDTO,
    AltrQLParseResponseDTO,
    AltrQLPlanResponseDTO,
    MutationClassificationDTO,
    PhysicalPlanItemDTO,
    PhysicalQueryBatchDTO,
    PhysicalQueryDTO,
    QueryMetadataDTO,
    SourceExecutionInfoDTO,
)
from altr_stream.query_engine.binding import bind_altrql
from altr_stream.query_engine.binding.logical_resolver import resolve_logical_ir
from altr_stream.query_engine.classification import classify_query
from altr_stream.query_engine.domain.ast import QueryOperation
from altr_stream.query_engine.domain.errors import AltrQueryError
from altr_stream.query_engine.domain.physical_query import (
    PhysicalQuery,
    PhysicalQueryBatch,
    PhysicalQueryResult,
)
from altr_stream.query_engine.lowering import get_lowerer
from altr_stream.query_engine.parser import parse_altrql
from altr_stream.query_engine.planning import (
    QueryPlanner,
    merge_federated_results,
    normalize_row,
)


router = APIRouter(prefix="/altrql", tags=["AltrQL"])


def _to_physical_query_dto(
    physical_query: PhysicalQueryResult | None,
) -> PhysicalQueryDTO | PhysicalQueryBatchDTO | None:
    """Helper to convert a PhysicalQueryResult domain object into its corresponding DTO."""
    if physical_query is None:
        return None
    if isinstance(physical_query, PhysicalQueryBatch):
        return PhysicalQueryBatchDTO(
            dialect=physical_query.dialect,
            queries=[
                PhysicalQueryDTO(
                    dialect=q.dialect,
                    query=q.query,
                    parameters=q.parameters,
                    source_id=q.source_id,
                    source_name=q.source_name,
                )
                for q in physical_query.queries
            ],
            source_id=physical_query.source_id,
            source_name=physical_query.source_name,
        )
    return PhysicalQueryDTO(
        dialect=physical_query.dialect,
        query=physical_query.query,
        parameters=physical_query.parameters,
        source_id=physical_query.source_id,
        source_name=physical_query.source_name,
    )


def _find_matching_entity_mapping(
    mapping: SourceMapping,
    entity_name: str,
) -> EntityMapping | None:
    """Find matching EntityMapping in a SourceMapping by logical or physical entity name."""
    target = entity_name.strip().lower()
    target_clean = target.rstrip("s")

    for em in mapping.entity_mappings:
        log_name = em.logical_entity_name.lower() if em.logical_entity_name else ""
        phys_name = em.physical_entity_name.lower() if em.physical_entity_name else ""
        log_id = em.logical_entity_id.lower() if em.logical_entity_id else ""

        if (
            log_name == target
            or log_id == target
            or phys_name == target
            or (log_name and log_name.rstrip("s") == target_clean)
            or (phys_name and phys_name.rstrip("s") == target_clean)
        ):
            return em
    return None


async def _find_active_source_and_entity_mapping(
    registry_service: RegistryService,
    source_id: str,
    entity_name: str,
    mapping_id: str | None = None,
    logical_model_id: str | None = None,
) -> tuple[SourceMapping | None, EntityMapping | None]:
    """Find active SourceMapping and matching EntityMapping for explicit-source execution."""
    if mapping_id:
        mapping = await registry_service.get_source_mapping(mapping_id)
        if mapping.status != MappingStatus.ACTIVE:
            raise MappingValidationError(
                f"Cannot resolve query with mapping '{mapping_id}' in '{mapping.status.value}' status. Only ACTIVE mappings can be used for execution."
            )
        matching_em = _find_matching_entity_mapping(mapping, entity_name)
        return mapping, matching_em

    if logical_model_id:
        mappings = await registry_service.list_source_mappings(
            logical_model_id=logical_model_id, source_id=source_id
        )
        active_mappings = [m for m in mappings if m.status == MappingStatus.ACTIVE]
        if not active_mappings:
            raise MappingValidationError(
                f"No ACTIVE mapping found for logical model '{logical_model_id}' and source '{source_id}'."
            )
        if len(active_mappings) > 1:
            raise MappingValidationError(
                f"Ambiguous active mappings for logical model '{logical_model_id}' and source '{source_id}'."
            )
        for m in active_mappings:
            matching_em = _find_matching_entity_mapping(m, entity_name)
            if matching_em:
                return m, matching_em
        em = active_mappings[0].entity_mappings[0] if active_mappings[0].entity_mappings else None
        return active_mappings[0], em

    # When only source_id is given (and normalize is enabled)
    all_mappings = await registry_service.list_source_mappings(source_id=source_id)
    active_mappings = [m for m in all_mappings if m.status == MappingStatus.ACTIVE]
    for m in active_mappings:
        matching_em = _find_matching_entity_mapping(m, entity_name)
        if matching_em:
            return m, matching_em
    if active_mappings:
        em = active_mappings[0].entity_mappings[0] if active_mappings[0].entity_mappings else None
        return active_mappings[0], em
    return None, None


def _normalize_result_rows(
    columns: list[str],
    rows: list[dict[str, Any]],
    physical_to_logical: dict[str, str],
    logical_field_order: list[str] | None = None,
    is_wildcard_projection: bool = True,
    requested_logical_projections: list[str] | None = None,
) -> tuple[list[str], list[dict[str, Any]]]:
    """Translate physical column names and row dicts back to canonical logical field names.

    Omits internal connector-specific primary keys (like MongoDB's '_id') and
    physical-only unmapped fields in logical mode.
    """
    if not physical_to_logical:
        return columns, rows

    norm_rows: list[dict[str, Any]] = []
    for r in rows:
        norm_r = normalize_row(r, physical_to_logical, preserve_unmapped=False)
        norm_rows.append(norm_r)

    if not is_wildcard_projection and requested_logical_projections:
        norm_columns = requested_logical_projections
    elif logical_field_order:
        # Preserve logical schema/mapping order for mapped fields
        norm_columns = [
            f for f in logical_field_order
            if f in physical_to_logical.values() or any(f in r for r in norm_rows)
        ]
        if not norm_columns:
            norm_columns = [f for f in logical_field_order if f in physical_to_logical.values()]
    else:
        # Fallback: map physical columns to logical, excluding unmapped (like _id)
        seen: set[str] = set()
        norm_columns = []
        for c in columns:
            if c in physical_to_logical:
                log_name = physical_to_logical[c]
                if log_name not in seen:
                    seen.add(log_name)
                    norm_columns.append(log_name)

    return norm_columns, norm_rows


async def _resolve_logical_model_id(
    registry_service: RegistryService,
    entity_name: str,
    explicit_model_id: str | None = None,
) -> str:
    """Resolve logical model ID from explicit input or auto-discover from registry."""
    if explicit_model_id:
        try:
            model = await registry_service.get_model(explicit_model_id)
            return model.id
        except Exception:
            return explicit_model_id

    models = await registry_service.list_models()
    if not models:
        raise NoActiveSourceMappingError(
            entity_name=entity_name,
            model_id="",
        )

    if len(models) == 1:
        return models[0].id

    # Find models containing the target entity
    matching_models = []
    target = entity_name.strip().lower()
    target_clean = target.rstrip("s")

    for m in models:
        ent = m.get_entity_by_name(entity_name) or m.get_entity_by_id(entity_name)
        if ent:
            matching_models.append(m)
            continue
        # Also check active source mappings under this model
        mappings = await registry_service.list_source_mappings(logical_model_id=m.id)
        active_mappings = [sm for sm in mappings if sm.status == MappingStatus.ACTIVE]
        found = False
        for sm in active_mappings:
            for em in sm.entity_mappings:
                log_name = em.logical_entity_name.lower() if em.logical_entity_name else ""
                phys_name = em.physical_entity_name.lower() if em.physical_entity_name else ""
                log_id = em.logical_entity_id.lower() if em.logical_entity_id else ""
                if (
                    log_name == target
                    or log_id == target
                    or phys_name == target
                    or (log_name and log_name.rstrip("s") == target_clean)
                    or (phys_name and phys_name.rstrip("s") == target_clean)
                ):
                    matching_models.append(m)
                    found = True
                    break
            if found:
                break

    if len(matching_models) == 1:
        return matching_models[0].id

    if matching_models:
        raise MissingPlanningContextError(
            f"Entity '{entity_name}' is defined in multiple logical models ({', '.join(m.name for m in matching_models)}). Please specify 'logical_model_id'."
        )

    raise NoActiveSourceMappingError(
        entity_name=entity_name,
        model_id="",
    )


@router.post("/parse", response_model=AltrQLParseResponseDTO, status_code=status.HTTP_200_OK)
async def parse_altrql_query(
    dto: AltrQLParseRequestDTO,
) -> AltrQLParseResponseDTO:
    """Parse an AltrQL query text into a canonical Intermediate Representation (AltrQueryIR).

    This endpoint operates purely in-memory as a language parser and semantic validator
    without connecting to databases, generating physical SQL, or executing queries.
    """
    try:
        ir = parse_altrql(dto.query)
        return AltrQLParseResponseDTO(
            success=True,
            ir=ir.to_dict(),
            error=None,
        )
    except AltrQueryError as e:
        return AltrQLParseResponseDTO(
            success=False,
            ir=None,
            error=AltrQLErrorDetailDTO(
                type=e.__class__.__name__,
                message=e.message,
                line=e.line,
                column=e.column,
            ),
        )


@router.post("/bind", response_model=AltrQLBindResponseDTO, status_code=status.HTTP_200_OK)
async def bind_altrql_query(
    dto: AltrQLBindRequestDTO,
    response: Response,
    schema_service: SchemaService = Depends(get_schema_service),
    registry_service: RegistryService = Depends(get_registry_service),
    query_planner: QueryPlanner = Depends(get_query_planner),
) -> AltrQLBindResponseDTO:
    """Bind a parsed AltrQL query against a physical datasource or logical model.

    Supports both explicit source binding and source-agnostic federated logical planning.
    """
    # 1. Parse and validate canonical IR
    try:
        ir = parse_altrql(dto.query)
    except AltrQueryError as e:
        return AltrQLBindResponseDTO(
            success=False,
            ir=None,
            bound_ir=None,
            classification=None,
            error=AltrQLErrorDetailDTO(
                type=e.__class__.__name__,
                message=e.message,
                line=e.line,
                column=e.column,
            ),
        )

    # 2. Source-Agnostic / Auto-Select Planning Path (when source_id is omitted)
    if not dto.source_id:
        try:
            model_id = await _resolve_logical_model_id(
                registry_service, ir.entity, dto.logical_model_id
            )
            federated_plan = await query_planner.create_federated_plan(ir, model_id)
            response.headers["X-Altr-Execution-Mode"] = "federated"
            response.headers["X-Altr-Federated-Sources"] = ",".join(federated_plan.accepted_sources)

            first_plan = federated_plan.physical_plans[0]
            classification_dto = MutationClassificationDTO(
                operation=first_plan.classification.operation.value,
                mutation_scope=first_plan.classification.mutation_scope.value,
                requires_confirmation=first_plan.classification.requires_confirmation,
                entity=first_plan.classification.entity,
                description=first_plan.classification.description,
            )
            return AltrQLBindResponseDTO(
                success=True,
                ir=ir.to_dict(),
                bound_ir=first_plan.bound_ir.to_dict(),
                classification=classification_dto,
                execution_mode="federated",
                selected_source_id=first_plan.selected_source_id,
                selected_mapping_id=first_plan.selected_mapping_id,
                error=None,
            )
        except AltrStreamError as e:
            return AltrQLBindResponseDTO(
                success=False,
                ir=ir.to_dict(),
                bound_ir=None,
                classification=None,
                error=AltrQLErrorDetailDTO(
                    type=e.__class__.__name__,
                    message=e.message,
                ),
            )
        except AltrQueryError as e:
            return AltrQLBindResponseDTO(
                success=False,
                ir=ir.to_dict(),
                bound_ir=None,
                classification=None,
                error=AltrQLErrorDetailDTO(
                    type=e.__class__.__name__,
                    message=e.message,
                    line=e.line,
                    column=e.column,
                ),
            )

    # 3. Explicit Source Binding Path
    mapping = None
    if dto.mapping_id or dto.logical_model_id or dto.normalize:
        try:
            mapping, _ = await _find_active_source_and_entity_mapping(
                registry_service=registry_service,
                source_id=dto.source_id,  # type: ignore[arg-type]
                entity_name=ir.entity,
                mapping_id=dto.mapping_id,
                logical_model_id=dto.logical_model_id,
            )

            if mapping:
                ir = resolve_logical_ir(ir, mapping)
        except AltrStreamError as e:
            return AltrQLBindResponseDTO(
                success=False,
                ir=ir.to_dict(),
                bound_ir=None,
                classification=None,
                error=AltrQLErrorDetailDTO(
                    type=e.__class__.__name__,
                    message=e.message,
                    line=1,
                    column=1,
                ),
            )

    try:
        schema = await schema_service.get_latest_schema(dto.source_id)  # type: ignore[arg-type]
    except SourceNotFoundError:
        return AltrQLBindResponseDTO(
            success=False,
            ir=ir.to_dict(),
            bound_ir=None,
            classification=None,
            error=AltrQLErrorDetailDTO(
                type="SourceNotFoundError",
                message=f"Source with id '{dto.source_id}' was not found.",
            ),
        )

    if not schema:
        return AltrQLBindResponseDTO(
            success=False,
            ir=ir.to_dict(),
            bound_ir=None,
            classification=None,
            error=AltrQLErrorDetailDTO(
                type="SchemaNotFoundError",
                message=f"No schema snapshot discovered yet for source '{dto.source_id}'. Run schema discovery first.",
            ),
        )

    try:
        bound_ir = bind_altrql(ir, schema)
        classification = classify_query(bound_ir)
        classification_dto = MutationClassificationDTO(
            operation=classification.operation.value,
            mutation_scope=classification.mutation_scope.value,
            requires_confirmation=classification.requires_confirmation,
            entity=classification.entity,
            description=classification.description,
        )
        return AltrQLBindResponseDTO(
            success=True,
            ir=ir.to_dict(),
            bound_ir=bound_ir.to_dict(),
            classification=classification_dto,
            execution_mode="single",
            selected_source_id=dto.source_id,
            selected_mapping_id=dto.mapping_id,
            error=None,
        )
    except AltrQueryError as e:
        return AltrQLBindResponseDTO(
            success=False,
            ir=ir.to_dict(),
            bound_ir=None,
            classification=None,
            error=AltrQLErrorDetailDTO(
                type=e.__class__.__name__,
                message=e.message,
                line=e.line,
                column=e.column,
            ),
        )


@router.post("/plan", response_model=AltrQLPlanResponseDTO, status_code=status.HTTP_200_OK)
async def plan_altrql_query(
    dto: AltrQLBindRequestDTO,
    response: Response,
    query_planner: QueryPlanner = Depends(get_query_planner),
    schema_service: SchemaService = Depends(get_schema_service),
    registry_service: RegistryService = Depends(get_registry_service),
    source_service: SourceService = Depends(get_source_service),
) -> AltrQLPlanResponseDTO:
    """Dry-run plan inspection endpoint for source-agnostic federated or explicit queries."""
    try:
        ir = parse_altrql(dto.query)
    except AltrQueryError as e:
        return AltrQLPlanResponseDTO(
            success=False,
            error=AltrQLErrorDetailDTO(
                type=e.__class__.__name__,
                message=e.message,
                line=e.line,
                column=e.column,
            ),
        )

    # 1. Source-Agnostic / Auto-Select Federated Planning Path (source_id omitted)
    if not dto.source_id:
        try:
            model_id = await _resolve_logical_model_id(
                registry_service, ir.entity, dto.logical_model_id
            )
            federated_plan = await query_planner.create_federated_plan(ir, model_id)
            response.headers["X-Altr-Execution-Mode"] = "federated"
            response.headers["X-Altr-Federated-Sources"] = ",".join(federated_plan.accepted_sources)

            physical_plan_dtos = [
                PhysicalPlanItemDTO(
                    source_id=p.selected_source_id,
                    source_name=p.selected_source_name,
                    source_type=p.selected_source_type.value,
                    mapping_id=p.selected_mapping_id,
                    physical_entity=p.physical_entity_name,
                    physical_query=_to_physical_query_dto(p.physical_query),
                    bound_ir=p.bound_ir.to_dict(),
                )
                for p in federated_plan.physical_plans
            ]

            first_plan = federated_plan.physical_plans[0]
            classification_dto = MutationClassificationDTO(
                operation=first_plan.classification.operation.value,
                mutation_scope=first_plan.classification.mutation_scope.value,
                requires_confirmation=first_plan.classification.requires_confirmation,
                entity=first_plan.classification.entity,
                description=first_plan.classification.description,
            )

            return AltrQLPlanResponseDTO(
                success=True,
                logical_model_id=model_id,
                target_entity=ir.entity,
                execution_mode="federated",
                selected_source_id=first_plan.selected_source_id,
                selected_source_name=first_plan.selected_source_name,
                selected_source_type=first_plan.selected_source_type.value,
                selected_mapping_id=first_plan.selected_mapping_id,
                physical_entity=first_plan.physical_entity_name,
                ir=ir.to_dict(),
                bound_ir=first_plan.bound_ir.to_dict(),
                classification=classification_dto,
                physical_query=_to_physical_query_dto(first_plan.physical_query),
                physical_plans=physical_plan_dtos,
                total_sources_planned=len(physical_plan_dtos),
                candidates_evaluated=[ev.to_dict() for ev in federated_plan.candidates_evaluated],
                error=None,
            )
        except AltrStreamError as e:
            return AltrQLPlanResponseDTO(
                success=False,
                error=AltrQLErrorDetailDTO(
                    type=e.__class__.__name__,
                    message=e.message,
                ),
            )
        except AltrQueryError as e:
            return AltrQLPlanResponseDTO(
                success=False,
                error=AltrQLErrorDetailDTO(
                    type=e.__class__.__name__,
                    message=e.message,
                    line=e.line,
                    column=e.column,
                ),
            )

    # 2. Explicit-Source Plan Compilation
    try:
        source = await source_service.get_source(dto.source_id)  # type: ignore[arg-type]
        schema = await schema_service.get_latest_schema(dto.source_id)  # type: ignore[arg-type]
        if not schema:
            raise MappingValidationError(f"No schema snapshot discovered yet for source '{dto.source_id}'.")

        mapping = None
        if dto.mapping_id or dto.logical_model_id or dto.normalize:
            mapping, _ = await _find_active_source_and_entity_mapping(
                registry_service=registry_service,
                source_id=dto.source_id,  # type: ignore[arg-type]
                entity_name=ir.entity,
                mapping_id=dto.mapping_id,
                logical_model_id=dto.logical_model_id,
            )

        resolved_ir = resolve_logical_ir(ir, mapping) if mapping else ir
        bound_ir = bind_altrql(resolved_ir, schema)
        classification = classify_query(bound_ir)
        lowerer = get_lowerer(source.type)
        physical_query = lowerer.lower(bound_ir)

        classification_dto = MutationClassificationDTO(
            operation=classification.operation.value,
            mutation_scope=classification.mutation_scope.value,
            requires_confirmation=classification.requires_confirmation,
            entity=classification.entity,
            description=classification.description,
        )
        return AltrQLPlanResponseDTO(
            success=True,
            logical_model_id=dto.logical_model_id,
            target_entity=ir.entity,
            execution_mode="single",
            selected_source_id=source.id,
            selected_source_name=source.name,
            selected_source_type=source.type.value,
            selected_mapping_id=dto.mapping_id,
            physical_entity=bound_ir.entity.name,
            ir=ir.to_dict(),
            bound_ir=bound_ir.to_dict(),
            classification=classification_dto,
            physical_query=_to_physical_query_dto(physical_query),
            physical_plans=[],
            total_sources_planned=1,
            candidates_evaluated=[],
            error=None,
        )
    except Exception as e:
        return AltrQLPlanResponseDTO(
            success=False,
            error=AltrQLErrorDetailDTO(
                type=e.__class__.__name__,
                message=str(e),
            ),
        )


@router.post("/execute", response_model=AltrQLExecuteResponseDTO, status_code=status.HTTP_200_OK)
async def execute_altrql_query(
    dto: AltrQLExecuteRequestDTO,
    response: Response,
    source_service: SourceService = Depends(get_source_service),
    schema_service: SchemaService = Depends(get_schema_service),
    query_service: QueryService = Depends(get_query_service),
    registry_service: RegistryService = Depends(get_registry_service),
    query_planner: QueryPlanner = Depends(get_query_planner),
) -> AltrQLExecuteResponseDTO:
    """Execute an AltrQL query against a registered data source or logical model."""
    # 1. Parse canonical IR
    try:
        ir = parse_altrql(dto.query)
    except AltrQueryError as e:
        return AltrQLExecuteResponseDTO(
            success=False,
            ir=None,
            bound_ir=None,
            classification=None,
            physical_query=None,
            error=AltrQLErrorDetailDTO(
                type=e.__class__.__name__,
                message=e.message,
                line=e.line,
                column=e.column,
            ),
        )

    # =========================================================================
    # Path B: Auto-Select / Federated Execution Path (source_id is omitted)
    # =========================================================================
    if not dto.source_id:
        # Check for unsupported mutations in federated mode (Correction 6)
        if ir.operation in (QueryOperation.CREATE, QueryOperation.UPDATE, QueryOperation.DELETE):
            return AltrQLExecuteResponseDTO(
                success=False,
                ir=ir.to_dict(),
                bound_ir=None,
                classification=None,
                physical_query=None,
                error=AltrQLErrorDetailDTO(
                    type="QueryExecutionError",
                    message=f"Federated Auto-Select execution does not support {ir.operation.value} mutations across multiple sources in v0.9. Please select an explicit physical source.",
                ),
            )

        try:
            model_id = await _resolve_logical_model_id(
                registry_service, ir.entity, dto.logical_model_id
            )
            federated_plan = await query_planner.create_federated_plan(ir, model_id)
        except AltrStreamError as e:
            return AltrQLExecuteResponseDTO(
                success=False,
                ir=ir.to_dict(),
                bound_ir=None,
                classification=None,
                physical_query=None,
                error=AltrQLErrorDetailDTO(
                    type=e.__class__.__name__,
                    message=e.message,
                ),
            )
        except AltrQueryError as e:
            return AltrQLExecuteResponseDTO(
                success=False,
                ir=ir.to_dict(),
                bound_ir=None,
                classification=None,
                physical_query=None,
                error=AltrQLErrorDetailDTO(
                    type=e.__class__.__name__,
                    message=e.message,
                    line=e.line,
                    column=e.column,
                ),
            )

        # Inject observability headers
        response.headers["X-Altr-Execution-Mode"] = "federated"
        response.headers["X-Altr-Federated-Sources"] = ",".join(federated_plan.accepted_sources)

        # Execute physical plans across all federated sources
        start_time = time.perf_counter()
        execution_results: list[tuple[Any, QueryResult]] = []
        physical_query_dtos = []
        sources_executed = []

        try:
            for plan in federated_plan.physical_plans:
                if isinstance(plan.physical_query, PhysicalQueryBatch):
                    result = await query_service.execute_batch(
                        source_id=plan.selected_source_id,
                        queries=[(q.query, q.parameters) for q in plan.physical_query.queries],
                    )
                else:
                    result = await query_service.execute_query(
                        source_id=plan.selected_source_id,
                        query=plan.physical_query.query,
                        parameters=plan.physical_query.parameters,
                    )

                execution_results.append((plan, result))
                physical_query_dtos.append(_to_physical_query_dto(plan.physical_query))
                sources_executed.append(plan.selected_source_id)

            # Normalize per-source and perform global sort, global limit, and global offset merging
            norm_cols, merged_rows = merge_federated_results(
                ir=ir,
                federated_plan=federated_plan,
                execution_results=execution_results,
            )

            elapsed_ms = round((time.perf_counter() - start_time) * 1000, 2)
            first_plan = federated_plan.physical_plans[0]

            classification_dto = MutationClassificationDTO(
                operation=first_plan.classification.operation.value,
                mutation_scope=first_plan.classification.mutation_scope.value,
                requires_confirmation=first_plan.classification.requires_confirmation,
                entity=first_plan.classification.entity,
                description=first_plan.classification.description,
            )

            per_source_info: list[SourceExecutionInfoDTO] = []
            for plan, res_item in execution_results:
                per_source_info.append(
                    SourceExecutionInfoDTO(
                        source_id=plan.selected_source_id,
                        source_name=plan.selected_source_name,
                        source_type=plan.selected_source_type.value if hasattr(plan.selected_source_type, "value") else str(plan.selected_source_type),
                        status="success",
                        rows=len(res_item.rows),
                        execution_time_ms=res_item.execution_time_ms,
                    )
                )

            return AltrQLExecuteResponseDTO(
                success=True,
                ir=ir.to_dict(),
                bound_ir=first_plan.bound_ir.to_dict(),
                classification=classification_dto,
                physical_query=physical_query_dtos[0] if physical_query_dtos else None,
                physical_queries=physical_query_dtos,
                columns=norm_cols,
                rows=merged_rows,
                execution_mode="federated",
                sources_executed=sources_executed,
                metadata=QueryMetadataDTO(
                    row_count=len(merged_rows),
                    affected_rows=None,
                    execution_time_ms=elapsed_ms,
                    message=f"Federated query executed successfully across {len(sources_executed)} sources.",
                    operation=QueryOperation.READ.value,
                    mutation_scope="NOT_APPLICABLE",
                    execution_mode="federated",
                    normalized=True,
                    source_count=len(sources_executed),
                    sources=per_source_info,
                ),
                error=None,
            )
        except Exception as e:
            return AltrQLExecuteResponseDTO(
                success=False,
                ir=ir.to_dict(),
                bound_ir=federated_plan.physical_plans[0].bound_ir.to_dict() if federated_plan.physical_plans else None,
                classification=None,
                physical_query=physical_query_dtos[0] if physical_query_dtos else None,
                physical_queries=physical_query_dtos,
                execution_mode="federated",
                sources_executed=sources_executed,
                columns=[],
                rows=[],
                metadata=None,
                error=AltrQLErrorDetailDTO(
                    type=e.__class__.__name__,
                    message=str(e),
                ),
            )

    # =========================================================================
    # Path A: Explicit-Source Execution Path (single source)
    # =========================================================================
    mapping: SourceMapping | None = None
    matching_em: EntityMapping | None = None

    # Track original logical projection fields if explicitly requested
    original_logical_projections = [
        sel.alias or sel.path.leaf for sel in ir.projection
    ] if not ir.is_wildcard_projection else None
    original_is_wildcard = ir.is_wildcard_projection

    if dto.mapping_id or dto.logical_model_id or dto.normalize:
        try:
            mapping, matching_em = await _find_active_source_and_entity_mapping(
                registry_service=registry_service,
                source_id=dto.source_id,  # type: ignore[arg-type]
                entity_name=ir.entity,
                mapping_id=dto.mapping_id,
                logical_model_id=dto.logical_model_id,
            )

            if mapping:
                ir = resolve_logical_ir(ir, mapping)
        except AltrStreamError as e:
            return AltrQLExecuteResponseDTO(
                success=False,
                ir=ir.to_dict(),
                bound_ir=None,
                classification=None,
                physical_query=None,
                error=AltrQLErrorDetailDTO(
                    type=e.__class__.__name__,
                    message=e.message,
                    line=1,
                    column=1,
                ),
            )

    try:
        source = await source_service.get_source(dto.source_id)  # type: ignore[arg-type]
    except SourceNotFoundError:
        return AltrQLExecuteResponseDTO(
            success=False,
            ir=ir.to_dict(),
            bound_ir=None,
            classification=None,
            physical_query=None,
            error=AltrQLErrorDetailDTO(
                type="SourceNotFoundError",
                message=f"Source with id '{dto.source_id}' was not found.",
            ),
        )

    schema = await schema_service.get_latest_schema(dto.source_id)  # type: ignore[arg-type]
    if not schema:
        return AltrQLExecuteResponseDTO(
            success=False,
            ir=ir.to_dict(),
            bound_ir=None,
            classification=None,
            physical_query=None,
            error=AltrQLErrorDetailDTO(
                type="SchemaNotFoundError",
                message=f"No schema snapshot discovered yet for source '{dto.source_id}'. Run schema discovery first.",
            ),
        )

    try:
        bound_ir = bind_altrql(ir, schema)
    except AltrQueryError as e:
        return AltrQLExecuteResponseDTO(
            success=False,
            ir=ir.to_dict(),
            bound_ir=None,
            classification=None,
            physical_query=None,
            error=AltrQLErrorDetailDTO(
                type=e.__class__.__name__,
                message=e.message,
                line=e.line,
                column=e.column,
            ),
        )

    classification = classify_query(bound_ir)
    classification_dto = MutationClassificationDTO(
        operation=classification.operation.value,
        mutation_scope=classification.mutation_scope.value,
        requires_confirmation=classification.requires_confirmation,
        entity=classification.entity,
        description=classification.description,
    )

    try:
        lowerer = get_lowerer(source.type)
        physical_query = lowerer.lower(bound_ir)
    except AltrQueryError as e:
        return AltrQLExecuteResponseDTO(
            success=False,
            ir=ir.to_dict(),
            bound_ir=bound_ir.to_dict(),
            classification=classification_dto,
            physical_query=None,
            error=AltrQLErrorDetailDTO(
                type=e.__class__.__name__,
                message=e.message,
                line=e.line,
                column=e.column,
            ),
        )

    physical_query_dto = _to_physical_query_dto(physical_query)

    if classification.requires_confirmation and not dto.confirm_mass_mutation:
        return AltrQLExecuteResponseDTO(
            success=False,
            ir=ir.to_dict(),
            bound_ir=bound_ir.to_dict(),
            classification=classification_dto,
            physical_query=physical_query_dto,
            selected_source_id=dto.source_id,
            selected_mapping_id=dto.mapping_id,
            columns=[],
            rows=[],
            metadata=None,
            error=AltrQLErrorDetailDTO(
                type="MassMutationConfirmationRequiredError",
                message=f"Mass {classification.operation.value} operation on entity '{classification.entity}' without a WHERE clause requires explicit confirmation.",
            ),
        )

    try:
        if isinstance(physical_query, PhysicalQueryBatch):
            result = await query_service.execute_batch(
                source_id=dto.source_id,  # type: ignore[arg-type]
                queries=[(q.query, q.parameters) for q in physical_query.queries],
            )
        else:
            result = await query_service.execute_query(
                source_id=dto.source_id,  # type: ignore[arg-type]
                query=physical_query.query,
                parameters=physical_query.parameters,
            )

        # Handle explicit source normalization (Normalize=OFF -> raw, Normalize=ON -> logical)
        final_cols = result.columns
        final_rows = result.rows
        if dto.normalize and matching_em:
            phys_to_log = {
                fm.physical_field_name: fm.logical_field_name
                for fm in matching_em.field_mappings
            }
            logical_order = [fm.logical_field_name for fm in matching_em.field_mappings]
            final_cols, final_rows = _normalize_result_rows(
                columns=result.columns,
                rows=result.rows,
                physical_to_logical=phys_to_log,
                logical_field_order=logical_order,
                is_wildcard_projection=original_is_wildcard,
                requested_logical_projections=original_logical_projections,
            )

        affected = (
            result.affected_rows
            if result.affected_rows is not None
            else (result.row_count if classification.operation != QueryOperation.READ else None)
        )
        per_source_info = [
            SourceExecutionInfoDTO(
                source_id=source.id,
                source_name=source.name,
                source_type=source.type.value if hasattr(source.type, "value") else str(source.type),
                status="success",
                rows=result.row_count,
                execution_time_ms=result.execution_time_ms,
            )
        ]

        return AltrQLExecuteResponseDTO(
            success=True,
            ir=ir.to_dict(),
            bound_ir=bound_ir.to_dict(),
            classification=classification_dto,
            physical_query=physical_query_dto,
            physical_queries=[physical_query_dto] if physical_query_dto else [],
            columns=final_cols,
            rows=final_rows,
            execution_mode="single",
            sources_executed=[dto.source_id],  # type: ignore[list-item]
            selected_source_id=dto.source_id,
            selected_mapping_id=dto.mapping_id,
            metadata=QueryMetadataDTO(
                row_count=result.row_count,
                affected_rows=affected,
                execution_time_ms=result.execution_time_ms,
                message=result.message,
                operation=classification.operation.value,
                mutation_scope=classification.mutation_scope.value,
                execution_mode="single",
                normalized=bool(dto.normalize and matching_em),
                source_count=1,
                sources=per_source_info,
            ),
            error=None,
        )
    except Exception as e:
        return AltrQLExecuteResponseDTO(
            success=False,
            ir=ir.to_dict(),
            bound_ir=bound_ir.to_dict(),
            classification=classification_dto,
            physical_query=physical_query_dto,
            execution_mode="single",
            selected_source_id=dto.source_id,
            selected_mapping_id=dto.mapping_id,
            columns=[],
            rows=[],
            metadata=None,
            error=AltrQLErrorDetailDTO(
                type=e.__class__.__name__,
                message=str(e),
            ),
        )

