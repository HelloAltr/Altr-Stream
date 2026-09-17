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
from altr_stream.domain.errors import QueryExecutionError, SchemaDiscoveryError
from altr_stream.domain.query import QueryResult
from altr_stream.domain.schema import SourceSchema
from altr_stream.domain.source import ConnectionConfig, SourceType
from altr_stream.infrastructure.connectors.factory import ConnectorFactory
from altr_stream.infrastructure.connectors.mongodb.mapper import (
    build_source_schema_from_mongodb_samples,
    extract_columns_from_documents,
    normalize_bson_document,
    normalize_bson_value,
)


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
        """Discover and return the standardized schema of the physical MongoDB database using deterministic sampling."""
        client = None
        is_internal_client = False
        sample_limit = 100
        db_name = self.config.database_name or ""
        try:
            if self._client is not None:
                client = self._client
            else:
                client = self._create_client()
                is_internal_client = True

            db = client[db_name or "admin"]

            # 1. Fetch non-system collections
            all_collections = await db.list_collection_names()
            target_collections = sorted([
                c for c in all_collections
                if not c.startswith("system.") and c != "system.views"
            ])

            # 2. Deterministically sample up to 100 documents per collection sorted by _id
            sampled_collections: dict[str, list[dict[str, Any]]] = {}
            for coll_name in target_collections:
                coll = db[coll_name]
                cursor = coll.find({}).sort("_id", 1).limit(sample_limit)
                docs = await cursor.to_list(length=sample_limit)
                sampled_collections[coll_name] = docs

            # 3. Build standardized SourceSchema from observed samples
            return build_source_schema_from_mongodb_samples(
                source_id=source_id,
                source_name=source_name,
                database_name=db_name,
                sampled_collections=sampled_collections,
                sample_limit=sample_limit,
            )
        except (PyMongoError, asyncio.TimeoutError, OSError, ConnectionRefusedError) as e:
            sanitized = self._sanitize_error(e)
            raise SchemaDiscoveryError(
                f"Failed to discover schema from MongoDB '{source_name}': {sanitized}",
                details=sanitized,
            ) from e
        except Exception as e:
            sanitized = self._sanitize_error(e)
            raise SchemaDiscoveryError(
                f"Unexpected error during schema discovery for '{source_name}': {sanitized}",
                details=sanitized,
            ) from e
        finally:
            if is_internal_client and client is not None:
                try:
                    await client.close()
                except Exception:
                    pass

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

    async def _execute_find(self, db: Any, spec: dict[str, Any], start_time: float) -> QueryResult:
        coll_name = spec["collection"]
        coll = db[coll_name]
        filter_doc = spec.get("filter", {})
        if not isinstance(filter_doc, dict):
            raise QueryExecutionError("MongoDB 'find' filter must be a dictionary.")

        projection = spec.get("projection")
        if projection is not None and not isinstance(projection, dict):
            raise QueryExecutionError("MongoDB 'find' projection must be a dictionary.")

        cursor = coll.find(filter=filter_doc, projection=projection)

        if "sort" in spec and spec["sort"] is not None:
            cursor = cursor.sort(spec["sort"])
        if "skip" in spec and spec["skip"] is not None:
            cursor = cursor.skip(int(spec["skip"]))
        if "limit" in spec and spec["limit"] is not None:
            cursor = cursor.limit(int(spec["limit"]))

        limit_val = spec.get("limit")
        fetch_length = int(limit_val) if limit_val is not None and int(limit_val) > 0 else 1000
        raw_docs = await cursor.to_list(length=fetch_length)

        normalized_docs = [normalize_bson_document(d) for d in raw_docs]

        projection_fields = spec.get("projection_fields")
        if projection_fields and isinstance(projection_fields, list):
            mapped_rows: list[dict[str, Any]] = []
            for doc in normalized_docs:
                row: dict[str, Any] = {}
                for pf in projection_fields:
                    col_name = pf["name"]
                    path_segments = pf["path"]
                    val: Any = doc
                    for seg in path_segments:
                        if isinstance(val, dict):
                            val = val.get(seg)
                        else:
                            val = None
                            break
                    row[col_name] = val
                mapped_rows.append(row)
            normalized_rows = mapped_rows
            columns = [pf["name"] for pf in projection_fields]
        else:
            normalized_rows = normalized_docs
            columns = extract_columns_from_documents(raw_docs, projection=projection)

        execution_time_ms = round((time_module.perf_counter() - start_time) * 1000, 2)

        return QueryResult(
            columns=columns,
            rows=normalized_rows,
            row_count=len(normalized_rows),
            affected_rows=None,
            message="Query executed successfully",
            execution_time_ms=execution_time_ms,
        )

    async def _execute_insert_many(self, db: Any, spec: dict[str, Any], start_time: float) -> QueryResult:
        coll_name = spec["collection"]
        coll = db[coll_name]
        documents = spec.get("documents")
        if not isinstance(documents, list) or len(documents) == 0:
            raise QueryExecutionError("MongoDB 'insert_many' requires a non-empty list of document dictionaries in 'documents'.")
        for doc in documents:
            if not isinstance(doc, dict):
                raise QueryExecutionError("Each item in 'documents' must be a dictionary.")

        ordered = bool(spec.get("ordered", True))
        docs_to_insert = [dict(d) for d in documents]
        result = await coll.insert_many(docs_to_insert, ordered=ordered)

        inserted_count = len(result.inserted_ids)
        inserted_rows = [{"_id": normalize_bson_value(id_val)} for id_val in result.inserted_ids]
        execution_time_ms = round((time_module.perf_counter() - start_time) * 1000, 2)

        return QueryResult(
            columns=["_id"],
            rows=inserted_rows,
            row_count=inserted_count,
            affected_rows=inserted_count,
            message=f"Inserted {inserted_count} document(s)",
            execution_time_ms=execution_time_ms,
        )

    async def _execute_update_many(self, db: Any, spec: dict[str, Any], start_time: float) -> QueryResult:
        coll_name = spec["collection"]
        coll = db[coll_name]
        filter_doc = spec.get("filter", {})
        if not isinstance(filter_doc, dict):
            raise QueryExecutionError("MongoDB 'update_many' filter must be a dictionary.")

        update_doc = spec.get("update")
        if not isinstance(update_doc, dict) or not update_doc:
            raise QueryExecutionError("MongoDB 'update_many' requires a non-empty update dictionary in 'update'.")

        upsert = bool(spec.get("upsert", False))
        result = await coll.update_many(filter=filter_doc, update=update_doc, upsert=upsert)

        execution_time_ms = round((time_module.perf_counter() - start_time) * 1000, 2)
        return QueryResult(
            columns=[],
            rows=[],
            row_count=0,
            affected_rows=result.modified_count,
            message=f"Updated {result.modified_count} document(s) (matched {result.matched_count})",
            execution_time_ms=execution_time_ms,
        )

    async def _execute_delete_many(self, db: Any, spec: dict[str, Any], start_time: float) -> QueryResult:
        coll_name = spec["collection"]
        coll = db[coll_name]
        filter_doc = spec.get("filter", {})
        if not isinstance(filter_doc, dict):
            raise QueryExecutionError("MongoDB 'delete_many' filter must be a dictionary.")

        result = await coll.delete_many(filter=filter_doc)

        execution_time_ms = round((time_module.perf_counter() - start_time) * 1000, 2)
        return QueryResult(
            columns=[],
            rows=[],
            row_count=0,
            affected_rows=result.deleted_count,
            message=f"Deleted {result.deleted_count} document(s)",
            execution_time_ms=execution_time_ms,
        )

    async def _dispatch_command(
        self, db: Any, query: str, parameters: list[Any] | None, start_time: float
    ) -> QueryResult:
        if not query or not isinstance(query, str):
            raise QueryExecutionError("MongoDB query must be a non-empty operation string (e.g. 'mongodb:find').")

        op = query.replace("mongodb:", "").strip().lower()
        spec = parameters[0] if parameters and len(parameters) > 0 and isinstance(parameters[0], dict) else {}

        if not spec or not isinstance(spec, dict):
            raise QueryExecutionError("MongoDB command requires a dictionary specification in parameters.")

        if "collection" not in spec or not isinstance(spec["collection"], str) or not spec["collection"].strip():
            raise QueryExecutionError("MongoDB command specification missing required string field 'collection'.")

        if op == "find":
            return await self._execute_find(db, spec, start_time)
        elif op == "insert_many":
            return await self._execute_insert_many(db, spec, start_time)
        elif op == "update_many":
            return await self._execute_update_many(db, spec, start_time)
        elif op == "delete_many":
            return await self._execute_delete_many(db, spec, start_time)
        else:
            raise QueryExecutionError(
                f"Unsupported MongoDB operation: '{op}'. Supported operations are: 'find', 'insert_many', 'update_many', 'delete_many'."
            )

    async def execute_query(self, query: str, parameters: list[Any] | None = None) -> QueryResult:
        """Execute a native MongoDB command and return normalized QueryResult."""
        start_time = time_module.perf_counter()
        client = None
        is_internal_client = False
        try:
            if self._client is not None:
                client = self._client
            else:
                client = self._create_client()
                is_internal_client = True

            db_name = self.config.database_name or "admin"
            db = client[db_name]

            return await self._dispatch_command(db, query, parameters, start_time)
        except QueryExecutionError:
            raise
        except (PyMongoError, asyncio.TimeoutError, OSError, ConnectionRefusedError) as e:
            sanitized = self._sanitize_error(e)
            raise QueryExecutionError(
                f"MongoDB query execution failed: {sanitized}",
                details=sanitized,
            ) from e
        except Exception as e:
            sanitized = self._sanitize_error(e)
            raise QueryExecutionError(
                f"Unexpected error executing MongoDB query: {sanitized}",
                details=sanitized,
            ) from e
        finally:
            if is_internal_client and client is not None:
                try:
                    await client.close()
                except Exception:
                    pass

    async def execute_batch(self, queries: list[tuple[str, list[Any] | None]]) -> QueryResult:
        """Execute multiple MongoDB commands sequentially."""
        start_time = time_module.perf_counter()
        total_affected: int | None = None
        all_rows: list[dict[str, Any]] = []
        all_columns: list[str] = []
        messages: list[str] = []

        client = None
        is_internal_client = False
        try:
            if self._client is not None:
                client = self._client
            else:
                client = self._create_client()
                is_internal_client = True

            db_name = self.config.database_name or "admin"
            db = client[db_name]

            for query_str, params in queries:
                res = await self._dispatch_command(db, query_str, params, start_time)
                if res.columns and not all_columns:
                    all_columns = res.columns
                if res.rows:
                    all_rows.extend(res.rows)
                if res.affected_rows is not None:
                    total_affected = (total_affected or 0) + res.affected_rows
                if res.message:
                    messages.append(res.message)

            execution_time_ms = round((time_module.perf_counter() - start_time) * 1000, 2)
            return QueryResult(
                columns=all_columns,
                rows=all_rows,
                row_count=len(all_rows),
                affected_rows=total_affected,
                message="; ".join(messages) if messages else "Batch executed successfully",
                execution_time_ms=execution_time_ms,
            )
        except QueryExecutionError:
            raise
        except (PyMongoError, asyncio.TimeoutError, OSError, ConnectionRefusedError) as e:
            sanitized = self._sanitize_error(e)
            raise QueryExecutionError(
                f"MongoDB batch execution failed: {sanitized}",
                details=sanitized,
            ) from e
        except Exception as e:
            sanitized = self._sanitize_error(e)
            raise QueryExecutionError(
                f"Unexpected error executing MongoDB batch: {sanitized}",
                details=sanitized,
            ) from e
        finally:
            if is_internal_client and client is not None:
                try:
                    await client.close()
                except Exception:
                    pass

