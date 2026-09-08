"""Unit tests for AltrQL v0.3 Advanced Conditional Logic & Expression Grouping Semantic Validator."""

import pytest

from altr_stream.query_engine import (
    AltrQueryIR,
    AltrQuerySemanticError,
    ComparisonOperator,
    FieldExpression,
    FieldPath,
    IntegerLiteral,
    LogicalExpression,
    LogicalOperator,
    NegationExpression,
    QueryOperation,
    StringLiteral,
    parse_altrql,
    validate_ir,
)


def test_validator_accepts_valid_logical_and_negation_expressions():
    query = """
    GET users WHERE {
        NOT { is_active = FALSE },
        { age >= 18 OR role = "admin" }
    };
    """
    ir = parse_altrql(query)
    validate_ir(ir)


def test_validator_rejects_missing_left_operand_in_logical_expression():
    ir = AltrQueryIR.model_construct(
        operation=QueryOperation.READ,
        entity="users",
        where=LogicalExpression.model_construct(
            operator=LogicalOperator.AND,
            left=None,
            right=FieldExpression(
                field=FieldPath(segments=["age"]),
                operator=ComparisonOperator.EQ,
                operand=IntegerLiteral(value=18),
            ),
        ),
        projection=[],
        assignments=[],
        sort=[],
        ranking=None,
        offset=None,
    )
    with pytest.raises(AltrQuerySemanticError) as exc_info:
        validate_ir(ir)
    assert "LogicalExpression requires both left and right operand expressions" in exc_info.value.message


def test_validator_rejects_missing_right_operand_in_logical_expression():
    ir = AltrQueryIR.model_construct(
        operation=QueryOperation.READ,
        entity="users",
        where=LogicalExpression.model_construct(
            operator=LogicalOperator.OR,
            left=FieldExpression(
                field=FieldPath(segments=["age"]),
                operator=ComparisonOperator.EQ,
                operand=IntegerLiteral(value=18),
            ),
            right=None,
        ),
        projection=[],
        assignments=[],
        sort=[],
        ranking=None,
        offset=None,
    )
    with pytest.raises(AltrQuerySemanticError) as exc_info:
        validate_ir(ir)
    assert "LogicalExpression requires both left and right operand expressions" in exc_info.value.message


def test_validator_rejects_missing_operand_in_negation_expression():
    ir = AltrQueryIR.model_construct(
        operation=QueryOperation.READ,
        entity="users",
        where=NegationExpression.model_construct(
            operand=None,
        ),
        projection=[],
        assignments=[],
        sort=[],
        ranking=None,
        offset=None,
    )
    with pytest.raises(AltrQuerySemanticError) as exc_info:
        validate_ir(ir)
    assert "NegationExpression requires an operand expression" in exc_info.value.message


def test_validator_validates_where_on_update_mutation():
    query = """
    UPDATE users (
        is_active: FALSE
    ) WHERE {
        role = "guest" OR age < 18
    };
    """
    ir = parse_altrql(query)
    validate_ir(ir)
    assert ir.operation == QueryOperation.UPDATE
    assert isinstance(ir.where, LogicalExpression)


def test_validator_validates_where_on_delete_mutation():
    query = """
    DELETE users WHERE {
        NOT { is_active = TRUE },
        created_at <= @2020-01-01
    };
    """
    ir = parse_altrql(query)
    validate_ir(ir)
    assert ir.operation == QueryOperation.DELETE
    assert isinstance(ir.where, LogicalExpression)
