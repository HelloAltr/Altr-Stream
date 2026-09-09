"""Unit tests for AltrQL v0.4 semantic validation on UPDATE queries."""

import pytest

from altr_stream.query_engine.domain.ast import (
    AltrQueryIR,
    BooleanLiteral,
    ComparisonOperator,
    CreateRecord,
    FieldExpression,
    FieldPath,
    FieldSelection,
    IntegerLiteral,
    LogicalExpression,
    LogicalOperator,
    MutationAssignment,
    NegationExpression,
    QueryOperation,
    RankingClause,
    RankingDirection,
    SortClause,
    SortDirection,
    StringLiteral,
    ValueSet,
)
from altr_stream.query_engine.domain.errors import AltrQuerySemanticError
from altr_stream.query_engine.parser import parse_altrql
from altr_stream.query_engine.semantic.validator import validate_ir


def test_validator_accepts_valid_update():
    """Valid UPDATE with assignments and WHERE passes semantic validation."""
    query = """
    UPDATE users (
        full_name: "Alice Updated",
        is_active: TRUE
    ) WHERE {
        email = "alice@example.com"
    };
    """
    ir = parse_altrql(query)
    validate_ir(ir)
    assert ir.operation == QueryOperation.UPDATE
    assert len(ir.assignments) == 2
    assert ir.where is not None


def test_validator_accepts_update_with_complex_where():
    """Valid UPDATE with OR and NOT in WHERE passes semantic validation."""
    query = """
    UPDATE users (
        is_active: FALSE
    ) WHERE {
        NOT { is_active = FALSE }
        OR email = "bob@example.com"
    };
    """
    ir = parse_altrql(query)
    validate_ir(ir)


def test_validator_rejects_update_without_assignments():
    """UPDATE with empty assignments list must be rejected."""
    ir = AltrQueryIR(
        operation=QueryOperation.UPDATE,
        entity="users",
        assignments=[],
        where=FieldExpression(
            field=FieldPath(segments=["id"]),
            operator=ComparisonOperator.EQ,
            operand=IntegerLiteral(value=1),
        ),
    )
    with pytest.raises(AltrQuerySemanticError) as exc_info:
        validate_ir(ir)
    assert "assignment" in exc_info.value.message.lower()


def test_validator_rejects_duplicate_assignments_in_update():
    """Duplicate field assignments in UPDATE must be rejected by validator."""
    ir = AltrQueryIR(
        operation=QueryOperation.UPDATE,
        entity="users",
        assignments=[
            MutationAssignment(field=FieldPath(segments=["username"]), value=StringLiteral(value="alice")),
            MutationAssignment(field=FieldPath(segments=["username"]), value=StringLiteral(value="bob")),
        ],
        where=FieldExpression(
            field=FieldPath(segments=["id"]),
            operator=ComparisonOperator.EQ,
            operand=IntegerLiteral(value=1),
        ),
    )
    with pytest.raises(AltrQuerySemanticError) as exc_info:
        validate_ir(ir)
    assert "duplicate" in exc_info.value.message.lower()


def test_validator_rejects_update_without_where():
    """UPDATE without WHERE clause must be rejected by validator."""
    ir = AltrQueryIR(
        operation=QueryOperation.UPDATE,
        entity="users",
        assignments=[
            MutationAssignment(field=FieldPath(segments=["is_active"]), value=BooleanLiteral(value=False)),
        ],
        where=None,
    )
    with pytest.raises(AltrQuerySemanticError) as exc_info:
        validate_ir(ir)
    assert "where" in exc_info.value.message.lower()


def test_validator_rejects_update_with_grouped_records():
    """UPDATE with CREATE-style grouped records must be rejected."""
    ir = AltrQueryIR(
        operation=QueryOperation.UPDATE,
        entity="users",
        assignments=[
            MutationAssignment(field=FieldPath(segments=["is_active"]), value=BooleanLiteral(value=False)),
        ],
        records=[
            CreateRecord(
                assignments=[
                    MutationAssignment(field=FieldPath(segments=["is_active"]), value=BooleanLiteral(value=False)),
                ]
            )
        ],
        where=FieldExpression(
            field=FieldPath(segments=["id"]),
            operator=ComparisonOperator.EQ,
            operand=IntegerLiteral(value=1),
        ),
    )
    with pytest.raises(AltrQuerySemanticError) as exc_info:
        validate_ir(ir)
    assert "record" in exc_info.value.message.lower()


def test_validator_rejects_update_with_projection():
    """UPDATE cannot specify field projections."""
    ir = AltrQueryIR(
        operation=QueryOperation.UPDATE,
        entity="users",
        projection=[FieldSelection(path=FieldPath(segments=["id"]))],
        assignments=[MutationAssignment(field=FieldPath(segments=["username"]), value=StringLiteral(value="alice"))],
        where=FieldExpression(
            field=FieldPath(segments=["id"]),
            operator=ComparisonOperator.EQ,
            operand=IntegerLiteral(value=1),
        ),
    )
    with pytest.raises(AltrQuerySemanticError) as exc_info:
        validate_ir(ir)
    assert "projection" in exc_info.value.message.lower()


def test_validator_rejects_update_with_sort_or_ranking():
    """UPDATE cannot specify SORT or RANKING."""
    # SORT
    ir_sort = AltrQueryIR(
        operation=QueryOperation.UPDATE,
        entity="users",
        assignments=[MutationAssignment(field=FieldPath(segments=["username"]), value=StringLiteral(value="alice"))],
        where=FieldExpression(
            field=FieldPath(segments=["id"]),
            operator=ComparisonOperator.EQ,
            operand=IntegerLiteral(value=1),
        ),
        sort=[SortClause(field=FieldPath(segments=["username"]), direction=SortDirection.ASC)],
    )
    with pytest.raises(AltrQuerySemanticError) as exc_info1:
        validate_ir(ir_sort)
    assert "sort" in exc_info1.value.message.lower()

    # RANKING
    ir_rank = AltrQueryIR(
        operation=QueryOperation.UPDATE,
        entity="users",
        assignments=[MutationAssignment(field=FieldPath(segments=["username"]), value=StringLiteral(value="alice"))],
        where=FieldExpression(
            field=FieldPath(segments=["id"]),
            operator=ComparisonOperator.EQ,
            operand=IntegerLiteral(value=1),
        ),
        ranking=RankingClause(direction=RankingDirection.TOP, count=5, field=FieldPath(segments=["id"])),
    )
    with pytest.raises(AltrQuerySemanticError) as exc_info2:
        validate_ir(ir_rank)
    assert "ranking" in exc_info2.value.message.lower() or "sort" in exc_info2.value.message.lower()


def test_validator_rejects_update_with_offset():
    """UPDATE cannot specify OFFSET."""
    ir_offset = AltrQueryIR(
        operation=QueryOperation.UPDATE,
        entity="users",
        assignments=[MutationAssignment(field=FieldPath(segments=["username"]), value=StringLiteral(value="alice"))],
        where=FieldExpression(
            field=FieldPath(segments=["id"]),
            operator=ComparisonOperator.EQ,
            operand=IntegerLiteral(value=1),
        ),
        offset=10,
    )
    with pytest.raises(AltrQuerySemanticError) as exc_info:
        validate_ir(ir_offset)
    assert "offset" in exc_info.value.message.lower()
