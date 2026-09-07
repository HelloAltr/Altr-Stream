"""Dialect Lowerer Registry for AltrQL.

Provides dynamic resolution of physical QueryLowerer implementations based on
the data source's SourceType or dialect name.
"""

from __future__ import annotations

from typing import Dict, Type, Union

from altr_stream.domain.source import SourceType
from altr_stream.query_engine.domain.errors import UnsupportedDialectError
from altr_stream.query_engine.lowering.base import QueryLowerer
from altr_stream.query_engine.lowering.postgres import PostgreSQLLowerer


class LowererRegistry:
    """Registry managing dialect-specific physical query lowerers."""

    def __init__(self) -> None:
        self._registry: Dict[str, Type[QueryLowerer]] = {}
        # Pre-register built-in dialects
        self.register(SourceType.POSTGRESQL, PostgreSQLLowerer)

    def register(
        self,
        dialect_or_source_type: Union[SourceType, str],
        lowerer_cls: Type[QueryLowerer],
    ) -> None:
        """Register a QueryLowerer implementation for a source type or dialect string."""
        key = self._normalize_key(dialect_or_source_type)
        self._registry[key] = lowerer_cls

    def get(self, dialect_or_source_type: Union[SourceType, str]) -> QueryLowerer:
        """Resolve and instantiate a QueryLowerer for the given source type or dialect."""
        key = self._normalize_key(dialect_or_source_type)
        lowerer_cls = self._registry.get(key)
        if lowerer_cls is None:
            raw_name = dialect_or_source_type.value if isinstance(dialect_or_source_type, SourceType) else str(dialect_or_source_type)
            raise UnsupportedDialectError(
                f"No AltrQL lowerer is registered for source dialect '{raw_name}'."
            )
        return lowerer_cls()

    def _normalize_key(self, key: Union[SourceType, str]) -> str:
        if isinstance(key, SourceType):
            return key.value.lower()
        return str(key).lower().strip()


# Global registry singleton
_GLOBAL_REGISTRY = LowererRegistry()


def get_lowerer(dialect_or_source_type: Union[SourceType, str]) -> QueryLowerer:
    """Resolve and return a QueryLowerer instance for the specified source type or dialect."""
    return _GLOBAL_REGISTRY.get(dialect_or_source_type)
