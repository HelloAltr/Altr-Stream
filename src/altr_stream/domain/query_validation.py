"""Query validation for native physical query execution in Query Playground."""

import re
from altr_stream.domain.errors import ReadOnlyQueryRequiredError


def strip_sql_comments(sql: str) -> str:
    """Strip SQL single-line (-- ...) and multi-line (/* ... */) comments."""
    # Remove multi-line comments /* ... */
    sql = re.sub(r"/\*[\s\S]*?\*/", " ", sql)
    # Remove single-line comments -- ...
    sql = re.sub(r"--[^\n]*", " ", sql)
    return sql.strip()


def split_sql_statements(sql: str) -> list[str]:
    """
    Split a SQL query string into discrete statements by statement-terminating semicolons.

    Ignores semicolons inside:
    - Single-quoted string literals ('foo;bar', handling escaped '')
    - Double-quoted identifiers ("col;name", handling escaped "")
    - Dollar-quoted strings ($tag$...;...$tag$ or $$...;...$$)
    - SQL single-line and multi-line comments (-- ... and /* ... */)
    """
    statements: list[str] = []
    current: list[str] = []
    i = 0
    n = len(sql)

    in_single_quote = False
    in_double_quote = False
    in_dollar_quote: str | None = None
    in_line_comment = False
    in_block_comment = False

    while i < n:
        c = sql[i]
        next_c = sql[i + 1] if i + 1 < n else ""

        if in_line_comment:
            current.append(c)
            if c == "\n":
                in_line_comment = False
            i += 1
            continue

        if in_block_comment:
            current.append(c)
            if c == "*" and next_c == "/":
                current.append(next_c)
                in_block_comment = False
                i += 2
                continue
            i += 1
            continue

        if in_single_quote:
            current.append(c)
            if c == "'":
                if next_c == "'":  # Escaped single quote ''
                    current.append(next_c)
                    i += 2
                    continue
                else:
                    in_single_quote = False
            i += 1
            continue

        if in_double_quote:
            current.append(c)
            if c == '"':
                if next_c == '"':  # Escaped double quote ""
                    current.append(next_c)
                    i += 2
                    continue
                else:
                    in_double_quote = False
            i += 1
            continue

        if in_dollar_quote is not None:
            if c == "$":
                tag_len = len(in_dollar_quote)
                if sql[i : i + tag_len] == in_dollar_quote:
                    current.append(in_dollar_quote)
                    in_dollar_quote = None
                    i += tag_len
                    continue
            current.append(c)
            i += 1
            continue

        # Outside quotes/comments
        if c == "-" and next_c == "-":
            in_line_comment = True
            current.append(c)
            current.append(next_c)
            i += 2
            continue

        if c == "/" and next_c == "*":
            in_block_comment = True
            current.append(c)
            current.append(next_c)
            i += 2
            continue

        if c == "'":
            in_single_quote = True
            current.append(c)
            i += 1
            continue

        if c == '"':
            in_double_quote = True
            current.append(c)
            i += 1
            continue

        if c == "$":
            match = re.match(r"^\$([A-Za-z_][A-Za-z0-9_]*)?\$", sql[i:])
            if match:
                tag = match.group(0)
                in_dollar_quote = tag
                current.append(tag)
                i += len(tag)
                continue
            else:
                current.append(c)
                i += 1
                continue

        if c == ";":
            stmt = "".join(current).strip()
            if stmt:
                statements.append(stmt)
            current = []
            i += 1
            continue

        current.append(c)
        i += 1

    final_stmt = "".join(current).strip()
    if final_stmt:
        statements.append(final_stmt)

    return [s for s in statements if strip_sql_comments(s)]


def validate_query(query: str) -> str:
    """
    Validate that the given SQL query is a valid single-statement query.

    Allows optional trailing semicolons, semicolons inside string literals/identifiers,
    and supports all single-statement native queries (SELECT, INSERT, UPDATE, DELETE,
    CREATE, DROP, ALTER, TRUNCATE, WITH, EXPLAIN, SHOW, etc.).

    Raises:
        ReadOnlyQueryRequiredError: If query is empty, invalid, or multi-statement.
    Returns:
        Cleaned single-statement query string without extraneous trailing statement terminators.
    """
    if not query or not query.strip():
        raise ReadOnlyQueryRequiredError("Query cannot be empty.")

    cleaned_comments = strip_sql_comments(query)
    if not cleaned_comments:
        raise ReadOnlyQueryRequiredError("Query cannot be empty.")

    statements = split_sql_statements(query)
    if not statements:
        raise ReadOnlyQueryRequiredError("Query cannot be empty.")

    if len(statements) > 1:
        raise ReadOnlyQueryRequiredError(
            "Multi-statement queries are forbidden in Query Playground. Please execute one statement at a time."
        )

    return statements[0].strip()


# Backward-compatible alias for existing imports
validate_read_only_query = validate_query
