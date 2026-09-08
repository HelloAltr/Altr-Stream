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
    operation: str | None = Field(default=None, description="Query operation type (READ, CREATE, UPDATE, DELETE)")
    mutation_scope: str | None = Field(default=None, description="Mutation scope (NOT_APPLICABLE, CONSTRAINED, MASS)")


class QueryExecuteResponseDTO(BaseModel):
    """Response payload for successful query execution."""

    success: bool = True
    columns: list[str] = Field(default_factory=list, description="Ordered list of column names")
    rows: list[dict[str, Any]] = Field(default_factory=list, description="Normalized rows formatted as JSON dictionaries")
    metadata: QueryMetadataDTO


class AltrQLParseRequestDTO(BaseModel):
    """Request payload for parsing an AltrQL query."""

    query: str = Field(..., min_length=1, description="AltrQL query string to parse")


class AltrQLErrorDetailDTO(BaseModel):
    """Generic structured diagnostic information for AltrQL lexing, parsing, semantic, and schema errors."""

    type: str = Field(..., description="Exception class name")
    message: str = Field(..., description="Human-readable error description")
    line: int | None = Field(default=None, description="1-indexed line number if available")
    column: int | None = Field(default=None, description="1-indexed column number if available")


# Alias for backward compatibility
AltrQLParseErrorDetailDTO = AltrQLErrorDetailDTO


class MutationClassificationDTO(BaseModel):
    """Classification metadata determining mutation properties and confirmation requirements."""

    operation: str = Field(..., description="Query operation (READ, CREATE, UPDATE, DELETE)")
    mutation_scope: str = Field(..., description="Scope of mutation (NOT_APPLICABLE, CONSTRAINED, MASS)")
    requires_confirmation: bool = Field(..., description="Whether client confirmation is required before execution")
    entity: str = Field(..., description="Target entity name")
    description: str = Field(..., description="Human-readable classification summary")


class AltrQLParseResponseDTO(BaseModel):
    """Response payload for AltrQL parse requests."""

    success: bool = Field(..., description="Whether parsing succeeded")
    ir: dict[str, Any] | None = Field(default=None, description="Serialized AltrQueryIR AST if successful")
    error: AltrQLErrorDetailDTO | None = Field(default=None, description="Parse error details if failed")


class AltrQLBindRequestDTO(BaseModel):
    """Request payload for binding an AltrQL query against a registered data source schema."""

    query: str = Field(..., min_length=1, description="AltrQL query string to bind")
    source_id: str = Field(..., min_length=1, description="Registered data source ID to bind against")


class AltrQLBindResponseDTO(BaseModel):
    """Response payload for AltrQL bind requests."""

    success: bool = Field(..., description="Whether schema binding and type validation succeeded")
    ir: dict[str, Any] | None = Field(default=None, description="Canonical AltrQueryIR AST")
    bound_ir: dict[str, Any] | None = Field(default=None, description="Schema-bound BoundAltrQueryIR AST if successful")
    classification: MutationClassificationDTO | None = Field(default=None, description="Mutation classification metadata if successful")
    error: AltrQLErrorDetailDTO | None = Field(default=None, description="Diagnostic error details if failed")


class PhysicalQueryDTO(BaseModel):
    """Physical query representation returned in AltrQL execution responses."""

    dialect: str = Field(..., description="Target database dialect name")
    query: str = Field(..., description="Executable physical SQL query string")
    parameters: list[Any] = Field(default_factory=list, description="Ordered literal values for parameters")
    source_id: str = Field(..., description="Target source ID")
    source_name: str = Field(..., description="Target source name")


class AltrQLExecuteRequestDTO(BaseModel):
    """Request payload for executing an AltrQL query against a registered data source."""

    query: str = Field(..., min_length=1, description="AltrQL query string to execute")
    source_id: str = Field(..., min_length=1, description="Registered data source ID to execute against")
    confirm_mass_mutation: bool = Field(default=False, description="Explicit confirmation for mass mutations without WHERE filter")


class AltrQLExecuteResponseDTO(BaseModel):
    """Response payload for AltrQL execution requests."""

    success: bool = Field(..., description="Whether query compilation and physical execution succeeded")
    ir: dict[str, Any] | None = Field(default=None, description="Canonical AltrQueryIR AST")
    bound_ir: dict[str, Any] | None = Field(default=None, description="Schema-bound BoundAltrQueryIR AST")
    classification: MutationClassificationDTO | None = Field(default=None, description="Mutation classification metadata")
    physical_query: PhysicalQueryDTO | None = Field(default=None, description="Lowered PhysicalQuery representation")
    columns: list[str] = Field(default_factory=list, description="Ordered list of column names")
    rows: list[dict[str, Any]] = Field(default_factory=list, description="Normalized rows formatted as JSON dictionaries")
    metadata: QueryMetadataDTO | None = Field(default=None, description="Query execution performance metadata")
    error: AltrQLErrorDetailDTO | None = Field(default=None, description="Diagnostic error details if failed")
