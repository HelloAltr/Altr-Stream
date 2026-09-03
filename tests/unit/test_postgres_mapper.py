"""Unit tests for PostgreSQL catalog introspection mapper."""

from altr_stream.domain.schema import ConstraintType, StandardDataType
from altr_stream.infrastructure.connectors.postgres.mapper import (
    build_source_schema_from_pg,
    map_pg_type_to_standard,
)


def test_map_pg_type_to_standard():
    assert map_pg_type_to_standard("varchar") == StandardDataType.STRING
    assert map_pg_type_to_standard("text") == StandardDataType.STRING
    assert map_pg_type_to_standard("integer") == StandardDataType.INTEGER
    assert map_pg_type_to_standard("int4") == StandardDataType.INTEGER
    assert map_pg_type_to_standard("bigint") == StandardDataType.BIGINT
    assert map_pg_type_to_standard("boolean") == StandardDataType.BOOLEAN
    assert map_pg_type_to_standard("jsonb") == StandardDataType.JSON
    assert map_pg_type_to_standard("timestamp with time zone") == StandardDataType.TIMESTAMPTZ
    assert map_pg_type_to_standard("uuid") == StandardDataType.UUID
    assert map_pg_type_to_standard("numeric") == StandardDataType.DECIMAL
    assert map_pg_type_to_standard("ARRAY", "_text") == StandardDataType.ARRAY
    assert map_pg_type_to_standard("custom_unknown_type") == StandardDataType.OTHER


def test_build_source_schema_from_pg():
    tables_data = [
        {"table_schema": "public", "table_name": "users", "table_type": "BASE TABLE"},
        {"table_schema": "public", "table_name": "orders", "table_type": "BASE TABLE"},
    ]

    columns_data = [
        {
            "table_schema": "public",
            "table_name": "users",
            "column_name": "id",
            "ordinal_position": 1,
            "column_default": "nextval('users_id_seq')",
            "is_nullable": "NO",
            "data_type": "integer",
            "udt_name": "int4",
        },
        {
            "table_schema": "public",
            "table_name": "users",
            "column_name": "email",
            "ordinal_position": 2,
            "column_default": None,
            "is_nullable": "NO",
            "data_type": "character varying",
            "udt_name": "varchar",
        },
        {
            "table_schema": "public",
            "table_name": "orders",
            "column_name": "id",
            "ordinal_position": 1,
            "column_default": None,
            "is_nullable": "NO",
            "data_type": "bigint",
            "udt_name": "int8",
        },
        {
            "table_schema": "public",
            "table_name": "orders",
            "column_name": "user_id",
            "ordinal_position": 2,
            "column_default": None,
            "is_nullable": "NO",
            "data_type": "integer",
            "udt_name": "int4",
        },
    ]

    pks_data = [
        {"table_schema": "public", "table_name": "users", "column_name": "id", "ordinal_position": 1},
        {"table_schema": "public", "table_name": "orders", "column_name": "id", "ordinal_position": 1},
    ]

    fks_data = [
        {
            "constraint_name": "fk_orders_user",
            "table_schema": "public",
            "table_name": "orders",
            "column_name": "user_id",
            "foreign_table_schema": "public",
            "foreign_table_name": "users",
            "foreign_column_name": "id",
        }
    ]

    schema = build_source_schema_from_pg(
        source_id="src-999",
        source_name="Postgres Store",
        tables_data=tables_data,
        columns_data=columns_data,
        pks_data=pks_data,
        fks_data=fks_data,
    )

    assert schema.source_id == "src-999"
    assert schema.entity_count == 2
    assert schema.total_field_count == 4

    users_entity = next(e for e in schema.entities if e.name == "users")
    assert users_entity.primary_key == ["id"]
    assert users_entity.fields[0].is_primary_key is True
    assert users_entity.fields[0].data_type == StandardDataType.INTEGER
    assert users_entity.fields[1].data_type == StandardDataType.STRING

    orders_entity = next(e for e in schema.entities if e.name == "orders")
    assert len(orders_entity.constraints) == 2  # PK + FK
    fk_constraint = next(c for c in orders_entity.constraints if c.constraint_type == ConstraintType.FOREIGN_KEY)
    assert fk_constraint.referenced_entity == "public.users"
    assert fk_constraint.referenced_fields == ["id"]
