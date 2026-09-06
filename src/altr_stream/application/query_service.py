"""Query execution application service."""

from altr_stream.domain.errors import (
    QueryExecutionNotSupportedError,
    SourceNotFoundError,
)
from altr_stream.domain.query import QueryResult
from altr_stream.domain.query_validation import validate_read_only_query
from altr_stream.infrastructure.connectors.factory import ConnectorFactory
from altr_stream.infrastructure.database.repository import SqliteSourceRepository


class QueryService:
    """Application use cases for native physical query execution."""

    def __init__(self, repository: SqliteSourceRepository):
        self.repository = repository

    async def execute_query(self, source_id: str, query: str) -> QueryResult:
        """Validate, orchestrate, and execute a native read-only query against a registered source."""
        # 1. Validate query format and read-only constraints
        cleaned_query = validate_read_only_query(query)

        # 2. Verify source exists
        source = await self.repository.get_by_id(source_id)
        if not source:
            raise SourceNotFoundError(source_id)

        # 3. Resolve connector
        connector = ConnectorFactory.get_connector(source.type, source.connection_config)

        # 4. Check capability
        caps = connector.get_capabilities()
        if not caps.read:
            raise QueryExecutionNotSupportedError(
                f"Connector for source '{source.name}' ({source.type.value}) does not support read query execution."
            )

        # 5. Execute within connector context
        async with connector:
            return await connector.execute_query(cleaned_query)
