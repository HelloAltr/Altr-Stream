"""Unit tests for AltrQL PostgreSQL query lowerer."""

import datetime
import pytest

from altr_stream.domain.schema import EntitySchema, FieldSchema, SourceSchema, StandardDataType
from altr_stream.query_engine.binding import bind_altrql
from altr_stream.query_engine.domain.ast import FieldPath
from altr_stream.query_engine.domain.bound_ast import (
    BoundAltrQueryIR,
    BoundEntity,
    BoundFieldPath,
    BoundRankingClause,
    BoundSortClause,
    LogicalTypeCategory,
)
from altr_stream.query_engine.domain.operators import RankingDirection, SortDirection
from altr_stream.query_engine.lowering.postgres import PostgreSQLLowerer
from altr_stream.query_engine.parser import parse_altrql


@pytest.fixture
def test_schema() -> SourceSchema:
    """Standard sample schema for lowering tests."""
    return SourceSchema(
        source_id="src_pg_01",
        source_name="Production Postgres DB",
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
                    FieldSchema(name="created_at", data_type=StandardDataType.TIMESTAMP, native_data_type="timestamp"),
                    FieldSchema(name="signup_date", data_type=StandardDataType.DATE, native_data_type="date"),
                ],
            )
        ],
    )


def test_lower_basic_query(test_schema: SourceSchema):
    ir = parse_altrql("GET users;")
    bound_ir = bind_altrql(ir, test_schema)
    lowerer = PostgreSQLLowerer()
    pq = lowerer.lower(bound_ir)

    assert pq.dialect == "postgresql"
    assert pq.query == 'SELECT * FROM "public"."users" ORDER BY "id" ASC;'
    assert pq.parameters == []
    assert pq.source_id == "src_pg_01"


def test_lower_projections_with_aliases(test_schema: SourceSchema):
    ir = parse_altrql("GET users (id, username AS name, age);")
    bound_ir = bind_altrql(ir, test_schema)
    lowerer = PostgreSQLLowerer()
    pq = lowerer.lower(bound_ir)

    assert pq.query == 'SELECT "id", "username" AS "name", "age" FROM "public"."users" ORDER BY "id" ASC;'
    assert pq.parameters == []


def test_lower_numeric_comparisons(test_schema: SourceSchema):
    ir = parse_altrql("GET users WHERE { age >= 18, score < 95.5 };")
    bound_ir = bind_altrql(ir, test_schema)
    lowerer = PostgreSQLLowerer()
    pq = lowerer.lower(bound_ir)

    assert pq.query == 'SELECT * FROM "public"."users" WHERE ("age" >= $1 AND "score" < $2) ORDER BY "id" ASC;'
    assert pq.parameters == [18, 95.5]


def test_lower_boolean_comparisons(test_schema: SourceSchema):
    ir = parse_altrql("GET users WHERE { is_active = TRUE };")
    bound_ir = bind_altrql(ir, test_schema)
    lowerer = PostgreSQLLowerer()
    pq = lowerer.lower(bound_ir)

    assert pq.query == 'SELECT * FROM "public"."users" WHERE "is_active" = $1 ORDER BY "id" ASC;'
    assert pq.parameters == [True]


def test_lower_string_operators(test_schema: SourceSchema):
    ir = parse_altrql('GET users WHERE { username STARTS "San", email ENDS "@test.com", username HAS "tho", username NOT HAS "admin" };')
    bound_ir = bind_altrql(ir, test_schema)
    lowerer = PostgreSQLLowerer()
    pq = lowerer.lower(bound_ir)

    assert pq.query == 'SELECT * FROM "public"."users" WHERE ((("username" LIKE $1 AND "email" LIKE $2) AND "username" LIKE $3) AND ("username" NOT LIKE $4 OR "username" IS NULL)) ORDER BY "id" ASC;'
    assert pq.parameters == ["San%", "%@test.com", "%tho%", "%admin%"]


def test_lower_temporal_keywords(test_schema: SourceSchema):
    ir = parse_altrql("GET users WHERE { created_at >= TODAY, created_at <= NOW };")
    bound_ir = bind_altrql(ir, test_schema)
    lowerer = PostgreSQLLowerer()
    pq = lowerer.lower(bound_ir)

    assert pq.query == 'SELECT * FROM "public"."users" WHERE ("created_at" >= CURRENT_DATE AND "created_at" <= CURRENT_TIMESTAMP) ORDER BY "id" ASC;'
    assert pq.parameters == []


def test_lower_explicit_iso_date(test_schema: SourceSchema):
    ir = parse_altrql("GET users WHERE { created_at >= @2026-01-01 };")
    bound_ir = bind_altrql(ir, test_schema)
    lowerer = PostgreSQLLowerer()
    pq = lowerer.lower(bound_ir)

    assert pq.query == 'SELECT * FROM "public"."users" WHERE "created_at" >= $1 ORDER BY "id" ASC;'
    assert pq.parameters == [datetime.date(2026, 1, 1)]
    assert isinstance(pq.parameters[0], datetime.date)


def test_lower_timestamp_field_date_only_equality(test_schema: SourceSchema):
    ir = parse_altrql("GET users WHERE { created_at = @2026-09-06 };")
    bound_ir = bind_altrql(ir, test_schema)
    lowerer = PostgreSQLLowerer()
    pq = lowerer.lower(bound_ir)

    assert pq.query == 'SELECT * FROM "public"."users" WHERE ("created_at" >= $1 AND "created_at" < $2) ORDER BY "id" ASC;'
    assert pq.parameters == [
        datetime.datetime(2026, 9, 6, 0, 0, 0),
        datetime.datetime(2026, 9, 7, 0, 0, 0),
    ]
    assert isinstance(pq.parameters[0], datetime.datetime)
    assert isinstance(pq.parameters[1], datetime.datetime)


def test_lower_date_field_date_only_equality(test_schema: SourceSchema):
    ir = parse_altrql("GET users WHERE { signup_date = @2026-09-06 };")
    bound_ir = bind_altrql(ir, test_schema)
    lowerer = PostgreSQLLowerer()
    pq = lowerer.lower(bound_ir)

    assert pq.query == 'SELECT * FROM "public"."users" WHERE "signup_date" = $1 ORDER BY "id" ASC;'
    assert pq.parameters == [datetime.date(2026, 9, 6)]
    assert isinstance(pq.parameters[0], datetime.date)


def test_lower_multiple_temporal_parameters(test_schema: SourceSchema):
    ir = parse_altrql("GET users WHERE { created_at >= @2026-09-01, created_at <= @2026-09-30 };")
    bound_ir = bind_altrql(ir, test_schema)
    lowerer = PostgreSQLLowerer()
    pq = lowerer.lower(bound_ir)

    assert pq.query == 'SELECT * FROM "public"."users" WHERE ("created_at" >= $1 AND "created_at" <= $2) ORDER BY "id" ASC;'
    assert pq.parameters == [datetime.date(2026, 9, 1), datetime.date(2026, 9, 30)]
    assert isinstance(pq.parameters[0], datetime.date)
    assert isinstance(pq.parameters[1], datetime.date)


def test_lower_nested_logical_expression_with_temporals(test_schema: SourceSchema):
    query = """
    GET users WHERE {
        NOT {
            is_active = FALSE,
            created_at = @2026-09-06
        } OR {
            is_active = TRUE,
            created_at = @2026-09-08
        }
    };
    """
    ir = parse_altrql(query)
    bound_ir = bind_altrql(ir, test_schema)
    lowerer = PostgreSQLLowerer()
    pq = lowerer.lower(bound_ir)

    assert 'WHERE (NOT ("is_active" = $1 AND ("created_at" >= $2 AND "created_at" < $3)) OR ("is_active" = $4 AND ("created_at" >= $5 AND "created_at" < $6))) ORDER BY "id" ASC;' in pq.query
    assert pq.parameters == [
        False,
        datetime.datetime(2026, 9, 6, 0, 0),
        datetime.datetime(2026, 9, 7, 0, 0),
        True,
        datetime.datetime(2026, 9, 8, 0, 0),
        datetime.datetime(2026, 9, 9, 0, 0),
    ]
    assert isinstance(pq.parameters[1], datetime.datetime)
    assert isinstance(pq.parameters[2], datetime.datetime)
    assert isinstance(pq.parameters[4], datetime.datetime)
    assert isinstance(pq.parameters[5], datetime.datetime)


def test_lower_temporal_range(test_schema: SourceSchema):
    ir = parse_altrql("GET users WHERE { created_at = @2026-01-01..@2026-12-31 };")
    bound_ir = bind_altrql(ir, test_schema)
    lowerer = PostgreSQLLowerer()
    pq = lowerer.lower(bound_ir)

    assert pq.query == 'SELECT * FROM "public"."users" WHERE "created_at" BETWEEN $1 AND $2 ORDER BY "id" ASC;'
    assert pq.parameters == [datetime.date(2026, 1, 1), datetime.date(2026, 12, 31)]


def test_lower_temporal_value_set(test_schema: SourceSchema):
    ir = parse_altrql("GET users WHERE { created_at = {@2026-01-01, @2026-06-01} };")
    bound_ir = bind_altrql(ir, test_schema)
    lowerer = PostgreSQLLowerer()
    pq = lowerer.lower(bound_ir)

    assert pq.query == 'SELECT * FROM "public"."users" WHERE (("created_at" >= $1 AND "created_at" < $2) OR ("created_at" >= $3 AND "created_at" < $4)) ORDER BY "id" ASC;'
    assert pq.parameters == [
        datetime.datetime(2026, 1, 1, 0, 0),
        datetime.datetime(2026, 1, 2, 0, 0),
        datetime.datetime(2026, 6, 1, 0, 0),
        datetime.datetime(2026, 6, 2, 0, 0),
    ]


def test_lower_mutations_with_temporal_literals(test_schema: SourceSchema):
    # UPDATE
    ir_update = parse_altrql("UPDATE users (is_active: FALSE) WHERE { created_at = @2026-09-06 };")
    bound_update = bind_altrql(ir_update, test_schema)
    pq_update = PostgreSQLLowerer().lower(bound_update)
    assert pq_update.query == 'UPDATE "public"."users" SET "is_active" = $1 WHERE ("created_at" >= $2 AND "created_at" < $3) RETURNING *;'
    assert pq_update.parameters == [False, datetime.datetime(2026, 9, 6, 0, 0), datetime.datetime(2026, 9, 7, 0, 0)]

    # DELETE
    ir_delete = parse_altrql("DELETE users WHERE { created_at < @2026-09-01 };")
    bound_delete = bind_altrql(ir_delete, test_schema)
    pq_delete = PostgreSQLLowerer().lower(bound_delete)
    assert pq_delete.query == 'DELETE FROM "public"."users" WHERE "created_at" < $1 RETURNING *;'
    assert pq_delete.parameters == [datetime.date(2026, 9, 1)]


def test_lower_range(test_schema: SourceSchema):
    ir = parse_altrql("GET users WHERE { age = 20..30 };")
    bound_ir = bind_altrql(ir, test_schema)
    lowerer = PostgreSQLLowerer()
    pq = lowerer.lower(bound_ir)

    assert pq.query == 'SELECT * FROM "public"."users" WHERE "age" BETWEEN $1 AND $2 ORDER BY "id" ASC;'
    assert pq.parameters == [20, 30]


def test_lower_simple_value_set(test_schema: SourceSchema):
    ir = parse_altrql("GET users WHERE { age = {18, 21, 25} };")
    bound_ir = bind_altrql(ir, test_schema)
    lowerer = PostgreSQLLowerer()
    pq = lowerer.lower(bound_ir)

    assert pq.query == 'SELECT * FROM "public"."users" WHERE "age" IN ($1, $2, $3) ORDER BY "id" ASC;'
    assert pq.parameters == [18, 21, 25]


def test_lower_complex_value_set(test_schema: SourceSchema):
    ir = parse_altrql("GET users WHERE { age = { 18..25, >= 50 } };")
    bound_ir = bind_altrql(ir, test_schema)
    lowerer = PostgreSQLLowerer()
    pq = lowerer.lower(bound_ir)

    assert pq.query == 'SELECT * FROM "public"."users" WHERE ("age" BETWEEN $1 AND $2 OR "age" >= $3) ORDER BY "id" ASC;'
    assert pq.parameters == [18, 25, 50]


def test_lower_compound_and_constraint(test_schema: SourceSchema):
    ir = parse_altrql("GET users WHERE { age = { >= 18 & <= 60 } };")
    bound_ir = bind_altrql(ir, test_schema)
    lowerer = PostgreSQLLowerer()
    pq = lowerer.lower(bound_ir)

    assert pq.query == 'SELECT * FROM "public"."users" WHERE ("age" >= $1 AND "age" <= $2) ORDER BY "id" ASC;'
    assert pq.parameters == [18, 60]


def test_lower_sort_clause(test_schema: SourceSchema):
    ir = parse_altrql("GET users SORT { age DESC, username ASC };")
    bound_ir = bind_altrql(ir, test_schema)
    lowerer = PostgreSQLLowerer()
    pq = lowerer.lower(bound_ir)

    assert pq.query == 'SELECT * FROM "public"."users" ORDER BY "age" DESC, "username" ASC;'


def test_lower_ranking_clause(test_schema: SourceSchema):
    ir = parse_altrql("GET users TOP 10 BY score;")
    bound_ir = bind_altrql(ir, test_schema)
    lowerer = PostgreSQLLowerer()
    pq = lowerer.lower(bound_ir)

    assert pq.query == 'SELECT * FROM "public"."users" ORDER BY "score" DESC LIMIT 10;'


def test_lower_ranking_and_sort_precedence(test_schema: SourceSchema):
    # Construct BoundAltrQueryIR directly to verify lowering precedence when both ranking and sort are present
    score_field = BoundFieldPath(
        path=FieldPath(segments=["score"]),
        data_type=StandardDataType.FLOAT,
        logical_category=LogicalTypeCategory.NUMERIC,
        native_type="float8",
    )
    created_at_field = BoundFieldPath(
        path=FieldPath(segments=["created_at"]),
        data_type=StandardDataType.TIMESTAMP,
        logical_category=LogicalTypeCategory.TEMPORAL,
        native_type="timestamp",
    )

    bound_ir = BoundAltrQueryIR(
        entity=BoundEntity(name="users", namespace="public"),
        ranking=BoundRankingClause(direction=RankingDirection.TOP, count=5, field=score_field),
        sort=[BoundSortClause(field=created_at_field, direction=SortDirection.ASC)],
        source_id="src_pg_01",
        source_name="Production Postgres DB",
    )

    lowerer = PostgreSQLLowerer()
    pq = lowerer.lower(bound_ir)

    assert pq.query == 'SELECT * FROM "public"."users" ORDER BY "score" DESC, "created_at" ASC LIMIT 5;'


def test_lower_ranking_and_offset(test_schema: SourceSchema):
    ir = parse_altrql("GET users BOTTOM 5 BY age OFFSET 10;")
    bound_ir = bind_altrql(ir, test_schema)
    lowerer = PostgreSQLLowerer()
    pq = lowerer.lower(bound_ir)

    assert pq.query == 'SELECT * FROM "public"."users" ORDER BY "age" ASC LIMIT 5 OFFSET 10;'


def test_lower_immutability(test_schema: SourceSchema):
    ir = parse_altrql("GET users WHERE { age >= 18 };")
    bound_ir = bind_altrql(ir, test_schema)
    before_dump = bound_ir.to_dict()

    lowerer = PostgreSQLLowerer()
    pq = lowerer.lower(bound_ir)

    assert pq is not None
    assert bound_ir.to_dict() == before_dump
