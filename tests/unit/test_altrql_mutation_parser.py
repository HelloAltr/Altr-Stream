"""Unit tests for AltrQL v0.2 mutation parser."""

import pytest

from altr_stream.query_engine import (
    AltrQueryError,
    AltrQueryIR,
    AltrQueryParseError,
    FieldPath,
    MutationAssignment,
    QueryOperation,
    StringLiteral,
    IntegerLiteral,
    BooleanLiteral,
    parse_altrql,
)


def test_parse_create_basic():
    """Test parsing a valid CREATE statement."""
    q = 'CREATE users ( username: "alice", email: "alice@example.com", age: 25 );'
    ir = parse_altrql(q)

    assert ir.operation == QueryOperation.CREATE
    assert ir.entity == "users"
    assert len(ir.assignments) == 3
    assert ir.assignments[0] == MutationAssignment(field=FieldPath(segments=["username"]), value=StringLiteral(value="alice"))
    assert ir.assignments[1] == MutationAssignment(field=FieldPath(segments=["email"]), value=StringLiteral(value="alice@example.com"))
    assert ir.assignments[2] == MutationAssignment(field=FieldPath(segments=["age"]), value=IntegerLiteral(value=25))
    assert ir.where is None
    assert ir.sort == []
    assert ir.ranking is None
    assert ir.offset is None


def test_parse_update_with_where():
    """Test parsing an UPDATE statement with a WHERE filter."""
    q = 'UPDATE users ( email: "new@example.com", is_active: TRUE ) WHERE { id = 1 };'
    ir = parse_altrql(q)

    assert ir.operation == QueryOperation.UPDATE
    assert ir.entity == "users"
    assert len(ir.assignments) == 2
    assert ir.assignments[0] == MutationAssignment(field=FieldPath(segments=["email"]), value=StringLiteral(value="new@example.com"))
    assert ir.assignments[1] == MutationAssignment(field=FieldPath(segments=["is_active"]), value=BooleanLiteral(value=True))
    assert ir.where is not None


def test_parse_update_without_where():
    """Test parsing a mass UPDATE statement without WHERE clause."""
    q = "UPDATE users ( is_active: FALSE );"
    ir = parse_altrql(q)

    assert ir.operation == QueryOperation.UPDATE
    assert ir.entity == "users"
    assert len(ir.assignments) == 1
    assert ir.assignments[0] == MutationAssignment(field=FieldPath(segments=["is_active"]), value=BooleanLiteral(value=False))
    assert ir.where is None


def test_parse_delete_with_where():
    """Test parsing a constrained DELETE statement with WHERE filter."""
    q = "DELETE users WHERE { id = 42 };"
    ir = parse_altrql(q)

    assert ir.operation == QueryOperation.DELETE
    assert ir.entity == "users"
    assert ir.assignments == []
    assert ir.where is not None


def test_parse_delete_without_where():
    """Test parsing an unconstrained mass DELETE statement."""
    q = "DELETE users;"
    ir = parse_altrql(q)

    assert ir.operation == QueryOperation.DELETE
    assert ir.entity == "users"
    assert ir.assignments == []
    assert ir.where is None


def test_parse_create_with_where_rejected():
    """CREATE cannot have a WHERE clause."""
    q = 'CREATE users ( username: "alice" ) WHERE { id = 1 };'
    with pytest.raises(AltrQueryParseError) as exc_info:
        parse_altrql(q)
    assert "unexpected" in exc_info.value.message.lower() or "where" in exc_info.value.message.lower()


def test_parse_create_with_sort_rejected():
    """CREATE cannot have SORT."""
    q = 'CREATE users ( username: "alice" ) SORT { username ASC };'
    with pytest.raises(AltrQueryParseError) as exc_info:
        parse_altrql(q)
    assert "unexpected" in exc_info.value.message.lower() or "sort" in exc_info.value.message.lower()


def test_parse_delete_with_payload_rejected():
    """DELETE cannot have an assignment payload."""
    q = 'DELETE users ( id: 1 ) WHERE { id = 1 };'
    with pytest.raises(AltrQueryParseError):
        parse_altrql(q)


def test_parse_mutation_missing_semicolon():
    """Mutations must end with a semicolon."""
    q = 'CREATE users ( username: "alice" )'
    with pytest.raises(AltrQueryParseError) as exc_info:
        parse_altrql(q)
    assert "semicolon" in exc_info.value.message.lower() or "expected ';'" in exc_info.value.message.lower()


def test_parse_mutation_empty_payload_rejected():
    """Mutation payloads must not be empty."""
    q = "CREATE users ();"
    with pytest.raises(AltrQueryParseError):
        parse_altrql(q)


def test_parse_mutation_missing_colon():
    """Assignments require field: value syntax."""
    q = 'CREATE users ( username "alice" );'
    with pytest.raises(AltrQueryParseError):
        parse_altrql(q)
