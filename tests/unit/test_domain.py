"""Unit tests for domain models and contracts."""

import pytest
from altr_stream.domain.connector import ConnectionTestResult, SourceCapabilities
from altr_stream.domain.schema import (
    ConstraintSchema,
    ConstraintType,
    EntitySchema,
    FieldSchema,
    SourceSchema,
    StandardDataType,
)
from altr_stream.domain.source import ConnectionConfig, Source, SourceStatus, SourceType


def test_source_model_creation():
    source = Source(
        name="Test PostgreSQL",
        type=SourceType.POSTGRESQL,
        host="localhost",
        port=5432,
        database_name="testdb",
        username="testuser",
        password="secret_password",
    )

    assert source.name == "Test PostgreSQL"
    assert source.type == SourceType.POSTGRESQL
    assert source.status == SourceStatus.UNKNOWN
    assert source.port == 5432

    # Verify password masking
    safe_dict = source.to_safe_dict()
    assert "password" not in safe_dict
    assert safe_dict["password_masked"] == "••••••••"


def test_connection_config_masking():
    config = ConnectionConfig(
        host="127.0.0.1",
        port=5432,
        database_name="mydb",
        username="admin",
        password="supersecretpassword",
    )
    masked = config.masked_dict()
    assert masked["password"] == "••••••••"
    assert masked["host"] == "127.0.0.1"


def test_standardized_schema_calculations():
    f1 = FieldSchema(
        name="id",
        data_type=StandardDataType.INTEGER,
        native_data_type="int4",
        nullable=False,
        is_primary_key=True,
        position=1,
    )
    f2 = FieldSchema(
        name="email",
        data_type=StandardDataType.STRING,
        native_data_type="varchar",
        nullable=False,
        is_primary_key=False,
        position=2,
    )

    entity = EntitySchema(
        name="users",
        namespace="public",
        entity_type="TABLE",
        fields=[f1, f2],
        primary_key=["id"],
        constraints=[
            ConstraintSchema(
                name="pk_users",
                constraint_type=ConstraintType.PRIMARY_KEY,
                fields=["id"],
            )
        ],
    )

    assert entity.field_count == 2
    assert entity.get_field("id") == f1
    assert entity.get_field("non_existent") is None

    schema = SourceSchema(
        source_id="src-123",
        source_name="Main DB",
        entities=[entity],
    )

    assert schema.entity_count == 1
    assert schema.total_field_count == 2


def test_capabilities_defaults():
    caps = SourceCapabilities()
    assert caps.schema_discovery is True
    assert caps.read is True
    assert caps.write is True
    assert caps.cdc is False  # Future milestone
    assert caps.batch_execution is True
    assert caps.streaming is False
    assert caps.custom_query is False
    assert caps.entity_types == []
    assert caps.supported_operations == []


def test_connection_test_result():
    res = ConnectionTestResult(
        success=True,
        message="Connected",
        latency_ms=12.4,
        server_version="PostgreSQL 16.1",
    )
    assert res.success is True
    assert res.latency_ms == 12.4
