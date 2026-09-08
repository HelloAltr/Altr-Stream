"""Integration tests for AltrQL v0.2 mutation endpoints across parse, bind, and execute."""

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
        "name": "Integration Test Source",
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
        source_name="Integration Test Source",
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
                        name="email",
                        data_type=StandardDataType.STRING,
                        native_data_type="varchar",
                        nullable=True,
                    ),
                    FieldSchema(
                        name="age",
                        data_type=StandardDataType.INTEGER,
                        native_data_type="int4",
                        nullable=True,
                    ),
                    FieldSchema(
                        name="is_active",
                        data_type=StandardDataType.BOOLEAN,
                        native_data_type="bool",
                        nullable=False,
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
async def test_parse_mutation_endpoints(client: AsyncClient):
    """Test /altrql/parse with CREATE, UPDATE, DELETE."""
    # 1. CREATE
    res_create = await client.post(
        "/api/v1/altrql/parse",
        json={"query": 'CREATE users ( username: "alice", age: 30 );'},
    )
    assert res_create.status_code == 200
    data_create = res_create.json()
    assert data_create["success"] is True
    assert data_create["ir"]["operation"] == "CREATE"
    assert len(data_create["ir"]["records"]) == 1
    assert len(data_create["ir"]["records"][0]["assignments"]) == 2

    # 2. UPDATE
    res_update = await client.post(
        "/api/v1/altrql/parse",
        json={"query": 'UPDATE users ( email: "a@b.com" ) WHERE { id = 1 };'},
    )
    assert res_update.status_code == 200
    data_update = res_update.json()
    assert data_update["success"] is True
    assert data_update["ir"]["operation"] == "UPDATE"

    # 3. DELETE
    res_delete = await client.post(
        "/api/v1/altrql/parse",
        json={"query": "DELETE users WHERE { id = 1 };"},
    )
    assert res_delete.status_code == 200
    data_delete = res_delete.json()
    assert data_delete["success"] is True
    assert data_delete["ir"]["operation"] == "DELETE"


@pytest.mark.asyncio
async def test_bind_mutation_endpoints_and_classification(client: AsyncClient):
    """Test /altrql/bind with mutation classification."""
    source_id = await _setup_test_source_and_schema(client)

    # 1. CREATE
    res = await client.post(
        "/api/v1/altrql/bind",
        json={"query": 'CREATE users ( username: "alice", age: 30 );', "source_id": source_id},
    )
    assert res.status_code == 200
    data = res.json()
    assert data["success"] is True
    assert data["classification"] is not None
    assert data["classification"]["operation"] == "CREATE"
    assert data["classification"]["mutation_scope"] == "NOT_APPLICABLE"
    assert data["classification"]["requires_confirmation"] is False

    # 2. Mass DELETE
    res_mass_del = await client.post(
        "/api/v1/altrql/bind",
        json={"query": "DELETE users;", "source_id": source_id},
    )
    assert res_mass_del.status_code == 200
    data_mass_del = res_mass_del.json()
    assert data_mass_del["success"] is True
    assert data_mass_del["classification"]["operation"] == "DELETE"
    assert data_mass_del["classification"]["mutation_scope"] == "MASS"
    assert data_mass_del["classification"]["requires_confirmation"] is True


@pytest.mark.asyncio
async def test_execute_create_mutation_success(client: AsyncClient):
    """Test /altrql/execute executing a CREATE statement."""
    source_id = await _setup_test_source_and_schema(client)

    mock_result = QueryResult(
        columns=["id", "username", "age", "is_active", "email"],
        rows=[{"id": 1, "username": "alice", "age": 28, "is_active": True, "email": "a@test.com"}],
        row_count=1,
        execution_time_ms=2.45,
        message="INSERT 0 1",
    )

    with patch(
        "altr_stream.infrastructure.connectors.postgres.connector.PostgreSQLConnector.execute_query",
        new=AsyncMock(return_value=mock_result),
    ):
        query = 'CREATE users ( username: "alice", age: 28, is_active: TRUE, email: "a@test.com" );'
        res = await client.post("/api/v1/altrql/execute", json={"query": query, "source_id": source_id})

        assert res.status_code == 200
        data = res.json()
        assert data["success"] is True
        assert data["error"] is None
        assert data["classification"]["operation"] == "CREATE"
        assert data["physical_query"]["query"] == 'INSERT INTO "public"."users" ("username", "age", "is_active", "email") VALUES ($1, $2, $3, $4) RETURNING *;'
        assert data["physical_query"]["parameters"] == ["alice", 28, True, "a@test.com"]
        assert data["rows"] == [{"id": 1, "username": "alice", "age": 28, "is_active": True, "email": "a@test.com"}]
        assert data["metadata"]["row_count"] == 1
        assert data["metadata"]["affected_rows"] == 1
        assert data["metadata"]["operation"] == "CREATE"


@pytest.mark.asyncio
async def test_execute_constrained_update_mutation_success(client: AsyncClient):
    """Test /altrql/execute executing a constrained UPDATE statement."""
    source_id = await _setup_test_source_and_schema(client)

    mock_result = QueryResult(
        columns=["id", "username", "email"],
        rows=[{"id": 1, "username": "alice", "email": "updated@test.com"}],
        row_count=1,
        execution_time_ms=1.8,
        message="UPDATE 1",
    )

    with patch(
        "altr_stream.infrastructure.connectors.postgres.connector.PostgreSQLConnector.execute_query",
        new=AsyncMock(return_value=mock_result),
    ):
        query = 'UPDATE users ( email: "updated@test.com" ) WHERE { id = 1 };'
        res = await client.post("/api/v1/altrql/execute", json={"query": query, "source_id": source_id})

        assert res.status_code == 200
        data = res.json()
        assert data["success"] is True
        assert data["classification"]["operation"] == "UPDATE"
        assert data["classification"]["mutation_scope"] == "CONSTRAINED"
        assert data["physical_query"]["query"] == 'UPDATE "public"."users" SET "email" = $1 WHERE "id" = $2 RETURNING *;'
        assert data["physical_query"]["parameters"] == ["updated@test.com", 1]
        assert data["metadata"]["affected_rows"] == 1


@pytest.mark.asyncio
async def test_execute_mass_update_safety_gate_and_confirmation(client: AsyncClient):
    """Test /altrql/execute safety gate for mass UPDATE requiring explicit confirmation."""
    source_id = await _setup_test_source_and_schema(client)

    mock_result = QueryResult(
        columns=["id", "is_active"],
        rows=[{"id": 1, "is_active": False}, {"id": 2, "is_active": False}],
        row_count=2,
        execution_time_ms=3.1,
        message="UPDATE 2",
    )

    query = "UPDATE users ( is_active: FALSE );"

    # 1. Without confirmation -> blocked by safety gate, returns diagnostic error with preserved artifacts
    res_blocked = await client.post(
        "/api/v1/altrql/execute",
        json={"query": query, "source_id": source_id, "confirm_mass_mutation": False},
    )
    assert res_blocked.status_code == 200
    data_blocked = res_blocked.json()
    assert data_blocked["success"] is False
    assert data_blocked["error"]["type"] == "MassMutationConfirmationRequiredError"
    assert "requires explicit confirmation" in data_blocked["error"]["message"]
    assert data_blocked["classification"]["requires_confirmation"] is True
    assert data_blocked["physical_query"]["query"] == 'UPDATE "public"."users" SET "is_active" = $1 RETURNING *;'
    assert data_blocked["physical_query"]["parameters"] == [False]

    # 2. With confirmation -> executes successfully
    with patch(
        "altr_stream.infrastructure.connectors.postgres.connector.PostgreSQLConnector.execute_query",
        new=AsyncMock(return_value=mock_result),
    ):
        res_confirmed = await client.post(
            "/api/v1/altrql/execute",
            json={"query": query, "source_id": source_id, "confirm_mass_mutation": True},
        )
        assert res_confirmed.status_code == 200
        data_confirmed = res_confirmed.json()
        assert data_confirmed["success"] is True
        assert data_confirmed["error"] is None
        assert data_confirmed["metadata"]["affected_rows"] == 2


@pytest.mark.asyncio
async def test_execute_mass_delete_safety_gate_and_confirmation(client: AsyncClient):
    """Test /altrql/execute safety gate for mass DELETE requiring explicit confirmation."""
    source_id = await _setup_test_source_and_schema(client)

    mock_result = QueryResult(
        columns=["id", "username"],
        rows=[{"id": 1, "username": "alice"}, {"id": 2, "username": "bob"}],
        row_count=2,
        execution_time_ms=2.0,
        message="DELETE 2",
    )

    query = "DELETE users;"

    # 1. Without confirmation -> blocked by safety gate
    res_blocked = await client.post(
        "/api/v1/altrql/execute",
        json={"query": query, "source_id": source_id, "confirm_mass_mutation": False},
    )
    assert res_blocked.status_code == 200
    data_blocked = res_blocked.json()
    assert data_blocked["success"] is False
    assert data_blocked["error"]["type"] == "MassMutationConfirmationRequiredError"
    assert data_blocked["classification"]["requires_confirmation"] is True
    assert data_blocked["physical_query"]["query"] == 'DELETE FROM "public"."users" RETURNING *;'

    # 2. With confirmation -> executes successfully
    with patch(
        "altr_stream.infrastructure.connectors.postgres.connector.PostgreSQLConnector.execute_query",
        new=AsyncMock(return_value=mock_result),
    ):
        res_confirmed = await client.post(
            "/api/v1/altrql/execute",
            json={"query": query, "source_id": source_id, "confirm_mass_mutation": True},
        )
        assert res_confirmed.status_code == 200
        data_confirmed = res_confirmed.json()
        assert data_confirmed["success"] is True
        assert data_confirmed["error"] is None
        assert data_confirmed["metadata"]["affected_rows"] == 2
