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
