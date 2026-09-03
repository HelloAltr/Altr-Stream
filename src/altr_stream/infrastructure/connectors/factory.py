"""Connector factory for resolving connector implementations by SourceType."""

from altr_stream.config import settings
from altr_stream.domain.connector import BaseConnector
from altr_stream.domain.errors import ConnectorNotFoundError
from altr_stream.domain.source import ConnectionConfig, SourceType
from altr_stream.infrastructure.connectors.postgres.connector import PostgreSQLConnector


class ConnectorFactory:
    """Factory to instantiate connectors based on SourceType."""

    _connectors: dict[SourceType, type[BaseConnector]] = {
        SourceType.POSTGRESQL: PostgreSQLConnector,
    }

    @classmethod
    def get_connector(
        cls,
        source_type: SourceType,
        config: ConnectionConfig,
        timeout_sec: float | None = None,
    ) -> BaseConnector:
        """Instantiate and return the appropriate connector for a given source type."""
        connector_cls = cls._connectors.get(source_type)
        if not connector_cls:
            raise ConnectorNotFoundError(source_type.value)

        timeout = timeout_sec or settings.default_connection_timeout_sec
        return connector_cls(config, timeout_sec=timeout)  # type: ignore[call-arg]
