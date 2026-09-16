"""Unit tests for QueryService application use cases."""

from unittest.mock import AsyncMock, MagicMock
import pytest
from sqlalchemy.ext.asyncio import AsyncSession

from altr_stream.application.query_service import QueryService
from altr_stream.domain.connector import BaseConnector, ConnectionTestResult, SourceCapabilities
from altr_stream.domain.errors import (
    QueryExecutionError,
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

    def __init__(self, config: ConnectionConfig, timeout_sec: float = 5.0, allow_custom_query: bool = True):
        super().__init__(config, timeout_sec=timeout_sec)
        self.allow_custom_query = allow_custom_query

    async def test_connection(self) -> ConnectionTestResult:
        return ConnectionTestResult(success=True, message="OK")

    async def discover_schema(self, source_id: str, source_name: str) -> SourceSchema:
        return SourceSchema(source_id=source_id, source_name=source_name, entities=[])

    def get_capabilities(self) -> SourceCapabilities:
        return SourceCapabilities(
            schema_discovery=True,
            custom_query=self.allow_custom_query,
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
async def test_execute_query_success_result_set(test_session: AsyncSession):
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
        mock_connector.get_capabilities.return_value = SourceCapabilities(custom_query=True)
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
async def test_execute_query_success_command_mutation(test_session: AsyncSession):
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

    mock_result = QueryResult(
        columns=[],
        rows=[],
        row_count=0,
        affected_rows=3,
        message="UPDATE 3",
        execution_time_ms=12.1,
    )

    with pytest.MonkeyPatch.context() as mp:
        mock_connector = MagicMock(spec=BaseConnector)
        mock_connector.get_capabilities.return_value = SourceCapabilities(custom_query=True)
        mock_connector.execute_query = AsyncMock(return_value=mock_result)
        mock_connector.__aenter__ = AsyncMock(return_value=mock_connector)
        mock_connector.__aexit__ = AsyncMock(return_value=None)

        mp.setattr(ConnectorFactory, "get_connector", lambda *args, **kwargs: mock_connector)

        result = await service.execute_query(saved.id, "UPDATE users SET active = true;")
        assert result.row_count == 0
        assert result.affected_rows == 3
        assert result.message == "UPDATE 3"
        assert result.execution_time_ms == 12.1


@pytest.mark.asyncio
async def test_execute_query_source_not_found(test_session: AsyncSession):
    repo = SqliteSourceRepository(test_session)
    service = QueryService(repo)

    with pytest.raises(SourceNotFoundError):
        await service.execute_query("non-existent-source-id", "SELECT 1;")


@pytest.mark.asyncio
async def test_execute_query_multi_statement_rejection(test_session: AsyncSession):
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
        await service.execute_query(saved.id, "SELECT 1; DROP TABLE sensitive_data;")


@pytest.mark.asyncio
async def test_execute_query_capability_rejection(test_session: AsyncSession):
    repo = SqliteSourceRepository(test_session)
    service = QueryService(repo)

    source = Source(
        name="No-Custom-Query Source",
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
        mock_connector.get_capabilities.return_value = SourceCapabilities(custom_query=False)
        mock_connector.__aenter__ = AsyncMock(return_value=mock_connector)
        mock_connector.__aexit__ = AsyncMock(return_value=None)

        mp.setattr(ConnectorFactory, "get_connector", lambda *args, **kwargs: mock_connector)

        with pytest.raises(QueryExecutionNotSupportedError):
            await service.execute_query(saved.id, "SELECT 1;")


@pytest.mark.asyncio
async def test_execute_query_mongodb_command(test_session: AsyncSession):
    repo = SqliteSourceRepository(test_session)
    service = QueryService(repo)

    source = Source(
        name="Mongo DB Source",
        type=SourceType.MONGODB,
        host="localhost",
        port=27017,
        database_name="altr_test_db",
        username="user",
        password="password",
        status=SourceStatus.ACTIVE,
    )
    saved = await repo.create(source)

    mock_result = QueryResult(
        columns=["_id", "name"],
        rows=[{"_id": "507f1f77bcf86cd799439011", "name": "Alice"}],
        row_count=1,
        execution_time_ms=8.0,
    )

    with pytest.MonkeyPatch.context() as mp:
        mock_connector = MagicMock(spec=BaseConnector)
        mock_connector.get_capabilities.return_value = SourceCapabilities(custom_query=True)
        mock_connector.execute_query = AsyncMock(return_value=mock_result)
        mock_connector.__aenter__ = AsyncMock(return_value=mock_connector)
        mock_connector.__aexit__ = AsyncMock(return_value=None)

        mp.setattr(ConnectorFactory, "get_connector", lambda *args, **kwargs: mock_connector)

        spec = {"collection": "users", "filter": {}}
        result = await service.execute_query(saved.id, "mongodb:find", parameters=[spec])
        assert result.row_count == 1
        assert result.columns == ["_id", "name"]
        mock_connector.execute_query.assert_awaited_once_with("mongodb:find", parameters=[spec])


@pytest.mark.asyncio
async def test_execute_query_mongodb_playground_raw_json_find(test_session: AsyncSession):
    """Verify that a raw JSON query from Playground without parameters reaches connector as mongodb:find with parameters=[dict]."""
    repo = SqliteSourceRepository(test_session)
    service = QueryService(repo)

    source = Source(
        name="Mongo Playground Source",
        type=SourceType.MONGODB,
        host="localhost",
        port=27017,
        database_name="altr_test_db",
        username="user",
        password="password",
        status=SourceStatus.ACTIVE,
    )
    saved = await repo.create(source)

    mock_result = QueryResult(
        columns=["_id", "username"],
        rows=[{"_id": "507f1f77bcf86cd799439011", "username": "alice"}],
        row_count=1,
        execution_time_ms=7.2,
    )

    with pytest.MonkeyPatch.context() as mp:
        mock_connector = MagicMock(spec=BaseConnector)
        mock_connector.get_capabilities.return_value = SourceCapabilities(custom_query=True)
        mock_connector.execute_query = AsyncMock(return_value=mock_result)
        mock_connector.__aenter__ = AsyncMock(return_value=mock_connector)
        mock_connector.__aexit__ = AsyncMock(return_value=None)

        mp.setattr(ConnectorFactory, "get_connector", lambda *args, **kwargs: mock_connector)

        playground_json = '{\n  "collection": "users",\n  "filter": {}\n}'
        result = await service.execute_query(saved.id, playground_json)

        assert result.row_count == 1
        assert result.columns == ["_id", "username"]
        mock_connector.execute_query.assert_awaited_once_with(
            "mongodb:find",
            parameters=[{"collection": "users", "filter": {}}],
        )


@pytest.mark.asyncio
async def test_execute_query_mongodb_playground_raw_json_projection_sort_limit_skip(test_session: AsyncSession):
    """Verify that projection, sort, limit, and skip in Playground JSON reach connector parameters intact."""
    repo = SqliteSourceRepository(test_session)
    service = QueryService(repo)

    source = Source(
        name="Mongo Playground Source",
        type=SourceType.MONGODB,
        host="localhost",
        port=27017,
        database_name="altr_test_db",
        username="user",
        password="password",
        status=SourceStatus.ACTIVE,
    )
    saved = await repo.create(source)

    mock_result = QueryResult(
        columns=["_id", "username", "email"],
        rows=[{"_id": "507f1f77bcf86cd799439011", "username": "alice", "email": "alice@example.com"}],
        row_count=1,
        execution_time_ms=6.5,
    )

    with pytest.MonkeyPatch.context() as mp:
        mock_connector = MagicMock(spec=BaseConnector)
        mock_connector.get_capabilities.return_value = SourceCapabilities(custom_query=True)
        mock_connector.execute_query = AsyncMock(return_value=mock_result)
        mock_connector.__aenter__ = AsyncMock(return_value=mock_connector)
        mock_connector.__aexit__ = AsyncMock(return_value=None)

        mp.setattr(ConnectorFactory, "get_connector", lambda *args, **kwargs: mock_connector)

        playground_json = """{
            "collection": "users",
            "filter": {"active": true},
            "projection": {"_id": 1, "username": 1, "email": 1},
            "sort": [["_id", -1]],
            "limit": 10,
            "skip": 5
        }"""
        result = await service.execute_query(saved.id, playground_json)

        assert result.row_count == 1
        mock_connector.execute_query.assert_awaited_once_with(
            "mongodb:find",
            parameters=[{
                "collection": "users",
                "filter": {"active": True},
                "projection": {"_id": 1, "username": 1, "email": 1},
                "sort": [["_id", -1]],
                "limit": 10,
                "skip": 5,
            }],
        )


@pytest.mark.asyncio
async def test_execute_query_mongodb_playground_mutations(test_session: AsyncSession):
    """Verify insert_many, update_many, and delete_many inference from Playground JSON queries."""
    repo = SqliteSourceRepository(test_session)
    service = QueryService(repo)

    source = Source(
        name="Mongo Playground Source",
        type=SourceType.MONGODB,
        host="localhost",
        port=27017,
        database_name="altr_test_db",
        username="user",
        password="password",
        status=SourceStatus.ACTIVE,
    )
    saved = await repo.create(source)

    with pytest.MonkeyPatch.context() as mp:
        mock_connector = MagicMock(spec=BaseConnector)
        mock_connector.get_capabilities.return_value = SourceCapabilities(custom_query=True)
        mock_connector.execute_query = AsyncMock(return_value=QueryResult(columns=[], rows=[], row_count=0, execution_time_ms=1.0))
        mock_connector.__aenter__ = AsyncMock(return_value=mock_connector)
        mock_connector.__aexit__ = AsyncMock(return_value=None)

        mp.setattr(ConnectorFactory, "get_connector", lambda *args, **kwargs: mock_connector)

        # 1. insert_many
        insert_json = '{"collection": "users", "documents": [{"name": "item1"}]}'
        await service.execute_query(saved.id, insert_json)
        mock_connector.execute_query.assert_awaited_with(
            "mongodb:insert_many",
            parameters=[{"collection": "users", "documents": [{"name": "item1"}]}],
        )

        # 2. update_many
        update_json = '{"collection": "users", "filter": {"name": "item1"}, "update": {"$set": {"name": "item2"}}}'
        await service.execute_query(saved.id, update_json)
        mock_connector.execute_query.assert_awaited_with(
            "mongodb:update_many",
            parameters=[{"collection": "users", "filter": {"name": "item1"}, "update": {"$set": {"name": "item2"}}}],
        )

        # 3. delete_many
        delete_json = '{"operation": "delete_many", "collection": "users", "filter": {"name": "item2"}}'
        await service.execute_query(saved.id, delete_json)
        mock_connector.execute_query.assert_awaited_with(
            "mongodb:delete_many",
            parameters=[{"collection": "users", "filter": {"name": "item2"}}],
        )


@pytest.mark.asyncio
async def test_execute_query_mongodb_invalid_json_and_empty(test_session: AsyncSession):
    """Verify invalid JSON syntax and empty queries are rejected with appropriate error types."""
    repo = SqliteSourceRepository(test_session)
    service = QueryService(repo)

    source = Source(
        name="Mongo Playground Source",
        type=SourceType.MONGODB,
        host="localhost",
        port=27017,
        database_name="altr_test_db",
        username="user",
        password="password",
        status=SourceStatus.ACTIVE,
    )
    saved = await repo.create(source)

    with pytest.MonkeyPatch.context() as mp:
        mock_connector = MagicMock(spec=BaseConnector)
        mock_connector.get_capabilities.return_value = SourceCapabilities(custom_query=True)
        mock_connector.__aenter__ = AsyncMock(return_value=mock_connector)
        mock_connector.__aexit__ = AsyncMock(return_value=None)
        mp.setattr(ConnectorFactory, "get_connector", lambda *args, **kwargs: mock_connector)

        with pytest.raises(QueryExecutionError, match="Invalid MongoDB JSON query"):
            await service.execute_query(saved.id, "{ invalid json: 123", mode="physical")

        with pytest.raises(ReadOnlyQueryRequiredError, match="Query cannot be empty"):
            await service.execute_query(saved.id, "   ")


@pytest.mark.asyncio
async def test_execute_query_mongodb_shell_mode_find(test_session: AsyncSession):
    """Verify that MongoDB Shell find queries execute and produce canonical PhysicalQuery calls."""
    repo = SqliteSourceRepository(test_session)
    service = QueryService(repo)

    source = Source(
        name="Mongo Shell Source",
        type=SourceType.MONGODB,
        host="localhost",
        port=27017,
        database_name="altr_test_db",
        username="user",
        password="password",
        status=SourceStatus.ACTIVE,
    )
    saved = await repo.create(source)

    mock_result = QueryResult(
        columns=["_id", "username"],
        rows=[{"_id": "507f1f77bcf86cd799439011", "username": "alice"}],
        row_count=1,
        execution_time_ms=5.0,
    )

    with pytest.MonkeyPatch.context() as mp:
        mock_connector = MagicMock(spec=BaseConnector)
        mock_connector.get_capabilities.return_value = SourceCapabilities(custom_query=True)
        mock_connector.execute_query = AsyncMock(return_value=mock_result)
        mock_connector.__aenter__ = AsyncMock(return_value=mock_connector)
        mock_connector.__aexit__ = AsyncMock(return_value=None)
        mp.setattr(ConnectorFactory, "get_connector", lambda *args, **kwargs: mock_connector)

        # 1. db.users.find().pretty()
        res1 = await service.execute_query(saved.id, "db.users.find().pretty()")
        assert res1.row_count == 1
        mock_connector.execute_query.assert_awaited_with(
            "mongodb:find",
            parameters=[{"collection": "users", "filter": {}}],
        )

        # 2. db.users.find({ username: "alice" }).sort({ age: -1 }).skip(5).limit(10) with explicit mode='shell'
        shell_query = 'db.users.find({ username: "alice" }).sort({ age: -1 }).skip(5).limit(10)'
        res2 = await service.execute_query(saved.id, shell_query, mode="shell")
        assert res2.row_count == 1
        mock_connector.execute_query.assert_awaited_with(
            "mongodb:find",
            parameters=[{
                "collection": "users",
                "filter": {"username": "alice"},
                "sort": {"age": -1},
                "skip": 5,
                "limit": 10,
            }],
        )


@pytest.mark.asyncio
async def test_execute_query_mongodb_shell_mode_mutations(test_session: AsyncSession):
    """Verify that MongoDB Shell mutation queries (insertMany, updateMany, deleteMany) execute properly."""
    repo = SqliteSourceRepository(test_session)
    service = QueryService(repo)

    source = Source(
        name="Mongo Shell Source",
        type=SourceType.MONGODB,
        host="localhost",
        port=27017,
        database_name="altr_test_db",
        username="user",
        password="password",
        status=SourceStatus.ACTIVE,
    )
    saved = await repo.create(source)

    with pytest.MonkeyPatch.context() as mp:
        mock_connector = MagicMock(spec=BaseConnector)
        mock_connector.get_capabilities.return_value = SourceCapabilities(custom_query=True)
        mock_connector.execute_query = AsyncMock(return_value=QueryResult(columns=[], rows=[], row_count=0, execution_time_ms=1.0))
        mock_connector.__aenter__ = AsyncMock(return_value=mock_connector)
        mock_connector.__aexit__ = AsyncMock(return_value=None)
        mp.setattr(ConnectorFactory, "get_connector", lambda *args, **kwargs: mock_connector)

        # 1. insertMany
        await service.execute_query(saved.id, 'db.users.insertMany([{ name: "alice", age: 25 }])', mode="shell")
        mock_connector.execute_query.assert_awaited_with(
            "mongodb:insert_many",
            parameters=[{"collection": "users", "documents": [{"name": "alice", "age": 25}], "ordered": True}],
        )

        # 2. updateMany
        await service.execute_query(
            saved.id,
            'db.users.updateMany({ status: "pending" }, { $set: { status: "active" } })',
            mode="shell",
        )
        mock_connector.execute_query.assert_awaited_with(
            "mongodb:update_many",
            parameters=[{"collection": "users", "filter": {"status": "pending"}, "update": {"$set": {"status": "active"}}}],
        )

        # 3. deleteMany
        await service.execute_query(saved.id, 'db.users.deleteMany({ status: "archived" })', mode="shell")
        mock_connector.execute_query.assert_awaited_with(
            "mongodb:delete_many",
            parameters=[{"collection": "users", "filter": {"status": "archived"}}],
        )


@pytest.mark.asyncio
async def test_execute_query_mongodb_shell_syntax_error(test_session: AsyncSession):
    """Verify that malformed MongoDB Shell syntax returns a descriptive QueryExecutionError."""
    repo = SqliteSourceRepository(test_session)
    service = QueryService(repo)

    source = Source(
        name="Mongo Shell Source",
        type=SourceType.MONGODB,
        host="localhost",
        port=27017,
        database_name="altr_test_db",
        username="user",
        password="password",
        status=SourceStatus.ACTIVE,
    )
    saved = await repo.create(source)

    with pytest.raises(QueryExecutionError, match="Invalid MongoDB shell syntax"):
        await service.execute_query(saved.id, "db.users.find(")


@pytest.mark.asyncio
async def test_execute_query_mode_rejected_for_non_mongodb(test_session: AsyncSession):
    """Verify that mode parameter is only accepted for MongoDB and rejected for PostgreSQL/MySQL/SQLite."""
    repo = SqliteSourceRepository(test_session)
    service = QueryService(repo)

    pg_source = Source(
        name="Postgres DB",
        type=SourceType.POSTGRESQL,
        host="localhost",
        port=5432,
        database_name="prod",
        username="postgres",
        password="password",
        status=SourceStatus.ACTIVE,
    )
    saved = await repo.create(pg_source)

    with pytest.raises(QueryExecutionError, match="Query mode 'shell' is only supported for MongoDB sources"):
        await service.execute_query(saved.id, "SELECT 1;", mode="shell")

    with pytest.raises(QueryExecutionError, match="Query mode 'physical' is only supported for MongoDB sources"):
        await service.execute_query(saved.id, "SELECT 1;", mode="physical")




