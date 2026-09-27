# Altr Stream — Connector Authoring Guide

This guide describes how to author, implement, and register physical database connectors in Altr Stream.

---

## 1. The `BaseConnector` Interface

All physical database connectors inherit from `BaseConnector` located in `src/altr_stream/domain/connector.py`. A connector is responsible for managing physical connection pools, introspecting database schemas, and executing parameterized physical queries.

```python
from abc import ABC, abstractmethod
from typing import Any
from altr_stream.domain.source import Source, PhysicalSchema
from altr_stream.query_engine.domain.physical import PhysicalQuery

class BaseConnector(ABC):
    """Abstract base class for all physical database connectors."""

    def __init__(self, source: Source):
        self.source = source
        self._pool: Any = None

    @abstractmethod
    async def connect(self) -> None:
        """Initialize the connection pool or client."""
        ...

    @abstractmethod
    async def disconnect(self) -> None:
        """Gracefully drain and close connection pools."""
        ...

    @abstractmethod
    async def test_connection(self) -> bool:
        """Validate socket connectivity and credentials."""
        ...

    @abstractmethod
    async def discover_schema(self) -> PhysicalSchema:
        """Introspect physical tables/collections, columns/fields, and primary keys."""
        ...

    @abstractmethod
    async def execute_query(self, query: PhysicalQuery) -> list[dict[str, Any]]:
        """Execute a parameterized query and return normalized row dictionaries."""
        ...
```

---

## 2. Connector Lifecycle & Connection Pools

Connectors must utilize asynchronous connection pools or non-blocking clients to ensure high concurrency:

- **PostgreSQL**: `asyncpg` (`asyncpg.create_pool(...)`)
- **MySQL**: `aiomysql` (`aiomysql.create_pool(...)`)
- **SQLite**: `aiosqlite` (`aiosqlite.connect(...)`)
- **MongoDB**: `pymongo` with thread-pool offloading or async motor driver

### Connection Timeouts
Connectors should respect `settings.default_connection_timeout_sec` during connection establishment and query execution.

---

## 3. Schema Discovery & Canonical Type Mapping

The `discover_schema()` method introspects the physical database catalog (e.g. `information_schema` in SQL databases, or collection inspection in MongoDB) and returns a `PhysicalSchema` model composed of `PhysicalEntity` and `PhysicalField` records.

Physical types must be mapped into canonical Altr Stream data types:
| Physical Database Type | Canonical Altr Type |
| :--- | :--- |
| `VARCHAR`, `TEXT`, `CHAR`, `String` | `STRING` |
| `INT`, `BIGINT`, `SMALLINT`, `INTEGER` | `INTEGER` |
| `DECIMAL`, `NUMERIC`, `FLOAT`, `DOUBLE` | `DECIMAL` |
| `BOOLEAN`, `TINYINT(1)`, `bool` | `BOOLEAN` |
| `TIMESTAMP`, `TIMESTAMPTZ`, `DATETIME`, `Date` | `TIMESTAMP` |
| `JSON`, `JSONB`, `BSON / Object` | `JSON` |
| `BYTEA`, `BLOB`, `Binary` | `BINARY` |

---

## 4. Query Execution & Error Boundaries

When implementing `execute_query(query: PhysicalQuery)`:
1. **Parameterized Execution**: Always pass query parameters separately to prevent SQL injection vulnerabilities. Never interpolate raw user values into SQL strings.
2. **Dictionary Conversion**: Results must be returned as a list of Python dictionaries (`list[dict[str, Any]]`) with string column names.
3. **No ID Bleed**: Non-relational physical IDs (such as MongoDB `_id`) must be stripped or converted to strings if explicitly projected.
4. **Exception Handling**: Connectors should raise standard domain exceptions on connection or execution failures, allowing the `QueryPlanner` to categorize the error cleanly into `SOURCE_UNREACHABLE` or `EXECUTION_FAILED`.
