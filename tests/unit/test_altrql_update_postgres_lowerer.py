"""Unit tests for lowering AltrQL v0.4 UPDATE queries into PostgreSQL dialect."""

import datetime
from datetime import timezone
import pytest

from altr_stream.domain.schema import (
    EntitySchema,
    FieldSchema,
    SourceSchema,
    StandardDataType,
)
from altr_stream.query_engine.binding import bind_altrql
from altr_stream.query_engine.domain.physical_query import PhysicalQuery, PhysicalQueryBatch
from altr_stream.query_engine.lowering.postgres import PostgreSQLLowerer
from altr_stream.query_engine.parser import parse_altrql


@pytest.fixture
def lowerer() -> PostgreSQLLowerer:
    return PostgreSQLLowerer()


@pytest.fixture
def test_schema() -> SourceSchema:
    return SourceSchema(
        source_id="src_1",
        source_name="Postgres DB",
        entities=[
            EntitySchema(
                name="users",
                namespace="public",
                entity_type="TABLE",
                fields=[
                    FieldSchema(name="id", data_type=StandardDataType.INTEGER, native_data_type="int4", is_primary_key=True),
                    FieldSchema(name="username", data_type=StandardDataType.STRING, native_data_type="varchar"),
                    FieldSchema(name="email", data_type=StandardDataType.STRING, native_data_type="varchar", nullable=True),
                    FieldSchema(name="age", data_type=StandardDataType.INTEGER, native_data_type="int4", nullable=True),
                    FieldSchema(name="is_active", data_type=StandardDataType.BOOLEAN, native_data_type="bool"),
                    FieldSchema(name="score", data_type=StandardDataType.FLOAT, native_data_type="float8", nullable=True),
                    FieldSchema(name="created_at", data_type=StandardDataType.TIMESTAMP, native_data_type="timestamptz"),
                ],
            )
        ],
        discovered_at=datetime.datetime.now(timezone.utc),
    )


def test_lower_update_single_field(lowerer: PostgreSQLLowerer, test_schema: SourceSchema):
    """Single field UPDATE lowers into parameterized SQL with deterministic parameter order."""
    ir = parse_altrql('UPDATE users ( is_active: FALSE ) WHERE { id = 1 };')
    bound = bind_altrql(ir, test_schema)
    physical = lowerer.lower(bound)

    assert isinstance(physical, PhysicalQuery)
    assert not isinstance(physical, PhysicalQueryBatch)
    assert physical.dialect == "postgresql"
    assert physical.query == 'UPDATE "public"."users" SET "is_active" = $1 WHERE "id" = $2 RETURNING *;'
    assert physical.parameters == [False, 1]


def test_lower_update_multiple_fields_preserves_source_order(lowerer: PostgreSQLLowerer, test_schema: SourceSchema):
    """Multiple fields UPDATE preserves exact source order of SET assignments before WHERE parameters."""
    ir = parse_altrql("""
    UPDATE users (
        username: "alice_updated",
        is_active: TRUE,
        age: 30
    ) WHERE {
        email = "alice@example.com"
    };
    """)
    bound = bind_altrql(ir, test_schema)
    physical = lowerer.lower(bound)

    assert isinstance(physical, PhysicalQuery)
    assert (
        physical.query
        == 'UPDATE "public"."users" SET "username" = $1, "is_active" = $2, "age" = $3 WHERE "email" = $4 RETURNING *;'
    )
    assert physical.parameters == ["alice_updated", True, 30, "alice@example.com"]


def test_lower_update_with_complex_where(lowerer: PostgreSQLLowerer, test_schema: SourceSchema):
    """UPDATE with compound WHERE (AND, OR, NOT) ensures assignment parameters precede condition parameters."""
    ir = parse_altrql("""
    UPDATE users (
        is_active: FALSE
    ) WHERE {
        NOT { age < 18 }
        AND {
            email = "alice@example.com"
            OR email = "bob@example.com"
        }
    };
    """)
    bound = bind_altrql(ir, test_schema)
    physical = lowerer.lower(bound)

    assert isinstance(physical, PhysicalQuery)
    assert physical.parameters[0] is False  # Assignment parameter $1
    assert physical.parameters[1] == 18     # Condition parameter $2
    assert physical.parameters[2] == "alice@example.com"  # Condition parameter $3
    assert physical.parameters[3] == "bob@example.com"    # Condition parameter $4


def test_lower_update_with_value_set_condition(lowerer: PostgreSQLLowerer, test_schema: SourceSchema):
    """UPDATE with ValueSet condition in WHERE."""
    ir = parse_altrql("""
    UPDATE users (
        is_active: FALSE
    ) WHERE {
        email = {
            "alice@example.com",
            "bob@example.com"
        }
    };
    """)
    bound = bind_altrql(ir, test_schema)
    physical = lowerer.lower(bound)

    assert isinstance(physical, PhysicalQuery)
    assert physical.query == 'UPDATE "public"."users" SET "is_active" = $1 WHERE "email" IN ($2, $3) RETURNING *;'
    assert physical.parameters == [False, "alice@example.com", "bob@example.com"]


def test_lower_update_with_temporal_timestamp_condition(lowerer: PostgreSQLLowerer, test_schema: SourceSchema):
    """UPDATE with date-only temporal literal equality on timestamp field expands to day range."""
    ir = parse_altrql("""
    UPDATE users (
        is_active: FALSE
    ) WHERE {
        created_at = @2026-09-06
    };
    """)
    bound = bind_altrql(ir, test_schema)
    physical = lowerer.lower(bound)

    assert isinstance(physical, PhysicalQuery)
    assert physical.query == 'UPDATE "public"."users" SET "is_active" = $1 WHERE ("created_at" >= $2 AND "created_at" < $3) RETURNING *;'
    assert physical.parameters[0] is False
    assert physical.parameters[1] == datetime.datetime(2026, 9, 6, 0, 0)
    assert physical.parameters[2] == datetime.datetime(2026, 9, 7, 0, 0)
