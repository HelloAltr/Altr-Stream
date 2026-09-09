"""Unit tests for AltrQL v0.4 schema binding and type validation on mutations."""

from datetime import datetime, timezone
import pytest

from altr_stream.domain.schema import (
    EntitySchema,
    FieldSchema,
    SourceSchema,
    StandardDataType,
)
from altr_stream.query_engine import parse_altrql
from altr_stream.query_engine.binding.binder import bind_altrql
from altr_stream.query_engine.domain.ast import (
    AltrQueryIR,
    IntegerLiteral,
    MutationAssignment,
    QueryOperation,
    StringLiteral,
)
from altr_stream.query_engine.domain.bound_ast import (
    BoundAltrQueryIR,
    BoundEntity,
    BoundMutationAssignment,
    LogicalTypeCategory,
)
from altr_stream.query_engine.domain.errors import (
    TypeCompatibilityError,
    UnknownEntityError,
    UnknownFieldError,
)


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
                        name="is_active",
                        data_type=StandardDataType.BOOLEAN,
                        native_data_type="bool",
                    ),
                    FieldSchema(
                        name="score",
                        data_type=StandardDataType.FLOAT,
                        native_data_type="float8",
                    ),
                ],
            )
        ],
        discovered_at=datetime.now(timezone.utc),
    )


def test_bind_create_mutation_success(mock_schema: SourceSchema):
    """Test successful schema binding for CREATE."""
    raw_ir = parse_altrql('CREATE users ( username: "alice", email: "alice@test.com", age: 30, score: 98.5, is_active: TRUE );')

    bound = bind_altrql(raw_ir, mock_schema)
    assert isinstance(bound, BoundAltrQueryIR)
    assert bound.operation == QueryOperation.CREATE
    assert bound.entity.name == "users"
    assert bound.entity.namespace == "public"
    assert len(bound.records) == 1
    assert len(bound.records[0].assignments) == 5

    assert bound.records[0].assignments[0].field.segments == ["username"]
    assert bound.records[0].assignments[0].field.logical_category == LogicalTypeCategory.STRING
    assert bound.records[0].assignments[0].value == StringLiteral(value="alice")

    assert bound.records[0].assignments[2].field.segments == ["age"]
    assert bound.records[0].assignments[2].field.logical_category == LogicalTypeCategory.NUMERIC
    assert bound.records[0].assignments[2].value == IntegerLiteral(value=30)


def test_bind_update_mutation_with_where_success(mock_schema: SourceSchema):
    """Test successful schema binding for UPDATE with WHERE filter."""
    raw_ir = parse_altrql('UPDATE users ( email: "updated@test.com" ) WHERE { id = 10 };')

    bound = bind_altrql(raw_ir, mock_schema)
    assert bound.operation == QueryOperation.UPDATE
    assert len(bound.assignments) == 1
    assert bound.assignments[0].field.logical_category == LogicalTypeCategory.STRING
    assert bound.where is not None


def test_bind_delete_mutation_with_where_success(mock_schema: SourceSchema):
    """Test successful schema binding for DELETE."""
    raw_ir = parse_altrql("DELETE users WHERE { age >= 65 };")

    bound = bind_altrql(raw_ir, mock_schema)
    assert bound.operation == QueryOperation.DELETE
    assert bound.assignments == []
    assert bound.where is not None


def test_bind_mutation_unknown_entity_rejected(mock_schema: SourceSchema):
    """Mutations on unknown entities must raise UnknownEntityError."""
    raw_ir = parse_altrql('CREATE non_existent_table ( x: 1 );')
    with pytest.raises(UnknownEntityError):
        bind_altrql(raw_ir, mock_schema)


def test_bind_mutation_unknown_field_rejected(mock_schema: SourceSchema):
    """Assigning to an unknown field must raise UnknownFieldError."""
    raw_ir = parse_altrql('CREATE users ( non_existent_col: "val" );')
    with pytest.raises(UnknownFieldError):
        bind_altrql(raw_ir, mock_schema)


def test_bind_mutation_type_incompatibility_rejected(mock_schema: SourceSchema):
    """Assigning incompatible types (e.g., string to integer column) must raise TypeCompatibilityError."""
    raw_ir = parse_altrql('UPDATE users ( age: "not_a_number" ) WHERE { id = 1 };')
    with pytest.raises(TypeCompatibilityError) as exc_info:
        bind_altrql(raw_ir, mock_schema)
    assert "age" in exc_info.value.message.lower() or "age" in exc_info.value.message.lower()
