"""Data Transfer Objects for the REST API."""

from datetime import datetime, timezone
from typing import Any
from pydantic import BaseModel, Field

from altr_stream.domain.source import Source, SourceStatus, SourceType


class SourceCreateDTO(BaseModel):
    """Request payload for registering a new data source."""

    name: str = Field(..., min_length=1, max_length=255, description="Unique human-readable source name")
    type: SourceType = Field(default=SourceType.POSTGRESQL, description="Database connector type")
    host: str = Field(..., min_length=1, description="Database server hostname or IP")
    port: int = Field(default=5432, ge=1, le=65535, description="Port number")
    database_name: str = Field(..., min_length=1, description="Target database name")
    username: str = Field(..., min_length=1, description="Database user name")
    password: str = Field(..., description="Database user password")
    test_connection_first: bool = Field(default=False, description="Test connection prior to saving")


class SourceUpdateDTO(BaseModel):
    """Request payload for updating an existing data source."""

    name: str | None = Field(default=None, min_length=1, max_length=255)
    host: str | None = None
    port: int | None = Field(default=None, ge=1, le=65535)
    database_name: str | None = None
    username: str | None = None
    password: str | None = None


class SourceResponseDTO(BaseModel):
    """Safe response payload for a data source (never leaks plaintext password)."""

    id: str
    name: str
    type: SourceType
    host: str
    port: int
    database_name: str
    username: str
    status: SourceStatus
    created_at: datetime
    updated_at: datetime
    password_masked: str = "••••••••"

    @classmethod
    def from_domain(cls, source: Source) -> "SourceResponseDTO":
        return cls(
            id=source.id,
            name=source.name,
            type=source.type,
            host=source.host,
            port=source.port,
            database_name=source.database_name,
            username=source.username,
            status=source.status,
            created_at=source.created_at,
            updated_at=source.updated_at,
            password_masked="••••••••" if source.password else "",
        )


class ConnectionTestRequestDTO(BaseModel):
    """Payload for testing connection without persisting a source."""

    type: SourceType = SourceType.POSTGRESQL
    host: str
    port: int = 5432
    database_name: str
    username: str
    password: str


class ConnectionTestResponseDTO(BaseModel):
    """Response payload for connection test results."""

    success: bool
    message: str
    latency_ms: float | None = None
    server_version: str | None = None
    error_details: str | None = None


class HealthResponseDTO(BaseModel):
    """System health status response."""

    status: str = "healthy"
    version: str
    service: str = "Altr Stream"
    timestamp: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))


class QueryExecuteRequestDTO(BaseModel):
    """Request payload for executing a native database query in the Query Playground."""

    source_id: str = Field(..., min_length=1, description="Registered data source ID")
    query: str = Field(..., min_length=1, description="Native query to execute")


class QueryMetadataDTO(BaseModel):
    """Execution metadata for a query result."""

    row_count: int = Field(default=0, description="Number of rows returned")
    affected_rows: int | None = Field(default=None, description="Number of rows affected for command/mutation queries")
    execution_time_ms: float = Field(..., description="Execution duration in milliseconds")
    message: str | None = Field(default=None, description="Command status or outcome message")


class QueryExecuteResponseDTO(BaseModel):
    """Response payload for successful query execution."""

    success: bool = True
    columns: list[str] = Field(default_factory=list, description="Ordered list of column names")
    rows: list[dict[str, Any]] = Field(default_factory=list, description="Normalized rows formatted as JSON dictionaries")
    metadata: QueryMetadataDTO


class AltrQLParseRequestDTO(BaseModel):
    """Request payload for parsing an AltrQL query."""

    query: str = Field(..., min_length=1, description="AltrQL query string to parse")


class AltrQLParseErrorDetailDTO(BaseModel):
    """Structured diagnostic information for an AltrQL parsing/lexing error."""

    type: str = Field(..., description="Exception class name")
    message: str = Field(..., description="Human-readable error description")
    line: int | None = Field(default=None, description="1-indexed line number of the error")
    column: int | None = Field(default=None, description="1-indexed column number of the error")


class AltrQLParseResponseDTO(BaseModel):
    """Response payload for AltrQL parse requests."""

    success: bool = Field(..., description="Whether parsing succeeded")
    ir: dict[str, Any] | None = Field(default=None, description="Serialized AltrQueryIR AST if successful")
    error: AltrQLParseErrorDetailDTO | None = Field(default=None, description="Parse error details if failed")


