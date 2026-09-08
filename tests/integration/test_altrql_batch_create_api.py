"""Integration tests for AltrQL v0.4 batch CREATE endpoints across parse, bind, and execute."""

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
        "name": "Batch Test Source",
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
        source_name="Batch Test Source",
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
async def test_parse_batch_create_endpoints(client: AsyncClient):
    """Test /altrql/parse with batch CREATE syntax."""
    query = """
    CREATE users (
        (username: "alice", email: "alice@example.com", age: 30),
        (username: "bob", email: "bob@example.com", age: 25)
    );
    """
    res = await client.post("/api/v1/altrql/parse", json={"query": query})
    assert res.status_code == 200
    data = res.json()
    assert data["success"] is True
    assert data["ir"]["operation"] == "CREATE"
    assert len(data["ir"]["records"]) == 2
    assert len(data["ir"]["records"][0]["assignments"]) == 3
    assert len(data["ir"]["records"][1]["assignments"]) == 3


@pytest.mark.asyncio
async def test_bind_batch_create_endpoints_and_classification(client: AsyncClient):
    """Test /altrql/bind with batch CREATE classification."""
    source_id = await _setup_test_source_and_schema(client)

    query = """
    CREATE users (
        (username: "alice", age: 30),
        (username: "bob", email: "bob@example.com")
    );
    """
    res = await client.post(
        "/api/v1/altrql/bind",
        json={"query": query, "source_id": source_id},
    )
    assert res.status_code == 200
    data = res.json()
    assert data["success"] is True
    assert data["classification"]["operation"] == "CREATE"
    assert data["classification"]["mutation_scope"] == "NOT_APPLICABLE"
    assert data["classification"]["requires_confirmation"] is False
    assert len(data["bound_ir"]["records"]) == 2


@pytest.mark.asyncio
async def test_execute_homogeneous_batch_create_mock(client: AsyncClient):
    """Test /altrql/execute with homogeneous batch CREATE producing single PhysicalQuery."""
    source_id = await _setup_test_source_and_schema(client)

    mock_result = QueryResult(
        columns=["id", "username", "email"],
        rows=[
            {"id": 1, "username": "alice", "email": "alice@test.com"},
            {"id": 2, "username": "bob", "email": "bob@test.com"},
        ],
        row_count=2,
        affected_rows=2,
        execution_time_ms=3.5,
        message="INSERT 0 2",
    )

    with patch(
        "altr_stream.infrastructure.connectors.postgres.connector.PostgreSQLConnector.execute_query",
        new=AsyncMock(return_value=mock_result),
    ):
        query = """
        CREATE users (
            (username: "alice", email: "alice@test.com"),
            (username: "bob", email: "bob@test.com")
        );
        """
        res = await client.post("/api/v1/altrql/execute", json={"query": query, "source_id": source_id})
        assert res.status_code == 200
        data = res.json()
        assert data["success"] is True
        assert data["physical_query"] is not None
        assert (
            data["physical_query"]["query"]
            == 'INSERT INTO "public"."users" ("username", "email") VALUES ($1, $2), ($3, $4) RETURNING *;'
        )
        assert data["physical_query"]["parameters"] == ["alice", "alice@test.com", "bob", "bob@test.com"]
        assert len(data["rows"]) == 2
        assert data["metadata"]["affected_rows"] == 2


@pytest.mark.asyncio
async def test_execute_heterogeneous_batch_create_mock(client: AsyncClient):
    """Test /altrql/execute with heterogeneous batch CREATE producing PhysicalQueryBatch."""
    source_id = await _setup_test_source_and_schema(client)

    # Mock batch execution returning merged results
    mock_batch_result = QueryResult(
        columns=["id", "username", "email", "age"],
        rows=[
            {"id": 1, "username": "alice", "email": "alice@test.com", "age": None},
            {"id": 2, "username": "bob", "email": "bob@test.com", "age": None},
            {"id": 3, "username": "charlie", "email": None, "age": 35},
            {"id": 4, "username": "david", "email": "david@test.com", "age": None},
        ],
        row_count=4,
        affected_rows=4,
        execution_time_ms=5.2,
        message="INSERT 0 4",
    )

    with patch(
        "altr_stream.infrastructure.connectors.postgres.connector.PostgreSQLConnector.execute_batch",
        new=AsyncMock(return_value=mock_batch_result),
    ):
        query = """
        CREATE users (
            (username: "alice", email: "alice@test.com"),
            (username: "bob", email: "bob@test.com"),
            (username: "charlie", age: 35),
            (username: "david", email: "david@test.com")
        );
        """
        res = await client.post("/api/v1/altrql/execute", json={"query": query, "source_id": source_id})
        assert res.status_code == 200
        data = res.json()
        assert data["success"] is True
        assert data["physical_query"] is not None
        assert data["physical_query"]["kind"] == "physical_query_batch"
        assert len(data["physical_query"]["queries"]) == 3
        assert len(data["rows"]) == 4
        assert data["metadata"]["affected_rows"] == 4


@pytest.mark.asyncio
async def test_live_postgres_batch_create_execution_and_rollback(client: AsyncClient):
    """Test live batch CREATE execution, heterogeneous grouping, and transactional rollback against PostgreSQL container."""
    if not await _is_postgres_available():
        pytest.skip("PostgreSQL test container not available on port 5432")

    connector = PostgreSQLConnector(PG_CONFIG)

    # Setup test table
    await connector.execute_query("DROP TABLE IF EXISTS test_batch_users;")
    await connector.execute_query("""
    CREATE TABLE test_batch_users (
        id SERIAL PRIMARY KEY,
        username VARCHAR(50) UNIQUE NOT NULL,
        email VARCHAR(100),
        age INT
    );
    """)

    # Create live source in API
    source_payload = {
        "name": "Live Postgres Batch Test Source",
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

    # Discover real schema
    disc_res = await client.post(f"/api/v1/sources/{source_id}/schema/discover")
    assert disc_res.status_code == 200

    try:
        # 1. Test Homogeneous Batch CREATE
        q_homo = """
        CREATE test_batch_users (
            (username: "alice", email: "alice@test.com", age: 25),
            (username: "bob", email: "bob@test.com", age: 30)
        );
        """
        res_homo = await client.post("/api/v1/altrql/execute", json={"query": q_homo, "source_id": source_id})
        assert res_homo.status_code == 200
        data_homo = res_homo.json()
        assert data_homo["success"] is True
        assert data_homo["physical_query"] is not None
        assert len(data_homo["rows"]) == 2
        assert data_homo["rows"][0]["username"] == "alice"
        assert data_homo["rows"][1]["username"] == "bob"

        # 2. Test Heterogeneous Batch CREATE with consecutive grouping (A, B, A)
        q_hetero = """
        CREATE test_batch_users (
            (username: "charlie", email: "charlie@test.com"),
            (username: "david", age: 40),
            (username: "eve", email: "eve@test.com")
        );
        """
        res_hetero = await client.post("/api/v1/altrql/execute", json={"query": q_hetero, "source_id": source_id})
        assert res_hetero.status_code == 200
        data_hetero = res_hetero.json()
        assert data_hetero["success"] is True
        assert data_hetero["physical_query"] is not None
        assert data_hetero["physical_query"]["kind"] == "physical_query_batch"
        assert len(data_hetero["physical_query"]["queries"]) == 3
        assert len(data_hetero["rows"]) == 3
        # Strict order preservation
        assert data_hetero["rows"][0]["username"] == "charlie"
        assert data_hetero["rows"][0]["email"] == "charlie@test.com"
        assert data_hetero["rows"][1]["username"] == "david"
        assert data_hetero["rows"][1]["age"] == 40
        assert data_hetero["rows"][2]["username"] == "eve"
        assert data_hetero["rows"][2]["email"] == "eve@test.com"

        # 3. Test Transactional Rollback when a batch record violates constraint
        # Group 1: frank (valid), Group 2: alice (duplicate unique key)
        q_fail = """
        CREATE test_batch_users (
            (username: "frank", email: "frank@test.com"),
            (username: "alice", age: 99)
        );
        """
        res_fail = await client.post("/api/v1/altrql/execute", json={"query": q_fail, "source_id": source_id})
        assert res_fail.status_code == 200
        data_fail = res_fail.json()
        assert data_fail["success"] is False
        assert "unique constraint" in data_fail["error"]["message"].lower()

        # Verify frank was NOT inserted (full transaction rollback!)
        check_frank = await connector.execute_query("SELECT * FROM test_batch_users WHERE username = 'frank';")
        assert len(check_frank.rows) == 0

    finally:
        await connector.execute_query("DROP TABLE IF EXISTS test_batch_users;")
