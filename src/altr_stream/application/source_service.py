"""Source management application service."""

from altr_stream.domain.connector import ConnectionTestResult, SourceCapabilities
from altr_stream.domain.errors import SourceAlreadyExistsError, SourceNotFoundError
from altr_stream.domain.source import ConnectionConfig, Source, SourceStatus, SourceType
from altr_stream.infrastructure.connectors.factory import ConnectorFactory
from altr_stream.infrastructure.database.repository import SqliteSourceRepository


class SourceService:
    """Application use cases for source management."""

    def __init__(self, repository: SqliteSourceRepository):
        self.repository = repository

    async def create_source(
        self,
        name: str,
        source_type: SourceType,
        host: str,
        port: int,
        database_name: str,
        username: str,
        password: str,
        test_first: bool = False,
    ) -> tuple[Source, ConnectionTestResult | None]:
        """Register a new data source."""
        existing = await self.repository.get_by_name(name)
        if existing:
            raise SourceAlreadyExistsError(name)

        config = ConnectionConfig(
            host=host,
            port=port,
            database_name=database_name,
            username=username,
            password=password,
        )

        test_result: ConnectionTestResult | None = None
        status = SourceStatus.UNKNOWN

        if test_first:
            connector = ConnectorFactory.get_connector(source_type, config)
            async with connector:
                test_result = await connector.test_connection()
            status = SourceStatus.ACTIVE if test_result.success else SourceStatus.UNREACHABLE

        source = Source(
            name=name,
            type=source_type,
            host=host,
            port=port,
            database_name=database_name,
            username=username,
            password=password,
            status=status,
        )

        created = await self.repository.create(source)
        return created, test_result

    async def get_source(self, source_id: str) -> Source:
        """Get source by ID or raise SourceNotFoundError."""
        source = await self.repository.get_by_id(source_id)
        if not source:
            raise SourceNotFoundError(source_id)
        return source

    async def list_sources(self) -> list[Source]:
        """List all registered data sources."""
        return await self.repository.list_all()

    async def update_source(
        self,
        source_id: str,
        name: str | None = None,
        host: str | None = None,
        port: int | None = None,
        database_name: str | None = None,
        username: str | None = None,
        password: str | None = None,
    ) -> Source:
        """Update source properties."""
        source = await self.get_source(source_id)

        if name and name != source.name:
            existing = await self.repository.get_by_name(name)
            if existing and existing.id != source.id:
                raise SourceAlreadyExistsError(name)
            source.name = name

        if host is not None:
            source.host = host
        if port is not None:
            source.port = port
        if database_name is not None:
            source.database_name = database_name
        if username is not None:
            source.username = username
        if password is not None and password.strip():
            source.password = password

        return await self.repository.update(source)

    async def delete_source(self, source_id: str) -> bool:
        """Delete source by ID."""
        return await self.repository.delete(source_id)

    async def test_source_connection(self, source_id: str) -> ConnectionTestResult:
        """Test physical connection for a registered source and update its status."""
        source = await self.get_source(source_id)
        connector = ConnectorFactory.get_connector(source.type, source.connection_config)
        async with connector:
            result = await connector.test_connection()

        new_status = SourceStatus.ACTIVE if result.success else SourceStatus.UNREACHABLE
        await self.repository.update_status(source_id, new_status)
        return result

    async def test_adhoc_connection(
        self,
        source_type: SourceType,
        config: ConnectionConfig,
    ) -> ConnectionTestResult:
        """Test connection parameters without saving."""
        connector = ConnectorFactory.get_connector(source_type, config)
        async with connector:
            return await connector.test_connection()

    def get_source_capabilities(self, source: Source) -> SourceCapabilities:
        """Get capabilities for the source's connector."""
        connector = ConnectorFactory.get_connector(source.type, source.connection_config)
        return connector.get_capabilities()
