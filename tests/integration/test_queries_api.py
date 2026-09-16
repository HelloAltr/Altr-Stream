"""Integration tests for the Query Execution API endpoint."""

from unittest.mock import AsyncMock, patch
from httpx import AsyncClient
import pytest
from altr_stream.domain.query import QueryResult


@pytest.mark.asyncio
async def test_execute_query_api_success_result_set(client: AsyncClient):
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
        assert data["metadata"]["affected_rows"] is None
        assert data["metadata"]["execution_time_ms"] == 18.4


@pytest.mark.asyncio
async def test_execute_query_api_success_mutation_command(client: AsyncClient):
    # 1. Register a test source
    source_payload = {
        "name": "Mutation Test DB",
        "type": "POSTGRESQL",
        "host": "localhost",
        "port": 5432,
        "database_name": "mutation_db",
        "username": "postgres",
        "password": "password",
    }
    src_res = await client.post("/api/v1/sources", json=source_payload)
    assert src_res.status_code == 201
    source_id = src_res.json()["id"]

    mock_result = QueryResult(
        columns=[],
        rows=[],
        row_count=0,
        affected_rows=5,
        message="UPDATE 5",
        execution_time_ms=22.3,
    )

    with patch(
        "altr_stream.infrastructure.connectors.postgres.connector.PostgreSQLConnector.execute_query",
        new=AsyncMock(return_value=mock_result),
    ):
        query_payload = {
            "source_id": source_id,
            "query": "UPDATE users SET active = true WHERE role = 'USER';",
        }
        res = await client.post("/api/v1/queries/execute", json=query_payload)
        assert res.status_code == 200
        data = res.json()
        assert data["success"] is True
        assert data["columns"] == []
        assert data["rows"] == []
        assert data["metadata"]["row_count"] == 0
        assert data["metadata"]["affected_rows"] == 5
        assert data["metadata"]["message"] == "UPDATE 5"
        assert data["metadata"]["execution_time_ms"] == 22.3


@pytest.mark.asyncio
async def test_execute_query_api_source_not_found(client: AsyncClient):
    res = await client.post(
        "/api/v1/queries/execute",
        json={"source_id": "missing-uuid-1234", "query": "SELECT 1;"},
    )
    assert res.status_code == 404
    assert "not found" in res.json()["detail"]


@pytest.mark.asyncio
async def test_execute_query_api_multi_statement_rejection(client: AsyncClient):
    source_payload = {
        "name": "Multi Statement DB",
        "type": "POSTGRESQL",
        "host": "localhost",
        "port": 5432,
        "database_name": "db",
        "username": "u",
        "password": "p",
    }
    src_res = await client.post("/api/v1/sources", json=source_payload)
    source_id = src_res.json()["id"]

    # Attempt multi-statement query
    res = await client.post(
        "/api/v1/queries/execute",
        json={"source_id": source_id, "query": "SELECT 1; DROP TABLE critical_data;"},
    )
    assert res.status_code == 400
    assert "multi-statement" in res.json()["detail"].lower()


@pytest.mark.asyncio
async def test_execute_query_api_mongodb_playground_find(client: AsyncClient):
    """Verify MongoDB Playground query reaches execution as query='mongodb:find' and parameters=[spec]."""
    source_payload = {
        "name": "Mongo Playground API DB",
        "type": "MONGODB",
        "host": "localhost",
        "port": 27017,
        "database_name": "altr_test_db",
        "username": "altr_test_user",
        "password": "altr_test_pass",
        "options": {"authSource": "admin"},
    }
    src_res = await client.post("/api/v1/sources", json=source_payload)
    assert src_res.status_code == 201
    source_id = src_res.json()["id"]

    mock_result = QueryResult(
        columns=["_id", "username", "role"],
        rows=[{"_id": "507f1f77bcf86cd799439011", "username": "alice", "role": "admin"}],
        row_count=1,
        execution_time_ms=10.5,
    )

    with patch(
        "altr_stream.infrastructure.connectors.mongodb.connector.MongoDBConnector.execute_query",
        new=AsyncMock(return_value=mock_result),
    ) as mock_exec:
        query_payload = {
            "source_id": source_id,
            "query": '{\n  "collection": "users",\n  "filter": {}\n}',
        }
        res = await client.post("/api/v1/queries/execute", json=query_payload)
        assert res.status_code == 200
        data = res.json()
        assert data["success"] is True
        assert data["columns"] == ["_id", "username", "role"]
        assert len(data["rows"]) == 1
        assert data["rows"][0]["username"] == "alice"
        assert data["metadata"]["row_count"] == 1
        assert data["metadata"]["execution_time_ms"] == 10.5

        mock_exec.assert_awaited_once_with(
            "mongodb:find",
            parameters=[{"collection": "users", "filter": {}}],
        )


@pytest.mark.asyncio
async def test_execute_query_api_mongodb_playground_projection_sort_limit_skip(client: AsyncClient):
    """Verify projection, sort, limit, and skip are forwarded to parameters."""
    source_payload = {
        "name": "Mongo Options API DB",
        "type": "MONGODB",
        "host": "localhost",
        "port": 27017,
        "database_name": "altr_test_db",
        "username": "altr_test_user",
        "password": "altr_test_pass",
        "options": {"authSource": "admin"},
    }
    src_res = await client.post("/api/v1/sources", json=source_payload)
    source_id = src_res.json()["id"]

    mock_result = QueryResult(
        columns=["_id", "name"],
        rows=[{"_id": "1", "name": "test"}],
        row_count=1,
        execution_time_ms=5.0,
    )

    with patch(
        "altr_stream.infrastructure.connectors.mongodb.connector.MongoDBConnector.execute_query",
        new=AsyncMock(return_value=mock_result),
    ) as mock_exec:
        query_payload = {
            "source_id": source_id,
            "query": """{
                "collection": "items",
                "filter": {"category": "electronics"},
                "projection": {"_id": 1, "name": 1},
                "sort": [["_id", -1]],
                "limit": 20,
                "skip": 5
            }""",
        }
        res = await client.post("/api/v1/queries/execute", json=query_payload)
        assert res.status_code == 200
        assert res.json()["success"] is True

        mock_exec.assert_awaited_once_with(
            "mongodb:find",
            parameters=[{
                "collection": "items",
                "filter": {"category": "electronics"},
                "projection": {"_id": 1, "name": 1},
                "sort": [["_id", -1]],
                "limit": 20,
                "skip": 5,
            }],
        )


@pytest.mark.asyncio
async def test_execute_query_api_mongodb_invalid_json(client: AsyncClient):
    """Verify invalid JSON against MongoDB source returns 400 Bad Request."""
    source_payload = {
        "name": "Mongo Invalid JSON DB",
        "type": "MONGODB",
        "host": "localhost",
        "port": 27017,
        "database_name": "altr_test_db",
        "username": "altr_test_user",
        "password": "altr_test_pass",
        "options": {"authSource": "admin"},
    }
    src_res = await client.post("/api/v1/sources", json=source_payload)
    source_id = src_res.json()["id"]

    res = await client.post(
        "/api/v1/queries/execute",
        json={"source_id": source_id, "query": "{ not valid json"},
    )
    assert res.status_code == 400
    assert "Invalid MongoDB JSON query" in res.json()["detail"]


@pytest.mark.asyncio
async def test_execute_query_api_mongodb_shell_syntax(client: AsyncClient):
    """Verify MongoDB Shell query reaches execution through API as query='mongodb:find' with parameters=[spec]."""
    source_payload = {
        "name": "Mongo Shell API DB",
        "type": "MONGODB",
        "host": "localhost",
        "port": 27017,
        "database_name": "altr_test_db",
        "username": "altr_test_user",
        "password": "altr_test_pass",
        "options": {"authSource": "admin"},
    }
    src_res = await client.post("/api/v1/sources", json=source_payload)
    assert src_res.status_code == 201
    source_id = src_res.json()["id"]

    mock_result = QueryResult(
        columns=["_id", "username"],
        rows=[{"_id": "507f1f77bcf86cd799439011", "username": "alice"}],
        row_count=1,
        execution_time_ms=8.0,
    )

    with patch(
        "altr_stream.infrastructure.connectors.mongodb.connector.MongoDBConnector.execute_query",
        new=AsyncMock(return_value=mock_result),
    ) as mock_exec:
        # 1. db.users.find().pretty()
        query_payload = {
            "source_id": source_id,
            "query": "db.users.find().pretty()",
            "mode": "shell",
        }
        res = await client.post("/api/v1/queries/execute", json=query_payload)
        assert res.status_code == 200
        data = res.json()
        assert data["success"] is True
        assert data["columns"] == ["_id", "username"]
        assert len(data["rows"]) == 1

        mock_exec.assert_awaited_with(
            "mongodb:find",
            parameters=[{"collection": "users", "filter": {}}],
        )

        # 2. db.users.find({ status: "active" }).sort({ age: -1 }).limit(5)
        query_payload2 = {
            "source_id": source_id,
            "query": 'db.users.find({ status: "active" }).sort({ age: -1 }).limit(5)',
        }
        res2 = await client.post("/api/v1/queries/execute", json=query_payload2)
        assert res2.status_code == 200
        assert res2.json()["success"] is True

        mock_exec.assert_awaited_with(
            "mongodb:find",
            parameters=[{
                "collection": "users",
                "filter": {"status": "active"},
                "sort": {"age": -1},
                "limit": 5,
            }],
        )


@pytest.mark.asyncio
async def test_execute_query_api_mongodb_shell_syntax_error(client: AsyncClient):
    """Verify malformed MongoDB Shell syntax returns 400 Bad Request with clear detail."""
    source_payload = {
        "name": "Mongo Shell Error DB",
        "type": "MONGODB",
        "host": "localhost",
        "port": 27017,
        "database_name": "altr_test_db",
        "username": "altr_test_user",
        "password": "altr_test_pass",
        "options": {"authSource": "admin"},
    }
    src_res = await client.post("/api/v1/sources", json=source_payload)
    source_id = src_res.json()["id"]

    res = await client.post(
        "/api/v1/queries/execute",
        json={"source_id": source_id, "query": "db.users.find(", "mode": "shell"},
    )
    assert res.status_code == 400
    assert "Invalid MongoDB shell syntax" in res.json()["detail"]


