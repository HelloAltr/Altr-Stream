"""PostgreSQL connector implementation using asyncpg."""

import asyncio
import time
from typing import Any
import asyncpg

from altr_stream.domain.connector import (
    BaseConnector,
    ConnectionTestResult,
    SourceCapabilities,
)
from altr_stream.domain.errors import ConnectionFailedError, SchemaDiscoveryError
from altr_stream.domain.schema import SourceSchema
from altr_stream.domain.source import ConnectionConfig
from altr_stream.infrastructure.connectors.postgres.introspection import (
    COLUMNS_QUERY,
    FOREIGN_KEYS_QUERY,
    PRIMARY_KEYS_QUERY,
    TABLES_QUERY,
)
from altr_stream.infrastructure.connectors.postgres.mapper import build_source_schema_from_pg


class PostgreSQLConnector(BaseConnector):
    """PostgreSQL database connector implementation."""

    def __init__(self, config: ConnectionConfig, timeout_sec: float = 5.0):
        super().__init__(config)
        self.timeout_sec = timeout_sec

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
        start_time = time.perf_counter()
        conn = None
        try:
            conn = await self._get_connection()
            version = await conn.fetchval("SELECT version();")
            latency_ms = round((time.perf_counter() - start_time) * 1000, 2)
            return ConnectionTestResult(
                success=True,
                message=f"Connected successfully to PostgreSQL ({latency_ms} ms)",
                latency_ms=latency_ms,
                server_version=str(version),
            )
        except (asyncpg.PostgresError, asyncio.TimeoutError, OSError, ConnectionRefusedError) as e:
            latency_ms = round((time.perf_counter() - start_time) * 1000, 2)
            sanitized = self._sanitize_error(e)
            return ConnectionTestResult(
                success=False,
                message=f"Connection failed: {sanitized}",
                latency_ms=latency_ms,
                error_details=sanitized,
            )
        except Exception as e:
            latency_ms = round((time.perf_counter() - start_time) * 1000, 2)
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
            supported_operations=["SELECT", "INSERT", "UPDATE", "DELETE", "SCHEMA_DISCOVERY"],
        )
