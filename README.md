# Altr Stream

> **Physical source abstraction and data infrastructure service for the HelloAltr / Altr Mesh ecosystem.**

Altr Stream is responsible for knowing *how* to physically connect to, introspect, and operate on external data sources (PostgreSQL, with MySQL and MongoDB planned). It encapsulates connection pools, catalog discovery, schema normalization, native pushdown operations, the **AltrQL logical query compiler**, and future Change Data Capture (CDC).

---

## 🏗️ System Architecture

```text
┌─────────────────────────────────────────────────────────────┐
│                      Client Browser                         │
└──────────────────────────────┬──────────────────────────────┘
                               │ HTTP / JSON
                               ▼
┌─────────────────────────────────────────────────────────────┐
│             altr-stream-admin (Port 3000)                   │
│        Flutter Web Application + Nginx Reverse Proxy        │
│        - Persistent desktop sidebar & progressive UX        │
│        - Overview, Data Sources, Activity, Settings         │
│        - Schema Explorer & Native Query Playground          │
│        - Global AltrQL Console & Multi-View Compiler View   │
│        - 4-step guided source onboarding wizard             │
│        - Serves pre-compiled static Flutter Web bundle      │
│        - Proxies /api/* to backend service                  │
└──────────────────────────────┬──────────────────────────────┘
                               │ Internal Network (/api/*)
                               ▼
┌─────────────────────────────────────────────────────────────┐
│               altr-stream-app (Port 8000)                   │
│                   FastAPI Backend Service                   │
│        - Source registration & lifecycle management         │
│        - AltrQL v0.5 Query Engine & Compiler Pipeline       │
│        - PostgreSQL connector (asyncpg)                     │
│        - Schema catalog introspection & normalizer          │
│        - SQLite metadata store (aiosqlite)                  │
└──────────────────────────────┬──────────────────────────────┘
                               │ Physical DB Driver
                               ▼
┌─────────────────────────────────────────────────────────────┐
│               postgres-test (Port 5432)                     │
│          PostgreSQL Test Database (Pre-seeded)              │
└─────────────────────────────────────────────────────────────┘
```

---

## ⚡ AltrQL Query Engine (v0.5)

AltrQL is a declarative, database-neutral logical query and mutation language designed for the Altr platform. The query engine compiles AltrQL queries through pure, isolated compiler phases into 100% parameterized dialect-specific SQL:

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
       ▼ Pure Dialect Lowering
Physical Query (`PhysicalQuery` | `PhysicalQueryBatch`)
       │
       ▼ Transactional Connector Execution
Normalized Query Result (`QueryResult`)
```

### Supported Operations & Syntax

#### 1. `GET` (Logical Retrieval & Two-Valued Logic)
```altrql
GET users (
    id,
    username,
    email
) WHERE {
    age = {18..65},
    created_at = @2026-09-06,
    status = {"ACTIVE", "PENDING", NULL},
    metadata = NULL
} TOP 10 BY created_at OFFSET 20;
```
- **Projections**: Field selections with optional aliases (`id AS user_id`).
- **Expressions**: Rich logical boolean tree (`AND`, `,`, `OR`, `NOT`, `{ ... }`).
- **Strict Two-Valued NULL Semantics**: Predicates resolve strictly to `TRUE` or `FALSE` (no SQL `UNKNOWN` in AST/IR):
  - `field = NULL` compiles to `"field" IS NULL`.
  - `field != NULL` compiles to `"field" IS NOT NULL`.
  - `field = {A, B, NULL}` compiles to `((field = $1 OR field = $2) OR field IS NULL)`.
  - `field != {A, B, NULL}` compiles to `((field NOT IN ($1, $2)) AND field IS NOT NULL)`.
  - `field != {A, B}` (without NULL) compiles to `((field NOT IN ($1, $2)) OR field IS NULL)`.
  - `field NOT HAS "sub"` evaluates to `TRUE` for `NULL` column values (`("field" NOT LIKE $1 OR "field" IS NULL)`).
- **Operators**: Equality (`=`), inequality (`!=`), range (`18..65`), compound bounds (`>=18 & <=65`), value sets (`{"A", "B"}`), and string pattern matchers (`STARTS`, `ENDS`, `HAS`, `NOT HAS`).
- **Precision-Aware Temporal Comparisons**: Comparing a date-only literal (`@YYYY-MM-DD`) against a `TIMESTAMP`/`TIMESTAMPTZ` field rewrites into a half-open day range `("created_at" >= $1 AND "created_at" < $2)` covering the entire calendar day `[00:00:00, 24:00:00)`.

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
- **Consecutive-Only Grouping**: Homogeneous records lower into a single multi-row `INSERT INTO ... VALUES ($1, $2), ($3, $4) RETURNING *;`. Heterogeneous records with differing column shapes (e.g. `[A, A, B, A]`) are grouped only across adjacent matching shapes (`[A, A]`, `[B]`, `[A]`), preserving exact logical record order and emitting a `PhysicalQueryBatch`.
- **Atomic Batch Execution**: `execute_batch()` executes statements sequentially inside an explicit transaction (`async with conn.transaction():`), ensuring complete rollback on any record failure.

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
- **Single PhysicalQuery**: UPDATE is strictly set-based and always compiles to a single `PhysicalQuery`.
- **Deterministic Parameter Ordering**: Mutation assignment parameters precede condition parameters (`$1` for SET, `$2` for WHERE).

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

## 🚀 Quick Start with Docker Compose

The complete system (Flutter Web Admin, FastAPI backend, and pre-seeded PostgreSQL test instance) can be launched using Docker Compose.

### 1. Build and Run Full Stack
```bash
docker compose up --build
```

### 2. Run in Background
```bash
docker compose up -d --build
```

### 3. Stop Services (Preserving Metadata & Data Volumes)
```bash
docker compose down
```

### 4. Complete Reset (Wipes Volumes & Test Databases)
```bash
docker compose down -v
```

---

## 🌐 Access Points

| Service | Access URL | Description |
| :--- | :--- | :--- |
| **Flutter Admin UI** | [http://localhost:3000](http://localhost:3000) | Desktop-first infrastructure management app for sources, schemas & telemetry |
| **Backend REST API** | [http://localhost:8000](http://localhost:8000) | Core data infrastructure REST API |
| **AltrQL Compiler & Execution APIs** | `POST /api/v1/altrql/parse`<br>`POST /api/v1/altrql/bind`<br>`POST /api/v1/altrql/execute` | End-to-end query parsing, semantic validation, schema binding, physical SQL lowering & controlled execution |
| **Interactive API Docs** | [http://localhost:8000/docs](http://localhost:8000/docs) | Swagger UI for exploring and testing API endpoints |
| **API Health Check** | [http://localhost:8000/api/v1/health](http://localhost:8000/api/v1/health) | Service health and version status |
| **PostgreSQL Test DB** | `localhost:5432` (`altr_test_db`) | User: `altr_test_user` • Password: `altr_test_pass` |

---

## 💻 Local Development Workflow

### Backend (FastAPI)
```bash
# Setup Python virtual environment
uv venv --python 3.12 .venv
source .venv/bin/activate
uv pip install -e ".[dev]"

# Run FastAPI backend with hot reload
uvicorn altr_stream.main:app --reload --host 0.0.0.0 --port 8000

# Run backend test suite (422 tests)
pytest tests/ -v
```

### Frontend (Flutter Web)
```bash
cd frontend/altr_stream_admin

# Fetch dependencies
flutter pub get

# Run Flutter Web development server with Chrome
flutter run -d chrome

# Run multi-viewport Flutter tests (25 tests)
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
│       │   │   ├── altrql_playground/ # Global AltrQL Console & Multi-View Compiler Inspector
│       │   │   ├── source_playground/ # Source-scoped Schema Explorer & Native SQL Playground
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
│       ├── domain/              # Source, Schema, Connector Contracts
│       ├── query_engine/        # AltrQL v0.5 Compiler (Parser, Semantic Validator, Binder, Lowerer)
│       │   ├── binding/         # Schema resolution & type compatibility validation
│       │   ├── classification/  # Pure deterministic mutation classification & safety scoping
│       │   ├── domain/          # Canonical AST, Bound AST, PhysicalQuery models
│       │   ├── lowering/        # Dialect lowerers (PostgreSQL multi-row & consecutive batch)
│       │   ├── parser/          # Lexer & recursive descent parser
│       │   └── semantic/        # AST invariants validator & normalizer
│       ├── infrastructure/      # SQLite Metadata Store & PostgreSQL Connector (asyncpg)
│       ├── application/         # SourceService, SchemaService, QueryService
│       ├── presentation/api/    # REST API Routes (/api/v1/sources, /altrql, /queries)
│       └── main.py              # FastAPI Application Entry
├── tests/                       # Backend Pytest Test Suite (Unit & Integration)
│   ├── unit/                    # Compiler unit tests (Parser, Validator, Binder, Lowerer)
│   └── integration/             # REST API & live database integration tests
├── docker/
│   └── postgres/init.sql        # Seed database schemas & sample tables
├── docker-compose.yml           # Multi-container production orchestration
├── docker-compose.dev.yml       # Development hot-reload override
├── Dockerfile                   # Python backend container
├── pyproject.toml               # Python packaging & dependencies
├── README.md                    # Project overview & architecture guide
└── USAGE.md                     # Operational manual & developer command reference
```