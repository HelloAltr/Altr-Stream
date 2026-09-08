"""Unit tests for lowering AltrQL v0.2 mutations into physical PostgreSQL dialect."""

from datetime import datetime, timezone
import pytest

from altr_stream.domain.schema import (
    EntitySchema,
    FieldSchema,
    SourceSchema,
    StandardDataType,
)
from altr_stream.query_engine.binding import bind_altrql
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
                    FieldSchema(name="is_active", data_type=StandardDataType.BOOLEAN, native_data_type="bool"),
                ],
            )
        ],
        discovered_at=datetime.now(timezone.utc),
    )


def test_lower_create_mutation(lowerer: PostgreSQLLowerer, test_schema: SourceSchema):
    """CREATE lowers into parameterized INSERT ... VALUES ... RETURNING *."""
    ir = parse_altrql('CREATE users ( username: "alice", age: 28 );')
    bound = bind_altrql(ir, test_schema)
    physical = lowerer.lower(bound)

    assert physical.dialect == "postgresql"
    assert physical.query == 'INSERT INTO "public"."users" ("username", "age") VALUES ($1, $2) RETURNING *;'
    assert physical.parameters == ["alice", 28]


def test_lower_constrained_update_mutation(lowerer: PostgreSQLLowerer, test_schema: SourceSchema):
    """UPDATE with WHERE lowers into UPDATE ... SET ... WHERE ... RETURNING * with correct parameter ordering."""
    ir = parse_altrql('UPDATE users ( email: "new_email@test.com", is_active: TRUE ) WHERE { id = 42 };')
    bound = bind_altrql(ir, test_schema)
    physical = lowerer.lower(bound)

    assert physical.dialect == "postgresql"
    assert (
        physical.query
        == 'UPDATE "public"."users" SET "email" = $1, "is_active" = $2 WHERE "id" = $3 RETURNING *;'
    )
    # Parameter ordering: assignments first ($1, $2), then WHERE ($3)
    assert physical.parameters == ["new_email@test.com", True, 42]


def test_lower_mass_update_mutation(lowerer: PostgreSQLLowerer, test_schema: SourceSchema):
    """Mass UPDATE without WHERE lowers into UPDATE ... SET ... RETURNING *."""
    ir = parse_altrql('UPDATE users ( is_active: FALSE );')
    bound = bind_altrql(ir, test_schema)
    physical = lowerer.lower(bound)

    assert physical.dialect == "postgresql"
    assert physical.query == 'UPDATE "public"."users" SET "is_active" = $1 RETURNING *;'
    assert physical.parameters == [False]


def test_lower_constrained_delete_mutation(lowerer: PostgreSQLLowerer, test_schema: SourceSchema):
    """DELETE with WHERE lowers into DELETE FROM ... WHERE ... RETURNING *."""
    ir = parse_altrql('DELETE users WHERE { id = 100 };')
    bound = bind_altrql(ir, test_schema)
    physical = lowerer.lower(bound)

    assert physical.dialect == "postgresql"
    assert physical.query == 'DELETE FROM "public"."users" WHERE "id" = $1 RETURNING *;'
    assert physical.parameters == [100]


def test_lower_mass_delete_mutation(lowerer: PostgreSQLLowerer, test_schema: SourceSchema):
    """Mass DELETE without WHERE lowers into DELETE FROM ... RETURNING *."""
    ir = parse_altrql('DELETE users;')
    bound = bind_altrql(ir, test_schema)
    physical = lowerer.lower(bound)

    assert physical.dialect == "postgresql"
    assert physical.query == 'DELETE FROM "public"."users" RETURNING *;'
    assert physical.parameters == []
