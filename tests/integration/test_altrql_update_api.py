"""Integration tests for AltrQL v0.4 UPDATE endpoints across parse, bind, and execute against PostgreSQL."""

from unittest.mock import AsyncMock, patch
from httpx import AsyncClient
import pytest

from altr_stream.domain.query import QueryResult
from altr_stream.domain.schema import (
    EntitySchema,
    FieldSchema,
    SourceSchema,
    StandardDataType,
)
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


async def _setup_test_source_and_schema(client: AsyncClient) -> str:
    """Helper to create a source and populate its schema with mock data."""
    source_payload = {
        "name": "UPDATE Test Source",
        "type": "POSTGRESQL",
        "host": "localhost",
        "port": 5432,
        "database_name": "app_db",
        "username": "user",
        "password": "password",
        "test_connection_first": False,
    }
    create_res = await client.post("/api/v1/sources", json=source_payload)
    source_id = create_res.json()["id"]

    mock_schema = SourceSchema(
        source_id=source_id,
        source_name="UPDATE Test Source",
        entities=[
            EntitySchema(
                name="users",
                namespace="public",
                fields=[
                    FieldSchema(name="id", data_type=StandardDataType.INTEGER, native_data_type="int4", is_primary_key=True),
                    FieldSchema(name="username", data_type=StandardDataType.STRING, native_data_type="varchar"),
                    FieldSchema(name="email", data_type=StandardDataType.STRING, native_data_type="varchar", nullable=True),
                    FieldSchema(name="age", data_type=StandardDataType.INTEGER, native_data_type="int4", nullable=True),
                    FieldSchema(name="is_active", data_type=StandardDataType.BOOLEAN, native_data_type="bool"),
                ],
            )
        ],
    )

    with patch(
        "altr_stream.infrastructure.connectors.postgres.connector.PostgreSQLConnector.discover_schema",
        new=AsyncMock(return_value=mock_schema),
    ):
        discover_res = await client.post(f"/api/v1/sources/{source_id}/schema/discover")
        assert discover_res.status_code == 200

    return source_id


@pytest.mark.asyncio
async def test_parse_update_endpoint(client: AsyncClient):
    """Test /altrql/parse with valid and invalid UPDATE statements."""
    # Valid
    res_valid = await client.post(
        "/api/v1/altrql/parse",
        json={"query": 'UPDATE users ( email: "updated@example.com", is_active: TRUE ) WHERE { id = 1 };'},
    )
    assert res_valid.status_code == 200
    data_valid = res_valid.json()
    assert data_valid["success"] is True
    assert data_valid["ir"]["operation"] == "UPDATE"
    assert len(data_valid["ir"]["assignments"]) == 2
    assert data_valid["ir"]["where"] is not None

    # Missing WHERE
    res_invalid = await client.post(
        "/api/v1/altrql/parse",
        json={"query": 'UPDATE users ( is_active: FALSE );'},
    )
    assert res_invalid.status_code == 200
    data_invalid = res_invalid.json()
    assert data_invalid["success"] is False
    assert data_invalid["error"]["type"] == "AltrQueryParseError"
    assert "where" in data_invalid["error"]["message"].lower()


@pytest.mark.asyncio
async def test_bind_update_endpoint(client: AsyncClient):
    """Test /altrql/bind with UPDATE classifying query as CONSTRAINED."""
    source_id = await _setup_test_source_and_schema(client)

    query = 'UPDATE users ( is_active: FALSE ) WHERE { email = "alice@test.com" };'
    res = await client.post(
        "/api/v1/altrql/bind",
        json={"query": query, "source_id": source_id},
    )
    assert res.status_code == 200
    data = res.json()
    assert data["success"] is True
    assert data["classification"]["operation"] == "UPDATE"
    assert data["classification"]["mutation_scope"] == "CONSTRAINED"
    assert data["classification"]["requires_confirmation"] is False
    assert len(data["bound_ir"]["assignments"]) == 1


@pytest.mark.asyncio
async def test_execute_update_mock(client: AsyncClient):
    """Test /altrql/execute executing a mock UPDATE."""
    source_id = await _setup_test_source_and_schema(client)

    mock_result = QueryResult(
        columns=["id", "username", "email", "is_active"],
        rows=[{"id": 1, "username": "alice", "email": "alice_updated@test.com", "is_active": False}],
        row_count=1,
        affected_rows=1,
        execution_time_ms=2.1,
        message="UPDATE 1",
    )

    with patch(
        "altr_stream.infrastructure.connectors.postgres.connector.PostgreSQLConnector.execute_query",
        new=AsyncMock(return_value=mock_result),
    ):
        query = 'UPDATE users ( email: "alice_updated@test.com", is_active: FALSE ) WHERE { id = 1 };'
        res = await client.post("/api/v1/altrql/execute", json={"query": query, "source_id": source_id})
        assert res.status_code == 200
        data = res.json()
        assert data["success"] is True
        assert data["physical_query"]["query"] == 'UPDATE "public"."users" SET "email" = $1, "is_active" = $2 WHERE "id" = $3 RETURNING *;'
        assert data["physical_query"]["parameters"] == ["alice_updated@test.com", False, 1]
        assert len(data["rows"]) == 1
        assert data["rows"][0]["email"] == "alice_updated@test.com"
        assert data["metadata"]["affected_rows"] == 1


@pytest.mark.asyncio
async def test_live_postgres_update_lifecycle_and_persistence(client: AsyncClient):
    """End-to-end integration against live PostgreSQL verifying single-row, multi-row, zero-row UPDATE, and persistence."""
    if not await _is_postgres_available():
        pytest.skip("PostgreSQL test container not available on port 5432")

    connector = PostgreSQLConnector(PG_CONFIG)

    # Setup clean table
    await connector.execute_query("DROP TABLE IF EXISTS test_update_users;")
    await connector.execute_query("""
    CREATE TABLE test_update_users (
        id SERIAL PRIMARY KEY,
        username VARCHAR(50) UNIQUE NOT NULL,
        email VARCHAR(100) NOT NULL,
        is_active BOOLEAN NOT NULL DEFAULT TRUE,
        age INT
    );
    """)

    # Register live source in API
    source_payload = {
        "name": "Live Postgres UPDATE Test Source",
        "type": "POSTGRESQL",
        "host": "localhost",
        "port": 5432,
        "database_name": "altr_test_db",
        "username": "altr_test_user",
        "password": "altr_test_pass",
        "test_connection_first": False,
    }
    create_res = await client.post("/api/v1/sources", json=source_payload)
    assert create_res.status_code == 201
    source_id = create_res.json()["id"]

    # Discover schema
    disc_res = await client.post(f"/api/v1/sources/{source_id}/schema/discover")
    assert disc_res.status_code == 200

    try:
        # 1. Seed records via batch CREATE
        seed_query = """
        CREATE test_update_users (
            (username: "alice", email: "alice@example.com", is_active: TRUE, age: 25),
            (username: "bob", email: "bob@example.com", is_active: TRUE, age: 30),
            (username: "carol", email: "carol@example.com", is_active: TRUE, age: 35)
        );
        """
        seed_res = await client.post("/api/v1/altrql/execute", json={"query": seed_query, "source_id": source_id})
        assert seed_res.status_code == 200
        assert seed_res.json()["success"] is True

        # 2. Single-record UPDATE
        q_single = """
        UPDATE test_update_users (
            username: "alice_updated",
            age: 26
        ) WHERE {
            email = "alice@example.com"
        };
        """
        res_single = await client.post("/api/v1/altrql/execute", json={"query": q_single, "source_id": source_id})
        assert res_single.status_code == 200
        data_single = res_single.json()
        assert data_single["success"] is True
        assert len(data_single["rows"]) == 1
        assert data_single["rows"][0]["username"] == "alice_updated"
        assert data_single["rows"][0]["age"] == 26
        assert data_single["metadata"]["affected_rows"] == 1

        # Verify persistence via GET
        get_res = await client.post(
            "/api/v1/altrql/execute",
            json={"query": 'GET test_update_users WHERE { email = "alice@example.com" };', "source_id": source_id},
        )
        assert get_res.json()["rows"][0]["username"] == "alice_updated"

        # 3. Multi-row set-based UPDATE via ValueSet
        q_multi = """
        UPDATE test_update_users (
            is_active: FALSE
        ) WHERE {
            email = {
                "bob@example.com",
                "carol@example.com"
            }
        };
        """
        res_multi = await client.post("/api/v1/altrql/execute", json={"query": q_multi, "source_id": source_id})
        assert res_multi.status_code == 200
        data_multi = res_multi.json()
        assert data_multi["success"] is True
        assert len(data_multi["rows"]) == 2
        assert data_multi["metadata"]["affected_rows"] == 2
        assert all(r["is_active"] is False for r in data_multi["rows"])

        # 4. Zero-row UPDATE
        q_zero = """
        UPDATE test_update_users (
            is_active: FALSE
        ) WHERE {
            email = "nonexistent@example.com"
        };
        """
        res_zero = await client.post("/api/v1/altrql/execute", json={"query": q_zero, "source_id": source_id})
        assert res_zero.status_code == 200
        data_zero = res_zero.json()
        assert data_zero["success"] is True
        assert data_zero["rows"] == []
        assert data_zero["metadata"]["row_count"] == 0
        assert data_zero["metadata"]["affected_rows"] == 0

    finally:
        await connector.execute_query("DROP TABLE IF EXISTS test_update_users;")
