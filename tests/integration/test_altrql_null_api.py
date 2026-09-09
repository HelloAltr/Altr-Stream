"""Live integration tests for AltrQL v0.5 NULL semantics against real PostgreSQL."""

from httpx import AsyncClient
import pytest

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


@pytest.mark.asyncio
async def test_postgres_live_null_semantics_lifecycle(client: AsyncClient):
    """End-to-end integration test verifying AltrQL NULL semantics in live PostgreSQL."""
    if not await _is_postgres_available():
        pytest.skip("PostgreSQL test container not available on port 5432")

    # 1. Register PostgreSQL Source
    source_payload = {
        "name": "Live NULL Test Source",
        "type": "POSTGRESQL",
        "host": PG_CONFIG.host,
        "port": PG_CONFIG.port,
        "database_name": PG_CONFIG.database_name,
        "username": PG_CONFIG.username,
        "password": PG_CONFIG.password,
    }
    src_res = await client.post("/api/v1/sources", json=source_payload)
    assert src_res.status_code == 201
    source_id = src_res.json()["id"]

    # 2. Discover Schema
    disc_res = await client.post(f"/api/v1/sources/{source_id}/schema/discover")
    assert disc_res.status_code == 200

    # 3. Clean up any leftover test categories from previous test runs
    clean_res = await client.post(
        "/api/v1/queries/execute",
        json={
            "source_id": source_id,
            "query": "DELETE FROM categories WHERE code LIKE 'NULL_TEST_%';",
        },
    )
    assert clean_res.status_code == 200

    # 4. CREATE category with explicit NULL description
    res_c1 = await client.post(
        "/api/v1/altrql/execute",
        json={
            "source_id": source_id,
            "query": 'CREATE categories ( code: "NULL_TEST_1", name: "Null Explicit Cat", description: NULL );',
        },
    )
    assert res_c1.status_code == 200
    data_c1 = res_c1.json()
    assert data_c1["success"] is True
    assert len(data_c1["rows"]) == 1
    assert data_c1["rows"][0]["description"] is None

    # 5. CREATE category with omitted description (database produces NULL)
    res_c2 = await client.post(
        "/api/v1/altrql/execute",
        json={
            "source_id": source_id,
            "query": 'CREATE categories ( code: "NULL_TEST_2", name: "Null Omitted Cat" );',
        },
    )
    assert res_c2.status_code == 200
    data_c2 = res_c2.json()
    assert data_c2["success"] is True
    assert len(data_c2["rows"]) == 1
    assert data_c2["rows"][0]["description"] is None

    # 6. GET categories WHERE { description = NULL }
    res_get_null = await client.post(
        "/api/v1/altrql/execute",
        json={
            "source_id": source_id,
            "query": "GET categories WHERE { description = NULL };",
        },
    )
    assert res_get_null.status_code == 200
    data_get_null = res_get_null.json()
    assert data_get_null["success"] is True
    null_codes = {r["code"] for r in data_get_null["rows"]}
    assert "NULL_TEST_1" in null_codes
    assert "NULL_TEST_2" in null_codes

    # 7. GET categories WHERE { description != NULL }
    res_get_not_null = await client.post(
        "/api/v1/altrql/execute",
        json={
            "source_id": source_id,
            "query": "GET categories WHERE { description != NULL };",
        },
    )
    assert res_get_not_null.status_code == 200
    data_get_not_null = res_get_not_null.json()
    assert data_get_not_null["success"] is True
    not_null_codes = {r["code"] for r in data_get_not_null["rows"]}
    assert "ELECTRONICS" in not_null_codes
    assert "SOFTWARE" in not_null_codes
    assert "NULL_TEST_1" not in not_null_codes

    # 8. GET with ValueSet containing NULL
    res_vs_null = await client.post(
        "/api/v1/altrql/execute",
        json={
            "source_id": source_id,
            "query": 'GET categories WHERE { code = {"ELECTRONICS", NULL} };',
        },
    )
    assert res_vs_null.status_code == 200
    data_vs_null = res_vs_null.json()
    assert data_vs_null["success"] is True
    vs_codes = {r["code"] for r in data_vs_null["rows"]}
    assert "ELECTRONICS" in vs_codes

    # 9a. GET with ValueSet inequality (!=) containing NULL (NULLs must be EXCLUDED)
    res_vs_neq = await client.post(
        "/api/v1/altrql/execute",
        json={
            "source_id": source_id,
            "query": 'GET categories WHERE { description != {"Devices, computers, and microcontrollers", NULL} };',
        },
    )
    assert res_vs_neq.status_code == 200
    data_vs_neq = res_vs_neq.json()
    assert data_vs_neq["success"] is True
    vs_neq_codes = {r["code"] for r in data_vs_neq["rows"]}
    assert "ELECTRONICS" not in vs_neq_codes
    assert "NULL_TEST_1" not in vs_neq_codes
    assert "NULL_TEST_2" not in vs_neq_codes
    assert "SOFTWARE" in vs_neq_codes

    # 9b. GET with ValueSet inequality (!=) WITHOUT NULL (NULLs must be INCLUDED under 2-valued logic)
    res_vs_neq_no_null = await client.post(
        "/api/v1/altrql/execute",
        json={
            "source_id": source_id,
            "query": 'GET categories WHERE { description != {"Devices, computers, and microcontrollers"} };',
        },
    )
    assert res_vs_neq_no_null.status_code == 200
    data_vs_neq_no_null = res_vs_neq_no_null.json()
    assert data_vs_neq_no_null["success"] is True
    vs_neq_no_null_codes = {r["code"] for r in data_vs_neq_no_null["rows"]}
    assert "ELECTRONICS" not in vs_neq_no_null_codes
    assert "NULL_TEST_1" in vs_neq_no_null_codes
    assert "NULL_TEST_2" in vs_neq_no_null_codes
    assert "SOFTWARE" in vs_neq_no_null_codes

    # 9c. GET with NOT HAS (NULLs must evaluate to TRUE under 2-valued logic)
    res_not_has = await client.post(
        "/api/v1/altrql/execute",
        json={
            "source_id": source_id,
            "query": 'GET categories WHERE { description NOT HAS "computers" };',
        },
    )
    assert res_not_has.status_code == 200
    data_not_has = res_not_has.json()
    assert data_not_has["success"] is True
    not_has_codes = {r["code"] for r in data_not_has["rows"]}
    assert "ELECTRONICS" not in not_has_codes
    assert "NULL_TEST_1" in not_has_codes
    assert "NULL_TEST_2" in not_has_codes
    assert "SOFTWARE" in not_has_codes

    # 10. UPDATE record setting description to NULL
    res_update_null = await client.post(
        "/api/v1/altrql/execute",
        json={
            "source_id": source_id,
            "query": 'UPDATE categories ( description: NULL ) WHERE { code = "NULL_TEST_1" };',
        },
    )
    assert res_update_null.status_code == 200
    data_update_null = res_update_null.json()
    assert data_update_null["success"] is True
    assert len(data_update_null["rows"]) == 1
    assert data_update_null["rows"][0]["description"] is None

    # 11. DELETE with NULL predicate (constrained delete)
    res_del_null = await client.post(
        "/api/v1/altrql/execute",
        json={
            "source_id": source_id,
            "query": "DELETE categories WHERE { description = NULL };",
        },
    )
    assert res_del_null.status_code == 200
    data_del_null = res_del_null.json()
    assert data_del_null["success"] is True
    del_codes = {r["code"] for r in data_del_null["rows"]}
    assert "NULL_TEST_1" in del_codes
    assert "NULL_TEST_2" in del_codes
    assert "ELECTRONICS" not in del_codes

    # 12. Mass DELETE without confirmation should be rejected
    res_mass = await client.post(
        "/api/v1/altrql/execute",
        json={
            "source_id": source_id,
            "query": "DELETE categories;",
            "confirm_mass_mutation": False,
        },
    )
    assert res_mass.status_code == 200
    data_mass = res_mass.json()
    assert data_mass["success"] is False
    assert data_mass["error"]["type"] == "MassMutationConfirmationRequiredError"


@pytest.mark.asyncio
async def test_postgres_live_json_null_semantics(client: AsyncClient):
    """Integration test verifying JSONB field NULL and non-NULL semantics against live PostgreSQL."""
    if not await _is_postgres_available():
        pytest.skip("PostgreSQL test container not available on port 5432")

    # 1. Register PostgreSQL Source
    source_payload = {
        "name": "Live JSON NULL Test Source",
        "type": "POSTGRESQL",
        "host": PG_CONFIG.host,
        "port": PG_CONFIG.port,
        "database_name": PG_CONFIG.database_name,
        "username": PG_CONFIG.username,
        "password": PG_CONFIG.password,
    }
    src_res = await client.post("/api/v1/sources", json=source_payload)
    assert src_res.status_code == 201
    source_id = src_res.json()["id"]

    # 2. Discover Schema
    disc_res = await client.post(f"/api/v1/sources/{source_id}/schema/discover")
    assert disc_res.status_code == 200

    # Clean up any leftover test user
    await client.post(
        "/api/v1/queries/execute",
        json={
            "source_id": source_id,
            "query": "DELETE FROM users WHERE email = 'json_null_user@example.com';",
        },
    )

    # 3. GET users WHERE { metadata != NULL }
    res_not_null = await client.post(
        "/api/v1/altrql/execute",
        json={
            "source_id": source_id,
            "query": "GET users (email, metadata) WHERE { metadata != NULL };",
        },
    )
    assert res_not_null.status_code == 200
    data_not_null = res_not_null.json()
    assert data_not_null["success"] is True
    emails_with_metadata = {r["email"] for r in data_not_null["rows"]}
    assert "alice@example.com" in emails_with_metadata
    assert "bob@example.com" in emails_with_metadata
    assert "carol@example.com" in emails_with_metadata

    # 4. CREATE user with explicit metadata: NULL
    res_create = await client.post(
        "/api/v1/altrql/execute",
        json={
            "source_id": source_id,
            "query": 'CREATE users ( email: "json_null_user@example.com", full_name: "JSON Null User", metadata: NULL );',
        },
    )
    assert res_create.status_code == 200
    data_create = res_create.json()
    assert data_create["success"] is True
    assert data_create["rows"][0]["metadata"] is None

    # 5. GET users WHERE { metadata = NULL }
    res_null = await client.post(
        "/api/v1/altrql/execute",
        json={
            "source_id": source_id,
            "query": "GET users (email, metadata) WHERE { metadata = NULL };",
        },
    )
    assert res_null.status_code == 200
    data_null = res_null.json()
    assert data_null["success"] is True
    null_emails = {r["email"] for r in data_null["rows"]}
    assert "json_null_user@example.com" in null_emails
    assert "bob@example.com" not in null_emails

    # 6. UPDATE user setting JSON metadata to NULL
    res_update = await client.post(
        "/api/v1/altrql/execute",
        json={
            "source_id": source_id,
            "query": 'UPDATE users ( metadata: NULL ) WHERE { email = "bob@example.com" };',
        },
    )
    assert res_update.status_code == 200
    data_update = res_update.json()
    assert data_update["success"] is True
    assert data_update["rows"][0]["metadata"] is None

    # Verify bob now matches metadata = NULL
    res_null2 = await client.post(
        "/api/v1/altrql/execute",
        json={
            "source_id": source_id,
            "query": "GET users (email, metadata) WHERE { metadata = NULL };",
        },
    )
    assert "bob@example.com" in {r["email"] for r in res_null2.json()["rows"]}

    # Restore bob's metadata
    await client.post(
        "/api/v1/queries/execute",
        json={
            "source_id": source_id,
            "query": "UPDATE users SET metadata = '{\"department\": \"Analytics\", \"tier\": \"silver\"}'::jsonb WHERE email = 'bob@example.com';",
        },
    )

    # 7. Non-NULL comparison on JSON field must fail validation
    res_invalid_comp = await client.post(
        "/api/v1/altrql/execute",
        json={
            "source_id": source_id,
            "query": 'GET users WHERE { metadata = "Engineering" };',
        },
    )
    assert res_invalid_comp.status_code == 200
    data_invalid_comp = res_invalid_comp.json()
    assert data_invalid_comp["success"] is False
    assert data_invalid_comp["error"]["type"] == "TypeCompatibilityError"
    assert "unsupported AltrQL comparison type 'JSON'" in data_invalid_comp["error"]["message"]

    # 8. Non-NULL mutation on JSON field must fail validation
    res_invalid_mut = await client.post(
        "/api/v1/altrql/execute",
        json={
            "source_id": source_id,
            "query": 'CREATE users ( email: "invalid_json@example.com", full_name: "Bad", metadata: "bad_str" );',
        },
    )
    assert res_invalid_mut.status_code == 200
    data_invalid_mut = res_invalid_mut.json()
    assert data_invalid_mut["success"] is False
    assert data_invalid_mut["error"]["type"] == "TypeCompatibilityError"
    assert "unsupported AltrQL mutation type 'JSON'" in data_invalid_mut["error"]["message"]

    # Clean up test user
    await client.post(
        "/api/v1/queries/execute",
        json={
            "source_id": source_id,
            "query": "DELETE FROM users WHERE email = 'json_null_user@example.com';",
        },
    )

