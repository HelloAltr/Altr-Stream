"""Unit tests for AltrQL v0.4 semantic validation and normalization on batch CREATE."""

import pytest

from altr_stream.query_engine.domain.ast import (
    AltrQueryIR,
    CreateRecord,
    FieldPath,
    FieldSelection,
    IntegerLiteral,
    LogicalExpression,
    MutationAssignment,
    QueryOperation,
    StringLiteral,
)
from altr_stream.query_engine.domain.errors import AltrQuerySemanticError
from altr_stream.query_engine.parser import parse_altrql
from altr_stream.query_engine.semantic.normalizer import normalize_ir
from altr_stream.query_engine.semantic.validator import validate_ir


def test_validator_accepts_valid_homogeneous_batch():
    """Homogeneous batch CREATE passes validation."""
    query = """
    CREATE users (
        (name: "Alice", email: "alice@example.com"),
        (name: "Bob", email: "bob@example.com")
    );
    """
    ir = parse_altrql(query)
    validate_ir(ir)
    assert len(ir.records) == 2


def test_validator_accepts_valid_heterogeneous_batch():
    """Heterogeneous batch CREATE with differing field shapes passes validation."""
    query = """
    CREATE users (
        (name: "Alice", email: "alice@example.com"),
        (name: "Bob", department: "Engineering"),
        (name: "Carol", email: "carol@example.com", age: 30)
    );
    """
    ir = parse_altrql(query)
    validate_ir(ir)
    assert len(ir.records) == 3


def test_validator_rejects_duplicate_field_within_batch_record():
    """Duplicate field inside a single record in a batch must be rejected."""
    ir = AltrQueryIR(
        operation=QueryOperation.CREATE,
        entity="users",
        records=[
            CreateRecord(
                assignments=[
                    MutationAssignment(field=FieldPath(segments=["name"]), value=StringLiteral(value="Alice")),
                    MutationAssignment(field=FieldPath(segments=["name"]), value=StringLiteral(value="Alicia")),
                ]
            ),
            CreateRecord(
                assignments=[
                    MutationAssignment(field=FieldPath(segments=["name"]), value=StringLiteral(value="Bob")),
                ]
            ),
        ],
    )
    with pytest.raises(AltrQuerySemanticError) as exc_info:
        validate_ir(ir)
    assert "duplicate" in exc_info.value.message.lower()


def test_validator_rejects_batch_with_empty_record():
    """A record with no assignments within a batch must be rejected."""
    ir = AltrQueryIR(
        operation=QueryOperation.CREATE,
        entity="users",
        records=[
            CreateRecord(
                assignments=[
                    MutationAssignment(field=FieldPath(segments=["name"]), value=StringLiteral(value="Alice")),
                ]
            ),
            CreateRecord(assignments=[]),
        ],
    )
    with pytest.raises(AltrQuerySemanticError) as exc_info:
        validate_ir(ir)
    assert "empty" in exc_info.value.message.lower()


def test_validator_rejects_batch_create_with_where_clause():
    """CREATE cannot have a WHERE filter even in batch mode."""
    from altr_stream.query_engine.domain.ast import FieldExpression, ComparisonOperator
    ir = AltrQueryIR(
        operation=QueryOperation.CREATE,
        entity="users",
        records=[
            CreateRecord(
                assignments=[
                    MutationAssignment(field=FieldPath(segments=["name"]), value=StringLiteral(value="Alice")),
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
    assert "where" in exc_info.value.message.lower()


def test_normalizer_normalizes_batch_records():
    """Normalizer processes every record in a batch IR."""
    query = """
    CREATE users (
        (name: "Alice", email: "alice@example.com"),
        (name: "Bob", email: "bob@example.com")
    );
    """
    ir = parse_altrql(query)
    normalized = normalize_ir(ir)
    assert len(normalized.records) == 2
    assert normalized.records[0].assignments[0].field.segments == ["name"]
    assert normalized.records[1].assignments[0].field.segments == ["name"]
