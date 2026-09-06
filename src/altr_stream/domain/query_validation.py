"""Query validation for native physical query execution in Query Playground."""

import re
from altr_stream.domain.errors import ReadOnlyQueryRequiredError

# Forbidden write and DDL keywords
FORBIDDEN_KEYWORDS = {
    "INSERT",
    "UPDATE",
    "DELETE",
    "DROP",
    "ALTER",
    "CREATE",
    "TRUNCATE",
    "GRANT",
    "REVOKE",
    "EXECUTE",
    "CALL",
    "REINDEX",
    "VACUUM",
    "COPY",
}

# Allowed statement starting keywords for read-only queries
ALLOWED_STARTS = {"SELECT", "WITH", "EXPLAIN"}


def strip_sql_comments(sql: str) -> str:
    """Strip SQL single-line and multi-line comments."""
    # Remove multi-line comments /* ... */
    sql = re.sub(r"/\*[\s\S]*?\*/", " ", sql)
    # Remove single-line comments -- ...
    sql = re.sub(r"--[^\n]*", " ", sql)
    return sql.strip()


def validate_read_only_query(query: str) -> str:
    """
    Validate that the given SQL query is a single-statement read-only query.

    Raises:
        ReadOnlyQueryRequiredError: If query is empty, multi-statement, or contains write/DDL operations.
    Returns:
        Cleaned, sanitized query string.
    """
    if not query or not query.strip():
        raise ReadOnlyQueryRequiredError("Query cannot be empty.")

    cleaned = strip_sql_comments(query)
    if not cleaned:
        raise ReadOnlyQueryRequiredError("Query cannot be empty.")

    # Check for multi-statements (semicolons separating non-whitespace text)
    # Split by semicolon and filter out empty parts
    statements = [s.strip() for s in cleaned.split(";") if s.strip()]
    if len(statements) > 1:
        raise ReadOnlyQueryRequiredError(
            "Multi-statement queries are forbidden in Query Playground. Please execute one statement at a time."
        )

    statement = statements[0]

    # Tokenize word boundaries
    tokens = re.findall(r"\b[A-Za-z_][A-Za-z0-9_]*\b", statement)
    if not tokens:
        raise ReadOnlyQueryRequiredError("Invalid query: no executable SQL statement found.")

    first_keyword = tokens[0].upper()
    if first_keyword not in ALLOWED_STARTS:
        raise ReadOnlyQueryRequiredError(
            f"Query Playground is restricted to read-only queries (SELECT, WITH, EXPLAIN). "
            f"'{first_keyword}' statements are not supported."
        )

    # Scan all tokens for forbidden write/DDL keywords
    upper_tokens = [t.upper() for t in tokens]
    for token in upper_tokens:
        if token in FORBIDDEN_KEYWORDS:
            raise ReadOnlyQueryRequiredError(
                f"Forbidden write or DDL operation '{token}' detected. "
                "The Query Playground only supports read-only execution."
            )

    return statement
