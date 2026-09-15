"""MySQL metadata to standardized Altr Schema mapper."""

from datetime import datetime, timezone
from typing import Any
import re

from altr_stream.domain.schema import (
    ConstraintSchema,
    ConstraintType,
    EntitySchema,
    FieldSchema,
    SourceSchema,
    StandardDataType,
)

MYSQL_TYPE_MAP: dict[str, StandardDataType] = {
    "varchar": StandardDataType.STRING,
    "char": StandardDataType.STRING,
    "text": StandardDataType.STRING,
    "tinytext": StandardDataType.STRING,
    "mediumtext": StandardDataType.STRING,
    "longtext": StandardDataType.STRING,
    "enum": StandardDataType.STRING,
    "set": StandardDataType.STRING,
    "smallint": StandardDataType.SMALLINT,
    "tinyint": StandardDataType.INTEGER,
    "mediumint": StandardDataType.INTEGER,
    "int": StandardDataType.INTEGER,
    "integer": StandardDataType.INTEGER,
    "bigint": StandardDataType.BIGINT,
    "serial": StandardDataType.BIGINT,
    "float": StandardDataType.FLOAT,
    "double": StandardDataType.FLOAT,
    "double precision": StandardDataType.FLOAT,
    "real": StandardDataType.FLOAT,
    "decimal": StandardDataType.DECIMAL,
    "numeric": StandardDataType.DECIMAL,
    "dec": StandardDataType.DECIMAL,
    "fixed": StandardDataType.DECIMAL,
    "boolean": StandardDataType.BOOLEAN,
    "bool": StandardDataType.BOOLEAN,
    "date": StandardDataType.DATE,
    "time": StandardDataType.TIME,
    "datetime": StandardDataType.TIMESTAMP,
    "timestamp": StandardDataType.TIMESTAMP,
    "year": StandardDataType.INTEGER,
    "json": StandardDataType.JSON,
    "binary": StandardDataType.BINARY,
    "varbinary": StandardDataType.BINARY,
    "blob": StandardDataType.BINARY,
    "tinyblob": StandardDataType.BINARY,
    "mediumblob": StandardDataType.BINARY,
    "longblob": StandardDataType.BINARY,
    "bit": StandardDataType.BINARY,
    "uuid": StandardDataType.UUID,
}


def map_mysql_type_to_standard(data_type: str, column_type: str | None = None) -> StandardDataType:
    """Map MySQL raw data type and full column type definition to StandardDataType."""
    normalized_type = (data_type or "").lower().strip()
    normalized_col_type = (column_type or "").lower().strip()

    # Special case: TINYINT(1) is commonly used in MySQL for BOOLEAN
    if normalized_type == "tinyint" and ("tinyint(1)" in normalized_col_type or "bool" in normalized_col_type):
        return StandardDataType.BOOLEAN

    # Check direct match from data_type
    if normalized_type in MYSQL_TYPE_MAP:
        return MYSQL_TYPE_MAP[normalized_type]

    # Extract base type from column_type if data_type was composite
    base_match = re.match(r"^([a-z]+)", normalized_col_type)
    if base_match:
        base_type = base_match.group(1)
        if base_type in MYSQL_TYPE_MAP:
            return MYSQL_TYPE_MAP[base_type]

    return StandardDataType.OTHER


def build_source_schema_from_mysql(
    source_id: str,
    source_name: str,
    tables_data: list[dict[str, Any]],
    columns_data: list[dict[str, Any]],
    constraints_data: list[dict[str, Any]],
) -> SourceSchema:
    """Construct a standardized SourceSchema from raw MySQL catalog query records."""
    # Normalize dictionary keys to lowercase for cross-version compatibility
    normalized_constraints = [{k.lower(): v for k, v in r.items()} for r in constraints_data]
    normalized_columns = [{k.lower(): v for k, v in r.items()} for r in columns_data]
    normalized_tables = [{k.lower(): v for k, v in r.items()} for r in tables_data]

    # Organize constraints by table_name
    pks_by_table: dict[str, list[str]] = {}
    fks_by_table: dict[str, dict[str, ConstraintSchema]] = {}
    uniques_by_table: dict[str, dict[str, list[str]]] = {}

    for row in normalized_constraints:
        tbl_name = row.get("table_name", "")
        col_name = row.get("column_name", "")
        c_name = row.get("constraint_name", "")
        c_type = str(row.get("constraint_type", "")).upper()

        if c_type == "PRIMARY KEY":
            pks_by_table.setdefault(tbl_name, []).append(col_name)
        elif c_type == "FOREIGN KEY":
            tbl_fks = fks_by_table.setdefault(tbl_name, {})
            if c_name not in tbl_fks:
                ref_tbl = row.get("referenced_table_name")
                ref_col = row.get("referenced_column_name")
                tbl_fks[c_name] = ConstraintSchema(
                    name=c_name,
                    constraint_type=ConstraintType.FOREIGN_KEY,
                    fields=[col_name],
                    referenced_entity=ref_tbl,
                    referenced_fields=[ref_col] if ref_col else [],
                )
            else:
                if col_name not in tbl_fks[c_name].fields:
                    tbl_fks[c_name].fields.append(col_name)
                ref_col = row.get("referenced_column_name")
                if ref_col and ref_col not in tbl_fks[c_name].referenced_fields:
                    tbl_fks[c_name].referenced_fields.append(ref_col)
        elif c_type == "UNIQUE":
            uniques_by_table.setdefault(tbl_name, {}).setdefault(c_name, []).append(col_name)

    # Organize columns by table_name -> list of FieldSchema
    cols_by_table: dict[str, list[FieldSchema]] = {}
    for row in normalized_columns:
        tbl_name = row.get("table_name", "")
        col_name = row.get("column_name", "")
        is_pk = col_name in pks_by_table.get(tbl_name, [])

        data_type = row.get("data_type", "")
        column_type = row.get("column_type", "")
        std_type = map_mysql_type_to_standard(data_type, column_type)

        field = FieldSchema(
            name=col_name,
            data_type=std_type,
            native_data_type=column_type or data_type or "unknown",
            nullable=str(row.get("is_nullable", "")).upper() == "YES",
            is_primary_key=is_pk,
            default_value=str(row["column_default"]) if row.get("column_default") is not None else None,
            position=int(row.get("ordinal_position", 0)),
            comment=row.get("column_comment") or None,
        )
        cols_by_table.setdefault(tbl_name, []).append(field)

    # Construct Entities
    entities: list[EntitySchema] = []
    for row in normalized_tables:
        tbl_name = row.get("table_name", "")
        table_type_raw = str(row.get("table_type", "")).upper()
        entity_type = "VIEW" if "VIEW" in table_type_raw else "TABLE"

        tbl_pks = pks_by_table.get(tbl_name, [])
        tbl_cols = cols_by_table.get(tbl_name, [])
        tbl_fks = list(fks_by_table.get(tbl_name, {}).values())

        constraints: list[ConstraintSchema] = []
        if tbl_pks:
            constraints.append(
                ConstraintSchema(
                    name=f"pk_{tbl_name}",
                    constraint_type=ConstraintType.PRIMARY_KEY,
                    fields=tbl_pks,
                )
            )
        constraints.extend(tbl_fks)

        for u_name, u_cols in uniques_by_table.get(tbl_name, {}).items():
            constraints.append(
                ConstraintSchema(
                    name=u_name,
                    constraint_type=ConstraintType.UNIQUE,
                    fields=u_cols,
                )
            )

        entity = EntitySchema(
            name=tbl_name,
            namespace="default",
            entity_type=entity_type,
            fields=tbl_cols,
            primary_key=tbl_pks,
            constraints=constraints,
            comment=row.get("table_comment") or None,
        )
        entities.append(entity)

    return SourceSchema(
        source_id=source_id,
        source_name=source_name,
        version="1.0.0",
        discovered_at=datetime.now(timezone.utc),
        entities=entities,
    )
