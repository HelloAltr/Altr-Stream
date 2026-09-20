"""Schema discovery and management application service."""

from altr_stream.domain.errors import SourceNotFoundError
from altr_stream.domain.schema import EntitySchema, SourceSchema
from altr_stream.domain.source import Source, SourceStatus
from altr_stream.infrastructure.connectors.factory import ConnectorFactory
from altr_stream.infrastructure.database.repository import SqliteSourceRepository
from altr_stream.query_engine.planning.models import (
    SourceExclusionInfo,
    SourceExclusionReason,
    SourceExecutionStatus,
)


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

    async def find_sources_with_physical_entity(
        self, entity_name: str
    ) -> tuple[list[tuple[Source, SourceSchema, EntitySchema]], list[SourceExclusionInfo]]:
        """Inspect all active sources to discover matching physical entities across cached schemas.

        Matches entity names case-insensitively and handles singular/plural variants.
        Returns:
            tuple of (matching_sources_and_schemas, excluded_sources_info)
        """
        all_sources = await self.repository.list_all()
        active_sources = [s for s in all_sources if s.status == SourceStatus.ACTIVE]

        target = entity_name.strip().lower()
        target_clean = target.rstrip("s")

        matching: list[tuple[Source, SourceSchema, EntitySchema]] = []
        excluded: list[SourceExclusionInfo] = []

        for src in active_sources:
            schema = await self.repository.get_latest_schema(src.id)
            src_type_str = src.type.value if hasattr(src.type, "value") else str(src.type)
            if not schema or not schema.entities:
                excluded.append(
                    SourceExclusionInfo(
                        source_id=src.id,
                        source_name=src.name,
                        source_type=src_type_str,
                        physical_entity=entity_name,
                        status=SourceExecutionStatus.EXCLUDED.value,
                        reason_code=SourceExclusionReason.PHYSICAL_ENTITY_NOT_FOUND.value,
                        message=f"No schema snapshot discovered yet for source '{src.name}'.",
                    )
                )
                continue

            matched_entity: EntitySchema | None = None
            for ent in schema.entities:
                ent_name = ent.name.strip().lower()
                if ent_name == target or (ent_name and ent_name.rstrip("s") == target_clean):
                    matched_entity = ent
                    break

            if matched_entity:
                matching.append((src, schema, matched_entity))
            else:
                excluded.append(
                    SourceExclusionInfo(
                        source_id=src.id,
                        source_name=src.name,
                        source_type=src_type_str,
                        physical_entity=entity_name,
                        status=SourceExecutionStatus.EXCLUDED.value,
                        reason_code=SourceExclusionReason.PHYSICAL_ENTITY_NOT_FOUND.value,
                        message=f"Physical entity '{entity_name}' not found in source '{src.name}'.",
                    )
                )

        return matching, excluded
