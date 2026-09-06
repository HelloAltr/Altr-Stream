"""Schema discovery and management application service."""

from altr_stream.domain.errors import SourceNotFoundError
from altr_stream.domain.schema import SourceSchema
from altr_stream.domain.source import SourceStatus
from altr_stream.infrastructure.connectors.factory import ConnectorFactory
from altr_stream.infrastructure.database.repository import SqliteSourceRepository


class SchemaService:
    """Application use cases for schema introspection and retrieval."""

    def __init__(self, repository: SqliteSourceRepository):
        self.repository = repository

    async def discover_and_save_schema(self, source_id: str) -> SourceSchema:
        """Introspect schema from physical source, store snapshot, and update status."""
        source = await self.repository.get_by_id(source_id)
        if not source:
            raise SourceNotFoundError(source_id)

        connector = ConnectorFactory.get_connector(source.type, source.connection_config)
        async with connector:
            schema = await connector.discover_schema(source_id=source.id, source_name=source.name)

        # Persist discovered schema snapshot
        await self.repository.save_schema_snapshot(source_id, schema)

        # Mark source as active since discovery succeeded
        await self.repository.update_status(source_id, SourceStatus.ACTIVE)

        return schema

    async def get_latest_schema(self, source_id: str) -> SourceSchema | None:
        """Retrieve the most recently discovered schema snapshot for a source."""
        source = await self.repository.get_by_id(source_id)
        if not source:
            raise SourceNotFoundError(source_id)
        return await self.repository.get_latest_schema(source_id)
