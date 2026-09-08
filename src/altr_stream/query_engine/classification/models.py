"""Classification models for AltrQL queries and mutations."""

from __future__ import annotations

from enum import Enum
from typing import Any, Dict
from pydantic import BaseModel, ConfigDict

from altr_stream.query_engine.domain.ast import QueryOperation


class MutationScope(str, Enum):
    """Scope of affected records for a query."""

    NOT_APPLICABLE = "NOT_APPLICABLE"
    CONSTRAINED = "CONSTRAINED"
    MASS = "MASS"


class MutationClassification(BaseModel):
    """Classification metadata determining mutation properties and confirmation requirements."""

    model_config = ConfigDict(frozen=True, extra="forbid")

    operation: QueryOperation
    mutation_scope: MutationScope
    requires_confirmation: bool
    entity: str
    description: str

    def to_dict(self) -> Dict[str, Any]:
        return self.model_dump()
