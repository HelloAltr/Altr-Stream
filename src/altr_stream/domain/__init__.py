"""Domain layer for Altr Stream."""

from altr_stream.domain.errors import (
    AltrStreamError,
    ConnectionFailedError,
    ConnectorNotFoundError,
    SchemaDiscoveryError,
    SourceAlreadyExistsError,
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

__all__ = [
    "AltrStreamError",
    "SourceNotFoundError",
    "SourceAlreadyExistsError",
    "ConnectorNotFoundError",
    "ConnectionFailedError",
    "SchemaDiscoveryError",
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
]
