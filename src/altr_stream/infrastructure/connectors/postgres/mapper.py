"""PostgreSQL metadata to standardized Altr Schema mapper."""

from datetime import datetime, timezone
from typing import Any

from altr_stream.domain.schema import (
    ConstraintSchema,
    ConstraintType,
    EntitySchema,
    FieldSchema,
    SourceSchema,
    StandardDataType,
)

PG_TYPE_MAP: dict[str, StandardDataType] = {
    "varchar": StandardDataType.STRING,
    "character varying": StandardDataType.STRING,
    "character": StandardDataType.STRING,
    "char": StandardDataType.STRING,
    "text": StandardDataType.STRING,
    "name": StandardDataType.STRING,
    "citext": StandardDataType.STRING,
    "smallint": StandardDataType.SMALLINT,
    "int2": StandardDataType.SMALLINT,
    "smallserial": StandardDataType.SMALLINT,
    "integer": StandardDataType.INTEGER,
    "int": StandardDataType.INTEGER,
    "int4": StandardDataType.INTEGER,
    "serial": StandardDataType.INTEGER,
    "bigint": StandardDataType.BIGINT,
    "int8": StandardDataType.BIGINT,
    "bigserial": StandardDataType.BIGINT,
    "real": StandardDataType.FLOAT,
    "float4": StandardDataType.FLOAT,
    "double precision": StandardDataType.FLOAT,
    "float8": StandardDataType.FLOAT,
    "numeric": StandardDataType.DECIMAL,
    "decimal": StandardDataType.DECIMAL,
    "money": StandardDataType.DECIMAL,
    "boolean": StandardDataType.BOOLEAN,
    "bool": StandardDataType.BOOLEAN,
    "date": StandardDataType.DATE,
    "time": StandardDataType.TIME,
    "time without time zone": StandardDataType.TIME,
    "time with time zone": StandardDataType.TIME,
    "timetz": StandardDataType.TIME,
    "timestamp": StandardDataType.TIMESTAMP,
    "timestamp without time zone": StandardDataType.TIMESTAMP,
    "timestamp with time zone": StandardDataType.TIMESTAMPTZ,
    "timestamptz": StandardDataType.TIMESTAMPTZ,
    "json": StandardDataType.JSON,
    "jsonb": StandardDataType.JSON,
    "uuid": StandardDataType.UUID,
    "bytea": StandardDataType.BINARY,
}


def map_pg_type_to_standard(data_type: str, udt_name: str | None = None) -> StandardDataType:
    """Map PostgreSQL raw data type or UDT name to StandardDataType."""
    normalized_type = (data_type or "").lower().strip()
    normalized_udt = (udt_name or "").lower().strip()

    # Check direct match
    if normalized_type in PG_TYPE_MAP:
        return PG_TYPE_MAP[normalized_type]
    if normalized_udt in PG_TYPE_MAP:
        return PG_TYPE_MAP[normalized_udt]

    # Array types in PostgreSQL (often start with '_' in UDT or end with '[]')
    if normalized_udt.startswith("_") or "[]" in normalized_type or normalized_type == "array":
        return StandardDataType.ARRAY

    return StandardDataType.OTHER


def build_source_schema_from_pg(
    source_id: str,
    source_name: str,
    tables_data: list[dict[str, Any]],
    columns_data: list[dict[str, Any]],
    pks_data: list[dict[str, Any]],
    fks_data: list[dict[str, Any]],
) -> SourceSchema:
    """Construct a standardized SourceSchema from raw PostgreSQL catalog query records."""
    # Organize primary keys by (schema, table) -> list of column names
    pks_by_table: dict[tuple[str, str], list[str]] = {}
    for row in pks_data:
        key = (row["table_schema"], row["table_name"])
        pks_by_table.setdefault(key, []).append(row["column_name"])

    # Organize columns by (schema, table) -> list of FieldSchema
    cols_by_table: dict[tuple[str, str], list[FieldSchema]] = {}
    for row in columns_data:
        schema_name = row["table_schema"]
        table_name = row["table_name"]
        col_name = row["column_name"]
        key = (schema_name, table_name)

        is_pk = col_name in pks_by_table.get(key, [])
        std_type = map_pg_type_to_standard(row.get("data_type", ""), row.get("udt_name", ""))

        field = FieldSchema(
            name=col_name,
            data_type=std_type,
            native_data_type=row.get("udt_name") or row.get("data_type") or "unknown",
            nullable=str(row.get("is_nullable", "")).upper() == "YES",
            is_primary_key=is_pk,
            default_value=row.get("column_default"),
            position=int(row.get("ordinal_position", 0)),
        )
        cols_by_table.setdefault(key, []).append(field)

    # Organize foreign key constraints by (schema, table)
    fks_by_table: dict[tuple[str, str], dict[str, ConstraintSchema]] = {}
    for row in fks_data:
        key = (row["table_schema"], row["table_name"])
        c_name = row["constraint_name"]
        table_fks = fks_by_table.setdefault(key, {})

        if c_name not in table_fks:
            table_fks[c_name] = ConstraintSchema(
                name=c_name,
                constraint_type=ConstraintType.FOREIGN_KEY,
                fields=[row["column_name"]],
                referenced_entity=f"{row['foreign_table_schema']}.{row['foreign_table_name']}",
                referenced_fields=[row["foreign_column_name"]],
            )
        else:
            if row["column_name"] not in table_fks[c_name].fields:
                table_fks[c_name].fields.append(row["column_name"])
            if row["foreign_column_name"] not in table_fks[c_name].referenced_fields:
                table_fks[c_name].referenced_fields.append(row["foreign_column_name"])

    # Construct Entities
    entities: list[EntitySchema] = []
    for row in tables_data:
        schema_name = row["table_schema"]
        table_name = row["table_name"]
        table_type_raw = str(row.get("table_type", "")).upper()
        entity_type = "VIEW" if "VIEW" in table_type_raw else "TABLE"
        key = (schema_name, table_name)

        table_pks = pks_by_table.get(key, [])
        table_cols = cols_by_table.get(key, [])
        table_fks = list(fks_by_table.get(key, {}).values())

        constraints: list[ConstraintSchema] = []
        if table_pks:
            constraints.append(
                ConstraintSchema(
                    name=f"pk_{table_name}",
                    constraint_type=ConstraintType.PRIMARY_KEY,
                    fields=table_pks,
                )
            )
        constraints.extend(table_fks)

        entity = EntitySchema(
            name=table_name,
            namespace=schema_name,
            entity_type=entity_type,
            fields=table_cols,
            primary_key=table_pks,
            constraints=constraints,
        )
        entities.append(entity)

    return SourceSchema(
        source_id=source_id,
        source_name=source_name,
        version="1.0.0",
        discovered_at=datetime.now(timezone.utc),
        entities=entities,
        metadata={
            "engine": "postgresql",
            "entity_count": len(entities),
            "total_field_count": sum(len(e.fields) for e in entities),
        },
    )
