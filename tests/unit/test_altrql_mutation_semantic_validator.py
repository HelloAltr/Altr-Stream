"""Unit tests for AltrQL v0.2 semantic validation and normalization on mutations."""

import pytest

from altr_stream.query_engine.domain.ast import (
    AltrQueryIR,
    FieldPath,
    FieldSelection,
    IntegerLiteral,
    MutationAssignment,
    QueryOperation,
    StringLiteral,
)
from altr_stream.query_engine.domain.errors import AltrQuerySemanticError
from altr_stream.query_engine.semantic.validator import validate_ir


def test_validator_rejects_duplicate_mutation_assignments():
    """Duplicate field assignments in CREATE/UPDATE must be rejected."""
    ir = AltrQueryIR(
        operation=QueryOperation.CREATE,
        entity="users",
        assignments=[
            MutationAssignment(field=FieldPath(segments=["username"]), value=StringLiteral(value="alice")),
            MutationAssignment(field=FieldPath(segments=["username"]), value=StringLiteral(value="bob")),
        ],
    )
    with pytest.raises(AltrQuerySemanticError) as exc_info:
        validate_ir(ir)
    assert "duplicate" in exc_info.value.message.lower()


def test_validator_rejects_create_without_assignments():
    """CREATE must have non-empty assignments."""
    ir = AltrQueryIR(
        operation=QueryOperation.CREATE,
        entity="users",
        assignments=[],
    )
    with pytest.raises(AltrQuerySemanticError) as exc_info:
        validate_ir(ir)
    assert "assignment" in exc_info.value.message.lower()


def test_validator_rejects_update_without_assignments():
    """UPDATE must have non-empty assignments."""
    ir = AltrQueryIR(
        operation=QueryOperation.UPDATE,
        entity="users",
        assignments=[],
    )
    with pytest.raises(AltrQuerySemanticError) as exc_info:
        validate_ir(ir)
    assert "assignment" in exc_info.value.message.lower()


def test_validator_rejects_delete_with_assignments():
    """DELETE cannot have assignments."""
    ir = AltrQueryIR(
        operation=QueryOperation.DELETE,
        entity="users",
        assignments=[MutationAssignment(field=FieldPath(segments=["id"]), value=IntegerLiteral(value=1))],
    )
    with pytest.raises(AltrQuerySemanticError) as exc_info:
        validate_ir(ir)
    assert "assignment" in exc_info.value.message.lower()


def test_validator_rejects_mutation_with_projection():
    """Mutations cannot specify field projections."""
    ir = AltrQueryIR(
        operation=QueryOperation.CREATE,
        entity="users",
        projection=[FieldSelection(path=FieldPath(segments=["id"]))],
        assignments=[MutationAssignment(field=FieldPath(segments=["username"]), value=StringLiteral(value="alice"))],
    )
    with pytest.raises(AltrQuerySemanticError) as exc_info:
        validate_ir(ir)
    assert "projection" in exc_info.value.message.lower()
