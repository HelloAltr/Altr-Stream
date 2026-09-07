"""Unit tests for AltrQL Schema Resolver (Phase D)."""

import pytest

from altr_stream.domain.schema import EntitySchema, FieldSchema, SourceSchema, StandardDataType
from altr_stream.query_engine.binding.resolver import resolve_entity, resolve_field_path
from altr_stream.query_engine.domain.ast import FieldPath
from altr_stream.query_engine.domain.errors import UnknownEntityError, UnknownFieldError


@pytest.fixture
def sample_source_schema() -> SourceSchema:
    users_entity = EntitySchema(
        name="users",
        fields=[
            FieldSchema(name="id", data_type=StandardDataType.INTEGER, native_data_type="int4", nullable=False, is_primary_key=True),
            FieldSchema(name="username", data_type=StandardDataType.STRING, native_data_type="varchar", nullable=False),
            FieldSchema(name="age", data_type=StandardDataType.INTEGER, native_data_type="int4", nullable=True),
            FieldSchema(name="is_active", data_type=StandardDataType.BOOLEAN, native_data_type="bool", nullable=False),
            FieldSchema(name="created_at", data_type=StandardDataType.TIMESTAMP, native_data_type="timestamp", nullable=False),
            FieldSchema(name="meta.raw_json", data_type=StandardDataType.JSON, native_data_type="jsonb", nullable=True),
        ],
    )
    orders_entity = EntitySchema(
        name="orders",
        fields=[
            FieldSchema(name="order_id", data_type=StandardDataType.BIGINT, native_data_type="int8", nullable=False, is_primary_key=True),
            FieldSchema(name="amount", data_type=StandardDataType.FLOAT, native_data_type="float8", nullable=False),
        ],
    )
    return SourceSchema(
        source_id="src_123",
        source_name="production_pg",
        entities=[users_entity, orders_entity],
    )


def test_resolve_entity_success(sample_source_schema: SourceSchema):
    entity = resolve_entity("users", sample_source_schema)
    assert isinstance(entity, EntitySchema)
    assert entity.name == "users"
    assert len(entity.fields) == 6


def test_resolve_entity_unknown_error(sample_source_schema: SourceSchema):
    with pytest.raises(UnknownEntityError) as exc_info:
        resolve_entity("non_existent_table", sample_source_schema)
    assert "non_existent_table" in str(exc_info.value)
    assert "production_pg" in str(exc_info.value)


def test_resolve_flat_field_path_success(sample_source_schema: SourceSchema):
    entity = resolve_entity("users", sample_source_schema)
    field_path = FieldPath(segments=["username"])
    
    field_schema = resolve_field_path(field_path, entity)
    assert isinstance(field_schema, FieldSchema)
    assert field_schema.name == "username"
    assert field_schema.data_type == StandardDataType.STRING
    assert field_schema.nullable is False


def test_resolve_unknown_field_error(sample_source_schema: SourceSchema):
    entity = resolve_entity("users", sample_source_schema)
    field_path = FieldPath(segments=["non_existent_column"])

    with pytest.raises(UnknownFieldError) as exc_info:
        resolve_field_path(field_path, entity)
    assert "non_existent_column" in str(exc_info.value)
    assert "users" in str(exc_info.value)


def test_reject_nested_multi_segment_field_path(sample_source_schema: SourceSchema):
    entity = resolve_entity("users", sample_source_schema)
    field_path = FieldPath(segments=["profile", "country"])

    with pytest.raises(UnknownFieldError) as exc_info:
        resolve_field_path(field_path, entity)
    assert "profile.country" in str(exc_info.value)
    assert "users" in str(exc_info.value)


def test_resolve_literal_dot_named_flat_column(sample_source_schema: SourceSchema):
    entity = resolve_entity("users", sample_source_schema)
    field_path = FieldPath(segments=["meta.raw_json"])

    field_schema = resolve_field_path(field_path, entity)
    assert field_schema.name == "meta.raw_json"
    assert field_schema.data_type == StandardDataType.JSON
