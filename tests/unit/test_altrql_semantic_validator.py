"""Unit tests for AltrQL Semantic Validator (validate_ir).

Tests AST invariants, range compatibility rules, ranking count bounds,
and direct AST object validation.
"""

import pytest

from altr_stream.query_engine.domain.ast import (
    AltrQueryIR,
    BooleanLiteral,
    ComparisonConstraint,
    CompoundAndConstraint,
    FieldExpression,
    FieldPath,
    FieldSelection,
    FloatLiteral,
    IntegerLiteral,
    LogicalExpression,
    NullLiteral,
    Range,
    RankingClause,
    RankingDirection,
    SortClause,
    SortDirection,
    StringLiteral,
    TemporalLiteral,
    ValueSet,
)
from altr_stream.query_engine.domain.errors import AltrQuerySemanticError
from altr_stream.query_engine.domain.operators import (
    ComparisonOperator,
    StringOperator,
    TemporalKeyword,
)
from altr_stream.query_engine.parser import parse_altrql
from altr_stream.query_engine.semantic.validator import validate_ir


def test_validator_valid_query_passes():
    """Test that a semantically valid query parses and validates cleanly."""
    query = """
    GET users (
        id AS user_id,
        name AS user_name,
        profile.avatar
    ) WHERE {
        age = {18..65},
        score = {>=1.5 & <=99.9},
        category STARTS "VIP"
    } TOP 10 BY score OFFSET 5;
    """
    ir = parse_altrql(query)
    assert ir.entity == "users"
    assert len(ir.projection) == 3
    assert ir.ranking is not None
    assert ir.ranking.count == 10


# ---------------------------------------------------------------------------
# Rule 1: Projection Alias Uniqueness
# ---------------------------------------------------------------------------


def test_validator_rejects_duplicate_projection_aliases_via_parser():
    """Test that duplicate aliases in query string raise AltrQuerySemanticError."""
    query = "GET users (id AS col, name AS col);"
    with pytest.raises(AltrQuerySemanticError) as exc_info:
        parse_altrql(query)
    assert "Duplicate projection alias 'col'" in exc_info.value.message


def test_validator_rejects_duplicate_projection_aliases_direct_ast():
    """Test that duplicate aliases in directly constructed IR raise AltrQuerySemanticError."""
    ir = AltrQueryIR(
        entity="users",
        projection=[
            FieldSelection(path=FieldPath(segments=["id"]), alias="col"),
            FieldSelection(path=FieldPath(segments=["name"]), alias="col"),
        ],
    )
    with pytest.raises(AltrQuerySemanticError) as exc_info:
        validate_ir(ir)
    assert "Duplicate projection alias 'col'" in exc_info.value.message


def test_validator_allows_distinct_projection_aliases():
    """Test that distinct aliases validate cleanly."""
    ir = AltrQueryIR(
        entity="users",
        projection=[
            FieldSelection(path=FieldPath(segments=["id"]), alias="user_id"),
            FieldSelection(path=FieldPath(segments=["name"]), alias="user_name"),
        ],
    )
    validate_ir(ir)


# ---------------------------------------------------------------------------
# Rule 2: Ranking Count Bounds
# ---------------------------------------------------------------------------


def test_validator_rejects_zero_ranking_count_direct_ast():
    """Test that ranking count <= 0 raises AltrQuerySemanticError."""
    ir = AltrQueryIR(
        entity="users",
        ranking=RankingClause(
            direction=RankingDirection.TOP,
            count=0,
            field=FieldPath(segments=["id"]),
        ),
    )
    with pytest.raises(AltrQuerySemanticError) as exc_info:
        validate_ir(ir)
    assert "Ranking count must be a positive integer greater than 0, got 0" in exc_info.value.message


def test_validator_rejects_negative_ranking_count_direct_ast():
    """Test that negative ranking count raises AltrQuerySemanticError."""
    ir = AltrQueryIR(
        entity="users",
        ranking=RankingClause(
            direction=RankingDirection.BOTTOM,
            count=-5,
            field=FieldPath(segments=["id"]),
        ),
    )
    with pytest.raises(AltrQuerySemanticError) as exc_info:
        validate_ir(ir)
    assert "Ranking count must be a positive integer greater than 0, got -5" in exc_info.value.message


# ---------------------------------------------------------------------------
# Rule 3: Non-negative Offset
# ---------------------------------------------------------------------------


def test_validator_rejects_negative_offset_direct_ast():
    """Test that negative OFFSET raises AltrQuerySemanticError."""
    ir = AltrQueryIR(
        entity="users",
        offset=-10,
    )
    with pytest.raises(AltrQuerySemanticError) as exc_info:
        validate_ir(ir)
    assert "OFFSET must be non-negative (>= 0), got -10" in exc_info.value.message


def test_validator_allows_zero_offset():
    """Test that OFFSET 0 is valid."""
    ir = AltrQueryIR(entity="users", offset=0)
    validate_ir(ir)


# ---------------------------------------------------------------------------
# Rule 4: SORT and RANKING Mutual Exclusivity
# ---------------------------------------------------------------------------


def test_validator_rejects_combined_sort_and_ranking_direct_ast():
    """Test that having both SORT and RANKING clauses raises AltrQuerySemanticError."""
    ir = AltrQueryIR(
        entity="users",
        sort=[SortClause(field=FieldPath(segments=["created_at"]), direction=SortDirection.DESC)],
        ranking=RankingClause(
            direction=RankingDirection.TOP,
            count=10,
            field=FieldPath(segments=["id"]),
        ),
    )
    with pytest.raises(AltrQuerySemanticError) as exc_info:
        validate_ir(ir)
    assert "Cannot combine 'SORT' with 'TOP'/'BOTTOM' ranking clause" in exc_info.value.message


# ---------------------------------------------------------------------------
# Rule 5: Expression & Operator Validation
# ---------------------------------------------------------------------------


def test_validator_rejects_empty_logical_expression_direct_ast():
    """Test that LogicalExpression with 0 operands raises AltrQuerySemanticError."""
    ir = AltrQueryIR(
        entity="users",
        where=LogicalExpression(operator="AND", operands=[]),
    )
    with pytest.raises(AltrQuerySemanticError) as exc_info:
        validate_ir(ir)
    assert "LogicalExpression must contain at least 1 operand" in exc_info.value.message


def test_validator_rejects_string_operator_with_numeric_literal_direct_ast():
    """Test that StringOperator with integer literal raises AltrQuerySemanticError."""
    ir = AltrQueryIR(
        entity="users",
        where=FieldExpression(
            field=FieldPath(segments=["name"]),
            operator=StringOperator.STARTS,
            operand=IntegerLiteral(value=123),
        ),
    )
    with pytest.raises(AltrQuerySemanticError) as exc_info:
        validate_ir(ir)
    assert "String operator 'STARTS' cannot be used with operand of type 'IntegerLiteral'" in exc_info.value.message


def test_validator_rejects_string_operator_with_non_string_in_value_set_direct_ast():
    """Test that StringOperator with non-string in ValueSet raises AltrQuerySemanticError."""
    ir = AltrQueryIR(
        entity="users",
        where=FieldExpression(
            field=FieldPath(segments=["name"]),
            operator=StringOperator.HAS,
            operand=ValueSet(elements=[StringLiteral(value="admin"), IntegerLiteral(value=42)]),
        ),
    )
    with pytest.raises(AltrQuerySemanticError) as exc_info:
        validate_ir(ir)
    assert "cannot be used with non-string element 'IntegerLiteral'" in exc_info.value.message


# ---------------------------------------------------------------------------
# Rule 6: ValueSet & Compound Constraints
# ---------------------------------------------------------------------------


def test_validator_rejects_empty_value_set_direct_ast():
    """Test that empty ValueSet raises AltrQuerySemanticError."""
    ir = AltrQueryIR(
        entity="users",
        where=FieldExpression(
            field=FieldPath(segments=["status"]),
            operator=ComparisonOperator.EQ,
            operand=ValueSet(elements=[]),
        ),
    )
    with pytest.raises(AltrQuerySemanticError) as exc_info:
        validate_ir(ir)
    assert "ValueSet cannot be empty" in exc_info.value.message


def test_validator_rejects_compound_and_with_less_than_two_constraints_direct_ast():
    """Test that CompoundAndConstraint with < 2 constraints raises AltrQuerySemanticError."""
    ir = AltrQueryIR(
        entity="users",
        where=FieldExpression(
            field=FieldPath(segments=["age"]),
            operator=ComparisonOperator.EQ,
            operand=ValueSet(
                elements=[
                    CompoundAndConstraint(
                        constraints=[
                            ComparisonConstraint(operator=ComparisonOperator.GTE, value=IntegerLiteral(value=18))
                        ]
                    )
                ]
            ),
        ),
    )
    with pytest.raises(AltrQuerySemanticError) as exc_info:
        validate_ir(ir)
    assert "CompoundAndConstraint must contain at least 2 comparison constraints" in exc_info.value.message


# ---------------------------------------------------------------------------
# Rule 7: Range Compatibility Matrix
# ---------------------------------------------------------------------------


@pytest.mark.parametrize(
    "start, end, valid",
    [
        # Integer ↔ Integer
        (IntegerLiteral(value=1), IntegerLiteral(value=10), True),
        (IntegerLiteral(value=10), IntegerLiteral(value=1), False),
        (IntegerLiteral(value=5), IntegerLiteral(value=5), True),
        # Integer ↔ Float
        (IntegerLiteral(value=1), FloatLiteral(value=10.5), True),
        (IntegerLiteral(value=10), FloatLiteral(value=1.5), False),
        # Float ↔ Integer
        (FloatLiteral(value=1.5), IntegerLiteral(value=10), True),
        (FloatLiteral(value=10.5), IntegerLiteral(value=1), False),
        # Float ↔ Float
        (FloatLiteral(value=1.5), FloatLiteral(value=10.5), True),
        (FloatLiteral(value=10.5), FloatLiteral(value=1.5), False),
        # String ↔ String
        (StringLiteral(value="a"), StringLiteral(value="z"), True),
        (StringLiteral(value="z"), StringLiteral(value="a"), False),
        (StringLiteral(value="test"), StringLiteral(value="test"), True),
        # Temporal ↔ Temporal
        (TemporalLiteral(keyword=TemporalKeyword.TODAY), TemporalLiteral(keyword=TemporalKeyword.NOW), True),
    ],
)
def test_validator_range_compatibility_matrix(start, end, valid):
    """Test range compatibility matrix across mixed numeric, string, and temporal bounds."""
    ir = AltrQueryIR(
        entity="events",
        where=FieldExpression(
            field=FieldPath(segments=["val"]),
            operator=ComparisonOperator.EQ,
            operand=Range(start=start, end=end),
        ),
    )
    if valid:
        validate_ir(ir)
    else:
        with pytest.raises(AltrQuerySemanticError) as exc_info:
            validate_ir(ir)
        assert "must be less than or equal to end" in exc_info.value.message


@pytest.mark.parametrize(
    "start, end",
    [
        (BooleanLiteral(value=True), BooleanLiteral(value=False)),
        (NullLiteral(), IntegerLiteral(value=10)),
        (IntegerLiteral(value=10), NullLiteral()),
        (StringLiteral(value="abc"), IntegerLiteral(value=10)),
        (IntegerLiteral(value=10), StringLiteral(value="abc")),
        (TemporalLiteral(keyword=TemporalKeyword.TODAY), StringLiteral(value="2026-01-01")),
    ],
)
def test_validator_range_invalid_types_and_mismatched_categories(start, end):
    """Test that boolean, null, and mismatched category bounds raise AltrQuerySemanticError."""
    ir = AltrQueryIR(
        entity="events",
        where=FieldExpression(
            field=FieldPath(segments=["val"]),
            operator=ComparisonOperator.EQ,
            operand=Range(start=start, end=end),
        ),
    )
    with pytest.raises(AltrQuerySemanticError) as exc_info:
        validate_ir(ir)
    assert (
        "Range cannot have boolean or null bounds" in exc_info.value.message
        or "Incompatible range bound types" in exc_info.value.message
    )


def test_validator_inverted_range_parsed_query_raises():
    """Test that an inverted range in query string raises AltrQuerySemanticError."""
    query = "GET users WHERE { age = 50..10 };"
    with pytest.raises(AltrQuerySemanticError) as exc_info:
        parse_altrql(query)
    assert "Range start (50) must be less than or equal to end (10)" in exc_info.value.message


def test_validator_temporal_iso_date_ranges():
    """Test that temporal ISO date ranges validate start <= end."""
    valid_query = "GET logs WHERE { ts = @2026-01-01..@2026-12-31 };"
    ir = parse_altrql(valid_query)
    assert ir.where is not None

    invalid_query = "GET logs WHERE { ts = @2026-12-31..@2026-01-01 };"
    with pytest.raises(AltrQuerySemanticError) as exc_info:
        parse_altrql(invalid_query)
    assert "Range start (@2026-12-31) must be less than or equal to end (@2026-01-01)" in exc_info.value.message
