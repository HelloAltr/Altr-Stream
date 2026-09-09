"""Unit tests for AltrQL v0.4 UPDATE parser."""

import pytest

from altr_stream.query_engine.domain.ast import (
    BooleanLiteral,
    ComparisonConstraint,
    ComparisonOperator,
    FieldExpression,
    FieldPath,
    IntegerLiteral,
    LogicalExpression,
    LogicalOperator,
    MutationAssignment,
    QueryOperation,
    StringLiteral,
    TemporalLiteral,
    ValueSet,
)
from altr_stream.query_engine.domain.errors import AltrQueryParseError
from altr_stream.query_engine.parser import parse_altrql


def test_parse_update_single_assignment():
    """Single assignment UPDATE with simple WHERE condition."""
    query = """
    UPDATE users (
        is_active: FALSE
    ) WHERE {
        email = "alice@example.com"
    };
    """
    ir = parse_altrql(query)
    assert ir.operation == QueryOperation.UPDATE
    assert ir.entity == "users"
    assert len(ir.assignments) == 1
    assert ir.assignments[0] == MutationAssignment(
        field=FieldPath(segments=["is_active"]),
        value=BooleanLiteral(value=False),
    )
    assert ir.where is not None
    assert isinstance(ir.where, FieldExpression)
    assert ir.where.field.segments == ["email"]
    assert ir.where.operator == ComparisonOperator.EQ
    assert ir.where.operand == StringLiteral(value="alice@example.com")


def test_parse_update_multiple_assignments():
    """Multiple assignments UPDATE preserving exact source order."""
    query = """
    UPDATE users (
        full_name: "Updated User",
        is_active: TRUE,
        age: 35
    ) WHERE {
        id = 1
    };
    """
    ir = parse_altrql(query)
    assert ir.operation == QueryOperation.UPDATE
    assert ir.entity == "users"
    assert len(ir.assignments) == 3
    assert ir.assignments[0].field.segments == ["full_name"]
    assert ir.assignments[0].value == StringLiteral(value="Updated User")
    assert ir.assignments[1].field.segments == ["is_active"]
    assert ir.assignments[1].value == BooleanLiteral(value=True)
    assert ir.assignments[2].field.segments == ["age"]
    assert ir.assignments[2].value == IntegerLiteral(value=35)


def test_parse_update_complex_where():
    """UPDATE with compound logical expressions and temporals in WHERE."""
    query = """
    UPDATE users (
        is_active: FALSE
    ) WHERE {
        created_at = @2026-09-06
        OR {
            is_active = TRUE,
            email = "alice@example.com"
        }
    };
    """
    ir = parse_altrql(query)
    assert ir.operation == QueryOperation.UPDATE
    assert ir.where is not None
    assert isinstance(ir.where, LogicalExpression)
    assert ir.where.operator == LogicalOperator.OR


def test_parse_update_set_membership():
    """UPDATE with ValueSet condition in WHERE."""
    query = """
    UPDATE users (
        is_active: FALSE
    ) WHERE {
        email = {
            "alice@example.com",
            "bob@example.com"
        }
    };
    """
    ir = parse_altrql(query)
    assert ir.where is not None
    assert isinstance(ir.where, FieldExpression)
    assert isinstance(ir.where.operand, ValueSet)
    assert len(ir.where.operand.elements) == 2


def test_parse_update_duplicate_assignments_parses_structurally():
    """Duplicate assignments parse structurally in parser; rejection is a semantic validator responsibility."""
    from altr_stream.query_engine.parser import Lexer, Parser
    query = """
    UPDATE users (
        name: "Alice",
        name: "Bob"
    ) WHERE {
        id = 1
    };
    """
    ir = Parser(Lexer(query).tokenize()).parse()
    assert ir.operation == QueryOperation.UPDATE
    assert len(ir.assignments) == 2
    assert ir.assignments[0].field.segments == ["name"]
    assert ir.assignments[1].field.segments == ["name"]


def test_parse_update_rejects_missing_payload():
    """UPDATE without mutation payload is rejected."""
    query = "UPDATE users WHERE { id = 1 };"
    with pytest.raises(AltrQueryParseError) as exc_info:
        parse_altrql(query)
    assert "(" in exc_info.value.message or "payload" in exc_info.value.message.lower()


def test_parse_update_rejects_empty_payload():
    """UPDATE with empty () payload is rejected."""
    query = "UPDATE users () WHERE { id = 1 };"
    with pytest.raises(AltrQueryParseError) as exc_info:
        parse_altrql(query)
    assert "empty" in exc_info.value.message.lower()


def test_parse_update_rejects_missing_where():
    """UPDATE without WHERE clause is rejected."""
    query = "UPDATE users ( is_active: FALSE );"
    with pytest.raises(AltrQueryParseError) as exc_info:
        parse_altrql(query)
    assert "where" in exc_info.value.message.lower()


def test_parse_update_rejects_empty_where():
    """UPDATE with empty WHERE {} block is rejected."""
    query = "UPDATE users ( is_active: FALSE ) WHERE {};"
    with pytest.raises(AltrQueryParseError) as exc_info:
        parse_altrql(query)
    assert "empty" in exc_info.value.message.lower()


def test_parse_update_rejects_trailing_comma_in_payload():
    """Trailing comma before ')' in payload is rejected."""
    query = "UPDATE users ( is_active: FALSE, ) WHERE { id = 1 };"
    with pytest.raises(AltrQueryParseError) as exc_info:
        parse_altrql(query)
    assert "trailing comma" in exc_info.value.message.lower()


def test_parse_update_rejects_disallowed_clauses():
    """UPDATE rejects SORT, RANKING, and OFFSET."""
    # SORT
    with pytest.raises(AltrQueryParseError) as exc_info1:
        parse_altrql("UPDATE users ( is_active: FALSE ) WHERE { id = 1 } SORT { id ASC };")
    assert "sort" in exc_info1.value.message.lower()

    # RANKING
    with pytest.raises(AltrQueryParseError) as exc_info2:
        parse_altrql("UPDATE users ( is_active: FALSE ) WHERE { id = 1 } TOP 10 BY id;")
    assert "ranking" in exc_info2.value.message.lower() or "sort" in exc_info2.value.message.lower()

    # OFFSET
    with pytest.raises(AltrQueryParseError) as exc_info3:
        parse_altrql("UPDATE users ( is_active: FALSE ) WHERE { id = 1 } OFFSET 5;")
    assert "offset" in exc_info3.value.message.lower()
