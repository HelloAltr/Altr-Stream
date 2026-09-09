"""Connector factory and registry for resolving connector implementations by SourceType."""

from typing import Callable, TypeVar

from altr_stream.config import settings
from altr_stream.domain.connector import BaseConnector
from altr_stream.domain.errors import ConnectorNotFoundError
from altr_stream.domain.source import ConnectionConfig, SourceType

C = TypeVar("C", bound=type[BaseConnector])


class ConnectorFactory:
    """Registry and factory to instantiate connectors based on SourceType."""

    _registry: dict[SourceType, type[BaseConnector]] = {}

    @classmethod
    def register(cls, source_type: SourceType) -> Callable[[C], C]:
        """Decorator or direct method to register a connector class for a given SourceType."""

        def decorator(connector_cls: C) -> C:
            cls._registry[source_type] = connector_cls
            return connector_cls

        return decorator

    @classmethod
    def unregister(cls, source_type: SourceType) -> None:
        """Unregister a connector class for a given SourceType (useful for test isolation)."""
        cls._registry.pop(source_type, None)

    @classmethod
    def get_connector(
        cls,
        source_type: SourceType,
        config: ConnectionConfig,
        timeout_sec: float | None = None,
    ) -> BaseConnector:
        """Instantiate and return the appropriate connector for a given source type."""
        connector_cls = cls._registry.get(source_type)
        if not connector_cls:
            raise ConnectorNotFoundError(source_type.value)

        timeout = timeout_sec or settings.default_connection_timeout_sec
        return connector_cls(config, timeout_sec=timeout)

    @classmethod
    def supported_types(cls) -> list[SourceType]:
        """Return list of currently registered and supported source types."""
        return list(cls._registry.keys())


# Ensure built-in connectors are registered upon module loading
from altr_stream.infrastructure.connectors.postgres import connector as _pg_connector  # noqa: E402, F401
from altr_stream.infrastructure.connectors.sqlite import connector as _sqlite_connector  # noqa: E402, F401
