"""Logical Data Model domain definitions for Altr Stream v0.7.

Represents vendor-neutral, canonical business models, entities, and fields
independent of physical database catalogs.
"""

from datetime import datetime, timezone
from typing import Any
import uuid
from pydantic import BaseModel, Field

from altr_stream.domain.schema import StandardDataType


class LogicalField(BaseModel):
    """Normalized logical field definition."""

    id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    logical_entity_id: str
    name: str
    data_type: StandardDataType = StandardDataType.STRING
    is_primary_key: bool = False
    nullable: bool = True
    created_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
    updated_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))


class LogicalEntity(BaseModel):
    """Normalized logical business/data entity."""

    id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    logical_model_id: str
    name: str
    description: str | None = None
    fields: list[LogicalField] = Field(default_factory=list)
    created_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
    updated_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))

    @property
    def field_count(self) -> int:
        return len(self.fields)

    def get_field_by_id(self, field_id: str) -> LogicalField | None:
        for f in self.fields:
            if f.id == field_id:
                return f
        return None

    def get_field_by_name(self, field_name: str) -> LogicalField | None:
        for f in self.fields:
            if f.name == field_name:
                return f
        return None


class LogicalModel(BaseModel):
    """Container for a cohesive set of logical entities and relationships."""

    id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    name: str
    version: str = "1.0.0"
    description: str | None = None
    entities: list[LogicalEntity] = Field(default_factory=list)
    created_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
    updated_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))

    @property
    def entity_count(self) -> int:
        return len(self.entities)

    @property
    def total_field_count(self) -> int:
        return sum(len(e.fields) for e in self.entities)

    def get_entity_by_id(self, entity_id: str) -> LogicalEntity | None:
        for e in self.entities:
            if e.id == entity_id:
                return e
        return None

    def get_entity_by_name(self, entity_name: str) -> LogicalEntity | None:
        for e in self.entities:
            if e.name == entity_name:
                return e
        return None
