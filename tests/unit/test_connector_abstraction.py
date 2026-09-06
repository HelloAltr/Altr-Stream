"""Unit tests for the Connector Architecture Foundation abstraction and factory."""

import pytest
from altr_stream.domain.connector import (
    BaseConnector,
    ConnectionTestResult,
    SourceCapabilities,
)
from altr_stream.domain.errors import ConnectorNotFoundError
from altr_stream.domain.query import QueryResult
from altr_stream.domain.schema import SourceSchema
from altr_stream.domain.source import ConnectionConfig, SourceType
from altr_stream.infrastructure.connectors.factory import ConnectorFactory
from altr_stream.infrastructure.connectors.postgres.connector import PostgreSQLConnector


class DummyRelationalConnector(BaseConnector):
    """Mock relational connector for testing registration and lifecycle."""

    def __init__(self, config: ConnectionConfig, timeout_sec: float = 5.0):
        super().__init__(config, timeout_sec=timeout_sec)
        self.closed = False

    async def test_connection(self) -> ConnectionTestResult:
        return ConnectionTestResult(success=True, message="Dummy OK", latency_ms=1.0)

    async def discover_schema(self, source_id: str, source_name: str) -> SourceSchema:
        return SourceSchema(source_id=source_id, source_name=source_name, entities=[])

    def get_capabilities(self) -> SourceCapabilities:
        return SourceCapabilities(
            schema_discovery=True,
            entity_types=["TABLE", "VIEW"],
            supported_operations=["SELECT", "INSERT"],
        )

    async def execute_query(self, query: str) -> QueryResult:
        return QueryResult(columns=["col1"], rows=[{"col1": "val1"}], row_count=1, execution_time_ms=1.0)

    async def close(self) -> None:
        self.closed = True


class DummyDocumentConnector(BaseConnector):
    """Mock document connector for testing registration."""

    async def test_connection(self) -> ConnectionTestResult:
        return ConnectionTestResult(success=True, message="Doc OK", latency_ms=2.0)

    async def discover_schema(self, source_id: str, source_name: str) -> SourceSchema:
        return SourceSchema(source_id=source_id, source_name=source_name, entities=[])

    def get_capabilities(self) -> SourceCapabilities:
        return SourceCapabilities(
            schema_discovery=True,
            entity_types=["COLLECTION"],
            supported_operations=["FIND", "INSERT"],
        )

    async def execute_query(self, query: str) -> QueryResult:
        return QueryResult(columns=["_id"], rows=[{"_id": "doc1"}], row_count=1, execution_time_ms=2.0)


def test_postgres_connector_registered_by_default():
    """Verify PostgreSQL connector is automatically registered."""
    assert SourceType.POSTGRESQL in ConnectorFactory.supported_types()

    config = ConnectionConfig(
        host="localhost",
        port=5432,
        database_name="testdb",
        username="postgres",
        password="secretpassword",
    )
    connector = ConnectorFactory.get_connector(SourceType.POSTGRESQL, config)
    assert isinstance(connector, PostgreSQLConnector)
    assert connector.config.host == "localhost"
    assert connector.timeout_sec == 5.0

    caps = connector.get_capabilities()
    assert caps.schema_discovery is True
    assert caps.custom_query is True
    assert caps.entity_types == ["TABLE", "VIEW"]
    assert "SELECT" in caps.supported_operations

    # Verify default SourceCapabilities has custom_query=False
    default_caps = SourceCapabilities()
    assert default_caps.custom_query is False


def test_connector_factory_decorator_registration():
    """Verify decorator-based connector registration, resolution, and unregistration."""
    # Register DummyRelationalConnector under MYSQL
    ConnectorFactory.register(SourceType.MYSQL)(DummyRelationalConnector)
    assert SourceType.MYSQL in ConnectorFactory.supported_types()

    config = ConnectionConfig(
        host="127.0.0.1",
        port=3306,
        database_name="mydb",
        username="root",
        password="password",
    )
    connector = ConnectorFactory.get_connector(SourceType.MYSQL, config, timeout_sec=10.0)
    assert isinstance(connector, DummyRelationalConnector)
    assert connector.timeout_sec == 10.0

    # Unregister and verify cleanup
    ConnectorFactory.unregister(SourceType.MYSQL)
    assert SourceType.MYSQL not in ConnectorFactory.supported_types()
    with pytest.raises(ConnectorNotFoundError):
        ConnectorFactory.get_connector(SourceType.MYSQL, config)


def test_unregistered_connector_raises_error():
    """Verify attempting to get an unregistered connector raises ConnectorNotFoundError."""
    # Ensure MONGODB is not registered
    ConnectorFactory.unregister(SourceType.MONGODB)
    config = ConnectionConfig(
        host="localhost",
        port=27017,
        database_name="test",
        username="user",
        password="password",
    )
    with pytest.raises(ConnectorNotFoundError) as exc_info:
        ConnectorFactory.get_connector(SourceType.MONGODB, config)
    assert "MONGODB" in str(exc_info.value)


@pytest.mark.asyncio
async def test_base_connector_context_manager_lifecycle():
    """Verify BaseConnector async context manager triggers close() cleanly."""
    config = ConnectionConfig(
        host="localhost",
        port=5432,
        database_name="test",
        username="user",
        password="password",
    )
    connector = DummyRelationalConnector(config)
    assert connector.closed is False

    async with connector as conn:
        assert conn is connector
        result = await conn.test_connection()
        assert result.success is True

    assert connector.closed is True


def test_vendor_neutral_capabilities_differentiation():
    """Verify capabilities model distinguishes between relational and document models cleanly."""
    relational_caps = DummyRelationalConnector(
        ConnectionConfig(
            host="localhost",
            port=5432,
            database_name="db",
            username="user",
            password="pwd",
        )
    ).get_capabilities()
    assert relational_caps.entity_types == ["TABLE", "VIEW"]

    doc_caps = DummyDocumentConnector(
        ConnectionConfig(
            host="localhost",
            port=27017,
            database_name="db",
            username="user",
            password="pwd",
        )
    ).get_capabilities()
    assert doc_caps.entity_types == ["COLLECTION"]
