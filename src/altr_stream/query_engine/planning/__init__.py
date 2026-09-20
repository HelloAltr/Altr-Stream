"""Source-agnostic query planning module for Altr Stream."""

from altr_stream.query_engine.planning.merger import (
    merge_federated_results,
    normalize_row,
)
from altr_stream.query_engine.planning.models import (
    CandidateEvaluation,
    EphemeralFieldProjection,
    EphemeralLogicalProjection,
    FederatedQueryPlan,
    LogicalPlanContext,
    PhysicalQueryPlan,
    SourceExclusionInfo,
    SourceExclusionReason,
    SourceExecutionStatus,
)
from altr_stream.query_engine.planning.planner import QueryPlanner
from altr_stream.query_engine.planning.selector import SourceSelector

__all__ = [
    "CandidateEvaluation",
    "EphemeralFieldProjection",
    "EphemeralLogicalProjection",
    "FederatedQueryPlan",
    "LogicalPlanContext",
    "PhysicalQueryPlan",
    "QueryPlanner",
    "SourceExclusionInfo",
    "SourceExclusionReason",
    "SourceExecutionStatus",
    "SourceSelector",
    "merge_federated_results",
    "normalize_row",
]

