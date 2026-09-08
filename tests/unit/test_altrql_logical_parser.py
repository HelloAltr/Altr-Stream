"""Unit tests for AltrQL v0.3 Advanced Conditional Logic & Expression Grouping Parser."""

import pytest

from altr_stream.query_engine import (
    AltrQueryParseError,
    BooleanLiteral,
    ComparisonOperator,
    FieldExpression,
    IntegerLiteral,
    LogicalExpression,
    LogicalOperator,
    NegationExpression,
    StringLiteral,
    StringOperator,
    parse_altrql,
)


def test_parse_implicit_and_commas():
    query = """
    GET users WHERE {
        is_active = TRUE,
        age >= 18
    };
    """
    ir = parse_altrql(query)
    assert isinstance(ir.where, LogicalExpression)
    assert ir.where.operator == LogicalOperator.AND
    assert ir.where.left.field.full_path == "is_active"
    assert ir.where.left.operand.value is True
    assert ir.where.right.field.full_path == "age"
    assert ir.where.right.operand.value == 18


def test_parse_explicit_and_keyword():
    query = """
    GET users WHERE {
        is_active = TRUE AND age >= 18
    };
    """
    ir = parse_altrql(query)
    assert isinstance(ir.where, LogicalExpression)
    assert ir.where.operator == LogicalOperator.AND
    assert ir.where.left.field.full_path == "is_active"
    assert ir.where.right.field.full_path == "age"


def test_parse_explicit_or_keyword():
    query = """
    GET users WHERE {
        role = "admin" OR role = "superadmin"
    };
    """
    ir = parse_altrql(query)
    assert isinstance(ir.where, LogicalExpression)
    assert ir.where.operator == LogicalOperator.OR
    assert ir.where.left.field.full_path == "role"
    assert ir.where.left.operand.value == "admin"
    assert ir.where.right.field.full_path == "role"
    assert ir.where.right.operand.value == "superadmin"


def test_parse_mixed_explicit_or_and_grouped_conditions():
    query = """
    GET users WHERE {
        role = "admin" OR {
            is_active = TRUE,
            age >= 18
        }
    };
    """
    ir = parse_altrql(query)
    assert isinstance(ir.where, LogicalExpression)
    assert ir.where.operator == LogicalOperator.OR
    assert ir.where.left.field.full_path == "role"

    right_and = ir.where.right
    assert isinstance(right_and, LogicalExpression)
    assert right_and.operator == LogicalOperator.AND
    assert right_and.left.field.full_path == "is_active"
    assert right_and.right.field.full_path == "age"


def test_parse_multiple_grouped_branches():
    query = """
    GET users WHERE {
        {
            is_active = TRUE,
            age >= 18
        } OR {
            role = "admin",
            verified = TRUE
        }
    };
    """
    ir = parse_altrql(query)
    assert isinstance(ir.where, LogicalExpression)
    assert ir.where.operator == LogicalOperator.OR

    left_branch = ir.where.left
    assert isinstance(left_branch, LogicalExpression)
    assert left_branch.operator == LogicalOperator.AND
    assert left_branch.left.field.full_path == "is_active"
    assert left_branch.right.field.full_path == "age"

    right_branch = ir.where.right
    assert isinstance(right_branch, LogicalExpression)
    assert right_branch.operator == LogicalOperator.AND
    assert right_branch.left.field.full_path == "role"
    assert right_branch.right.field.full_path == "verified"


def test_parse_grouped_negation():
    query = """
    GET users WHERE {
        NOT {
            is_active = FALSE,
            verified = FALSE
        }
    };
    """
    ir = parse_altrql(query)
    assert isinstance(ir.where, NegationExpression)
    assert isinstance(ir.where.operand, LogicalExpression)
    assert ir.where.operand.operator == LogicalOperator.AND
    assert ir.where.operand.left.field.full_path == "is_active"
    assert ir.where.operand.right.field.full_path == "verified"


def test_parse_dedicated_not_has():
    query = 'GET users WHERE { tags NOT HAS "premium" };'
    ir = parse_altrql(query)
    assert isinstance(ir.where, FieldExpression)
    assert ir.where.field.full_path == "tags"
    assert ir.where.operator == StringOperator.NOT_HAS
    assert ir.where.operand.value == "premium"


def test_parse_grouped_negation_of_has():
    query = 'GET users WHERE { NOT { tags HAS "premium" } };'
    ir = parse_altrql(query)
    assert isinstance(ir.where, NegationExpression)
    assert isinstance(ir.where.operand, FieldExpression)
    assert ir.where.operand.field.full_path == "tags"
    assert ir.where.operand.operator == StringOperator.HAS
    assert ir.where.operand.operand.value == "premium"


def test_parse_operator_precedence_or_and():
    query = "GET users WHERE { a = 1 OR b = 2 AND c = 3 };"
    ir = parse_altrql(query)
    # Expected: OR(a=1, AND(b=2, c=3))
    assert isinstance(ir.where, LogicalExpression)
    assert ir.where.operator == LogicalOperator.OR
    assert ir.where.left.field.full_path == "a"
    assert isinstance(ir.where.right, LogicalExpression)
    assert ir.where.right.operator == LogicalOperator.AND
    assert ir.where.right.left.field.full_path == "b"
    assert ir.where.right.right.field.full_path == "c"


def test_parse_operator_precedence_grouping_overrides():
    query = "GET users WHERE { { a = 1 OR b = 2 }, c = 3 };"
    ir = parse_altrql(query)
    # Expected: AND(OR(a=1, b=2), c=3)
    assert isinstance(ir.where, LogicalExpression)
    assert ir.where.operator == LogicalOperator.AND
    assert isinstance(ir.where.left, LogicalExpression)
    assert ir.where.left.operator == LogicalOperator.OR
    assert ir.where.left.left.field.full_path == "a"
    assert ir.where.left.right.field.full_path == "b"
    assert ir.where.right.field.full_path == "c"


def test_parse_rejects_empty_where_block():
    with pytest.raises(AltrQueryParseError) as exc_info:
        parse_altrql("GET users WHERE {};")
    assert "WHERE block cannot be empty" in str(exc_info.value)


def test_parse_rejects_empty_condition_group():
    with pytest.raises(AltrQueryParseError) as exc_info:
        parse_altrql("GET users WHERE { {} };")
    assert "Condition group '{ }' cannot be empty" in str(exc_info.value)


def test_parse_rejects_dangling_or():
    with pytest.raises(AltrQueryParseError) as exc_info:
        parse_altrql("GET users WHERE { a = 1 OR };")
    assert "Expected expression after 'OR'" in str(exc_info.value)


def test_parse_rejects_dangling_and():
    with pytest.raises(AltrQueryParseError) as exc_info:
        parse_altrql("GET users WHERE { a = 1 AND };")
    assert "Expected expression after 'AND'" in str(exc_info.value)


def test_parse_rejects_dangling_not():
    with pytest.raises(AltrQueryParseError) as exc_info:
        parse_altrql("GET users WHERE { NOT };")
    assert "Expected expression after 'NOT'" in str(exc_info.value)


def test_parse_rejects_trailing_comma_in_where():
    with pytest.raises(AltrQueryParseError) as exc_info:
        parse_altrql("GET users WHERE { a = 1, };")
    assert "Unexpected trailing comma in WHERE block" in str(exc_info.value)


def test_parse_rejects_invalid_comparison_operand_structure():
    with pytest.raises(AltrQueryParseError) as exc_info:
        parse_altrql("GET users WHERE { age >= {18..20} };")
    assert "cannot accept a value set or group" in str(exc_info.value)
