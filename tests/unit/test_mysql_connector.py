"""Unit tests for MySQLConnector lifecycle, introspection, and execution."""

from unittest.mock import AsyncMock, MagicMock, patch
import pytest

from altr_stream.domain.connector import ParameterStyle
from altr_stream.domain.errors import QueryExecutionError, SchemaDiscoveryError
from altr_stream.domain.source import ConnectionConfig, SourceType
from altr_stream.infrastructure.connectors.factory import ConnectorFactory
from altr_stream.infrastructure.connectors.mysql.connector import MySQLConnector, normalize_value


@pytest.fixture
def mysql_config():
    """Standard MySQL connection configuration fixture."""
    return ConnectionConfig(
        host="localhost",
        port=3306,
        database_name="test_shop",
        username="shop_admin",
        password="super_secret_password",
    )


def test_mysql_connector_factory_registration(mysql_config):
    """Test that MySQLConnector is correctly registered in ConnectorFactory for SourceType.MYSQL."""
    connector = ConnectorFactory.get_connector(SourceType.MYSQL, mysql_config)
    assert isinstance(connector, MySQLConnector)
    assert connector.config.host == "localhost"
    assert connector.config.port == 3306


def test_mysql_connector_capabilities(mysql_config):
    """Test reported capabilities of MySQL connector."""
    connector = MySQLConnector(mysql_config)
    caps = connector.get_capabilities()

    assert caps.schema_discovery is True
    assert caps.read is True
    assert caps.write is True
    assert caps.custom_query is True
    assert caps.supports_transactions is True
    assert caps.supports_returning is False
    assert caps.supports_date_only_equality is True
    assert caps.parameter_style == ParameterStyle.POSITIONAL_FORMAT
    assert "TABLE" in caps.entity_types
    assert "VIEW" in caps.entity_types


@pytest.mark.asyncio
async def test_mysql_test_connection_success(mysql_config):
    """Test successful test_connection reporting latency and version."""
    connector = MySQLConnector(mysql_config)

    mock_cursor = AsyncMock()
    mock_cursor.fetchone.return_value = {"VERSION()": "8.0.36-MySQL Community Server"}

    mock_conn = MagicMock()
    mock_cursor_context = AsyncMock()
    mock_cursor_context.__aenter__.return_value = mock_cursor
    mock_cursor_context.__aexit__.return_value = None
    mock_conn.cursor.return_value = mock_cursor_context

    with patch.object(connector, "_acquire_connection", new_callable=AsyncMock) as mock_acquire, \
         patch.object(connector, "_release_connection", new_callable=AsyncMock) as mock_release:
        mock_acquire.return_value = (mock_conn, False)

        result = await connector.test_connection()

        assert result.success is True
        assert "8.0.36" in (result.server_version or "")
        assert result.latency_ms is not None
        mock_release.assert_awaited_once()


@pytest.mark.asyncio
async def test_mysql_test_connection_failure_masks_password(mysql_config):
    """Test test_connection sanitizes credentials in error messages."""
    connector = MySQLConnector(mysql_config)

    with patch.object(connector, "_acquire_connection", new_callable=AsyncMock) as mock_acquire, \
         patch.object(connector, "_release_connection", new_callable=AsyncMock) as mock_release:
        mock_acquire.side_effect = Exception(f"Access denied for user 'shop_admin': {mysql_config.password}")

        result = await connector.test_connection()

        assert result.success is False
        assert "super_secret_password" not in result.message
        assert "••••••••" in result.message
        mock_release.assert_awaited_once()


@pytest.mark.asyncio
async def test_mysql_discover_schema(mysql_config):
    """Test discover_schema executing catalog queries and building SourceSchema."""
    connector = MySQLConnector(mysql_config)

    mock_cursor = AsyncMock()
    mock_cursor.fetchall.side_effect = [
        # 1. tables
        [{"table_name": "products", "table_type": "BASE TABLE", "table_comment": None}],
        # 2. columns
        [
            {
                "table_name": "products",
                "column_name": "id",
                "data_type": "bigint",
                "column_type": "bigint(20)",
                "is_nullable": "NO",
                "column_default": None,
                "ordinal_position": 1,
                "column_comment": None,
            },
            {
                "table_name": "products",
                "column_name": "name",
                "data_type": "varchar",
                "column_type": "varchar(255)",
                "is_nullable": "NO",
                "column_default": None,
                "ordinal_position": 2,
                "column_comment": None,
            },
        ],
        # 3. constraints
        [
            {
                "table_name": "products",
                "column_name": "id",
                "constraint_name": "PRIMARY",
                "constraint_type": "PRIMARY KEY",
                "referenced_table_name": None,
                "referenced_column_name": None,
                "ordinal_position": 1,
            }
        ],
    ]

    mock_conn = MagicMock()
    mock_cursor_context = AsyncMock()
    mock_cursor_context.__aenter__.return_value = mock_cursor
    mock_cursor_context.__aexit__.return_value = None
    mock_conn.cursor.return_value = mock_cursor_context

    with patch.object(connector, "_acquire_connection", new_callable=AsyncMock) as mock_acquire, \
         patch.object(connector, "_release_connection", new_callable=AsyncMock) as mock_release:
        mock_acquire.return_value = (mock_conn, False)

        schema = await connector.discover_schema("src_1", "Test MySQL Source")

        assert schema.source_id == "src_1"
        assert schema.entity_count == 1
        entity = schema.entities[0]
        assert entity.name == "products"
        assert entity.primary_key == ["id"]
        assert len(entity.fields) == 2
        mock_release.assert_awaited_once()


@pytest.mark.asyncio
async def test_mysql_discover_schema_error(mysql_config):
    """Test discover_schema error propagation and sanitization."""
    connector = MySQLConnector(mysql_config)

    with patch.object(connector, "_acquire_connection", new_callable=AsyncMock) as mock_acquire, \
         patch.object(connector, "_release_connection", new_callable=AsyncMock) as mock_release:
        mock_acquire.side_effect = Exception("Database unreachable")

        with pytest.raises(SchemaDiscoveryError) as exc_info:
            await connector.discover_schema("src_1", "Test MySQL Source")

        assert "Database unreachable" in str(exc_info.value)
        mock_release.assert_awaited_once()


@pytest.mark.asyncio
async def test_mysql_execute_query_select(mysql_config):
    """Test execute_query for result-returning SELECT query."""
    connector = MySQLConnector(mysql_config)

    mock_cursor = AsyncMock()
    mock_cursor.description = [("id",), ("name",), ("price",)]
    mock_cursor.fetchall.return_value = [
        {"id": 1, "name": "Laptop", "price": 999.99},
        {"id": 2, "name": "Mouse", "price": 25.50},
    ]

    mock_conn = MagicMock()
    mock_cursor_context = AsyncMock()
    mock_cursor_context.__aenter__.return_value = mock_cursor
    mock_cursor_context.__aexit__.return_value = None
    mock_conn.cursor.return_value = mock_cursor_context

    with patch.object(connector, "_acquire_connection", new_callable=AsyncMock) as mock_acquire, \
         patch.object(connector, "_release_connection", new_callable=AsyncMock) as mock_release:
        mock_acquire.return_value = (mock_conn, False)

        res = await connector.execute_query("SELECT id, name, price FROM products WHERE price > %s;", [20.0])

        assert res.columns == ["id", "name", "price"]
        assert res.row_count == 2
        assert res.affected_rows is None
        assert res.rows[0]["name"] == "Laptop"
        mock_cursor.execute.assert_awaited_once_with(
            "SELECT id, name, price FROM products WHERE price > %s;",
            (20.0,),
        )
        mock_release.assert_awaited_once()


@pytest.mark.asyncio
async def test_mysql_execute_query_mutation(mysql_config):
    """Test execute_query for mutation statement (UPDATE/DELETE)."""
    connector = MySQLConnector(mysql_config)

    mock_cursor = AsyncMock()
    mock_cursor.description = None
    mock_cursor.rowcount = 4

    mock_conn = MagicMock()
    mock_cursor_context = AsyncMock()
    mock_cursor_context.__aenter__.return_value = mock_cursor
    mock_cursor_context.__aexit__.return_value = None
    mock_conn.cursor.return_value = mock_cursor_context

    with patch.object(connector, "_acquire_connection", new_callable=AsyncMock) as mock_acquire, \
         patch.object(connector, "_release_connection", new_callable=AsyncMock) as mock_release:
        mock_acquire.return_value = (mock_conn, False)

        res = await connector.execute_query("UPDATE products SET price = price * 1.1 WHERE category = %s;", ["electronics"])

        assert res.columns == []
        assert res.rows == []
        assert res.row_count == 0
        assert res.affected_rows == 4
        mock_release.assert_awaited_once()


@pytest.mark.asyncio
async def test_mysql_execute_query_error(mysql_config):
    """Test execute_query error handling."""
    connector = MySQLConnector(mysql_config)

    with patch.object(connector, "_acquire_connection", new_callable=AsyncMock) as mock_acquire, \
         patch.object(connector, "_release_connection", new_callable=AsyncMock) as mock_release:
        mock_acquire.side_effect = Exception("Table 'unknown' doesn't exist")

        with pytest.raises(QueryExecutionError) as exc_info:
            await connector.execute_query("SELECT * FROM unknown;")

        assert "doesn't exist" in str(exc_info.value)
        mock_release.assert_awaited_once()


@pytest.mark.asyncio
async def test_mysql_execute_batch_success(mysql_config):
    """Test execute_batch in transaction."""
    connector = MySQLConnector(mysql_config)

    mock_cursor = AsyncMock()
    mock_cursor.description = None
    mock_cursor.rowcount = 1

    mock_conn = MagicMock()
    mock_conn.begin = AsyncMock()
    mock_conn.commit = AsyncMock()
    mock_cursor_context = AsyncMock()
    mock_cursor_context.__aenter__.return_value = mock_cursor
    mock_cursor_context.__aexit__.return_value = None
    mock_conn.cursor.return_value = mock_cursor_context

    with patch.object(connector, "_acquire_connection", new_callable=AsyncMock) as mock_acquire, \
         patch.object(connector, "_release_connection", new_callable=AsyncMock) as mock_release:
        mock_acquire.return_value = (mock_conn, False)

        queries = [
            ("INSERT INTO products (id, name) VALUES (%s, %s);", [1, "P1"]),
            ("INSERT INTO products (id, name) VALUES (%s, %s);", [2, "P2"]),
        ]
        res = await connector.execute_batch(queries)

        assert res.affected_rows == 2
        mock_conn.begin.assert_awaited_once()
        mock_conn.commit.assert_awaited_once()
        mock_release.assert_awaited_once()


@pytest.mark.asyncio
async def test_mysql_execute_batch_rollback_on_error(mysql_config):
    """Test execute_batch rolls back on error."""
    connector = MySQLConnector(mysql_config)

    mock_cursor = AsyncMock()
    mock_cursor.execute.side_effect = [None, Exception("Duplicate primary key")]

    mock_conn = MagicMock()
    mock_conn.begin = AsyncMock()
    mock_conn.rollback = AsyncMock()
    mock_cursor_context = AsyncMock()
    mock_cursor_context.__aenter__.return_value = mock_cursor
    mock_cursor_context.__aexit__.return_value = None
    mock_conn.cursor.return_value = mock_cursor_context

    with patch.object(connector, "_acquire_connection", new_callable=AsyncMock) as mock_acquire, \
         patch.object(connector, "_release_connection", new_callable=AsyncMock) as mock_release:
        mock_acquire.return_value = (mock_conn, False)

        queries = [
            ("INSERT INTO products (id) VALUES (%s);", [1]),
            ("INSERT INTO products (id) VALUES (%s);", [1]),
        ]
        with pytest.raises(QueryExecutionError):
            await connector.execute_batch(queries)

        mock_conn.begin.assert_awaited_once()
        mock_conn.rollback.assert_awaited_once()
        mock_release.assert_awaited_once()


def test_normalize_value():
    """Test value normalization helper."""
    assert normalize_value(None) is None
    assert normalize_value(42) == 42
    assert normalize_value("test") == "test"
    assert normalize_value(b"hello") == b"hello".hex()
    assert normalize_value({"a": 1, "b": None}) == {"a": 1, "b": None}
    assert normalize_value([1, 2, "3"]) == [1, 2, "3"]
