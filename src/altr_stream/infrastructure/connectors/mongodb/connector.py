"""MongoDB physical connector implementation using PyMongo native AsyncMongoClient."""

import asyncio
import re
import time as time_module
from typing import Any
import urllib.parse

from pymongo import AsyncMongoClient
from pymongo.errors import PyMongoError

from altr_stream.domain.connector import (
    BaseConnector,
    ConnectionTestResult,
    ParameterStyle,
    SourceCapabilities,
)
from altr_stream.domain.query import QueryResult
from altr_stream.domain.schema import SourceSchema
from altr_stream.domain.source import ConnectionConfig, SourceType
from altr_stream.infrastructure.connectors.factory import ConnectorFactory


@ConnectorFactory.register(SourceType.MONGODB)
class MongoDBConnector(BaseConnector):
    """MongoDB physical connector implementation with async client lifecycle management."""

    def __init__(self, config: ConnectionConfig, timeout_sec: float = 5.0):
        super().__init__(config, timeout_sec=timeout_sec)
        self._client: AsyncMongoClient | None = None

    def _build_connection_uri(self) -> str:
        """Construct the MongoDB connection URI safely from ConnectionConfig."""
        host = self.config.host or "localhost"
        port = int(self.config.port or 27017)
        db_name = self.config.database_name or ""

        # Query options (e.g. authSource, replicaSet, tls, directConnection)
        options: dict[str, Any] = dict(self.config.options) if self.config.options else {}

        if self.config.username and self.config.password:
            user_quoted = urllib.parse.quote_plus(self.config.username)
            pass_quoted = urllib.parse.quote_plus(self.config.password)
            userinfo = f"{user_quoted}:{pass_quoted}@"
            # Set default authSource if not explicitly provided
            if "authSource" not in options:
                options["authSource"] = "admin"
        elif self.config.username:
            user_quoted = urllib.parse.quote_plus(self.config.username)
            userinfo = f"{user_quoted}@"
        else:
            userinfo = ""

        query_params = urllib.parse.urlencode(options) if options else ""
        query_suffix = f"?{query_params}" if query_params else ""

        return f"mongodb://{userinfo}{host}:{port}/{db_name}{query_suffix}"

    def _create_client(self) -> AsyncMongoClient:
        """Instantiate a new AsyncMongoClient configured with timeouts."""
        uri = self._build_connection_uri()
        timeout_ms = int(self.timeout_sec * 1000)
        return AsyncMongoClient(
            uri,
            serverSelectionTimeoutMS=timeout_ms,
            connectTimeoutMS=timeout_ms,
            socketTimeoutMS=timeout_ms,
        )

    async def initialize(self) -> None:
        """Initialize the PyMongo AsyncMongoClient connection."""
        if self._client is None:
            self._client = self._create_client()
        self._is_initialized = True

    async def close(self) -> None:
        """Safely close the PyMongo AsyncMongoClient and reset connector state."""
        if self._client is not None:
            try:
                await self._client.close()
            except Exception:
                pass
            self._client = None
        self._is_initialized = False

    def _sanitize_error(self, err: Exception) -> str:
        """Sanitize error messages to prevent leaking passwords or credentials in URIs."""
        err_msg = str(err)
        # 1. Mask explicit password string
        if self.config.password and self.config.password in err_msg:
            err_msg = err_msg.replace(self.config.password, "••••••••")
        # 2. Mask password inside URL encoded forms if present
        if self.config.password:
            quoted_pw = urllib.parse.quote_plus(self.config.password)
            if quoted_pw in err_msg:
                err_msg = err_msg.replace(quoted_pw, "••••••••")
        # 3. Mask mongodb://user:pass@host regex patterns
        err_msg = re.sub(
            r"mongodb://([^:]+):([^@]+)@",
            r"mongodb://\1:••••••••@",
            err_msg,
        )
        return err_msg

    async def test_connection(self) -> ConnectionTestResult:
        """Test reachability and authentication with the MongoDB server using ping and buildInfo."""
        start_time = time_module.perf_counter()
        client = None
        is_internal_client = False
        try:
            if self._client is not None:
                client = self._client
            else:
                client = self._create_client()
                is_internal_client = True

            # Determine target database for command execution
            db_name = self.config.database_name or "admin"
            db = client[db_name]

            # 1. Ping the server to verify connectivity and authentication
            await db.command("ping")

            # 2. Query buildInfo to extract server version
            server_version: str | None = None
            try:
                build_info = await db.command("buildInfo")
                server_version = str(build_info.get("version", ""))
            except Exception:
                # If buildInfo fails due to restricted permissions, proceed with successful ping
                pass

            latency_ms = round((time_module.perf_counter() - start_time) * 1000, 2)
            version_str = f" v{server_version}" if server_version else ""
            return ConnectionTestResult(
                success=True,
                message=f"Connected successfully to MongoDB{version_str} ({latency_ms} ms)",
                latency_ms=latency_ms,
                server_version=server_version,
            )
        except (PyMongoError, asyncio.TimeoutError, OSError, ConnectionRefusedError) as e:
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
            if is_internal_client and client is not None:
                try:
                    await client.close()
                except Exception:
                    pass

    async def discover_schema(self, source_id: str, source_name: str) -> SourceSchema:
        """Discover and return the standardized schema of the physical MongoDB database."""
        raise NotImplementedError("MongoDB schema discovery will be implemented in Phase 0.7.2b.")

    def get_capabilities(self) -> SourceCapabilities:
        """Report physical capabilities for the MongoDB connector."""
        return SourceCapabilities(
            schema_discovery=True,
            read=True,
            write=True,
            cdc=False,
            batch_execution=True,
            streaming=False,
            custom_query=True,
            supports_transactions=False,
            supports_returning=False,
            supports_date_only_equality=True,
            parameter_style=ParameterStyle.DOCUMENT_BSON,
            max_batch_size=1000,
            entity_types=["COLLECTION"],
            supported_operations=["find", "insert_many", "update_many", "delete_many"],
        )

    async def execute_query(self, query: str, parameters: list[Any] | None = None) -> QueryResult:
        """Execute a native MongoDB command and return normalized results."""
        raise NotImplementedError("MongoDB query execution will be implemented in Phase 0.7.2c.")

    async def execute_batch(self, queries: list[tuple[str, list[Any] | None]]) -> QueryResult:
        """Execute a batch of native MongoDB commands."""
        raise NotImplementedError("MongoDB batch execution will be implemented in Phase 0.7.2c.")
