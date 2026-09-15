"""Unit tests for MySQL metadata mapping and schema construction."""

import pytest

from altr_stream.domain.schema import ConstraintType, StandardDataType
from altr_stream.infrastructure.connectors.mysql.mapper import (
    build_source_schema_from_mysql,
    map_mysql_type_to_standard,
)


def test_map_mysql_type_to_standard_numeric():
    """Test mapping of MySQL numeric types."""
    assert map_mysql_type_to_standard("tinyint", "tinyint(1)") == StandardDataType.BOOLEAN
    assert map_mysql_type_to_standard("tinyint", "tinyint(4)") == StandardDataType.INTEGER
    assert map_mysql_type_to_standard("smallint", "smallint(6)") == StandardDataType.SMALLINT
    assert map_mysql_type_to_standard("mediumint", "mediumint(9)") == StandardDataType.INTEGER
    assert map_mysql_type_to_standard("int", "int(11)") == StandardDataType.INTEGER
    assert map_mysql_type_to_standard("integer", "integer") == StandardDataType.INTEGER
    assert map_mysql_type_to_standard("bigint", "bigint(20)") == StandardDataType.BIGINT
    assert map_mysql_type_to_standard("serial", "serial") == StandardDataType.BIGINT
    assert map_mysql_type_to_standard("float", "float") == StandardDataType.FLOAT
    assert map_mysql_type_to_standard("double", "double") == StandardDataType.FLOAT
    assert map_mysql_type_to_standard("real", "real") == StandardDataType.FLOAT
    assert map_mysql_type_to_standard("decimal", "decimal(10,2)") == StandardDataType.DECIMAL
    assert map_mysql_type_to_standard("numeric", "numeric(15,4)") == StandardDataType.DECIMAL


def test_map_mysql_type_to_standard_text_and_temporal():
    """Test mapping of MySQL text, temporal, boolean, JSON, and binary types."""
    assert map_mysql_type_to_standard("varchar", "varchar(255)") == StandardDataType.STRING
    assert map_mysql_type_to_standard("char", "char(36)") == StandardDataType.STRING
    assert map_mysql_type_to_standard("text", "text") == StandardDataType.STRING
    assert map_mysql_type_to_standard("tinytext", "tinytext") == StandardDataType.STRING
    assert map_mysql_type_to_standard("mediumtext", "mediumtext") == StandardDataType.STRING
    assert map_mysql_type_to_standard("longtext", "longtext") == StandardDataType.STRING
    assert map_mysql_type_to_standard("enum", "enum('a','b')") == StandardDataType.STRING
    assert map_mysql_type_to_standard("set", "set('1','2')") == StandardDataType.STRING
    assert map_mysql_type_to_standard("boolean", "boolean") == StandardDataType.BOOLEAN
    assert map_mysql_type_to_standard("bool", "bool") == StandardDataType.BOOLEAN
    assert map_mysql_type_to_standard("date", "date") == StandardDataType.DATE
    assert map_mysql_type_to_standard("time", "time") == StandardDataType.TIME
    assert map_mysql_type_to_standard("datetime", "datetime(6)") == StandardDataType.TIMESTAMP
    assert map_mysql_type_to_standard("timestamp", "timestamp") == StandardDataType.TIMESTAMP
    assert map_mysql_type_to_standard("year", "year") == StandardDataType.INTEGER
    assert map_mysql_type_to_standard("json", "json") == StandardDataType.JSON
    assert map_mysql_type_to_standard("blob", "blob") == StandardDataType.BINARY
    assert map_mysql_type_to_standard("varbinary", "varbinary(100)") == StandardDataType.BINARY
    assert map_mysql_type_to_standard("unknown_custom", "unknown_custom") == StandardDataType.OTHER


def test_build_source_schema_from_mysql_structure():
    """Test full assembly of SourceSchema from raw MySQL catalog dictionary records."""
    tables_data = [
        {"table_name": "users", "table_type": "BASE TABLE", "table_comment": "User accounts"},
        {"table_name": "orders", "table_type": "BASE TABLE", "table_comment": None},
        {"table_name": "active_users_view", "table_type": "VIEW", "table_comment": "View of active users"},
    ]

    columns_data = [
        # users columns
        {
            "table_name": "users",
            "column_name": "id",
            "data_type": "bigint",
            "column_type": "bigint(20) unsigned",
            "is_nullable": "NO",
            "column_default": None,
            "ordinal_position": 1,
            "column_comment": "Primary ID",
        },
        {
            "table_name": "users",
            "column_name": "email",
            "data_type": "varchar",
            "column_type": "varchar(255)",
            "is_nullable": "NO",
            "column_default": None,
            "ordinal_position": 2,
            "column_comment": "Unique Email",
        },
        {
            "table_name": "users",
            "column_name": "is_active",
            "data_type": "tinyint",
            "column_type": "tinyint(1)",
            "is_nullable": "NO",
            "column_default": "1",
            "ordinal_position": 3,
            "column_comment": None,
        },
        {
            "table_name": "users",
            "column_name": "metadata",
            "data_type": "json",
            "column_type": "json",
            "is_nullable": "YES",
            "column_default": None,
            "ordinal_position": 4,
            "column_comment": None,
        },
        # orders columns
        {
            "table_name": "orders",
            "column_name": "order_id",
            "data_type": "int",
            "column_type": "int(11)",
            "is_nullable": "NO",
            "column_default": None,
            "ordinal_position": 1,
            "column_comment": None,
        },
        {
            "table_name": "orders",
            "column_name": "user_id",
            "data_type": "bigint",
            "column_type": "bigint(20)",
            "is_nullable": "NO",
            "column_default": None,
            "ordinal_position": 2,
            "column_comment": None,
        },
        {
            "table_name": "orders",
            "column_name": "amount",
            "data_type": "decimal",
            "column_type": "decimal(10,2)",
            "is_nullable": "YES",
            "column_default": "0.00",
            "ordinal_position": 3,
            "column_comment": None,
        },
        # active_users_view columns
        {
            "table_name": "active_users_view",
            "column_name": "id",
            "data_type": "bigint",
            "column_type": "bigint(20)",
            "is_nullable": "NO",
            "column_default": None,
            "ordinal_position": 1,
            "column_comment": None,
        },
    ]

    constraints_data = [
        # users constraints
        {
            "table_name": "users",
            "column_name": "id",
            "constraint_name": "PRIMARY",
            "constraint_type": "PRIMARY KEY",
            "referenced_table_name": None,
            "referenced_column_name": None,
            "ordinal_position": 1,
        },
        {
            "table_name": "users",
            "column_name": "email",
            "constraint_name": "uq_users_email",
            "constraint_type": "UNIQUE",
            "referenced_table_name": None,
            "referenced_column_name": None,
            "ordinal_position": 1,
        },
        # orders constraints
        {
            "table_name": "orders",
            "column_name": "order_id",
            "constraint_name": "PRIMARY",
            "constraint_type": "PRIMARY KEY",
            "referenced_table_name": None,
            "referenced_column_name": None,
            "ordinal_position": 1,
        },
        {
            "table_name": "orders",
            "column_name": "user_id",
            "constraint_name": "fk_orders_users",
            "constraint_type": "FOREIGN KEY",
            "referenced_table_name": "users",
            "referenced_column_name": "id",
            "ordinal_position": 1,
        },
    ]

    schema = build_source_schema_from_mysql(
        source_id="src_mysql_1",
        source_name="Production MySQL",
        tables_data=tables_data,
        columns_data=columns_data,
        constraints_data=constraints_data,
    )

    assert schema.source_id == "src_mysql_1"
    assert schema.source_name == "Production MySQL"
    assert schema.entity_count == 3
    assert schema.total_field_count == 8

    # Check users table entity
    users_entity = next((e for e in schema.entities if e.name == "users"), None)
    assert users_entity is not None
    assert users_entity.entity_type == "TABLE"
    assert users_entity.primary_key == ["id"]
    assert users_entity.comment == "User accounts"
    assert len(users_entity.fields) == 4

    id_field = users_entity.get_field("id")
    assert id_field is not None
    assert id_field.data_type == StandardDataType.BIGINT
    assert id_field.is_primary_key is True
    assert id_field.nullable is False
    assert id_field.comment == "Primary ID"

    is_active_field = users_entity.get_field("is_active")
    assert is_active_field is not None
    assert is_active_field.data_type == StandardDataType.BOOLEAN
    assert is_active_field.default_value == "1"

    metadata_field = users_entity.get_field("metadata")
    assert metadata_field is not None
    assert metadata_field.data_type == StandardDataType.JSON
    assert metadata_field.nullable is True

    # Check constraints on users
    assert any(c.constraint_type == ConstraintType.PRIMARY_KEY and c.fields == ["id"] for c in users_entity.constraints)
    assert any(c.constraint_type == ConstraintType.UNIQUE and c.fields == ["email"] for c in users_entity.constraints)

    # Check orders table entity
    orders_entity = next((e for e in schema.entities if e.name == "orders"), None)
    assert orders_entity is not None
    assert orders_entity.primary_key == ["order_id"]
    fk = next((c for c in orders_entity.constraints if c.constraint_type == ConstraintType.FOREIGN_KEY), None)
    assert fk is not None
    assert fk.fields == ["user_id"]
    assert fk.referenced_entity == "users"
    assert fk.referenced_fields == ["id"]

    # Check active_users_view
    view_entity = next((e for e in schema.entities if e.name == "active_users_view"), None)
    assert view_entity is not None
    assert view_entity.entity_type == "VIEW"
    assert view_entity.comment == "View of active users"
