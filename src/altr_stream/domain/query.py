"""Domain models for query execution and results."""

from typing import Any
from pydantic import BaseModel, Field


class QueryExecutionRequest(BaseModel):
    """Domain request for executing a native database query."""

    source_id: str
    query: str


class QueryResult(BaseModel):
    """Vendor-neutral normalized representation of physical query execution results."""

    columns: list[str] = Field(default_factory=list)
    rows: list[dict[str, Any]] = Field(default_factory=list)
    row_count: int = 0
    affected_rows: int | None = None
    message: str | None = None
    execution_time_ms: float = 0.0

