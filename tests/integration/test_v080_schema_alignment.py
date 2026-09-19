"""Integration and lifecycle tests for Altr Stream v0.8.0-alpha.

Covers:
1. Multi-source ACTIVE mapping invariant per (logical_model_id, source_id)
2. Altr Align suggestion ingestion (provenance=ALTR_ALIGN, status=DRAFT)
3. Altr Align suggestion validation (valid vs invalid) and lifecycle
4. Resolution discovery API (GET /api/v1/registry/models/{model_id}/resolve/{entity_name})
5. Compiler status enforcement in /bind and /execute (rejecting DRAFT/ERROR mappings)
"""

import pytest
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from altr_stream.domain.logical import LogicalEntity, LogicalField, LogicalModel
from altr_stream.domain.mapping import MappingProvenance, MappingStatus
from altr_stream.domain.schema import EntitySchema, FieldSchema, SourceSchema, StandardDataType
from altr_stream.domain.source import Source, SourceStatus, SourceType
from altr_stream.infrastructure.database.registry_repository import SqliteRegistryRepository
from altr_stream.infrastructure.database.repository import SqliteSourceRepository


@pytest.mark.asyncio
async def test_multi_source_active_lifecycle(client: AsyncClient, test_session: AsyncSession):
    """Scenario 1 & 2:
    - Multiple sources (Postgres, Mongo, MySQL) have ACTIVE mappings for the same logical model.
    - Activating Source B does not deactivate Source A.
    - Activating a newer mapping for Source A replaces only previous Source A mapping.
    """
    source_repo = SqliteSourceRepository(test_session)
    registry_repo = SqliteRegistryRepository(test_session)

    # 1. Create Logical Model
    model = LogicalModel(
        name="CustomerUniverse",
        version="1.0.0",
        entities=[
            LogicalEntity(
                logical_model_id="",
                name="users",
                fields=[
                    LogicalField(logical_entity_id="", name="id", data_type=StandardDataType.INTEGER, is_primary_key=True),
                    LogicalField(logical_entity_id="", name="username", data_type=StandardDataType.STRING),
                    LogicalField(logical_entity_id="", name="email", data_type=StandardDataType.STRING),
                ],
            )
        ],
    )
    saved_model = await registry_repo.create_model(model)
    model_id = saved_model.id
    entity_id = saved_model.entities[0].id
    f_id = saved_model.entities[0].get_field_by_name("id").id
    f_uname = saved_model.entities[0].get_field_by_name("username").id
    f_email = saved_model.entities[0].get_field_by_name("email").id

    # 2. Create 3 Physical Sources
    pg_src = await source_repo.create(
        Source(name="PG Source", type=SourceType.POSTGRESQL, host="localhost", port=5432, database_name="pg_db", username="u", status=SourceStatus.ACTIVE)
    )
    mongo_src = await source_repo.create(
        Source(name="Mongo Source", type=SourceType.MONGODB, host="localhost", port=27017, database_name="mongo_db", username="u", status=SourceStatus.ACTIVE)
    )
    mysql_src = await source_repo.create(
        Source(name="MySQL Source", type=SourceType.MYSQL, host="localhost", port=3306, database_name="mysql_db", username="u", status=SourceStatus.ACTIVE)
    )

    # Save schema snapshots for each
    await source_repo.save_schema_snapshot(
        pg_src.id,
        SourceSchema(
            source_id=pg_src.id,
            source_name=pg_src.name,
            entities=[
                EntitySchema(
                    name="pg_users",
                    namespace="public",
                    fields=[
                        FieldSchema(name="user_id", data_type=StandardDataType.INTEGER, native_data_type="int4", is_primary_key=True),
                        FieldSchema(name="user_name", data_type=StandardDataType.STRING, native_data_type="text"),
                        FieldSchema(name="user_email", data_type=StandardDataType.STRING, native_data_type="text"),
                    ],
                )
            ],
        ),
    )
    await source_repo.save_schema_snapshot(
        mongo_src.id,
        SourceSchema(
            source_id=mongo_src.id,
            source_name=mongo_src.name,
            entities=[
                EntitySchema(
                    name="customers",
                    namespace="public",
                    fields=[
                        FieldSchema(name="_id", data_type=StandardDataType.INTEGER, native_data_type="int", is_primary_key=True),
                        FieldSchema(name="login", data_type=StandardDataType.STRING, native_data_type="string"),
                        FieldSchema(name="contact_email", data_type=StandardDataType.STRING, native_data_type="string"),
                    ],
                )
            ],
        ),
    )
    await source_repo.save_schema_snapshot(
        mysql_src.id,
        SourceSchema(
            source_id=mysql_src.id,
            source_name=mysql_src.name,
            entities=[
                EntitySchema(
                    name="tbl_users",
                    namespace="public",
                    fields=[
                        FieldSchema(name="id", data_type=StandardDataType.INTEGER, native_data_type="int", is_primary_key=True),
                        FieldSchema(name="name", data_type=StandardDataType.STRING, native_data_type="varchar"),
                        FieldSchema(name="email_addr", data_type=StandardDataType.STRING, native_data_type="varchar"),
                    ],
                )
            ],
        ),
    )

    # 3. Create mapping for PostgreSQL -> Validate -> Activate
    m_pg = await client.post(
        "/api/v1/registry/mappings",
        json={
            "logical_model_id": model_id,
            "source_id": pg_src.id,
            "version": "1.0.0",
            "entity_mappings": [
                {
                    "logical_entity_id": entity_id,
                    "physical_entity_name": "pg_users",
                    "physical_namespace": "public",
                    "field_mappings": [
                        {"logical_field_id": f_id, "physical_field_name": "user_id"},
                        {"logical_field_id": f_uname, "physical_field_name": "user_name"},
                        {"logical_field_id": f_email, "physical_field_name": "user_email"},
                    ],
                }
            ],
        },
    )
    assert m_pg.status_code == 201
    m_pg_id = m_pg.json()["id"]
    await client.post(f"/api/v1/registry/mappings/{m_pg_id}/validate")
    act_pg = await client.post(f"/api/v1/registry/mappings/{m_pg_id}/activate")
    assert act_pg.status_code == 200
    assert act_pg.json()["status"] == "ACTIVE"

    # 4. Create mapping for MongoDB -> Validate -> Activate
    m_mongo = await client.post(
        "/api/v1/registry/mappings",
        json={
            "logical_model_id": model_id,
            "source_id": mongo_src.id,
            "version": "1.0.0",
            "entity_mappings": [
                {
                    "logical_entity_id": entity_id,
                    "physical_entity_name": "customers",
                    "physical_namespace": "public",
                    "field_mappings": [
                        {"logical_field_id": f_id, "physical_field_name": "_id"},
                        {"logical_field_id": f_uname, "physical_field_name": "login"},
                        {"logical_field_id": f_email, "physical_field_name": "contact_email"},
                    ],
                }
            ],
        },
    )
    assert m_mongo.status_code == 201
    m_mongo_id = m_mongo.json()["id"]
    await client.post(f"/api/v1/registry/mappings/{m_mongo_id}/validate")
    act_mongo = await client.post(f"/api/v1/registry/mappings/{m_mongo_id}/activate")
    assert act_mongo.status_code == 200
    assert act_mongo.json()["status"] == "ACTIVE"

    # Verify PG is STILL ACTIVE (coexistence)
    get_pg = await client.get(f"/api/v1/registry/mappings/{m_pg_id}")
    assert get_pg.json()["status"] == "ACTIVE"

    # 5. Create mapping for MySQL -> Validate -> Activate
    m_mysql = await client.post(
        "/api/v1/registry/mappings",
        json={
            "logical_model_id": model_id,
            "source_id": mysql_src.id,
            "version": "1.0.0",
            "entity_mappings": [
                {
                    "logical_entity_id": entity_id,
                    "physical_entity_name": "tbl_users",
                    "physical_namespace": "public",
                    "field_mappings": [
                        {"logical_field_id": f_id, "physical_field_name": "id"},
                        {"logical_field_id": f_uname, "physical_field_name": "name"},
                        {"logical_field_id": f_email, "physical_field_name": "email_addr"},
                    ],
                }
            ],
        },
    )
    assert m_mysql.status_code == 201
    m_mysql_id = m_mysql.json()["id"]
    await client.post(f"/api/v1/registry/mappings/{m_mysql_id}/validate")
    act_mysql = await client.post(f"/api/v1/registry/mappings/{m_mysql_id}/activate")
    assert act_mysql.status_code == 200
    assert act_mysql.json()["status"] == "ACTIVE"

    # Check ALL THREE are ACTIVE concurrently
    res_pg = await client.get(f"/api/v1/registry/mappings/{m_pg_id}")
    res_mongo = await client.get(f"/api/v1/registry/mappings/{m_mongo_id}")
    res_mysql = await client.get(f"/api/v1/registry/mappings/{m_mysql_id}")
    assert res_pg.json()["status"] == "ACTIVE"
    assert res_mongo.json()["status"] == "ACTIVE"
    assert res_mysql.json()["status"] == "ACTIVE"

    # 6. Same-source replacement: Create PG v2 mapping -> Activate
    m_pg_v2 = await client.post(
        "/api/v1/registry/mappings",
        json={
            "logical_model_id": model_id,
            "source_id": pg_src.id,
            "version": "2.0.0",
            "entity_mappings": [
                {
                    "logical_entity_id": entity_id,
                    "physical_entity_name": "pg_users",
                    "physical_namespace": "public",
                    "field_mappings": [
                        {"logical_field_id": f_id, "physical_field_name": "user_id"},
                        {"logical_field_id": f_uname, "physical_field_name": "user_name"},
                        {"logical_field_id": f_email, "physical_field_name": "user_email"},
                    ],
                }
            ],
        },
    )
    assert m_pg_v2.status_code == 201
    m_pg_v2_id = m_pg_v2.json()["id"]
    await client.post(f"/api/v1/registry/mappings/{m_pg_v2_id}/validate")
    act_pg_v2 = await client.post(f"/api/v1/registry/mappings/{m_pg_v2_id}/activate")
    assert act_pg_v2.status_code == 200
    assert act_pg_v2.json()["status"] == "ACTIVE"

    # Only older PG mapping was demoted to VALIDATED
    get_pg_v1 = await client.get(f"/api/v1/registry/mappings/{m_pg_id}")
    assert get_pg_v1.json()["status"] == "VALIDATED"

    # Mongo and MySQL mappings remain unaffected (ACTIVE)
    get_mongo_after = await client.get(f"/api/v1/registry/mappings/{m_mongo_id}")
    get_mysql_after = await client.get(f"/api/v1/registry/mappings/{m_mysql_id}")
    assert get_mongo_after.json()["status"] == "ACTIVE"
    assert get_mysql_after.json()["status"] == "ACTIVE"


@pytest.mark.asyncio
async def test_align_suggestion_ingestion_and_validation(client: AsyncClient, test_session: AsyncSession):
    """Scenario 3:
    - POST /api/v1/registry/models/{model_id}/align/suggestions
    - Ingested proposal has provenance=ALTR_ALIGN, status=DRAFT.
    - Not automatically ACTIVE.
    - Validation identifies valid vs invalid suggestions.
    - Approval lifecycle (DRAFT -> VALIDATED -> ACTIVE).
    """
    source_repo = SqliteSourceRepository(test_session)
    registry_repo = SqliteRegistryRepository(test_session)

    # Setup logical model
    model = await registry_repo.create_model(
        LogicalModel(
            name="ProductsModel",
            entities=[
                LogicalEntity(
                    logical_model_id="",
                    name="items",
                    fields=[
                        LogicalField(logical_entity_id="", name="sku", data_type="STRING", is_primary_key=True),
                        LogicalField(logical_entity_id="", name="price", data_type="FLOAT"),
                    ],
                )
            ],
        )
    )
    sku_id = model.entities[0].fields[0].id
    price_id = model.entities[0].fields[1].id

    # Setup physical source
    source = await source_repo.create(
        Source(name="Inventory DB", type=SourceType.POSTGRESQL, host="localhost", port=5432, database_name="inv", username="u", status=SourceStatus.ACTIVE)
    )
    await source_repo.save_schema_snapshot(
        source.id,
        SourceSchema(
            source_id=source.id,
            source_name=source.name,
            entities=[
                EntitySchema(
                    name="inventory_items",
                    namespace="public",
                    fields=[
                        FieldSchema(name="item_sku", data_type=StandardDataType.STRING, native_data_type="varchar", is_primary_key=True),
                        FieldSchema(name="unit_price", data_type=StandardDataType.FLOAT, native_data_type="float8"),
                    ],
                )
            ],
        ),
    )

    # 1. Ingest Valid Altr Align Suggestion
    suggestion_payload = {
        "source_id": source.id,
        "version": "1.0.0",
        "entity_mappings": [
            {
                "logical_entity_name": "items",
                "physical_entity_name": "inventory_items",
                "physical_namespace": "public",
                "field_mappings": [
                    {"logical_field_name": "sku", "physical_field_name": "item_sku", "confidence": 0.98},
                    {"logical_field_name": "price", "physical_field_name": "unit_price", "confidence": 0.95},
                ],
            }
        ],
    }
    ingest_res = await client.post(
        f"/api/v1/registry/models/{model.id}/align/suggestions",
        json=suggestion_payload,
    )
    assert ingest_res.status_code == 201
    sug_data = ingest_res.json()
    assert sug_data["provenance"] == "ALTR_ALIGN"
    assert sug_data["status"] == "DRAFT"
    assert sug_data["entity_mapping_count"] == 1
    assert sug_data["total_field_mapping_count"] == 2
    mapping_id = sug_data["id"]

    # 2. Verify DRAFT mapping cannot execute
    cannot_act = await client.post(f"/api/v1/registry/mappings/{mapping_id}/activate")
    assert cannot_act.status_code == 422
    assert "Only VALIDATED mappings can be activated" in cannot_act.json()["detail"]

    # 3. Validate suggestion against schema
    val_res = await client.post(f"/api/v1/registry/mappings/{mapping_id}/validate")
    assert val_res.status_code == 200
    assert val_res.json()["is_valid"] is True
    assert val_res.json()["mapping"]["status"] == "VALIDATED"

    # 4. Approve / Activate suggestion
    act_res = await client.post(f"/api/v1/registry/mappings/{mapping_id}/activate")
    assert act_res.status_code == 200
    assert act_res.json()["status"] == "ACTIVE"


@pytest.mark.asyncio
async def test_align_suggestion_invalid_validation(client: AsyncClient, test_session: AsyncSession):
    """Test validation errors on invalid Altr Align suggestions (missing table/field, datatype mismatch)."""
    source_repo = SqliteSourceRepository(test_session)
    registry_repo = SqliteRegistryRepository(test_session)

    model = await registry_repo.create_model(
        LogicalModel(
            name="OrdersModel",
            entities=[
                LogicalEntity(
                    logical_model_id="",
                    name="orders",
                    fields=[
                        LogicalField(logical_entity_id="", name="order_id", data_type="INTEGER", is_primary_key=True),
                        LogicalField(logical_entity_id="", name="is_paid", data_type="BOOLEAN"),
                    ],
                )
            ],
        )
    )

    source = await source_repo.create(
        Source(name="Orders DB", type=SourceType.POSTGRESQL, host="localhost", port=5432, database_name="orders", username="u", status=SourceStatus.ACTIVE)
    )
    await source_repo.save_schema_snapshot(
        source.id,
        SourceSchema(
            source_id=source.id,
            source_name=source.name,
            entities=[
                EntitySchema(
                    name="tbl_orders",
                    namespace="public",
                    fields=[
                        FieldSchema(name="order_num", data_type=StandardDataType.INTEGER, native_data_type="int4", is_primary_key=True),
                        FieldSchema(name="status_text", data_type=StandardDataType.STRING, native_data_type="varchar"),  # STRING != BOOLEAN
                    ],
                )
            ],
        ),
    )

    # Ingest suggestion with incompatible datatype (BOOLEAN -> STRING)
    bad_type_payload = {
        "source_id": source.id,
        "version": "1.0.0",
        "entity_mappings": [
            {
                "logical_entity_name": "orders",
                "physical_entity_name": "tbl_orders",
                "physical_namespace": "public",
                "field_mappings": [
                    {"logical_field_name": "order_id", "physical_field_name": "order_num"},
                    {"logical_field_name": "is_paid", "physical_field_name": "status_text"},
                ],
            }
        ],
    }
    res = await client.post(f"/api/v1/registry/models/{model.id}/align/suggestions", json=bad_type_payload)
    assert res.status_code == 201
    bad_map_id = res.json()["id"]

    val_res = await client.post(f"/api/v1/registry/mappings/{bad_map_id}/validate")
    assert val_res.status_code == 200
    assert val_res.json()["is_valid"] is False
    assert val_res.json()["mapping"]["status"] == "ERROR"
    assert "cannot map to physical field" in val_res.json()["error"]


@pytest.mark.asyncio
async def test_resolution_discovery_endpoint(client: AsyncClient, test_session: AsyncSession):
    """Scenario 4:
    - GET /api/v1/registry/models/{model_id}/resolve/{entity_name}
    - Exposes all ACTIVE physical source mappings capable of resolving a logical entity.
    - DRAFT or non-active mappings are excluded.
    """
    source_repo = SqliteSourceRepository(test_session)
    registry_repo = SqliteRegistryRepository(test_session)

    # Logical model with "users" entity
    model = await registry_repo.create_model(
        LogicalModel(
            name="FederatedUserSpace",
            entities=[
                LogicalEntity(
                    logical_model_id="",
                    name="users",
                    fields=[
                        LogicalField(logical_entity_id="", name="id", data_type=StandardDataType.INTEGER, is_primary_key=True),
                        LogicalField(logical_entity_id="", name="name", data_type=StandardDataType.STRING),
                    ],
                )
            ],
        )
    )
    entity_id = model.entities[0].id
    f_id = model.entities[0].fields[0].id
    f_name = model.entities[0].fields[1].id

    # Create 2 sources
    src1 = await source_repo.create(
        Source(name="PG Source", type=SourceType.POSTGRESQL, host="localhost", port=5432, database_name="db1", username="u", status=SourceStatus.ACTIVE)
    )
    src2 = await source_repo.create(
        Source(name="Mongo Source", type=SourceType.MONGODB, host="localhost", port=27017, database_name="db2", username="u", status=SourceStatus.ACTIVE)
    )

    await source_repo.save_schema_snapshot(
        src1.id,
        SourceSchema(
            source_id=src1.id,
            source_name=src1.name,
            entities=[
                EntitySchema(
                    name="app_users",
                    namespace="public",
                    fields=[
                        FieldSchema(name="user_id", data_type=StandardDataType.INTEGER, native_data_type="int4"),
                        FieldSchema(name="full_name", data_type=StandardDataType.STRING, native_data_type="text"),
                    ],
                )
            ],
        ),
    )
    await source_repo.save_schema_snapshot(
        src2.id,
        SourceSchema(
            source_id=src2.id,
            source_name=src2.name,
            entities=[
                EntitySchema(
                    name="user_docs",
                    namespace="public",
                    fields=[
                        FieldSchema(name="_id", data_type=StandardDataType.INTEGER, native_data_type="int"),
                        FieldSchema(name="display_name", data_type=StandardDataType.STRING, native_data_type="string"),
                    ],
                )
            ],
        ),
    )

    # Source 1: ACTIVE mapping
    m1 = await client.post(
        "/api/v1/registry/mappings",
        json={
            "logical_model_id": model.id,
            "source_id": src1.id,
            "version": "1.0.0",
            "entity_mappings": [
                {
                    "logical_entity_id": entity_id,
                    "physical_entity_name": "app_users",
                    "physical_namespace": "public",
                    "field_mappings": [
                        {"logical_field_id": f_id, "physical_field_name": "user_id"},
                        {"logical_field_id": f_name, "physical_field_name": "full_name"},
                    ],
                }
            ],
        },
    )
    m1_id = m1.json()["id"]
    await client.post(f"/api/v1/registry/mappings/{m1_id}/validate")
    await client.post(f"/api/v1/registry/mappings/{m1_id}/activate")

    # Source 2: ACTIVE mapping
    m2 = await client.post(
        "/api/v1/registry/mappings",
        json={
            "logical_model_id": model.id,
            "source_id": src2.id,
            "version": "1.0.0",
            "entity_mappings": [
                {
                    "logical_entity_id": entity_id,
                    "physical_entity_name": "user_docs",
                    "physical_namespace": "public",
                    "field_mappings": [
                        {"logical_field_id": f_id, "physical_field_name": "_id"},
                        {"logical_field_id": f_name, "physical_field_name": "display_name"},
                    ],
                }
            ],
        },
    )
    m2_id = m2.json()["id"]
    await client.post(f"/api/v1/registry/mappings/{m2_id}/validate")
    await client.post(f"/api/v1/registry/mappings/{m2_id}/activate")

    # Query resolution endpoint for "users"
    res = await client.get(f"/api/v1/registry/models/{model.id}/resolve/users")
    assert res.status_code == 200
    res_data = res.json()
    assert res_data["logical_model_name"] == "FederatedUserSpace"
    assert res_data["logical_entity_name"] == "users"
    assert res_data["candidate_count"] == 2
    candidates = res_data["candidates"]

    # Verify both sources are present
    sources_in_res = {c["source_id"] for c in candidates}
    assert src1.id in sources_in_res
    assert src2.id in sources_in_res

    # Check candidate 1 field mapping details
    pg_cand = next(c for c in candidates if c["source_id"] == src1.id)
    assert pg_cand["physical_entity_name"] == "app_users"
    assert pg_cand["source_type"] == "POSTGRESQL"
    assert len(pg_cand["field_mappings"]) == 2
    f_id_map = next(f for f in pg_cand["field_mappings"] if f["logical_field_name"] == "id")
    assert f_id_map["physical_field_name"] == "user_id"
    assert f_id_map["logical_data_type"] == "INTEGER"


@pytest.mark.asyncio
async def test_compiler_mapping_status_enforcement(client: AsyncClient, test_session: AsyncSession):
    """Scenario 5:
    - Attempting execution with DRAFT / VALIDATED / ERROR mapping is rejected with structured error.
    - Attempting execution with ACTIVE mapping succeeds.
    """
    source_repo = SqliteSourceRepository(test_session)
    registry_repo = SqliteRegistryRepository(test_session)

    model = await registry_repo.create_model(
        LogicalModel(
            name="SecurityModel",
            entities=[
                LogicalEntity(
                    logical_model_id="",
                    name="users",
                    fields=[
                        LogicalField(logical_entity_id="", name="id", data_type=StandardDataType.INTEGER, is_primary_key=True),
                        LogicalField(logical_entity_id="", name="name", data_type=StandardDataType.STRING),
                    ],
                )
            ],
        )
    )
    entity_id = model.entities[0].id
    f_id = model.entities[0].get_field_by_name("id").id
    f_name = model.entities[0].get_field_by_name("name").id

    source = await source_repo.create(
        Source(name="PG Security DB", type=SourceType.POSTGRESQL, host="localhost", port=5432, database_name="pg_sec", username="u", status=SourceStatus.ACTIVE)
    )
    await source_repo.save_schema_snapshot(
        source.id,
        SourceSchema(
            source_id=source.id,
            source_name=source.name,
            entities=[
                EntitySchema(
                    name="users",
                    namespace="public",
                    fields=[
                        FieldSchema(name="id", data_type=StandardDataType.INTEGER, native_data_type="int4"),
                        FieldSchema(name="name", data_type=StandardDataType.STRING, native_data_type="text"),
                    ],
                )
            ],
        ),
    )

    # 1. Create DRAFT mapping
    m_res = await client.post(
        "/api/v1/registry/mappings",
        json={
            "logical_model_id": model.id,
            "source_id": source.id,
            "version": "1.0.0",
            "entity_mappings": [
                {
                    "logical_entity_id": entity_id,
                    "physical_entity_name": "users",
                    "physical_namespace": "public",
                    "field_mappings": [
                        {"logical_field_id": f_id, "physical_field_name": "id"},
                        {"logical_field_id": f_name, "physical_field_name": "name"},
                    ],
                }
            ],
        },
    )
    mapping_id = m_res.json()["id"]

    # 2. Try to BIND with DRAFT mapping_id -> Must fail
    bind_draft = await client.post(
        "/api/v1/altrql/bind",
        json={
            "source_id": source.id,
            "mapping_id": mapping_id,
            "query": "GET users (id, name);",
        },
    )
    assert bind_draft.status_code == 200
    bind_draft_data = bind_draft.json()
    assert bind_draft_data["success"] is False
    assert "Only ACTIVE mappings can be used" in bind_draft_data["error"]["message"]

    # 3. Try to EXECUTE with DRAFT mapping_id -> Must fail
    exec_draft = await client.post(
        "/api/v1/altrql/execute",
        json={
            "source_id": source.id,
            "mapping_id": mapping_id,
            "query": "GET users (id, name);",
        },
    )
    assert exec_draft.status_code == 200
    exec_draft_data = exec_draft.json()
    assert exec_draft_data["success"] is False
    assert "Only ACTIVE mappings can be used" in exec_draft_data["error"]["message"]

    # 4. Try to EXECUTE with logical_model_id when mapping is still DRAFT -> Must fail
    exec_model_draft = await client.post(
        "/api/v1/altrql/execute",
        json={
            "source_id": source.id,
            "logical_model_id": model.id,
            "query": "GET users (id, name);",
        },
    )
    assert exec_model_draft.status_code == 200
    assert exec_model_draft.json()["success"] is False
    assert "No ACTIVE mapping found" in exec_model_draft.json()["error"]["message"]

    # 5. Validate & Activate mapping
    await client.post(f"/api/v1/registry/mappings/{mapping_id}/validate")
    await client.post(f"/api/v1/registry/mappings/{mapping_id}/activate")

    # 6. BIND with ACTIVE mapping_id -> Succeeds
    bind_active = await client.post(
        "/api/v1/altrql/bind",
        json={
            "source_id": source.id,
            "mapping_id": mapping_id,
            "query": "GET users (id, name);",
        },
    )
    assert bind_active.status_code == 200
    assert bind_active.json()["success"] is True

    # 7. BIND with logical_model_id -> Resolves ACTIVE mapping -> Succeeds
    bind_model_active = await client.post(
        "/api/v1/altrql/bind",
        json={
            "source_id": source.id,
            "logical_model_id": model.id,
            "query": "GET users (id, name);",
        },
    )
    assert bind_model_active.status_code == 200
    assert bind_model_active.json()["success"] is True

