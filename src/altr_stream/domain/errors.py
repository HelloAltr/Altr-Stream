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
