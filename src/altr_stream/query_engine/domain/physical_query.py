"""Strongly-typed Physical Query representation for AltrQL v0.4.

Contains the database-specific executable query string and parameterized values
produced by lowering a schema-bound BoundAltrQueryIR.
"""

from __future__ import annotations

from typing import Any, List, Literal, Union
from pydantic import Field

from altr_stream.query_engine.domain.ast import ASTNode


class PhysicalQuery(ASTNode):
    """Result of lowering a schema-bound AltrQL query into a single database-specific executable query."""

    dialect: str = Field(..., description="Target database dialect name (e.g. 'postgresql')")
    query: str = Field(..., description="Executable native query string with positional parameter placeholders")
    parameters: List[Any] = Field(default_factory=list, description="Ordered literal values for query parameter placeholders")
    source_id: str = Field(..., description="Target source ID")
    source_name: str = Field(..., description="Target source name")


class PhysicalQueryBatch(ASTNode):
    """Result of lowering a schema-bound AltrQL query into multiple ordered physical queries (e.g. heterogeneous batch CREATE)."""

    kind: Literal["physical_query_batch"] = "physical_query_batch"
    dialect: str = Field(..., description="Target database dialect name (e.g. 'postgresql')")
    queries: List[PhysicalQuery] = Field(default_factory=list, description="Ordered list of physical queries to execute sequentially")
    source_id: str = Field(..., description="Target source ID")
    source_name: str = Field(..., description="Target source name")


PhysicalQueryResult = Union[PhysicalQuery, PhysicalQueryBatch]
