"""SQLite connector implementation using aiosqlite."""

import asyncio
from datetime import date, datetime, time
from decimal import Decimal
import time as time_module
from typing import Any
import uuid
import aiosqlite

from altr_stream.domain.connector import (
    BaseConnector,
    ConnectionTestResult,
    ParameterStyle,
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
from altr_stream.infrastructure.connectors.sqlite.introspection import (
    TABLES_QUERY,
    foreign_key_list_query,
    table_info_query,
)
from altr_stream.infrastructure.connectors.sqlite.mapper import build_source_schema_from_sqlite


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


@ConnectorFactory.register(SourceType.SQLITE)
class SQLiteConnector(BaseConnector):
    """SQLite database connector implementation."""

    def __init__(self, config: ConnectionConfig, timeout_sec: float = 5.0):
        super().__init__(config, timeout_sec=timeout_sec)

    def _get_db_path(self) -> str:
        """Resolve the file or memory path for SQLite database."""
        if self.config.file_path:
            return self.config.file_path
        if self.config.database_name:
            return self.config.database_name
        return ":memory:"

    async def _get_connection(self) -> aiosqlite.Connection:
        """Establish an asynchronous connection to SQLite."""
        db_path = self._get_db_path()
        conn = await aiosqlite.connect(db_path, timeout=self.timeout_sec)
        conn.row_factory = aiosqlite.Row
        return conn

    async def test_connection(self) -> ConnectionTestResult:
        """Test accessibility and query execution on the SQLite database."""
        start_time = time_module.perf_counter()
        conn = None
        try:
            conn = await self._get_connection()
            async with conn.execute("SELECT sqlite_version();") as cursor:
                row = await cursor.fetchone()
                version = row[0] if row else "unknown"

            latency_ms = round((time_module.perf_counter() - start_time) * 1000, 2)
            return ConnectionTestResult(
                success=True,
                message=f"Connected successfully to SQLite ({latency_ms} ms)",
                latency_ms=latency_ms,
                server_version=str(version),
            )
        except Exception as e:
            latency_ms = round((time_module.perf_counter() - start_time) * 1000, 2)
            err_msg = str(e)
            return ConnectionTestResult(
                success=False,
                message=f"Connection failed: {err_msg}",
                latency_ms=latency_ms,
                error_details=err_msg,
            )
        finally:
            if conn:
                try:
                    await conn.close()
                except Exception:
                    pass

    async def discover_schema(self, source_id: str, source_name: str) -> SourceSchema:
        """Introspect tables, columns, primary keys, and foreign keys from SQLite."""
        conn = None
        try:
            conn = await self._get_connection()

            # 1. Fetch tables and views
            tables_data: list[dict[str, Any]] = []
            async with conn.execute(TABLES_QUERY) as cursor:
                rows = await cursor.fetchall()
                tables_data = [{"table_name": r["table_name"], "table_type": r["table_type"]} for r in rows]

            # 2. For each table, fetch columns and FKs
            table_columns: dict[str, list[dict[str, Any]]] = {}
            table_fks: dict[str, list[dict[str, Any]]] = {}

            for tbl in tables_data:
                t_name = tbl["table_name"]

                # Columns via PRAGMA table_info
                async with conn.execute(table_info_query(t_name)) as cursor:
                    c_rows = await cursor.fetchall()
                    table_columns[t_name] = [dict(r) for r in c_rows]

                # Foreign keys via PRAGMA foreign_key_list
                async with conn.execute(foreign_key_list_query(t_name)) as cursor:
                    fk_rows = await cursor.fetchall()
                    table_fks[t_name] = [dict(r) for r in fk_rows]

            return build_source_schema_from_sqlite(
                source_id=source_id,
                source_name=source_name,
                tables_data=tables_data,
                table_columns=table_columns,
                table_fks=table_fks,
            )
        except Exception as e:
            raise SchemaDiscoveryError(
                f"Failed to discover schema from SQLite '{source_name}': {e}",
                details=str(e),
            ) from e
        finally:
            if conn:
                try:
                    await conn.close()
                except Exception:
                    pass

    async def execute_query(self, query: str, parameters: list[Any] | None = None) -> QueryResult:
        """Execute a native query against SQLite and return normalized QueryResult."""
        start_time = time_module.perf_counter()
        conn = None
        params = parameters or []
        try:
            conn = await self._get_connection()
            async with conn.execute(query, params) as cursor:
                if cursor.description is not None:
                    # Result-returning query (SELECT / RETURNING)
                    columns = [d[0] for d in cursor.description]
                    records = await cursor.fetchall()
                    rows = [
                        {col: normalize_value(record[col]) for col in columns}
                        for record in records
                    ]
                    await conn.commit()
                    execution_time_ms = round((time_module.perf_counter() - start_time) * 1000, 2)
                    return QueryResult(
                        columns=columns,
                        rows=rows,
                        row_count=len(rows),
                        affected_rows=None,
                        message="Query executed successfully",
                        execution_time_ms=execution_time_ms,
                    )
                else:
                    # Mutation query without result set
                    await conn.commit()
                    affected_rows = cursor.rowcount if cursor.rowcount != -1 else None
                    execution_time_ms = round((time_module.perf_counter() - start_time) * 1000, 2)
                    return QueryResult(
                        columns=[],
                        rows=[],
                        row_count=0,
                        affected_rows=affected_rows,
                        message="Command executed successfully",
                        execution_time_ms=execution_time_ms,
                    )
        except Exception as e:
            raise QueryExecutionError(
                f"SQLite query execution failed: {e}",
                details=str(e),
            ) from e
        finally:
            if conn:
                try:
                    await conn.close()
                except Exception:
                    pass

    async def execute_batch(self, queries: list[tuple[str, list[Any] | None]]) -> QueryResult:
        """Execute multiple queries sequentially within a transaction in SQLite."""
        start_time = time_module.perf_counter()
        conn = None
        all_rows: list[dict[str, Any]] = []
        all_columns: list[str] = []
        total_affected: int | None = None

        try:
            conn = await self._get_connection()
            for query_str, params in queries:
                q_params = params or []
                async with conn.execute(query_str, q_params) as cursor:
                    if cursor.description is not None:
                        cols = [d[0] for d in cursor.description]
                        if not all_columns:
                            all_columns = cols
                        records = await cursor.fetchall()
                        for record in records:
                            all_rows.append({col: normalize_value(record[col]) for col in cols})
                    else:
                        if cursor.rowcount != -1:
                            total_affected = (total_affected or 0) + cursor.rowcount

            await conn.commit()
            execution_time_ms = round((time_module.perf_counter() - start_time) * 1000, 2)
            return QueryResult(
                columns=all_columns,
                rows=all_rows,
                row_count=len(all_rows),
                affected_rows=total_affected,
                message="Batch executed successfully",
                execution_time_ms=execution_time_ms,
            )
        except Exception as e:
            if conn:
                try:
                    await conn.rollback()
                except Exception:
                    pass
            raise QueryExecutionError(
                f"SQLite batch execution failed: {e}",
                details=str(e),
            ) from e
        finally:
            if conn:
                try:
                    await conn.close()
                except Exception:
                    pass

    def get_capabilities(self) -> SourceCapabilities:
        """Report capabilities for the SQLite connector."""
        return SourceCapabilities(
            schema_discovery=True,
            read=True,
            write=True,
            cdc=False,
            batch_execution=True,
            streaming=False,
            custom_query=True,
            supports_transactions=True,
            supports_returning=True,
            supports_date_only_equality=True,
            parameter_style=ParameterStyle.POSITIONAL_QMARK,
            max_batch_size=1000,
            entity_types=["TABLE", "VIEW"],
            supported_operations=["SELECT", "INSERT", "UPDATE", "DELETE", "SCHEMA_DISCOVERY"],
        )
