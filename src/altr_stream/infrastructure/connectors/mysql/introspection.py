"""MySQL ANSI information_schema catalog queries for schema discovery."""

TABLES_QUERY = """
SELECT 
    table_name,
    table_type,
    table_comment
FROM information_schema.tables
WHERE table_schema = %s
  AND table_type IN ('BASE TABLE', 'VIEW', 'SYSTEM VIEW')
ORDER BY table_name;
"""

COLUMNS_QUERY = """
SELECT 
    table_name,
    column_name,
    data_type,
    column_type,
    is_nullable,
    column_default,
    ordinal_position,
    column_comment
FROM information_schema.columns
WHERE table_schema = %s
ORDER BY table_name, ordinal_position;
"""

CONSTRAINTS_QUERY = """
SELECT 
    kcu.table_name,
    kcu.column_name,
    kcu.constraint_name,
    tc.constraint_type,
    kcu.referenced_table_name,
    kcu.referenced_column_name,
    kcu.ordinal_position
FROM information_schema.key_column_usage kcu
JOIN information_schema.table_constraints tc
  ON kcu.constraint_name = tc.constraint_name
 AND kcu.table_schema = tc.table_schema
 AND kcu.table_name = tc.table_name
WHERE kcu.table_schema = %s
ORDER BY kcu.table_name, kcu.constraint_name, kcu.ordinal_position;
"""
