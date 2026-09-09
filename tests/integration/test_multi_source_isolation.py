"""Integration tests for multi-source isolation and independent execution across heterogeneous data sources."""

import os
import tempfile
import aiosqlite
from httpx import AsyncClient
import pytest

from altr_stream.domain.connector import ParameterStyle
from altr_stream.domain.source import ConnectionConfig
from altr_stream.infrastructure.connectors.postgres.connector import PostgreSQLConnector

PG_CONFIG = ConnectionConfig(
    host="localhost",
    port=5432,
    database_name="altr_test_db",
    username="altr_test_user",
    password="altr_test_pass",
)


async def _is_postgres_available() -> bool:
    try:
        conn = PostgreSQLConnector(PG_CONFIG, timeout_sec=2.0)
        res = await conn.test_connection()
        return res.success
    except Exception:
        return False


@pytest.fixture
def sqlite_test_db():
    """Create a temporary SQLite database file for testing."""
    fd, path = tempfile.mkstemp(suffix=".db")
    os.close(fd)
    yield path
    if os.path.exists(path):
        os.remove(path)


@pytest.fixture
def sqlite_test_db_2():
    """Create a second temporary SQLite database file for testing."""
    fd, path = tempfile.mkstemp(suffix="_2.db")
    os.close(fd)
    yield path
    if os.path.exists(path):
        os.remove(path)


@pytest.mark.asyncio
async def test_two_sqlite_sources_isolation(
    client: AsyncClient,
    sqlite_test_db: str,
    sqlite_test_db_2: str,
):
    """Test two distinct SQLite sources operating concurrently with complete data and schema isolation."""
    # 1. Initialize SQLite DB 1 (Inventory)
    async with aiosqlite.connect(sqlite_test_db) as db:
        await db.execute(
            "CREATE TABLE products (id INTEGER PRIMARY KEY, name TEXT NOT NULL, price REAL NOT NULL);"
        )
        await db.execute("INSERT INTO products (id, name, price) VALUES (1, 'Keyboard', 49.99);")
        await db.execute("INSERT INTO products (id, name, price) VALUES (2, 'Monitor', 299.99);")
        await db.commit()

    # 2. Initialize SQLite DB 2 (Analytics / Logs)
    async with aiosqlite.connect(sqlite_test_db_2) as db:
        await db.execute(
            "CREATE TABLE events (event_id INTEGER PRIMARY KEY, event_type TEXT NOT NULL, duration_ms INTEGER);"
        )
        await db.execute("INSERT INTO events (event_id, event_type, duration_ms) VALUES (100, 'LOGIN', 12);")
        await db.execute("INSERT INTO events (event_id, event_type, duration_ms) VALUES (101, 'QUERY', 85);")
        await db.commit()

    # 3. Register Source 1 via API
    res1 = await client.post(
        "/api/v1/sources",
        json={
            "name": "Inventory DB",
            "type": "SQLITE",
            "file_path": sqlite_test_db,
            "test_connection_first": True,
        },
    )
    assert res1.status_code == 201, res1.text
    src1 = res1.json()
    src1_id = src1["id"]
    assert src1["type"] == "SQLITE"
    assert src1["file_path"] == sqlite_test_db

    # 4. Register Source 2 via API
    res2 = await client.post(
        "/api/v1/sources",
        json={
            "name": "Analytics DB",
            "type": "SQLITE",
            "file_path": sqlite_test_db_2,
            "test_connection_first": True,
        },
    )
    assert res2.status_code == 201, res2.text
    src2 = res2.json()
    src2_id = src2["id"]
    assert src2["type"] == "SQLITE"
    assert src2["file_path"] == sqlite_test_db_2

    # 5. Discover schemas independently
    disc1 = await client.post(f"/api/v1/sources/{src1_id}/schema/discover")
    assert disc1.status_code == 200
    schema1 = disc1.json()
    assert any(e["name"] == "products" for e in schema1["entities"])
    assert not any(e["name"] == "events" for e in schema1["entities"])

    disc2 = await client.post(f"/api/v1/sources/{src2_id}/schema/discover")
    assert disc2.status_code == 200
    schema2 = disc2.json()
    assert any(e["name"] == "events" for e in schema2["entities"])
    assert not any(e["name"] == "products" for e in schema2["entities"])

    # 6. Query Source 1 with AltrQL
    q1_res = await client.post(
        "/api/v1/altrql/execute",
        json={"source_id": src1_id, "query": "GET products WHERE { price > 50.0 };"},
    )
    assert q1_res.status_code == 200
    q1_data = q1_res.json()
    assert q1_data["success"] is True
    assert q1_data["physical_query"]["dialect"] == "sqlite"
    assert len(q1_data["rows"]) == 1
    assert q1_data["rows"][0]["name"] == "Monitor"

    # 7. Query Source 2 with AltrQL
    q2_res = await client.post(
        "/api/v1/altrql/execute",
        json={"source_id": src2_id, "query": "GET events WHERE { duration_ms < 50 };"},
    )
    assert q2_res.status_code == 200
    q2_data = q2_res.json()
    assert q2_data["success"] is True
    assert q2_data["physical_query"]["dialect"] == "sqlite"
    assert len(q2_data["rows"]) == 1
    assert q2_data["rows"][0]["event_type"] == "LOGIN"

    # 8. Cross-source entity isolation: Querying Source 1 for Source 2 entity fails during binding
    cross_res = await client.post(
        "/api/v1/altrql/execute",
        json={"source_id": src1_id, "query": "GET events;"},
    )
    assert cross_res.status_code == 200
    cross_data = cross_res.json()
    assert cross_data["success"] is False
    assert cross_data["error"]["type"] == "UnknownEntityError"

    # 9. Mutate Source 1 and verify Source 2 is unaffected
    mut_res = await client.post(
        "/api/v1/altrql/execute",
        json={
            "source_id": src1_id,
            "query": 'CREATE products ( id: 3, name: "Mousepad", price: 15.5 );',
        },
    )
    assert mut_res.status_code == 200
    assert mut_res.json()["success"] is True, mut_res.json()

    # Check Source 1 has 3 items
    count1 = await client.post(
        "/api/v1/altrql/execute",
        json={"source_id": src1_id, "query": "GET products;"},
    )
    assert len(count1.json()["rows"]) == 3

    # Check Source 2 still has 2 items
    count2 = await client.post(
        "/api/v1/altrql/execute",
        json={"source_id": src2_id, "query": "GET events;"},
    )
    assert len(count2.json()["rows"]) == 2


@pytest.mark.asyncio
async def test_heterogeneous_postgres_and_sqlite_isolation(
    client: AsyncClient,
    sqlite_test_db: str,
):
    """Test concurrent operations across heterogeneous PostgreSQL and SQLite data sources."""
    if not await _is_postgres_available():
        pytest.skip("PostgreSQL test container not available on port 5432")

    # 1. Setup SQLite source
    async with aiosqlite.connect(sqlite_test_db) as db:
        await db.execute(
            "CREATE TABLE books (id INTEGER PRIMARY KEY, title TEXT NOT NULL, author TEXT NOT NULL);"
        )
        await db.execute("INSERT INTO books (id, title, author) VALUES (1, 'The Pragmatic Programmer', 'Hunt');")
        await db.commit()

    # 2. Register PostgreSQL source
    pg_reg = await client.post(
        "/api/v1/sources",
        json={
            "name": "Live Postgres Source",
            "type": "POSTGRESQL",
            "host": PG_CONFIG.host,
            "port": PG_CONFIG.port,
            "database_name": PG_CONFIG.database_name,
            "username": PG_CONFIG.username,
            "password": PG_CONFIG.password,
            "test_connection_first": True,
        },
    )
    assert pg_reg.status_code == 201
    pg_src_id = pg_reg.json()["id"]

    # 3. Register SQLite source
    sqlite_reg = await client.post(
        "/api/v1/sources",
        json={
            "name": "Local SQLite Books",
            "type": "SQLITE",
            "file_path": sqlite_test_db,
            "test_connection_first": True,
        },
    )
    assert sqlite_reg.status_code == 201
    sqlite_src_id = sqlite_reg.json()["id"]

    # 4. Check capabilities
    pg_caps = (await client.get(f"/api/v1/sources/{pg_src_id}/capabilities")).json()
    assert pg_caps["parameter_style"] == ParameterStyle.POSITIONAL_NUMERIC.value

    sqlite_caps = (await client.get(f"/api/v1/sources/{sqlite_src_id}/capabilities")).json()
    assert sqlite_caps["parameter_style"] == ParameterStyle.POSITIONAL_QMARK.value

    # 5. Discover schemas
    await client.post(f"/api/v1/sources/{pg_src_id}/schema/discover")
    await client.post(f"/api/v1/sources/{sqlite_src_id}/schema/discover")

    # 6. Execute PostgreSQL query (PostgreSQL lowering with $1)
    pg_q = await client.post(
        "/api/v1/altrql/execute",
        json={"source_id": pg_src_id, "query": 'GET users WHERE { email HAS "user" };'},
    )
    assert pg_q.status_code == 200
    pg_res = pg_q.json()
    assert pg_res["success"] is True, pg_res
    assert pg_res["physical_query"]["dialect"] == "postgresql"
    assert "$1" in pg_res["physical_query"]["query"]

    # 7. Execute SQLite query (SQLite lowering with ?)
    sqlite_q = await client.post(
        "/api/v1/altrql/execute",
        json={"source_id": sqlite_src_id, "query": 'GET books WHERE { author HAS "Hunt" };'},
    )
    assert sqlite_q.status_code == 200
    sqlite_res = sqlite_q.json()
    assert sqlite_res["success"] is True, sqlite_res
    assert sqlite_res["physical_query"]["dialect"] == "sqlite"
    assert "?" in sqlite_res["physical_query"]["query"]
    assert len(sqlite_res["rows"]) == 1
    assert sqlite_res["rows"][0]["title"] == "The Pragmatic Programmer"
    assert pg_res["physical_query"]["dialect"] == "postgresql"
    assert "$1" in pg_res["physical_query"]["query"]

    # 7. Execute SQLite query (SQLite lowering with ?)
    sqlite_q = await client.post(
        "/api/v1/altrql/execute",
        json={"source_id": sqlite_src_id, "query": 'GET books WHERE { author HAS "Hunt" };'},
    )
    assert sqlite_q.status_code == 200
    sqlite_res = sqlite_q.json()
    assert sqlite_res["success"] is True
    assert sqlite_res["physical_query"]["dialect"] == "sqlite"
    assert "?" in sqlite_res["physical_query"]["query"]
    assert len(sqlite_res["rows"]) == 1
    assert sqlite_res["rows"][0]["title"] == "The Pragmatic Programmer"
