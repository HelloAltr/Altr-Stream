"""Domain layer exceptions."""


class AltrStreamError(Exception):
    """Base domain exception for Altr Stream."""

    def __init__(self, message: str):
        super().__init__(message)
        self.message = message


class SourceNotFoundError(AltrStreamError):
    """Raised when a requested data source cannot be found."""

    def __init__(self, source_id: str):
        super().__init__(f"Source with id '{source_id}' was not found.")
        self.source_id = source_id


class SourceAlreadyExistsError(AltrStreamError):
    """Raised when a source name or configuration already exists."""

    def __init__(self, name: str):
        super().__init__(f"Source with name '{name}' already exists.")
        self.name = name


class ConnectorNotFoundError(AltrStreamError):
    """Raised when no connector implementation exists for a source type."""

    def __init__(self, source_type: str):
        super().__init__(f"No connector implementation registered for source type '{source_type}'.")
        self.source_type = source_type


class ConnectionFailedError(AltrStreamError):
    """Raised when testing or establishing a connection fails."""

    def __init__(self, message: str, details: str | None = None):
        super().__init__(message)
        self.details = details


class SchemaDiscoveryError(AltrStreamError):
    """Raised when schema introspection fails."""

    def __init__(self, message: str, details: str | None = None):
        super().__init__(message)
        self.details = details


class ReadOnlyQueryRequiredError(AltrStreamError):
    """Raised when a non-read or destructive query is submitted to the Query Playground."""

    def __init__(self, message: str = "Query Playground is restricted to read-only queries (SELECT, WITH, EXPLAIN)."):
        super().__init__(message)


class QueryExecutionError(AltrStreamError):
    """Raised when physical query execution fails in the database engine."""

    def __init__(self, message: str, details: str | None = None):
        super().__init__(message)
        self.details = details


class QueryExecutionNotSupportedError(AltrStreamError):
    """Raised when a connector or source does not support query execution."""

    def __init__(self, message: str):
        super().__init__(message)


class LogicalModelNotFoundError(AltrStreamError):
    """Raised when a requested logical model cannot be found."""

    def __init__(self, model_id: str):
        super().__init__(f"Logical model with id '{model_id}' was not found.")
        self.model_id = model_id


class LogicalModelAlreadyExistsError(AltrStreamError):
    """Raised when a logical model name already exists."""

    def __init__(self, name: str):
        super().__init__(f"Logical model with name '{name}' already exists.")
        self.name = name


class LogicalEntityNotFoundError(AltrStreamError):
    """Raised when a logical entity cannot be found in a model."""

    def __init__(self, entity_id_or_name: str, model_id: str | None = None):
        msg = f"Logical entity '{entity_id_or_name}' was not found"
        if model_id:
            msg += f" in model '{model_id}'"
        super().__init__(msg + ".")
        self.entity_id_or_name = entity_id_or_name
        self.model_id = model_id


class LogicalFieldNotFoundError(AltrStreamError):
    """Raised when a logical field cannot be found in an entity."""

    def __init__(self, field_id_or_name: str, entity_id: str | None = None):
        msg = f"Logical field '{field_id_or_name}' was not found"
        if entity_id:
            msg += f" in entity '{entity_id}'"
        super().__init__(msg + ".")
        self.field_id_or_name = field_id_or_name
        self.entity_id = entity_id


class SourceMappingNotFoundError(AltrStreamError):
    """Raised when a source mapping cannot be found."""

    def __init__(self, mapping_id: str):
        super().__init__(f"Source mapping with id '{mapping_id}' was not found.")
        self.mapping_id = mapping_id


class MappingValidationError(AltrStreamError):
    """Raised when mapping validation fails against physical schema."""

    def __init__(self, message: str, details: str | None = None):
        super().__init__(message)
        self.details = details


class DuplicateMappingError(AltrStreamError):
    """Raised when a duplicate mapping is registered."""

    def __init__(self, message: str):
        super().__init__(message)

