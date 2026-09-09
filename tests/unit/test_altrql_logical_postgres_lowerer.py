"""Unit tests for AltrQL v0.4 Advanced Conditional Logic & Expression Grouping PostgreSQL Lowerer."""

import pytest

from altr_stream.domain.schema import EntitySchema, FieldSchema, SourceSchema, StandardDataType
from altr_stream.query_engine import (
    PostgreSQLLowerer,
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
                namespace="public",
                fields=[
                    FieldSchema(name="id", data_type=StandardDataType.INTEGER, native_data_type="int4", is_primary_key=True),
                    FieldSchema(name="username", data_type=StandardDataType.STRING, native_data_type="varchar"),
                    FieldSchema(name="role", data_type=StandardDataType.STRING, native_data_type="varchar"),
                    FieldSchema(name="age", data_type=StandardDataType.INTEGER, native_data_type="int4"),
                    FieldSchema(name="is_active", data_type=StandardDataType.BOOLEAN, native_data_type="bool"),
                    FieldSchema(name="verified", data_type=StandardDataType.BOOLEAN, native_data_type="bool"),
                    FieldSchema(name="tags", data_type=StandardDataType.STRING, native_data_type="varchar"),
                    FieldSchema(name="created_at", data_type=StandardDataType.TIMESTAMP, native_data_type="timestamp"),
                ],
            )
        ],
    )


def test_lower_implicit_and_with_commas(user_schema: SourceSchema):
    query = """
    GET users WHERE {
        is_active = TRUE,
        age >= 18
    };
    """
    ir = parse_altrql(query)
    bound = bind_altrql(ir, user_schema)
    lowerer = PostgreSQLLowerer()
    pq = lowerer.lower(bound)

    assert pq.query == 'SELECT * FROM "public"."users" WHERE ("is_active" = $1 AND "age" >= $2);'
    assert pq.parameters == [True, 18]


def test_lower_nested_grouped_or(user_schema: SourceSchema):
    query = """
    GET users WHERE {
        {
            is_active = TRUE,
            age >= 18
        } OR {
            role = "admin",
            verified = TRUE
        }
    };
    """
    ir = parse_altrql(query)
    bound = bind_altrql(ir, user_schema)
    lowerer = PostgreSQLLowerer()
    pq = lowerer.lower(bound)

    assert pq.query == 'SELECT * FROM "public"."users" WHERE (("is_active" = $1 AND "age" >= $2) OR ("role" = $3 AND "verified" = $4));'
    assert pq.parameters == [True, 18, "admin", True]


def test_lower_grouped_negation(user_schema: SourceSchema):
    query = """
    GET users WHERE {
        NOT {
            is_active = FALSE,
            verified = FALSE
        }
    };
    """
    ir = parse_altrql(query)
    bound = bind_altrql(ir, user_schema)
    lowerer = PostgreSQLLowerer()
    pq = lowerer.lower(bound)

    assert pq.query == 'SELECT * FROM "public"."users" WHERE NOT ("is_active" = $1 AND "verified" = $2);'
    assert pq.parameters == [False, False]


def test_lower_single_field_negation(user_schema: SourceSchema):
    query = """
    GET users WHERE {
        NOT is_active = FALSE
    };
    """
    ir = parse_altrql(query)
    bound = bind_altrql(ir, user_schema)
    lowerer = PostgreSQLLowerer()
    pq = lowerer.lower(bound)

    assert pq.query == 'SELECT * FROM "public"."users" WHERE NOT ("is_active" = $1);'
    assert pq.parameters == [False]


def test_lower_dedicated_not_has(user_schema: SourceSchema):
    query = 'GET users WHERE { tags NOT HAS "banned" };'
    ir = parse_altrql(query)
    bound = bind_altrql(ir, user_schema)
    lowerer = PostgreSQLLowerer()
    pq = lowerer.lower(bound)

    assert pq.query == 'SELECT * FROM "public"."users" WHERE ("tags" NOT LIKE $1 OR "tags" IS NULL);'
    assert pq.parameters == ["%banned%"]


def test_lower_update_with_advanced_logical_where(user_schema: SourceSchema):
    query = """
    UPDATE users (
        is_active: FALSE
    ) WHERE {
        role = "guest" OR age < 18
    };
    """
    ir = parse_altrql(query)
    bound = bind_altrql(ir, user_schema)
    lowerer = PostgreSQLLowerer()
    pq = lowerer.lower(bound)

    # SET param first ($1), followed by WHERE params ($2, $3)
    assert pq.query == 'UPDATE "public"."users" SET "is_active" = $1 WHERE ("role" = $2 OR "age" < $3) RETURNING *;'
    assert pq.parameters == [False, "guest", 18]


def test_lower_delete_with_advanced_logical_where(user_schema: SourceSchema):
    query = """
    DELETE users WHERE {
        NOT { is_active = TRUE },
        role = "temp"
    };
    """
    ir = parse_altrql(query)
    bound = bind_altrql(ir, user_schema)
    lowerer = PostgreSQLLowerer()
    pq = lowerer.lower(bound)

    assert pq.query == 'DELETE FROM "public"."users" WHERE (NOT ("is_active" = $1) AND "role" = $2) RETURNING *;'
    assert pq.parameters == [True, "temp"]
