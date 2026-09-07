"""Strongly-typed Physical Query representation for AltrQL v0.1.

Contains the database-specific executable query string and parameterized values
produced by lowering a schema-bound BoundAltrQueryIR.
"""

from __future__ import annotations

from typing import Any, List
from pydantic import Field

from altr_stream.query_engine.domain.ast import ASTNode


class PhysicalQuery(ASTNode):
    """Result of lowering a schema-bound AltrQL query into a database-specific executable query."""

    dialect: str = Field(..., description="Target database dialect name (e.g. 'postgresql')")
    query: str = Field(..., description="Executable native query string with positional parameter placeholders")
    parameters: List[Any] = Field(default_factory=list, description="Ordered literal values for query parameter placeholders")
    source_id: str = Field(..., description="Target source ID")
    source_name: str = Field(..., description="Target source name")
