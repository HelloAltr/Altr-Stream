"""Unit tests for AltrQL v0.5 NULL semantics across Parser, Semantic Validator, Binder, and Lowerer."""

import pytest

from altr_stream.domain.schema import (
    EntitySchema,
    FieldSchema,
    SourceSchema,
    StandardDataType,
)
from altr_stream.query_engine.binding.binder import bind_altrql
from altr_stream.query_engine.domain.ast import (
    ComparisonOperator,
    FieldExpression,
    NullLiteral,
    QueryOperation,
    StringOperator,
)
from altr_stream.query_engine.domain.errors import (
    AltrQueryParseError,
    AltrQuerySemanticError,
    TypeCompatibilityError,
)
from altr_stream.query_engine.lowering.postgres import PostgreSQLLowerer
from altr_stream.query_engine.parser import parse_altrql


@pytest.fixture
def mock_schema() -> SourceSchema:
    return SourceSchema(
        source_id="src_test_null",
        source_name="Test Source",
        version="1.0.0",
        entities=[
            EntitySchema(
                name="users",
                namespace="public",
                entity_type="TABLE",
                fields=[
                    FieldSchema(name="id", data_type=StandardDataType.INTEGER, native_data_type="int4", nullable=False, is_primary_key=True),
                    FieldSchema(name="email", data_type=StandardDataType.STRING, native_data_type="varchar", nullable=False),
                    FieldSchema(name="status", data_type=StandardDataType.STRING, native_data_type="varchar", nullable=True),
                    FieldSchema(name="metadata", data_type=StandardDataType.JSON, native_data_type="jsonb", nullable=True),
                    FieldSchema(name="age", data_type=StandardDataType.INTEGER, native_data_type="int4", nullable=True),
                ],
                primary_key=["id"],
            )
        ],
    )


# ---------------------------------------------------------------------------
# 1. Parser Tests
# ---------------------------------------------------------------------------


def test_parse_null_equality():
    ir = parse_altrql("GET users WHERE { metadata = NULL };")
    assert ir.operation == QueryOperation.READ
    assert isinstance(ir.where, FieldExpression)
    assert ir.where.operator == ComparisonOperator.EQ
    assert isinstance(ir.where.operand, NullLiteral)


def test_parse_null_inequality():
    ir = parse_altrql("GET users WHERE { metadata != NULL };")
    assert isinstance(ir.where, FieldExpression)
    assert ir.where.operator == ComparisonOperator.NEQ
    assert isinstance(ir.where.operand, NullLiteral)


def test_parse_null_in_valueset():
    ir = parse_altrql('GET users WHERE { status = {"ACTIVE", NULL} };')
    assert isinstance(ir.where, FieldExpression)
    vs = ir.where.operand
    assert len(vs.elements) == 2
    assert isinstance(vs.elements[1], NullLiteral)


def test_parse_create_explicit_null():
    ir = parse_altrql('CREATE users ( email: "alice@example.com", metadata: NULL );')
    assert ir.operation == QueryOperation.CREATE
    assert len(ir.records) == 1
    assert len(ir.records[0].assignments) == 2
    assert isinstance(ir.records[0].assignments[1].value, NullLiteral)


def test_parse_update_explicit_null():
    ir = parse_altrql('UPDATE users ( metadata: NULL ) WHERE { id = 1 };')
    assert ir.operation == QueryOperation.UPDATE
    assert len(ir.assignments) == 1
    assert isinstance(ir.assignments[0].value, NullLiteral)


def test_parse_delete_with_null_predicate():
    ir = parse_altrql("DELETE users WHERE { metadata = NULL };")
    assert ir.operation == QueryOperation.DELETE
    assert ir.where is not None
    assert isinstance(ir.where.operand, NullLiteral)


# ---------------------------------------------------------------------------
# 2. Semantic Validator & Parser Token Tests
# ---------------------------------------------------------------------------


def test_parse_rejects_string_operator_with_null():
    with pytest.raises(AltrQueryParseError) as exc_info:
        parse_altrql("GET users WHERE { email HAS NULL };")
    assert "Expected string literal in quotes" in exc_info.value.message


def test_semantic_validator_rejects_range_with_null():
    with pytest.raises(AltrQuerySemanticError) as exc_info:
        parse_altrql("GET users WHERE { age = { 1..NULL } };")
    assert "Range cannot have boolean or null bounds" in exc_info.value.message


# ---------------------------------------------------------------------------
# 3. Schema Binder & Type Validator Tests
# ---------------------------------------------------------------------------


def test_bind_null_equality_on_nullable_and_non_nullable(mock_schema: SourceSchema):
    bound_nullable = bind_altrql(parse_altrql("GET users WHERE { metadata = NULL };"), mock_schema)
    assert bound_nullable.where is not None

    bound_non_nullable = bind_altrql(parse_altrql("GET users WHERE { email = NULL };"), mock_schema)
    assert bound_non_nullable.where is not None


def test_bind_null_in_valueset(mock_schema: SourceSchema):
    bound = bind_altrql(parse_altrql('GET users WHERE { status = {"ACTIVE", NULL} };'), mock_schema)
    assert bound.where is not None


def test_bind_ordering_operator_with_null_rejected(mock_schema: SourceSchema):
    with pytest.raises(TypeCompatibilityError) as exc_info:
        bind_altrql(parse_altrql("GET users WHERE { age > NULL };"), mock_schema)
    assert "Ordering operator '>' is not supported with NULL" in str(exc_info.value)


def test_bind_create_null_assignment_on_non_nullable_rejected(mock_schema: SourceSchema):
    with pytest.raises(TypeCompatibilityError) as exc_info:
        bind_altrql(parse_altrql('CREATE users ( email: NULL );'), mock_schema)
    assert "Cannot assign NULL to non-nullable field 'email'" in str(exc_info.value)


def test_bind_update_null_assignment_on_non_nullable_rejected(mock_schema: SourceSchema):
    with pytest.raises(TypeCompatibilityError) as exc_info:
        bind_altrql(parse_altrql('UPDATE users ( email: NULL ) WHERE { id = 1 };'), mock_schema)
    assert "Cannot assign NULL to non-nullable field 'email'" in str(exc_info.value)


# ---------------------------------------------------------------------------
# 4. PostgreSQL Lowerer Tests
# ---------------------------------------------------------------------------


def test_lower_null_equality(mock_schema: SourceSchema):
    bound = bind_altrql(parse_altrql("GET users WHERE { metadata = NULL };"), mock_schema)
    lowerer = PostgreSQLLowerer()
    res = lowerer.lower(bound)
    assert res.query == 'SELECT * FROM "public"."users" WHERE "metadata" IS NULL ORDER BY "id" ASC;'
    assert res.parameters == []


def test_lower_null_inequality(mock_schema: SourceSchema):
    bound = bind_altrql(parse_altrql("GET users WHERE { metadata != NULL };"), mock_schema)
    lowerer = PostgreSQLLowerer()
    res = lowerer.lower(bound)
    assert res.query == 'SELECT * FROM "public"."users" WHERE "metadata" IS NOT NULL ORDER BY "id" ASC;'
    assert res.parameters == []


def test_lower_null_negation(mock_schema: SourceSchema):
    bound = bind_altrql(parse_altrql("GET users WHERE { NOT { metadata = NULL } };"), mock_schema)
    lowerer = PostgreSQLLowerer()
    res = lowerer.lower(bound)
    assert res.query == 'SELECT * FROM "public"."users" WHERE NOT ("metadata" IS NULL) ORDER BY "id" ASC;'
    assert res.parameters == []


def test_lower_valueset_with_null_equality(mock_schema: SourceSchema):
    bound = bind_altrql(parse_altrql('GET users WHERE { status = {"ACTIVE", NULL} };'), mock_schema)
    lowerer = PostgreSQLLowerer()
    res = lowerer.lower(bound)
    assert res.query == 'SELECT * FROM "public"."users" WHERE ("status" = $1 OR "status" IS NULL) ORDER BY "id" ASC;'
    assert res.parameters == ["ACTIVE"]


def test_lower_valueset_with_null_inequality(mock_schema: SourceSchema):
    bound = bind_altrql(parse_altrql('GET users WHERE { status != {"ACTIVE", NULL} };'), mock_schema)
    lowerer = PostgreSQLLowerer()
    res = lowerer.lower(bound)
    assert res.query == 'SELECT * FROM "public"."users" WHERE ("status" != $1 AND "status" IS NOT NULL) ORDER BY "id" ASC;'
    assert res.parameters == ["ACTIVE"]


def test_lower_valueset_only_null(mock_schema: SourceSchema):
    bound_eq = bind_altrql(parse_altrql('GET users WHERE { status = {NULL} };'), mock_schema)
    lowerer = PostgreSQLLowerer()
    res_eq = lowerer.lower(bound_eq)
    assert res_eq.query == 'SELECT * FROM "public"."users" WHERE "status" IS NULL ORDER BY "id" ASC;'
    assert res_eq.parameters == []

    bound_neq = bind_altrql(parse_altrql('GET users WHERE { status != {NULL} };'), mock_schema)
    res_neq = lowerer.lower(bound_neq)
    assert res_neq.query == 'SELECT * FROM "public"."users" WHERE "status" IS NOT NULL ORDER BY "id" ASC;'
    assert res_neq.parameters == []


def test_lower_not_has_with_null_handling(mock_schema: SourceSchema):
    bound = bind_altrql(parse_altrql('GET users WHERE { status NOT HAS "act" };'), mock_schema)
    lowerer = PostgreSQLLowerer()
    res = lowerer.lower(bound)
    assert res.query == 'SELECT * FROM "public"."users" WHERE ("status" NOT LIKE $1 OR "status" IS NULL) ORDER BY "id" ASC;'
    assert res.parameters == ["%act%"]


def test_lower_create_with_null(mock_schema: SourceSchema):
    bound = bind_altrql(parse_altrql('CREATE users ( email: "alice@example.com", metadata: NULL );'), mock_schema)
    lowerer = PostgreSQLLowerer()
    res = lowerer.lower(bound)
    assert res.query == 'INSERT INTO "public"."users" ("email", "metadata") VALUES ($1, NULL) RETURNING *;'
    assert res.parameters == ["alice@example.com"]


def test_lower_update_with_null(mock_schema: SourceSchema):
    bound = bind_altrql(parse_altrql('UPDATE users ( metadata: NULL ) WHERE { id = 1 };'), mock_schema)
    lowerer = PostgreSQLLowerer()
    res = lowerer.lower(bound)
    assert res.query == 'UPDATE "public"."users" SET "metadata" = NULL WHERE "id" = $1 RETURNING *;'
    assert res.parameters == [1]


def test_lower_delete_with_null(mock_schema: SourceSchema):
    bound = bind_altrql(parse_altrql('DELETE users WHERE { metadata = NULL };'), mock_schema)
    lowerer = PostgreSQLLowerer()
    res = lowerer.lower(bound)
    assert res.query == 'DELETE FROM "public"."users" WHERE "metadata" IS NULL RETURNING *;'
    assert res.parameters == []


def test_bind_json_non_null_comparison_rejected(mock_schema: SourceSchema):
    with pytest.raises(TypeCompatibilityError) as exc_info1:
        bind_altrql(parse_altrql('GET users WHERE { metadata = "raw_string" };'), mock_schema)
    assert "unsupported AltrQL comparison type 'JSON'" in str(exc_info1.value)

    with pytest.raises(TypeCompatibilityError) as exc_info2:
        bind_altrql(parse_altrql('GET users WHERE { metadata > 10 };'), mock_schema)
    assert "unsupported AltrQL comparison type 'JSON'" in str(exc_info2.value)


def test_bind_json_non_null_mutation_rejected(mock_schema: SourceSchema):
    with pytest.raises(TypeCompatibilityError) as exc_info1:
        bind_altrql(parse_altrql('CREATE users ( email: "test@example.com", metadata: "{}" );'), mock_schema)
    assert "unsupported AltrQL mutation type 'JSON'" in str(exc_info1.value)

    with pytest.raises(TypeCompatibilityError) as exc_info2:
        bind_altrql(parse_altrql('UPDATE users ( metadata: 123 ) WHERE { id = 1 };'), mock_schema)
    assert "unsupported AltrQL mutation type 'JSON'" in str(exc_info2.value)


