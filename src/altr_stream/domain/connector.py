"""Connector contract and capabilities interface."""

from abc import ABC, abstractmethod
from enum import Enum
from typing import Any
from pydantic import BaseModel, Field

from altr_stream.domain.query import QueryResult
from altr_stream.domain.schema import SourceSchema
from altr_stream.domain.source import ConnectionConfig


class ParameterStyle(str, Enum):
    """Parameter binding style supported by a physical database dialect."""

    POSITIONAL_NUMERIC = "POSITIONAL_NUMERIC"  # e.g. $1, $2 (PostgreSQL)
    POSITIONAL_QMARK = "POSITIONAL_QMARK"      # e.g. ?, ? (SQLite, MySQL)
    NAMED = "NAMED"                            # e.g. :param (Oracle, SQLite named)


class SourceCapabilities(BaseModel):
    """High-level capabilities exposed by a physical source connector."""

    schema_discovery: bool = True
    read: bool = True
    write: bool = True
    cdc: bool = False
    batch_execution: bool = True
    streaming: bool = False
    custom_query: bool = False
    supports_transactions: bool = True
    supports_returning: bool = True
    supports_date_only_equality: bool = True
    parameter_style: ParameterStyle = ParameterStyle.POSITIONAL_NUMERIC
    max_batch_size: int | None = 1000
    entity_types: list[str] = Field(
        default_factory=list,
        description="Types of entities exposed by this source (e.g. TABLE, VIEW, COLLECTION)",
    )
    supported_operations: list[str] = Field(
        default_factory=list,
        description="Informational list of operations supported by the source engine",
    )


class ConnectionTestResult(BaseModel):
    """Result of a connector connection test."""

    success: bool
    message: str
    latency_ms: float | None = None
    server_version: str | None = None
    error_details: str | None = None


class BaseConnector(ABC):
    """Abstract base connector interface for all physical data sources with managed lifecycle."""

    def __init__(self, config: ConnectionConfig, timeout_sec: float = 5.0):
        self.config = config
        self.timeout_sec = timeout_sec
        self._is_initialized: bool = False

    async def initialize(self) -> None:
        """Initialize connection pools or persistent resources."""
        self._is_initialized = True

    async def close(self) -> None:
        """Clean up connection pools and resources."""
        self._is_initialized = False

    @abstractmethod
    async def test_connection(self) -> ConnectionTestResult:
        """Test if the physical data source is accessible with provided credentials."""
        ...

    @abstractmethod
    async def discover_schema(self, source_id: str, source_name: str) -> SourceSchema:
        """Discover and return the standardized schema of the physical data source."""
        ...

    @abstractmethod
    def get_capabilities(self) -> SourceCapabilities:
        """Return the capabilities supported by this connector."""
        ...

    @abstractmethod
    async def execute_query(self, query: str, parameters: list[Any] | None = None) -> QueryResult:
        """Execute a native database query and return normalized results."""
        ...

    async def execute_batch(self, queries: list[tuple[str, list[Any] | None]]) -> QueryResult:
        """Execute a sequence of native queries atomically and return combined results."""
        raise NotImplementedError("Batch query execution is not supported by this connector.")

    async def __aenter__(self) -> "BaseConnector":
        if not self._is_initialized:
            await self.initialize()
        return self

    async def __aexit__(self, exc_type: Any, exc_val: Any, exc_tb: Any) -> None:
        await self.close()

