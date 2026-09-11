"""Data Transfer Objects for the REST API."""

from datetime import datetime, timezone
from typing import Any
from pydantic import BaseModel, Field

from altr_stream.domain.source import Source, SourceStatus, SourceType


class SourceCreateDTO(BaseModel):
    """Request payload for registering a new data source."""

    name: str = Field(..., min_length=1, max_length=255, description="Unique human-readable source name")
    type: SourceType = Field(default=SourceType.POSTGRESQL, description="Database connector type")
    host: str | None = Field(default=None, description="Database server hostname or IP")
    port: int | None = Field(default=None, ge=1, le=65535, description="Port number")
    database_name: str | None = Field(default=None, description="Target database name")
    username: str | None = Field(default=None, description="Database user name")
    password: str | None = Field(default=None, description="Database user password")
    file_path: str | None = Field(default=None, description="Local or absolute file path for file-based databases")
    test_connection_first: bool = Field(default=False, description="Test connection prior to saving")


class SourceUpdateDTO(BaseModel):
    """Request payload for updating an existing data source."""

    name: str | None = Field(default=None, min_length=1, max_length=255)
    host: str | None = None
    port: int | None = Field(default=None, ge=1, le=65535)
    database_name: str | None = None
    username: str | None = None
    password: str | None = None
    file_path: str | None = None


class SourceResponseDTO(BaseModel):
    """Safe response payload for a data source (never leaks plaintext password)."""

    id: str
    name: str
    type: SourceType
    host: str | None = None
    port: int | None = None
    database_name: str | None = None
    username: str | None = None
    file_path: str | None = None
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
            file_path=source.file_path,
            status=source.status,
            created_at=source.created_at,
            updated_at=source.updated_at,
            password_masked="••••••••" if source.password else "",
        )


class ConnectionTestRequestDTO(BaseModel):
    """Payload for testing connection without persisting a source."""

    type: SourceType = SourceType.POSTGRESQL
    host: str | None = None
    port: int | None = 5432
    database_name: str | None = None
    username: str | None = None
    password: str | None = None
    file_path: str | None = None


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
    mapping_id: str | None = Field(default=None, description="Optional SourceMapping ID for logical resolution")
    logical_model_id: str | None = Field(default=None, description="Optional LogicalModel ID for logical resolution")


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


class PhysicalQueryBatchDTO(BaseModel):
    """Physical query batch representation returned in AltrQL execution responses."""

    kind: str = "physical_query_batch"
    dialect: str = Field(..., description="Target database dialect name")
    queries: list[PhysicalQueryDTO] = Field(default_factory=list, description="Ordered physical queries in batch")
    source_id: str = Field(..., description="Target source ID")
    source_name: str = Field(..., description="Target source name")


class AltrQLExecuteRequestDTO(BaseModel):
    """Request payload for executing an AltrQL query against a registered data source."""

    query: str = Field(..., min_length=1, description="AltrQL query string to execute")
    source_id: str = Field(..., min_length=1, description="Registered data source ID to execute against")
    mapping_id: str | None = Field(default=None, description="Optional SourceMapping ID for logical resolution")
    logical_model_id: str | None = Field(default=None, description="Optional LogicalModel ID for logical resolution")
    confirm_mass_mutation: bool = Field(default=False, description="Explicit confirmation for mass mutations without WHERE filter")


class AltrQLExecuteResponseDTO(BaseModel):
    """Response payload for AltrQL execution requests."""

    success: bool = Field(..., description="Whether query compilation and physical execution succeeded")
    ir: dict[str, Any] | None = Field(default=None, description="Canonical AltrQueryIR AST")
    bound_ir: dict[str, Any] | None = Field(default=None, description="Schema-bound BoundAltrQueryIR AST")
    classification: MutationClassificationDTO | None = Field(default=None, description="Mutation classification metadata")
    physical_query: PhysicalQueryDTO | PhysicalQueryBatchDTO | None = Field(default=None, description="Lowered PhysicalQuery representation")
    columns: list[str] = Field(default_factory=list, description="Ordered list of column names")
    rows: list[dict[str, Any]] = Field(default_factory=list, description="Normalized rows formatted as JSON dictionaries")
    metadata: QueryMetadataDTO | None = Field(default=None, description="Query execution performance metadata")
    error: AltrQLErrorDetailDTO | None = Field(default=None, description="Diagnostic error details if failed")


# ==========================================
# Schema Registry DTOs (v0.7)
# ==========================================

class LogicalFieldCreateDTO(BaseModel):
    """Payload for creating a logical field."""

    name: str = Field(..., min_length=1, max_length=255, description="Field name")
    data_type: str = Field(default="STRING", description="Normalized StandardDataType")
    is_primary_key: bool = Field(default=False, description="Whether this field is part of the logical primary key")
    nullable: bool = Field(default=True, description="Whether this field allows NULL values")


class LogicalFieldUpdateDTO(BaseModel):
    """Payload for updating a logical field."""

    name: str | None = Field(default=None, min_length=1, max_length=255)
    data_type: str | None = None
    is_primary_key: bool | None = None
    nullable: bool | None = None


class LogicalFieldResponseDTO(BaseModel):
    """Response representation of a logical field."""

    id: str
    logical_entity_id: str
    name: str
    data_type: str
    is_primary_key: bool
    nullable: bool
    created_at: datetime
    updated_at: datetime

    @classmethod
    def from_domain(cls, field: Any) -> "LogicalFieldResponseDTO":
        return cls(
            id=field.id,
            logical_entity_id=field.logical_entity_id,
            name=field.name,
            data_type=field.data_type.value if hasattr(field.data_type, "value") else str(field.data_type),
            is_primary_key=field.is_primary_key,
            nullable=field.nullable,
            created_at=field.created_at,
            updated_at=field.updated_at,
        )


class LogicalEntityCreateDTO(BaseModel):
    """Payload for creating a logical entity."""

    name: str = Field(..., min_length=1, max_length=255, description="Entity name")
    description: str | None = Field(default=None, description="Optional entity description")
    fields: list[LogicalFieldCreateDTO] = Field(default_factory=list, description="Initial fields")


class LogicalEntityUpdateDTO(BaseModel):
    """Payload for updating a logical entity."""

    name: str | None = Field(default=None, min_length=1, max_length=255)
    description: str | None = None


class LogicalEntityResponseDTO(BaseModel):
    """Response representation of a logical entity."""

    id: str
    logical_model_id: str
    name: str
    description: str | None
    fields: list[LogicalFieldResponseDTO]
    field_count: int
    created_at: datetime
    updated_at: datetime

    @classmethod
    def from_domain(cls, entity: Any) -> "LogicalEntityResponseDTO":
        fields_dto = [LogicalFieldResponseDTO.from_domain(f) for f in entity.fields]
        return cls(
            id=entity.id,
            logical_model_id=entity.logical_model_id,
            name=entity.name,
            description=entity.description,
            fields=fields_dto,
            field_count=len(fields_dto),
            created_at=entity.created_at,
            updated_at=entity.updated_at,
        )


class LogicalModelCreateDTO(BaseModel):
    """Payload for creating a logical model."""

    name: str = Field(..., min_length=1, max_length=255, description="Unique model name")
    version: str = Field(default="1.0.0", max_length=50, description="Model semantic version")
    description: str | None = Field(default=None, description="Optional model description")
    entities: list[LogicalEntityCreateDTO] = Field(default_factory=list, description="Initial entities")


class LogicalModelUpdateDTO(BaseModel):
    """Payload for updating a logical model."""

    name: str | None = Field(default=None, min_length=1, max_length=255)
    version: str | None = Field(default=None, max_length=50)
    description: str | None = None


class LogicalModelResponseDTO(BaseModel):
    """Response representation of a logical model."""

    id: str
    name: str
    version: str
    description: str | None
    entities: list[LogicalEntityResponseDTO]
    entity_count: int
    total_field_count: int
    created_at: datetime
    updated_at: datetime

    @classmethod
    def from_domain(cls, model: Any) -> "LogicalModelResponseDTO":
        entities_dto = [LogicalEntityResponseDTO.from_domain(e) for e in model.entities]
        return cls(
            id=model.id,
            name=model.name,
            version=model.version,
            description=model.description,
            entities=entities_dto,
            entity_count=len(entities_dto),
            total_field_count=sum(len(e.fields) for e in entities_dto),
            created_at=model.created_at,
            updated_at=model.updated_at,
        )


class FieldMappingCreateDTO(BaseModel):
    """Payload for mapping a logical field to a physical column."""

    logical_field_id: str = Field(..., description="ID of the target logical field")
    logical_field_name: str | None = Field(default=None, description="Optional logical field name")
    physical_field_name: str = Field(..., min_length=1, description="Physical database column name")
    transformation_rule: str | None = Field(default=None, description="Optional transformation metadata (e.g. DIRECT_ALIAS)")


class FieldMappingResponseDTO(BaseModel):
    """Response representation of a field mapping."""

    id: str
    entity_mapping_id: str
    logical_field_id: str
    logical_field_name: str
    physical_field_name: str
    transformation_rule: str | None
    created_at: datetime
    updated_at: datetime

    @classmethod
    def from_domain(cls, fm: Any) -> "FieldMappingResponseDTO":
        return cls(
            id=fm.id,
            entity_mapping_id=fm.entity_mapping_id,
            logical_field_id=fm.logical_field_id,
            logical_field_name=fm.logical_field_name,
            physical_field_name=fm.physical_field_name,
            transformation_rule=fm.transformation_rule,
            created_at=fm.created_at,
            updated_at=fm.updated_at,
        )


class EntityMappingCreateDTO(BaseModel):
    """Payload for mapping a logical entity to a physical table/view."""

    logical_entity_id: str = Field(..., description="ID of the target logical entity")
    logical_entity_name: str | None = Field(default=None, description="Optional logical entity name")
    physical_entity_name: str = Field(..., min_length=1, description="Physical table or view name")
    physical_namespace: str = Field(default="public", description="Physical schema/namespace")
    field_mappings: list[FieldMappingCreateDTO] = Field(default_factory=list, description="Field mapping list")


class EntityMappingResponseDTO(BaseModel):
    """Response representation of an entity mapping."""

    id: str
    source_mapping_id: str
    logical_entity_id: str
    logical_entity_name: str
    physical_entity_name: str
    physical_namespace: str
    field_mappings: list[FieldMappingResponseDTO]
    field_mapping_count: int
    created_at: datetime
    updated_at: datetime

    @classmethod
    def from_domain(cls, em: Any) -> "EntityMappingResponseDTO":
        fms_dto = [FieldMappingResponseDTO.from_domain(fm) for fm in em.field_mappings]
        return cls(
            id=em.id,
            source_mapping_id=em.source_mapping_id,
            logical_entity_id=em.logical_entity_id,
            logical_entity_name=em.logical_entity_name,
            physical_entity_name=em.physical_entity_name,
            physical_namespace=em.physical_namespace,
            field_mappings=fms_dto,
            field_mapping_count=len(fms_dto),
            created_at=em.created_at,
            updated_at=em.updated_at,
        )


class SourceMappingCreateDTO(BaseModel):
    """Payload for creating a source mapping association."""

    logical_model_id: str = Field(..., description="Target logical model ID")
    source_id: str = Field(..., description="Target physical data source ID")
    version: str = Field(default="1.0.0", max_length=50)
    status: str = Field(default="DRAFT", description="Initial status (DRAFT, ACTIVE, VALIDATED, ERROR)")
    provenance: str = Field(default="USER", description="Mapping provenance (USER, ALTR_ALIGN, SYSTEM)")
    entity_mappings: list[EntityMappingCreateDTO] = Field(default_factory=list, description="Entity mappings")


class SourceMappingUpdateDTO(BaseModel):
    """Payload for updating a source mapping."""

    version: str | None = None
    status: str | None = None
    provenance: str | None = None
    error_message: str | None = None
    entity_mappings: list[EntityMappingCreateDTO] | None = None


class SourceMappingResponseDTO(BaseModel):
    """Response representation of a source mapping."""

    id: str
    logical_model_id: str
    source_id: str
    version: str
    status: str
    provenance: str
    error_message: str | None
    entity_mappings: list[EntityMappingResponseDTO]
    entity_mapping_count: int
    total_field_mapping_count: int
    created_at: datetime
    updated_at: datetime

    @classmethod
    def from_domain(cls, sm: Any) -> "SourceMappingResponseDTO":
        ems_dto = [EntityMappingResponseDTO.from_domain(em) for em in sm.entity_mappings]
        return cls(
            id=sm.id,
            logical_model_id=sm.logical_model_id,
            source_id=sm.source_id,
            version=sm.version,
            status=sm.status.value if hasattr(sm.status, "value") else str(sm.status),
            provenance=sm.provenance.value if hasattr(sm.provenance, "value") else str(sm.provenance),
            error_message=sm.error_message,
            entity_mappings=ems_dto,
            entity_mapping_count=len(ems_dto),
            total_field_mapping_count=sum(len(em.field_mappings) for em in ems_dto),
            created_at=sm.created_at,
            updated_at=sm.updated_at,
        )


class MappingValidationResponseDTO(BaseModel):
    """Response payload for mapping validation requests."""

    is_valid: bool
    error: str | None
    mapping: SourceMappingResponseDTO


class RegistrySummaryDTO(BaseModel):
    """Aggregated metrics for the Overview quick-launch card."""

    logical_models_count: int
    logical_entities_count: int
    logical_fields_count: int
    source_mappings_count: int
    entity_mappings_count: int
    field_mappings_count: int
    active_mappings_count: int
    draft_mappings_count: int

