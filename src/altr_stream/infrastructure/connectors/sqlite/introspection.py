"""SQLite catalog introspection queries and pragma helpers."""

TABLES_QUERY = """
SELECT 
    name AS table_name,
    type AS table_type
FROM sqlite_master
WHERE type IN ('table', 'view')
  AND name NOT LIKE 'sqlite_%'
ORDER BY name;
"""


def table_info_query(table_name: str) -> str:
    """Generate PRAGMA query to introspect table columns."""
    sanitized = table_name.replace('"', '""')
    return f'PRAGMA table_info("{sanitized}");'


def foreign_key_list_query(table_name: str) -> str:
    """Generate PRAGMA query to introspect table foreign keys."""
    sanitized = table_name.replace('"', '""')
    return f'PRAGMA foreign_key_list("{sanitized}");'
