"""Live integration tests against PostgreSQL database verifying real execution and database reachability."""

import asyncio
from httpx import AsyncClient
import pytest
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


@pytest.fixture(scope="module")
def event_loop():
    loop = asyncio.new_event_loop()
    yield loop
    loop.close()


@pytest.mark.asyncio
async def test_postgres_live_result_queries():
    """Verify live execution of SELECT, WITH, EXPLAIN, SHOW queries against PostgreSQL without mocks."""
    if not await _is_postgres_available():
        pytest.skip("PostgreSQL test container not available on port 5432")

    connector = PostgreSQLConnector(PG_CONFIG)

    # 1. Simple SELECT
    res1 = await connector.execute_query("SELECT 1 as num;")
    assert res1.columns == ["num"]
    assert res1.rows == [{"num": 1}]
    assert res1.row_count == 1
    assert res1.affected_rows is None
    assert "SELECT" in (res1.message or "")

    # 2. SELECT with table query and limit
    res2 = await connector.execute_query("SELECT id, email FROM users LIMIT 3;")
    assert "id" in res2.columns
    assert "email" in res2.columns
    assert len(res2.rows) <= 3
    assert res2.affected_rows is None

    # 3. SELECT with string literal and semicolon
    res3 = await connector.execute_query("SELECT 'hello, world; test' as greeting;")
    assert res3.columns == ["greeting"]
    assert res3.rows == [{"greeting": "hello, world; test"}]

    # 4. WITH Common Table Expression
    res4 = await connector.execute_query("WITH cte AS (SELECT 42 as answer) SELECT answer FROM cte;")
    assert res4.columns == ["answer"]
    assert res4.rows == [{"answer": 42}]

    # 5. EXPLAIN query
    res5 = await connector.execute_query("EXPLAIN SELECT * FROM users;")
    assert len(res5.columns) == 1
    assert len(res5.rows) > 0

    # 6. SHOW query
    res6 = await connector.execute_query("SHOW timezone;")
    assert res6.columns == ["TimeZone"]
    assert len(res6.rows) == 1


@pytest.mark.asyncio
async def test_postgres_live_command_queries_and_reachability():
    """Verify live execution and database state mutations for CREATE, INSERT, UPDATE, DELETE, ALTER, DROP."""
    if not await _is_postgres_available():
        pytest.skip("PostgreSQL test container not available on port 5432")

    connector = PostgreSQLConnector(PG_CONFIG)

    # Clean up table if leftover from previous test
    try:
        await connector.execute_query("DROP TABLE IF EXISTS execution_probe_test;")
    except Exception:
        pass

    # 1. CREATE TABLE
    res_create = await connector.execute_query("CREATE TABLE execution_probe_test (id INTEGER, note TEXT);")
    assert res_create.columns == []
    assert res_create.rows == []
    assert res_create.row_count == 0
    assert res_create.message == "CREATE TABLE"

    # Verify table exists in PostgreSQL
    verify_create = await connector.execute_query(
        "SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'execution_probe_test') as tbl_exists;"
    )
    assert verify_create.rows == [{"tbl_exists": True}]

    # 2. INSERT records
    res_insert = await connector.execute_query(
        "INSERT INTO execution_probe_test (id, note) VALUES (1, 'alpha'), (2, 'beta'), (3, 'gamma');"
    )
    assert res_insert.affected_rows == 3
    assert res_insert.message == "INSERT 0 3"

    # 3. UPDATE record
    res_update = await connector.execute_query(
        "UPDATE execution_probe_test SET note = 'alpha_updated' WHERE id = 1;"
    )
    assert res_update.affected_rows == 1
    assert res_update.message == "UPDATE 1"

    # Verify update in PostgreSQL
    check_update = await connector.execute_query("SELECT note FROM execution_probe_test WHERE id = 1;")
    assert check_update.rows == [{"note": "alpha_updated"}]

    # 4. ALTER TABLE
    res_alter = await connector.execute_query(
        "ALTER TABLE execution_probe_test ADD COLUMN flag BOOLEAN DEFAULT false;"
    )
    assert res_alter.message == "ALTER TABLE"

    # 5. DELETE record
    res_delete = await connector.execute_query("DELETE FROM execution_probe_test WHERE id = 2;")
    assert res_delete.affected_rows == 1
    assert res_delete.message == "DELETE 1"

    # Verify remaining rows
    check_rows = await connector.execute_query("SELECT id FROM execution_probe_test ORDER BY id;")
    assert check_rows.rows == [{"id": 1}, {"id": 3}]

    # 6. DROP TABLE
    res_drop = await connector.execute_query("DROP TABLE execution_probe_test;")
    assert res_drop.message == "DROP TABLE"

    # Verify table no longer exists in PostgreSQL
    verify_drop = await connector.execute_query(
        "SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'execution_probe_test') as tbl_exists;"
    )
    assert verify_drop.rows == [{"tbl_exists": False}]


@pytest.mark.asyncio
async def test_api_live_postgres_execution(client: AsyncClient):
    """Verify live end-to-end execution through FastAPI endpoint against PostgreSQL."""
    if not await _is_postgres_available():
        pytest.skip("PostgreSQL test container not available on port 5432")

    # 1. Register PostgreSQL source in SQLite metadata
    source_payload = {
        "name": "Live PostgreSQL Source",
        "type": "POSTGRESQL",
        "host": PG_CONFIG.host,
        "port": PG_CONFIG.port,
        "database_name": PG_CONFIG.database_name,
        "username": PG_CONFIG.username,
        "password": PG_CONFIG.password,
    }
    src_res = await client.post("/api/v1/sources", json=source_payload)
    assert src_res.status_code == 201
    source_id = src_res.json()["id"]

    # 2. Execute SELECT query via API
    res_select = await client.post(
        "/api/v1/queries/execute",
        json={"source_id": source_id, "query": "SELECT * FROM users LIMIT 2;"},
    )
    assert res_select.status_code == 200
    data_select = res_select.json()
    assert data_select["success"] is True
    assert "id" in data_select["columns"]
    assert len(data_select["rows"]) <= 2
    assert data_select["metadata"]["row_count"] <= 2
    assert data_select["metadata"]["affected_rows"] is None

    # 3. Execute command query via API (disposable table)
    res_create = await client.post(
        "/api/v1/queries/execute",
        json={"source_id": source_id, "query": "CREATE TABLE api_probe_temp (id INT);"},
    )
    assert res_create.status_code == 200
    data_create = res_create.json()
    assert data_create["success"] is True
    assert data_create["columns"] == []
    assert data_create["rows"] == []
    assert data_create["metadata"]["message"] == "CREATE TABLE"

    # 4. Trigger Schema Discovery via API and verify api_probe_temp is discovered
    res_discover = await client.post(f"/api/v1/sources/{source_id}/schema/discover")
    assert res_discover.status_code == 200
    schema_data = res_discover.json()
    entity_names = [e["name"] for e in schema_data["entities"]]
    assert "api_probe_temp" in entity_names

    # 5. Drop the table via API
    res_drop = await client.post(
        "/api/v1/queries/execute",
        json={"source_id": source_id, "query": "DROP TABLE api_probe_temp;"},
    )
    assert res_drop.status_code == 200
    assert res_drop.json()["metadata"]["message"] == "DROP TABLE"

    # 6. Re-discover schema via API and verify api_probe_temp is gone
    res_discover_after = await client.post(f"/api/v1/sources/{source_id}/schema/discover")
    assert res_discover_after.status_code == 200
    entity_names_after = [e["name"] for e in res_discover_after.json()["entities"]]
    assert "api_probe_temp" not in entity_names_after


@pytest.mark.asyncio
async def test_postgres_live_altrql_temporal_execution(client: AsyncClient):
    """Verify end-to-end AltrQL query execution with temporal literals against live PostgreSQL."""
    if not await _is_postgres_available():
        pytest.skip("PostgreSQL test container not available on port 5432")

    # 1. Register PostgreSQL source in SQLite metadata
    source_payload = {
        "name": "Live AltrQL Temporal Source",
        "type": "POSTGRESQL",
        "host": PG_CONFIG.host,
        "port": PG_CONFIG.port,
        "database_name": PG_CONFIG.database_name,
        "username": PG_CONFIG.username,
        "password": PG_CONFIG.password,
    }
    src_res = await client.post("/api/v1/sources", json=source_payload)
    assert src_res.status_code == 201
    source_id = src_res.json()["id"]

    # 2. Discover schema
    disc_res = await client.post(f"/api/v1/sources/{source_id}/schema/discover")
    assert disc_res.status_code == 200

    # 3. Date-only equality query on TIMESTAMP field matching records created across the day
    res1 = await client.post(
        "/api/v1/altrql/execute",
        json={
            "source_id": source_id,
            "query": "GET users WHERE { created_at = @2026-09-06 };",
        },
    )
    assert res1.status_code == 200
    data1 = res1.json()
    assert data1["success"] is True
    assert data1["error"] is None
    assert data1["rows"] is not None
    # All 3 records on 2026-09-06 are returned regardless of time (06:41:16)
    assert len(data1["rows"]) == 3
    emails = {r["email"] for r in data1["rows"]}
    assert emails == {"alice@example.com", "bob@example.com", "carol@example.com"}
    assert data1["physical_query"]["parameters"] == ["2026-09-06T00:00:00", "2026-09-07T00:00:00"]

    # 4. Date-only equality query on TIMESTAMP field matching single record on 2026-09-08
    res_edith = await client.post(
        "/api/v1/altrql/execute",
        json={
            "source_id": source_id,
            "query": "GET users WHERE { created_at = @2026-09-08 };",
        },
    )
    assert res_edith.status_code == 200
    data_edith = res_edith.json()
    assert data_edith["success"] is True
    assert len(data_edith["rows"]) == 1
    assert data_edith["rows"][0]["email"] == "edith@example.com"

    # 5. Date-only equality query on date with zero records
    res_empty = await client.post(
        "/api/v1/altrql/execute",
        json={
            "source_id": source_id,
            "query": "GET users WHERE { created_at = @2026-09-07 };",
        },
    )
    assert res_empty.status_code == 200
    data_empty = res_empty.json()
    assert data_empty["success"] is True
    assert len(data_empty["rows"]) == 0

    # 6. Nested logical expression regression query with multiple temporal equalities
    nested_query = """
    GET users WHERE {
        NOT {
            is_active = FALSE,
            created_at = @2026-09-06
        } OR {
            is_active = TRUE,
            created_at = @2026-09-08
        }
    };
    """
    res2 = await client.post(
        "/api/v1/altrql/execute",
        json={"source_id": source_id, "query": nested_query},
    )
    assert res2.status_code == 200
    data2 = res2.json()
    assert data2["success"] is True
    assert data2["error"] is None
    assert data2["rows"] is not None
    assert len(data2["rows"]) > 0
    assert data2["physical_query"]["parameters"] == [
        False,
        "2026-09-06T00:00:00",
        "2026-09-07T00:00:00",
        True,
        "2026-09-08T00:00:00",
        "2026-09-09T00:00:00",
    ]
