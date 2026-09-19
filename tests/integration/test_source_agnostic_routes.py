"""Integration tests for Altr Stream v0.9 federated multi-source planning, binding, and execution endpoints."""

from unittest.mock import AsyncMock, patch
import pytest
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from altr_stream.domain.logical import LogicalEntity, LogicalField, LogicalModel
from altr_stream.domain.mapping import (
    EntityMapping,
    FieldMapping,
    MappingProvenance,
    MappingStatus,
    SourceMapping,
)
from altr_stream.domain.query import QueryResult
from altr_stream.domain.schema import (
    EntitySchema,
    FieldSchema,
    SourceSchema,
    StandardDataType,
)
from altr_stream.domain.source import Source, SourceStatus, SourceType
from altr_stream.infrastructure.database.registry_repository import SqliteRegistryRepository
from altr_stream.infrastructure.database.repository import SqliteSourceRepository


@pytest.fixture
async def setup_dual_source_environment(test_session: AsyncSession):
    """Setup two sources mapped to one logical model for federated testing."""
    source_repo = SqliteSourceRepository(test_session)
    reg_repo = SqliteRegistryRepository(test_session)

    # Source 1: PostgreSQL-style (source_a)
    source_a = Source(
        id="source_a",
        name="Postgres DB Alpha",
        type=SourceType.POSTGRESQL,
        host="localhost",
        port=5432,
        database_name="pg_alpha",
        status=SourceStatus.ACTIVE,
    )
    saved_source_a = await source_repo.create(source_a)

    phys_fields_a = [
        FieldSchema(name="user_id", data_type=StandardDataType.INTEGER, native_data_type="INTEGER", is_primary_key=True),
        FieldSchema(name="full_name", data_type=StandardDataType.STRING, native_data_type="VARCHAR"),
        FieldSchema(name="contact_email", data_type=StandardDataType.STRING, native_data_type="VARCHAR"),
        FieldSchema(name="user_age", data_type=StandardDataType.INTEGER, native_data_type="INTEGER"),
    ]
    phys_entity_a = EntitySchema(name="app_users", namespace="public", fields=phys_fields_a, primary_key=["user_id"])
    phys_schema_a = SourceSchema(source_id=saved_source_a.id, source_name=saved_source_a.name, entities=[phys_entity_a])
    await source_repo.save_schema_snapshot(saved_source_a.id, phys_schema_a)

    # Source 2: SQLite-style (source_b)
    source_b = Source(
        id="source_b",
        name="SQLite DB Beta",
        type=SourceType.SQLITE,
        file_path="/tmp/test_beta.db",
        status=SourceStatus.ACTIVE,
    )
    saved_source_b = await source_repo.create(source_b)

    phys_fields_b = [
        FieldSchema(name="id", data_type=StandardDataType.INTEGER, native_data_type="INTEGER", is_primary_key=True),
        FieldSchema(name="name", data_type=StandardDataType.STRING, native_data_type="TEXT"),
        FieldSchema(name="email", data_type=StandardDataType.STRING, native_data_type="TEXT"),
    ]
    phys_entity_b = EntitySchema(name="users", namespace="main", fields=phys_fields_b, primary_key=["id"])
    phys_schema_b = SourceSchema(source_id=saved_source_b.id, source_name=saved_source_b.name, entities=[phys_entity_b])
    await source_repo.save_schema_snapshot(saved_source_b.id, phys_schema_b)

    # Logical Model: Customer
    lf_id = LogicalField(logical_entity_id="", name="id", data_type=StandardDataType.INTEGER, is_primary_key=True)
    lf_name = LogicalField(logical_entity_id="", name="name", data_type=StandardDataType.STRING)
    lf_email = LogicalField(logical_entity_id="", name="email", data_type=StandardDataType.STRING)
    lf_age = LogicalField(logical_entity_id="", name="age", data_type=StandardDataType.INTEGER)
    le_customer = LogicalEntity(logical_model_id="", name="Customer", fields=[lf_id, lf_name, lf_email, lf_age])

    model = LogicalModel(name="RetailModel", entities=[le_customer])
    saved_model = await reg_repo.create_model(model)
    saved_entity = saved_model.entities[0]
    saved_fields = {f.name: f.id for f in saved_entity.fields}

    # Mapping for Source A (full coverage: id, name, email, age)
    sm_a = SourceMapping(
        id="map_a",
        logical_model_id=saved_model.id,
        source_id=saved_source_a.id,
        version="1.0.0",
        status=MappingStatus.ACTIVE,
        provenance=MappingProvenance.USER,
        entity_mappings=[
            EntityMapping(
                source_mapping_id="",
                logical_entity_id=saved_entity.id,
                logical_entity_name=saved_entity.name,
                physical_entity_name="app_users",
                physical_namespace="public",
                field_mappings=[
                    FieldMapping(entity_mapping_id="", logical_field_id=saved_fields["id"], logical_field_name="id", physical_field_name="user_id"),
                    FieldMapping(entity_mapping_id="", logical_field_id=saved_fields["name"], logical_field_name="name", physical_field_name="full_name"),
                    FieldMapping(entity_mapping_id="", logical_field_id=saved_fields["email"], logical_field_name="email", physical_field_name="contact_email"),
                    FieldMapping(entity_mapping_id="", logical_field_id=saved_fields["age"], logical_field_name="age", physical_field_name="user_age"),
                ],
            )
        ],
    )
    saved_sm_a = await reg_repo.create_source_mapping(sm_a)

    # Mapping for Source B (partial coverage: id, name, email -- missing age)
    sm_b = SourceMapping(
        id="map_b",
        logical_model_id=saved_model.id,
        source_id=saved_source_b.id,
        version="1.0.0",
        status=MappingStatus.ACTIVE,
        provenance=MappingProvenance.USER,
        entity_mappings=[
            EntityMapping(
                source_mapping_id="",
                logical_entity_id=saved_entity.id,
                logical_entity_name=saved_entity.name,
                physical_entity_name="users",
                physical_namespace="main",
                field_mappings=[
                    FieldMapping(entity_mapping_id="", logical_field_id=saved_fields["id"], logical_field_name="id", physical_field_name="id"),
                    FieldMapping(entity_mapping_id="", logical_field_id=saved_fields["name"], logical_field_name="name", physical_field_name="name"),
                    FieldMapping(entity_mapping_id="", logical_field_id=saved_fields["email"], logical_field_name="email", physical_field_name="email"),
                ],
            )
        ],
    )
    saved_sm_b = await reg_repo.create_source_mapping(sm_b)

    return {
        "model": saved_model,
        "source_a": saved_source_a,
        "source_b": saved_source_b,
        "map_a": saved_sm_a,
        "map_b": saved_sm_b,
    }


@pytest.mark.asyncio
async def test_plan_endpoint_single_eligible_selection(client: AsyncClient, setup_dual_source_environment):
    env = setup_dual_source_environment
    model_id = env["model"].id

    # Query requires 'age' -> Only Source A is eligible
    payload = {
        "query": 'GET Customer (name, email) WHERE { age >= 21 };',
        "logical_model_id": model_id,
    }

    res = await client.post("/api/v1/altrql/plan", json=payload)
    assert res.status_code == 200
    assert res.headers.get("X-Altr-Execution-Mode") == "federated"
    assert res.headers.get("X-Altr-Federated-Sources") == "source_a"

    data = res.json()
    assert data["success"] is True
    assert data["execution_mode"] == "federated"
    assert data["total_sources_planned"] == 1
    assert data["physical_plans"][0]["source_id"] == "source_a"
    assert len(data["candidates_evaluated"]) == 2

    eval_map = {e["source_id"]: e for e in data["candidates_evaluated"]}
    assert eval_map["source_a"]["is_eligible"] is True
    assert eval_map["source_b"]["is_eligible"] is False
    assert "does not map required logical field(s)" in eval_map["source_b"]["rejection_reason"]


@pytest.mark.asyncio
async def test_plan_endpoint_multi_source_federation(client: AsyncClient, setup_dual_source_environment):
    env = setup_dual_source_environment
    model_id = env["model"].id

    # Query requires only 'name' and 'email' -> Both Source A and Source B are eligible!
    payload = {
        "query": 'GET Customer (name, email);',
        "logical_model_id": model_id,
    }

    res = await client.post("/api/v1/altrql/plan", json=payload)
    assert res.status_code == 200
    assert res.headers.get("X-Altr-Execution-Mode") == "federated"
    sources_in_header = res.headers.get("X-Altr-Federated-Sources", "").split(",")
    assert "source_a" in sources_in_header
    assert "source_b" in sources_in_header

    data = res.json()
    assert data["success"] is True
    assert data["execution_mode"] == "federated"
    assert data["total_sources_planned"] == 2
    assert len(data["physical_plans"]) == 2
    assert all(e["is_eligible"] for e in data["candidates_evaluated"])


@pytest.mark.asyncio
async def test_plan_endpoint_no_active_mapping_for_unknown_entity(client: AsyncClient):
    payload = {
        "query": "GET UnknownEntity (col);",
    }

    res = await client.post("/api/v1/altrql/plan", json=payload)
    assert res.status_code == 200
    data = res.json()
    assert data["success"] is False
    assert data["error"]["type"] == "NoActiveSourceMappingError"


@pytest.mark.asyncio
async def test_plan_endpoint_incomplete_field_coverage(client: AsyncClient, setup_dual_source_environment):
    env = setup_dual_source_environment
    model_id = env["model"].id

    # Query references a non-existent field 'non_existent_field'
    payload = {
        "query": 'GET Customer WHERE { non_existent_field = "xyz" };',
        "logical_model_id": model_id,
    }

    res = await client.post("/api/v1/altrql/plan", json=payload)
    assert res.status_code == 200
    data = res.json()
    assert data["success"] is False
    assert data["error"]["type"] == "IncompleteFieldMappingError"


@pytest.mark.asyncio
async def test_bind_endpoint_source_agnostic(client: AsyncClient, setup_dual_source_environment):
    env = setup_dual_source_environment
    model_id = env["model"].id

    payload = {
        "query": 'GET Customer (email) WHERE { age > 18 };',
        "logical_model_id": model_id,
    }

    res = await client.post("/api/v1/altrql/bind", json=payload)
    assert res.status_code == 200
    assert res.headers.get("X-Altr-Execution-Mode") == "federated"
    assert res.headers.get("X-Altr-Federated-Sources") == "source_a"

    data = res.json()
    assert data["success"] is True
    assert data["execution_mode"] == "federated"
    assert data["bound_ir"]["entity"]["name"] == "app_users"


@pytest.mark.asyncio
async def test_execute_endpoint_federated_multi_source(client: AsyncClient, setup_dual_source_environment):
    env = setup_dual_source_environment
    model_id = env["model"].id

    payload = {
        "query": 'GET Customer (name, email) SORT { name ASC };',
        "logical_model_id": model_id,
    }

    # Mock QueryService.execute_query returning different rows per source
    async def mock_exec_query(source_id: str, query: str, parameters=None):
        if source_id == "source_a":
            return QueryResult(
                columns=["full_name", "contact_email"],
                rows=[
                    {"full_name": "Bob Jones", "contact_email": "bob@example.com"},
                    {"full_name": "David Davis", "contact_email": "david@example.com"},
                ],
                total_rows=2,
                execution_time_ms=3.0,
            )
        else:
            return QueryResult(
                columns=["name", "email"],
                rows=[
                    {"name": "Alice Smith", "email": "alice@example.com"},
                    {"name": "Charlie Brown", "email": "charlie@example.com"},
                ],
                total_rows=2,
                execution_time_ms=2.0,
            )

    with patch(
        "altr_stream.application.query_service.QueryService.execute_query",
        side_effect=mock_exec_query,
    ):
        res = await client.post("/api/v1/altrql/execute", json=payload)
        assert res.status_code == 200
        assert res.headers.get("X-Altr-Execution-Mode") == "federated"

        data = res.json()
        assert data["success"] is True
        assert data["execution_mode"] == "federated"
        assert len(data["sources_executed"]) == 2
        assert set(data["sources_executed"]) == {"source_a", "source_b"}

        # Verify columns and rows are normalized and globally sorted by name ASC
        assert data["columns"] == ["name", "email"]
        assert len(data["rows"]) == 4
        assert [r["name"] for r in data["rows"]] == [
            "Alice Smith",
            "Bob Jones",
            "Charlie Brown",
            "David Davis",
        ]


@pytest.mark.asyncio
async def test_execute_endpoint_rejects_federated_mutations(client: AsyncClient, setup_dual_source_environment):
    env = setup_dual_source_environment
    model_id = env["model"].id

    payload = {
        "query": 'UPDATE Customer (name: "New Name") WHERE { id = 1 };',
        "logical_model_id": model_id,
    }

    res = await client.post("/api/v1/altrql/execute", json=payload)
    assert res.status_code == 200
    data = res.json()
    assert data["success"] is False
    assert "Federated Auto-Select execution does not support UPDATE mutations" in data["error"]["message"]


@pytest.mark.asyncio
async def test_backward_compatibility_explicit_source_id(client: AsyncClient, setup_dual_source_environment):
    env = setup_dual_source_environment
    source_b_id = env["source_b"].id
    map_b_id = env["map_b"].id

    # Explicit source_id and mapping_id should execute on source_b directly
    payload = {
        "query": 'GET Customer (name, email) WHERE { email = "bob@example.com" };',
        "source_id": source_b_id,
        "mapping_id": map_b_id,
    }

    res = await client.post("/api/v1/altrql/bind", json=payload)
    assert res.status_code == 200
    data = res.json()
    assert data["success"] is True
    assert data["bound_ir"]["entity"]["name"] == "users"
