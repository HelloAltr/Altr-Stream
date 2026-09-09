"""Unit tests for SQLite dialect physical query lowering."""

import pytest

from altr_stream.domain.schema import (
    EntitySchema,
    FieldSchema,
    SourceSchema,
    StandardDataType,
)
from altr_stream.query_engine.binding.binder import bind_altrql
from altr_stream.query_engine.lowering.sqlite import SQLiteLowerer
from altr_stream.query_engine.parser import parse_altrql


@pytest.fixture
def sqlite_schema() -> SourceSchema:
    return SourceSchema(
        source_id="src_sqlite_test",
        source_name="SQLite Test Source",
        version="1.0.0",
        entities=[
            EntitySchema(
                name="users",
                namespace="main",
                entity_type="TABLE",
                fields=[
                    FieldSchema(name="id", data_type=StandardDataType.INTEGER, native_data_type="INTEGER", nullable=False, is_primary_key=True),
                    FieldSchema(name="email", data_type=StandardDataType.STRING, native_data_type="TEXT", nullable=False),
                    FieldSchema(name="status", data_type=StandardDataType.STRING, native_data_type="TEXT", nullable=True),
                    FieldSchema(name="age", data_type=StandardDataType.INTEGER, native_data_type="INTEGER", nullable=True),
                    FieldSchema(name="metadata", data_type=StandardDataType.JSON, native_data_type="TEXT", nullable=True),
                    FieldSchema(name="created_at", data_type=StandardDataType.TIMESTAMP, native_data_type="TEXT", nullable=False),
                ],
                primary_key=["id"],
            )
        ],
    )


def test_sqlite_lower_read_simple(sqlite_schema: SourceSchema):
    bound = bind_altrql(parse_altrql("GET users;"), sqlite_schema)
    lowerer = SQLiteLowerer()
    res = lowerer.lower(bound)
    assert res.dialect == "sqlite"
    assert res.query == 'SELECT * FROM "users";'
    assert res.parameters == []


def test_sqlite_lower_read_with_filter_and_projection(sqlite_schema: SourceSchema):
    bound = bind_altrql(parse_altrql('GET users (id, email) WHERE { status = "ACTIVE" };'), sqlite_schema)
    lowerer = SQLiteLowerer()
    res = lowerer.lower(bound)
    assert res.query == 'SELECT "id", "email" FROM "users" WHERE "status" = ?;'
    assert res.parameters == ["ACTIVE"]


def test_sqlite_lower_null_equality_and_inequality(sqlite_schema: SourceSchema):
    bound_eq = bind_altrql(parse_altrql("GET users WHERE { metadata = NULL };"), sqlite_schema)
    lowerer = SQLiteLowerer()
    res_eq = lowerer.lower(bound_eq)
    assert res_eq.query == 'SELECT * FROM "users" WHERE "metadata" IS NULL;'
    assert res_eq.parameters == []

    bound_neq = bind_altrql(parse_altrql("GET users WHERE { metadata != NULL };"), sqlite_schema)
    res_neq = lowerer.lower(bound_neq)
    assert res_neq.query == 'SELECT * FROM "users" WHERE "metadata" IS NOT NULL;'
    assert res_neq.parameters == []


def test_sqlite_lower_valueset_with_null(sqlite_schema: SourceSchema):
    bound = bind_altrql(parse_altrql('GET users WHERE { status = {"ACTIVE", "PENDING", NULL} };'), sqlite_schema)
    lowerer = SQLiteLowerer()
    res = lowerer.lower(bound)
    assert res.query == 'SELECT * FROM "users" WHERE ("status" IS NULL OR "status" IN (?, ?));'
    assert res.parameters == ["ACTIVE", "PENDING"]


def test_sqlite_lower_string_has_and_not_has(sqlite_schema: SourceSchema):
    bound_has = bind_altrql(parse_altrql('GET users WHERE { email HAS "example" };'), sqlite_schema)
    lowerer = SQLiteLowerer()
    res_has = lowerer.lower(bound_has)
    assert res_has.query == 'SELECT * FROM "users" WHERE "email" LIKE ?;'
    assert res_has.parameters == ["%example%"]

    bound_not_has = bind_altrql(parse_altrql('GET users WHERE { status NOT HAS "act" };'), sqlite_schema)
    res_not_has = lowerer.lower(bound_not_has)
    assert res_not_has.query == 'SELECT * FROM "users" WHERE ("status" NOT LIKE ? OR "status" IS NULL);'
    assert res_not_has.parameters == ["%act%"]


def test_sqlite_lower_create_with_null(sqlite_schema: SourceSchema):
    bound = bind_altrql(parse_altrql('CREATE users ( email: "test@example.com", metadata: NULL );'), sqlite_schema)
    lowerer = SQLiteLowerer()
    res = lowerer.lower(bound)
    assert res.query == 'INSERT INTO "users" ("email", "metadata") VALUES (?, NULL) RETURNING *;'
    assert res.parameters == ["test@example.com"]


def test_sqlite_lower_update_with_null(sqlite_schema: SourceSchema):
    bound = bind_altrql(parse_altrql('UPDATE users ( metadata: NULL ) WHERE { id = 1 };'), sqlite_schema)
    lowerer = SQLiteLowerer()
    res = lowerer.lower(bound)
    assert res.query == 'UPDATE "users" SET "metadata" = NULL WHERE "id" = ? RETURNING *;'
    assert res.parameters == [1]


def test_sqlite_lower_delete_with_null(sqlite_schema: SourceSchema):
    bound = bind_altrql(parse_altrql('DELETE users WHERE { metadata = NULL };'), sqlite_schema)
    lowerer = SQLiteLowerer()
    res = lowerer.lower(bound)
    assert res.query == 'DELETE FROM "users" WHERE "metadata" IS NULL RETURNING *;'
    assert res.parameters == []
