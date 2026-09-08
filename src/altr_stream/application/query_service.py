"""Query execution application service."""

from typing import Any

from altr_stream.domain.errors import (
    QueryExecutionNotSupportedError,
    SourceNotFoundError,
)
from altr_stream.domain.query import QueryResult
from altr_stream.domain.query_validation import validate_query
from altr_stream.infrastructure.connectors.factory import ConnectorFactory
from altr_stream.infrastructure.database.repository import SqliteSourceRepository


class QueryService:
    """Application use cases for native physical query execution."""

    def __init__(self, repository: SqliteSourceRepository):
        self.repository = repository

    async def execute_query(
        self, source_id: str, query: str, parameters: list[Any] | None = None
    ) -> QueryResult:
        """Validate, orchestrate, and execute a native query against a registered source."""
        # 1. Validate query format and ensure single-statement execution
        cleaned_query = validate_query(query)

        # 2. Verify source exists
        source = await self.repository.get_by_id(source_id)
        if not source:
            raise SourceNotFoundError(source_id)

        # 3. Resolve connector
        connector = ConnectorFactory.get_connector(source.type, source.connection_config)

        # 4. Check custom_query capability
        caps = connector.get_capabilities()
        if not caps.custom_query:
            raise QueryExecutionNotSupportedError(
                f"Connector for source '{source.name}' ({source.type.value}) does not support custom query execution."
            )

        # 5. Execute within connector context
        async with connector:
            return await connector.execute_query(cleaned_query, parameters=parameters)

    async def execute_batch(
        self, source_id: str, queries: list[tuple[str, list[Any] | None]]
    ) -> QueryResult:
        """Validate, orchestrate, and execute a sequence of queries atomically within a transaction."""
        cleaned_queries: list[tuple[str, list[Any] | None]] = []
        for q, p in queries:
            cleaned_queries.append((validate_query(q), p))

        # 2. Verify source exists
        source = await self.repository.get_by_id(source_id)
        if not source:
            raise SourceNotFoundError(source_id)

        # 3. Resolve connector
        connector = ConnectorFactory.get_connector(source.type, source.connection_config)

        # 4. Check custom_query capability
        caps = connector.get_capabilities()
        if not caps.custom_query:
            raise QueryExecutionNotSupportedError(
                f"Connector for source '{source.name}' ({source.type.value}) does not support custom query execution."
            )

        # 5. Execute within connector context
        async with connector:
            return await connector.execute_batch(cleaned_queries)


