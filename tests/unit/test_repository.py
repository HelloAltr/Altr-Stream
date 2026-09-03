"""Unit tests for SQLite source and schema repository."""

import pytest
from sqlalchemy.ext.asyncio import AsyncSession

from altr_stream.domain.errors import SourceNotFoundError
from altr_stream.domain.schema import EntitySchema, FieldSchema, SourceSchema, StandardDataType
from altr_stream.domain.source import Source, SourceStatus, SourceType
from altr_stream.infrastructure.database.repository import SqliteSourceRepository


@pytest.mark.asyncio
async def test_repository_crud(test_session: AsyncSession):
    repo = SqliteSourceRepository(test_session)

    # 1. Create
    source = Source(
        name="Production DB",
        type=SourceType.POSTGRESQL,
        host="postgres.internal",
        port=5432,
        database_name="prod_db",
        username="postgres",
        password="secret_pass_123",
    )
    created = await repo.create(source)
    assert created.id == source.id
    assert created.name == "Production DB"

    # 2. Get by ID
    fetched = await repo.get_by_id(source.id)
    assert fetched is not None
    assert fetched.name == "Production DB"
    assert fetched.password == "secret_pass_123"

    # 3. Get by Name
    by_name = await repo.get_by_name("Production DB")
    assert by_name is not None
    assert by_name.id == source.id

    # 4. List All
    all_sources = await repo.list_all()
    assert len(all_sources) == 1
    assert all_sources[0].id == source.id

    # 5. Update
    fetched.host = "postgres.updated.internal"
    fetched.port = 5433
    updated = await repo.update(fetched)
    assert updated.host == "postgres.updated.internal"
    assert updated.port == 5433

    # 6. Update Status
    await repo.update_status(source.id, SourceStatus.ACTIVE)
    after_status = await repo.get_by_id(source.id)
    assert after_status.status == SourceStatus.ACTIVE

    # 7. Delete
    deleted = await repo.delete(source.id)
    assert deleted is True

    # 8. Verify deletion
    assert await repo.get_by_id(source.id) is None


@pytest.mark.asyncio
async def test_repository_schema_snapshot(test_session: AsyncSession):
    repo = SqliteSourceRepository(test_session)

    source = Source(
        name="Analytics DB",
        type=SourceType.POSTGRESQL,
        host="localhost",
        port=5432,
        database_name="analytics",
        username="postgres",
        password="pass",
    )
    await repo.create(source)

    # Initially no schema
    initial_schema = await repo.get_latest_schema(source.id)
    assert initial_schema is None

    # Save schema snapshot
    entity = EntitySchema(
        name="events",
        namespace="public",
        fields=[
            FieldSchema(
                name="id",
                data_type=StandardDataType.BIGINT,
                native_data_type="int8",
                is_primary_key=True,
                nullable=False,
            )
        ],
    )
    schema = SourceSchema(
        source_id=source.id,
        source_name=source.name,
        entities=[entity],
    )

    await repo.save_schema_snapshot(source.id, schema)

    # Retrieve schema snapshot
    loaded = await repo.get_latest_schema(source.id)
    assert loaded is not None
    assert loaded.source_id == source.id
    assert loaded.entity_count == 1
    assert loaded.entities[0].name == "events"
    assert loaded.entities[0].fields[0].name == "id"
