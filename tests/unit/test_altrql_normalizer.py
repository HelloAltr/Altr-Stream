"""Unit tests for AltrQL IR Normalizer (normalize_ir).

Tests single-operand collapsing, same-operator flattening, structure preservation,
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


def test_normalizer_single_operand_and_collapse():
    """Test collapsing LogicalExpression with single operand into inner expression."""
    expr = _make_field_expr("age", 25)
    ir = AltrQueryIR(
        entity="users",
        where=LogicalExpression(operator="AND", operands=[expr]),
    )
    normalized = normalize_ir(ir)
    assert isinstance(normalized.where, FieldExpression)
    assert normalized.where.field.full_path == "age"
    assert normalized.where.operand.value == 25


def test_normalizer_single_operand_or_collapse():
    """Test collapsing LogicalExpression(OR, [A]) into A."""
    expr = _make_field_expr("role", 1)
    ir = AltrQueryIR(
        entity="users",
        where=LogicalExpression(operator="OR", operands=[expr]),
    )
    normalized = normalize_ir(ir)
    assert isinstance(normalized.where, FieldExpression)
    assert normalized.where.field.full_path == "role"


def test_normalizer_nested_single_operand_collapse():
    """Test recursive collapse of nested single-operand logical expressions."""
    inner = _make_field_expr("status", 1)
    ir = AltrQueryIR(
        entity="users",
        where=LogicalExpression(
            operator="AND",
            operands=[
                LogicalExpression(
                    operator="OR",
                    operands=[
                        LogicalExpression(operator="AND", operands=[inner])
                    ],
                )
            ],
        ),
    )
    normalized = normalize_ir(ir)
    assert isinstance(normalized.where, FieldExpression)
    assert normalized.where.field.full_path == "status"


def test_normalizer_flatten_same_operator_and():
    """Test flattening AND(A, AND(B, C), D) -> AND(A, B, C, D)."""
    a = _make_field_expr("a", 1)
    b = _make_field_expr("b", 2)
    c = _make_field_expr("c", 3)
    d = _make_field_expr("d", 4)

    ir = AltrQueryIR(
        entity="users",
        where=LogicalExpression(
            operator="AND",
            operands=[
                a,
                LogicalExpression(operator="AND", operands=[b, c]),
                d,
            ],
        ),
    )
    normalized = normalize_ir(ir)
    assert isinstance(normalized.where, LogicalExpression)
    assert normalized.where.operator == "AND"
    assert len(normalized.where.operands) == 4
    paths = [op.field.full_path for op in normalized.where.operands]
    assert paths == ["a", "b", "c", "d"]


def test_normalizer_flatten_same_operator_or():
    """Test flattening OR(OR(A, B), OR(C, D)) -> OR(A, B, C, D)."""
    a = _make_field_expr("a", 1)
    b = _make_field_expr("b", 2)
    c = _make_field_expr("c", 3)
    d = _make_field_expr("d", 4)

    ir = AltrQueryIR(
        entity="users",
        where=LogicalExpression(
            operator="OR",
            operands=[
                LogicalExpression(operator="OR", operands=[a, b]),
                LogicalExpression(operator="OR", operands=[c, d]),
            ],
        ),
    )
    normalized = normalize_ir(ir)
    assert isinstance(normalized.where, LogicalExpression)
    assert normalized.where.operator == "OR"
    assert len(normalized.where.operands) == 4
    paths = [op.field.full_path for op in normalized.where.operands]
    assert paths == ["a", "b", "c", "d"]


def test_normalizer_preserves_mixed_operator_hierarchy():
    """Test that AND(A, OR(B, C)) is strictly preserved without flattening across operators."""
    a = _make_field_expr("a", 1)
    b = _make_field_expr("b", 2)
    c = _make_field_expr("c", 3)

    ir = AltrQueryIR(
        entity="users",
        where=LogicalExpression(
            operator="AND",
            operands=[
                a,
                LogicalExpression(operator="OR", operands=[b, c]),
            ],
        ),
    )
    normalized = normalize_ir(ir)
    assert isinstance(normalized.where, LogicalExpression)
    assert normalized.where.operator == "AND"
    assert len(normalized.where.operands) == 2
    assert isinstance(normalized.where.operands[1], LogicalExpression)
    assert normalized.where.operands[1].operator == "OR"
    assert len(normalized.where.operands[1].operands) == 2


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
    assert ir.where.operator == "AND"
    assert len(ir.where.operands) == 2

    first_op = ir.where.operands[0]
    assert isinstance(first_op.operand, ValueSet)
    assert len(first_op.operand.elements) == 3
    assert isinstance(first_op.operand.elements[2], Range)

    second_op = ir.where.operands[1]
    assert isinstance(second_op.operand, ValueSet)
    assert len(second_op.operand.elements) == 1
    assert isinstance(second_op.operand.elements[0], CompoundAndConstraint)
    assert len(second_op.operand.elements[0].constraints) == 2


def test_normalizer_idempotence_and_determinism():
    """Test that normalize_ir is idempotent: normalize(normalize(ir)) == normalize(ir)."""
    query = """
    GET users (id, name AS uname) WHERE {
        age = {18..65} OR score = 100,
        status = "ACTIVE"
    } TOP 10 BY age OFFSET 0;
    """
    ir = parse_altrql(query)
    norm1 = normalize_ir(ir)
    norm2 = normalize_ir(norm1)
    assert norm1.to_dict() == norm2.to_dict()
    assert norm1 == norm2
