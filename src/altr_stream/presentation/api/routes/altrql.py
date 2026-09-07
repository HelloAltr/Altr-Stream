"""AltrQL language REST API endpoints."""

from fastapi import APIRouter, status

from altr_stream.presentation.api.dtos import (
    AltrQLParseErrorDetailDTO,
    AltrQLParseRequestDTO,
    AltrQLParseResponseDTO,
)
from altr_stream.query_engine.domain.errors import AltrQueryError
from altr_stream.query_engine.parser import parse_altrql

router = APIRouter(prefix="/altrql", tags=["AltrQL"])


@router.post("/parse", response_model=AltrQLParseResponseDTO, status_code=status.HTTP_200_OK)
async def parse_altrql_query(
    dto: AltrQLParseRequestDTO,
) -> AltrQLParseResponseDTO:
    """Parse an AltrQL query text into a typed Abstract Syntax Tree (AltrQueryIR).

    This endpoint operates purely in-memory as a language parser without connecting
    to databases, generating physical SQL, or executing queries.
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
            error=AltrQLParseErrorDetailDTO(
                type=e.__class__.__name__,
                message=e.message,
                line=e.line,
                column=e.column,
            ),
        )
