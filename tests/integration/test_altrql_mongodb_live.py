"""Live integration tests for MongoDB AltrQL Lowering and Execution (Milestone v0.7.5-alpha).

Tests the full AltrQL query pipeline against a live MongoDB container:
AltrQL -> parse -> bind -> classify -> MongoDBLowerer -> PhysicalQuery -> MongoDBConnector -> QueryResult.
"""

import asyncio
from datetime import datetime, timezone
import json
import pytest
from httpx import AsyncClient

from altr_stream.domain.source import ConnectionConfig
from altr_stream.infrastructure.connectors.mongodb.connector import MongoDBConnector

MONGO_CONFIG = ConnectionConfig(
    host="localhost",
    port=27017,
    database_name="altr_test_db",
    username="altr_test_user",
    password="altr_test_pass",
    options={"authSource": "admin"},
)

SEED_USERS = [
    {"id_num": 1, "email": "alice@example.com", "username": "alice", "status": "ACTIVE", "age": 25, "is_active": True, "metadata": {"department": "Engineering", "tier": "gold"}, "score": 95.5},
    {"id_num": 2, "email": "bob@example.com", "username": "bob", "status": "PENDING", "age": 30, "is_active": True, "metadata": {"department": "Analytics", "tier": "silver"}, "score": 88.0},
    {"id_num": 3, "email": "carol@example.com", "username": "carol", "status": "INACTIVE", "age": 22, "is_active": False, "metadata": {"department": "Operations", "tier": "bronze"}, "score": 75.0},
    {"id_num": 4, "email": "dave@corp.net", "username": "dave", "status": "ACTIVE", "age": 40, "is_active": True, "metadata": None, "score": 91.0},
    {"id_num": 5, "email": "eve@test.org", "username": "eve", "status": "SUSPENDED", "age": 19, "is_active": False, "metadata": None, "score": 62.5},
]


async def _is_mongodb_available() -> bool:
    try:
        conn = MongoDBConnector(MONGO_CONFIG, timeout_sec=2.0)
        res = await conn.test_connection()
        return res.success
    except Exception:
        return False


@pytest.fixture(scope="module")
def event_loop():
    loop = asyncio.new_event_loop()
    yield loop
    loop.close()


@pytest.mark.asyncio
async def test_altrql_mongodb_live_pipeline(client: AsyncClient):
    """Execute live AltrQL queries across all CRUD and semantic query forms against live MongoDB."""
    if not await _is_mongodb_available():
        pytest.skip("MongoDB test container not available on port 27017")

    # 1. Reset collection directly in MongoDB
    connector = MongoDBConnector(MONGO_CONFIG)
    async with connector:
        # Delete any existing test data in live_altrql_users
        await connector.execute_query(
            "mongodb:delete_many",
            [{"collection": "live_altrql_users", "filter": {}}],
        )
        # Seed initial documents
        await connector.execute_query(
            "mongodb:insert_many",
            [{"collection": "live_altrql_users", "documents": SEED_USERS, "ordered": True}],
        )

    # 2. Register MongoDB source in API
    src_res = await client.post(
        "/api/v1/sources",
        json={
            "name": "Live-MongoDB-AltrQL",
            "type": "MONGODB",
            "host": MONGO_CONFIG.host,
            "port": MONGO_CONFIG.port,
            "database_name": MONGO_CONFIG.database_name,
            "username": MONGO_CONFIG.username,
            "password": MONGO_CONFIG.password,
            "options": MONGO_CONFIG.options,
        },
    )
    assert src_res.status_code == 201
    source_id = src_res.json()["id"]

    # 3. Discover schema
    disc_res = await client.post(f"/api/v1/sources/{source_id}/schema/discover")
    assert disc_res.status_code == 200

    # Helper for running AltrQL
    async def exec_altrql(query: str, confirm_mass: bool = False):
        res = await client.post(
            "/api/v1/altrql/execute",
            json={
                "source_id": source_id,
                "query": query,
                "confirm_mass_mutation": confirm_mass,
            },
        )
        assert res.status_code == 200, f"HTTP failure: {res.text}"
        data = res.json()
        assert data["success"] is True, f"AltrQL query failure: {data.get('error')}"
        return data

    # -----------------------------------------------------------------------
    # Case 1: Simple GET (Wildcard)
    # -----------------------------------------------------------------------
    r1 = await exec_altrql("GET live_altrql_users;")
    assert r1["metadata"]["row_count"] == 5
    assert len(r1["rows"]) == 5
    emails = [row["email"] for row in r1["rows"]]
    assert "alice@example.com" in emails
    assert "dave@corp.net" in emails

    # -----------------------------------------------------------------------
    # Case 2: Specific Projection (excluding _id)
    # -----------------------------------------------------------------------
    r2 = await exec_altrql("GET live_altrql_users (email, age);")
    assert r2["columns"] == ["email", "age"]
    for row in r2["rows"]:
        assert "_id" not in row
        assert "email" in row
        assert "age" in row

    # -----------------------------------------------------------------------
    # Case 3: Equality Filter
    # -----------------------------------------------------------------------
    r3 = await exec_altrql('GET live_altrql_users WHERE { email = "alice@example.com" };')
    assert r3["metadata"]["row_count"] == 1
    assert r3["rows"][0]["email"] == "alice@example.com"

    # -----------------------------------------------------------------------
    # Case 4: ValueSet Exact Membership
    # -----------------------------------------------------------------------
    r4 = await exec_altrql('GET live_altrql_users WHERE { status = {"ACTIVE", "PENDING"} };')
    assert r4["metadata"]["row_count"] == 3
    found_statuses = {row["status"] for row in r4["rows"]}
    assert found_statuses == {"ACTIVE", "PENDING"}

    # -----------------------------------------------------------------------
    # Case 5: HAS Substring Match (re.escape regex)
    # -----------------------------------------------------------------------
    r5 = await exec_altrql('GET live_altrql_users WHERE { email HAS "example" };')
    assert r5["metadata"]["row_count"] == 3
    for row in r5["rows"]:
        assert "example" in row["email"]

    # -----------------------------------------------------------------------
    # Case 6: HAS ValueSet (ANY Substring)
    # -----------------------------------------------------------------------
    r6 = await exec_altrql('GET live_altrql_users WHERE { email HAS {"alice", "corp"} };')
    assert r6["metadata"]["row_count"] == 2
    r6_emails = {row["email"] for row in r6["rows"]}
    assert r6_emails == {"alice@example.com", "dave@corp.net"}

    # -----------------------------------------------------------------------
    # Case 7: NOT HAS Substring Negation (preserving NULL/missing)
    # -----------------------------------------------------------------------
    r7 = await exec_altrql('GET live_altrql_users WHERE { email NOT HAS "example" };')
    assert r7["metadata"]["row_count"] == 2
    r7_emails = {row["email"] for row in r7["rows"]}
    assert r7_emails == {"dave@corp.net", "eve@test.org"}

    # -----------------------------------------------------------------------
    # Case 8: Inclusive Ranges
    # -----------------------------------------------------------------------
    r8 = await exec_altrql("GET live_altrql_users WHERE { age = 22..30 };")
    assert r8["metadata"]["row_count"] == 3
    r8_ages = {row["age"] for row in r8["rows"]}
    assert r8_ages == {22, 25, 30}

    # -----------------------------------------------------------------------
    # Case 9: NULL Equality and Inequality
    # -----------------------------------------------------------------------
    r9_null = await exec_altrql("GET live_altrql_users WHERE { metadata = NULL };")
    assert r9_null["metadata"]["row_count"] == 2
    r9_null_emails = {row["email"] for row in r9_null["rows"]}
    assert r9_null_emails == {"dave@corp.net", "eve@test.org"}

    r9_not_null = await exec_altrql("GET live_altrql_users WHERE { metadata != NULL };")
    assert r9_not_null["metadata"]["row_count"] == 3
    r9_not_null_emails = {row["email"] for row in r9_not_null["rows"]}
    assert r9_not_null_emails == {"alice@example.com", "bob@example.com", "carol@example.com"}

    # -----------------------------------------------------------------------
    # Case 10: Nested Dotted Field Filter
    # -----------------------------------------------------------------------
    r10 = await exec_altrql('GET live_altrql_users WHERE { metadata.department = "Engineering" };')
    assert r10["metadata"]["row_count"] == 1
    assert r10["rows"][0]["email"] == "alice@example.com"

    # -----------------------------------------------------------------------
    # Case 11: Explicit SORT Block
    # -----------------------------------------------------------------------
    r11 = await exec_altrql("GET live_altrql_users SORT { age DESC, username ASC };")
    assert r11["metadata"]["row_count"] == 5
    ages = [row["age"] for row in r11["rows"]]
    assert ages == [40, 30, 25, 22, 19]

    # -----------------------------------------------------------------------
    # Case 12: TOP N BY Ranking & OFFSET
    # -----------------------------------------------------------------------
    r12 = await exec_altrql("GET live_altrql_users TOP 2 BY age OFFSET 1;")
    assert r12["metadata"]["row_count"] == 2
    assert r12["rows"][0]["age"] == 30  # 40 is skipped
    assert r12["rows"][1]["age"] == 25

    # -----------------------------------------------------------------------
    # Case 13: CREATE Single & Batch
    # -----------------------------------------------------------------------
    r13_create = await exec_altrql(
        'CREATE live_altrql_users ( email: "frank@test.com", username: "frank", age: 33, status: "ACTIVE", is_active: TRUE, score: 82.0 );'
    )
    assert r13_create["metadata"]["operation"] == "CREATE"
    assert r13_create["metadata"]["affected_rows"] == 1

    # Verify frank is now in collection
    r13_verify = await exec_altrql('GET live_altrql_users WHERE { email = "frank@test.com" };')
    assert r13_verify["metadata"]["row_count"] == 1

    # -----------------------------------------------------------------------
    # Case 14: UPDATE Operation ($set)
    # -----------------------------------------------------------------------
    r14_update = await exec_altrql(
        'UPDATE live_altrql_users ( status: "PROMOTED", score: 99.0 ) WHERE { email = "frank@test.com" };'
    )
    assert r14_update["metadata"]["operation"] == "UPDATE"
    assert r14_update["metadata"]["affected_rows"] == 1

    r14_verify = await exec_altrql('GET live_altrql_users WHERE { email = "frank@test.com" };')
    assert r14_verify["rows"][0]["status"] == "PROMOTED"
    assert r14_verify["rows"][0]["score"] == 99.0

    # -----------------------------------------------------------------------
    # Case 15: DELETE Operation
    # -----------------------------------------------------------------------
    r15_del = await exec_altrql('DELETE live_altrql_users WHERE { email = "frank@test.com" };')
    assert r15_del["metadata"]["operation"] == "DELETE"
    assert r15_del["metadata"]["affected_rows"] == 1

    r15_verify = await exec_altrql('GET live_altrql_users WHERE { email = "frank@test.com" };')
    assert r15_verify["metadata"]["row_count"] == 0
