"""Integration tests for SqliteRegistryRepository."""

import pytest
from sqlalchemy.ext.asyncio import AsyncSession

from altr_stream.domain.logical import LogicalEntity, LogicalField, LogicalModel
from altr_stream.domain.mapping import (
    EntityMapping,
    FieldMapping,
    MappingProvenance,
    MappingStatus,
    SourceMapping,
)
from altr_stream.domain.schema import StandardDataType
from altr_stream.domain.source import Source, SourceStatus, SourceType
from altr_stream.infrastructure.database.registry_repository import SqliteRegistryRepository
from altr_stream.infrastructure.database.repository import SqliteSourceRepository


@pytest.mark.asyncio
async def test_logical_model_crud_and_cascade(test_session: AsyncSession):
    repo = SqliteRegistryRepository(test_session)

    # 1. Create Model with Entity and Fields
    f1 = LogicalField(logical_entity_id="", name="id", data_type=StandardDataType.INTEGER, is_primary_key=True)
    f2 = LogicalField(logical_entity_id="", name="email", data_type=StandardDataType.STRING)
    e1 = LogicalEntity(logical_model_id="", name="User", description="User entity", fields=[f1, f2])

    model = LogicalModel(
        name="UserModel",
        version="1.0.0",
        description="Core user model",
        entities=[e1],
    )

    created = await repo.create_model(model)
    assert created.id is not None
    assert created.name == "UserModel"
    assert created.entity_count == 1
    assert created.entities[0].name == "User"
    assert created.entities[0].field_count == 2

    # 2. Get by ID and Name
    fetched = await repo.get_model_by_id(created.id)
    assert fetched is not None
    assert fetched.name == "UserModel"

    fetched_name = await repo.get_model_by_name("UserModel")
    assert fetched_name is not None
    assert fetched_name.id == created.id

    # 3. Add Another Entity
    f3 = LogicalField(logical_entity_id="", name="role_name", data_type=StandardDataType.STRING)
    e2 = LogicalEntity(logical_model_id=created.id, name="Role", fields=[f3])
    added_e = await repo.add_entity(e2)
    assert added_e.name == "Role"

    refreshed = await repo.get_model_by_id(created.id)
    assert refreshed.entity_count == 2

    # 4. List Models
    models = await repo.list_models()
    assert len(models) >= 1

    # 5. Delete Entity
    del_entity_ok = await repo.delete_entity(added_e.id)
    assert del_entity_ok is True
    refreshed2 = await repo.get_model_by_id(created.id)
    assert refreshed2.entity_count == 1

    # 6. Delete Model
    del_model_ok = await repo.delete_model(created.id)
    assert del_model_ok is True
    assert await repo.get_model_by_id(created.id) is None


@pytest.mark.asyncio
async def test_source_mapping_crud_and_cascade(test_session: AsyncSession):
    reg_repo = SqliteRegistryRepository(test_session)
    source_repo = SqliteSourceRepository(test_session)

    # 1. Create Source & Model
    source = Source(
        name="Test PG Source",
        type=SourceType.POSTGRESQL,
        host="localhost",
        port=5432,
        database_name="test_db",
        username="postgres",
        status=SourceStatus.ACTIVE,
    )
    saved_source = await source_repo.create(source)

    f1 = LogicalField(logical_entity_id="", name="id", data_type=StandardDataType.INTEGER, is_primary_key=True)
    f2 = LogicalField(logical_entity_id="", name="username", data_type=StandardDataType.STRING)
    e1 = LogicalEntity(logical_model_id="", name="Account", fields=[f1, f2])
    model = LogicalModel(name="AccountModel", entities=[e1])
    saved_model = await reg_repo.create_model(model)

    logical_entity = saved_model.entities[0]
    logical_f1 = logical_entity.fields[0]
    logical_f2 = logical_entity.fields[1]

    # 2. Create Source Mapping with Entity and Field Mappings
    fm1 = FieldMapping(
        entity_mapping_id="",
        logical_field_id=logical_f1.id,
        logical_field_name=logical_f1.name,
        physical_field_name="acc_id",
    )
    fm2 = FieldMapping(
        entity_mapping_id="",
        logical_field_id=logical_f2.id,
        logical_field_name=logical_f2.name,
        physical_field_name="acc_username",
    )
    em1 = EntityMapping(
        source_mapping_id="",
        logical_entity_id=logical_entity.id,
        logical_entity_name=logical_entity.name,
        physical_entity_name="accounts",
        physical_namespace="public",
        field_mappings=[fm1, fm2],
    )
    sm = SourceMapping(
        logical_model_id=saved_model.id,
        source_id=saved_source.id,
        version="1.0.0",
        status=MappingStatus.DRAFT,
        provenance=MappingProvenance.USER,
        entity_mappings=[em1],
    )

    created_sm = await reg_repo.create_source_mapping(sm)
    assert created_sm.id is not None
    assert created_sm.entity_mapping_count == 1
    assert created_sm.total_field_mapping_count == 2

    # 3. Fetch Mapping
    fetched_sm = await reg_repo.get_source_mapping_by_id(created_sm.id)
    assert fetched_sm is not None
    assert fetched_sm.entity_mappings[0].physical_entity_name == "accounts"
    assert fetched_sm.entity_mappings[0].field_mappings[0].physical_field_name == "acc_id"

    # 4. Summary Metrics
    summary = await reg_repo.get_summary()
    assert summary["logical_models_count"] >= 1
    assert summary["source_mappings_count"] >= 1
    assert summary["entity_mappings_count"] >= 1
    assert summary["field_mappings_count"] >= 2

    # 5. Delete Source Mapping
    del_ok = await reg_repo.delete_source_mapping(created_sm.id)
    assert del_ok is True
    assert await reg_repo.get_source_mapping_by_id(created_sm.id) is None
