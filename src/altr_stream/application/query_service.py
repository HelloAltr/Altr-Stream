"""Query execution application service."""

import json
from typing import Any

from altr_stream.domain.errors import (
    QueryExecutionError,
    QueryExecutionNotSupportedError,
    ReadOnlyQueryRequiredError,
    SourceNotFoundError,
)
from altr_stream.domain.query import QueryResult
from altr_stream.domain.query_validation import validate_query
from altr_stream.domain.source import SourceType
from altr_stream.infrastructure.connectors.factory import ConnectorFactory
from altr_stream.infrastructure.connectors.mongodb.shell_parser import (
    parse_mongodb_shell_query,
)
from altr_stream.infrastructure.database.repository import SqliteSourceRepository


def _prepare_mongodb_query(
    query: str, parameters: list[Any] | None = None, mode: str | None = None
) -> tuple[str, list[Any]]:
    """
    Parse and normalize a MongoDB query into a canonical operation string and parameter dictionary.

    Conforms to the locked architectural contract:
        query = "mongodb:<operation>"
        parameters = [native_command_dict]
    """
    if not query or not query.strip():
        if parameters and len(parameters) > 0 and isinstance(parameters[0], dict):
            spec = parameters[0]
            op = spec.pop("operation", "find") if isinstance(spec, dict) else "find"
            return f"mongodb:{op}", parameters
        raise ReadOnlyQueryRequiredError("Query cannot be empty.")

    raw_query = query.strip()

    # Case 1: Parameters already provided as a dictionary specification (e.g. from AltrQL lowering)
    if parameters and len(parameters) > 0 and isinstance(parameters[0], dict):
        if raw_query.startswith("mongodb:"):
            return raw_query, parameters
        else:
            op = raw_query if raw_query in {"find", "insert_many", "update_many", "delete_many"} else "find"
            return f"mongodb:{op}", parameters

    # Case 2: Query string contains an internal "mongodb:<op>" prefix
    if raw_query.startswith("mongodb:"):
        prefix, _, rest = raw_query.partition(" ")
        if not rest.strip():
            prefix, _, rest = raw_query.partition("\n")

        op = prefix.replace("mongodb:", "").strip().lower() or "find"
        rest_stripped = rest.strip()
        if rest_stripped:
            try:
                spec = json.loads(rest_stripped)
            except Exception as e:
                raise QueryExecutionError(f"Invalid MongoDB JSON query: {e}") from e
            if not isinstance(spec, dict):
                raise QueryExecutionError("MongoDB query specification must be a JSON object.")
            if "operation" in spec:
                op = str(spec.pop("operation")).strip().lower()
            return f"mongodb:{op}", [spec]
        else:
            raise QueryExecutionError("MongoDB command requires a dictionary specification in parameters.")

    # Case 3: Explicit or inferred mode handling
    normalized_mode = mode.strip().lower() if mode else None

    # If explicit 'shell' mode or query starts with 'db.' (or non-JSON), parse with MongoDB Shell parser
    if normalized_mode == "shell":
        op_str, spec = parse_mongodb_shell_query(raw_query)
        return op_str, [spec]

    # If explicit 'physical' mode, parse directly with structured JSON parser
    if normalized_mode == "physical":
        try:
            spec = json.loads(raw_query)
        except Exception as e:
            raise QueryExecutionError(f"Invalid MongoDB JSON query: {e}") from e

        if not isinstance(spec, dict):
            raise QueryExecutionError("MongoDB query specification must be a JSON object.")

        if "operation" in spec:
            op = str(spec.pop("operation")).strip().lower()
        elif "documents" in spec or "document" in spec:
            op = "insert_many"
        elif "update" in spec:
            op = "update_many"
        elif "delete" in spec:
            op = "delete_many"
        else:
            op = "find"

        return f"mongodb:{op}", [spec]

    # Mode is None: deterministic syntax-based routing (no ambiguous fallback hiding errors)
    if raw_query.startswith("{"):
        try:
            spec = json.loads(raw_query)
        except Exception as e:
            raise QueryExecutionError(f"Invalid MongoDB JSON query: {e}") from e

        if not isinstance(spec, dict):
            raise QueryExecutionError("MongoDB query specification must be a JSON object.")

        if "operation" in spec:
            op = str(spec.pop("operation")).strip().lower()
        elif "documents" in spec or "document" in spec:
            op = "insert_many"
        elif "update" in spec:
            op = "update_many"
        elif "delete" in spec:
            op = "delete_many"
        else:
            op = "find"

        return f"mongodb:{op}", [spec]
    else:
        # Treats non-JSON (e.g. `db.users...`) deterministically as MongoDB Shell syntax
        op_str, spec = parse_mongodb_shell_query(raw_query)
        return op_str, [spec]


class QueryService:
    """Application use cases for native physical query execution."""

    def __init__(self, repository: SqliteSourceRepository):
        self.repository = repository

    async def execute_query(
        self,
        source_id: str,
        query: str,
        parameters: list[Any] | None = None,
        mode: str | None = None,
    ) -> QueryResult:
        """Validate, orchestrate, and execute a native query against a registered source."""
        # 1. Verify source exists
        source = await self.repository.get_by_id(source_id)
        if not source:
            raise SourceNotFoundError(source_id)

        # 2. Validate and prepare query format according to source dialect
        if source.type == SourceType.MONGODB:
            cleaned_query, final_params = _prepare_mongodb_query(query, parameters, mode=mode)
        else:
            if mode is not None and mode.strip():
                raise QueryExecutionError(
                    f"Query mode '{mode}' is only supported for MongoDB sources, but source '{source.name}' has type '{source.type.value}'."
                )
            cleaned_query = validate_query(query)
            final_params = parameters

        # 3. Resolve connector
        connector = ConnectorFactory.get_connector(source.type, source.connection_config)

        # 4. Check custom_query capability
        caps = connector.get_capabilities()
        if not caps.custom_query:
            raise QueryExecutionNotSupportedError(
                f"Connector for source '{source.name}' ({source.type.value}) does not support custom query execution."
            )

        # 5. Execute within connector context
        async with connector:
            return await connector.execute_query(cleaned_query, parameters=final_params)

    async def execute_batch(
        self,
        source_id: str,
        queries: list[tuple[str, list[Any] | None]],
    ) -> QueryResult:
        """Validate, orchestrate, and execute a sequence of queries atomically within a transaction."""
        # 1. Verify source exists
        source = await self.repository.get_by_id(source_id)
        if not source:
            raise SourceNotFoundError(source_id)

        # 2. Validate and prepare queries according to source dialect
        cleaned_queries: list[tuple[str, list[Any] | None]] = []
        for q, p in queries:
            if source.type == SourceType.MONGODB:
                cq, cp = _prepare_mongodb_query(q, p)
                cleaned_queries.append((cq, cp))
            else:
                cleaned_queries.append((validate_query(q), p))

        # 3. Resolve connector
        connector = ConnectorFactory.get_connector(source.type, source.connection_config)

        # 4. Check custom_query capability
        caps = connector.get_capabilities()
        if not caps.custom_query:
            raise QueryExecutionNotSupportedError(
                f"Connector for source '{source.name}' ({source.type.value}) does not support custom query execution."
            )

        # 5. Execute within connector context
        async with connector:
            return await connector.execute_batch(cleaned_queries)

