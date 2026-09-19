"""Source-agnostic query planning module for Altr Stream v0.9."""

from altr_stream.query_engine.planning.merger import (
    merge_federated_results,
    normalize_row,
)
from altr_stream.query_engine.planning.models import (
    CandidateEvaluation,
    FederatedQueryPlan,
    LogicalPlanContext,
    PhysicalQueryPlan,
)
from altr_stream.query_engine.planning.planner import QueryPlanner
from altr_stream.query_engine.planning.selector import SourceSelector

__all__ = [
    "CandidateEvaluation",
    "FederatedQueryPlan",
    "LogicalPlanContext",
    "PhysicalQueryPlan",
    "QueryPlanner",
    "SourceSelector",
    "merge_federated_results",
    "normalize_row",
]

