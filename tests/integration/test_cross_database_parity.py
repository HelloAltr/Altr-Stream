"""Cross-database semantic parity tests for AltrQL across SQLite, PostgreSQL, MySQL, and MongoDB.

Verifies that identical AltrQL queries produce equivalent logical results across all 4 physical targets.
"""

import asyncio
import json
import sqlite3
import tempfile
from httpx import AsyncClient
import pytest

from altr_stream.domain.source import ConnectionConfig
from altr_stream.infrastructure.connectors.mongodb.connector import MongoDBConnector
from altr_stream.infrastructure.connectors.mysql.connector import MySQLConnector
from altr_stream.infrastructure.connectors.postgres.connector import PostgreSQLConnector

PG_CONFIG = ConnectionConfig(
    host="localhost",
    port=5432,
    database_name="altr_test_db",
    username="altr_test_user",
    password="altr_test_pass",
)

MYSQL_CONFIG = ConnectionConfig(
    host="localhost",
    port=3306,
    database_name="altr_test_db",
    username="altr_test_user",
    password="altr_test_pass",
)

MONGO_CONFIG = ConnectionConfig(
    host="localhost",
    port=27017,
    database_name="altr_test_db",
    username="altr_test_user",
    password="altr_test_pass",
    options={"authSource": "admin"},
)

SEED_USERS = [
    (1, "alice@example.com", "ACTIVE", 25, True, json.dumps({"department": "Engineering", "tier": "gold"})),
    (2, "bob@example.com", "PENDING", 30, True, json.dumps({"department": "Analytics", "tier": "silver"})),
    (3, "carol@example.com", "INACTIVE", 22, False, json.dumps({"department": "Operations", "tier": "bronze"})),
    (4, "dave@corp.net", "ACTIVE", 40, True, None),
    (5, "eve@test.org", "SUSPENDED", 19, False, None),
]


async def _is_target_available(connector) -> bool:
    try:
        res = await connector.test_connection()
        return res.success
    except Exception:
        return False


@pytest.fixture(scope="module")
def event_loop():
    loop = asyncio.new_event_loop()
    yield loop
    loop.close()


@pytest.mark.asyncio
async def test_cross_database_semantic_parity(client: AsyncClient):
    """Execute identical AltrQL queries across SQLite, PostgreSQL, MySQL, and MongoDB, verifying parity."""
    # 1. Check availability of live containers
    pg_conn = PostgreSQLConnector(PG_CONFIG, timeout_sec=2.0)
    mysql_conn = MySQLConnector(MYSQL_CONFIG, timeout_sec=2.0)
    mongo_conn = MongoDBConnector(MONGO_CONFIG, timeout_sec=2.0)

    pg_available = await _is_target_available(pg_conn)
    mysql_available = await _is_target_available(mysql_conn)
    mongo_available = await _is_target_available(mongo_conn)

    if not pg_available or not mysql_available or not mongo_available:
        pytest.skip("PostgreSQL, MySQL, or MongoDB container not available on default test ports")

    # 2. Setup SQLite database file
    temp_db = tempfile.NamedTemporaryFile(suffix=".db", delete=False)
    sqlite_db_path = temp_db.name
    temp_db.close()

    sq_conn = sqlite3.connect(sqlite_db_path)
    sq_cur = sq_conn.cursor()
    sq_cur.execute("""
        CREATE TABLE parity_users (
            id INTEGER PRIMARY KEY,
            email TEXT NOT NULL,
            status TEXT,
            age INTEGER,
            is_active BOOLEAN NOT NULL,
            metadata TEXT
        );
    """)
    for row in SEED_USERS:
        sq_cur.execute("INSERT INTO parity_users VALUES (?, ?, ?, ?, ?, ?);", (row[0], row[1], row[2], row[3], 1 if row[4] else 0, row[5]))
    sq_conn.commit()
    sq_conn.close()

    # 3. Setup PostgreSQL table
    async with pg_conn:
        await pg_conn.execute_query("DROP TABLE IF EXISTS parity_users;")
        await pg_conn.execute_query("""
            CREATE TABLE parity_users (
                id INTEGER PRIMARY KEY,
                email VARCHAR(255) NOT NULL,
                status VARCHAR(50),
                age INTEGER,
                is_active BOOLEAN NOT NULL,
                metadata JSONB
            );
        """)
        for row in SEED_USERS:
            meta_val = f"'{row[5]}'::jsonb" if row[5] else "NULL"
            await pg_conn.execute_query(
                f"INSERT INTO parity_users (id, email, status, age, is_active, metadata) VALUES ({row[0]}, '{row[1]}', '{row[2]}', {row[3]}, {str(row[4]).lower()}, {meta_val});"
            )

    # 4. Setup MySQL table
    async with mysql_conn:
        await mysql_conn.execute_query("DROP TABLE IF EXISTS parity_users;")
        await mysql_conn.execute_query("""
            CREATE TABLE parity_users (
                id INT PRIMARY KEY,
                email VARCHAR(255) NOT NULL,
                status VARCHAR(50),
                age INT,
                is_active TINYINT(1) NOT NULL,
                metadata JSON
            );
        """)
        for row in SEED_USERS:
            meta_val = f"'{row[5]}'" if row[5] else "NULL"
            await mysql_conn.execute_query(
                f"INSERT INTO parity_users (id, email, status, age, is_active, metadata) VALUES ({row[0]}, '{row[1]}', '{row[2]}', {row[3]}, {1 if row[4] else 0}, {meta_val});"
            )

    # 5. Setup MongoDB collection
    async with mongo_conn:
        await mongo_conn.execute_query("mongodb:delete_many", [{"collection": "parity_users", "filter": {}}])
        mongo_docs = [
            {
                "id": row[0],
                "email": row[1],
                "status": row[2],
                "age": row[3],
                "is_active": row[4],
                "metadata": json.loads(row[5]) if row[5] else None,
            }
            for row in SEED_USERS
        ]
        await mongo_conn.execute_query(
            "mongodb:insert_many",
            [{"collection": "parity_users", "documents": mongo_docs, "ordered": True}],
        )

    # 6. Register sources in Altr Stream
    src_sq = await client.post("/api/v1/sources", json={"name": "Parity-SQLite", "type": "SQLITE", "file_path": sqlite_db_path})
    src_pg = await client.post("/api/v1/sources", json={"name": "Parity-Postgres", "type": "POSTGRESQL", "host": PG_CONFIG.host, "port": PG_CONFIG.port, "database_name": PG_CONFIG.database_name, "username": PG_CONFIG.username, "password": PG_CONFIG.password})
    src_my = await client.post("/api/v1/sources", json={"name": "Parity-MySQL", "type": "MYSQL", "host": MYSQL_CONFIG.host, "port": MYSQL_CONFIG.port, "database_name": MYSQL_CONFIG.database_name, "username": MYSQL_CONFIG.username, "password": MYSQL_CONFIG.password})
    src_mg = await client.post("/api/v1/sources", json={"name": "Parity-MongoDB", "type": "MONGODB", "host": MONGO_CONFIG.host, "port": MONGO_CONFIG.port, "database_name": MONGO_CONFIG.database_name, "username": MONGO_CONFIG.username, "password": MONGO_CONFIG.password, "options": MONGO_CONFIG.options})

    sq_id = src_sq.json()["id"]
    pg_id = src_pg.json()["id"]
    my_id = src_my.json()["id"]
    mg_id = src_mg.json()["id"]

    # 7. Discover schemas for all 4
    await client.post(f"/api/v1/sources/{sq_id}/schema/discover")
    await client.post(f"/api/v1/sources/{pg_id}/schema/discover")
    await client.post(f"/api/v1/sources/{my_id}/schema/discover")
    await client.post(f"/api/v1/sources/{mg_id}/schema/discover")

    # Helper to execute query on all 4 sources and extract comparable results
    async def run_query(query: str):
        r_sq = await client.post("/api/v1/altrql/execute", json={"source_id": sq_id, "query": query})
        r_pg = await client.post("/api/v1/altrql/execute", json={"source_id": pg_id, "query": query})
        r_my = await client.post("/api/v1/altrql/execute", json={"source_id": my_id, "query": query})
        r_mg = await client.post("/api/v1/altrql/execute", json={"source_id": mg_id, "query": query})

        assert r_sq.status_code == 200 and r_sq.json()["success"] is True, f"SQLite failed: {r_sq.text}"
        assert r_pg.status_code == 200 and r_pg.json()["success"] is True, f"PG failed: {r_pg.text}"
        assert r_my.status_code == 200 and r_my.json()["success"] is True, f"MySQL failed: {r_my.text}"
        assert r_mg.status_code == 200 and r_mg.json()["success"] is True, f"MongoDB failed: {r_mg.text}"

        def normalize_rows(rows):
            return [(r.get("id"), r.get("email")) for r in rows]

        return (
            normalize_rows(r_sq.json()["rows"]),
            normalize_rows(r_pg.json()["rows"]),
            normalize_rows(r_my.json()["rows"]),
            normalize_rows(r_mg.json()["rows"]),
        )

    # -----------------------------------------------------------------------
    # Case 1: Simple GET + Default Deterministic Ordering (id ASC)
    # -----------------------------------------------------------------------
    sq_rows, pg_rows, my_rows, mg_rows = await run_query("GET parity_users;")
    expected_all = [(1, "alice@example.com"), (2, "bob@example.com"), (3, "carol@example.com"), (4, "dave@corp.net"), (5, "eve@test.org")]
    assert sq_rows == expected_all
    assert pg_rows == expected_all
    assert my_rows == expected_all
    assert mg_rows == expected_all

    # -----------------------------------------------------------------------
    # Case 2: Equality Predicate
    # -----------------------------------------------------------------------
    sq_rows, pg_rows, my_rows, mg_rows = await run_query('GET parity_users WHERE { email = "alice@example.com" };')
    assert sq_rows == [(1, "alice@example.com")]
    assert pg_rows == [(1, "alice@example.com")]
    assert my_rows == [(1, "alice@example.com")]
    assert mg_rows == [(1, "alice@example.com")]

    # -----------------------------------------------------------------------
    # Case 3: ValueSet Exact Membership
    # -----------------------------------------------------------------------
    sq_rows, pg_rows, my_rows, mg_rows = await run_query('GET parity_users WHERE { status = {"ACTIVE", "PENDING"} };')
    assert sq_rows == [(1, "alice@example.com"), (2, "bob@example.com"), (4, "dave@corp.net")]
    assert pg_rows == sq_rows
    assert my_rows == sq_rows
    assert mg_rows == sq_rows

    # -----------------------------------------------------------------------
    # Case 4: ValueSet with Numbers and Range
    # -----------------------------------------------------------------------
    sq_rows, pg_rows, my_rows, mg_rows = await run_query("GET parity_users WHERE { age = {19, 25..30} };")
    assert sq_rows == [(1, "alice@example.com"), (2, "bob@example.com"), (5, "eve@test.org")]
    assert pg_rows == sq_rows
    assert my_rows == sq_rows
    assert mg_rows == sq_rows

    # -----------------------------------------------------------------------
    # Case 5: HAS Substring Matching
    # -----------------------------------------------------------------------
    sq_rows, pg_rows, my_rows, mg_rows = await run_query('GET parity_users WHERE { email HAS "example" };')
    assert sq_rows == [(1, "alice@example.com"), (2, "bob@example.com"), (3, "carol@example.com")]
    assert pg_rows == sq_rows
    assert my_rows == sq_rows
    assert mg_rows == sq_rows

    # -----------------------------------------------------------------------
    # Case 6: HAS ValueSet Matching ANY Substring
    # -----------------------------------------------------------------------
    sq_rows, pg_rows, my_rows, mg_rows = await run_query('GET parity_users WHERE { email HAS {"alice", "corp"} };')
    assert sq_rows == [(1, "alice@example.com"), (4, "dave@corp.net")]
    assert pg_rows == sq_rows
    assert my_rows == sq_rows
    assert mg_rows == sq_rows

    # -----------------------------------------------------------------------
    # Case 7: NOT HAS Substring Negation (preserving NULL behavior)
    # -----------------------------------------------------------------------
    sq_rows, pg_rows, my_rows, mg_rows = await run_query('GET parity_users WHERE { email NOT HAS "example" };')
    assert sq_rows == [(4, "dave@corp.net"), (5, "eve@test.org")]
    assert pg_rows == sq_rows
    assert my_rows == sq_rows
    assert mg_rows == sq_rows

    # -----------------------------------------------------------------------
    # Case 8: Inclusive Ranges
    # -----------------------------------------------------------------------
    sq_rows, pg_rows, my_rows, mg_rows = await run_query("GET parity_users WHERE { age = {22..30} };")
    assert sq_rows == [(1, "alice@example.com"), (2, "bob@example.com"), (3, "carol@example.com")]
    assert pg_rows == sq_rows
    assert my_rows == sq_rows
    assert mg_rows == sq_rows

    # -----------------------------------------------------------------------
    # Case 9: Combined WHERE Predicates (AND)
    # -----------------------------------------------------------------------
    sq_rows, pg_rows, my_rows, mg_rows = await run_query("""
    GET parity_users WHERE {
        status = "ACTIVE",
        is_active = TRUE,
        age >= 25
    };
    """)
    assert sq_rows == [(1, "alice@example.com"), (4, "dave@corp.net")]
    assert pg_rows == sq_rows
    assert my_rows == sq_rows
    assert mg_rows == sq_rows

    # -----------------------------------------------------------------------
    # Case 10: Explicit Sorting (DESC)
    # -----------------------------------------------------------------------
    sq_rows, pg_rows, my_rows, mg_rows = await run_query("GET parity_users SORT { age DESC, id ASC };")
    expected_sorted = [(4, "dave@corp.net"), (2, "bob@example.com"), (1, "alice@example.com"), (3, "carol@example.com"), (5, "eve@test.org")]
    assert sq_rows == expected_sorted
    assert pg_rows == expected_sorted
    assert my_rows == expected_sorted
    assert mg_rows == expected_sorted

    # -----------------------------------------------------------------------
    # Case 11: Pagination (LIMIT & OFFSET)
    # -----------------------------------------------------------------------
    sq_rows, pg_rows, my_rows, mg_rows = await run_query("GET parity_users TOP 2 BY id OFFSET 1;")
    expected_top = [(4, "dave@corp.net"), (3, "carol@example.com")]
    assert sq_rows == expected_top
    assert pg_rows == expected_top
    assert my_rows == expected_top
    assert mg_rows == expected_top

    # -----------------------------------------------------------------------
    # Case 12: Nested JSON Field Extraction
    # -----------------------------------------------------------------------
    sq_rows, pg_rows, my_rows, mg_rows = await run_query('GET parity_users WHERE { metadata.department = "Engineering" };')
    assert sq_rows == [(1, "alice@example.com")]
    assert pg_rows == sq_rows
    assert my_rows == sq_rows
    assert mg_rows == sq_rows

    # -----------------------------------------------------------------------
    # Case 13: NULL Equality & ValueSet with NULL
    # -----------------------------------------------------------------------
    sq_rows, pg_rows, my_rows, mg_rows = await run_query("GET parity_users WHERE { metadata = NULL };")
    assert sq_rows == [(4, "dave@corp.net"), (5, "eve@test.org")]
    assert pg_rows == sq_rows
    assert my_rows == sq_rows
    assert mg_rows == sq_rows

    sq_rows, pg_rows, my_rows, mg_rows = await run_query("GET parity_users WHERE { metadata != NULL };")
    assert sq_rows == [(1, "alice@example.com"), (2, "bob@example.com"), (3, "carol@example.com")]
    assert pg_rows == sq_rows
    assert my_rows == sq_rows
    assert mg_rows == sq_rows
