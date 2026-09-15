"""MySQL connector implementation using aiomysql."""

import asyncio
from datetime import date, datetime, time
from decimal import Decimal
import time as time_module
from typing import Any
import uuid
import aiomysql
import pymysql

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
from altr_stream.infrastructure.connectors.mysql.introspection import (
    COLUMNS_QUERY,
    CONSTRAINTS_QUERY,
    TABLES_QUERY,
)
from altr_stream.infrastructure.connectors.mysql.mapper import build_source_schema_from_mysql


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


@ConnectorFactory.register(SourceType.MYSQL)
class MySQLConnector(BaseConnector):
    """MySQL database connector implementation with connection pooling."""

    def __init__(self, config: ConnectionConfig, timeout_sec: float = 5.0):
        super().__init__(config, timeout_sec=timeout_sec)
        self._pool: aiomysql.Pool | None = None

    async def initialize(self) -> None:
        """Initialize aiomysql connection pool."""
        if self._pool is None:
            try:
                self._pool = await aiomysql.create_pool(
                    host=self.config.host or "localhost",
                    port=int(self.config.port or 3306),
                    user=self.config.username or "root",
                    password=self.config.password or "",
                    db=self.config.database_name,
                    minsize=1,
                    maxsize=10,
                    connect_timeout=self.timeout_sec,
                    autocommit=True,
                    cursorclass=aiomysql.DictCursor,
                )
            except Exception:
                # If pool creation fails during initial probe, fallback to direct per-call connections
                pass
        self._is_initialized = True

    async def close(self) -> None:
        """Clean up connection pools and resources."""
        if self._pool is not None:
            try:
                self._pool.close()
                await self._pool.wait_closed()
            except Exception:
                pass
            self._pool = None
        self._is_initialized = False

    def _sanitize_error(self, err: Exception) -> str:
        """Sanitize error messages to prevent leaking internal password."""
        err_msg = str(err)
        if self.config.password and self.config.password in err_msg:
            err_msg = err_msg.replace(self.config.password, "••••••••")
        return err_msg

    async def _get_connection(self) -> aiomysql.Connection:
        """Establish a direct aiomysql connection with timeout."""
        return await aiomysql.connect(
            host=self.config.host or "localhost",
            port=int(self.config.port or 3306),
            user=self.config.username or "root",
            password=self.config.password or "",
            db=self.config.database_name,
            connect_timeout=self.timeout_sec,
            autocommit=True,
            cursorclass=aiomysql.DictCursor,
        )

    async def _acquire_connection(self) -> tuple[aiomysql.Connection, bool]:
        """Acquire a connection from pool if available, otherwise direct connection.
        Returns (connection, is_from_pool).
        """
        if self._pool is not None and not self._pool._closed:
            conn = await self._pool.acquire()
            return conn, True
        conn = await self._get_connection()
        return conn, False

    async def _release_connection(self, conn: aiomysql.Connection | None, is_from_pool: bool) -> None:
        """Release a connection back to the pool or close it."""
        if not conn:
            return
        try:
            if is_from_pool and self._pool is not None and not self._pool._closed:
                self._pool.release(conn)
            else:
                conn.close()
        except Exception:
            pass

    async def test_connection(self) -> ConnectionTestResult:
        """Test reachability and authentication with the MySQL server."""
        start_time = time_module.perf_counter()
        conn = None
        is_from_pool = False
        try:
            conn, is_from_pool = await self._acquire_connection()
            async with conn.cursor() as cursor:
                await cursor.execute("SELECT VERSION();")
                row = await cursor.fetchone()
                version = "unknown"
                if row:
                    if isinstance(row, dict):
                        version = list(row.values())[0]
                    elif isinstance(row, (list, tuple)):
                        version = row[0]

            latency_ms = round((time_module.perf_counter() - start_time) * 1000, 2)
            return ConnectionTestResult(
                success=True,
                message=f"Connected successfully to MySQL ({latency_ms} ms)",
                latency_ms=latency_ms,
                server_version=str(version),
            )
        except (aiomysql.Error, pymysql.Error, asyncio.TimeoutError, OSError, ConnectionRefusedError) as e:
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
            await self._release_connection(conn, is_from_pool)

    async def discover_schema(self, source_id: str, source_name: str) -> SourceSchema:
        """Introspect tables, columns, primary keys, and foreign keys from MySQL."""
        conn = None
        is_from_pool = False
        db_name = self.config.database_name or ""
        try:
            conn, is_from_pool = await self._acquire_connection()
            async with conn.cursor() as cursor:
                # 1. Fetch tables and views
                await cursor.execute(TABLES_QUERY, (db_name,))
                tables_records = await cursor.fetchall()
                tables_data = [dict(r) for r in tables_records]

                # 2. Fetch columns
                await cursor.execute(COLUMNS_QUERY, (db_name,))
                columns_records = await cursor.fetchall()
                columns_data = [dict(r) for r in columns_records]

                # 3. Fetch constraints
                await cursor.execute(CONSTRAINTS_QUERY, (db_name,))
                constraints_records = await cursor.fetchall()
                constraints_data = [dict(r) for r in constraints_records]

            return build_source_schema_from_mysql(
                source_id=source_id,
                source_name=source_name,
                tables_data=tables_data,
                columns_data=columns_data,
                constraints_data=constraints_data,
            )
        except (aiomysql.Error, pymysql.Error, asyncio.TimeoutError, OSError) as e:
            sanitized = self._sanitize_error(e)
            raise SchemaDiscoveryError(
                f"Failed to discover schema from MySQL '{source_name}': {sanitized}",
                details=sanitized,
            ) from e
        except Exception as e:
            sanitized = self._sanitize_error(e)
            raise SchemaDiscoveryError(
                f"Unexpected error during schema discovery for '{source_name}': {sanitized}",
                details=sanitized,
            ) from e
        finally:
            await self._release_connection(conn, is_from_pool)

    async def execute_query(self, query: str, parameters: list[Any] | None = None) -> QueryResult:
        """Execute a native SQL query against MySQL and return normalized QueryResult."""
        start_time = time_module.perf_counter()
        conn = None
        is_from_pool = False
        params = tuple(parameters) if parameters else ()
        try:
            conn, is_from_pool = await self._acquire_connection()
            async with conn.cursor() as cursor:
                await cursor.execute(query, params)
                execution_time_ms = round((time_module.perf_counter() - start_time) * 1000, 2)

                if cursor.description is not None:
                    # Result-returning query (SELECT)
                    columns = [d[0] for d in cursor.description]
                    records = await cursor.fetchall()
                    rows = [
                        {col: normalize_value(record[col]) for col in columns}
                        for record in records
                    ]
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
                    affected_rows = cursor.rowcount if cursor.rowcount != -1 else None
                    return QueryResult(
                        columns=[],
                        rows=[],
                        row_count=0,
                        affected_rows=affected_rows,
                        message="Command executed successfully",
                        execution_time_ms=execution_time_ms,
                    )
        except (aiomysql.Error, pymysql.Error, asyncio.TimeoutError, OSError) as e:
            sanitized = self._sanitize_error(e)
            raise QueryExecutionError(
                f"MySQL query execution failed: {sanitized}",
                details=sanitized,
            ) from e
        except Exception as e:
            sanitized = self._sanitize_error(e)
            raise QueryExecutionError(
                f"Unexpected error executing query: {sanitized}",
                details=sanitized,
            ) from e
        finally:
            await self._release_connection(conn, is_from_pool)

    async def execute_batch(self, queries: list[tuple[str, list[Any] | None]]) -> QueryResult:
        """Execute multiple SQL queries sequentially within a transaction in MySQL."""
        start_time = time_module.perf_counter()
        conn = None
        is_from_pool = False
        all_rows: list[dict[str, Any]] = []
        all_columns: list[str] = []
        total_affected: int | None = None

        try:
            conn, is_from_pool = await self._acquire_connection()
            await conn.begin()
            async with conn.cursor() as cursor:
                for query_str, params in queries:
                    q_params = tuple(params) if params else ()
                    await cursor.execute(query_str, q_params)
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
        except (aiomysql.Error, pymysql.Error, asyncio.TimeoutError, OSError) as e:
            if conn:
                try:
                    await conn.rollback()
                except Exception:
                    pass
            sanitized = self._sanitize_error(e)
            raise QueryExecutionError(
                f"MySQL batch execution failed: {sanitized}",
                details=sanitized,
            ) from e
        except Exception as e:
            if conn:
                try:
                    await conn.rollback()
                except Exception:
                    pass
            sanitized = self._sanitize_error(e)
            raise QueryExecutionError(
                f"Unexpected error executing query batch: {sanitized}",
                details=sanitized,
            ) from e
        finally:
            await self._release_connection(conn, is_from_pool)

    def get_capabilities(self) -> SourceCapabilities:
        """Report capabilities for the MySQL connector."""
        return SourceCapabilities(
            schema_discovery=True,
            read=True,
            write=True,
            cdc=False,
            batch_execution=True,
            streaming=False,
            custom_query=True,
            supports_transactions=True,
            supports_returning=False,
            supports_date_only_equality=True,
            parameter_style=ParameterStyle.POSITIONAL_FORMAT,
            max_batch_size=1000,
            entity_types=["TABLE", "VIEW"],
            supported_operations=["SELECT", "INSERT", "UPDATE", "DELETE", "SCHEMA_DISCOVERY"],
        )
