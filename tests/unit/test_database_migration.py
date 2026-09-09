"""Automated unit and integration tests for SQLite metadata database schema migrations."""

import os
import tempfile
import aiosqlite
import pytest
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

from altr_stream.domain.source import Source, SourceStatus, SourceType
from altr_stream.infrastructure.database.migrations import run_migrations
from altr_stream.infrastructure.database.repository import SqliteSourceRepository
from altr_stream.infrastructure.database.session import init_db


@pytest.fixture
def temp_db_path():
    """Create a unique temporary SQLite database file path."""
    fd, path = tempfile.mkstemp(suffix=".db")
    os.close(fd)
    yield path
    if os.path.exists(path):
        os.remove(path)


@pytest.mark.asyncio
async def test_fresh_database_initialization(temp_db_path: str):
    """Verify that a fresh database is initialized with the full v0.6 schema including file_path."""
    engine = create_async_engine(f"sqlite+aiosqlite:///{temp_db_path}", echo=False)
    try:
        await init_db(engine)

        async with aiosqlite.connect(temp_db_path) as db:
            async with db.execute("PRAGMA table_info(sources)") as cursor:
                columns = {row[1]: row[2] for row in await cursor.fetchall()}

        assert "id" in columns
        assert "name" in columns
        assert "type" in columns
        assert "host" in columns
        assert "port" in columns
        assert "database_name" in columns
        assert "username" in columns
        assert "password" in columns
        assert "file_path" in columns
        assert "status" in columns
        assert "created_at" in columns
        assert "updated_at" in columns
    finally:
        await engine.dispose()


@pytest.mark.asyncio
async def test_upgrade_from_pre_v06_sources_schema(temp_db_path: str):
    """Verify safe upgrade of pre-v0.6 database preserving existing PostgreSQL source records."""
    # 1. Create a pre-v0.6 database schema (without file_path)
    async with aiosqlite.connect(temp_db_path) as db:
        await db.execute(
            """
            CREATE TABLE sources (
                id VARCHAR(36) NOT NULL PRIMARY KEY,
                name VARCHAR(255) NOT NULL UNIQUE,
                type VARCHAR(50) NOT NULL,
                host VARCHAR(255) NOT NULL,
                port INTEGER NOT NULL,
                database_name VARCHAR(255) NOT NULL,
                username VARCHAR(255) NOT NULL,
                password VARCHAR(255) NOT NULL,
                status VARCHAR(50) NOT NULL,
                created_at DATETIME NOT NULL,
                updated_at DATETIME NOT NULL
            );
            """
        )
        # Seed an existing PostgreSQL source record matching runtime snapshot
        await db.execute(
            """
            INSERT INTO sources (
                id, name, type, host, port, database_name, username, password, status, created_at, updated_at
            ) VALUES (
                'a13ed997-7c94-4f07-96c7-976e41d97044',
                'Postgre Test',
                'POSTGRESQL',
                'altr-postgres-test',
                5432,
                'altr_test_db',
                'altr_test_user',
                'altr_test_pass',
                'ACTIVE',
                '2026-09-06 06:43:45.589589',
                '2026-09-08 03:50:22.098710'
            );
            """
        )
        await db.commit()

        # Verify file_path is indeed missing before migration
        async with db.execute("PRAGMA table_info(sources)") as cursor:
            pre_columns = [row[1] for row in await cursor.fetchall()]
        assert "file_path" not in pre_columns

    # 2. Run application database initialization (which runs migrations)
    engine = create_async_engine(f"sqlite+aiosqlite:///{temp_db_path}", echo=False)
    try:
        await init_db(engine)

        # 3. Verify file_path column was added
        async with aiosqlite.connect(temp_db_path) as db:
            async with db.execute("PRAGMA table_info(sources)") as cursor:
                post_columns = [row[1] for row in await cursor.fetchall()]
        assert "file_path" in post_columns

        # 4. Verify repository can list and query the existing PostgreSQL source without error
        session_factory = async_sessionmaker(bind=engine, class_=AsyncSession, expire_on_commit=False)
        async with session_factory() as session:
            repo = SqliteSourceRepository(session)
            sources = await repo.list_all()
            assert len(sources) == 1

            existing_pg = sources[0]
            assert existing_pg.id == "a13ed997-7c94-4f07-96c7-976e41d97044"
            assert existing_pg.name == "Postgre Test"
            assert existing_pg.type == SourceType.POSTGRESQL
            assert existing_pg.host == "altr-postgres-test"
            assert existing_pg.port == 5432
            assert existing_pg.database_name == "altr_test_db"
            assert existing_pg.username == "altr_test_user"
            assert existing_pg.password == "altr_test_pass"
            assert existing_pg.status == SourceStatus.ACTIVE
            assert existing_pg.file_path is None
    finally:
        await engine.dispose()


@pytest.mark.asyncio
async def test_migration_idempotency_on_repeated_startup(temp_db_path: str):
    """Verify that running migrations repeatedly on already-upgraded databases is idempotent and safe."""
    engine = create_async_engine(f"sqlite+aiosqlite:///{temp_db_path}", echo=False)
    try:
        # First initialization
        await init_db(engine)

        # Second initialization
        await init_db(engine)

        # Third initialization
        await init_db(engine)

        # Check table integrity
        async with aiosqlite.connect(temp_db_path) as db:
            async with db.execute("PRAGMA table_info(sources)") as cursor:
                columns = [row[1] for row in await cursor.fetchall()]
        assert columns.count("file_path") == 1
    finally:
        await engine.dispose()


@pytest.mark.asyncio
async def test_heterogeneous_sources_in_migrated_db(temp_db_path: str):
    """Verify registering and querying both PostgreSQL and SQLite sources in an upgraded database."""
    # 1. Setup pre-v0.6 database with PostgreSQL source
    async with aiosqlite.connect(temp_db_path) as db:
        await db.execute(
            """
            CREATE TABLE sources (
                id VARCHAR(36) NOT NULL PRIMARY KEY,
                name VARCHAR(255) NOT NULL UNIQUE,
                type VARCHAR(50) NOT NULL,
                host VARCHAR(255) NOT NULL,
                port INTEGER NOT NULL,
                database_name VARCHAR(255) NOT NULL,
                username VARCHAR(255) NOT NULL,
                password VARCHAR(255) NOT NULL,
                status VARCHAR(50) NOT NULL,
                created_at DATETIME NOT NULL,
                updated_at DATETIME NOT NULL
            );
            """
        )
        await db.execute(
            """
            INSERT INTO sources (
                id, name, type, host, port, database_name, username, password, status, created_at, updated_at
            ) VALUES (
                'pg-1', 'Legacy PG', 'POSTGRESQL', 'localhost', 5432, 'db1', 'u1', 'p1', 'ACTIVE',
                '2026-09-01 00:00:00', '2026-09-01 00:00:00'
            );
            """
        )
        await db.commit()

    # 2. Upgrade database
    engine = create_async_engine(f"sqlite+aiosqlite:///{temp_db_path}", echo=False)
    try:
        await init_db(engine)

        session_factory = async_sessionmaker(bind=engine, class_=AsyncSession, expire_on_commit=False)
        async with session_factory() as session:
            repo = SqliteSourceRepository(session)

            # 3. Add a new SQLite source with file_path
            sqlite_src = Source(
                id="sqlite-1",
                name="Local SQLite",
                type=SourceType.SQLITE,
                file_path="/tmp/local_test.db",
                status=SourceStatus.ACTIVE,
            )
            created_sqlite = await repo.create(sqlite_src)
            assert created_sqlite.file_path == "/tmp/local_test.db"

            # 4. List all sources and verify both coexist
            all_sources = await repo.list_all()
            assert len(all_sources) == 2

            pg_source = next(s for s in all_sources if s.id == "pg-1")
            assert pg_source.type == SourceType.POSTGRESQL
            assert pg_source.file_path is None
            assert pg_source.host == "localhost"

            sq_source = next(s for s in all_sources if s.id == "sqlite-1")
            assert sq_source.type == SourceType.SQLITE
            assert sq_source.file_path == "/tmp/local_test.db"
            assert sq_source.host is None
    finally:
        await engine.dispose()


@pytest.mark.asyncio
async def test_schema_snapshots_preserved_across_migration(temp_db_path: str):
    """Verify that schema snapshots linked to sources via foreign keys are preserved across migration."""
    # 1. Setup pre-v0.6 database with a source and schema snapshot
    async with aiosqlite.connect(temp_db_path) as db:
        await db.execute(
            """
            CREATE TABLE sources (
                id VARCHAR(36) NOT NULL PRIMARY KEY,
                name VARCHAR(255) NOT NULL UNIQUE,
                type VARCHAR(50) NOT NULL,
                host VARCHAR(255) NOT NULL,
                port INTEGER NOT NULL,
                database_name VARCHAR(255) NOT NULL,
                username VARCHAR(255) NOT NULL,
                password VARCHAR(255) NOT NULL,
                status VARCHAR(50) NOT NULL,
                created_at DATETIME NOT NULL,
                updated_at DATETIME NOT NULL
            );
            """
        )
        await db.execute(
            """
            CREATE TABLE schema_snapshots (
                id VARCHAR(36) NOT NULL PRIMARY KEY,
                source_id VARCHAR(36) NOT NULL,
                version VARCHAR(50) NOT NULL,
                schema_json TEXT NOT NULL,
                discovered_at DATETIME NOT NULL,
                FOREIGN KEY(source_id) REFERENCES sources (id) ON DELETE CASCADE
            );
            """
        )
        await db.execute(
            """
            INSERT INTO sources (
                id, name, type, host, port, database_name, username, password, status, created_at, updated_at
            ) VALUES (
                'src-with-schema', 'Source 1', 'POSTGRESQL', 'localhost', 5432, 'db1', 'u1', 'p1', 'ACTIVE',
                '2026-09-01 00:00:00', '2026-09-01 00:00:00'
            );
            """
        )
        schema_json_sample = '{"source_id": "src-with-schema", "source_name": "Source 1", "version": "1.0.0", "discovered_at": "2026-09-01T00:00:00Z", "entities": [], "metadata": {}}'
        await db.execute(
            """
            INSERT INTO schema_snapshots (
                id, source_id, version, schema_json, discovered_at
            ) VALUES (
                'snap-1', 'src-with-schema', '1.0.0', ?, '2026-09-01 00:00:00'
            );
            """,
            (schema_json_sample,),
        )
        await db.commit()

    # 2. Run migration
    engine = create_async_engine(f"sqlite+aiosqlite:///{temp_db_path}", echo=False)
    try:
        await init_db(engine)

        # 3. Verify snapshot is preserved and loadable via repository
        session_factory = async_sessionmaker(bind=engine, class_=AsyncSession, expire_on_commit=False)
        async with session_factory() as session:
            repo = SqliteSourceRepository(session)
            latest_schema = await repo.get_latest_schema("src-with-schema")
            assert latest_schema is not None
            assert latest_schema.source_id == "src-with-schema"
            assert latest_schema.version == "1.0.0"
    finally:
        await engine.dispose()


@pytest.mark.asyncio
async def test_update_migrated_source(temp_db_path: str):
    """Verify updating a migrated source retains its fields and can populate file_path."""
    async with aiosqlite.connect(temp_db_path) as db:
        await db.execute(
            """
            CREATE TABLE sources (
                id VARCHAR(36) NOT NULL PRIMARY KEY,
                name VARCHAR(255) NOT NULL UNIQUE,
                type VARCHAR(50) NOT NULL,
                host VARCHAR(255) NOT NULL,
                port INTEGER NOT NULL,
                database_name VARCHAR(255) NOT NULL,
                username VARCHAR(255) NOT NULL,
                password VARCHAR(255) NOT NULL,
                status VARCHAR(50) NOT NULL,
                created_at DATETIME NOT NULL,
                updated_at DATETIME NOT NULL
            );
            """
        )
        await db.execute(
            """
            INSERT INTO sources (
                id, name, type, host, port, database_name, username, password, status, created_at, updated_at
            ) VALUES (
                'upd-1', 'Initial Name', 'POSTGRESQL', 'localhost', 5432, 'db1', 'u1', 'p1', 'ACTIVE',
                '2026-09-01 00:00:00', '2026-09-01 00:00:00'
            );
            """
        )
        await db.commit()

    engine = create_async_engine(f"sqlite+aiosqlite:///{temp_db_path}", echo=False)
    try:
        await init_db(engine)

        session_factory = async_sessionmaker(bind=engine, class_=AsyncSession, expire_on_commit=False)
        async with session_factory() as session:
            repo = SqliteSourceRepository(session)
            source = await repo.get_by_id("upd-1")
            assert source is not None
            source.name = "Renamed Source"
            source.file_path = "/path/to/backup.db"
            updated = await repo.update(source)
            assert updated.name == "Renamed Source"
            assert updated.file_path == "/path/to/backup.db"

            reloaded = await repo.get_by_id("upd-1")
            assert reloaded is not None
            assert reloaded.name == "Renamed Source"
            assert reloaded.file_path == "/path/to/backup.db"
    finally:
        await engine.dispose()

