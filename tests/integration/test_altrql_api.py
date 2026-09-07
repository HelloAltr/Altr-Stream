"""Integration tests for AltrQL Parse and Bind REST API endpoints."""

from unittest.mock import AsyncMock, patch
from httpx import AsyncClient
import pytest

from altr_stream.domain.schema import EntitySchema, FieldSchema, SourceSchema, StandardDataType


@pytest.mark.asyncio
async def test_parse_altrql_api_success_basic(client: AsyncClient):
    """Test parsing a valid basic AltrQL query."""
    payload = {"query": "GET users;"}
    res = await client.post("/api/v1/altrql/parse", json=payload)
    assert res.status_code == 200
    data = res.json()
    assert data["success"] is True
    assert data["error"] is None
    assert data["ir"] is not None
    assert data["ir"]["entity"] == "users"
    assert data["ir"]["projection"] == []
    assert data["ir"]["where"] is None


@pytest.mark.asyncio
async def test_parse_altrql_api_success_complex(client: AsyncClient):
    """Test parsing a complex AltrQL query with projections, WHERE, value sets, and ranking."""
    query = """
    // Retrieve active adult users
    GET users (
        id,
        name AS username,
        address.country
    ) WHERE {
        age = {>18} OR role = "ADMIN",
        status = "ACTIVE",
        id = {1, 2, 6..10}
    } TOP 10 BY age OFFSET 20;
    """
    res = await client.post("/api/v1/altrql/parse", json={"query": query})
    assert res.status_code == 200
    data = res.json()
    assert data["success"] is True
    assert data["error"] is None
    assert data["ir"] is not None
    assert data["ir"]["entity"] == "users"
    assert len(data["ir"]["projection"]) == 3
    assert data["ir"]["projection"][1]["alias"] == "username"
    assert data["ir"]["projection"][2]["path"]["segments"] == ["address", "country"]
    assert data["ir"]["ranking"]["count"] == 10
    assert data["ir"]["offset"] == 20


@pytest.mark.asyncio
async def test_parse_altrql_api_parse_error_case_sensitive(client: AsyncClient):
    """Test that lowercase keyword returns structured parse error."""
    res = await client.post("/api/v1/altrql/parse", json={"query": "get users;"})
    assert res.status_code == 200
    data = res.json()
    assert data["success"] is False
    assert data["ir"] is None
    assert data["error"] is not None
    assert data["error"]["type"] == "AltrQueryParseError"
    assert "strictly uppercase" in data["error"]["message"]
    assert data["error"]["line"] == 1
    assert data["error"]["column"] == 1


@pytest.mark.asyncio
async def test_parse_altrql_api_parse_error_missing_semicolon(client: AsyncClient):
    """Test that missing semicolon returns structured parse error."""
    res = await client.post("/api/v1/altrql/parse", json={"query": "GET users"})
    assert res.status_code == 200
    data = res.json()
    assert data["success"] is False
    assert data["ir"] is None
    assert data["error"] is not None
    assert data["error"]["type"] == "AltrQueryParseError"
    assert "Expected ';'" in data["error"]["message"]


@pytest.mark.asyncio
async def test_parse_altrql_api_lex_error_unterminated_string(client: AsyncClient):
    """Test that unterminated string returns structured lexer error."""
    res = await client.post(
        "/api/v1/altrql/parse",
        json={"query": 'GET users WHERE { status = "ACTIVE };'},
    )
    assert res.status_code == 200
    data = res.json()
    assert data["success"] is False
    assert data["ir"] is None
    assert data["error"] is not None
    assert data["error"]["type"] == "AltrQueryLexError"
    assert "Unterminated string literal" in data["error"]["message"]


@pytest.mark.asyncio
async def test_parse_altrql_api_semantic_error_duplicate_aliases(client: AsyncClient):
    """Test that query with duplicate aliases returns structured semantic error."""
    res = await client.post(
        "/api/v1/altrql/parse",
        json={"query": "GET users (id AS uid, name AS uid);"},
    )
    assert res.status_code == 200
    data = res.json()
    assert data["success"] is False
    assert data["ir"] is None
    assert data["error"] is not None
    assert data["error"]["type"] == "AltrQuerySemanticError"
    assert "Duplicate projection alias 'uid'" in data["error"]["message"]


@pytest.mark.asyncio
async def test_parse_altrql_api_semantic_error_inverted_range(client: AsyncClient):
    """Test that query with inverted range bounds returns structured semantic error."""
    res = await client.post(
        "/api/v1/altrql/parse",
        json={"query": "GET users WHERE { age = 50..10 };"},
    )
    assert res.status_code == 200
    data = res.json()
    assert data["success"] is False
    assert data["ir"] is None
    assert data["error"] is not None
    assert data["error"]["type"] == "AltrQuerySemanticError"
    assert "Range start (50) must be less than or equal to end (10)" in data["error"]["message"]


@pytest.mark.asyncio
async def test_parse_altrql_api_validation_error_empty_body(client: AsyncClient):
    """Test 422 validation on empty query payload."""
    res = await client.post("/api/v1/altrql/parse", json={"query": ""})
    assert res.status_code == 422


# ---------------------------------------------------------------------------
# AltrQL Bind Integration Tests (Phase D)
# ---------------------------------------------------------------------------


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
                    FieldSchema(name="id", data_type=StandardDataType.INTEGER, native_data_type="int4", is_primary_key=True, nullable=False),
                    FieldSchema(name="username", data_type=StandardDataType.STRING, native_data_type="varchar", nullable=False),
                    FieldSchema(name="age", data_type=StandardDataType.INTEGER, native_data_type="int4", nullable=True),
                    FieldSchema(name="is_active", data_type=StandardDataType.BOOLEAN, native_data_type="bool", nullable=False),
                    FieldSchema(name="created_at", data_type=StandardDataType.TIMESTAMP, native_data_type="timestamp", nullable=False),
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
async def test_bind_altrql_api_success(client: AsyncClient):
    source_id = await _setup_test_source_and_schema(client)

    query = 'GET users (id AS uid, username) WHERE { age = {>=18 & <=65}, created_at >= TODAY } SORT { age DESC };'
    payload = {"query": query, "source_id": source_id}

    res = await client.post("/api/v1/altrql/bind", json=payload)
    assert res.status_code == 200
    data = res.json()
    assert data["success"] is True
    assert data["error"] is None
    assert data["ir"] is not None
    assert data["bound_ir"] is not None

    bound = data["bound_ir"]
    assert bound["source_id"] == source_id
    assert bound["source_name"] == "Integration Test Source"
    assert bound["entity"]["name"] == "users"
    assert len(bound["projection"]) == 2
    assert bound["projection"][0]["alias"] == "uid"
    assert bound["projection"][0]["field"]["data_type"] == "INTEGER"
    assert bound["projection"][0]["field"]["logical_category"] == "NUMERIC"
    assert len(bound["sort"]) == 1
    assert bound["sort"][0]["direction"] == "DESC"


@pytest.mark.asyncio
async def test_bind_altrql_api_source_not_found(client: AsyncClient):
    payload = {"query": "GET users;", "source_id": "non_existent_source_id"}
    res = await client.post("/api/v1/altrql/bind", json=payload)
    assert res.status_code == 200
    data = res.json()
    assert data["success"] is False
    assert data["bound_ir"] is None
    assert data["error"] is not None
    assert data["error"]["type"] == "SourceNotFoundError"
    assert "non_existent_source_id" in data["error"]["message"]


@pytest.mark.asyncio
async def test_bind_altrql_api_schema_not_found(client: AsyncClient):
    # Create source without discovering schema
    source_payload = {
        "name": "Undiscovered Source",
        "type": "POSTGRESQL",
        "host": "localhost",
        "port": 5432,
        "database_name": "db",
        "username": "user",
        "password": "password",
        "test_connection_first": False,
    }
    create_res = await client.post("/api/v1/sources", json=source_payload)
    source_id = create_res.json()["id"]

    payload = {"query": "GET users;", "source_id": source_id}
    res = await client.post("/api/v1/altrql/bind", json=payload)
    assert res.status_code == 200
    data = res.json()
    assert data["success"] is False
    assert data["error"]["type"] == "SchemaNotFoundError"


@pytest.mark.asyncio
async def test_bind_altrql_api_unknown_entity(client: AsyncClient):
    source_id = await _setup_test_source_and_schema(client)
    payload = {"query": "GET customers;", "source_id": source_id}
    res = await client.post("/api/v1/altrql/bind", json=payload)
    assert res.status_code == 200
    data = res.json()
    assert data["success"] is False
    assert data["error"]["type"] == "UnknownEntityError"
    assert "customers" in data["error"]["message"]


@pytest.mark.asyncio
async def test_bind_altrql_api_unknown_field(client: AsyncClient):
    source_id = await _setup_test_source_and_schema(client)
    payload = {"query": "GET users (id, non_existent_col);", "source_id": source_id}
    res = await client.post("/api/v1/altrql/bind", json=payload)
    assert res.status_code == 200
    data = res.json()
    assert data["success"] is False
    assert data["error"]["type"] == "UnknownFieldError"
    assert "non_existent_col" in data["error"]["message"]


@pytest.mark.asyncio
async def test_bind_altrql_api_type_compatibility_error(client: AsyncClient):
    source_id = await _setup_test_source_and_schema(client)
    payload = {"query": 'GET users WHERE { age = "twenty" };', "source_id": source_id}
    res = await client.post("/api/v1/altrql/bind", json=payload)
    assert res.status_code == 200
    data = res.json()
    assert data["success"] is False
    assert data["error"]["type"] == "TypeCompatibilityError"


@pytest.mark.asyncio
async def test_bind_altrql_api_null_rejected(client: AsyncClient):
    source_id = await _setup_test_source_and_schema(client)
    payload = {"query": "GET users WHERE { age = NULL };", "source_id": source_id}
    res = await client.post("/api/v1/altrql/bind", json=payload)
    assert res.status_code == 200
    data = res.json()
    assert data["success"] is False
    assert data["error"]["type"] == "TypeCompatibilityError"
    assert "NULL" in data["error"]["message"]


@pytest.mark.asyncio
async def test_bind_altrql_api_parse_error_in_query(client: AsyncClient):
    source_id = await _setup_test_source_and_schema(client)
    payload = {"query": "get users;", "source_id": source_id}
    res = await client.post("/api/v1/altrql/bind", json=payload)
    assert res.status_code == 200
    data = res.json()
    assert data["success"] is False
    assert data["error"]["type"] == "AltrQueryParseError"


@pytest.mark.asyncio
async def test_bind_altrql_api_explicit_iso_date_success(client: AsyncClient):
    source_id = await _setup_test_source_and_schema(client)
    payload = {"query": "GET users WHERE { created_at >= @2026-01-01 };", "source_id": source_id}
    res = await client.post("/api/v1/altrql/bind", json=payload)
    assert res.status_code == 200
    data = res.json()
    assert data["success"] is True
    assert data["bound_ir"] is not None
    assert data["bound_ir"]["where"]["field"]["path"]["segments"] == ["created_at"]
    assert data["bound_ir"]["where"]["field"]["logical_category"] == "TEMPORAL"
    assert data["bound_ir"]["where"]["operand"]["value"] == "2026-01-01"


@pytest.mark.asyncio
async def test_bind_altrql_api_temporal_vs_string_and_cross_type_errors(client: AsyncClient):
    source_id = await _setup_test_source_and_schema(client)

    # 1. Quoted string for temporal field fails binding
    payload1 = {"query": 'GET users WHERE { created_at = "2026-01-01" };', "source_id": source_id}
    res1 = await client.post("/api/v1/altrql/bind", json=payload1)
    data1 = res1.json()
    assert data1["success"] is False
    assert data1["error"]["type"] == "TypeCompatibilityError"

    # 2. ISO date for numeric field fails binding
    payload2 = {"query": "GET users WHERE { age = @2026-01-01 };", "source_id": source_id}
    res2 = await client.post("/api/v1/altrql/bind", json=payload2)
    data2 = res2.json()
    assert data2["success"] is False
    assert data2["error"]["type"] == "TypeCompatibilityError"

    # 3. Invalid calendar date fails lexing/parsing
    payload3 = {"query": "GET users WHERE { created_at = @2026-02-30 };", "source_id": source_id}
    res3 = await client.post("/api/v1/altrql/bind", json=payload3)
    data3 = res3.json()
    assert data3["success"] is False
    assert data3["error"]["type"] == "AltrQueryLexError"
