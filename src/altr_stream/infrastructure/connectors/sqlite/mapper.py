"""SQLite metadata to standardized Altr Schema mapper."""

from datetime import datetime, timezone
import re
from typing import Any

from altr_stream.domain.schema import (
    ConstraintSchema,
    ConstraintType,
    EntitySchema,
    FieldSchema,
    SourceSchema,
    StandardDataType,
)

SQLITE_TYPE_MAP: dict[str, StandardDataType] = {
    "int": StandardDataType.INTEGER,
    "integer": StandardDataType.INTEGER,
    "tinyint": StandardDataType.SMALLINT,
    "smallint": StandardDataType.SMALLINT,
    "mediumint": StandardDataType.INTEGER,
    "bigint": StandardDataType.BIGINT,
    "int2": StandardDataType.SMALLINT,
    "int4": StandardDataType.INTEGER,
    "int8": StandardDataType.BIGINT,
    "real": StandardDataType.FLOAT,
    "double": StandardDataType.FLOAT,
    "double precision": StandardDataType.FLOAT,
    "float": StandardDataType.FLOAT,
    "numeric": StandardDataType.DECIMAL,
    "decimal": StandardDataType.DECIMAL,
    "boolean": StandardDataType.BOOLEAN,
    "bool": StandardDataType.BOOLEAN,
    "date": StandardDataType.DATE,
    "datetime": StandardDataType.TIMESTAMP,
    "timestamp": StandardDataType.TIMESTAMP,
    "time": StandardDataType.TIME,
    "text": StandardDataType.STRING,
    "character": StandardDataType.STRING,
    "varchar": StandardDataType.STRING,
    "nvarchar": StandardDataType.STRING,
    "char": StandardDataType.STRING,
    "clob": StandardDataType.STRING,
    "string": StandardDataType.STRING,
    "blob": StandardDataType.BINARY,
    "json": StandardDataType.JSON,
    "jsonb": StandardDataType.JSON,
    "uuid": StandardDataType.UUID,
}


def map_sqlite_type_to_standard(data_type: str) -> StandardDataType:
    """Map SQLite declared column data type to StandardDataType."""
    normalized = (data_type or "").lower().strip()
    # Strip precision/scale e.g. VARCHAR(255), NUMERIC(10,2)
    normalized = re.sub(r"\(.*\)", "", normalized).strip()

    if normalized in SQLITE_TYPE_MAP:
        return SQLITE_TYPE_MAP[normalized]

    # Type affinity fallbacks based on SQLite standard affinity rules
    if "int" in normalized:
        return StandardDataType.INTEGER
    if "char" in normalized or "clob" in normalized or "text" in normalized:
        return StandardDataType.STRING
    if "blob" in normalized or not normalized:
        return StandardDataType.STRING
    if "real" in normalized or "floa" in normalized or "doub" in normalized:
        return StandardDataType.FLOAT
    if "numeric" in normalized or "dec" in normalized:
        return StandardDataType.DECIMAL

    return StandardDataType.OTHER


def build_source_schema_from_sqlite(
    source_id: str,
    source_name: str,
    tables_data: list[dict[str, Any]],
    table_columns: dict[str, list[dict[str, Any]]],
    table_fks: dict[str, list[dict[str, Any]]],
) -> SourceSchema:
    """Construct a standardized SourceSchema from SQLite introspection data."""
    entities: list[EntitySchema] = []

    for row in tables_data:
        table_name = row["table_name"]
        table_type_raw = str(row.get("table_type", "")).upper()
        entity_type = "VIEW" if "VIEW" in table_type_raw else "TABLE"

        raw_cols = table_columns.get(table_name, [])
        raw_fks = table_fks.get(table_name, [])

        fields: list[FieldSchema] = []
        pks: list[str] = []

        for col_dict in raw_cols:
            col_name = col_dict["name"]
            col_type = col_dict.get("type", "")
            is_pk = bool(col_dict.get("pk", 0) > 0)
            if is_pk:
                pks.append(col_name)

            std_type = map_sqlite_type_to_standard(col_type)
            is_notnull = bool(col_dict.get("notnull", 0) == 1)

            fields.append(
                FieldSchema(
                    name=col_name,
                    data_type=std_type,
                    native_data_type=col_type or "TEXT",
                    nullable=not is_notnull,
                    is_primary_key=is_pk,
                    default_value=str(col_dict.get("dflt_value")) if col_dict.get("dflt_value") is not None else None,
                    position=int(col_dict.get("cid", 0)),
                )
            )

        constraints: list[ConstraintSchema] = []
        if pks:
            constraints.append(
                ConstraintSchema(
                    name=f"pk_{table_name}",
                    constraint_type=ConstraintType.PRIMARY_KEY,
                    fields=pks,
                )
            )

        for fk in raw_fks:
            from_col = fk.get("from")
            to_table = fk.get("table")
            to_col = fk.get("to")
            fk_id = fk.get("id", 0)
            if from_col and to_table:
                constraints.append(
                    ConstraintSchema(
                        name=f"fk_{table_name}_{from_col}_{fk_id}",
                        constraint_type=ConstraintType.FOREIGN_KEY,
                        fields=[from_col],
                        referenced_entity=to_table,
                        referenced_fields=[to_col] if to_col else [],
                    )
                )

        entity = EntitySchema(
            name=table_name,
            namespace="main",
            entity_type=entity_type,
            fields=fields,
            primary_key=pks,
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
            "engine": "sqlite",
            "entity_count": len(entities),
            "total_field_count": sum(len(e.fields) for e in entities),
        },
    )
