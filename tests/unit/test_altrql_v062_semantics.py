"""Comprehensive unit tests for AltrQL v0.6.2-alpha query semantics and deterministic ordering.

Covers:
1. Combined WHERE predicates composing with AND (commas, newlines).
2. HAS {v1, v2, ...} set-membership semantics (exact match, NOT substring).
3. Single string literal HAS "sub" retaining substring match.
4. Inclusive range semantics ({1, 2, 5..7} matches 1, 2, 5, 6, 7).
5. Nested JSON field access (metadata.department, NULL parents, missing keys).
6. SORT block parsing (ASC/DESC, multi-field, comma/newline separated).
7. SORT + LIMIT / OFFSET parser & IR.
8. Deterministic default ordering by logical primary key (entity.primary_key ASC).
9. Explicit SORT strictly overriding default primary key ordering.
10. Dialect-specific lowering in PostgreSQL and SQLite.
"""

import pytest

from altr_stream.domain.schema import (
    EntitySchema,
    FieldSchema,
    SourceSchema,
    StandardDataType,
)
from altr_stream.query_engine.binding.binder import bind_altrql
from altr_stream.query_engine.domain.ast import (
    FieldExpression,
    FieldPath,
    IntegerLiteral,
    LogicalExpression,
    LogicalOperator,
    Range,
    StringLiteral,
    ValueSet,
)
from altr_stream.query_engine.domain.bound_ast import (
    BoundFieldExpression,
    BoundLogicalExpression,
)
from altr_stream.query_engine.domain.operators import (
    ComparisonOperator,
    SortDirection,
    StringOperator,
)
from altr_stream.query_engine.lowering.postgres import PostgreSQLLowerer
from altr_stream.query_engine.lowering.sqlite import SQLiteLowerer
from altr_stream.query_engine.domain.errors import AltrQueryParseError
from altr_stream.query_engine.parser.parser import parse_altrql


@pytest.fixture
def sample_schema() -> SourceSchema:
    return SourceSchema(
        source_id="src_v062_test",
        source_name="Test Source v0.6.2",
        entities=[
            EntitySchema(
                name="users",
                namespace="public",
                fields=[
                    FieldSchema(name="id", data_type=StandardDataType.INTEGER, native_data_type="int4", is_primary_key=True),
                    FieldSchema(name="email", data_type=StandardDataType.STRING, native_data_type="varchar"),
                    FieldSchema(name="username", data_type=StandardDataType.STRING, native_data_type="varchar"),
                    FieldSchema(name="role", data_type=StandardDataType.STRING, native_data_type="varchar"),
                    FieldSchema(name="is_active", data_type=StandardDataType.BOOLEAN, native_data_type="bool"),
                    FieldSchema(name="metadata", data_type=StandardDataType.JSON, native_data_type="jsonb"),
                    FieldSchema(name="score", data_type=StandardDataType.FLOAT, native_data_type="float8"),
                ],
                primary_key=["id"],
            ),
            EntitySchema(
                name="orders",
                namespace="public",
                fields=[
                    FieldSchema(name="tenant_id", data_type=StandardDataType.STRING, native_data_type="varchar", is_primary_key=True),
                    FieldSchema(name="order_no", data_type=StandardDataType.INTEGER, native_data_type="int4", is_primary_key=True),
                    FieldSchema(name="total", data_type=StandardDataType.FLOAT, native_data_type="float8"),
                ],
                primary_key=["tenant_id", "order_no"],
            ),
            EntitySchema(
                name="logs",
                namespace="public",
                fields=[
                    FieldSchema(name="message", data_type=StandardDataType.STRING, native_data_type="varchar"),
                    FieldSchema(name="level", data_type=StandardDataType.STRING, native_data_type="varchar"),
                ],
                primary_key=[],
            ),
        ],
    )


# ---------------------------------------------------------------------------
# 1. Combined WHERE Predicates + HAS
# ---------------------------------------------------------------------------


def test_combined_where_predicates_and_has_parsing_and_binding(sample_schema: SourceSchema):
    query = """
    GET users WHERE {
        email HAS {"edith", "group_a1"}
        is_active = TRUE,
        metadata = NULL
    };
    """
    ir = parse_altrql(query)
    assert ir.where is not None
    # Conjoined with AND
    assert isinstance(ir.where, LogicalExpression)
    assert ir.where.operator == LogicalOperator.AND

    bound = bind_altrql(ir, sample_schema)
    assert bound.where is not None
    assert isinstance(bound.where, BoundLogicalExpression)

    # Postgres lowering
    pg_lowerer = PostgreSQLLowerer()
    pg_query = pg_lowerer.lower(bound)
    assert 'WHERE (("email" LIKE $1 OR "email" LIKE $2) AND ("is_active" = $3 AND "metadata" IS NULL))' in pg_query.query
    assert pg_query.parameters == ["%edith%", "%group_a1%", True]
    assert pg_query.query.endswith('ORDER BY "id" ASC;')

    # SQLite lowering
    sqlite_lowerer = SQLiteLowerer()
    sq_query = sqlite_lowerer.lower(bound)
    assert 'WHERE (("email" LIKE ? OR "email" LIKE ?) AND ("is_active" = ? AND "metadata" IS NULL))' in sq_query.query
    assert sq_query.parameters == ["%edith%", "%group_a1%", 1]
    assert sq_query.query.endswith('ORDER BY "id" ASC;')


def test_has_single_and_valueset_substring_semantics(sample_schema: SourceSchema):
    # 1. HAS single literal: substring match
    ir_single = parse_altrql('GET users WHERE { email HAS "alice" };')
    bound_single = bind_altrql(ir_single, sample_schema)

    pg_single = PostgreSQLLowerer().lower(bound_single)
    assert 'WHERE "email" LIKE $1' in pg_single.query
    assert pg_single.parameters == ["%alice%"]

    sq_single = SQLiteLowerer().lower(bound_single)
    assert 'WHERE "email" LIKE ?' in sq_single.query
    assert sq_single.parameters == ["%alice%"]

    # 2. HAS {"alice"}: behaves identically to HAS "alice"
    ir_single_set = parse_altrql('GET users WHERE { email HAS {"alice"} };')
    bound_single_set = bind_altrql(ir_single_set, sample_schema)

    pg_single_set = PostgreSQLLowerer().lower(bound_single_set)
    assert 'WHERE "email" LIKE $1' in pg_single_set.query
    assert pg_single_set.parameters == ["%alice%"]

    sq_single_set = SQLiteLowerer().lower(bound_single_set)
    assert 'WHERE "email" LIKE ?' in sq_single_set.query
    assert sq_single_set.parameters == ["%alice%"]

    # 3. HAS {"alice", "carol"}: substring match against any supplied value
    ir_multi_set = parse_altrql('GET users WHERE { email HAS {"alice", "carol"} };')
    bound_multi_set = bind_altrql(ir_multi_set, sample_schema)

    pg_multi_set = PostgreSQLLowerer().lower(bound_multi_set)
    assert 'WHERE ("email" LIKE $1 OR "email" LIKE $2)' in pg_multi_set.query
    assert pg_multi_set.parameters == ["%alice%", "%carol%"]

    sq_multi_set = SQLiteLowerer().lower(bound_multi_set)
    assert 'WHERE ("email" LIKE ? OR "email" LIKE ?)' in sq_multi_set.query
    assert sq_multi_set.parameters == ["%alice%", "%carol%"]

    # 4. HAS {"alice@example.com"}: still performs substring matching
    ir_full = parse_altrql('GET users WHERE { email HAS {"alice@example.com"} };')
    bound_full = bind_altrql(ir_full, sample_schema)
    pg_full = PostgreSQLLowerer().lower(bound_full)
    assert 'WHERE "email" LIKE $1' in pg_full.query
    assert pg_full.parameters == ["%alice@example.com%"]


def test_exact_set_membership_with_equals(sample_schema: SourceSchema):
    # = with ValueSet remains the mechanism for exact set membership
    ir = parse_altrql('GET users WHERE { email = {"alice@example.com", "carol@example.com"} };')
    bound = bind_altrql(ir, sample_schema)

    pg = PostgreSQLLowerer().lower(bound)
    assert 'WHERE "email" IN ($1, $2)' in pg.query
    assert pg.parameters == ["alice@example.com", "carol@example.com"]

    sq = SQLiteLowerer().lower(bound)
    assert 'WHERE "email" IN (?, ?)' in sq.query
    assert sq.parameters == ["alice@example.com", "carol@example.com"]


def test_not_has_valueset_substring_negation(sample_schema: SourceSchema):
    # NOT HAS {"admin", "superadmin"}: matches records containing NONE of the substrings
    ir = parse_altrql('GET users WHERE { role NOT HAS {"admin", "superadmin"} };')
    bound = bind_altrql(ir, sample_schema)

    pg = PostgreSQLLowerer().lower(bound)
    assert 'WHERE (("role" NOT LIKE $1 AND "role" NOT LIKE $2) OR "role" IS NULL)' in pg.query
    assert pg.parameters == ["%admin%", "%superadmin%"]

    sq = SQLiteLowerer().lower(bound)
    assert 'WHERE (("role" NOT LIKE ? AND "role" NOT LIKE ?) OR "role" IS NULL)' in sq.query
    assert sq.parameters == ["%admin%", "%superadmin%"]

    # NOT HAS {"admin"}: behaves identically to single NOT HAS "admin"
    ir_single = parse_altrql('GET users WHERE { role NOT HAS {"admin"} };')
    bound_single = bind_altrql(ir_single, sample_schema)
    pg_single = PostgreSQLLowerer().lower(bound_single)
    assert 'WHERE ("role" NOT LIKE $1 OR "role" IS NULL)' in pg_single.query
    assert pg_single.parameters == ["%admin%"]

    sq_single = SQLiteLowerer().lower(bound_single)
    assert 'WHERE ("role" NOT LIKE ? OR "role" IS NULL)' in sq_single.query
    assert sq_single.parameters == ["%admin%"]


# ---------------------------------------------------------------------------
# 2. Inclusive Range Semantics
# ---------------------------------------------------------------------------


def test_inclusive_range_semantics(sample_schema: SourceSchema):
    query = "GET users WHERE { id = {1, 2, 5..7} };"
    ir = parse_altrql(query)
    bound = bind_altrql(ir, sample_schema)

    pg = PostgreSQLLowerer().lower(bound)
    # Range is rendered as BETWEEN (which is inclusive in SQL)
    assert 'WHERE ("id" = $1 OR "id" = $2 OR "id" BETWEEN $3 AND $4)' in pg.query
    assert pg.parameters == [1, 2, 5, 7]

    sq = SQLiteLowerer().lower(bound)
    assert 'WHERE ("id" IN (?, ?) OR "id" BETWEEN ? AND ?)' in sq.query
    assert sq.parameters == [1, 2, 5, 7]


def test_direct_inclusive_range(sample_schema: SourceSchema):
    query = "GET users WHERE { id = 5..7 };"
    ir = parse_altrql(query)
    bound = bind_altrql(ir, sample_schema)

    pg = PostgreSQLLowerer().lower(bound)
    assert 'WHERE "id" BETWEEN $1 AND $2' in pg.query
    assert pg.parameters == [5, 7]

    sq = SQLiteLowerer().lower(bound)
    assert 'WHERE "id" BETWEEN ? AND ?' in sq.query
    assert sq.parameters == [5, 7]


# ---------------------------------------------------------------------------
# 3. Nested JSON Field Access
# ---------------------------------------------------------------------------


def test_nested_json_field_access(sample_schema: SourceSchema):
    query = 'GET users WHERE { metadata.department = "Engineering" };'
    ir = parse_altrql(query)
    assert isinstance(ir.where, FieldExpression)
    assert ir.where.field.is_nested is True
    assert ir.where.field.segments == ["metadata", "department"]

    bound = bind_altrql(ir, sample_schema)
    assert bound.where.field.path.segments == ["metadata", "department"]  # type: ignore[union-attr]

    # Postgres uses ->> for nested JSON extraction
    pg = PostgreSQLLowerer().lower(bound)
    assert 'WHERE "metadata"->>\'department\' = $1' in pg.query
    assert pg.parameters == ["Engineering"]

    # SQLite uses json_extract
    sq = SQLiteLowerer().lower(bound)
    assert "WHERE json_extract(\"metadata\", '$.department') = ?" in sq.query
    assert sq.parameters == ["Engineering"]


def test_nested_json_projection_and_deep_path(sample_schema: SourceSchema):
    query = 'GET users (id, metadata.config.theme AS theme) WHERE { metadata.config.debug = "true" };'
    ir = parse_altrql(query)
    bound = bind_altrql(ir, sample_schema)

    pg = PostgreSQLLowerer().lower(bound)
    assert 'SELECT "id", "metadata"->\'config\'->>\'theme\' AS "theme"' in pg.query
    assert 'WHERE "metadata"->\'config\'->>\'debug\' = $1' in pg.query

    sq = SQLiteLowerer().lower(bound)
    assert 'SELECT "id", json_extract("metadata", \'$.config.theme\') AS "theme"' in sq.query
    assert "WHERE json_extract(\"metadata\", '$.config.debug') = ?" in sq.query


# ---------------------------------------------------------------------------
# 4. SORT Parsing, Multi-Field, and Directions
# ---------------------------------------------------------------------------


def test_sort_block_parsing_and_lowering(sample_schema: SourceSchema):
    query_asc = "GET users SORT { id ASC } LIMIT 3;"
    ir_asc = parse_altrql(query_asc)
    assert len(ir_asc.sort) == 1
    assert ir_asc.sort[0].field.leaf == "id"
    assert ir_asc.sort[0].direction == SortDirection.ASC
    assert ir_asc.limit == 3

    bound_asc = bind_altrql(ir_asc, sample_schema)
    pg_asc = PostgreSQLLowerer().lower(bound_asc)
    assert 'ORDER BY "id" ASC LIMIT 3;' in pg_asc.query

    query_desc = "GET users SORT { id DESC } LIMIT 3;"
    ir_desc = parse_altrql(query_desc)
    bound_desc = bind_altrql(ir_desc, sample_schema)
    pg_desc = PostgreSQLLowerer().lower(bound_desc)
    assert 'ORDER BY "id" DESC LIMIT 3;' in pg_desc.query


def test_sort_multi_field_with_commas_and_newlines(sample_schema: SourceSchema):
    query = """
    GET users SORT {
        score DESC,
        username ASC
    } LIMIT 10 OFFSET 20;
    """
    ir = parse_altrql(query)
    assert len(ir.sort) == 2
    assert ir.sort[0].field.leaf == "score"
    assert ir.sort[0].direction == SortDirection.DESC
    assert ir.sort[1].field.leaf == "username"
    assert ir.sort[1].direction == SortDirection.ASC
    assert ir.limit == 10
    assert ir.offset == 20

    bound = bind_altrql(ir, sample_schema)
    pg = PostgreSQLLowerer().lower(bound)
    assert 'ORDER BY "score" DESC, "username" ASC LIMIT 10 OFFSET 20;' in pg.query

    sq = SQLiteLowerer().lower(bound)
    assert 'ORDER BY "score" DESC, "username" ASC LIMIT 10 OFFSET 20;' in sq.query


def test_sort_syntax_error_handling():
    # Missing closing brace
    with pytest.raises(AltrQueryParseError):
        parse_altrql("GET users SORT { id ASC;")

    # Invalid direction
    with pytest.raises(AltrQueryParseError):
        parse_altrql("GET users SORT { id UP };")

    # Mutation with LIMIT should fail parsing or validation
    with pytest.raises(AltrQueryParseError):
        parse_altrql("UPDATE users (is_active: FALSE) LIMIT 5;")


# ---------------------------------------------------------------------------
# 5. Deterministic Default Primary Key Ordering vs Explicit SORT
# ---------------------------------------------------------------------------


def test_deterministic_default_ordering_single_pk(sample_schema: SourceSchema):
    query = "GET users;"
    ir = parse_altrql(query)
    bound = bind_altrql(ir, sample_schema)

    pg = PostgreSQLLowerer().lower(bound)
    assert pg.query == 'SELECT * FROM "public"."users" ORDER BY "id" ASC;'

    sq = SQLiteLowerer().lower(bound)
    assert sq.query == 'SELECT * FROM "users" ORDER BY "id" ASC;'


def test_deterministic_default_ordering_composite_pk(sample_schema: SourceSchema):
    query = "GET orders;"
    ir = parse_altrql(query)
    bound = bind_altrql(ir, sample_schema)

    pg = PostgreSQLLowerer().lower(bound)
    assert pg.query == 'SELECT * FROM "public"."orders" ORDER BY "tenant_id" ASC, "order_no" ASC;'

    sq = SQLiteLowerer().lower(bound)
    assert sq.query == 'SELECT * FROM "orders" ORDER BY "tenant_id" ASC, "order_no" ASC;'


def test_default_ordering_with_limit_and_offset(sample_schema: SourceSchema):
    query = "GET users LIMIT 3 OFFSET 5;"
    ir = parse_altrql(query)
    bound = bind_altrql(ir, sample_schema)

    pg = PostgreSQLLowerer().lower(bound)
    assert pg.query == 'SELECT * FROM "public"."users" ORDER BY "id" ASC LIMIT 3 OFFSET 5;'

    sq = SQLiteLowerer().lower(bound)
    assert sq.query == 'SELECT * FROM "users" ORDER BY "id" ASC LIMIT 3 OFFSET 5;'


def test_explicit_sort_strictly_overrides_default_pk(sample_schema: SourceSchema):
    query = "GET users SORT { id DESC } LIMIT 3;"
    ir = parse_altrql(query)
    bound = bind_altrql(ir, sample_schema)

    pg = PostgreSQLLowerer().lower(bound)
    # Must ONLY sort by id DESC, not id ASC
    assert pg.query == 'SELECT * FROM "public"."users" ORDER BY "id" DESC LIMIT 3;'

    sq = SQLiteLowerer().lower(bound)
    assert sq.query == 'SELECT * FROM "users" ORDER BY "id" DESC LIMIT 3;'


def test_no_pk_entity_has_no_default_order_by(sample_schema: SourceSchema):
    query = "GET logs;"
    ir = parse_altrql(query)
    bound = bind_altrql(ir, sample_schema)

    pg = PostgreSQLLowerer().lower(bound)
    assert pg.query == 'SELECT * FROM "public"."logs";'

    sq = SQLiteLowerer().lower(bound)
    assert sq.query == 'SELECT * FROM "logs";'
