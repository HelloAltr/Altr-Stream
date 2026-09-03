"""Integration tests for Admin UI web routes and templates."""

from unittest.mock import AsyncMock, patch
import pytest
from httpx import AsyncClient

from altr_stream.domain.connector import ConnectionTestResult
from altr_stream.domain.schema import EntitySchema, FieldSchema, SourceSchema, StandardDataType


@pytest.mark.asyncio
async def test_dashboard_renders_empty_state(client: AsyncClient):
    response = await client.get("/")
    assert response.status_code == 200
    assert "Altr Stream" in response.text
    assert "No Data Sources Registered" in response.text


@pytest.mark.asyncio
async def test_add_source_form_renders(client: AsyncClient):
    response = await client.get("/admin/sources/new")
    assert response.status_code == 200
    assert "Register Data Source" in response.text
    assert "PostgreSQL Connection Details" in response.text
    assert "Test Connection First" in response.text


@pytest.mark.asyncio
async def test_test_inline_htmx(client: AsyncClient):
    mock_result = ConnectionTestResult(
        success=True,
        message="Connected successfully to PostgreSQL (5.0 ms)",
        latency_ms=5.0,
        server_version="PostgreSQL 16.0",
    )

    with patch(
        "altr_stream.infrastructure.connectors.postgres.connector.PostgreSQLConnector.test_connection",
        new=AsyncMock(return_value=mock_result),
    ):
        form_data = {
            "type": "POSTGRESQL",
            "host": "localhost",
            "port": 5432,
            "database_name": "testdb",
            "username": "postgres",
            "password": "pass",
        }
        res = await client.post("/admin/sources/test-inline", data=form_data)
        assert res.status_code == 200
        assert "Connection Successful!" in res.text
        assert "5.0 ms" in res.text


@pytest.mark.asyncio
async def test_full_web_ui_source_flow(client: AsyncClient):
    mock_test = ConnectionTestResult(
        success=True,
        message="Connected to PostgreSQL",
        latency_ms=1.2,
    )
    mock_schema = SourceSchema(
        source_id="tmp",
        source_name="Store Postgres",
        entities=[
            EntitySchema(
                name="inventory",
                namespace="public",
                fields=[
                    FieldSchema(
                        name="item_id",
                        data_type=StandardDataType.INTEGER,
                        native_data_type="int4",
                        is_primary_key=True,
                        nullable=False,
                    )
                ],
            )
        ],
    )

    with (
        patch(
            "altr_stream.infrastructure.connectors.postgres.connector.PostgreSQLConnector.test_connection",
            new=AsyncMock(return_value=mock_test),
        ),
        patch(
            "altr_stream.infrastructure.connectors.postgres.connector.PostgreSQLConnector.discover_schema",
            new=AsyncMock(return_value=mock_schema),
        ),
    ):
        # 1. Submit Add Source Form
        form_data = {
            "name": "Store Postgres",
            "type": "POSTGRESQL",
            "host": "localhost",
            "port": "5432",
            "database_name": "storedb",
            "username": "postgres",
            "password": "secretpassword",
        }
        post_res = await client.post("/admin/sources/new", data=form_data, follow_redirects=False)
        assert post_res.status_code == 303
        redirect_url = post_res.headers["location"]
        source_id = redirect_url.split("/")[-1]

        # 2. View Source Detail Page
        detail_res = await client.get(f"/admin/sources/{source_id}")
        assert detail_res.status_code == 200
        assert "Store Postgres" in detail_res.text
        assert "storedb" in detail_res.text
        assert "•••••••• (Protected)" in detail_res.text

        # 3. Test Connection via HTMX
        test_res = await client.post(f"/admin/sources/{source_id}/test")
        assert test_res.status_code == 200
        assert "Connection Successful!" in test_res.text

        # 4. Discover Schema via HTMX
        discover_res = await client.post(f"/admin/sources/{source_id}/discover")
        assert discover_res.status_code == 200
        assert "Schema Discovered Successfully!" in discover_res.text

        # 5. View Schema Viewer Page
        schema_res = await client.get(f"/admin/sources/{source_id}/schema")
        assert schema_res.status_code == 200
        assert "public.inventory" in schema_res.text
        assert "item_id" in schema_res.text
        assert "INTEGER" in schema_res.text

        # 6. Delete Source
        del_res = await client.post(f"/admin/sources/{source_id}/delete", follow_redirects=False)
        assert del_res.status_code == 303
        assert del_res.headers["location"] == "/"

        # 7. Verify Dashboard is empty again
        dash_res = await client.get("/")
        assert dash_res.status_code == 200
        assert "No Data Sources Registered" in dash_res.text
