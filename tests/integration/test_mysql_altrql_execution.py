"""Live integration tests for AltrQL execution against native MySQL 8.x."""

import asyncio
from httpx import AsyncClient
import pytest

from altr_stream.domain.source import ConnectionConfig, SourceType
from altr_stream.infrastructure.connectors.mysql.connector import MySQLConnector

MYSQL_CONFIG = ConnectionConfig(
    host="localhost",
    port=3306,
    database_name="altr_test_db",
    username="altr_test_user",
    password="altr_test_pass",
)


async def _is_mysql_available() -> bool:
    try:
        conn = MySQLConnector(MYSQL_CONFIG, timeout_sec=2.0)
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
async def test_mysql_live_altrql_execution_via_api(client: AsyncClient):
    """Verify live end-to-end execution of AltrQL queries against MySQL through REST API."""
    if not await _is_mysql_available():
        pytest.skip("MySQL test container not available on port 3306")

    # 1. Register MySQL source
    source_payload = {
        "name": "Live MySQL AltrQL Test Source",
        "type": "MYSQL",
        "host": MYSQL_CONFIG.host,
        "port": MYSQL_CONFIG.port,
        "database_name": MYSQL_CONFIG.database_name,
        "username": MYSQL_CONFIG.username,
        "password": MYSQL_CONFIG.password,
    }
    src_res = await client.post("/api/v1/sources", json=source_payload)
    assert src_res.status_code == 201
    source_id = src_res.json()["id"]

    # 2. Discover schema
    disc_res = await client.post(f"/api/v1/sources/{source_id}/schema/discover")
    assert disc_res.status_code == 200

    # 3. Simple GET with default PK ordering
    res1 = await client.post(
        "/api/v1/altrql/execute",
        json={"source_id": source_id, "query": "GET users;"},
    )
    assert res1.status_code == 200
    data1 = res1.json()
    assert data1["success"] is True
    assert data1["physical_query"]["dialect"] == "mysql"
    assert "ORDER BY `id` ASC" in data1["physical_query"]["query"]
    assert len(data1["rows"]) >= 3
    # Check default ascending ordering
    ids = [r["id"] for r in data1["rows"]]
    assert ids == sorted(ids)

    # 4. GET with WHERE equality
    res2 = await client.post(
        "/api/v1/altrql/execute",
        json={"source_id": source_id, "query": 'GET users WHERE { email = "alice@example.com" };'},
    )
    assert res2.status_code == 200
    data2 = res2.json()
    assert data2["success"] is True
    assert len(data2["rows"]) == 1
    assert data2["rows"][0]["email"] == "alice@example.com"

    # 5. GET with ValueSet exact membership
    res3 = await client.post(
        "/api/v1/altrql/execute",
        json={"source_id": source_id, "query": "GET users WHERE { id = {1, 2} };"},
    )
    assert res3.status_code == 200
    data3 = res3.json()
    assert data3["success"] is True
    assert len(data3["rows"]) == 2
    assert {r["id"] for r in data3["rows"]} == {1, 2}

    # 6. GET with HAS substring match
    res4 = await client.post(
        "/api/v1/altrql/execute",
        json={"source_id": source_id, "query": 'GET users WHERE { email HAS "alice" };'},
    )
    assert res4.status_code == 200
    data4 = res4.json()
    assert data4["success"] is True
    assert len(data4["rows"]) >= 1
    assert "alice" in data4["rows"][0]["email"]

    # 7. GET with HAS ValueSet (matches ANY substring)
    res5 = await client.post(
        "/api/v1/altrql/execute",
        json={"source_id": source_id, "query": 'GET users WHERE { email HAS {"alice", "bob"} };'},
    )
    assert res5.status_code == 200
    data5 = res5.json()
    assert data5["success"] is True
    assert len(data5["rows"]) == 2

    # 8. GET with NOT HAS
    res6 = await client.post(
        "/api/v1/altrql/execute",
        json={"source_id": source_id, "query": 'GET users WHERE { email NOT HAS "alice" };'},
    )
    assert res6.status_code == 200
    data6 = res6.json()
    assert data6["success"] is True
    for r in data6["rows"]:
        assert "alice" not in r["email"]

    # 9. GET with Range filter
    res7 = await client.post(
        "/api/v1/altrql/execute",
        json={"source_id": source_id, "query": "GET products WHERE { price = {500..3000} };"},
    )
    assert res7.status_code == 200
    data7 = res7.json()
    assert data7["success"] is True
    assert len(data7["rows"]) >= 2
    for r in data7["rows"]:
        assert 500 <= float(r["price"]) <= 3000

    # 10. GET with Nested JSON extraction
    res8 = await client.post(
        "/api/v1/altrql/execute",
        json={"source_id": source_id, "query": 'GET users WHERE { metadata.tier = "gold" };'},
    )
    assert res8.status_code == 200
    data8 = res8.json()
    assert data8["success"] is True
    assert len(data8["rows"]) == 1
    assert data8["rows"][0]["email"] == "alice@example.com"

    # 11. GET with Explicit SORT override
    res9 = await client.post(
        "/api/v1/altrql/execute",
        json={"source_id": source_id, "query": "GET users SORT { id DESC };"},
    )
    assert res9.status_code == 200
    data9 = res9.json()
    assert data9["success"] is True
    ids_desc = [r["id"] for r in data9["rows"]]
    assert ids_desc == sorted(ids_desc, reverse=True)

    # 12. GET with LIMIT and OFFSET
    res10 = await client.post(
        "/api/v1/altrql/execute",
        json={"source_id": source_id, "query": "GET users TOP 2 BY id OFFSET 1;"},
    )
    assert res10.status_code == 200
    data10 = res10.json()
    assert data10["success"] is True
    assert len(data10["rows"]) == 2
    # TOP 2 BY id produces ORDER BY id DESC LIMIT 2 OFFSET 1
    assert "LIMIT 2 OFFSET 1" in data10["physical_query"]["query"]


@pytest.mark.asyncio
async def test_mysql_live_altrql_mutations_and_batch(client: AsyncClient):
    """Verify live AltrQL mutations (CREATE, UPDATE, DELETE) against MySQL."""
    if not await _is_mysql_available():
        pytest.skip("MySQL test container not available on port 3306")

    # 1. Register MySQL source
    source_payload = {
        "name": "Live MySQL Mutation Test Source",
        "type": "MYSQL",
        "host": MYSQL_CONFIG.host,
        "port": MYSQL_CONFIG.port,
        "database_name": MYSQL_CONFIG.database_name,
        "username": MYSQL_CONFIG.username,
        "password": MYSQL_CONFIG.password,
    }
    src_res = await client.post("/api/v1/sources", json=source_payload)
    assert src_res.status_code == 201
    source_id = src_res.json()["id"]

    # 2. Discover schema
    disc_res = await client.post(f"/api/v1/sources/{source_id}/schema/discover")
    assert disc_res.status_code == 200

    # 3. CREATE single entity
    create_query = """
    CREATE categories (
        code: "DEV_TOOLS",
        name: "Developer Tools",
        description: "Compilers, debuggers, and IDEs"
    );
    """
    res_c = await client.post(
        "/api/v1/altrql/execute",
        json={"source_id": source_id, "query": create_query},
    )
    assert res_c.status_code == 200
    data_c = res_c.json()
    assert data_c["success"] is True
    assert data_c["classification"]["operation"] == "CREATE"

    # Verify created
    res_v1 = await client.post(
        "/api/v1/altrql/execute",
        json={"source_id": source_id, "query": 'GET categories WHERE { code = "DEV_TOOLS" };'},
    )
    assert len(res_v1.json()["rows"]) == 1
    assert res_v1.json()["rows"][0]["name"] == "Developer Tools"

    # 4. UPDATE entity
    update_query = """
    UPDATE categories (
        name: "Developer Tools Updated"
    ) WHERE {
        code = "DEV_TOOLS"
    };
    """
    res_u = await client.post(
        "/api/v1/altrql/execute",
        json={"source_id": source_id, "query": update_query},
    )
    assert res_u.status_code == 200
    assert res_u.json()["success"] is True

    # Verify updated
    res_v2 = await client.post(
        "/api/v1/altrql/execute",
        json={"source_id": source_id, "query": 'GET categories WHERE { code = "DEV_TOOLS" };'},
    )
    assert res_v2.json()["rows"][0]["name"] == "Developer Tools Updated"

    # 5. DELETE entity (constrained)
    delete_query = 'DELETE categories WHERE { code = "DEV_TOOLS" };'
    res_d = await client.post(
        "/api/v1/altrql/execute",
        json={"source_id": source_id, "query": delete_query},
    )
    assert res_d.status_code == 200
    assert res_d.json()["success"] is True

    # Verify deleted
    res_v3 = await client.post(
        "/api/v1/altrql/execute",
        json={"source_id": source_id, "query": 'GET categories WHERE { code = "DEV_TOOLS" };'},
    )
    assert len(res_v3.json()["rows"]) == 0
