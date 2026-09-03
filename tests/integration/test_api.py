"""Integration tests for REST API endpoints."""

from unittest.mock import AsyncMock, patch
import pytest
from httpx import AsyncClient

from altr_stream.domain.connector import ConnectionTestResult, SourceCapabilities
from altr_stream.domain.schema import EntitySchema, FieldSchema, SourceSchema, StandardDataType


@pytest.mark.asyncio
async def test_health_check_endpoint(client: AsyncClient):
    response = await client.get("/api/v1/health")
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "healthy"
    assert data["service"] == "Altr Stream"
    assert "version" in data


@pytest.mark.asyncio
async def test_sources_crud_api(client: AsyncClient):
    # 1. Create Source
    payload = {
        "name": "Main PostgreSQL",
        "type": "POSTGRESQL",
        "host": "localhost",
        "port": 5432,
        "database_name": "app_db",
        "username": "postgres",
        "password": "mypassword123",
        "test_connection_first": False,
    }
    create_res = await client.post("/api/v1/sources", json=payload)
    assert create_res.status_code == 201
    source_data = create_res.json()
    assert source_data["name"] == "Main PostgreSQL"
    assert source_data["password_masked"] == "••••••••"
    assert "password" not in source_data
    source_id = source_data["id"]

    # 2. Prevent duplicate name
    dup_res = await client.post("/api/v1/sources", json=payload)
    assert dup_res.status_code == 409

    # 3. List Sources
    list_res = await client.get("/api/v1/sources")
    assert list_res.status_code == 200
    sources = list_res.json()
    assert len(sources) == 1
    assert sources[0]["id"] == source_id

    # 4. Get Source by ID
    get_res = await client.get(f"/api/v1/sources/{source_id}")
    assert get_res.status_code == 200
    assert get_res.json()["name"] == "Main PostgreSQL"

    # 5. Update Source
    update_res = await client.put(
        f"/api/v1/sources/{source_id}",
        json={"name": "Updated PostgreSQL", "port": 5433},
    )
    assert update_res.status_code == 200
    assert update_res.json()["name"] == "Updated PostgreSQL"
    assert update_res.json()["port"] == 5433

    # 6. Get Capabilities
    cap_res = await client.get(f"/api/v1/sources/{source_id}/capabilities")
    assert cap_res.status_code == 200
    caps = cap_res.json()
    assert caps["schema_discovery"] is True
    assert caps["cdc"] is False

    # 7. Delete Source
    del_res = await client.delete(f"/api/v1/sources/{source_id}")
    assert del_res.status_code == 204

    # 8. Verify 404 on deleted source
    not_found_res = await client.get(f"/api/v1/sources/{source_id}")
    assert not_found_res.status_code == 404


@pytest.mark.asyncio
async def test_adhoc_connection_test_api(client: AsyncClient):
    mock_result = ConnectionTestResult(
        success=True,
        message="Connected successfully to PostgreSQL (2.5 ms)",
        latency_ms=2.5,
        server_version="PostgreSQL 16.1",
    )

    with patch(
        "altr_stream.infrastructure.connectors.postgres.connector.PostgreSQLConnector.test_connection",
        new=AsyncMock(return_value=mock_result),
    ):
        payload = {
            "type": "POSTGRESQL",
            "host": "localhost",
            "port": 5432,
            "database_name": "test_db",
            "username": "user",
            "password": "pass",
        }
        res = await client.post("/api/v1/sources/test", json=payload)
        assert res.status_code == 200
        data = res.json()
        assert data["success"] is True
        assert "Connected successfully" in data["message"]
        assert data["latency_ms"] == 2.5


@pytest.mark.asyncio
async def test_schema_discovery_api(client: AsyncClient):
    # Register source
    payload = {
        "name": "Warehouse DB",
        "type": "POSTGRESQL",
        "host": "localhost",
        "port": 5432,
        "database_name": "warehouse",
        "username": "postgres",
        "password": "secret",
    }
    source_res = await client.post("/api/v1/sources", json=payload)
    source_id = source_res.json()["id"]

    mock_schema = SourceSchema(
        source_id=source_id,
        source_name="Warehouse DB",
        entities=[
            EntitySchema(
                name="customers",
                namespace="public",
                fields=[
                    FieldSchema(
                        name="id",
                        data_type=StandardDataType.INTEGER,
                        native_data_type="int4",
                        is_primary_key=True,
                        nullable=False,
                    )
                ],
            )
        ],
    )

    with patch(
        "altr_stream.infrastructure.connectors.postgres.connector.PostgreSQLConnector.discover_schema",
        new=AsyncMock(return_value=mock_schema),
    ):
        # Trigger schema discovery
        discover_res = await client.post(f"/api/v1/sources/{source_id}/schema/discover")
        assert discover_res.status_code == 200
        data = discover_res.json()
        assert data["source_id"] == source_id
        assert len(data["entities"]) == 1
        assert data["entities"][0]["name"] == "customers"

        # Fetch latest schema
        get_schema_res = await client.get(f"/api/v1/sources/{source_id}/schema")
        assert get_schema_res.status_code == 200
        saved_data = get_schema_res.json()
        assert saved_data["source_id"] == source_id
        assert len(saved_data["entities"]) == 1
