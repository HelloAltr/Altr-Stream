"""Unit tests for AltrQL v0.4 UPDATE schema binding and type validation."""

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
    BooleanLiteral,
    IntegerLiteral,
    NullLiteral,
    QueryOperation,
    StringLiteral,
)
from altr_stream.query_engine.domain.bound_ast import (
    BoundAltrQueryIR,
    BoundMutationAssignment,
    LogicalTypeCategory,
)
from altr_stream.query_engine.domain.errors import (
    TypeCompatibilityError,
    UnknownEntityError,
    UnknownFieldError,
)
from altr_stream.query_engine.parser import parse_altrql


@pytest.fixture
def test_schema() -> SourceSchema:
    return SourceSchema(
        source_id="src_1",
        source_name="Postgres DB",
        entities=[
            EntitySchema(
                name="users",
                namespace="public",
                fields=[
                    FieldSchema(name="id", data_type=StandardDataType.INTEGER, native_data_type="int4", is_primary_key=True),
                    FieldSchema(name="username", data_type=StandardDataType.STRING, native_data_type="varchar"),
                    FieldSchema(name="email", data_type=StandardDataType.STRING, native_data_type="varchar", nullable=True),
                    FieldSchema(name="age", data_type=StandardDataType.INTEGER, native_data_type="int4", nullable=True),
                    FieldSchema(name="score", data_type=StandardDataType.FLOAT, native_data_type="float8", nullable=True),
                    FieldSchema(name="is_active", data_type=StandardDataType.BOOLEAN, native_data_type="bool"),
                    FieldSchema(name="created_at", data_type=StandardDataType.TIMESTAMP, native_data_type="timestamptz"),
                ],
            )
        ],
        discovered_at=datetime.now(timezone.utc),
    )


def test_bind_update_success(test_schema: SourceSchema):
    """Test successful schema binding for UPDATE with multiple diverse assignments and WHERE."""
    raw_ir = parse_altrql("""
    UPDATE users (
        username: "alice_updated",
        is_active: TRUE,
        age: 32,
        score: 99.5,
        email: NULL
    ) WHERE {
        id = 1
    };
    """)

    bound = bind_altrql(raw_ir, test_schema)
    assert isinstance(bound, BoundAltrQueryIR)
    assert bound.operation == QueryOperation.UPDATE
    assert bound.entity.name == "users"
    assert bound.entity.namespace == "public"
    assert len(bound.assignments) == 5

    # Check assignment types
    assert bound.assignments[0].field.segments == ["username"]
    assert bound.assignments[0].field.logical_category == LogicalTypeCategory.STRING
    assert bound.assignments[0].value == StringLiteral(value="alice_updated")

    assert bound.assignments[1].field.segments == ["is_active"]
    assert bound.assignments[1].field.logical_category == LogicalTypeCategory.BOOLEAN
    assert bound.assignments[1].value == BooleanLiteral(value=True)

    assert bound.assignments[2].field.segments == ["age"]
    assert bound.assignments[2].field.logical_category == LogicalTypeCategory.NUMERIC
    assert bound.assignments[2].value == IntegerLiteral(value=32)

    assert bound.assignments[4].field.segments == ["email"]
    assert isinstance(bound.assignments[4].value, NullLiteral)

    assert bound.where is not None


def test_bind_update_unknown_entity(test_schema: SourceSchema):
    """UPDATE on nonexistent entity raises UnknownEntityError."""
    raw_ir = parse_altrql('UPDATE nonexistent ( is_active: FALSE ) WHERE { id = 1 };')
    with pytest.raises(UnknownEntityError):
        bind_altrql(raw_ir, test_schema)


def test_bind_update_unknown_assignment_field(test_schema: SourceSchema):
    """UPDATE with unknown field in assignments raises UnknownFieldError."""
    raw_ir = parse_altrql('UPDATE users ( imaginary_field: "val" ) WHERE { id = 1 };')
    with pytest.raises(UnknownFieldError) as exc_info:
        bind_altrql(raw_ir, test_schema)
    assert "imaginary_field" in str(exc_info.value)


def test_bind_update_assignment_type_mismatch(test_schema: SourceSchema):
    """UPDATE with type mismatch in assignment raises TypeCompatibilityError."""
    # Boolean assigned string
    raw_ir1 = parse_altrql('UPDATE users ( is_active: "not_a_bool" ) WHERE { id = 1 };')
    with pytest.raises(TypeCompatibilityError) as exc_info1:
        bind_altrql(raw_ir1, test_schema)
    assert "is_active" in str(exc_info1.value)

    # Integer assigned string
    raw_ir2 = parse_altrql('UPDATE users ( age: "thirty" ) WHERE { id = 1 };')
    with pytest.raises(TypeCompatibilityError) as exc_info2:
        bind_altrql(raw_ir2, test_schema)
    assert "age" in str(exc_info2.value)


def test_bind_update_condition_type_mismatch(test_schema: SourceSchema):
    """UPDATE with type mismatch in WHERE condition raises TypeCompatibilityError."""
    raw_ir = parse_altrql('UPDATE users ( is_active: TRUE ) WHERE { id = "not_an_int" };')
    with pytest.raises(TypeCompatibilityError) as exc_info:
        bind_altrql(raw_ir, test_schema)
    assert "id" in str(exc_info.value)


def test_bind_update_condition_unknown_field(test_schema: SourceSchema):
    """UPDATE with unknown field in WHERE condition raises UnknownFieldError."""
    raw_ir = parse_altrql('UPDATE users ( is_active: TRUE ) WHERE { unknown_col = 1 };')
    with pytest.raises(UnknownFieldError) as exc_info:
        bind_altrql(raw_ir, test_schema)
    assert "unknown_col" in str(exc_info.value)
