"""Domain layer for Altr Stream."""

from altr_stream.domain.errors import (
    AltrStreamError,
    ConnectionFailedError,
    ConnectorNotFoundError,
    DuplicateMappingError,
    LogicalEntityNotFoundError,
    LogicalFieldNotFoundError,
    LogicalModelAlreadyExistsError,
    LogicalModelNotFoundError,
    MappingValidationError,
    QueryExecutionError,
    QueryExecutionNotSupportedError,
    ReadOnlyQueryRequiredError,
    SchemaDiscoveryError,
    SourceAlreadyExistsError,
    SourceMappingNotFoundError,
    SourceNotFoundError,
)
from altr_stream.domain.source import (
    ConnectionConfig,
    Source,
    SourceStatus,
    SourceType,
)
from altr_stream.domain.schema import (
    ConstraintSchema,
    ConstraintType,
    EntitySchema,
    FieldSchema,
    SourceSchema,
    StandardDataType,
)
from altr_stream.domain.connector import (
    BaseConnector,
    ConnectionTestResult,
    SourceCapabilities,
)
from altr_stream.domain.logical import (
    LogicalEntity,
    LogicalField,
    LogicalModel,
)
from altr_stream.domain.mapping import (
    EntityMapping,
    FieldMapping,
    MappingProvenance,
    MappingStatus,
    SourceMapping,
)

__all__ = [
    "AltrStreamError",
    "SourceNotFoundError",
    "SourceAlreadyExistsError",
    "ConnectorNotFoundError",
    "ConnectionFailedError",
    "SchemaDiscoveryError",
    "LogicalModelNotFoundError",
    "LogicalModelAlreadyExistsError",
    "LogicalEntityNotFoundError",
    "LogicalFieldNotFoundError",
    "SourceMappingNotFoundError",
    "MappingValidationError",
    "DuplicateMappingError",
    "QueryExecutionError",
    "QueryExecutionNotSupportedError",
    "ReadOnlyQueryRequiredError",
    "Source",
    "SourceType",
    "SourceStatus",
    "ConnectionConfig",
    "StandardDataType",
    "ConstraintType",
    "FieldSchema",
    "ConstraintSchema",
    "EntitySchema",
    "SourceSchema",
    "BaseConnector",
    "ConnectionTestResult",
    "SourceCapabilities",
    "LogicalModel",
    "LogicalEntity",
    "LogicalField",
    "SourceMapping",
    "EntityMapping",
    "FieldMapping",
    "MappingStatus",
    "MappingProvenance",
]

