"""Query execution REST API endpoints for Query Playground."""

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from altr_stream.application.query_service import QueryService
from altr_stream.domain.errors import (
    AltrStreamError,
    QueryExecutionError,
    QueryExecutionNotSupportedError,
    ReadOnlyQueryRequiredError,
    SourceNotFoundError,
)
from altr_stream.infrastructure.database.models import ApiKeyModel
from altr_stream.infrastructure.database.repository import SqliteSourceRepository
from altr_stream.infrastructure.database.session import get_session
from altr_stream.presentation.api.dtos import (
    QueryExecuteRequestDTO,
    QueryExecuteResponseDTO,
    QueryMetadataDTO,
)
from altr_stream.presentation.api.security import require_read_access

router = APIRouter(prefix="/queries", tags=["Queries"])


def get_query_service(session: AsyncSession = Depends(get_session)) -> QueryService:
    repository = SqliteSourceRepository(session)
    return QueryService(repository)


@router.post("/execute", response_model=QueryExecuteResponseDTO, status_code=status.HTTP_200_OK)
async def execute_query(
    dto: QueryExecuteRequestDTO,
    auth_key: ApiKeyModel | None = Depends(require_read_access),
    service: QueryService = Depends(get_query_service),
) -> QueryExecuteResponseDTO:
    """Execute a native query against a registered physical data source."""
    if dto.mode == "write" and auth_key is not None and not any(s in auth_key.scopes for s in ("write", "admin")):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Write query execution requires 'write' or 'admin' scope.",
        )
    try:
        result = await service.execute_query(source_id=dto.source_id, query=dto.query, mode=dto.mode)
        return QueryExecuteResponseDTO(
            success=True,
            columns=result.columns,
            rows=result.rows,
            metadata=QueryMetadataDTO(
                row_count=result.row_count,
                affected_rows=result.affected_rows,
                message=result.message,
                execution_time_ms=result.execution_time_ms,
            ),
        )
    except SourceNotFoundError as e:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=e.message) from e
    except ReadOnlyQueryRequiredError as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=e.message) from e
    except QueryExecutionNotSupportedError as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=e.message) from e
    except QueryExecutionError as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=e.message) from e
    except AltrStreamError as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=e.message) from e
