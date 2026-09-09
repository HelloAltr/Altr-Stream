"""Unit tests for AltrQL v0.4 Advanced Conditional Logic & Expression Grouping Schema Binder."""

import pytest

from altr_stream.domain.schema import EntitySchema, FieldSchema, SourceSchema, StandardDataType
from altr_stream.query_engine import (
    BoundFieldExpression,
    BoundLogicalExpression,
    BoundNegationExpression,
    LogicalOperator,
    LogicalTypeCategory,
    StringOperator,
    TypeCompatibilityError,
    UnknownFieldError,
    bind_altrql,
    parse_altrql,
)


@pytest.fixture
def user_schema() -> SourceSchema:
    return SourceSchema(
        source_id="src_users",
        source_name="user_db",
        entities=[
            EntitySchema(
                name="users",
                fields=[
                    FieldSchema(name="id", data_type=StandardDataType.INTEGER, native_data_type="int4", is_primary_key=True),
                    FieldSchema(name="username", data_type=StandardDataType.STRING, native_data_type="varchar"),
                    FieldSchema(name="role", data_type=StandardDataType.STRING, native_data_type="varchar"),
                    FieldSchema(name="age", data_type=StandardDataType.INTEGER, native_data_type="int4"),
                    FieldSchema(name="is_active", data_type=StandardDataType.BOOLEAN, native_data_type="bool"),
                    FieldSchema(name="tags", data_type=StandardDataType.STRING, native_data_type="varchar"),
                    FieldSchema(name="created_at", data_type=StandardDataType.TIMESTAMP, native_data_type="timestamp"),
                ],
            )
        ],
    )


def test_bind_nested_logical_expression_tree(user_schema: SourceSchema):
    query = """
    GET users WHERE {
        {
            is_active = TRUE,
            age >= 18
        } OR {
            role = "admin",
            tags HAS "superuser"
        }
    };
    """
    ir = parse_altrql(query)
    bound = bind_altrql(ir, user_schema)

    assert bound.where is not None
    assert isinstance(bound.where, BoundLogicalExpression)
    assert bound.where.operator == LogicalOperator.OR

    left_and = bound.where.left
    assert isinstance(left_and, BoundLogicalExpression)
    assert left_and.operator == LogicalOperator.AND
    assert isinstance(left_and.left, BoundFieldExpression)
    assert left_and.left.field.segments == ["is_active"]
    assert left_and.left.field.logical_category == LogicalTypeCategory.BOOLEAN
    assert isinstance(left_and.right, BoundFieldExpression)
    assert left_and.right.field.segments == ["age"]
    assert left_and.right.field.logical_category == LogicalTypeCategory.NUMERIC

    right_and = bound.where.right
    assert isinstance(right_and, BoundLogicalExpression)
    assert right_and.operator == LogicalOperator.AND
    assert isinstance(right_and.left, BoundFieldExpression)
    assert right_and.left.field.segments == ["role"]
    assert isinstance(right_and.right, BoundFieldExpression)
    assert right_and.right.field.segments == ["tags"]
    assert right_and.right.operator == StringOperator.HAS


def test_bind_negation_expression(user_schema: SourceSchema):
    query = """
    GET users WHERE {
        NOT {
            is_active = FALSE,
            age < 18
        }
    };
    """
    ir = parse_altrql(query)
    bound = bind_altrql(ir, user_schema)

    assert bound.where is not None
    assert isinstance(bound.where, BoundNegationExpression)
    assert isinstance(bound.where.operand, BoundLogicalExpression)
    assert bound.where.operand.operator == LogicalOperator.AND
    assert bound.where.operand.left.field.segments == ["is_active"]
    assert bound.where.operand.right.field.segments == ["age"]


def test_bind_dedicated_not_has(user_schema: SourceSchema):
    query = 'GET users WHERE { tags NOT HAS "banned" };'
    ir = parse_altrql(query)
    bound = bind_altrql(ir, user_schema)

    assert isinstance(bound.where, BoundFieldExpression)
    assert bound.where.field.segments == ["tags"]
    assert bound.where.operator == StringOperator.NOT_HAS


def test_bind_rejects_unknown_field_in_nested_expression(user_schema: SourceSchema):
    query = """
    GET users WHERE {
        is_active = TRUE OR {
            non_existent_field = "test"
        }
    };
    """
    ir = parse_altrql(query)
    with pytest.raises(UnknownFieldError) as exc_info:
        bind_altrql(ir, user_schema)
    assert "non_existent_field" in str(exc_info.value)


def test_bind_rejects_type_mismatch_in_nested_expression(user_schema: SourceSchema):
    query = """
    GET users WHERE {
        {
            age >= "invalid_string_age"
        } OR role = "admin"
    };
    """
    ir = parse_altrql(query)
    with pytest.raises(TypeCompatibilityError) as exc_info:
        bind_altrql(ir, user_schema)
    assert "NUMERIC" in str(exc_info.value)
    assert "STRING" in str(exc_info.value)
