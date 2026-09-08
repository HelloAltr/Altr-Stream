"""Unit tests for AltrQL v0.4 batch / grouped CREATE parser."""

import pytest

from altr_stream.query_engine import (
    AltrQueryIR,
    AltrQueryParseError,
    BooleanLiteral,
    CreateRecord,
    FieldPath,
    IntegerLiteral,
    MutationAssignment,
    NullLiteral,
    QueryOperation,
    StringLiteral,
    TemporalLiteral,
    parse_altrql,
)


def test_parser_single_record_create_backward_compatibility():
    """Single-record CREATE syntax remains valid and parses into exactly one CreateRecord."""
    query = 'CREATE users ( email: "alice@example.com", full_name: "Alice", is_active: TRUE );'
    ir = parse_altrql(query)

    assert ir.operation == QueryOperation.CREATE
    assert ir.entity == "users"
    assert len(ir.records) == 1
    assert len(ir.records[0].assignments) == 3

    assert ir.records[0].assignments[0].field.segments == ["email"]
    assert ir.records[0].assignments[0].value == StringLiteral(value="alice@example.com")
    assert ir.records[0].assignments[1].field.segments == ["full_name"]
    assert ir.records[0].assignments[1].value == StringLiteral(value="Alice")
    assert ir.records[0].assignments[2].field.segments == ["is_active"]
    assert ir.records[0].assignments[2].value == BooleanLiteral(value=True)


def test_parser_batch_create_two_records():
    """Two-record batch CREATE parses into ordered list of two CreateRecord objects."""
    query = """
    CREATE users (
        ( email: "alice@example.com", name: "Alice" ),
        ( email: "bob@example.com", name: "Bob" )
    );
    """
    ir = parse_altrql(query)

    assert ir.operation == QueryOperation.CREATE
    assert ir.entity == "users"
    assert len(ir.records) == 2

    # Record 1
    assert len(ir.records[0].assignments) == 2
    assert ir.records[0].assignments[0].field.segments == ["email"]
    assert ir.records[0].assignments[0].value == StringLiteral(value="alice@example.com")
    assert ir.records[0].assignments[1].field.segments == ["name"]
    assert ir.records[0].assignments[1].value == StringLiteral(value="Alice")

    # Record 2
    assert len(ir.records[1].assignments) == 2
    assert ir.records[1].assignments[0].field.segments == ["email"]
    assert ir.records[1].assignments[0].value == StringLiteral(value="bob@example.com")
    assert ir.records[1].assignments[1].field.segments == ["name"]
    assert ir.records[1].assignments[1].value == StringLiteral(value="Bob")


def test_parser_batch_create_multiple_records_with_diverse_literals():
    """Multiple batch records with numbers, booleans, nulls, and temporals."""
    query = """
    CREATE employees (
        ( name: "Alice", age: 30, salary: 120000.50, is_active: TRUE ),
        ( name: "Bob", age: 40, salary: 150000.00, is_active: FALSE ),
        ( name: "Carol", age: 25, salary: 90000.00, is_active: TRUE, hire_date: @2026-09-08, note: NULL )
    );
    """
    ir = parse_altrql(query)

    assert ir.operation == QueryOperation.CREATE
    assert ir.entity == "employees"
    assert len(ir.records) == 3

    assert len(ir.records[0].assignments) == 4
    assert len(ir.records[1].assignments) == 4
    assert len(ir.records[2].assignments) == 6

    assert ir.records[2].assignments[4].field.segments == ["hire_date"]
    assert isinstance(ir.records[2].assignments[4].value, TemporalLiteral)
    assert ir.records[2].assignments[4].value.value == "2026-09-08"

    assert ir.records[2].assignments[5].field.segments == ["note"]
    assert isinstance(ir.records[2].assignments[5].value, NullLiteral)


def test_parser_empty_batch_rejected():
    """Empty batch `CREATE users ();` must be rejected."""
    query = "CREATE users ();"
    with pytest.raises(AltrQueryParseError) as exc_info:
        parse_altrql(query)
    assert "empty" in exc_info.value.message.lower()


def test_parser_empty_record_in_batch_rejected():
    """Empty record `CREATE users ( () );` must be rejected."""
    query = "CREATE users ( () );"
    with pytest.raises(AltrQueryParseError) as exc_info:
        parse_altrql(query)
    assert "empty" in exc_info.value.message.lower()


def test_parser_trailing_comma_in_batch_rejected():
    """Trailing comma in batch payload `( (a: 1), );` must be rejected."""
    query = 'CREATE users ( ( name: "Alice" ), );'
    with pytest.raises(AltrQueryParseError) as exc_info:
        parse_altrql(query)
    assert "trailing comma" in exc_info.value.message.lower()


def test_parser_trailing_comma_in_record_rejected():
    """Trailing comma inside a record `( (a: 1,), (a: 2) );` must be rejected."""
    query = 'CREATE users ( ( name: "Alice", ), ( name: "Bob" ) );'
    with pytest.raises(AltrQueryParseError) as exc_info:
        parse_altrql(query)
    assert "trailing comma" in exc_info.value.message.lower()


def test_parser_mixed_syntax_single_then_batch_rejected():
    """Mixing single-record and batch-record syntax `( name: "Alice", (name: "Bob") );` is rejected."""
    query = 'CREATE users ( name: "Alice", ( name: "Bob" ) );'
    with pytest.raises(AltrQueryParseError) as exc_info:
        parse_altrql(query)
    assert "cannot mix" in exc_info.value.message.lower() or "mix" in exc_info.value.message.lower()


def test_parser_mixed_syntax_batch_then_single_rejected():
    """Mixing batch-record and single-record syntax `( (name: "Alice"), name: "Bob" );` is rejected."""
    query = 'CREATE users ( ( name: "Alice" ), name: "Bob" );'
    with pytest.raises(AltrQueryParseError) as exc_info:
        parse_altrql(query)
    assert "cannot mix" in exc_info.value.message.lower() or "mix" in exc_info.value.message.lower()


def test_parser_missing_comma_separator_between_records_rejected():
    """Missing comma separator between records `( (a: 1) (a: 2) );` is rejected."""
    query = 'CREATE users ( ( name: "Alice" ) ( name: "Bob" ) );'
    with pytest.raises(AltrQueryParseError) as exc_info:
        parse_altrql(query)
    assert "expected ','" in exc_info.value.message.lower() or "comma" in exc_info.value.message.lower()


def test_parser_batch_create_with_where_rejected():
    """Batch CREATE cannot have a WHERE clause."""
    query = 'CREATE users ( ( name: "Alice" ), ( name: "Bob" ) ) WHERE { id = 1 };'
    with pytest.raises(AltrQueryParseError) as exc_info:
        parse_altrql(query)
    assert "where" in exc_info.value.message.lower()


def test_parser_batch_create_with_sort_rejected():
    """Batch CREATE cannot have a SORT clause."""
    query = 'CREATE users ( ( name: "Alice" ), ( name: "Bob" ) ) SORT { name ASC };'
    with pytest.raises(AltrQueryParseError) as exc_info:
        parse_altrql(query)
    assert "sort" in exc_info.value.message.lower()


def test_parser_batch_create_duplicate_field_in_record_rejected():
    """Duplicate field inside a single record must be rejected."""
    query = 'CREATE users ( ( name: "Alice", name: "Bob" ) );'
    with pytest.raises(AltrQueryParseError) as exc_info:
        parse_altrql(query)
    assert "duplicate" in exc_info.value.message.lower()
