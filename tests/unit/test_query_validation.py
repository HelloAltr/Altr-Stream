"""Unit tests for Query Playground read-only query validation."""

import pytest
from altr_stream.domain.errors import ReadOnlyQueryRequiredError
from altr_stream.domain.query_validation import strip_sql_comments, validate_read_only_query


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
    "query",
    [
        "SELECT * FROM users",
        "SELECT id, name, email FROM users WHERE active = true LIMIT 10",
        "SELECT 1;",
        "WITH active_users AS (SELECT * FROM users WHERE status = 'ACTIVE') SELECT * FROM active_users;",
        "EXPLAIN SELECT * FROM orders JOIN users ON orders.user_id = users.id;",
        "   select * from products limit 5;   ",
        "/* comment */ SELECT * FROM items;",
        "-- comment \n SELECT * FROM items;",
    ],
)
def test_validate_read_only_query_valid(query: str):
    validated = validate_read_only_query(query)
    assert validated is not None
    assert len(validated) > 0


@pytest.mark.parametrize(
    "query,reason",
    [
        ("", "empty query"),
        ("   ", "whitespace only"),
        ("-- just a comment", "only comment"),
        ("INSERT INTO users (name) VALUES ('Hacker')", "INSERT statement"),
        ("UPDATE users SET name = 'Admin' WHERE id = 1", "UPDATE statement"),
        ("DELETE FROM users WHERE id = 1", "DELETE statement"),
        ("DROP TABLE users", "DROP statement"),
        ("ALTER TABLE users ADD COLUMN age INT", "ALTER statement"),
        ("CREATE TABLE test (id INT)", "CREATE statement"),
        ("TRUNCATE TABLE users", "TRUNCATE statement"),
        ("GRANT ALL ON users TO public", "GRANT statement"),
        ("REVOKE ALL ON users FROM public", "REVOKE statement"),
        ("EXECUTE my_plan", "EXECUTE statement"),
        ("CALL my_procedure()", "CALL statement"),
        ("COPY users TO '/tmp/data'", "COPY statement"),
        ("VACUUM FULL", "VACUUM statement"),
        ("REINDEX TABLE users", "REINDEX statement"),
        ("SELECT * FROM users; DROP TABLE users;", "multi-statement write injection"),
        ("SELECT * FROM users; DELETE FROM orders;", "multi-statement delete injection"),
        ("SELECT * FROM users; SELECT * FROM orders;", "multi-statement forbidden in playground"),
        ("/* sneaky */ INSERT INTO logs VALUES (1)", "comment evasion with INSERT"),
        ("WITH x AS (DELETE FROM users RETURNING *) SELECT * FROM x", "write CTE in WITH"),
    ],
)
def test_validate_read_only_query_invalid(query: str, reason: str):
    with pytest.raises(ReadOnlyQueryRequiredError):
        validate_read_only_query(query)
