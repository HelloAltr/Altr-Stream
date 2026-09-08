"""Unit tests for AltrQL v0.4 schema binding and type validation on batch CREATE."""

from datetime import datetime, timezone
import pytest

from altr_stream.domain.schema import (
    EntitySchema,
    FieldSchema,
    SourceSchema,
    StandardDataType,
)
from altr_stream.query_engine.binding.binder import bind_altrql
from altr_stream.query_engine.domain.ast import (
    IntegerLiteral,
    QueryOperation,
    StringLiteral,
)
from altr_stream.query_engine.domain.bound_ast import (
    BoundAltrQueryIR,
    BoundCreateRecord,
    LogicalTypeCategory,
)
from altr_stream.query_engine.domain.errors import (
    TypeCompatibilityError,
    UnknownEntityError,
    UnknownFieldError,
)
from altr_stream.query_engine.parser import parse_altrql


@pytest.fixture
def mock_schema() -> SourceSchema:
    return SourceSchema(
        source_id="src_test",
        source_name="Test DB",
        entities=[
            EntitySchema(
                name="users",
                namespace="public",
                fields=[
                    FieldSchema(
                        name="id",
                        data_type=StandardDataType.INTEGER,
                        native_data_type="int4",
                        is_primary_key=True,
                    ),
                    FieldSchema(
                        name="username",
                        data_type=StandardDataType.STRING,
                        native_data_type="varchar",
                    ),
                    FieldSchema(
                        name="email",
                        data_type=StandardDataType.STRING,
                        native_data_type="varchar",
                    ),
                    FieldSchema(
                        name="age",
                        data_type=StandardDataType.INTEGER,
                        native_data_type="int4",
                    ),
                    FieldSchema(
                        name="score",
                        data_type=StandardDataType.FLOAT,
                        native_data_type="float8",
                    ),
                    FieldSchema(
                        name="is_active",
                        data_type=StandardDataType.BOOLEAN,
                        native_data_type="bool",
                    ),
                ],
            )
        ],
        discovered_at=datetime.now(timezone.utc),
    )


def test_bind_homogeneous_batch_create(mock_schema: SourceSchema):
    """Homogeneous batch CREATE binds each record correctly with full schema info."""
    raw_ir = parse_altrql("""
    CREATE users (
        (username: "alice", email: "alice@test.com", age: 30),
        (username: "bob", email: "bob@test.com", age: 25)
    );
    """)

    bound = bind_altrql(raw_ir, mock_schema)
    assert isinstance(bound, BoundAltrQueryIR)
    assert bound.operation == QueryOperation.CREATE
    assert len(bound.records) == 2
    assert all(isinstance(r, BoundCreateRecord) for r in bound.records)

    # Record 1
    r1 = bound.records[0]
    assert len(r1.assignments) == 3
    assert r1.assignments[0].field.segments == ["username"]
    assert r1.assignments[0].field.logical_category == LogicalTypeCategory.STRING
    assert r1.assignments[0].value == StringLiteral(value="alice")
    assert r1.assignments[2].field.segments == ["age"]
    assert r1.assignments[2].field.logical_category == LogicalTypeCategory.NUMERIC
    assert r1.assignments[2].value == IntegerLiteral(value=30)

    # Record 2
    r2 = bound.records[1]
    assert len(r2.assignments) == 3
    assert r2.assignments[0].field.segments == ["username"]
    assert r2.assignments[0].value == StringLiteral(value="bob")
    assert r2.assignments[2].value == IntegerLiteral(value=25)


def test_bind_heterogeneous_batch_create(mock_schema: SourceSchema):
    """Heterogeneous batch CREATE binds different field shapes across records."""
    raw_ir = parse_altrql("""
    CREATE users (
        (username: "alice", email: "alice@test.com"),
        (username: "bob", age: 25, is_active: TRUE),
        (username: "carol", score: 99.5)
    );
    """)

    bound = bind_altrql(raw_ir, mock_schema)
    assert len(bound.records) == 3

    # Check distinct shapes
    cols_r0 = [a.field.path.leaf for a in bound.records[0].assignments]
    assert cols_r0 == ["username", "email"]

    cols_r1 = [a.field.path.leaf for a in bound.records[1].assignments]
    assert cols_r1 == ["username", "age", "is_active"]

    cols_r2 = [a.field.path.leaf for a in bound.records[2].assignments]
    assert cols_r2 == ["username", "score"]


def test_bind_batch_create_unknown_entity(mock_schema: SourceSchema):
    """Batch CREATE with nonexistent entity raises UnknownEntityError."""
    raw_ir = parse_altrql("""
    CREATE nonexistent (
        (name: "alice"),
        (name: "bob")
    );
    """)
    with pytest.raises(UnknownEntityError):
        bind_altrql(raw_ir, mock_schema)


def test_bind_batch_create_unknown_field_in_second_record(mock_schema: SourceSchema):
    """Unknown field in any record of a batch raises UnknownFieldError."""
    raw_ir = parse_altrql("""
    CREATE users (
        (username: "alice", email: "alice@test.com"),
        (username: "bob", nonexistent_field: "foo")
    );
    """)
    with pytest.raises(UnknownFieldError) as exc_info:
        bind_altrql(raw_ir, mock_schema)
    assert "nonexistent_field" in str(exc_info.value)


def test_bind_batch_create_type_incompatibility(mock_schema: SourceSchema):
    """Type mismatch in any record of a batch raises TypeCompatibilityError."""
    raw_ir = parse_altrql("""
    CREATE users (
        (username: "alice", age: 30),
        (username: "bob", age: "not_a_number")
    );
    """)
    with pytest.raises(TypeCompatibilityError) as exc_info:
        bind_altrql(raw_ir, mock_schema)
    assert "age" in str(exc_info.value)
