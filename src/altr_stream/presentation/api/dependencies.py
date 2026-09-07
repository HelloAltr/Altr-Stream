"""Centralized FastAPI dependency providers."""

from fastapi import Depends
from sqlalchemy.ext.asyncio import AsyncSession

from altr_stream.application.schema_service import SchemaService
from altr_stream.application.source_service import SourceService
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
