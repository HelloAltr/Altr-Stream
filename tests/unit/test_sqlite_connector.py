"""Unit tests for SQLiteConnector schema discovery, connection testing, and execution."""

import aiosqlite
import pytest

from altr_stream.domain.connector import ParameterStyle
from altr_stream.domain.schema import StandardDataType
from altr_stream.domain.source import ConnectionConfig, SourceType
from altr_stream.infrastructure.connectors.factory import ConnectorFactory
from altr_stream.infrastructure.connectors.sqlite.connector import SQLiteConnector


@pytest.fixture
async def sqlite_test_db(tmp_path):
    """Create a temporary SQLite database with test schema and data."""
    db_path = str(tmp_path / "test_source.db")
    async with aiosqlite.connect(db_path) as conn:
        await conn.execute("""
            CREATE TABLE categories (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                code TEXT NOT NULL UNIQUE,
                name TEXT NOT NULL,
                description TEXT
            );
        """)
        await conn.execute("""
            CREATE TABLE products (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                sku TEXT NOT NULL UNIQUE,
                name TEXT NOT NULL,
                category_id INTEGER REFERENCES categories(id),
                price REAL NOT NULL,
                stock_quantity INTEGER DEFAULT 0 NOT NULL,
                is_available INTEGER DEFAULT 1 NOT NULL,
                metadata TEXT,
                created_at TEXT DEFAULT CURRENT_TIMESTAMP NOT NULL
            );
        """)
        await conn.execute("""
            INSERT INTO categories (code, name, description) VALUES
            ('ELEC', 'Electronics', 'Gadgets and hardware'),
            ('BOOK', 'Books', NULL);
        """)
        await conn.execute("""
            INSERT INTO products (sku, name, category_id, price, stock_quantity, is_available, metadata) VALUES
            ('PROD-1', 'Laptop M3', 1, 1999.99, 10, 1, '{"tier": "pro"}'),
            ('PROD-2', 'Clean Code Book', 2, 45.00, 50, 1, NULL);
        """)
        await conn.commit()

    return db_path


@pytest.mark.asyncio
async def test_sqlite_connector_registered():
    assert SourceType.SQLITE in ConnectorFactory.supported_types()
    config = ConnectionConfig(file_path=":memory:")
    connector = ConnectorFactory.get_connector(SourceType.SQLITE, config)
    assert isinstance(connector, SQLiteConnector)


@pytest.mark.asyncio
async def test_sqlite_connection_test(sqlite_test_db):
    config = ConnectionConfig(file_path=sqlite_test_db)
    connector = SQLiteConnector(config)
    res = await connector.test_connection()
    assert res.success is True
    assert "Connected successfully to SQLite" in res.message
    assert res.server_version is not None


@pytest.mark.asyncio
async def test_sqlite_capabilities():
    config = ConnectionConfig(file_path=":memory:")
    connector = SQLiteConnector(config)
    caps = connector.get_capabilities()
    assert caps.schema_discovery is True
    assert caps.read is True
    assert caps.write is True
    assert caps.custom_query is True
    assert caps.parameter_style == ParameterStyle.POSITIONAL_QMARK
    assert "TABLE" in caps.entity_types


@pytest.mark.asyncio
async def test_sqlite_schema_discovery(sqlite_test_db):
    config = ConnectionConfig(file_path=sqlite_test_db)
    connector = SQLiteConnector(config)

    schema = await connector.discover_schema(source_id="src_sqlite_1", source_name="Test SQLite")
    assert schema.source_id == "src_sqlite_1"
    assert schema.source_name == "Test SQLite"
    assert schema.entity_count == 2

    # Check categories table
    cat_entity = next(e for e in schema.entities if e.name == "categories")
    assert cat_entity.entity_type == "TABLE"
    assert cat_entity.primary_key == ["id"]
    code_field = cat_entity.get_field("code")
    assert code_field is not None
    assert code_field.data_type == StandardDataType.STRING
    assert code_field.nullable is False

    desc_field = cat_entity.get_field("description")
    assert desc_field is not None
    assert desc_field.nullable is True

    # Check products table
    prod_entity = next(e for e in schema.entities if e.name == "products")
    price_field = prod_entity.get_field("price")
    assert price_field is not None
    assert price_field.data_type == StandardDataType.FLOAT


@pytest.mark.asyncio
async def test_sqlite_execute_query_read(sqlite_test_db):
    config = ConnectionConfig(file_path=sqlite_test_db)
    connector = SQLiteConnector(config)

    res = await connector.execute_query("SELECT * FROM categories ORDER BY id ASC;")
    assert res.row_count == 2
    assert res.columns == ["id", "code", "name", "description"]
    assert res.rows[0]["code"] == "ELEC"
    assert res.rows[0]["description"] == "Gadgets and hardware"
    assert res.rows[1]["description"] is None


@pytest.mark.asyncio
async def test_sqlite_execute_query_with_parameters(sqlite_test_db):
    config = ConnectionConfig(file_path=sqlite_test_db)
    connector = SQLiteConnector(config)

    res = await connector.execute_query(
        "SELECT id, sku, price FROM products WHERE price > ? ORDER BY price DESC;",
        parameters=[100.0],
    )
    assert res.row_count == 1
    assert res.rows[0]["sku"] == "PROD-1"
    assert res.rows[0]["price"] == 1999.99


@pytest.mark.asyncio
async def test_sqlite_execute_batch(sqlite_test_db):
    config = ConnectionConfig(file_path=sqlite_test_db)
    connector = SQLiteConnector(config)

    queries = [
        ("INSERT INTO categories (code, name) VALUES (?, ?);", ["FOOD", "Groceries"]),
        ("INSERT INTO categories (code, name) VALUES (?, ?);", ["TOYS", "Kids Toys"]),
    ]
    res = await connector.execute_batch(queries)
    assert res.affected_rows == 2

    verify_res = await connector.execute_query("SELECT COUNT(*) AS cnt FROM categories;")
    assert verify_res.rows[0]["cnt"] == 4
