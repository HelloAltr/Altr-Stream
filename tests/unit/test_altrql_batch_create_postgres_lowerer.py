"""Unit tests for lowering AltrQL v0.4 batch CREATE into PostgreSQL physical queries."""

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
                    FieldSchema(name="email", data_type=StandardDataType.STRING, native_data_type="varchar"),
                    FieldSchema(name="age", data_type=StandardDataType.INTEGER, native_data_type="int4"),
                    FieldSchema(name="score", data_type=StandardDataType.FLOAT, native_data_type="float8"),
                    FieldSchema(name="is_active", data_type=StandardDataType.BOOLEAN, native_data_type="bool"),
                    FieldSchema(name="created_at", data_type=StandardDataType.TIMESTAMP, native_data_type="timestamptz"),
                ],
            )
        ],
        discovered_at=datetime.datetime.now(timezone.utc),
    )


def test_lower_single_record_create(lowerer: PostgreSQLLowerer, test_schema: SourceSchema):
    """Single-record CREATE produces a single PhysicalQuery."""
    ir = parse_altrql('CREATE users ( username: "alice", email: "alice@example.com" );')
    bound = bind_altrql(ir, test_schema)
    physical = lowerer.lower(bound)

    assert isinstance(physical, PhysicalQuery)
    assert physical.dialect == "postgresql"
    assert physical.query == 'INSERT INTO "public"."users" ("username", "email") VALUES ($1, $2) RETURNING *;'
    assert physical.parameters == ["alice", "alice@example.com"]


def test_lower_homogeneous_batch_create(lowerer: PostgreSQLLowerer, test_schema: SourceSchema):
    """Homogeneous batch CREATE produces a single multi-row PhysicalQuery with sequential parameter indexing."""
    ir = parse_altrql("""
    CREATE users (
        (username: "alice", email: "alice@example.com"),
        (username: "bob", email: "bob@example.com"),
        (username: "carol", email: "carol@example.com")
    );
    """)
    bound = bind_altrql(ir, test_schema)
    physical = lowerer.lower(bound)

    assert isinstance(physical, PhysicalQuery)
    assert physical.dialect == "postgresql"
    assert (
        physical.query
        == 'INSERT INTO "public"."users" ("username", "email") VALUES ($1, $2), ($3, $4), ($5, $6) RETURNING *;'
    )
    assert physical.parameters == [
        "alice",
        "alice@example.com",
        "bob",
        "bob@example.com",
        "carol",
        "carol@example.com",
    ]


def test_lower_heterogeneous_batch_consecutive_grouping(lowerer: PostgreSQLLowerer, test_schema: SourceSchema):
    """Consecutive records with identical columns are grouped, but non-consecutive matching shapes are NOT regrouped globally."""
    # Pattern: A, A, B, A
    ir = parse_altrql("""
    CREATE users (
        (username: "alice", email: "alice@example.com"),
        (username: "bob", email: "bob@example.com"),
        (username: "charlie", age: 30),
        (username: "david", email: "david@example.com")
    );
    """)
    bound = bind_altrql(ir, test_schema)
    result = lowerer.lower(bound)

    assert isinstance(result, PhysicalQueryBatch)
    assert len(result.queries) == 3

    # Group 1: Alice and Bob (shape: username, email)
    q1 = result.queries[0]
    assert q1.dialect == "postgresql"
    assert q1.query == 'INSERT INTO "public"."users" ("username", "email") VALUES ($1, $2), ($3, $4) RETURNING *;'
    assert q1.parameters == ["alice", "alice@example.com", "bob", "bob@example.com"]

    # Group 2: Charlie (shape: username, age) - Note parameter indexing starts at $1
    q2 = result.queries[1]
    assert q2.dialect == "postgresql"
    assert q2.query == 'INSERT INTO "public"."users" ("username", "age") VALUES ($1, $2) RETURNING *;'
    assert q2.parameters == ["charlie", 30]

    # Group 3: David (shape: username, email) - Not merged with group 1! Parameter indexing starts at $1
    q3 = result.queries[2]
    assert q3.dialect == "postgresql"
    assert q3.query == 'INSERT INTO "public"."users" ("username", "email") VALUES ($1, $2) RETURNING *;'
    assert q3.parameters == ["david", "david@example.com"]


def test_lower_batch_create_with_diverse_types(lowerer: PostgreSQLLowerer, test_schema: SourceSchema):
    """Batch CREATE with nulls, booleans, floats, and temporal literals."""
    ir = parse_altrql("""
    CREATE users (
        (username: "alice", is_active: TRUE, score: 95.5, created_at: @2026-09-08),
        (username: "bob", is_active: FALSE, score: NULL, created_at: @2026-09-09)
    );
    """)
    bound = bind_altrql(ir, test_schema)
    physical = lowerer.lower(bound)

    assert isinstance(physical, PhysicalQuery)
    assert (
        physical.query
        == 'INSERT INTO "public"."users" ("username", "is_active", "score", "created_at") VALUES ($1, $2, $3, $4), ($5, $6, NULL, $7) RETURNING *;'
    )
    assert physical.parameters[0] == "alice"
    assert physical.parameters[1] is True
    assert physical.parameters[2] == 95.5
    assert isinstance(physical.parameters[3], datetime.date)
    assert physical.parameters[3] == datetime.date(2026, 9, 8)

    assert physical.parameters[4] == "bob"
    assert physical.parameters[5] is False
    assert isinstance(physical.parameters[6], datetime.date)
    assert physical.parameters[6] == datetime.date(2026, 9, 9)
    assert len(physical.parameters) == 7
