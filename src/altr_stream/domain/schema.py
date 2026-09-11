"""Standardized schema models for Altr Stream."""

from datetime import datetime, timezone
from enum import Enum
from typing import Any
from pydantic import BaseModel, Field


class StandardDataType(str, Enum):
    """Normalized, vendor-neutral data types."""

    STRING = "STRING"
    INTEGER = "INTEGER"
    BIGINT = "BIGINT"
    SMALLINT = "SMALLINT"
    FLOAT = "FLOAT"
    DECIMAL = "DECIMAL"
    BOOLEAN = "BOOLEAN"
    DATE = "DATE"
    TIME = "TIME"
    TIMESTAMP = "TIMESTAMP"
    TIMESTAMPTZ = "TIMESTAMPTZ"
    JSON = "JSON"
    ARRAY = "ARRAY"
    BINARY = "BINARY"
    UUID = "UUID"
    OTHER = "OTHER"


INTEGER_TYPES: frozenset[StandardDataType] = frozenset({
    StandardDataType.INTEGER,
    StandardDataType.BIGINT,
    StandardDataType.SMALLINT,
})

FLOAT_TYPES: frozenset[StandardDataType] = frozenset({
    StandardDataType.FLOAT,
    StandardDataType.DECIMAL,
})

STRING_TYPES: frozenset[StandardDataType] = frozenset({
    StandardDataType.STRING,
    StandardDataType.UUID,
})

BOOLEAN_TYPES: frozenset[StandardDataType] = frozenset({
    StandardDataType.BOOLEAN,
})

TEMPORAL_TYPES: frozenset[StandardDataType] = frozenset({
    StandardDataType.DATE,
    StandardDataType.TIME,
    StandardDataType.TIMESTAMP,
    StandardDataType.TIMESTAMPTZ,
})

JSON_TYPES: frozenset[StandardDataType] = frozenset({
    StandardDataType.JSON,
})

BINARY_TYPES: frozenset[StandardDataType] = frozenset({
    StandardDataType.BINARY,
})

ARRAY_TYPES: frozenset[StandardDataType] = frozenset({
    StandardDataType.ARRAY,
})


def are_datatypes_compatible(
    logical_type: StandardDataType | str,
    physical_type: StandardDataType | str,
) -> bool:
    """Check deterministic type compatibility between logical and physical data types.

    Rules:
    - INTEGER logical: physical must be INTEGER, BIGINT, or SMALLINT.
    - FLOAT / DECIMAL logical: physical must be FLOAT, DECIMAL, or INTEGER/BIGINT/SMALLINT.
    - STRING logical: physical must be STRING or UUID.
    - BOOLEAN logical: physical must be BOOLEAN.
    - TEMPORAL logical: physical must be DATE, TIME, TIMESTAMP, or TIMESTAMPTZ.
    - JSON logical: physical must be JSON.
    - BINARY logical: physical must be BINARY.
    - ARRAY logical: physical must be ARRAY.
    """
    if isinstance(logical_type, str):
        try:
            logical_type = StandardDataType(logical_type.upper())
        except ValueError:
            return False
    if isinstance(physical_type, str):
        try:
            physical_type = StandardDataType(physical_type.upper())
        except ValueError:
            return False

    if logical_type == physical_type:
        return True

    if logical_type in INTEGER_TYPES:
        return physical_type in INTEGER_TYPES

    if logical_type in FLOAT_TYPES:
        return physical_type in (FLOAT_TYPES | INTEGER_TYPES)

    if logical_type in STRING_TYPES:
        return physical_type in STRING_TYPES

    if logical_type in BOOLEAN_TYPES:
        return physical_type in BOOLEAN_TYPES

    if logical_type in TEMPORAL_TYPES:
        return physical_type in TEMPORAL_TYPES

    if logical_type in JSON_TYPES:
        return physical_type in JSON_TYPES

    if logical_type in BINARY_TYPES:
        return physical_type in BINARY_TYPES

    if logical_type in ARRAY_TYPES:
        return physical_type in ARRAY_TYPES

    return False


class ConstraintType(str, Enum):
    """Database constraint types."""

    PRIMARY_KEY = "PRIMARY_KEY"
    FOREIGN_KEY = "FOREIGN_KEY"
    UNIQUE = "UNIQUE"
    CHECK = "CHECK"


class FieldSchema(BaseModel):
    """Standardized representation of a single entity column/field."""

    name: str
    data_type: StandardDataType = StandardDataType.STRING
    native_data_type: str
    nullable: bool = True
    is_primary_key: bool = False
    default_value: str | None = None
    position: int = 0
    comment: str | None = None


class ConstraintSchema(BaseModel):
    """Standardized constraint representation."""

    name: str
    constraint_type: ConstraintType
    fields: list[str] = Field(default_factory=list)
    referenced_entity: str | None = None
    referenced_fields: list[str] = Field(default_factory=list)


class EntitySchema(BaseModel):
    """Standardized representation of a table, view, or collection."""

    name: str
    namespace: str = "default"
    entity_type: str = "TABLE"  # TABLE, VIEW, COLLECTION
    fields: list[FieldSchema] = Field(default_factory=list)
    primary_key: list[str] = Field(default_factory=list)
    constraints: list[ConstraintSchema] = Field(default_factory=list)
    comment: str | None = None

    @property
    def field_count(self) -> int:
        return len(self.fields)

    def get_field(self, field_name: str) -> FieldSchema | None:
        for f in self.fields:
            if f.name == field_name:
                return f
        return None


class SourceSchema(BaseModel):
    """Standardized complete schema definition of an external source."""

    source_id: str
    source_name: str
    version: str = "1.0.0"
    discovered_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
    entities: list[EntitySchema] = Field(default_factory=list)
    metadata: dict[str, Any] = Field(default_factory=dict)

    @property
    def entity_count(self) -> int:
        return len(self.entities)

    @property
    def total_field_count(self) -> int:
        return sum(len(e.fields) for e in self.entities)
