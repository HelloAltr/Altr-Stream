"""Unit tests for MySQL dialect physical query lowering."""

import pytest

from altr_stream.domain.schema import (
    EntitySchema,
    FieldSchema,
    SourceSchema,
    StandardDataType,
)
from altr_stream.query_engine.binding.binder import bind_altrql
from altr_stream.query_engine.domain.physical_query import PhysicalQueryBatch
from altr_stream.query_engine.lowering.mysql import MySQLLowerer
from altr_stream.query_engine.parser import parse_altrql


@pytest.fixture
def mysql_schema() -> SourceSchema:
    return SourceSchema(
        source_id="src_mysql_test",
        source_name="MySQL Test Source",
        version="1.0.0",
        entities=[
            EntitySchema(
                name="users",
                namespace="default",
                entity_type="TABLE",
                fields=[
                    FieldSchema(name="id", data_type=StandardDataType.INTEGER, native_data_type="int", nullable=False, is_primary_key=True),
                    FieldSchema(name="email", data_type=StandardDataType.STRING, native_data_type="varchar(255)", nullable=False),
                    FieldSchema(name="status", data_type=StandardDataType.STRING, native_data_type="varchar(50)", nullable=True),
                    FieldSchema(name="age", data_type=StandardDataType.INTEGER, native_data_type="int", nullable=True),
                    FieldSchema(name="is_active", data_type=StandardDataType.BOOLEAN, native_data_type="tinyint(1)", nullable=False),
                    FieldSchema(name="metadata", data_type=StandardDataType.JSON, native_data_type="json", nullable=True),
                    FieldSchema(name="created_at", data_type=StandardDataType.TIMESTAMP, native_data_type="datetime", nullable=False),
                ],
                primary_key=["id"],
            ),
            EntitySchema(
                name="orders",
                namespace="default",
                entity_type="TABLE",
                fields=[
                    FieldSchema(name="tenant_id", data_type=StandardDataType.STRING, native_data_type="varchar(50)", nullable=False, is_primary_key=True),
                    FieldSchema(name="order_no", data_type=StandardDataType.INTEGER, native_data_type="int", nullable=False, is_primary_key=True),
                    FieldSchema(name="total", data_type=StandardDataType.DECIMAL, native_data_type="decimal(10,2)", nullable=False),
                ],
                primary_key=["tenant_id", "order_no"],
            ),
        ],
    )


# ---------------------------------------------------------------------------
# 1. Simple Equality & Projections
# ---------------------------------------------------------------------------

def test_mysql_lower_read_simple(mysql_schema: SourceSchema):
    bound = bind_altrql(parse_altrql("GET users;"), mysql_schema)
    lowerer = MySQLLowerer()
    res = lowerer.lower(bound)
    assert res.dialect == "mysql"
    assert res.query == "SELECT * FROM `users` ORDER BY `id` ASC;"
    assert res.parameters == []


def test_mysql_lower_read_with_filter_and_projection(mysql_schema: SourceSchema):
    bound = bind_altrql(parse_altrql('GET users (id, email AS user_email) WHERE { status = "ACTIVE" };'), mysql_schema)
    lowerer = MySQLLowerer()
    res = lowerer.lower(bound)
    assert res.query == "SELECT `id`, `email` AS `user_email` FROM `users` WHERE `status` = %s ORDER BY `id` ASC;"
    assert res.parameters == ["ACTIVE"]


# ---------------------------------------------------------------------------
# 2. ValueSet Equality (Exact Membership)
# ---------------------------------------------------------------------------

def test_mysql_lower_valueset_equality(mysql_schema: SourceSchema):
    bound = bind_altrql(parse_altrql('GET users WHERE { status = {"ACTIVE", "PENDING"} };'), mysql_schema)
    lowerer = MySQLLowerer()
    res = lowerer.lower(bound)
    assert res.query == "SELECT * FROM `users` WHERE `status` IN (%s, %s) ORDER BY `id` ASC;"
    assert res.parameters == ["ACTIVE", "PENDING"]


def test_mysql_lower_valueset_with_range(mysql_schema: SourceSchema):
    bound = bind_altrql(parse_altrql("GET users WHERE { age = {18, 21, 30..40} };"), mysql_schema)
    lowerer = MySQLLowerer()
    res = lowerer.lower(bound)
    assert res.query == "SELECT * FROM `users` WHERE (`age` IN (%s, %s) OR `age` BETWEEN %s AND %s) ORDER BY `id` ASC;"
    assert res.parameters == [18, 21, 30, 40]


# ---------------------------------------------------------------------------
# 3. Inclusive Ranges
# ---------------------------------------------------------------------------

def test_mysql_lower_range_predicate(mysql_schema: SourceSchema):
    bound = bind_altrql(parse_altrql("GET users WHERE { age = {18..65} };"), mysql_schema)
    lowerer = MySQLLowerer()
    res = lowerer.lower(bound)
    assert res.query == "SELECT * FROM `users` WHERE `age` BETWEEN %s AND %s ORDER BY `id` ASC;"
    assert res.parameters == [18, 65]


# ---------------------------------------------------------------------------
# 4. HAS & NOT HAS Substring Semantics
# ---------------------------------------------------------------------------

def test_mysql_lower_string_has_single(mysql_schema: SourceSchema):
    bound = bind_altrql(parse_altrql('GET users WHERE { email HAS "alice" };'), mysql_schema)
    lowerer = MySQLLowerer()
    res = lowerer.lower(bound)
    assert res.query == "SELECT * FROM `users` WHERE `email` LIKE %s ORDER BY `id` ASC;"
    assert res.parameters == ["%alice%"]


def test_mysql_lower_string_has_valueset(mysql_schema: SourceSchema):
    bound = bind_altrql(parse_altrql('GET users WHERE { email HAS {"alice", "bob"} };'), mysql_schema)
    lowerer = MySQLLowerer()
    res = lowerer.lower(bound)
    assert res.query == "SELECT * FROM `users` WHERE (`email` LIKE %s OR `email` LIKE %s) ORDER BY `id` ASC;"
    assert res.parameters == ["%alice%", "%bob%"]


def test_mysql_lower_string_not_has_single(mysql_schema: SourceSchema):
    bound = bind_altrql(parse_altrql('GET users WHERE { email NOT HAS "alice" };'), mysql_schema)
    lowerer = MySQLLowerer()
    res = lowerer.lower(bound)
    assert res.query == "SELECT * FROM `users` WHERE (`email` NOT LIKE %s OR `email` IS NULL) ORDER BY `id` ASC;"
    assert res.parameters == ["%alice%"]


def test_mysql_lower_string_not_has_valueset(mysql_schema: SourceSchema):
    bound = bind_altrql(parse_altrql('GET users WHERE { email NOT HAS {"alice", "bob"} };'), mysql_schema)
    lowerer = MySQLLowerer()
    res = lowerer.lower(bound)
    assert res.query == "SELECT * FROM `users` WHERE ((`email` NOT LIKE %s AND `email` NOT LIKE %s) OR `email` IS NULL) ORDER BY `id` ASC;"
    assert res.parameters == ["%alice%", "%bob%"]


# ---------------------------------------------------------------------------
# 5. NULL Semantics
# ---------------------------------------------------------------------------

def test_mysql_lower_null_predicates(mysql_schema: SourceSchema):
    bound_eq = bind_altrql(parse_altrql("GET users WHERE { metadata = NULL };"), mysql_schema)
    lowerer = MySQLLowerer()
    res_eq = lowerer.lower(bound_eq)
    assert res_eq.query == "SELECT * FROM `users` WHERE `metadata` IS NULL ORDER BY `id` ASC;"
    assert res_eq.parameters == []

    bound_neq = bind_altrql(parse_altrql("GET users WHERE { metadata != NULL };"), mysql_schema)
    res_neq = lowerer.lower(bound_neq)
    assert res_neq.query == "SELECT * FROM `users` WHERE `metadata` IS NOT NULL ORDER BY `id` ASC;"
    assert res_neq.parameters == []


def test_mysql_lower_valueset_with_null(mysql_schema: SourceSchema):
    bound_in = bind_altrql(parse_altrql('GET users WHERE { status = {"ACTIVE", "PENDING", NULL} };'), mysql_schema)
    lowerer = MySQLLowerer()
    res_in = lowerer.lower(bound_in)
    assert res_in.query == "SELECT * FROM `users` WHERE (`status` IS NULL OR `status` IN (%s, %s)) ORDER BY `id` ASC;"
    assert res_in.parameters == ["ACTIVE", "PENDING"]

    bound_nin = bind_altrql(parse_altrql('GET users WHERE { status != {"ACTIVE", "PENDING", NULL} };'), mysql_schema)
    res_nin = lowerer.lower(bound_nin)
    assert res_nin.query == "SELECT * FROM `users` WHERE (`status` IS NOT NULL AND `status` NOT IN (%s, %s)) ORDER BY `id` ASC;"
    assert res_nin.parameters == ["ACTIVE", "PENDING"]


# ---------------------------------------------------------------------------
# 6. Combined Predicates (AND, OR, NOT)
# ---------------------------------------------------------------------------

def test_mysql_lower_combined_predicates(mysql_schema: SourceSchema):
    query = """
    GET users WHERE {
        status = "ACTIVE",
        is_active = TRUE,
        age >= 21
    };
    """
    bound = bind_altrql(parse_altrql(query), mysql_schema)
    lowerer = MySQLLowerer()
    res = lowerer.lower(bound)
    assert res.query == "SELECT * FROM `users` WHERE ((`status` = %s AND `is_active` = %s) AND `age` >= %s) ORDER BY `id` ASC;"
    assert res.parameters == ["ACTIVE", True, 21]


# ---------------------------------------------------------------------------
# 7. Nested JSON Predicates
# ---------------------------------------------------------------------------

def test_mysql_lower_nested_json(mysql_schema: SourceSchema):
    bound = bind_altrql(parse_altrql('GET users WHERE { metadata.department = "Engineering" };'), mysql_schema)
    lowerer = MySQLLowerer()
    res = lowerer.lower(bound)
    assert res.query == "SELECT * FROM `users` WHERE JSON_UNQUOTE(JSON_EXTRACT(`metadata`, '$.department')) = %s ORDER BY `id` ASC;"
    assert res.parameters == ["Engineering"]


# ---------------------------------------------------------------------------
# 8. Sorting & Deterministic Default Ordering
# ---------------------------------------------------------------------------

def test_mysql_lower_explicit_sort_asc_desc(mysql_schema: SourceSchema):
    bound = bind_altrql(parse_altrql("GET users SORT { created_at DESC, id ASC };"), mysql_schema)
    lowerer = MySQLLowerer()
    res = lowerer.lower(bound)
    assert res.query == "SELECT * FROM `users` ORDER BY `created_at` DESC, `id` ASC;"


def test_mysql_lower_composite_pk_default_order(mysql_schema: SourceSchema):
    bound = bind_altrql(parse_altrql("GET orders;"), mysql_schema)
    lowerer = MySQLLowerer()
    res = lowerer.lower(bound)
    assert res.query == "SELECT * FROM `orders` ORDER BY `tenant_id` ASC, `order_no` ASC;"


# ---------------------------------------------------------------------------
# 9. LIMIT & OFFSET
# ---------------------------------------------------------------------------

def test_mysql_lower_limit_offset_and_ranking(mysql_schema: SourceSchema):
    bound = bind_altrql(parse_altrql("GET users TOP 10 BY created_at OFFSET 20;"), mysql_schema)
    lowerer = MySQLLowerer()
    res = lowerer.lower(bound)
    assert res.query == "SELECT * FROM `users` ORDER BY `created_at` DESC LIMIT 10 OFFSET 20;"


# ---------------------------------------------------------------------------
# 10. Date-Only Temporal Equality Rewriting
# ---------------------------------------------------------------------------

def test_mysql_lower_date_only_equality(mysql_schema: SourceSchema):
    bound = bind_altrql(parse_altrql("GET users WHERE { created_at = @2026-09-06 };"), mysql_schema)
    lowerer = MySQLLowerer()
    res = lowerer.lower(bound)
    assert res.query == "SELECT * FROM `users` WHERE (`created_at` >= %s AND `created_at` < %s) ORDER BY `id` ASC;"
    assert res.parameters == ["2026-09-06T00:00:00", "2026-09-07T00:00:00"]


# ---------------------------------------------------------------------------
# 11. Mutations (CREATE, UPDATE, DELETE)
# ---------------------------------------------------------------------------

def test_mysql_lower_create_single(mysql_schema: SourceSchema):
    bound = bind_altrql(parse_altrql('CREATE users ( email: "alice@example.com", is_active: TRUE, metadata: NULL );'), mysql_schema)
    lowerer = MySQLLowerer()
    res = lowerer.lower(bound)
    assert res.query == "INSERT INTO `users` (`email`, `is_active`, `metadata`) VALUES (%s, %s, NULL);"
    assert res.parameters == ["alice@example.com", True]


def test_mysql_lower_create_batch(mysql_schema: SourceSchema):
    query = """
    CREATE users (
        (email: "alice@example.com", is_active: TRUE),
        (email: "bob@example.com", is_active: FALSE)
    );
    """
    bound = bind_altrql(parse_altrql(query), mysql_schema)
    lowerer = MySQLLowerer()
    res = lowerer.lower(bound)
    assert res.query == "INSERT INTO `users` (`email`, `is_active`) VALUES (%s, %s), (%s, %s);"
    assert res.parameters == ["alice@example.com", True, "bob@example.com", False]


def test_mysql_lower_update(mysql_schema: SourceSchema):
    bound = bind_altrql(parse_altrql('UPDATE users ( status: "INACTIVE", metadata: NULL ) WHERE { id = 5 };'), mysql_schema)
    lowerer = MySQLLowerer()
    res = lowerer.lower(bound)
    assert res.query == "UPDATE `users` SET `status` = %s, `metadata` = NULL WHERE `id` = %s;"
    assert res.parameters == ["INACTIVE", 5]


def test_mysql_lower_delete(mysql_schema: SourceSchema):
    bound = bind_altrql(parse_altrql("DELETE users WHERE { age < 18 };"), mysql_schema)
    lowerer = MySQLLowerer()
    res = lowerer.lower(bound)
    assert res.query == "DELETE FROM `users` WHERE `age` < %s;"
    assert res.parameters == [18]
