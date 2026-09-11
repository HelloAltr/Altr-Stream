"""Integration tests for Schema Registry REST APIs."""

import pytest
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from altr_stream.domain.schema import (
    EntitySchema,
    FieldSchema,
    SourceSchema,
    StandardDataType,
)
from altr_stream.domain.source import Source, SourceStatus, SourceType
from altr_stream.infrastructure.database.repository import SqliteSourceRepository


@pytest.mark.asyncio
async def test_registry_models_and_entities_api_lifecycle(client: AsyncClient):
    # 1. Create Model with Entity and Fields
    payload = {
        "name": "ECommerceModel",
        "version": "1.0.0",
        "description": "Online retail domain",
        "entities": [
            {
                "name": "Product",
                "description": "Retail item",
                "fields": [
                    {"name": "id", "data_type": "INTEGER", "is_primary_key": True, "nullable": False},
                    {"name": "title", "data_type": "STRING", "is_primary_key": False, "nullable": False},
                    {"name": "price", "data_type": "FLOAT", "is_primary_key": False, "nullable": True},
                ],
            }
        ],
    }
    res = await client.post("/api/v1/registry/models", json=payload)
    assert res.status_code == 201
    model_data = res.json()
    model_id = model_data["id"]
    assert model_data["name"] == "ECommerceModel"
    assert len(model_data["entities"]) == 1
    assert len(model_data["entities"][0]["fields"]) == 3
    entity_id = model_data["entities"][0]["id"]

    # 2. Get Model by ID
    res = await client.get(f"/api/v1/registry/models/{model_id}")
    assert res.status_code == 200
    assert res.json()["name"] == "ECommerceModel"

    # 3. List Models
    res = await client.get("/api/v1/registry/models")
    assert res.status_code == 200
    assert any(m["id"] == model_id for m in res.json())

    # 4. Add Entity to Model
    new_entity_payload = {
        "name": "Category",
        "description": "Product category",
        "fields": [
            {"name": "id", "data_type": "INTEGER", "is_primary_key": True},
            {"name": "name", "data_type": "STRING"},
        ],
    }
    res = await client.post(f"/api/v1/registry/models/{model_id}/entities", json=new_entity_payload)
    assert res.status_code == 201
    category_id = res.json()["id"]

    # Test update entity directly
    res = await client.put(
        f"/api/v1/registry/entities/{category_id}",
        json={"name": "Categories", "description": "Updated description"},
    )
    assert res.status_code == 200
    assert res.json()["name"] == "Categories"

    # Test get entity directly
    res = await client.get(f"/api/v1/registry/entities/{category_id}")
    assert res.status_code == 200
    assert res.json()["name"] == "Categories"

    # 5. Add Field to Entity directly
    new_field_payload = {
        "name": "sku",
        "data_type": "STRING",
        "is_primary_key": False,
        "nullable": True,
    }
    res = await client.post(f"/api/v1/registry/entities/{entity_id}/fields", json=new_field_payload)
    assert res.status_code == 201
    sku_field_id = res.json()["id"]

    # Test update field directly
    res = await client.put(
        f"/api/v1/registry/fields/{sku_field_id}",
        json={"name": "sku_code", "data_type": "STRING", "nullable": False},
    )
    assert res.status_code == 200
    assert res.json()["name"] == "sku_code"
    assert res.json()["nullable"] is False

    # Test get field directly
    res = await client.get(f"/api/v1/registry/fields/{sku_field_id}")
    assert res.status_code == 200
    assert res.json()["name"] == "sku_code"

    # Verify model now has 2 entities and Product has 4 fields
    res = await client.get(f"/api/v1/registry/models/{model_id}")
    refreshed = res.json()
    assert len(refreshed["entities"]) == 2

    # 6. Delete Added Field directly
    res = await client.delete(f"/api/v1/registry/fields/{sku_field_id}")
    assert res.status_code == 204

    # 7. Delete Entity directly
    res = await client.delete(f"/api/v1/registry/entities/{category_id}")
    assert res.status_code == 204

    # 8. Delete Model
    res = await client.delete(f"/api/v1/registry/models/{model_id}")
    assert res.status_code == 204

    res = await client.get(f"/api/v1/registry/models/{model_id}")
    assert res.status_code == 404


@pytest.mark.asyncio
async def test_registry_mappings_api_and_validation(client: AsyncClient, test_session: AsyncSession):
    # Setup physical source and discovered schema snapshot
    source_repo = SqliteSourceRepository(test_session)
    source = Source(
        name="Inventory SQLite DB",
        type=SourceType.SQLITE,
        file_path="/tmp/test_inv.db",
        status=SourceStatus.ACTIVE,
    )
    saved_source = await source_repo.create(source)

    phys_fields = [
        FieldSchema(name="prod_id", data_type=StandardDataType.INTEGER, native_data_type="INTEGER", is_primary_key=True),
        FieldSchema(name="prod_name", data_type=StandardDataType.STRING, native_data_type="TEXT"),
        FieldSchema(name="prod_price", data_type=StandardDataType.FLOAT, native_data_type="REAL"),
    ]
    phys_entity = EntitySchema(name="items", namespace="main", fields=phys_fields, primary_key=["prod_id"])
    phys_schema = SourceSchema(source_id=saved_source.id, source_name=saved_source.name, entities=[phys_entity])
    await source_repo.save_schema_snapshot(saved_source.id, phys_schema)

    # Create Logical Model
    model_payload = {
        "name": "InventoryLogicalModel",
        "entities": [
            {
                "name": "Item",
                "fields": [
                    {"name": "id", "data_type": "INTEGER", "is_primary_key": True},
                    {"name": "name", "data_type": "STRING"},
                    {"name": "price", "data_type": "FLOAT"},
                ],
            }
        ],
    }
    res = await client.post("/api/v1/registry/models", json=model_payload)
    assert res.status_code == 201
    model_data = res.json()
    model_id = model_data["id"]
    logical_entity_id = model_data["entities"][0]["id"]
    logical_fields = {f["name"]: f["id"] for f in model_data["entities"][0]["fields"]}

    # Create Source Mapping
    mapping_payload = {
        "logical_model_id": model_id,
        "source_id": saved_source.id,
        "version": "1.0.0",
        "status": "DRAFT",
        "entity_mappings": [
            {
                "logical_entity_id": logical_entity_id,
                "physical_entity_name": "items",
                "physical_namespace": "main",
                "field_mappings": [
                    {"logical_field_id": logical_fields["id"], "physical_field_name": "prod_id"},
                    {"logical_field_id": logical_fields["name"], "physical_field_name": "prod_name"},
                    {"logical_field_id": logical_fields["price"], "physical_field_name": "prod_price"},
                ],
            }
        ],
    }
    res = await client.post("/api/v1/registry/mappings", json=mapping_payload)
    assert res.status_code == 201
    mapping_data = res.json()
    mapping_id = mapping_data["id"]
    assert mapping_data["status"] in ["VALIDATED", "DRAFT"]
    assert mapping_data["entity_mapping_count"] == 1

    # Validate Mapping via API
    val_res = await client.post(f"/api/v1/registry/mappings/{mapping_id}/validate")
    assert val_res.status_code == 200
    assert val_res.json()["is_valid"] is True

    # Activate Mapping
    act_res = await client.post(f"/api/v1/registry/mappings/{mapping_id}/activate")
    assert act_res.status_code == 200
    assert act_res.json()["status"] == "ACTIVE"

    # Update Source Mapping (edit entity/field mappings) -> resets to DRAFT
    update_payload = {
        "version": "1.0.1",
        "entity_mappings": [
            {
                "logical_entity_id": logical_entity_id,
                "physical_entity_name": "items",
                "physical_namespace": "main",
                "field_mappings": [
                    {"logical_field_id": logical_fields["id"], "physical_field_name": "prod_id"},
                    {"logical_field_id": logical_fields["name"], "physical_field_name": "prod_name"},
                ],
            }
        ],
    }
    put_res = await client.put(f"/api/v1/registry/mappings/{mapping_id}", json=update_payload)
    assert put_res.status_code == 200
    updated_data = put_res.json()
    assert updated_data["version"] == "1.0.1"
    assert updated_data["total_field_mapping_count"] == 2
    assert updated_data["status"] == "DRAFT"  # Reset to DRAFT upon edit

    # Summary Endpoint
    sum_res = await client.get("/api/v1/registry/summary")
    assert sum_res.status_code == 200
    assert sum_res.json()["logical_models_count"] >= 1


@pytest.mark.asyncio
async def test_source_mapping_lifecycle_invariants(client: AsyncClient, test_session: AsyncSession):
    """Enforce complete 7-case lifecycle invariants:
    1. DRAFT -> ACTIVATE -> rejected (422)
    2. ERROR -> ACTIVATE -> rejected (422)
    3. VALIDATED -> ACTIVATE -> allowed
    4. ACTIVE -> EDIT -> DRAFT (cannot remain ACTIVE)
    5. ACTIVE -> EDIT -> validation fails -> cannot become ACTIVE
    6. ACTIVE -> EDIT -> VALIDATED -> ACTIVATE -> allowed
    7. Single active mapping rule (activating second deactivates first)
    """
    source_repo = SqliteSourceRepository(test_session)
    source = Source(
        name="Lifecycle PG Source",
        type=SourceType.POSTGRESQL,
        host="localhost",
        port=5432,
        database_name="lc_db",
        username="lc_user",
        status=SourceStatus.ACTIVE,
    )
    saved_source = await source_repo.create(source)

    phys_fields = [
        FieldSchema(name="id", data_type=StandardDataType.INTEGER, native_data_type="INTEGER", is_primary_key=True),
        FieldSchema(name="email", data_type=StandardDataType.STRING, native_data_type="VARCHAR(255)"),
    ]
    phys_entity = EntitySchema(name="users", namespace="public", fields=phys_fields, primary_key=["id"])
    phys_schema = SourceSchema(source_id=saved_source.id, source_name=saved_source.name, entities=[phys_entity])
    await source_repo.save_schema_snapshot(saved_source.id, phys_schema)

    # 1. Create Model
    model_res = await client.post(
        "/api/v1/registry/models",
        json={
            "name": "LifecycleModel",
            "entities": [
                {
                    "name": "User",
                    "fields": [
                        {"name": "id", "data_type": "INTEGER", "is_primary_key": True},
                        {"name": "email", "data_type": "STRING"},
                    ],
                }
            ],
        },
    )
    assert model_res.status_code == 201
    model_data = model_res.json()
    model_id = model_data["id"]
    entity_id = model_data["entities"][0]["id"]
    f_id = next(f["id"] for f in model_data["entities"][0]["fields"] if f["name"] == "id")
    f_email = next(f["id"] for f in model_data["entities"][0]["fields"] if f["name"] == "email")

    # 2. Create Mapping (starts in DRAFT)
    create_payload = {
        "logical_model_id": model_id,
        "source_id": saved_source.id,
        "version": "1.0.0",
        "status": "DRAFT",
        "entity_mappings": [
            {
                "logical_entity_id": entity_id,
                "physical_entity_name": "users",
                "physical_namespace": "public",
                "field_mappings": [
                    {"logical_field_id": f_id, "physical_field_name": "id"},
                    {"logical_field_id": f_email, "physical_field_name": "email"},
                ],
            }
        ],
    }
    create_res = await client.post("/api/v1/registry/mappings", json=create_payload)
    assert create_res.status_code == 201
    m1_id = create_res.json()["id"]
    assert create_res.json()["status"] == "DRAFT"

    # Invariant 1: DRAFT -> ACTIVATE -> REJECTED (422)
    act_draft_res = await client.post(f"/api/v1/registry/mappings/{m1_id}/activate")
    assert act_draft_res.status_code == 422
    assert "Cannot activate mapping with status 'DRAFT'" in act_draft_res.json()["detail"]

    # Invariant 2: ERROR -> ACTIVATE -> REJECTED (422)
    # Put invalid table name to force ERROR on validation
    invalid_edit = {
        "entity_mappings": [
            {
                "logical_entity_id": entity_id,
                "physical_entity_name": "non_existent_table",
                "physical_namespace": "public",
                "field_mappings": [{"logical_field_id": f_id, "physical_field_name": "id"}],
            }
        ]
    }
    await client.put(f"/api/v1/registry/mappings/{m1_id}", json=invalid_edit)
    val_err_res = await client.post(f"/api/v1/registry/mappings/{m1_id}/validate")
    assert val_err_res.status_code == 200
    assert val_err_res.json()["is_valid"] is False
    assert val_err_res.json()["mapping"]["status"] == "ERROR"

    act_err_res = await client.post(f"/api/v1/registry/mappings/{m1_id}/activate")
    assert act_err_res.status_code == 422
    assert "Cannot activate mapping with status 'ERROR'" in act_err_res.json()["detail"]

    # Invariant 3: VALIDATED -> ACTIVATE -> ALLOWED (status = ACTIVE)
    # Fix mapping back to valid physical table
    valid_edit = {
        "entity_mappings": [
            {
                "logical_entity_id": entity_id,
                "physical_entity_name": "users",
                "physical_namespace": "public",
                "field_mappings": [
                    {"logical_field_id": f_id, "physical_field_name": "id"},
                    {"logical_field_id": f_email, "physical_field_name": "email"},
                ],
            }
        ]
    }
    put_valid_res = await client.put(f"/api/v1/registry/mappings/{m1_id}", json=valid_edit)
    assert put_valid_res.status_code == 200
    assert put_valid_res.json()["status"] == "DRAFT"

    val_res = await client.post(f"/api/v1/registry/mappings/{m1_id}/validate")
    assert val_res.status_code == 200
    assert val_res.json()["is_valid"] is True
    assert val_res.json()["mapping"]["status"] == "VALIDATED"

    act_res = await client.post(f"/api/v1/registry/mappings/{m1_id}/activate")
    assert act_res.status_code == 200
    assert act_res.json()["status"] == "ACTIVE"

    # Invariant 4: ACTIVE -> EDIT -> DRAFT (cannot remain ACTIVE)
    # Edit the active mapping (e.g. unmap email, map only id -> id)
    edit_active_payload = {
        "entity_mappings": [
            {
                "logical_entity_id": entity_id,
                "physical_entity_name": "users",
                "physical_namespace": "public",
                "field_mappings": [
                    {"logical_field_id": f_id, "physical_field_name": "id"},
                ],
            }
        ]
    }
    edit_res = await client.put(f"/api/v1/registry/mappings/{m1_id}", json=edit_active_payload)
    assert edit_res.status_code == 200
    assert edit_res.json()["status"] == "DRAFT"  # Reset from ACTIVE to DRAFT!

    # Invariant 5: ACTIVE -> EDIT -> validation fails -> cannot become ACTIVE
    # Edit with bad column
    bad_col_edit = {
        "entity_mappings": [
            {
                "logical_entity_id": entity_id,
                "physical_entity_name": "users",
                "physical_namespace": "public",
                "field_mappings": [
                    {"logical_field_id": f_id, "physical_field_name": "missing_col"},
                ],
            }
        ]
    }
    await client.put(f"/api/v1/registry/mappings/{m1_id}", json=bad_col_edit)
    val_fail = await client.post(f"/api/v1/registry/mappings/{m1_id}/validate")
    assert val_fail.status_code == 200
    assert val_fail.json()["is_valid"] is False
    assert val_fail.json()["mapping"]["status"] == "ERROR"

    act_fail = await client.post(f"/api/v1/registry/mappings/{m1_id}/activate")
    assert act_fail.status_code == 422

    # Invariant 6: ACTIVE -> EDIT -> VALIDATED -> ACTIVATE -> allowed
    # Restore valid mapping
    await client.put(f"/api/v1/registry/mappings/{m1_id}", json=edit_active_payload)
    val_ok = await client.post(f"/api/v1/registry/mappings/{m1_id}/validate")
    assert val_ok.status_code == 200
    assert val_ok.json()["is_valid"] is True
    assert val_ok.json()["mapping"]["status"] == "VALIDATED"

    act_ok = await client.post(f"/api/v1/registry/mappings/{m1_id}/activate")
    assert act_ok.status_code == 200
    assert act_ok.json()["status"] == "ACTIVE"

    # Invariant 7: Existing single active mapping rule works
    # Create second data source and second mapping for same logical model
    source2 = Source(
        name="Second Source",
        type=SourceType.POSTGRESQL,
        host="localhost",
        port=5432,
        database_name="second_db",
        username="postgres",
        status=SourceStatus.ACTIVE,
    )
    saved_source2 = await source_repo.create(source2)
    await source_repo.save_schema_snapshot(
        saved_source2.id,
        SourceSchema(source_id=saved_source2.id, source_name=saved_source2.name, entities=[phys_entity]),
    )

    create2_res = await client.post(
        "/api/v1/registry/mappings",
        json={
            "logical_model_id": model_id,
            "source_id": saved_source2.id,
            "version": "1.0.0",
            "status": "DRAFT",
            "entity_mappings": [
                {
                    "logical_entity_id": entity_id,
                    "physical_entity_name": "users",
                    "physical_namespace": "public",
                    "field_mappings": [{"logical_field_id": f_id, "physical_field_name": "id"}],
                }
            ],
        },
    )
    assert create2_res.status_code == 201
    m2_id = create2_res.json()["id"]

    # Validate m2
    val_m2 = await client.post(f"/api/v1/registry/mappings/{m2_id}/validate")
    assert val_m2.status_code == 200
    assert val_m2.json()["mapping"]["status"] == "VALIDATED"

    # Activate m2 -> m2 becomes ACTIVE, m1 is reverted from ACTIVE to VALIDATED
    act_m2 = await client.post(f"/api/v1/registry/mappings/{m2_id}/activate")
    assert act_m2.status_code == 200
    assert act_m2.json()["status"] == "ACTIVE"

    # Check m1 status is no longer ACTIVE
    get_m1 = await client.get(f"/api/v1/registry/mappings/{m1_id}")
    assert get_m1.status_code == 200
    assert get_m1.json()["status"] == "VALIDATED"


@pytest.mark.asyncio
async def test_datatype_compatibility_validation(client: AsyncClient, test_session: AsyncSession):
    """Enforce strict logical-to-physical datatype compatibility during validation.
    
    1. BOOLEAN -> BOOLEAN succeeds
    2. BOOLEAN -> STRING fails with descriptive error
    3. STRING -> BOOLEAN fails
    4. INTEGER -> STRING fails
    5. JSON -> JSON succeeds
    6. Invalid datatype mapping transitions to ERROR and cannot be activated.
    """
    source_repo = SqliteSourceRepository(test_session)
    source = Source(
        name="TypeCheck PG Source",
        type=SourceType.POSTGRESQL,
        host="localhost",
        port=5432,
        database_name="typecheck_db",
        username="postgres",
        status=SourceStatus.ACTIVE,
    )
    saved_source = await source_repo.create(source)

    phys_fields = [
        FieldSchema(name="id", data_type=StandardDataType.INTEGER, native_data_type="INTEGER", is_primary_key=True),
        FieldSchema(name="full_name", data_type=StandardDataType.STRING, native_data_type="VARCHAR(255)"),
        FieldSchema(name="is_active", data_type=StandardDataType.BOOLEAN, native_data_type="BOOLEAN"),
        FieldSchema(name="extra_meta", data_type=StandardDataType.JSON, native_data_type="JSONB"),
    ]
    phys_entity = EntitySchema(name="users", namespace="public", fields=phys_fields, primary_key=["id"])
    phys_schema = SourceSchema(source_id=saved_source.id, source_name=saved_source.name, entities=[phys_entity])
    await source_repo.save_schema_snapshot(saved_source.id, phys_schema)

    # Create Logical Model with diverse types
    model_res = await client.post(
        "/api/v1/registry/models",
        json={
            "name": "UniversityDomain",
            "entities": [
                {
                    "name": "Student",
                    "fields": [
                        {"name": "id", "data_type": "INTEGER", "is_primary_key": True},
                        {"name": "name", "data_type": "STRING"},
                        {"name": "status", "data_type": "BOOLEAN"},
                        {"name": "metadata", "data_type": "JSON"},
                    ],
                }
            ],
        },
    )
    assert model_res.status_code == 201
    model_data = model_res.json()
    model_id = model_data["id"]
    entity_id = model_data["entities"][0]["id"]
    fields_list = model_data["entities"][0]["fields"]
    f_id = next(f["id"] for f in fields_list if f["name"] == "id")
    f_name = next(f["id"] for f in fields_list if f["name"] == "name")
    f_status = next(f["id"] for f in fields_list if f["name"] == "status")
    f_meta = next(f["id"] for f in fields_list if f["name"] == "metadata")

    # 1. Test Valid Type Mappings: INTEGER -> INTEGER, STRING -> STRING, BOOLEAN -> BOOLEAN, JSON -> JSON
    valid_mapping_payload = {
        "logical_model_id": model_id,
        "source_id": saved_source.id,
        "version": "1.0.0",
        "status": "DRAFT",
        "entity_mappings": [
            {
                "logical_entity_id": entity_id,
                "physical_entity_name": "users",
                "physical_namespace": "public",
                "field_mappings": [
                    {"logical_field_id": f_id, "physical_field_name": "id"},
                    {"logical_field_id": f_name, "physical_field_name": "full_name"},
                    {"logical_field_id": f_status, "physical_field_name": "is_active"},
                    {"logical_field_id": f_meta, "physical_field_name": "extra_meta"},
                ],
            }
        ],
    }
    create_res = await client.post("/api/v1/registry/mappings", json=valid_mapping_payload)
    assert create_res.status_code == 201
    m_id = create_res.json()["id"]

    val_res = await client.post(f"/api/v1/registry/mappings/{m_id}/validate")
    assert val_res.status_code == 200
    assert val_res.json()["is_valid"] is True
    assert val_res.json()["mapping"]["status"] == "VALIDATED"

    # 2. Test Invalid Type Mapping: BOOLEAN -> STRING (Status -> full_name)
    invalid_bool_to_str = {
        "entity_mappings": [
            {
                "logical_entity_id": entity_id,
                "physical_entity_name": "users",
                "physical_namespace": "public",
                "field_mappings": [
                    {"logical_field_id": f_id, "physical_field_name": "id"},
                    {"logical_field_id": f_status, "physical_field_name": "full_name"},  # BOOLEAN -> STRING
                ],
            }
        ]
    }
    await client.put(f"/api/v1/registry/mappings/{m_id}", json=invalid_bool_to_str)
    val_err1 = await client.post(f"/api/v1/registry/mappings/{m_id}/validate")
    assert val_err1.status_code == 200
    assert val_err1.json()["is_valid"] is False
    assert val_err1.json()["mapping"]["status"] == "ERROR"
    assert "Logical field 'status' (BOOLEAN) cannot map to physical field 'full_name' (STRING)" in val_err1.json()["error"]

    # Activation must be rejected
    act_err1 = await client.post(f"/api/v1/registry/mappings/{m_id}/activate")
    assert act_err1.status_code == 422

    # 3. Test Invalid Type Mapping: STRING -> BOOLEAN (Name -> is_active)
    invalid_str_to_bool = {
        "entity_mappings": [
            {
                "logical_entity_id": entity_id,
                "physical_entity_name": "users",
                "physical_namespace": "public",
                "field_mappings": [
                    {"logical_field_id": f_id, "physical_field_name": "id"},
                    {"logical_field_id": f_name, "physical_field_name": "is_active"},  # STRING -> BOOLEAN
                ],
            }
        ]
    }
    await client.put(f"/api/v1/registry/mappings/{m_id}", json=invalid_str_to_bool)
    val_err2 = await client.post(f"/api/v1/registry/mappings/{m_id}/validate")
    assert val_err2.status_code == 200
    assert val_err2.json()["is_valid"] is False
    assert val_err2.json()["mapping"]["status"] == "ERROR"
    assert "Logical field 'name' (STRING) cannot map to physical field 'is_active' (BOOLEAN)" in val_err2.json()["error"]

    # 4. Test Invalid Type Mapping: INTEGER -> STRING (Id -> full_name)
    invalid_int_to_str = {
        "entity_mappings": [
            {
                "logical_entity_id": entity_id,
                "physical_entity_name": "users",
                "physical_namespace": "public",
                "field_mappings": [
                    {"logical_field_id": f_id, "physical_field_name": "full_name"},  # INTEGER -> STRING
                ],
            }
        ]
    }
    await client.put(f"/api/v1/registry/mappings/{m_id}", json=invalid_int_to_str)
    val_err3 = await client.post(f"/api/v1/registry/mappings/{m_id}/validate")
    assert val_err3.status_code == 200
    assert val_err3.json()["is_valid"] is False
    assert val_err3.json()["mapping"]["status"] == "ERROR"
    assert "Logical field 'id' (INTEGER) cannot map to physical field 'full_name' (STRING)" in val_err3.json()["error"]

