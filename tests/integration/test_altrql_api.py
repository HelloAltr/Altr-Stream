"""Integration tests for the AltrQL Parse REST API endpoint."""

from httpx import AsyncClient
import pytest


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
async def test_parse_altrql_api_validation_error_empty_body(client: AsyncClient):
    """Test 422 validation on empty query payload."""
    res = await client.post("/api/v1/altrql/parse", json={"query": ""})
    assert res.status_code == 422
