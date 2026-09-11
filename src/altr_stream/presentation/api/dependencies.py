"""Centralized FastAPI dependency providers."""

from fastapi import Depends
from sqlalchemy.ext.asyncio import AsyncSession

from altr_stream.application.query_service import QueryService
from altr_stream.application.registry_service import RegistryService
from altr_stream.application.schema_service import SchemaService
from altr_stream.application.source_service import SourceService
from altr_stream.infrastructure.database.registry_repository import SqliteRegistryRepository
from altr_stream.infrastructure.database.repository import SqliteSourceRepository
from altr_stream.infrastructure.database.session import get_session


def get_source_service(session: AsyncSession = Depends(get_session)) -> SourceService:
    """Provide a scoped SourceService instance."""
    repository = SqliteSourceRepository(session)
    return SourceService(repository)


def get_schema_service(session: AsyncSession = Depends(get_session)) -> SchemaService:
    """Provide a scoped SchemaService instance."""
    repository = SqliteSourceRepository(session)
    return SchemaService(repository)


def get_query_service(session: AsyncSession = Depends(get_session)) -> QueryService:
    """Provide a scoped QueryService instance."""
    repository = SqliteSourceRepository(session)
    return QueryService(repository)


def get_registry_service(session: AsyncSession = Depends(get_session)) -> RegistryService:
    """Provide a scoped RegistryService instance."""
    registry_repo = SqliteRegistryRepository(session)
    source_repo = SqliteSourceRepository(session)
    schema_service = SchemaService(source_repo)
    return RegistryService(registry_repo, source_repo, schema_service)


