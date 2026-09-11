"""Mapping Registry domain definitions for Altr Stream v0.7.

Represents deterministic mappings between canonical Logical Models
and discovered physical database schemas.
"""

from datetime import datetime, timezone
from enum import Enum
from typing import Any
import uuid
from pydantic import BaseModel, Field


class MappingStatus(str, Enum):
    """Lifecycle status of a source mapping."""

    DRAFT = "DRAFT"
    ACTIVE = "ACTIVE"
    VALIDATED = "VALIDATED"
    ERROR = "ERROR"


class MappingProvenance(str, Enum):
    """Origin/creator of a mapping rule."""

    USER = "USER"
    ALTR_ALIGN = "ALTR_ALIGN"
    SYSTEM = "SYSTEM"


class FieldMapping(BaseModel):
    """Deterministic mapping from a logical field to a physical column."""

    id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    entity_mapping_id: str
    logical_field_id: str
    logical_field_name: str
    physical_field_name: str
    transformation_rule: str | None = None
    created_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
    updated_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))


class EntityMapping(BaseModel):
    """Mapping from a logical entity to a physical table, view, or collection."""

    id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    source_mapping_id: str
    logical_entity_id: str
    logical_entity_name: str
    physical_entity_name: str
    physical_namespace: str = "public"
    field_mappings: list[FieldMapping] = Field(default_factory=list)
    created_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
    updated_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))

    @property
    def field_mapping_count(self) -> int:
        return len(self.field_mappings)

    def get_field_mapping_by_logical_name(self, name: str) -> FieldMapping | None:
        for fm in self.field_mappings:
            if fm.logical_field_name == name:
                return fm
        return None

    def get_field_mapping_by_logical_id(self, field_id: str) -> FieldMapping | None:
        for fm in self.field_mappings:
            if fm.logical_field_id == field_id:
                return fm
        return None


class SourceMapping(BaseModel):
    """Association binding a LogicalModel to a physical Source with approved entity/field mappings."""

    id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    logical_model_id: str
    source_id: str
    version: str = "1.0.0"
    status: MappingStatus = MappingStatus.DRAFT
    provenance: MappingProvenance = MappingProvenance.USER
    error_message: str | None = None
    entity_mappings: list[EntityMapping] = Field(default_factory=list)
    created_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
    updated_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))

    @property
    def entity_mapping_count(self) -> int:
        return len(self.entity_mappings)

    @property
    def total_field_mapping_count(self) -> int:
        return sum(len(em.field_mappings) for em in self.entity_mappings)

    def get_entity_mapping_by_logical_name(self, name: str) -> EntityMapping | None:
        for em in self.entity_mappings:
            if em.logical_entity_name == name:
                return em
        return None

    def get_entity_mapping_by_logical_id(self, entity_id: str) -> EntityMapping | None:
        for em in self.entity_mappings:
            if em.logical_entity_id == entity_id:
                return em
        return None
