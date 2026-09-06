"""Unit tests for Query Playground SQL-aware query validation."""

import pytest
from altr_stream.domain.errors import ReadOnlyQueryRequiredError
from altr_stream.domain.query_validation import (
    split_sql_statements,
    strip_sql_comments,
    validate_query,
    validate_read_only_query,
)


def test_strip_sql_comments():
    sql = """
    -- This is a single line comment
    SELECT * /* inline comment */
    FROM users -- another comment
    /*
      multi-line
      comment
    */
    WHERE id = 1;
    """
    stripped = strip_sql_comments(sql)
    assert "--" not in stripped
    assert "/*" not in stripped
    assert "SELECT *" in stripped
    assert "WHERE id = 1;" in stripped


@pytest.mark.parametrize(
    "query,expected_count",
    [
        ("SELECT * FROM users", 1),
        ("SELECT * FROM users;", 1),
        ("SELECT 1; SELECT 2;", 2),
        ("SELECT * FROM users WHERE name = 'foo;bar';", 1),
        ('SELECT "col;name" FROM users;', 1),
        ("-- comment; with semicolon\nSELECT * FROM users; /* block; comment */", 1),
        ("CREATE FUNCTION f() RETURNS void AS $$ BEGIN SELECT 1; END; $$ LANGUAGE plpgsql;", 1),
    ],
)
def test_split_sql_statements(query: str, expected_count: int):
    stmts = split_sql_statements(query)
    assert len(stmts) == expected_count


@pytest.mark.parametrize(
    "query",
    [
        "SELECT * FROM users",
        "SELECT id, name, email FROM users WHERE active = true LIMIT 10",
        "SELECT 1;",
        "SELECT * FROM users WHERE notes = 'hello;world';",
        'SELECT "user;id" FROM users WHERE status = \'active\';',
        "WITH active_users AS (SELECT * FROM users WHERE status = 'ACTIVE') SELECT * FROM active_users;",
        "EXPLAIN SELECT * FROM orders JOIN users ON orders.user_id = users.id;",
        "   select * from products limit 5;   ",
        "/* comment */ SELECT * FROM items;",
        "-- comment \n SELECT * FROM items;",
        "INSERT INTO users (name, email) VALUES ('Alice', 'alice@example.com');",
        "UPDATE users SET name = 'Bob' WHERE id = 1;",
        "DELETE FROM users WHERE id = 2;",
        "CREATE TABLE test_table (id SERIAL PRIMARY KEY, name VARCHAR(100));",
        "ALTER TABLE users ADD COLUMN age INT;",
        "DROP TABLE test_table;",
        "TRUNCATE TABLE logs;",
    ],
)
def test_validate_query_valid(query: str):
    validated = validate_query(query)
    assert validated is not None
    assert len(validated) > 0


@pytest.mark.parametrize(
    "query,reason",
    [
        ("", "empty query"),
        ("   ", "whitespace only"),
        ("-- just a comment", "only comment"),
        ("/* block comment only */", "only block comment"),
        ("SELECT * FROM users; DROP TABLE users;", "multi-statement write injection"),
        ("SELECT * FROM users; DELETE FROM orders;", "multi-statement delete injection"),
        ("SELECT * FROM users; SELECT * FROM orders;", "multi-statement forbidden in playground"),
        ("INSERT INTO a VALUES (1); INSERT INTO b VALUES (2);", "multi-statement insert"),
    ],
)
def test_validate_query_invalid(query: str, reason: str):
    with pytest.raises(ReadOnlyQueryRequiredError):
        validate_query(query)


def test_validate_read_only_query_alias():
    """Verify validate_read_only_query remains backward compatible."""
    assert validate_read_only_query("SELECT 1;") == "SELECT 1"
