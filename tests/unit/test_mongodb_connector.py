"""Unit tests for MongoDBConnector lifecycle, configuration, capabilities, and connection testing."""

from unittest.mock import AsyncMock, MagicMock, patch
from bson import ObjectId
import pytest

from altr_stream.domain.connector import ParameterStyle
from altr_stream.domain.errors import QueryExecutionError
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
async def test_mongodb_discover_schema_mock_success(mongodb_config: ConnectionConfig):
    """Test successful schema discovery using mock AsyncMongoClient and cursor."""
    connector = MongoDBConnector(mongodb_config)

    mock_cursor = MagicMock()
    mock_cursor.sort.return_value = mock_cursor
    mock_cursor.limit.return_value = mock_cursor
    mock_cursor.to_list = AsyncMock(return_value=[
        {"_id": ObjectId("507f1f77bcf86cd799439011"), "username": "alice", "score": 95},
        {"_id": ObjectId("507f1f77bcf86cd799439012"), "username": "bob", "score": 88, "role": "admin"},
    ])

    mock_coll = MagicMock()
    mock_coll.find.return_value = mock_cursor

    mock_db = MagicMock()
    mock_db.list_collection_names = AsyncMock(return_value=["users", "system.views", "system.profile"])
    mock_db.__getitem__.return_value = mock_coll

    mock_client = MagicMock()
    mock_client.__getitem__.return_value = mock_db
    mock_client.close = AsyncMock()

    with patch.object(connector, "_create_client", return_value=mock_client):
        schema = await connector.discover_schema("src_1", "MongoDB Test")

        assert schema.source_id == "src_1"
        assert schema.source_name == "MongoDB Test"
        assert schema.entity_count == 1
        entity = schema.entities[0]
        assert entity.name == "users"
        assert entity.entity_type == "COLLECTION"

        field_names = [f.name for f in entity.fields]
        assert field_names == ["_id", "role", "score", "username"]

        mock_coll.find.assert_called_once_with({})
        mock_cursor.sort.assert_called_once_with("_id", 1)
        mock_cursor.limit.assert_called_once_with(100)
        mock_client.close.assert_awaited_once()


@pytest.mark.asyncio
async def test_mongodb_discover_schema_sanitizes_errors(mongodb_config: ConnectionConfig):
    """Test discover_schema wraps errors in SchemaDiscoveryError and sanitizes passwords."""
    connector = MongoDBConnector(mongodb_config)

    mock_client = MagicMock()
    mock_db = MagicMock()
    mock_db.list_collection_names = AsyncMock(
        side_effect=Exception(f"Failed to authenticate user altr_test_user with password {mongodb_config.password}")
    )
    mock_client.__getitem__.return_value = mock_db
    mock_client.close = AsyncMock()

    with patch.object(connector, "_create_client", return_value=mock_client):
        with pytest.raises(Exception) as exc_info:
            await connector.discover_schema("src_1", "MongoDB Test")

        err_msg = str(exc_info.value)
        assert "super_secret_mongo_password" not in err_msg
        assert "••••••••" in err_msg
        mock_client.close.assert_awaited_once()


@pytest.mark.asyncio
async def test_mongodb_execute_query_find(mongodb_config: ConnectionConfig):
    """Test find execution with filters, sorting, limit, and normalized results."""
    from bson import Decimal128
    from datetime import datetime, timezone

    connector = MongoDBConnector(mongodb_config)

    mock_cursor = MagicMock()
    mock_cursor.sort.return_value = mock_cursor
    mock_cursor.skip.return_value = mock_cursor
    mock_cursor.limit.return_value = mock_cursor
    mock_cursor.to_list = AsyncMock(return_value=[
        {
            "_id": ObjectId("507f1f77bcf86cd799439011"),
            "username": "alice",
            "balance": Decimal128("120.50"),
            "created_at": datetime(2026, 9, 16, 8, 0, 0, tzinfo=timezone.utc),
            "role": "admin",
        }
    ])

    mock_coll = MagicMock()
    mock_coll.find.return_value = mock_cursor
    mock_db = MagicMock()
    mock_db.__getitem__.return_value = mock_coll
    mock_client = MagicMock()
    mock_client.__getitem__.return_value = mock_db
    mock_client.close = AsyncMock()

    with patch.object(connector, "_create_client", return_value=mock_client):
        spec = {
            "collection": "users",
            "filter": {"role": "admin"},
            "projection": {"_id": 1, "username": 1, "balance": 1, "created_at": 1, "role": 1},
            "sort": [("created_at", -1)],
            "limit": 10,
            "skip": 0,
        }
        res = await connector.execute_query("mongodb:find", parameters=[spec])

        assert res.row_count == 1
        assert res.affected_rows is None
        assert res.columns == ["_id", "username", "balance", "created_at", "role"]
        assert len(res.rows) == 1
        assert res.rows[0]["_id"] == "507f1f77bcf86cd799439011"
        assert res.rows[0]["username"] == "alice"
        assert res.rows[0]["balance"] == Decimal128("120.50").to_decimal()
        assert res.rows[0]["created_at"] == datetime(2026, 9, 16, 8, 0, 0, tzinfo=timezone.utc)
        assert res.execution_time_ms >= 0

        mock_coll.find.assert_called_once_with(
            filter={"role": "admin"},
            projection={"_id": 1, "username": 1, "balance": 1, "created_at": 1, "role": 1},
        )
        mock_cursor.sort.assert_called_once_with([("created_at", -1)])
        mock_cursor.limit.assert_called_once_with(10)
        mock_client.close.assert_awaited_once()


@pytest.mark.asyncio
async def test_mongodb_execute_query_insert_many(mongodb_config: ConnectionConfig):
    """Test insert_many execution returning inserted count, affected rows, and inserted IDs."""
    connector = MongoDBConnector(mongodb_config)

    mock_insert_result = MagicMock()
    mock_insert_result.inserted_ids = [
        ObjectId("507f1f77bcf86cd799439011"),
        ObjectId("507f1f77bcf86cd799439012"),
    ]

    mock_coll = MagicMock()
    mock_coll.insert_many = AsyncMock(return_value=mock_insert_result)
    mock_db = MagicMock()
    mock_db.__getitem__.return_value = mock_coll
    mock_client = MagicMock()
    mock_client.__getitem__.return_value = mock_db
    mock_client.close = AsyncMock()

    with patch.object(connector, "_create_client", return_value=mock_client):
        spec = {
            "collection": "users",
            "documents": [
                {"username": "user1"},
                {"username": "user2"},
            ],
            "ordered": True,
        }
        res = await connector.execute_query("mongodb:insert_many", parameters=[spec])

        assert res.row_count == 2
        assert res.affected_rows == 2
        assert res.columns == ["_id"]
        assert len(res.rows) == 2
        assert res.rows[0]["_id"] == "507f1f77bcf86cd799439011"
        assert res.rows[1]["_id"] == "507f1f77bcf86cd799439012"
        assert "Inserted 2 document(s)" in (res.message or "")

        mock_coll.insert_many.assert_awaited_once_with(
            [{"username": "user1"}, {"username": "user2"}],
            ordered=True,
        )
        mock_client.close.assert_awaited_once()


@pytest.mark.asyncio
async def test_mongodb_execute_query_update_many(mongodb_config: ConnectionConfig):
    """Test update_many execution returning modified count as affected rows."""
    connector = MongoDBConnector(mongodb_config)

    mock_update_result = MagicMock()
    mock_update_result.modified_count = 3
    mock_update_result.matched_count = 3

    mock_coll = MagicMock()
    mock_coll.update_many = AsyncMock(return_value=mock_update_result)
    mock_db = MagicMock()
    mock_db.__getitem__.return_value = mock_coll
    mock_client = MagicMock()
    mock_client.__getitem__.return_value = mock_db
    mock_client.close = AsyncMock()

    with patch.object(connector, "_create_client", return_value=mock_client):
        spec = {
            "collection": "users",
            "filter": {"role": "guest"},
            "update": {"$set": {"status": "archived"}},
            "upsert": False,
        }
        res = await connector.execute_query("mongodb:update_many", parameters=[spec])

        assert res.row_count == 0
        assert res.affected_rows == 3
        assert res.columns == []
        assert res.rows == []
        assert "Updated 3 document(s)" in (res.message or "")

        mock_coll.update_many.assert_awaited_once_with(
            filter={"role": "guest"},
            update={"$set": {"status": "archived"}},
            upsert=False,
        )
        mock_client.close.assert_awaited_once()


@pytest.mark.asyncio
async def test_mongodb_execute_query_delete_many(mongodb_config: ConnectionConfig):
    """Test delete_many execution returning deleted count as affected rows."""
    connector = MongoDBConnector(mongodb_config)

    mock_delete_result = MagicMock()
    mock_delete_result.deleted_count = 4

    mock_coll = MagicMock()
    mock_coll.delete_many = AsyncMock(return_value=mock_delete_result)
    mock_db = MagicMock()
    mock_db.__getitem__.return_value = mock_coll
    mock_client = MagicMock()
    mock_client.__getitem__.return_value = mock_db
    mock_client.close = AsyncMock()

    with patch.object(connector, "_create_client", return_value=mock_client):
        spec = {
            "collection": "logs",
            "filter": {"level": "debug"},
        }
        res = await connector.execute_query("mongodb:delete_many", parameters=[spec])

        assert res.row_count == 0
        assert res.affected_rows == 4
        assert res.columns == []
        assert res.rows == []
        assert "Deleted 4 document(s)" in (res.message or "")

        mock_coll.delete_many.assert_awaited_once_with(filter={"level": "debug"})
        mock_client.close.assert_awaited_once()


@pytest.mark.asyncio
async def test_mongodb_execute_batch_success(mongodb_config: ConnectionConfig):
    """Test execute_batch executing multiple commands sequentially."""
    connector = MongoDBConnector(mongodb_config)

    mock_insert_result = MagicMock()
    mock_insert_result.inserted_ids = [ObjectId("507f1f77bcf86cd799439011")]

    mock_update_result = MagicMock()
    mock_update_result.modified_count = 2
    mock_update_result.matched_count = 2

    mock_coll = MagicMock()
    mock_coll.insert_many = AsyncMock(return_value=mock_insert_result)
    mock_coll.update_many = AsyncMock(return_value=mock_update_result)
    mock_db = MagicMock()
    mock_db.__getitem__.return_value = mock_coll
    mock_client = MagicMock()
    mock_client.__getitem__.return_value = mock_db
    mock_client.close = AsyncMock()

    with patch.object(connector, "_create_client", return_value=mock_client):
        batch = [
            ("mongodb:insert_many", [{"collection": "users", "documents": [{"name": "alice"}]}]),
            ("mongodb:update_many", [{"collection": "users", "filter": {}, "update": {"$set": {"active": True}}}]),
        ]
        res = await connector.execute_batch(batch)

        assert res.affected_rows == 3  # 1 inserted + 2 modified
        mock_client.close.assert_awaited_once()


@pytest.mark.asyncio
async def test_mongodb_execute_query_validation_and_error_sanitization(mongodb_config: ConnectionConfig):
    """Test that invalid command specs and driver errors are caught, wrapped in QueryExecutionError, and sanitized."""
    connector = MongoDBConnector(mongodb_config)

    # 1. Missing collection
    with pytest.raises(QueryExecutionError) as exc_info1:
        await connector.execute_query("mongodb:find", parameters=[{"filter": {}}])
    assert "collection" in str(exc_info1.value)

    # 2. Unsupported operation
    with pytest.raises(QueryExecutionError) as exc_info2:
        await connector.execute_query("mongodb:drop_database", parameters=[{"collection": "users"}])
    assert "Unsupported MongoDB operation" in str(exc_info2.value)

    # 3. Missing parameters dictionary
    with pytest.raises(QueryExecutionError) as exc_info3:
        await connector.execute_query("mongodb:find", parameters=[])
    assert "dictionary specification" in str(exc_info3.value)

    # 4. Driver exception sanitizes passwords
    mock_coll = MagicMock()
    mock_coll.find.side_effect = Exception(
        f"Server error with password {mongodb_config.password} on mongodb://user:{mongodb_config.password}@localhost:27017"
    )
    mock_db = MagicMock()
    mock_db.__getitem__.return_value = mock_coll
    mock_client = MagicMock()
    mock_client.__getitem__.return_value = mock_db
    mock_client.close = AsyncMock()

    with patch.object(connector, "_create_client", return_value=mock_client):
        with pytest.raises(QueryExecutionError) as exc_info4:
            await connector.execute_query("mongodb:find", parameters=[{"collection": "users"}])

        err_msg = str(exc_info4.value)
        assert "super_secret_mongo_password" not in err_msg
        assert "••••••••" in err_msg
        mock_client.close.assert_awaited_once()

