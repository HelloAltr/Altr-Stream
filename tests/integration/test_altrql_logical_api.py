"""Integration tests for AltrQL v0.3 advanced conditional logic endpoints across parse, bind, and execute."""

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


async def _setup_test_source_and_schema(client: AsyncClient) -> str:
    """Helper to create a source and populate its schema."""
    source_payload = {
        "name": "Logical Test Source",
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
        source_name="Logical Test Source",
        entities=[
            EntitySchema(
                name="users",
                namespace="public",
                fields=[
                    FieldSchema(
                        name="id",
                        data_type=StandardDataType.INTEGER,
                        native_data_type="int4",
                        is_primary_key=True,
                        nullable=False,
                    ),
                    FieldSchema(
                        name="username",
                        data_type=StandardDataType.STRING,
                        native_data_type="varchar",
                        nullable=False,
                    ),
                    FieldSchema(
                        name="role",
                        data_type=StandardDataType.STRING,
                        native_data_type="varchar",
                        nullable=False,
                    ),
                    FieldSchema(
                        name="age",
                        data_type=StandardDataType.INTEGER,
                        native_data_type="int4",
                        nullable=False,
                    ),
                    FieldSchema(
                        name="is_active",
                        data_type=StandardDataType.BOOLEAN,
                        native_data_type="bool",
                        nullable=False,
                    ),
                    FieldSchema(
                        name="verified",
                        data_type=StandardDataType.BOOLEAN,
                        native_data_type="bool",
                        nullable=False,
                    ),
                    FieldSchema(
                        name="tags",
                        data_type=StandardDataType.STRING,
                        native_data_type="varchar",
                        nullable=True,
                    ),
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
async def test_api_parse_advanced_conditional_expressions(client: AsyncClient):
    query = """
    GET users WHERE {
        { is_active = TRUE, age >= 18 } OR { role = "admin", verified = TRUE }
    };
    """
    res = await client.post("/api/v1/altrql/parse", json={"query": query})
    assert res.status_code == 200
    data = res.json()
    assert data["success"] is True
    assert data["ir"]["where"]["operator"] == "OR"
    assert data["ir"]["where"]["left"]["operator"] == "AND"
    assert data["ir"]["where"]["right"]["operator"] == "AND"


@pytest.mark.asyncio
async def test_api_parse_negation_and_not_has(client: AsyncClient):
    query = 'GET users WHERE { NOT { tags HAS "spam" }, role NOT HAS "guest" };'
    res = await client.post("/api/v1/altrql/parse", json={"query": query})
    assert res.status_code == 200
    data = res.json()
    assert data["success"] is True
    assert data["ir"]["where"]["operator"] == "AND"
    assert data["ir"]["where"]["left"]["kind"] == "negation_expression"
    assert data["ir"]["where"]["right"]["operator"] == "NOT HAS"


@pytest.mark.asyncio
async def test_api_bind_nested_conditional_expressions(client: AsyncClient):
    source_id = await _setup_test_source_and_schema(client)
    query = """
    GET users WHERE {
        { is_active = TRUE, age >= 18 } OR role = "admin"
    };
    """
    res = await client.post("/api/v1/altrql/bind", json={"source_id": source_id, "query": query})
    assert res.status_code == 200
    data = res.json()
    assert data["success"] is True
    assert data["bound_ir"]["where"]["operator"] == "OR"
    assert data["bound_ir"]["where"]["left"]["operator"] == "AND"


@pytest.mark.asyncio
async def test_api_execute_get_with_advanced_logical_where(client: AsyncClient):
    source_id = await _setup_test_source_and_schema(client)
    query = """
    GET users (username, role) WHERE {
        { is_active = TRUE, age >= 18 } OR role = "admin"
    };
    """

    mock_result = QueryResult(
        columns=["username", "role"],
        rows=[{"username": "alice", "role": "user"}, {"username": "bob", "role": "admin"}],
        row_count=2,
        execution_time_ms=5.4,
    )

    with patch("altr_stream.application.query_service.QueryService.execute_query", new=AsyncMock(return_value=mock_result)) as mock_exec:
        res = await client.post("/api/v1/altrql/execute", json={"source_id": source_id, "query": query})
        assert res.status_code == 200
        data = res.json()
        assert data["success"] is True
        assert len(data["rows"]) == 2
        assert 'WHERE (("is_active" = $1 AND "age" >= $2) OR "role" = $3);' in data["physical_query"]["query"]
        assert data["physical_query"]["parameters"] == [True, 18, "admin"]
        mock_exec.assert_called_once()


@pytest.mark.asyncio
async def test_api_execute_update_with_advanced_logical_where(client: AsyncClient):
    source_id = await _setup_test_source_and_schema(client)
    query = """
    UPDATE users (
        is_active: FALSE
    ) WHERE {
        role = "guest" OR age < 18
    };
    """

    mock_result = QueryResult(
        columns=["id", "username", "role", "age", "is_active", "verified", "tags"],
        rows=[{"id": 10, "username": "guest1", "is_active": False}],
        row_count=1,
        affected_rows=1,
        execution_time_ms=6.1,
    )

    with patch("altr_stream.application.query_service.QueryService.execute_query", new=AsyncMock(return_value=mock_result)) as mock_exec:
        res = await client.post("/api/v1/altrql/execute", json={"source_id": source_id, "query": query})
        assert res.status_code == 200
        data = res.json()
        assert data["success"] is True
        assert data["classification"]["operation"] == "UPDATE"
        assert data["classification"]["mutation_scope"] == "CONSTRAINED"
        assert data["classification"]["requires_confirmation"] is False
        assert 'UPDATE "public"."users" SET "is_active" = $1 WHERE ("role" = $2 OR "age" < $3) RETURNING *;' in data["physical_query"]["query"]
        assert data["physical_query"]["parameters"] == [False, "guest", 18]
        mock_exec.assert_called_once()


@pytest.mark.asyncio
async def test_api_execute_delete_with_negation_where(client: AsyncClient):
    source_id = await _setup_test_source_and_schema(client)
    query = """
    DELETE users WHERE {
        NOT { is_active = TRUE }
    };
    """

    mock_result = QueryResult(
        columns=["id", "username", "role", "age", "is_active", "verified", "tags"],
        rows=[{"id": 20, "username": "inactive_user"}],
        row_count=1,
        affected_rows=1,
        execution_time_ms=4.8,
    )

    with patch("altr_stream.application.query_service.QueryService.execute_query", new=AsyncMock(return_value=mock_result)) as mock_exec:
        res = await client.post("/api/v1/altrql/execute", json={"source_id": source_id, "query": query})
        assert res.status_code == 200
        data = res.json()
        assert data["success"] is True
        assert data["classification"]["operation"] == "DELETE"
        assert data["classification"]["mutation_scope"] == "CONSTRAINED"
        assert 'DELETE FROM "public"."users" WHERE NOT ("is_active" = $1) RETURNING *;' in data["physical_query"]["query"]
        assert data["physical_query"]["parameters"] == [True]
        mock_exec.assert_called_once()
