"""Live integration tests for MongoDB physical connector lifecycle and reachability against a live MongoDB container."""

import asyncio
import pytest

from altr_stream.domain.source import ConnectionConfig
from altr_stream.infrastructure.connectors.mongodb.connector import MongoDBConnector

MONGO_CONFIG = ConnectionConfig(
    host="localhost",
    port=27017,
    database_name="altr_test_db",
    username="altr_test_user",
    password="altr_test_pass",
    options={"authSource": "admin"},
)


async def _is_mongodb_available() -> bool:
    """Check if MongoDB test container is reachable on localhost:27017."""
    try:
        conn = MongoDBConnector(MONGO_CONFIG, timeout_sec=2.0)
        res = await conn.test_connection()
        return res.success
    except Exception:
        return False


@pytest.fixture(scope="module")
def event_loop():
    loop = asyncio.new_event_loop()
    yield loop
    loop.close()


@pytest.mark.asyncio
async def test_mongodb_live_test_connection_success():
    """Verify test_connection succeeds against live MongoDB container reporting version and latency."""
    if not await _is_mongodb_available():
        pytest.skip("MongoDB test container not available on port 27017")

    connector = MongoDBConnector(MONGO_CONFIG)
    result = await connector.test_connection()

    assert result.success is True
    assert "Connected successfully to MongoDB" in result.message
    assert result.latency_ms is not None
    assert result.latency_ms > 0
    assert result.server_version is not None
    assert result.server_version.startswith("7.")


@pytest.mark.asyncio
async def test_mongodb_live_connector_lifecycle():
    """Verify live AsyncMongoClient lifecycle initialization, operation, and cleanup."""
    if not await _is_mongodb_available():
        pytest.skip("MongoDB test container not available on port 27017")

    connector = MongoDBConnector(MONGO_CONFIG)

    # 1. Prior to initialize
    assert connector._is_initialized is False
    assert connector._client is None

    # 2. Initialize
    await connector.initialize()
    assert connector._is_initialized is True
    assert connector._client is not None

    # Test that initialized client can ping server
    db = connector._client["altr_test_db"]
    ping_res = await db.command("ping")
    assert ping_res.get("ok") == 1.0

    # 3. Close
    await connector.close()
    assert connector._is_initialized is False
    assert connector._client is None

    # 4. Safe idempotent close
    await connector.close()
    assert connector._client is None


@pytest.mark.asyncio
async def test_mongodb_live_reconnection():
    """Verify connector can be re-initialized after being closed."""
    if not await _is_mongodb_available():
        pytest.skip("MongoDB test container not available on port 27017")

    connector = MongoDBConnector(MONGO_CONFIG)

    async with connector:
        assert connector._is_initialized is True
        res1 = await connector.test_connection()
        assert res1.success is True

    assert connector._is_initialized is False

    # Second context manager cycle (re-initialization)
    async with connector:
        assert connector._is_initialized is True
        res2 = await connector.test_connection()
        assert res2.success is True

    assert connector._is_initialized is False


@pytest.mark.asyncio
async def test_mongodb_live_invalid_credentials():
    """Verify invalid credentials return a sanitized failure response."""
    if not await _is_mongodb_available():
        pytest.skip("MongoDB test container not available on port 27017")

    bad_config = ConnectionConfig(
        host="localhost",
        port=27017,
        database_name="altr_test_db",
        username="altr_test_user",
        password="invalid_secret_password_xyz",
        options={"authSource": "admin"},
    )
    connector = MongoDBConnector(bad_config, timeout_sec=2.0)
    result = await connector.test_connection()

    assert result.success is False
    assert "Connection failed" in result.message
    # Verify password is masked and not leaked
    assert "invalid_secret_password_xyz" not in result.message
    assert "invalid_secret_password_xyz" not in (result.error_details or "")


@pytest.mark.asyncio
async def test_mongodb_live_unreachable_endpoint():
    """Verify unreachable MongoDB host/port returns connection failure with sanitized details."""
    unreachable_config = ConnectionConfig(
        host="localhost",
        port=27019,  # Unused port
        database_name="altr_test_db",
        username="user",
        password="password123",
    )
    connector = MongoDBConnector(unreachable_config, timeout_sec=1.0)
    result = await connector.test_connection()

    assert result.success is False
    assert result.latency_ms is not None
    assert "password123" not in result.message
    assert "password123" not in (result.error_details or "")


@pytest.mark.asyncio
async def test_mongodb_live_schema_discovery():
    """Verify live schema discovery against MongoDB test container with rich BSON document samples."""
    if not await _is_mongodb_available():
        pytest.skip("MongoDB test container not available on port 27017")

    from bson import Decimal128, ObjectId
    from datetime import datetime, timezone

    connector = MongoDBConnector(MONGO_CONFIG)
    await connector.initialize()
    try:
        db = connector._client["altr_test_db"]
        coll = db["live_discovery_test"]
        await coll.delete_many({})

        # Insert 3 diverse documents
        await coll.insert_many([
            {
                "_id": ObjectId("507f1f77bcf86cd799439011"),
                "username": "live_user_1",
                "email": "u1@example.com",
                "score": 100,
                "balance": Decimal128("250.50"),
                "created_at": datetime.now(timezone.utc),
                "tags": ["alpha", "beta"],
                "profile": {
                    "tier": "gold",
                    "geo": {
                        "city": "Bengaluru",
                        "active": True,
                    },
                },
            },
            {
                "_id": ObjectId("507f1f77bcf86cd799439012"),
                "username": "live_user_2",
                "score": 85,
                "profile": {
                    "tier": "silver",
                },
            },
        ])

        schema = await connector.discover_schema("src_live_1", "Live Mongo Source")

        assert schema.source_id == "src_live_1"
        assert schema.source_name == "Live Mongo Source"

        # Check entity discovery
        coll_entity = next((e for e in schema.entities if e.name == "live_discovery_test"), None)
        assert coll_entity is not None
        assert coll_entity.entity_type == "COLLECTION"
        assert coll_entity.primary_key == ["_id"]

        # Verify fields
        f_id = coll_entity.get_field("_id")
        assert f_id is not None
        assert f_id.is_primary_key is True
        assert f_id.nullable is False
        assert f_id.native_data_type == "objectId"

        f_user = coll_entity.get_field("username")
        assert f_user is not None
        assert f_user.nullable is False

        f_email = coll_entity.get_field("email")
        assert f_email is not None
        assert f_email.nullable is True  # missing in doc 2

        f_balance = coll_entity.get_field("balance")
        assert f_balance is not None
        assert f_balance.data_type == "DECIMAL"

        f_profile = coll_entity.get_field("profile")
        assert f_profile is not None
        assert f_profile.data_type == "JSON"

        f_tier = coll_entity.get_field("profile.tier")
        assert f_tier is not None
        assert f_tier.data_type == "STRING"

        f_city = coll_entity.get_field("profile.geo.city")
        assert f_city is not None
        assert f_city.data_type == "STRING"

        # Cleanup
        await coll.delete_many({})
    finally:
        await connector.close()


@pytest.mark.asyncio
async def test_mongodb_live_schema_snapshot_persistence():
    """Verify live MongoDB schema discovery persists and retrieves schema snapshots via SchemaService."""
    if not await _is_mongodb_available():
        pytest.skip("MongoDB test container not available on port 27017")

    from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
    from altr_stream.application.schema_service import SchemaService
    from altr_stream.domain.source import Source, SourceStatus, SourceType
    from altr_stream.infrastructure.database.models import Base
    from altr_stream.infrastructure.database.repository import SqliteSourceRepository

    engine = create_async_engine("sqlite+aiosqlite:///:memory:", echo=False)
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)

    session_factory = async_sessionmaker(engine, expire_on_commit=False, class_=AsyncSession)
    async with session_factory() as session:
        repo = SqliteSourceRepository(session)
        service = SchemaService(repo)

        # Register a MongoDB source
        source = Source(
            name="Live MongoDB Source",
            type=SourceType.MONGODB,
            host="localhost",
            port=27017,
            database_name="altr_test_db",
            username="altr_test_user",
            password="altr_test_pass",
            options={"authSource": "admin"},
            status=SourceStatus.UNKNOWN,
        )
        created_source = await repo.create(source)
        await session.commit()

        # Execute discovery and snapshot persistence
        discovered_schema = await service.discover_and_save_schema(created_source.id)
        await session.commit()

        assert discovered_schema.source_id == created_source.id
        assert discovered_schema.entity_count > 0

        # Retrieve the latest snapshot from SQLite repository
        retrieved_schema = await service.get_latest_schema(created_source.id)
        assert retrieved_schema is not None
        assert retrieved_schema.source_id == created_source.id
        assert retrieved_schema.entity_count == discovered_schema.entity_count

        # Check source status updated to ACTIVE
        updated_source = await repo.get_by_id(created_source.id)
        assert updated_source is not None
        assert updated_source.status == SourceStatus.ACTIVE
