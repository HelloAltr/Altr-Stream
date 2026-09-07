"""Unit tests for AltrQL Binder (Phase D)."""

import pytest

from altr_stream.domain.schema import EntitySchema, FieldSchema, SourceSchema, StandardDataType
from altr_stream.query_engine import parse_altrql
from altr_stream.query_engine.binding.binder import bind_altrql
from altr_stream.query_engine.domain.ast import (
    AltrQueryIR,
    ComparisonConstraint,
    CompoundAndConstraint,
    FieldExpression,
    FieldPath,
    FieldSelection,
    IntegerLiteral,
    LogicalExpression,
    Range,
    RankingClause,
    SortClause,
    StringLiteral,
    TemporalLiteral,
    ValueSet,
)
from altr_stream.query_engine.domain.bound_ast import (
    BoundAltrQueryIR,
    BoundEntity,
    BoundFieldExpression,
    BoundFieldPath,
    BoundFieldSelection,
    BoundLogicalExpression,
    BoundRankingClause,
    BoundSortClause,
    LogicalTypeCategory,
)
from altr_stream.query_engine.domain.errors import (
    TypeCompatibilityError,
    UnknownEntityError,
    UnknownFieldError,
)
from altr_stream.query_engine.domain.operators import (
    ComparisonOperator,
    RankingDirection,
    SortDirection,
    StringOperator,
    TemporalKeyword,
)


@pytest.fixture
def sample_schema() -> SourceSchema:
    return SourceSchema(
        source_id="src_42",
        source_name="analytics_pg",
        entities=[
            EntitySchema(
                name="events",
                fields=[
                    FieldSchema(name="id", data_type=StandardDataType.BIGINT, native_data_type="int8", nullable=False, is_primary_key=True),
                    FieldSchema(name="event_type", data_type=StandardDataType.STRING, native_data_type="varchar", nullable=False),
                    FieldSchema(name="user_id", data_type=StandardDataType.INTEGER, native_data_type="int4", nullable=False),
                    FieldSchema(name="timestamp", data_type=StandardDataType.TIMESTAMP, native_data_type="timestamp", nullable=False),
                    FieldSchema(name="score", data_type=StandardDataType.FLOAT, native_data_type="float8", nullable=True),
                ],
            )
        ],
    )


def test_bind_wildcard_query_success(sample_schema: SourceSchema):
    raw_ir = parse_altrql("GET events;")
    bound = bind_altrql(raw_ir, sample_schema)

    assert isinstance(bound, BoundAltrQueryIR)
    assert bound.source_id == "src_42"
    assert bound.source_name == "analytics_pg"
    assert bound.entity.name == "events"
    assert bound.is_wildcard_projection is True
    assert bound.projection == []


def test_bind_explicit_projection_with_alias(sample_schema: SourceSchema):
    raw_ir = parse_altrql("GET events (id AS event_id, event_type);")
    bound = bind_altrql(raw_ir, sample_schema)

    assert isinstance(bound.projection, list)
    assert len(bound.projection) == 2
    assert isinstance(bound.projection[0], BoundFieldSelection)
    assert bound.projection[0].field.segments == ["id"]
    assert bound.projection[0].field.data_type == StandardDataType.BIGINT
    assert bound.projection[0].alias == "event_id"

    assert isinstance(bound.projection[1], BoundFieldSelection)
    assert bound.projection[1].field.segments == ["event_type"]
    assert bound.projection[1].field.data_type == StandardDataType.STRING
    assert bound.projection[1].alias is None


def test_bind_complex_where_clause(sample_schema: SourceSchema):
    query = 'GET events (id) WHERE { event_type STARTS "auth_", user_id = {1, 2, 5..10}, timestamp >= TODAY };'
    raw_ir = parse_altrql(query)
    bound = bind_altrql(raw_ir, sample_schema)

    assert bound.where is not None
    assert isinstance(bound.where, BoundLogicalExpression)
    assert bound.where.operator == "AND"
    assert len(bound.where.operands) == 3

    # Check 1st operand: event_type STARTS "auth_"
    op1 = bound.where.operands[0]
    assert isinstance(op1, BoundFieldExpression)
    assert op1.field.segments == ["event_type"]
    assert op1.field.logical_category == LogicalTypeCategory.STRING
    assert op1.operator == StringOperator.STARTS
    assert isinstance(op1.operand, StringLiteral)

    # Check 2nd operand: user_id = {1, 2, 5..10}
    op2 = bound.where.operands[1]
    assert isinstance(op2, BoundFieldExpression)
    assert op2.field.segments == ["user_id"]
    assert op2.field.logical_category == LogicalTypeCategory.NUMERIC
    assert isinstance(op2.operand, ValueSet)

    # Check 3rd operand: timestamp >= TODAY
    op3 = bound.where.operands[2]
    assert isinstance(op3, BoundFieldExpression)
    assert op3.field.segments == ["timestamp"]
    assert op3.field.logical_category == LogicalTypeCategory.TEMPORAL
    assert isinstance(op3.operand, TemporalLiteral)


def test_bind_sort_and_ranking_clauses(sample_schema: SourceSchema):
    query = "GET events (id) SORT { timestamp DESC, id ASC };"
    raw_ir = parse_altrql(query)
    bound = bind_altrql(raw_ir, sample_schema)

    assert bound.sort is not None
    assert len(bound.sort) == 2
    assert bound.sort[0].field.segments == ["timestamp"]
    assert bound.sort[0].field.data_type == StandardDataType.TIMESTAMP
    assert bound.sort[0].direction == SortDirection.DESC

    ranking_query = "GET events (id) TOP 10 BY score;"
    raw_ir2 = parse_altrql(ranking_query)
    bound2 = bind_altrql(raw_ir2, sample_schema)

    assert bound2.ranking is not None
    assert isinstance(bound2.ranking, BoundRankingClause)
    assert bound2.ranking.direction == RankingDirection.TOP
    assert bound2.ranking.count == 10
    assert bound2.ranking.field.segments == ["score"]
    assert bound2.ranking.field.data_type == StandardDataType.FLOAT


def test_bind_unknown_entity_error(sample_schema: SourceSchema):
    raw_ir = parse_altrql("GET unknown_table;")
    with pytest.raises(UnknownEntityError) as exc_info:
        bind_altrql(raw_ir, sample_schema)
    assert "unknown_table" in str(exc_info.value)


def test_bind_unknown_field_in_projection(sample_schema: SourceSchema):
    raw_ir = parse_altrql("GET events (id, non_existent_col);")
    with pytest.raises(UnknownFieldError) as exc_info:
        bind_altrql(raw_ir, sample_schema)
    assert "non_existent_col" in str(exc_info.value)


def test_bind_unknown_field_in_where(sample_schema: SourceSchema):
    raw_ir = parse_altrql('GET events WHERE { ghost_col = "value" };')
    with pytest.raises(UnknownFieldError) as exc_info:
        bind_altrql(raw_ir, sample_schema)
    assert "ghost_col" in str(exc_info.value)


def test_bind_type_compatibility_error(sample_schema: SourceSchema):
    raw_ir = parse_altrql('GET events WHERE { id = "string_id" };')
    with pytest.raises(TypeCompatibilityError) as exc_info:
        bind_altrql(raw_ir, sample_schema)
    assert "STRING" in str(exc_info.value)
    assert "NUMERIC" in str(exc_info.value)


def test_binder_is_pure_and_does_not_mutate_input_ir(sample_schema: SourceSchema):
    raw_ir = parse_altrql("GET events (id) WHERE { user_id = 123 };")
    original_projection = raw_ir.projection
    original_where = raw_ir.where

    bound = bind_altrql(raw_ir, sample_schema)

    assert raw_ir.projection == original_projection
    assert raw_ir.where == original_where
    assert isinstance(bound, BoundAltrQueryIR)
    assert not isinstance(raw_ir, BoundAltrQueryIR)


def test_bind_explicit_iso_date_literal(sample_schema: SourceSchema):
    raw_ir = parse_altrql("GET events WHERE { timestamp >= @2026-01-01 };")
    bound = bind_altrql(raw_ir, sample_schema)

    assert isinstance(bound.where, BoundFieldExpression)
    assert bound.where.field.segments == ["timestamp"]
    assert bound.where.field.logical_category == LogicalTypeCategory.TEMPORAL
    assert isinstance(bound.where.operand, TemporalLiteral)
    assert bound.where.operand.value == "2026-01-01"
