"""Integration tests for end-to-end logical AltrQL query binding and execution."""

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
from altr_stream.domain.schema import (
    EntitySchema,
    FieldSchema,
    SourceSchema,
    StandardDataType,
)
from altr_stream.domain.source import Source, SourceStatus, SourceType
from altr_stream.infrastructure.database.registry_repository import SqliteRegistryRepository
from altr_stream.infrastructure.database.repository import SqliteSourceRepository


@pytest.mark.asyncio
async def test_logical_altrql_bind_and_execute_mock(client: AsyncClient, test_session: AsyncSession):
    source_repo = SqliteSourceRepository(test_session)
    reg_repo = SqliteRegistryRepository(test_session)

    # 1. Setup Source
    source = Source(
        name="Mock School DB",
        type=SourceType.SQLITE,
        file_path="/tmp/mock_school.db",
        status=SourceStatus.ACTIVE,
    )
    saved_source = await source_repo.create(source)

    # 2. Setup Physical Schema Snapshot
    phys_fields = [
        FieldSchema(name="student_id", data_type=StandardDataType.INTEGER, native_data_type="INTEGER", is_primary_key=True),
        FieldSchema(name="full_name", data_type=StandardDataType.STRING, native_data_type="TEXT"),
        FieldSchema(name="email_addr", data_type=StandardDataType.STRING, native_data_type="TEXT"),
        FieldSchema(name="gpa", data_type=StandardDataType.FLOAT, native_data_type="REAL"),
    ]
    phys_entity = EntitySchema(name="tbl_students", namespace="main", fields=phys_fields, primary_key=["student_id"])
    phys_schema = SourceSchema(source_id=saved_source.id, source_name=saved_source.name, entities=[phys_entity])
    await source_repo.save_schema_snapshot(saved_source.id, phys_schema)

    # 3. Setup Logical Model
    lf_id = LogicalField(logical_entity_id="", name="id", data_type=StandardDataType.INTEGER, is_primary_key=True)
    lf_name = LogicalField(logical_entity_id="", name="name", data_type=StandardDataType.STRING)
    lf_email = LogicalField(logical_entity_id="", name="email", data_type=StandardDataType.STRING)
    lf_gpa = LogicalField(logical_entity_id="", name="grade_point_average", data_type=StandardDataType.FLOAT)
    le_student = LogicalEntity(logical_model_id="", name="Student", fields=[lf_id, lf_name, lf_email, lf_gpa])

    model = LogicalModel(name="SchoolModel", entities=[le_student])
    saved_model = await reg_repo.create_model(model)

    saved_entity = saved_model.entities[0]
    saved_fields = {f.name: f.id for f in saved_entity.fields}

    # 4. Setup Source Mapping
    fm_id = FieldMapping(entity_mapping_id="", logical_field_id=saved_fields["id"], logical_field_name="id", physical_field_name="student_id")
    fm_name = FieldMapping(entity_mapping_id="", logical_field_id=saved_fields["name"], logical_field_name="name", physical_field_name="full_name")
    fm_email = FieldMapping(entity_mapping_id="", logical_field_id=saved_fields["email"], logical_field_name="email", physical_field_name="email_addr")
    fm_gpa = FieldMapping(entity_mapping_id="", logical_field_id=saved_fields["grade_point_average"], logical_field_name="grade_point_average", physical_field_name="gpa")

    em = EntityMapping(
        source_mapping_id="",
        logical_entity_id=saved_entity.id,
        logical_entity_name=saved_entity.name,
        physical_entity_name="tbl_students",
        physical_namespace="main",
        field_mappings=[fm_id, fm_name, fm_email, fm_gpa],
    )

    sm = SourceMapping(
        logical_model_id=saved_model.id,
        source_id=saved_source.id,
        version="1.0.0",
        status=MappingStatus.ACTIVE,
        provenance=MappingProvenance.USER,
        entity_mappings=[em],
    )
    saved_sm = await reg_repo.create_source_mapping(sm)

    # 5. Bind Logical Query via API
    bind_payload = {
        "query": 'GET Student(id, name, email) WHERE { grade_point_average >= 3.5 AND name = "Alice" };',
        "source_id": saved_source.id,
        "mapping_id": saved_sm.id,
    }
    bind_res = await client.post("/api/v1/altrql/bind", json=bind_payload)
    assert bind_res.status_code == 200
    bind_data = bind_res.json()
    assert bind_data["success"] is True
    assert bind_data["bound_ir"]["entity"]["name"] == "tbl_students"
    assert bind_data["bound_ir"]["projection"][0]["field"]["path"]["segments"] == ["student_id"]
    assert bind_data["bound_ir"]["projection"][1]["field"]["path"]["segments"] == ["full_name"]
    assert bind_data["bound_ir"]["projection"][2]["field"]["path"]["segments"] == ["email_addr"]

    # Also bind using logical_model_id directly
    bind_model_payload = {
        "query": "GET Student(id, grade_point_average);",
        "source_id": saved_source.id,
        "logical_model_id": saved_model.id,
    }
    bind_model_res = await client.post("/api/v1/altrql/bind", json=bind_model_payload)
    assert bind_model_res.status_code == 200
    assert bind_model_res.json()["success"] is True
    assert bind_model_res.json()["bound_ir"]["projection"][1]["field"]["path"]["segments"] == ["gpa"]
