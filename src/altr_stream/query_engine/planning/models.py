"""Data structures and models for source-agnostic query planning."""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any

from enum import Enum
from altr_stream.domain.source import SourceType
from altr_stream.query_engine.classification.classifier import MutationClassification
from altr_stream.query_engine.domain.ast import AltrQueryIR, QueryOperation
from altr_stream.query_engine.domain.bound_ast import BoundAltrQueryIR
from altr_stream.query_engine.domain.physical_query import (
    PhysicalQuery,
    PhysicalQueryBatch,
    PhysicalQueryResult,
)


class SourceExecutionStatus(str, Enum):
    """Outcome status for a physical source in planning or execution."""

    SUCCESS = "SUCCESS"
    FAILED = "FAILED"
    EXCLUDED = "EXCLUDED"


class SourceExclusionReason(str, Enum):
    """Deterministic diagnostic reason codes for excluded or failed sources."""

    PHYSICAL_ENTITY_NOT_FOUND = "PHYSICAL_ENTITY_NOT_FOUND"
    NO_ACTIVE_MAPPING = "NO_ACTIVE_MAPPING"
    INCOMPLETE_FIELD_MAPPING = "INCOMPLETE_FIELD_MAPPING"
    SOURCE_CAPABILITY_MISMATCH = "SOURCE_CAPABILITY_MISMATCH"
    SOURCE_UNREACHABLE = "SOURCE_UNREACHABLE"
    EXECUTION_FAILED = "EXECUTION_FAILED"
    EXECUTION_TIMEOUT = "EXECUTION_TIMEOUT"
    NORMALIZATION_FAILED = "NORMALIZATION_FAILED"


@dataclass
class SourceExclusionInfo:
    """Structured diagnostic record for an excluded or failed source."""

    source_id: str
    source_name: str | None = None
    source_type: str | None = None
    physical_entity: str | None = None
    status: str = SourceExecutionStatus.EXCLUDED.value
    reason_code: str = SourceExclusionReason.PHYSICAL_ENTITY_NOT_FOUND.value
    message: str = ""

    def to_dict(self) -> dict[str, Any]:
        return {
            "source_id": self.source_id,
            "source_name": self.source_name,
            "source_type": self.source_type,
            "physical_entity": self.physical_entity,
            "status": self.status,
            "reason_code": self.reason_code,
            "message": self.message,
        }


@dataclass
class EphemeralFieldProjection:
    """Canonical field in an ephemeral logical projection."""

    name: str
    data_type: str = "STRING"
    is_primary_key: bool = False
    source_field_names: dict[str, str] = field(default_factory=dict)

    def to_dict(self) -> dict[str, Any]:
        return {
            "name": self.name,
            "data_type": self.data_type,
            "is_primary_key": self.is_primary_key,
            "source_field_names": self.source_field_names,
        }


@dataclass
class EphemeralLogicalProjection:
    """In-memory logical projection synthesized from discovered physical schemas."""

    entity_name: str
    canonical_fields: list[EphemeralFieldProjection] = field(default_factory=list)
    participating_sources: list[str] = field(default_factory=list)
    excluded_sources: list[SourceExclusionInfo] = field(default_factory=list)
    is_ephemeral: bool = True

    def to_dict(self) -> dict[str, Any]:
        return {
            "entity_name": self.entity_name,
            "canonical_fields": [f.to_dict() for f in self.canonical_fields],
            "participating_sources": self.participating_sources,
            "excluded_sources": [e.to_dict() for e in self.excluded_sources],
            "is_ephemeral": self.is_ephemeral,
        }


@dataclass
class CandidateEvaluation:
    """Diagnostic evaluation record for a candidate source mapping."""

    source_id: str
    source_name: str
    source_type: SourceType
    mapping_id: str
    physical_entity_name: str
    is_eligible: bool
    rejection_reason: str | None = None
    unmapped_fields: list[str] = field(default_factory=list)
    missing_capabilities: list[str] = field(default_factory=list)

    def to_dict(self) -> dict[str, Any]:
        """Convert evaluation record to dictionary for logging and API responses."""
        return {
            "source_id": self.source_id,
            "source_name": self.source_name,
            "source_type": self.source_type.value,
            "mapping_id": self.mapping_id,
            "physical_entity_name": self.physical_entity_name,
            "is_eligible": self.is_eligible,
            "rejection_reason": self.rejection_reason,
            "unmapped_fields": self.unmapped_fields,
            "missing_capabilities": self.missing_capabilities,
        }


@dataclass
class LogicalPlanContext:
    """Encapsulates the logical intent and requirements extracted from a canonical IR."""

    logical_model_id: str | None = None
    target_entity: str = ""
    operation: QueryOperation = QueryOperation.READ
    is_wildcard: bool = True
    projected_fields: list[str] = field(default_factory=list)
    filter_fields: list[str] = field(default_factory=list)
    mutation_fields: list[str] = field(default_factory=list)
    sort_fields: list[str] = field(default_factory=list)
    requires_returning: bool = False
    requires_transactions: bool = False

    @property
    def all_referenced_fields(self) -> set[str]:
        """Return all distinct logical field names referenced in this query."""
        fields: set[str] = set()
        fields.update(self.projected_fields)
        fields.update(self.filter_fields)
        fields.update(self.mutation_fields)
        fields.update(self.sort_fields)
        return fields


@dataclass
class PhysicalQueryPlan:
    """The fully compiled and lowered execution plan bound to a single physical datasource."""

    logical_model_id: str
    target_entity: str
    selected_source_id: str
    selected_source_name: str
    selected_source_type: SourceType
    selected_mapping_id: str
    physical_entity_name: str
    resolved_ir: AltrQueryIR
    bound_ir: BoundAltrQueryIR
    classification: MutationClassification
    physical_query: PhysicalQueryResult
    logical_to_physical_map: dict[str, str] = field(default_factory=dict)
    physical_to_logical_map: dict[str, str] = field(default_factory=dict)
    candidates_evaluated: list[CandidateEvaluation] = field(default_factory=list)


@dataclass
class FederatedQueryPlan:
    """A federated execution plan targeting multiple physical datasources."""

    logical_model_id: str
    target_entity: str
    logical_ir: AltrQueryIR
    physical_plans: list[PhysicalQueryPlan] = field(default_factory=list)
    candidates_evaluated: list[CandidateEvaluation] = field(default_factory=list)
    excluded_sources: list[SourceExclusionInfo] = field(default_factory=list)
    execution_mode: str = "federated"
    is_ephemeral: bool = False
    ephemeral_projection: EphemeralLogicalProjection | None = None

    @property
    def accepted_sources(self) -> list[str]:
        """List of source IDs for which physical plans were successfully compiled."""
        return [p.selected_source_id for p in self.physical_plans]

    @property
    def rejected_sources(self) -> list[str]:
        """List of source IDs that were evaluated and rejected."""
        return [e.source_id for e in self.candidates_evaluated if not e.is_eligible]

    @property
    def total_sources_planned(self) -> int:
        """Total number of physical sources participating in the federated execution."""
        return len(self.physical_plans)

