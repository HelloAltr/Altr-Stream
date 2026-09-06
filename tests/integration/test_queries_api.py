"""Integration tests for the Query Execution API endpoint."""

from unittest.mock import AsyncMock, patch
from httpx import AsyncClient
import pytest
from altr_stream.domain.query import QueryResult


@pytest.mark.asyncio
async def test_execute_query_api_success(client: AsyncClient):
    # 1. Register a test source
    source_payload = {
        "name": "Query Test DB",
        "type": "POSTGRESQL",
        "host": "localhost",
        "port": 5432,
        "database_name": "query_db",
        "username": "postgres",
        "password": "password",
    }
    src_res = await client.post("/api/v1/sources", json=source_payload)
    assert src_res.status_code == 201
    source_id = src_res.json()["id"]

    # 2. Mock connector execute_query
    mock_result = QueryResult(
        columns=["id", "username", "role"],
        rows=[
            {"id": 1, "username": "admin", "role": "SUPERADMIN"},
            {"id": 2, "username": "operator", "role": "ADMIN"},
        ],
        row_count=2,
        execution_time_ms=18.4,
    )

    with patch(
        "altr_stream.infrastructure.connectors.postgres.connector.PostgreSQLConnector.execute_query",
        new=AsyncMock(return_value=mock_result),
    ):
        query_payload = {
            "source_id": source_id,
            "query": "SELECT id, username, role FROM users LIMIT 10;",
        }
        res = await client.post("/api/v1/queries/execute", json=query_payload)
        assert res.status_code == 200
        data = res.json()
        assert data["success"] is True
        assert data["columns"] == ["id", "username", "role"]
        assert len(data["rows"]) == 2
        assert data["rows"][0]["username"] == "admin"
        assert data["metadata"]["row_count"] == 2
        assert data["metadata"]["execution_time_ms"] == 18.4


@pytest.mark.asyncio
async def test_execute_query_api_source_not_found(client: AsyncClient):
    res = await client.post(
        "/api/v1/queries/execute",
        json={"source_id": "missing-uuid-1234", "query": "SELECT 1;"},
    )
    assert res.status_code == 404
    assert "not found" in res.json()["detail"]


@pytest.mark.asyncio
async def test_execute_query_api_read_only_rejection(client: AsyncClient):
    source_payload = {
        "name": "Write Test DB",
        "type": "POSTGRESQL",
        "host": "localhost",
        "port": 5432,
        "database_name": "db",
        "username": "u",
        "password": "p",
    }
    src_res = await client.post("/api/v1/sources", json=source_payload)
    source_id = src_res.json()["id"]

    # Attempt write query
    res = await client.post(
        "/api/v1/queries/execute",
        json={"source_id": source_id, "query": "DROP TABLE critical_data;"},
    )
    assert res.status_code == 400
    assert "read-only" in res.json()["detail"].lower()
