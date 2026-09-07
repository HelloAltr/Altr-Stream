"""PostgreSQL connector implementation using asyncpg."""

import asyncio
from datetime import date, datetime, time
from decimal import Decimal
import re
import time as time_module
from typing import Any
import uuid
import asyncpg

from altr_stream.domain.connector import (
    BaseConnector,
    ConnectionTestResult,
    SourceCapabilities,
)
from altr_stream.domain.errors import (
    ConnectionFailedError,
    QueryExecutionError,
    SchemaDiscoveryError,
)
from altr_stream.domain.query import QueryResult
from altr_stream.domain.schema import SourceSchema
from altr_stream.domain.source import ConnectionConfig, SourceType
from altr_stream.infrastructure.connectors.factory import ConnectorFactory
from altr_stream.infrastructure.connectors.postgres.introspection import (
    COLUMNS_QUERY,
    FOREIGN_KEYS_QUERY,
    PRIMARY_KEYS_QUERY,
    TABLES_QUERY,
)
from altr_stream.infrastructure.connectors.postgres.mapper import build_source_schema_from_pg


def normalize_value(val: Any) -> Any:
    """Recursively normalize database values to JSON-safe Python primitives."""
    if val is None:
        return None
    if isinstance(val, (int, float, bool, str)):
        return val
    if isinstance(val, (datetime, date, time)):
        return val.isoformat()
    if isinstance(val, uuid.UUID):
        return str(val)
    if isinstance(val, Decimal):
        return float(val) if val.as_tuple().exponent != 0 else int(val)
    if isinstance(val, (bytes, bytearray, memoryview)):
        return bytes(val).hex()
    if isinstance(val, dict):
        return {str(k): normalize_value(v) for k, v in val.items()}
    if isinstance(val, (list, tuple, set)):
        return [normalize_value(item) for item in val]
    return str(val)


def _parse_affected_rows(status: str) -> int | None:
    """Extract affected rows count from PostgreSQL command tag."""
    if not status:
        return None
    m = re.match(r"^(?:UPDATE|DELETE|MOVE|FETCH)\s+(\d+)$", status.strip(), re.IGNORECASE)
    if m:
        return int(m.group(1))
    m = re.match(r"^INSERT\s+\d+\s+(\d+)$", status.strip(), re.IGNORECASE)
    if m:
        return int(m.group(1))
    return None


@ConnectorFactory.register(SourceType.POSTGRESQL)
class PostgreSQLConnector(BaseConnector):
    """PostgreSQL database connector implementation."""

    def __init__(self, config: ConnectionConfig, timeout_sec: float = 5.0):
        super().__init__(config, timeout_sec=timeout_sec)

    def _sanitize_error(self, err: Exception) -> str:
        """Sanitize error messages to prevent leaking internal password or raw URIs."""
        err_msg = str(err)
        if self.config.password and self.config.password in err_msg:
            err_msg = err_msg.replace(self.config.password, "••••••••")
        return err_msg

    async def _get_connection(self) -> asyncpg.Connection:
        """Establish a direct asyncpg connection with timeout."""
        return await asyncpg.connect(
            host=self.config.host,
            port=self.config.port,
            database=self.config.database_name,
            user=self.config.username,
            password=self.config.password,
            timeout=self.timeout_sec,
        )

    async def test_connection(self) -> ConnectionTestResult:
        """Test reachability and authentication with the PostgreSQL server."""
        start_time = time_module.perf_counter()
        conn = None
        try:
            conn = await self._get_connection()
            version = await conn.fetchval("SELECT version();")
            latency_ms = round((time_module.perf_counter() - start_time) * 1000, 2)
            return ConnectionTestResult(
                success=True,
                message=f"Connected successfully to PostgreSQL ({latency_ms} ms)",
                latency_ms=latency_ms,
                server_version=str(version),
            )
        except (asyncpg.PostgresError, asyncio.TimeoutError, OSError, ConnectionRefusedError) as e:
            latency_ms = round((time_module.perf_counter() - start_time) * 1000, 2)
            sanitized = self._sanitize_error(e)
            return ConnectionTestResult(
                success=False,
                message=f"Connection failed: {sanitized}",
                latency_ms=latency_ms,
                error_details=sanitized,
            )
        except Exception as e:
            latency_ms = round((time_module.perf_counter() - start_time) * 1000, 2)
            sanitized = self._sanitize_error(e)
            return ConnectionTestResult(
                success=False,
                message=f"Unexpected error testing connection: {sanitized}",
                latency_ms=latency_ms,
                error_details=sanitized,
            )
        finally:
            if conn:
                try:
                    await conn.close()
                except Exception:
                    pass

    async def discover_schema(self, source_id: str, source_name: str) -> SourceSchema:
        """Introspect tables, columns, primary keys, and foreign keys from PostgreSQL."""
        conn = None
        try:
            conn = await self._get_connection()

            # Execute catalog queries
            tables_records = await conn.fetch(TABLES_QUERY)
            columns_records = await conn.fetch(COLUMNS_QUERY)
            pks_records = await conn.fetch(PRIMARY_KEYS_QUERY)
            fks_records = await conn.fetch(FOREIGN_KEYS_QUERY)

            tables_data = [dict(r) for r in tables_records]
            columns_data = [dict(r) for r in columns_records]
            pks_data = [dict(r) for r in pks_records]
            fks_data = [dict(r) for r in fks_records]

            return build_source_schema_from_pg(
                source_id=source_id,
                source_name=source_name,
                tables_data=tables_data,
                columns_data=columns_data,
                pks_data=pks_data,
                fks_data=fks_data,
            )
        except (asyncpg.PostgresError, asyncio.TimeoutError, OSError) as e:
            sanitized = self._sanitize_error(e)
            raise SchemaDiscoveryError(
                f"Failed to discover schema from PostgreSQL '{source_name}': {sanitized}",
                details=sanitized,
            ) from e
        except Exception as e:
            sanitized = self._sanitize_error(e)
            raise SchemaDiscoveryError(
                f"Unexpected error during schema discovery for '{source_name}': {sanitized}",
                details=sanitized,
            ) from e
        finally:
            if conn:
                try:
                    await conn.close()
                except Exception:
                    pass

    async def execute_query(self, query: str, parameters: list[Any] | None = None) -> QueryResult:
        """Execute a native query (result-returning or command) against PostgreSQL and return normalized QueryResult."""
        start_time = time_module.perf_counter()
        conn = None
        params = parameters or []
        try:
            conn = await self._get_connection()
            stmt = await conn.prepare(query)
            attributes = stmt.get_attributes()

            if attributes:
                records = await stmt.fetch(*params)
                status_msg = stmt.get_statusmsg()
                execution_time_ms = round((time_module.perf_counter() - start_time) * 1000, 2)
                columns = [attr.name for attr in attributes]
                rows = [
                    {col: normalize_value(record[col]) for col in columns}
                    for record in records
                ]
                return QueryResult(
                    columns=columns,
                    rows=rows,
                    row_count=len(rows),
                    affected_rows=None,
                    message=status_msg,
                    execution_time_ms=execution_time_ms,
                )
            else:
                records = await stmt.fetch(*params)
                status_str = stmt.get_statusmsg() or ""
                execution_time_ms = round((time_module.perf_counter() - start_time) * 1000, 2)
                affected_rows = _parse_affected_rows(status_str)
                return QueryResult(
                    columns=[],
                    rows=[],
                    row_count=0,
                    affected_rows=affected_rows,
                    message=status_str,
                    execution_time_ms=execution_time_ms,
                )
        except (asyncpg.PostgresError, asyncio.TimeoutError, OSError) as e:
            sanitized = self._sanitize_error(e)
            raise QueryExecutionError(
                f"PostgreSQL query execution failed: {sanitized}",
                details=sanitized,
            ) from e
        except Exception as e:
            sanitized = self._sanitize_error(e)
            raise QueryExecutionError(
                f"Unexpected error executing query: {sanitized}",
                details=sanitized,
            ) from e
        finally:
            if conn:
                try:
                    await conn.close()
                except Exception:
                    pass

    def get_capabilities(self) -> SourceCapabilities:
        """Report capabilities for the PostgreSQL connector."""
        return SourceCapabilities(
            schema_discovery=True,
            read=True,
            write=True,
            cdc=False,  # CDC is future scope
            batch_execution=True,
            streaming=False,
            custom_query=True,
            entity_types=["TABLE", "VIEW"],
            supported_operations=["SELECT", "INSERT", "UPDATE", "DELETE", "SCHEMA_DISCOVERY"],
        )
