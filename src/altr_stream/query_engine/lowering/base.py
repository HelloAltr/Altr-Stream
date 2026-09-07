"""Abstract base class for physical dialect query lowerers.

Lowerers accept a schema-bound BoundAltrQueryIR and translate it deterministically
into a target dialect's PhysicalQuery without performing any database I/O or network calls.
"""

from abc import ABC, abstractmethod

from altr_stream.query_engine.domain.bound_ast import BoundAltrQueryIR
from altr_stream.query_engine.domain.physical_query import PhysicalQuery


class QueryLowerer(ABC):
    """Abstract interface for pure, deterministic physical dialect query lowerers."""

    @abstractmethod
    def lower(self, query: BoundAltrQueryIR) -> PhysicalQuery:
        """Translate a schema-bound AltrQL IR into an executable physical query."""
        ...
