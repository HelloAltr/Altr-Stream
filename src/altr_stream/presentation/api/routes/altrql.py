"""AltrQL language REST API endpoints."""

from fastapi import APIRouter, Depends, status

from altr_stream.application.query_service import QueryService
from altr_stream.application.schema_service import SchemaService
from altr_stream.application.source_service import SourceService
from altr_stream.domain.errors import SourceNotFoundError
from altr_stream.presentation.api.dependencies import (
    get_query_service,
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
    MutationClassificationDTO,
    PhysicalQueryBatchDTO,
    PhysicalQueryDTO,
    QueryMetadataDTO,
)
from altr_stream.query_engine.binding import bind_altrql
from altr_stream.query_engine.classification import classify_query
from altr_stream.query_engine.domain.ast import QueryOperation
from altr_stream.query_engine.domain.errors import AltrQueryError
from altr_stream.query_engine.domain.physical_query import PhysicalQueryBatch
from altr_stream.query_engine.lowering import get_lowerer
from altr_stream.query_engine.parser import parse_altrql

router = APIRouter(prefix="/altrql", tags=["AltrQL"])


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
    schema_service: SchemaService = Depends(get_schema_service),
) -> AltrQLBindResponseDTO:
    """Bind a parsed AltrQL query against a registered data source's discovered schema snapshot.

    Performs entity and field resolution as well as schema-aware operator/operand type validation
    without physical SQL lowering or query execution.
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

    # 2. Retrieve discovered schema snapshot from repository
    try:
        schema = await schema_service.get_latest_schema(dto.source_id)
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

    # 3. Pure schema binding, type validation & classification
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


@router.post("/execute", response_model=AltrQLExecuteResponseDTO, status_code=status.HTTP_200_OK)
async def execute_altrql_query(
    dto: AltrQLExecuteRequestDTO,
    source_service: SourceService = Depends(get_source_service),
    schema_service: SchemaService = Depends(get_schema_service),
    query_service: QueryService = Depends(get_query_service),
) -> AltrQLExecuteResponseDTO:
    """Execute an AltrQL query against a registered data source.

    Orchestrates the complete verified pipeline:
    Parse -> Bind -> Classify -> Lower -> Safety Gate -> Execute -> Normalize Result.
    Preserves intermediate compiler artifacts on downstream failures.
    """
    # 1. Parse and semantically validate canonical IR
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

    # 2. Retrieve source
    try:
        source = await source_service.get_source(dto.source_id)
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

    # 3. Retrieve schema snapshot
    schema = await schema_service.get_latest_schema(dto.source_id)
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

    # 4. Pure schema binding & type validation
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

    # 5. Deterministic classification
    classification = classify_query(bound_ir)
    classification_dto = MutationClassificationDTO(
        operation=classification.operation.value,
        mutation_scope=classification.mutation_scope.value,
        requires_confirmation=classification.requires_confirmation,
        entity=classification.entity,
        description=classification.description,
    )

    # 6. Pure dialect lowering
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

    if isinstance(physical_query, PhysicalQueryBatch):
        physical_query_dto = PhysicalQueryBatchDTO(
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
    else:
        physical_query_dto = PhysicalQueryDTO(
            dialect=physical_query.dialect,
            query=physical_query.query,
            parameters=physical_query.parameters,
            source_id=physical_query.source_id,
            source_name=physical_query.source_name,
        )

    # 7. Mass mutation safety gate
    if classification.requires_confirmation and not dto.confirm_mass_mutation:
        return AltrQLExecuteResponseDTO(
            success=False,
            ir=ir.to_dict(),
            bound_ir=bound_ir.to_dict(),
            classification=classification_dto,
            physical_query=physical_query_dto,
            columns=[],
            rows=[],
            metadata=None,
            error=AltrQLErrorDetailDTO(
                type="MassMutationConfirmationRequiredError",
                message=f"Mass {classification.operation.value} operation on entity '{classification.entity}' without a WHERE clause requires explicit confirmation.",
            ),
        )

    # 8. Physical database execution via QueryService
    try:
        if isinstance(physical_query, PhysicalQueryBatch):
            result = await query_service.execute_batch(
                source_id=dto.source_id,
                queries=[(q.query, q.parameters) for q in physical_query.queries],
            )
        else:
            result = await query_service.execute_query(
                source_id=dto.source_id,
                query=physical_query.query,
                parameters=physical_query.parameters,
            )
        affected = (
            result.affected_rows
            if result.affected_rows is not None
            else (result.row_count if classification.operation != QueryOperation.READ else None)
        )
        return AltrQLExecuteResponseDTO(
            success=True,
            ir=ir.to_dict(),
            bound_ir=bound_ir.to_dict(),
            classification=classification_dto,
            physical_query=physical_query_dto,
            columns=result.columns,
            rows=result.rows,
            metadata=QueryMetadataDTO(
                row_count=result.row_count,
                affected_rows=affected,
                execution_time_ms=result.execution_time_ms,
                message=result.message,
                operation=classification.operation.value,
                mutation_scope=classification.mutation_scope.value,
            ),
            error=None,
        )
    except Exception as e:
        # Preserve pipeline context on execution failures
        return AltrQLExecuteResponseDTO(
            success=False,
            ir=ir.to_dict(),
            bound_ir=bound_ir.to_dict(),
            classification=classification_dto,
            physical_query=physical_query_dto,
            columns=[],
            rows=[],
            metadata=None,
            error=AltrQLErrorDetailDTO(
                type=e.__class__.__name__,
                message=str(e),
            ),
        )
