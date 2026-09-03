"""SQLite repository for sources and schema snapshots."""

from datetime import datetime, timezone
import json
from sqlalchemy import delete, select, update
from sqlalchemy.ext.asyncio import AsyncSession

from altr_stream.domain.errors import SourceNotFoundError
from altr_stream.domain.schema import SourceSchema
from altr_stream.domain.source import Source, SourceStatus, SourceType
from altr_stream.infrastructure.database.models import SchemaSnapshotModel, SourceModel


class SqliteSourceRepository:
    """Repository handling persistence of Source records and Schema Snapshots."""

    def __init__(self, session: AsyncSession):
        self.session = session

    def _to_domain(self, model: SourceModel) -> Source:
        """Convert SQLAlchemy model to domain entity."""
        return Source(
            id=model.id,
            name=model.name,
            type=SourceType(model.type),
            host=model.host,
            port=model.port,
            database_name=model.database_name,
            username=model.username,
            password=model.password,
            status=SourceStatus(model.status),
            created_at=model.created_at,
            updated_at=model.updated_at,
        )

    async def create(self, source: Source) -> Source:
        """Persist a new source entity."""
        model = SourceModel(
            id=source.id,
            name=source.name,
            type=source.type.value,
            host=source.host,
            port=source.port,
            database_name=source.database_name,
            username=source.username,
            password=source.password,
            status=source.status.value,
            created_at=source.created_at,
            updated_at=source.updated_at,
        )
        self.session.add(model)
        await self.session.flush()
        return self._to_domain(model)

    async def get_by_id(self, source_id: str) -> Source | None:
        """Retrieve a source by unique ID."""
        stmt = select(SourceModel).where(SourceModel.id == source_id)
        result = await self.session.execute(stmt)
        model = result.scalar_one_or_none()
        return self._to_domain(model) if model else None

    async def get_by_name(self, name: str) -> Source | None:
        """Retrieve a source by unique name."""
        stmt = select(SourceModel).where(SourceModel.name == name)
        result = await self.session.execute(stmt)
        model = result.scalar_one_or_none()
        return self._to_domain(model) if model else None

    async def list_all(self) -> list[Source]:
        """List all registered sources."""
        stmt = select(SourceModel).order_by(SourceModel.created_at.desc())
        result = await self.session.execute(stmt)
        models = result.scalars().all()
        return [self._to_domain(m) for m in models]

    async def update(self, source: Source) -> Source:
        """Update existing source configuration."""
        stmt = select(SourceModel).where(SourceModel.id == source.id)
        result = await self.session.execute(stmt)
        model = result.scalar_one_or_none()
        if not model:
            raise SourceNotFoundError(source.id)

        model.name = source.name
        model.type = source.type.value
        model.host = source.host
        model.port = source.port
        model.database_name = source.database_name
        model.username = source.username
        if source.password:
            model.password = source.password
        model.status = source.status.value
        model.updated_at = datetime.now(timezone.utc)

        await self.session.flush()
        return self._to_domain(model)

    async def delete(self, source_id: str) -> bool:
        """Delete a source by ID."""
        stmt = delete(SourceModel).where(SourceModel.id == source_id)
        result = await self.session.execute(stmt)
        return result.rowcount > 0

    async def update_status(self, source_id: str, status: SourceStatus) -> None:
        """Update only the status of a source."""
        stmt = (
            update(SourceModel)
            .where(SourceModel.id == source_id)
            .values(status=status.value, updated_at=datetime.now(timezone.utc))
        )
        await self.session.execute(stmt)
        await self.session.flush()

    async def save_schema_snapshot(self, source_id: str, schema: SourceSchema) -> None:
        """Persist a discovered schema snapshot for a source."""
        model = SchemaSnapshotModel(
            source_id=source_id,
            version=schema.version,
            schema_json=schema.model_dump_json(),
            discovered_at=schema.discovered_at,
        )
        self.session.add(model)
        await self.session.flush()

    async def get_latest_schema(self, source_id: str) -> SourceSchema | None:
        """Retrieve the latest schema snapshot for a source."""
        stmt = (
            select(SchemaSnapshotModel)
            .where(SchemaSnapshotModel.source_id == source_id)
            .order_by(SchemaSnapshotModel.discovered_at.desc())
            .limit(1)
        )
        result = await self.session.execute(stmt)
        model = result.scalar_one_or_none()
        if not model:
            return None
        data = json.loads(model.schema_json)
        return SourceSchema.model_validate(data)
