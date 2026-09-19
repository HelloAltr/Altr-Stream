# Altr Stream

> **Physical source abstraction, multi-database query compilation, and data infrastructure service for the HelloAltr / Altr Mesh ecosystem.**

Altr Stream is responsible for knowing *how* to physically connect to, introspect, and operate across heterogeneous physical data sources (**PostgreSQL**, **MySQL**, **SQLite**, and **MongoDB**). It encapsulates connection pools, catalog discovery, schema normalization, native pushdown operations, the **AltrQL Federated Query Engine (v0.9.0-alpha)**, the **Logical Model & Source Mapping Registry**, and future Change Data Capture (CDC).

---

## 🏗️ System Architecture

```text
┌─────────────────────────────────────────────────────────────────────────────┐
│                              Client Browser                                 │
└──────────────────────────────────────┬──────────────────────────────────────┘
                                       │ HTTP / JSON
                                       ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                     altr-stream-admin (Port 3000)                           │
│                Flutter Web Application + Nginx Reverse Proxy                │
│        - Persistent desktop sidebar & progressive disclosure UX             │
│        - Overview, Data Sources, Logical Models, Activity, Settings         │
│        - Schema Explorer & Source-Scoped Native Database Playground         │
│        - Global AltrQL Console & Multi-View Compiler Inspector (/altrql)    │
│        - Auto-Select / All Sources Federated Multi-DB Query Execution       │
│        - 4-step guided source onboarding wizard                             │
│        - Serves pre-compiled static Flutter Web bundle                      │
│        - Proxies /api/* to backend service                                  │
└──────────────────────────────────────┬──────────────────────────────────────┘
                                       │ Internal Network (/api/*)
                                       ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                       altr-stream-app (Port 8000)                           │
│                           FastAPI Backend Service                           │
│        - Source registration & connection lifecycle management              │
│        - AltrQL v0.9.0-alpha Federated Query Engine & Compiler Pipeline     │
│        - Source Selector & Federated Multi-Source Execution Engine          │
│        - Canonical Schema Catalog Introspection & Normalization Engine      │
│        - Logical Model & Source Mapping Registry (Lifecycle & Validation)   │
│        - Internal Metadata Store (SQLite / aiosqlite)                       │
│        - Multi-database physical connectors & pure dialect lowerers         │
└───────┬──────────────────────┬──────────────────────┬───────────────────────┘
        │                      │                      │                       │
        ▼ asyncpg              ▼ aiomysql             ▼ aiosqlite             ▼ pymongo
┌───────────────┐      ┌───────────────┐      ┌───────────────┐      ┌────────────────┐
│  PostgreSQL   │      │     MySQL     │      │    SQLite     │      │    MongoDB     │
│  (Port 5432)  │      │  (Port 3306)  │      │ (Local/File)  │      │  (Port 27017)  │
└───────────────┘      └───────────────┘      └───────────────┘      └────────────────┘
```

---

## ⚡ AltrQL Federated Query Engine (v0.9.0-alpha)

AltrQL is a declarative, database-neutral logical query and mutation language designed for the Altr platform. The query engine supports both single-source targeted execution and federated multi-source logical execution across heterogeneous physical databases:

```text
Raw AltrQL String
       │
       ▼ Lex & Parse
Canonical AST (`AltrQueryIR`)
       │
       ▼ Semantic Validation & Normalization
Validated AST
       │
       ▼ Schema Binding & Type Validation
Bound AST (`BoundAltrQueryIR`)
       │
       ▼ Pure Dialect Lowering (Postgres | MySQL | SQLite | MongoDB)
Physical Query (`PhysicalQuery` | `PhysicalQueryBatch`)
       │
       ▼ Transactional Connector Execution
Normalized Query Result (`QueryResult`)
```

### Supported Operations & Semantic Parity (v0.7.6-alpha)

#### 1. `GET` (Logical Retrieval & Cross-DB Semantic Parity)
```altrql
GET users (
    id,
    username AS user_name,
    metadata.tier AS user_tier,
    created_at
) WHERE {
    age = {18..65},
    created_at = @2026-09-06,
    status != "INACTIVE",
    email HAS {"@company.com", "@partner.org"},
    metadata.tier != NULL
} SORT {
    created_at DESC,
    username ASC
} TOP 10 OFFSET 20;
```
- **Projections & Aliases**: Field selections with top-level and nested path aliasing (`username AS user_name`, `metadata.tier AS user_tier`).
- **Expressions**: Rich logical boolean tree (`AND`, `,`, `OR`, `NOT`, `{ ... }`).
- **Strict Two-Valued NULL Logic**: Predicates resolve strictly to `TRUE` or `FALSE` across all engines:
  - `field = NULL` compiles to `"field" IS NULL` (SQL) / `{"field": None}` (MongoDB).
  - `field != NULL` compiles to `"field" IS NOT NULL` (SQL) / `{"field": {"$ne": None}}` (MongoDB).
  - Scalar inequality `field != "val"` includes `NULL` values: `("field" != $1 OR "field" IS NULL)` (SQL) / `{"field": {"$ne": "val"}}` (MongoDB).
  - `field = {A, B, NULL}` compiles to `((field = $1 OR field = $2) OR field IS NULL)`.
  - `field != {A, B, NULL}` compiles to `((field NOT IN ($1, $2)) AND field IS NOT NULL)`.
  - `field != {A, B}` (without NULL) compiles to `((field NOT IN ($1, $2)) OR field IS NULL)`.
- **String Pattern Matchers & Wildcard Escaping**: `STARTS`, `ENDS`, `HAS`, `NOT HAS` with single values or ValueSets (`HAS {"a", "b"}`). Literal special characters (`%`, `_`, `\`) are safely escaped with explicit dialect escape clauses (`ESCAPE '\'` in PostgreSQL/SQLite, `ESCAPE '\\'` in MySQL, `re.escape()` in MongoDB).
- **Explicit SORT NULL Ordering Parity**:
  - `ASC` orders `NULL` values **FIRST** across all databases (`ASC NULLS FIRST` in PostgreSQL; emulated in SQLite/MySQL; custom sort expressions in MongoDB).
  - `DESC` orders `NULL` values **LAST** across all databases (`DESC NULLS LAST` in PostgreSQL; emulated in SQLite/MySQL; custom sort expressions in MongoDB).
- **Precision-Aware Temporal Comparisons**: Comparing a date-only literal (`@YYYY-MM-DD`) against a `TIMESTAMP`/`TIMESTAMPTZ` field rewrites automatically into a half-open day range `("created_at" >= $1 AND "created_at" < $2)` covering the full calendar day `[00:00:00, 24:00:00)`.

#### 2. `CREATE` (Single & Batch Insertions, Explicit NULL vs Omission)
- **Single-Record Syntax**:
  ```altrql
  CREATE users (
      username: "alice",
      email: "alice@example.com",
      metadata: NULL
  );
  ```
- **Explicit NULL vs Omission**: Assigning `field: NULL` inserts an explicit `NULL` into nullable columns. Omitted columns are excluded from `INSERT`, allowing database column defaults to apply. Non-nullable fields assigned `NULL` fail validation at schema-binding time (`TypeCompatibilityError`).
- **Batch / Grouped Syntax**:
  ```altrql
  CREATE users (
      (username: "alice", email: "alice@example.com"),
      (username: "bob", email: "bob@example.com")
  );
  ```
- **Consecutive-Only Grouping**: Homogeneous records lower into a single multi-row `INSERT INTO ... VALUES (...)` / MongoDB `insert_many`. Heterogeneous records with differing column shapes (e.g. `[A, A, B, A]`) are grouped only across adjacent matching shapes (`[A, A]`, `[B]`, `[A]`), preserving exact logical record order and emitting a `PhysicalQueryBatch`.
- **Atomic Batch Execution**: Statements execute sequentially inside an explicit transaction (`async with conn.transaction():`), ensuring complete rollback on any record failure.

#### 3. `UPDATE` (Set-Based with Mandatory WHERE & NULL Support)
```altrql
UPDATE users (
    full_name: "Alice Updated",
    metadata: NULL
) WHERE {
    email = "alice@example.com"
};
```
- **Mandatory WHERE**: Full-table mutations without a `WHERE` clause are rejected at parse and validation time as a language-level safety invariant.
- **NULL Assignments**: Explicitly assigning `field: NULL` sets the column to `NULL` for nullable fields; non-nullable fields are rejected at binding time.
- **Single PhysicalQuery**: Compiles to a single parameterized physical query with deterministic parameter ordering (`$1` for SET, `$2` for WHERE).

#### 4. `DELETE` (Constrained & Mass Mutations)
- **Constrained DELETE**:
  ```altrql
  DELETE users WHERE { metadata = NULL };
  ```
  Deleting with a predicate (including `field = NULL` or `field != NULL`) is classified as `CONSTRAINED`.
- **Mass DELETE (Safety Gated)**:
  ```altrql
  DELETE users;
  ```
  Requires explicit `confirm_mass_mutation=true` in the execution API, otherwise returning `MassMutationConfirmationRequiredError`.

---

## 🗂️ Logical Model & Source Mapping Registry (v0.7.0+)

Altr Stream provides a centralized registry for abstract business entities (Logical Models) and their mappings to physical database schemas:

- **Logical Models**: Database-agnostic entity definitions with typed logical fields (`STRING`, `INTEGER`, `DECIMAL`, `BOOLEAN`, `TIMESTAMP`, `JSON`, etc.).
- **Source Mappings**: Explicit entity and field-level mappings binding logical models to physical tables/collections and columns/paths.
- **Validation Lifecycle**: Mappings transition through strict validation states (`DRAFT` $\rightarrow$ `VALIDATED` $\rightarrow$ `ACTIVE` $\rightarrow$ `ERROR`) backed by an automated type compatibility matrix.

---

## 🌐 Federated Multi-Source Logical Query Execution (v0.9.0-alpha)

Altr Stream v0.9 introduces declarative, multi-database query federation across **PostgreSQL**, **MySQL**, **SQLite**, and **MongoDB** through the Logical Model & Source Mapping Registry.

### 1. Auto-Select / All Sources (Federated Execution)
Executing a query with `Auto-Select / All Sources` targets the canonical Logical Schema and fans out across all currently eligible active source mappings:
```altrql
GET students;
```
1. **Logical Entity Resolution**: Resolves the target logical entity with case-insensitive and singular/plural alignment.
2. **Active Mapping Discovery**: Discovers all active source mappings registered for the entity.
3. **Physical Plan Generation & Lowering**: Lowers the logical IR into parameterized physical plans tailored to each backend dialect (PostgreSQL SQL, MySQL SQL, SQLite SQL, MongoDB aggregation pipelines).
4. **Parallel Execution**: Dispatches queries concurrently across participating physical database connections.
5. **Canonical Result Normalization**: Translates dialect-specific physical column names into canonical logical fields (e.g., PostgreSQL `full_name`, MySQL `student_name`, SQLite `name` $\rightarrow$ canonical `name`) and strips physical engine artifacts (e.g., MongoDB `_id`).
6. **Unified Merging & Global Operations**: Merges streams, applies global logical sorting across the merged dataset, and enforces global `LIMIT`/`OFFSET`/`TOP` pagination semantics.

> [!IMPORTANT]
> **Auto-Select / All Sources** means **federated logical execution across all currently eligible active mappings**. It does *not* mean picking a single source or falling back on error.

### 2. Explicit-Source Execution & Normalization Control
When querying a specific physical source (e.g., Target Source = `PostgreSQL`), two operational modes are supported:
- **`Normalize = OFF`**: Returns raw physical database columns/keys directly from the connector.
- **`Normalize = ON`**: Normalizes rows into the canonical logical schema using the active source mapping.

### 3. Execution & Observability Metadata Contract
Every query executed via `POST /api/v1/altrql/execute` returns machine-readable execution metadata in the response envelope:
```json
{
  "data": [...],
  "meta": {
    "execution_mode": "federated",
    "normalized": true,
    "source_count": 4,
    "row_count": 32,
    "duration_ms": 28.45,
    "sources": [
      {
        "source_id": "postgres-prod",
        "source_name": "PostgreSQL Primary",
        "source_type": "postgresql",
        "status": "success",
        "rows": 8,
        "execution_time_ms": 12.3
      },
      {
        "source_id": "mysql-prod",
        "source_name": "MySQL Replica",
        "source_type": "mysql",
        "status": "success",
        "rows": 8,
        "execution_time_ms": 10.1
      },
      {
        "source_id": "sqlite-local",
        "source_name": "SQLite Edge",
        "source_type": "sqlite",
        "status": "success",
        "rows": 8,
        "execution_time_ms": 2.4
      },
      {
        "source_id": "mongo-analytics",
        "source_name": "MongoDB Cluster",
        "source_type": "mongodb",
        "status": "success",
        "rows": 8,
        "execution_time_ms": 14.2
      }
    ]
  }
}
```

> [!NOTE]
> **Planned for v0.10**: Partial logical-model discovery fallback (e.g., executing `GET users;` when `users` is not yet a mapped logical entity but exists in physical source catalogs) is deferred to milestone v0.10.

---

## 🚀 Quick Start with Docker Compose

The complete multi-database system (Flutter Web Admin, FastAPI backend, PostgreSQL, MySQL, and MongoDB pre-seeded instances) can be launched using Docker Compose.

### 1. Build and Run Full Stack
```bash
docker compose up --build
```

### 2. Run in Background
```bash
docker compose up -d --build
```

### 3. Check Container Status
```bash
docker compose ps
```

### 4. Stop Services (Preserving Metadata & Data Volumes)
```bash
docker compose down
```

### 5. Complete Reset (Wipes Volumes & Resets Test Databases)
```bash
docker compose down -v
```

---

## 🌐 Access Points & Endpoints

| Service | Access URL / Port | Description |
| :--- | :--- | :--- |
| **Flutter Admin UI** | [http://localhost:3000](http://localhost:3000) | Desktop-first infrastructure management app for sources, models, schemas & telemetry |
| **Backend REST API** | [http://localhost:8000](http://localhost:8000) | Core data infrastructure REST API |
| **Interactive API Docs** | [http://localhost:8000/docs](http://localhost:8000/docs) | Swagger UI for exploring and testing API endpoints |
| **API Health Check** | [http://localhost:8000/api/v1/health](http://localhost:8000/api/v1/health) | Service health and engine version status |
| **AltrQL Compiler APIs** | `POST /api/v1/altrql/parse`<br>`POST /api/v1/altrql/bind`<br>`POST /api/v1/altrql/execute` | End-to-end query parsing, semantic validation, schema binding, physical lowering, federated planning & execution |
| **Logical Models APIs** | `GET /api/v1/models`<br>`POST /api/v1/models`<br>`POST /api/v1/models/{id}/mappings` | Logical model definition and physical source mapping registry |
| **PostgreSQL Test DB** | `localhost:5432` (`altr_test_db`) | User: `altr_test_user` • Password: `altr_test_pass` |
| **MySQL Test DB** | `localhost:3306` (`altr_test_db`) | User: `altr_test_user` • Password: `altr_test_pass` |
| **MongoDB Test DB** | `localhost:27017` (`altr_test_db`) | User: `altr_test_user` • Password: `altr_test_pass` |

---

## 💻 Local Development & Testing Workflow

### Backend (FastAPI + Pytest)
```bash
# Setup Python virtual environment
uv venv --python 3.12 .venv
source .venv/bin/activate
uv pip install -e ".[dev]"

# Run FastAPI backend with hot reload
uvicorn altr_stream.main:app --reload --host 0.0.0.0 --port 8000

# Run complete backend test suite (688 tests)
pytest tests/ -v
```

### Frontend (Flutter Web)
```bash
cd frontend/altr_stream_admin

# Fetch dependencies
flutter pub get

# Run Flutter Web development server with Chrome
flutter run -d chrome

# Run multi-viewport Flutter widget & integration tests (86 tests)
flutter test

# Run Flutter static analysis
flutter analyze

# Build release web bundle
flutter build web --release
```

---

## 📁 Repository Layout

```text
Altr-Stream/
├── frontend/
│   └── altr_stream_admin/       # Flutter Web Admin Application
│       ├── lib/
│       │   ├── core/            # API Client, AppConfig, Theme
│       │   ├── features/
│       │   │   ├── overview/    # Node overview, summaries & quick links
│       │   │   ├── sources/     # Sources list, details tabs & 4-step wizard
│       │   │   ├── models/      # Logical Model & Source Mapping Registry
│       │   │   ├── altrql_playground/ # Global AltrQL Console & Multi-View Compiler Inspector
│       │   │   ├── source_playground/ # Source-scoped Schema Explorer & Native Query Playground
│       │   │   ├── activity/    # Operational timeline
│       │   │   └── settings/    # Node configuration & diagnostics
│       │   ├── shared/          # Persistent AppShell, PageHeader, StatusBadges
│       │   └── main.dart        # Centralized router & state coordinator
│       ├── web/                 # Web template & index.html
│       ├── nginx.conf           # Production Nginx reverse proxy configuration
│       ├── Dockerfile           # Multi-stage Flutter build & Nginx runtime
│       └── pubspec.yaml         # Flutter dependencies
├── src/
│   └── altr_stream/             # FastAPI Backend Service
│       ├── domain/              # Source, Schema, Logical Model, Connector Contracts
│       ├── query_engine/        # AltrQL v0.7.6-alpha Compiler (Parser, Validator, Binder, Lowerers)
│       │   ├── binding/         # Schema resolution & type compatibility validation
│       │   ├── classification/  # Pure deterministic mutation classification & safety scoping
│       │   ├── domain/          # Canonical AST, Bound AST, PhysicalQuery models
│       │   ├── lowering/        # Pure dialect lowerers (Postgres, MySQL, SQLite, MongoDB)
│       │   ├── parser/          # Lexer & recursive descent parser
│       │   └── semantic/        # AST invariants validator & normalizer
│       ├── infrastructure/      # Physical DB Connectors (asyncpg, aiomysql, aiosqlite, pymongo)
│       ├── application/         # SourceService, SchemaService, QueryService, ModelRegistryService
│       ├── presentation/api/    # REST API Routes (/api/v1/sources, /models, /altrql, /queries)
│       └── main.py              # FastAPI Application Entry
├── tests/                       # Backend Pytest Test Suite (653 Unit & Integration Tests)
│   ├── unit/                    # Compiler unit tests (Parser, Validator, Binder, Lowerers)
│   └── integration/             # Cross-DB semantic parity & live database integration tests
├── docker/
│   ├── postgres/init.sql        # PostgreSQL test schemas & seed tables
│   ├── mysql/init.sql           # MySQL test schemas & seed tables
│   └── mongodb/init.js          # MongoDB test database & collections seed script
├── docker-compose.yml           # Multi-container production orchestration
├── docker-compose.dev.yml       # Development hot-reload override
├── Dockerfile                   # Python backend container
├── pyproject.toml               # Python packaging & dependencies
├── README.md                    # Project overview & architecture guide
└── USAGE.md                     # Operational manual & developer command reference
```