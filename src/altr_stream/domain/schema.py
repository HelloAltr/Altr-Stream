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
    namespace: str = "public"
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
