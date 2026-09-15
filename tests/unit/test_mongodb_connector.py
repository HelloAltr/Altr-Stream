"""Unit tests for MongoDBConnector lifecycle, configuration, capabilities, and connection testing."""

from unittest.mock import AsyncMock, MagicMock, patch
import pytest

from altr_stream.domain.connector import ParameterStyle
from altr_stream.domain.source import ConnectionConfig, SourceType
from altr_stream.infrastructure.connectors.factory import ConnectorFactory
from altr_stream.infrastructure.connectors.mongodb.connector import MongoDBConnector


@pytest.fixture
def mongodb_config() -> ConnectionConfig:
    """Standard MongoDB connection configuration fixture."""
    return ConnectionConfig(
        host="localhost",
        port=27017,
        database_name="altr_test_db",
        username="altr_test_user",
        password="super_secret_mongo_password",
        options={"authSource": "admin", "directConnection": "true"},
    )


def test_mongodb_connector_factory_registration(mongodb_config: ConnectionConfig):
    """Test that MongoDBConnector is registered in ConnectorFactory for SourceType.MONGODB."""
    connector = ConnectorFactory.get_connector(SourceType.MONGODB, mongodb_config)
    assert isinstance(connector, MongoDBConnector)
    assert connector.config.host == "localhost"
    assert connector.config.port == 27017
    assert SourceType.MONGODB in ConnectorFactory.supported_types()


def test_mongodb_connector_capabilities(mongodb_config: ConnectionConfig):
    """Test reported capabilities of MongoDB connector."""
    connector = MongoDBConnector(mongodb_config)
    caps = connector.get_capabilities()

    assert caps.schema_discovery is True
    assert caps.read is True
    assert caps.write is True
    assert caps.cdc is False
    assert caps.batch_execution is True
    assert caps.streaming is False
    assert caps.custom_query is True
    assert caps.supports_transactions is False
    assert caps.supports_returning is False
    assert caps.supports_date_only_equality is True
    assert caps.parameter_style == ParameterStyle.DOCUMENT_BSON
    assert caps.max_batch_size == 1000
    assert caps.entity_types == ["COLLECTION"]
    assert "find" in caps.supported_operations
    assert "insert_many" in caps.supported_operations
    assert "update_many" in caps.supported_operations
    assert "delete_many" in caps.supported_operations


def test_mongodb_uri_builder_without_auth():
    """Test URI generation when no credentials are provided."""
    config = ConnectionConfig(host="mongo.example.com", port=27018, database_name="analytics")
    connector = MongoDBConnector(config)
    uri = connector._build_connection_uri()
    assert uri == "mongodb://mongo.example.com:27018/analytics"


def test_mongodb_uri_builder_with_auth_and_options(mongodb_config: ConnectionConfig):
    """Test URI generation with URL-quoted credentials and query options."""
    connector = MongoDBConnector(mongodb_config)
    uri = connector._build_connection_uri()
    assert "altr_test_user:super_secret_mongo_password@" in uri
    assert "localhost:27017/altr_test_db?" in uri
    assert "authSource=admin" in uri
    assert "directConnection=true" in uri


@pytest.mark.asyncio
async def test_mongodb_connector_lifecycle():
    """Test initialize and close lifecycle methods."""
    config = ConnectionConfig(host="localhost", port=27017, database_name="test_db")
    connector = MongoDBConnector(config)

    assert connector._is_initialized is False
    assert connector._client is None

    await connector.initialize()
    assert connector._is_initialized is True
    assert connector._client is not None

    client_ref = connector._client
    with patch.object(client_ref, "close", new_callable=AsyncMock) as mock_close:
        await connector.close()
        assert connector._is_initialized is False
        assert connector._client is None
        mock_close.assert_awaited_once()

    # Multiple calls to close should be safely idempotent
    await connector.close()
    assert connector._client is None


@pytest.mark.asyncio
async def test_mongodb_connector_async_context_manager():
    """Test async context manager __aenter__ and __aexit__."""
    config = ConnectionConfig(host="localhost", port=27017, database_name="test_db")
    connector = MongoDBConnector(config)

    async with connector:
        assert connector._is_initialized is True
        assert connector._client is not None
        # Mock client close on exit
        patcher = patch.object(connector._client, "close", new_callable=AsyncMock)
        mock_close = patcher.start()

    assert connector._is_initialized is False
    assert connector._client is None
    mock_close.assert_awaited_once()
    patcher.stop()


@pytest.mark.asyncio
async def test_mongodb_test_connection_success(mongodb_config: ConnectionConfig):
    """Test successful test_connection reporting latency and server version."""
    connector = MongoDBConnector(mongodb_config)

    mock_db = MagicMock()
    mock_db.command = AsyncMock(side_effect=[
        {"ok": 1.0},  # ping response
        {"version": "7.0.12", "ok": 1.0},  # buildInfo response
    ])

    mock_client = MagicMock()
    mock_client.__getitem__.return_value = mock_db
    mock_client.close = AsyncMock()

    with patch.object(connector, "_create_client", return_value=mock_client):
        result = await connector.test_connection()

        assert result.success is True
        assert "Connected successfully to MongoDB v7.0.12" in result.message
        assert result.server_version == "7.0.12"
        assert result.latency_ms is not None
        assert result.latency_ms >= 0
        mock_db.command.assert_any_await("ping")
        mock_db.command.assert_any_await("buildInfo")
        mock_client.close.assert_awaited_once()


@pytest.mark.asyncio
async def test_mongodb_test_connection_failure_masks_password(mongodb_config: ConnectionConfig):
    """Test test_connection sanitizes passwords in error details."""
    connector = MongoDBConnector(mongodb_config)

    mock_db = MagicMock()
    # Simulate auth failure with plaintext password embedded in exception message
    mock_db.command = AsyncMock(
        side_effect=Exception(
            f"Authentication failed for user altr_test_user with password {mongodb_config.password} at mongodb://altr_test_user:{mongodb_config.password}@localhost:27017/altr_test_db"
        )
    )

    mock_client = MagicMock()
    mock_client.__getitem__.return_value = mock_db
    mock_client.close = AsyncMock()

    with patch.object(connector, "_create_client", return_value=mock_client):
        result = await connector.test_connection()

        assert result.success is False
        assert "super_secret_mongo_password" not in result.message
        assert "super_secret_mongo_password" not in (result.error_details or "")
        assert "••••••••" in (result.error_details or "")
        mock_client.close.assert_awaited_once()


@pytest.mark.asyncio
async def test_mongodb_test_connection_buildinfo_fallback(mongodb_config: ConnectionConfig):
    """Test test_connection still succeeds if buildInfo fails but ping succeeds."""
    connector = MongoDBConnector(mongodb_config)

    mock_db = MagicMock()
    mock_db.command = AsyncMock(side_effect=[
        {"ok": 1.0},  # ping succeeds
        Exception("Unauthorized to run buildInfo"),  # buildInfo fails
    ])

    mock_client = MagicMock()
    mock_client.__getitem__.return_value = mock_db
    mock_client.close = AsyncMock()

    with patch.object(connector, "_create_client", return_value=mock_client):
        result = await connector.test_connection()

        assert result.success is True
        assert "Connected successfully to MongoDB" in result.message
        assert result.server_version is None
        mock_client.close.assert_awaited_once()


@pytest.mark.asyncio
async def test_mongodb_unimplemented_stubs(mongodb_config: ConnectionConfig):
    """Verify that schema discovery and query execution raise NotImplementedError in Phase 0.7.2a."""
    connector = MongoDBConnector(mongodb_config)

    with pytest.raises(NotImplementedError) as exc_info1:
        await connector.discover_schema("src_1", "MongoDB Test")
    assert "0.7.2b" in str(exc_info1.value)

    with pytest.raises(NotImplementedError) as exc_info2:
        await connector.execute_query("mongodb:find", [])
    assert "0.7.2c" in str(exc_info2.value)

    with pytest.raises(NotImplementedError) as exc_info3:
        await connector.execute_batch([])
    assert "0.7.2c" in str(exc_info3.value)
