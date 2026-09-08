"""Unit tests for AltrQL IR Normalizer (normalize_ir).

Tests expression tree preservation, negation normalization, structure preservation,
idempotence, and determinism.
"""

from altr_stream.query_engine.domain.ast import (
    AltrQueryIR,
    ComparisonConstraint,
    CompoundAndConstraint,
    FieldExpression,
    FieldPath,
    FieldSelection,
    IntegerLiteral,
    LogicalExpression,
    LogicalOperator,
    NegationExpression,
    Range,
    StringLiteral,
    ValueSet,
)
from altr_stream.query_engine.domain.operators import ComparisonOperator
from altr_stream.query_engine.parser import parse_altrql
from altr_stream.query_engine.semantic.normalizer import normalize_ir


def _make_field_expr(name: str, val: int) -> FieldExpression:
    return FieldExpression(
        field=FieldPath(segments=[name]),
        operator=ComparisonOperator.EQ,
        operand=IntegerLiteral(value=val),
    )


def test_normalizer_preserves_field_expression():
    """Test normalizing an atomic field expression."""
    expr = _make_field_expr("age", 25)
    ir = AltrQueryIR(
        entity="users",
        where=expr,
    )
    normalized = normalize_ir(ir)
    assert isinstance(normalized.where, FieldExpression)
    assert normalized.where.field.full_path == "age"
    assert normalized.where.operand.value == 25


def test_normalizer_preserves_negation_expression():
    """Test normalizing a NegationExpression."""
    expr = _make_field_expr("is_active", 0)
    ir = AltrQueryIR(
        entity="users",
        where=NegationExpression(operand=expr),
    )
    normalized = normalize_ir(ir)
    assert isinstance(normalized.where, NegationExpression)
    assert isinstance(normalized.where.operand, FieldExpression)
    assert normalized.where.operand.field.full_path == "is_active"


def test_normalizer_preserves_nested_logical_expression_tree():
    """Test normalizing a binary LogicalExpression tree."""
    a = _make_field_expr("a", 1)
    b = _make_field_expr("b", 2)
    c = _make_field_expr("c", 3)

    inner_and = LogicalExpression(operator=LogicalOperator.AND, left=a, right=b)
    root_or = LogicalExpression(operator=LogicalOperator.OR, left=inner_and, right=c)

    ir = AltrQueryIR(
        entity="users",
        where=root_or,
    )
    normalized = normalize_ir(ir)
    assert isinstance(normalized.where, LogicalExpression)
    assert normalized.where.operator == LogicalOperator.OR
    assert isinstance(normalized.where.left, LogicalExpression)
    assert normalized.where.left.operator == LogicalOperator.AND
    assert normalized.where.left.left.field.full_path == "a"
    assert normalized.where.left.right.field.full_path == "b"
    assert normalized.where.right.field.full_path == "c"


def test_normalizer_preserves_value_sets_and_constraints_as_is():
    """Test that ValueSet, Range, and CompoundAndConstraint are preserved without lowering."""
    query = """
    GET users WHERE {
        id = {1, 2, 6..10},
        age = {>=18 & <=60}
    };
    """
    ir = parse_altrql(query)
    assert isinstance(ir.where, LogicalExpression)
    assert ir.where.operator == LogicalOperator.AND

    first_op = ir.where.left
    assert isinstance(first_op, FieldExpression)
    assert isinstance(first_op.operand, ValueSet)
    assert len(first_op.operand.elements) == 3
    assert isinstance(first_op.operand.elements[2], Range)

    second_op = ir.where.right
    assert isinstance(second_op, FieldExpression)
    assert isinstance(second_op.operand, ValueSet)
    assert len(second_op.operand.elements) == 1
    assert isinstance(second_op.operand.elements[0], CompoundAndConstraint)
    assert len(second_op.operand.elements[0].constraints) == 2


def test_normalizer_idempotence_and_determinism():
    """Test that normalize_ir is idempotent: normalize(normalize(ir)) == normalize(ir)."""
    query = """
    GET users (id, name AS uname) WHERE {
        age = 25 OR score = 100,
        status = "ACTIVE"
    } TOP 10 BY age OFFSET 0;
    """
    ir = parse_altrql(query)
    norm1 = normalize_ir(ir)
    norm2 = normalize_ir(norm1)
    assert norm1.to_dict() == norm2.to_dict()
    assert norm1 == norm2
