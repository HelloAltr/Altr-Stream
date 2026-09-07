"""Unit tests for AltrQL LowererRegistry."""

import pytest

from altr_stream.domain.source import SourceType
from altr_stream.query_engine.domain.errors import UnsupportedDialectError
from altr_stream.query_engine.lowering.base import QueryLowerer
from altr_stream.query_engine.lowering.postgres import PostgreSQLLowerer
from altr_stream.query_engine.lowering.registry import LowererRegistry, get_lowerer


def test_registry_resolves_postgresql_by_enum():
    lowerer = get_lowerer(SourceType.POSTGRESQL)
    assert isinstance(lowerer, PostgreSQLLowerer)


def test_registry_resolves_postgresql_by_string():
    lowerer1 = get_lowerer("postgresql")
    lowerer2 = get_lowerer("POSTGRESQL")
    assert isinstance(lowerer1, PostgreSQLLowerer)
    assert isinstance(lowerer2, PostgreSQLLowerer)


def test_registry_unsupported_dialect_raises_error():
    with pytest.raises(UnsupportedDialectError) as exc_info:
        get_lowerer("mongodb")
    assert "No AltrQL lowerer is registered for source dialect 'mongodb'." in str(exc_info.value)


def test_registry_custom_registration():
    class DummyMySQLQueryLowerer(QueryLowerer):
        def lower(self, query):
            raise NotImplementedError()

    registry = LowererRegistry()
    registry.register("mysql", DummyMySQLQueryLowerer)
    lowerer = registry.get("mysql")
    assert isinstance(lowerer, DummyMySQLQueryLowerer)
