"""Unit tests for QueryService application use cases."""

from unittest.mock import AsyncMock, MagicMock
import pytest
from sqlalchemy.ext.asyncio import AsyncSession

from altr_stream.application.query_service import QueryService
from altr_stream.domain.connector import BaseConnector, ConnectionTestResult, SourceCapabilities
from altr_stream.domain.errors import (
    QueryExecutionNotSupportedError,
    ReadOnlyQueryRequiredError,
    SourceNotFoundError,
)
from altr_stream.domain.query import QueryResult
from altr_stream.domain.schema import SourceSchema
from altr_stream.domain.source import ConnectionConfig, Source, SourceStatus, SourceType
from altr_stream.infrastructure.connectors.factory import ConnectorFactory
from altr_stream.infrastructure.database.repository import SqliteSourceRepository


class MockQueryConnector(BaseConnector):
    """Mock connector implementing execute_query for tests."""

    def __init__(self, config: ConnectionConfig, timeout_sec: float = 5.0, allow_read: bool = True):
        super().__init__(config, timeout_sec=timeout_sec)
        self.allow_read = allow_read

    async def test_connection(self) -> ConnectionTestResult:
        return ConnectionTestResult(success=True, message="OK")

    async def discover_schema(self, source_id: str, source_name: str) -> SourceSchema:
        return SourceSchema(source_id=source_id, source_name=source_name, entities=[])

    def get_capabilities(self) -> SourceCapabilities:
        return SourceCapabilities(
            schema_discovery=True,
            read=self.allow_read,
            entity_types=["TABLE"],
        )

    async def execute_query(self, query: str) -> QueryResult:
        return QueryResult(
            columns=["id", "name"],
            rows=[{"id": 1, "name": "Alice"}, {"id": 2, "name": "Bob"}],
            row_count=2,
            execution_time_ms=15.5,
        )


@pytest.mark.asyncio
async def test_execute_query_success(test_session: AsyncSession):
    repo = SqliteSourceRepository(test_session)
    service = QueryService(repo)

    source = Source(
        name="Production Postgres",
        type=SourceType.POSTGRESQL,
        host="localhost",
        port=5432,
        database_name="prod",
        username="postgres",
        password="password",
        status=SourceStatus.ACTIVE,
    )
    saved = await repo.create(source)

    # Mock connector execution
    mock_result = QueryResult(
        columns=["id", "email"],
        rows=[{"id": 10, "email": "test@example.com"}],
        row_count=1,
        execution_time_ms=5.2,
    )

    with pytest.MonkeyPatch.context() as mp:
        mock_connector = MagicMock(spec=BaseConnector)
        mock_connector.get_capabilities.return_value = SourceCapabilities(read=True)
        mock_connector.execute_query = AsyncMock(return_value=mock_result)
        mock_connector.__aenter__ = AsyncMock(return_value=mock_connector)
        mock_connector.__aexit__ = AsyncMock(return_value=None)

        mp.setattr(ConnectorFactory, "get_connector", lambda *args, **kwargs: mock_connector)

        result = await service.execute_query(saved.id, "SELECT * FROM users LIMIT 1;")
        assert result.row_count == 1
        assert result.columns == ["id", "email"]
        assert result.rows[0]["email"] == "test@example.com"
        assert result.execution_time_ms == 5.2


@pytest.mark.asyncio
async def test_execute_query_source_not_found(test_session: AsyncSession):
    repo = SqliteSourceRepository(test_session)
    service = QueryService(repo)

    with pytest.raises(SourceNotFoundError):
        await service.execute_query("non-existent-source-id", "SELECT 1;")


@pytest.mark.asyncio
async def test_execute_query_read_only_rejection(test_session: AsyncSession):
    repo = SqliteSourceRepository(test_session)
    service = QueryService(repo)

    source = Source(
        name="Source A",
        type=SourceType.POSTGRESQL,
        host="localhost",
        port=5432,
        database_name="db",
        username="u",
        password="p",
    )
    saved = await repo.create(source)

    with pytest.raises(ReadOnlyQueryRequiredError):
        await service.execute_query(saved.id, "DROP TABLE sensitive_data;")


@pytest.mark.asyncio
async def test_execute_query_capability_rejection(test_session: AsyncSession):
    repo = SqliteSourceRepository(test_session)
    service = QueryService(repo)

    source = Source(
        name="No-Read Source",
        type=SourceType.POSTGRESQL,
        host="localhost",
        port=5432,
        database_name="db",
        username="u",
        password="p",
    )
    saved = await repo.create(source)

    with pytest.MonkeyPatch.context() as mp:
        mock_connector = MagicMock(spec=BaseConnector)
        mock_connector.get_capabilities.return_value = SourceCapabilities(read=False)
        mock_connector.__aenter__ = AsyncMock(return_value=mock_connector)
        mock_connector.__aexit__ = AsyncMock(return_value=None)

        mp.setattr(ConnectorFactory, "get_connector", lambda *args, **kwargs: mock_connector)

        with pytest.raises(QueryExecutionNotSupportedError):
            await service.execute_query(saved.id, "SELECT 1;")
