"""Source management REST API endpoints."""

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from altr_stream.application.schema_service import SchemaService
from altr_stream.application.source_service import SourceService
from altr_stream.domain.connector import SourceCapabilities
from altr_stream.domain.errors import (
    AltrStreamError,
    SchemaDiscoveryError,
    SourceAlreadyExistsError,
    SourceNotFoundError,
)
from altr_stream.domain.schema import SourceSchema
from altr_stream.domain.source import ConnectionConfig
from altr_stream.presentation.api.dependencies import (
    get_schema_service,
    get_source_service,
)
from altr_stream.presentation.api.dtos import (
    ConnectionTestRequestDTO,
    ConnectionTestResponseDTO,
    SourceCreateDTO,
    SourceResponseDTO,
    SourceUpdateDTO,
)

router = APIRouter(prefix="/sources", tags=["Sources"])


@router.post("", response_model=SourceResponseDTO, status_code=status.HTTP_201_CREATED)
async def create_source(
    dto: SourceCreateDTO,
    service: SourceService = Depends(get_source_service),
) -> SourceResponseDTO:
    """Register a new external data source."""
    try:
        source, _ = await service.create_source(
            name=dto.name,
            source_type=dto.type,
            host=dto.host,
            port=dto.port,
            database_name=dto.database_name,
            username=dto.username,
            password=dto.password,
            file_path=dto.file_path,
            test_first=dto.test_connection_first,
        )
        return SourceResponseDTO.from_domain(source)
    except SourceAlreadyExistsError as e:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=e.message) from e
    except AltrStreamError as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=e.message) from e


@router.get("", response_model=list[SourceResponseDTO])
async def list_sources(
    service: SourceService = Depends(get_source_service),
) -> list[SourceResponseDTO]:
    """List all registered data sources."""
    sources = await service.list_sources()
    return [SourceResponseDTO.from_domain(s) for s in sources]


@router.post("/test", response_model=ConnectionTestResponseDTO)
async def test_adhoc_connection(
    dto: ConnectionTestRequestDTO,
    service: SourceService = Depends(get_source_service),
) -> ConnectionTestResponseDTO:
    """Test physical connection reachability without saving the source."""
    config = ConnectionConfig(
        host=dto.host,
        port=dto.port,
        database_name=dto.database_name,
        username=dto.username,
        password=dto.password,
        file_path=dto.file_path,
    )
    result = await service.test_adhoc_connection(dto.type, config)
    return ConnectionTestResponseDTO(
        success=result.success,
        message=result.message,
        latency_ms=result.latency_ms,
        server_version=result.server_version,
        error_details=result.error_details,
    )


@router.get("/{source_id}", response_model=SourceResponseDTO)
async def get_source(
    source_id: str,
    service: SourceService = Depends(get_source_service),
) -> SourceResponseDTO:
    """Retrieve details for a single data source."""
    try:
        source = await service.get_source(source_id)
        return SourceResponseDTO.from_domain(source)
    except SourceNotFoundError as e:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=e.message) from e


@router.put("/{source_id}", response_model=SourceResponseDTO)
async def update_source(
    source_id: str,
    dto: SourceUpdateDTO,
    service: SourceService = Depends(get_source_service),
) -> SourceResponseDTO:
    """Update properties for a registered data source."""
    try:
        source = await service.update_source(
            source_id=source_id,
            name=dto.name,
            host=dto.host,
            port=dto.port,
            database_name=dto.database_name,
            username=dto.username,
            password=dto.password,
            file_path=dto.file_path,
        )
        return SourceResponseDTO.from_domain(source)
    except SourceNotFoundError as e:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=e.message) from e
    except SourceAlreadyExistsError as e:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=e.message) from e


@router.delete("/{source_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_source(
    source_id: str,
    service: SourceService = Depends(get_source_service),
) -> None:
    """Delete a registered data source and its associated schema snapshots."""
    deleted = await service.delete_source(source_id)
    if not deleted:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Source with id '{source_id}' was not found.",
        )


@router.post("/{source_id}/test", response_model=ConnectionTestResponseDTO)
async def test_saved_source_connection(
    source_id: str,
    service: SourceService = Depends(get_source_service),
) -> ConnectionTestResponseDTO:
    """Test physical connection for an already registered data source."""
    try:
        result = await service.test_source_connection(source_id)
        return ConnectionTestResponseDTO(
            success=result.success,
            message=result.message,
            latency_ms=result.latency_ms,
            server_version=result.server_version,
            error_details=result.error_details,
        )
    except SourceNotFoundError as e:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=e.message) from e


@router.get("/{source_id}/capabilities", response_model=SourceCapabilities)
async def get_source_capabilities(
    source_id: str,
    service: SourceService = Depends(get_source_service),
) -> SourceCapabilities:
    """Retrieve capabilities supported by the source's connector."""
    try:
        source = await service.get_source(source_id)
        return service.get_source_capabilities(source)
    except SourceNotFoundError as e:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=e.message) from e


@router.post("/{source_id}/schema/discover", response_model=SourceSchema)
async def discover_source_schema(
    source_id: str,
    service: SchemaService = Depends(get_schema_service),
) -> SourceSchema:
    """Introspect schema from physical source and store snapshot."""
    try:
        return await service.discover_and_save_schema(source_id)
    except SourceNotFoundError as e:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=e.message) from e
    except SchemaDiscoveryError as e:
        raise HTTPException(status_code=status.HTTP_502_BAD_GATEWAY, detail=e.message) from e
    except AltrStreamError as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=e.message) from e


@router.get("/{source_id}/schema", response_model=SourceSchema)
async def get_latest_schema(
    source_id: str,
    service: SchemaService = Depends(get_schema_service),
) -> SourceSchema:
    """Retrieve the most recent schema snapshot discovered for this source."""
    try:
        schema = await service.get_latest_schema(source_id)
        if not schema:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"No schema snapshot discovered yet for source '{source_id}'. Run schema discovery first.",
            )
        return schema
    except SourceNotFoundError as e:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=e.message) from e
