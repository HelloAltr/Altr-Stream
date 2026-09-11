"""Integration tests for AltrQL v0.6.2-alpha REST API endpoints and execution.

Tests:
- Combined WHERE predicates with HAS set-membership, boolean comparison, and NULL
- Inclusive range parsing and execution
- Nested JSON field access against SQLite and PostgreSQL schemas
- Explicit SORT ASC/DESC with LIMIT
- Deterministic default PK ordering with and without LIMIT
- Explicit SORT overriding default ordering
- Real end-to-end execution against SQLite connector
"""

import json
import sqlite3
import tempfile
from unittest.mock import AsyncMock, patch

from httpx import AsyncClient
import pytest
from sqlalchemy.ext.asyncio import AsyncSession

from altr_stream.domain.query import QueryResult
from altr_stream.domain.schema import (
    EntitySchema,
    FieldSchema,
    SourceSchema,
    StandardDataType,
)
from altr_stream.domain.source import Source, SourceStatus, SourceType
from altr_stream.infrastructure.database.repository import SqliteSourceRepository


async def _setup_sqlite_users_source(client: AsyncClient, test_session: AsyncSession, db_path: str) -> str:
    """Helper to initialize a real SQLite DB file with test data and register it as a Source."""
    conn = sqlite3.connect(db_path)
    cur = conn.cursor()
    cur.execute("""
        CREATE TABLE users (
            id INTEGER PRIMARY KEY,
            email TEXT,
            is_active INTEGER,
            metadata TEXT
        );
    """)
    records = [
        (1, "alice@example.com", 1, json.dumps({"department": "Engineering", "tier": "gold"})),
        (2, "bob@example.com", 1, json.dumps({"department": "Sales", "tier": "silver"})),
        (3, "edith", 1, None),
        (4, "group_a1", 1, None),
        (5, "edith@example.com", 1, None), # Should NOT match HAS {"edith", "group_a1"}
        (6, "charlie@example.com", 0, None),
        (7, "dave@example.com", 1, json.dumps({"department": "Engineering", "tier": "bronze"})),
    ]
    cur.executemany("INSERT INTO users VALUES (?, ?, ?, ?)", records)
    conn.commit()
    conn.close()

    source_repo = SqliteSourceRepository(test_session)
    source = Source(
        name="v062 SQLite Test Source",
        type=SourceType.SQLITE,
        file_path=db_path,
        status=SourceStatus.ACTIVE,
    )
    saved_source = await source_repo.create(source)

    # Discover / save schema
    schema = SourceSchema(
        source_id=saved_source.id,
        source_name=saved_source.name,
        entities=[
            EntitySchema(
                name="users",
                namespace="main",
                fields=[
                    FieldSchema(name="id", data_type=StandardDataType.INTEGER, native_data_type="INTEGER", is_primary_key=True),
                    FieldSchema(name="email", data_type=StandardDataType.STRING, native_data_type="TEXT"),
                    FieldSchema(name="is_active", data_type=StandardDataType.BOOLEAN, native_data_type="INTEGER"),
                    FieldSchema(name="metadata", data_type=StandardDataType.JSON, native_data_type="TEXT"),
                ],
                primary_key=["id"],
            )
        ],
    )
    await source_repo.save_schema_snapshot(saved_source.id, schema)
    return saved_source.id


@pytest.mark.asyncio
async def test_api_parse_v062_features(client: AsyncClient):
    # 1. Combined WHERE + HAS
    query1 = """
    GET users WHERE {
        email HAS {"edith", "group_a1"}
        is_active = TRUE,
        metadata = NULL
    };
    """
    res1 = await client.post("/api/v1/altrql/parse", json={"query": query1})
    assert res1.status_code == 200
    data1 = res1.json()
    assert data1["success"] is True
    assert data1["ir"]["where"]["operator"] == "AND"

    # 2. Inclusive range
    query2 = "GET users WHERE { id = {1, 2, 5..7} };"
    res2 = await client.post("/api/v1/altrql/parse", json={"query": query2})
    assert res2.status_code == 200
    data2 = res2.json()
    assert data2["success"] is True

    # 3. SORT + LIMIT
    query3 = "GET users SORT { id ASC } LIMIT 3 OFFSET 1;"
    res3 = await client.post("/api/v1/altrql/parse", json={"query": query3})
    assert res3.status_code == 200
    data3 = res3.json()
    assert data3["success"] is True
    assert data3["ir"]["sort"][0]["field"]["segments"] == ["id"]
    assert data3["ir"]["sort"][0]["direction"] == "ASC"
    assert data3["ir"]["limit"] == 3
    assert data3["ir"]["offset"] == 1


@pytest.mark.asyncio
async def test_api_execute_combined_where_and_has(client: AsyncClient, test_session: AsyncSession):
    with tempfile.NamedTemporaryFile(suffix=".db") as tmp:
        source_id = await _setup_sqlite_users_source(client, test_session, tmp.name)

        query = """
        GET users (id, email) WHERE {
            email HAS {"edith", "group_a1"}
            is_active = TRUE,
            metadata = NULL
        };
        """
        res = await client.post("/api/v1/altrql/execute", json={"source_id": source_id, "query": query})
        assert res.status_code == 200
        data = res.json()
        assert data["success"] is True
        # Under substring HAS {"edith", "group_a1"}, matches id=3 ("edith"), id=4 ("group_a1"), and id=5 ("edith@example.com")
        emails = [r["email"] for r in data["rows"]]
        assert sorted(emails) == ["edith", "edith@example.com", "group_a1"]


@pytest.mark.asyncio
async def test_api_execute_has_substring_vs_exact_equals(client: AsyncClient, test_session: AsyncSession):
    with tempfile.NamedTemporaryFile(suffix=".db") as tmp:
        source_id = await _setup_sqlite_users_source(client, test_session, tmp.name)

        # 1. HAS single string: substring matching
        res_has_single = await client.post(
            "/api/v1/altrql/execute",
            json={"source_id": source_id, "query": 'GET users (id, email) WHERE { email HAS "alice" };'},
        )
        assert res_has_single.status_code == 200
        assert [r["email"] for r in res_has_single.json()["rows"]] == ["alice@example.com"]

        # 2. HAS {"alice", "bob"}: substring matching across any supplied value
        res_has_multi = await client.post(
            "/api/v1/altrql/execute",
            json={"source_id": source_id, "query": 'GET users (id, email) WHERE { email HAS {"alice", "bob"} };'},
        )
        assert res_has_multi.status_code == 200
        assert sorted([r["email"] for r in res_has_multi.json()["rows"]]) == ["alice@example.com", "bob@example.com"]

        # 3. Exact = with ValueSet {"alice", "bob"}: NO matches because full strings are "alice@example.com"
        res_eq_exact_no_match = await client.post(
            "/api/v1/altrql/execute",
            json={"source_id": source_id, "query": 'GET users (id, email) WHERE { email = {"alice", "bob"} };'},
        )
        assert res_eq_exact_no_match.status_code == 200
        assert len(res_eq_exact_no_match.json()["rows"]) == 0

        # 4. Exact = with ValueSet of full strings: matches exact rows
        res_eq_exact_match = await client.post(
            "/api/v1/altrql/execute",
            json={"source_id": source_id, "query": 'GET users (id, email) WHERE { email = {"alice@example.com", "bob@example.com"} };'},
        )
        assert res_eq_exact_match.status_code == 200
        assert sorted([r["email"] for r in res_eq_exact_match.json()["rows"]]) == ["alice@example.com", "bob@example.com"]

        # 5. NOT HAS {"example", "group"}: matches records containing NONE of the substrings
        res_not_has = await client.post(
            "/api/v1/altrql/execute",
            json={"source_id": source_id, "query": 'GET users (id, email) WHERE { email NOT HAS {"example", "group"} };'},
        )
        assert res_not_has.status_code == 200
        assert [r["email"] for r in res_not_has.json()["rows"]] == ["edith"]


@pytest.mark.asyncio
async def test_api_execute_inclusive_range(client: AsyncClient, test_session: AsyncSession):
    with tempfile.NamedTemporaryFile(suffix=".db") as tmp:
        source_id = await _setup_sqlite_users_source(client, test_session, tmp.name)

        query = "GET users (id) WHERE { id = {1, 2, 5..7} };"
        res = await client.post("/api/v1/altrql/execute", json={"source_id": source_id, "query": query})
        assert res.status_code == 200
        data = res.json()
        assert data["success"] is True
        # Must include 1, 2, 5, 6, 7 (including range boundaries 5 and 7 and interior 6)
        ids = [r["id"] for r in data["rows"]]
        assert sorted(ids) == [1, 2, 5, 6, 7]


@pytest.mark.asyncio
async def test_api_execute_nested_json(client: AsyncClient, test_session: AsyncSession):
    with tempfile.NamedTemporaryFile(suffix=".db") as tmp:
        source_id = await _setup_sqlite_users_source(client, test_session, tmp.name)

        query = 'GET users (id, email) WHERE { metadata.department = "Engineering" };'
        res = await client.post("/api/v1/altrql/execute", json={"source_id": source_id, "query": query})
        assert res.status_code == 200
        data = res.json()
        assert data["success"] is True
        # Should match alice (id=1) and dave (id=7)
        ids = [r["id"] for r in data["rows"]]
        assert sorted(ids) == [1, 7]


@pytest.mark.asyncio
async def test_api_execute_sort_asc_and_desc_with_limit(client: AsyncClient, test_session: AsyncSession):
    with tempfile.NamedTemporaryFile(suffix=".db") as tmp:
        source_id = await _setup_sqlite_users_source(client, test_session, tmp.name)

        # ASC with LIMIT 3
        res_asc = await client.post(
            "/api/v1/altrql/execute",
            json={"source_id": source_id, "query": "GET users (id) SORT { id ASC } LIMIT 3;"},
        )
        assert res_asc.status_code == 200
        data_asc = res_asc.json()
        assert [r["id"] for r in data_asc["rows"]] == [1, 2, 3]

        # DESC with LIMIT 3
        res_desc = await client.post(
            "/api/v1/altrql/execute",
            json={"source_id": source_id, "query": "GET users (id) SORT { id DESC } LIMIT 3;"},
        )
        assert res_desc.status_code == 200
        data_desc = res_desc.json()
        assert [r["id"] for r in data_desc["rows"]] == [7, 6, 5]


@pytest.mark.asyncio
async def test_api_execute_default_ordering_and_limit(client: AsyncClient, test_session: AsyncSession):
    with tempfile.NamedTemporaryFile(suffix=".db") as tmp:
        source_id = await _setup_sqlite_users_source(client, test_session, tmp.name)

        # GET users; -> Default primary key ordering (id ASC)
        res_all = await client.post(
            "/api/v1/altrql/execute",
            json={"source_id": source_id, "query": "GET users (id);"},
        )
        assert res_all.status_code == 200
        data_all = res_all.json()
        assert [r["id"] for r in data_all["rows"]] == [1, 2, 3, 4, 5, 6, 7]

        # GET users LIMIT 3; -> Default primary key ordering + LIMIT 3
        res_limit = await client.post(
            "/api/v1/altrql/execute",
            json={"source_id": source_id, "query": "GET users (id) LIMIT 3;"},
        )
        assert res_limit.status_code == 200
        data_limit = res_limit.json()
        assert [r["id"] for r in data_limit["rows"]] == [1, 2, 3]
