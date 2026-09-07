"""AltrQL language REST API endpoints."""

from fastapi import APIRouter, Depends, status

from altr_stream.application.schema_service import SchemaService
from altr_stream.domain.errors import SourceNotFoundError
from altr_stream.presentation.api.dependencies import get_schema_service
from altr_stream.presentation.api.dtos import (
    AltrQLBindRequestDTO,
    AltrQLBindResponseDTO,
    AltrQLErrorDetailDTO,
    AltrQLParseRequestDTO,
    AltrQLParseResponseDTO,
)
from altr_stream.query_engine.binding import bind_altrql
from altr_stream.query_engine.domain.errors import AltrQueryError
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
            error=AltrQLErrorDetailDTO(
                type="SchemaNotFoundError",
                message=f"No schema snapshot discovered yet for source '{dto.source_id}'. Run schema discovery first.",
            ),
        )

    # 3. Pure schema binding & type validation
    try:
        bound_ir = bind_altrql(ir, schema)
        return AltrQLBindResponseDTO(
            success=True,
            ir=ir.to_dict(),
            bound_ir=bound_ir.to_dict(),
            error=None,
        )
    except AltrQueryError as e:
        return AltrQLBindResponseDTO(
            success=False,
            ir=ir.to_dict(),
            bound_ir=None,
            error=AltrQLErrorDetailDTO(
                type=e.__class__.__name__,
                message=e.message,
                line=e.line,
                column=e.column,
            ),
        )
