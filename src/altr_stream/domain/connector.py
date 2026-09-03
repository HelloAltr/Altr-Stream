"""Connector contract and capabilities interface."""

from abc import ABC, abstractmethod
from typing import Any
from pydantic import BaseModel, Field

from altr_stream.domain.schema import SourceSchema
from altr_stream.domain.source import ConnectionConfig


class SourceCapabilities(BaseModel):
    """Capabilities exposed by a source connector."""

    schema_discovery: bool = True
    read: bool = True
    write: bool = True
    cdc: bool = False
    batch_execution: bool = True
    streaming: bool = False
    custom_query: bool = True
    supported_operations: list[str] = Field(
        default_factory=lambda: ["SELECT", "INSERT", "UPDATE", "DELETE", "SCHEMA_DISCOVERY"]
    )


class ConnectionTestResult(BaseModel):
    """Result of a connector connection test."""

    success: bool
    message: str
    latency_ms: float | None = None
    server_version: str | None = None
    error_details: str | None = None


class BaseConnector(ABC):
    """Abstract base connector interface for all physical data sources."""

    def __init__(self, config: ConnectionConfig):
        self.config = config

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

    async def close(self) -> None:
        """Clean up connection pools and resources."""
        pass
