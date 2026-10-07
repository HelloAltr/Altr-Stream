# Altr Stream — Developer Usage & Command Reference

This document provides a comprehensive, copy-pasteable command reference for running, developing, testing, querying, and maintaining Altr Stream across its multi-database ecosystem (**PostgreSQL**, **MySQL**, **SQLite**, and **MongoDB**).

---

## 1. Prerequisites

- **Docker:** Engine 24.0+
- **Docker Compose:** v2.20+
- *(Optional for host-native testing)*: Python 3.12+ with `uv`, Flutter SDK 3.24+

---

## 2. Production Stack Workflow (Port 8000)

In production, Altr Stream runs as a unified service container serving both the FastAPI REST backend and the pre-compiled Flutter Web administrative interface on a single port (**8000**).

### Start Production Container
```bash
docker compose up -d
```

### Check Container Status
```bash
docker compose ps
```

The container `altr-stream` should show `Up` / `healthy` on `0.0.0.0:8000->8000/tcp`.

### View Live Logs
```bash
docker compose logs -f altr-stream
```

### Stop Production Stack (Preserving Persistent Volumes)
```bash
docker compose down
```

---

## 3. Flutter Web Development Mode (Port 3001)

When working on Flutter UI features, development mode mounts your local `frontend/altr_stream_admin/` source code into a hot-reloading Flutter development container on Port 3001, connecting to the backend on Port 8000.

### Start Development Stack
```bash
docker compose -f docker-compose.yml -f docker-compose.dev.yml up -d
```

### Accessing the Application
- **Flutter Dev Server (Web):** [http://localhost:3001/](http://localhost:3001/)
- **FastAPI Backend & Production UI:** [http://localhost:8000/](http://localhost:8000/)
- **Swagger API Docs:** [http://localhost:8000/docs](http://localhost:8000/docs)

### Stop Development Mode
```bash
docker compose -f docker-compose.yml -f docker-compose.dev.yml down
```


---

## 4. AltrQL Language & Federated Query Engine

AltrQL provides unified, cross-database declarative querying and mutation across PostgreSQL, MySQL, SQLite, and MongoDB.

### 4.1 `GET` (Cross-DB Retrieval & Parity Semantics)

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

#### Key Capabilities & Parity Rules:
1. **Projection Aliasing**:
   - Simple aliases: `username AS user_name`
   - Nested document path aliases: `metadata.tier AS user_tier`
2. **Two-Valued NULL Logic**:
   - `field = NULL` $\rightarrow$ `field IS NULL` (SQL) / `{"field": None}` (MongoDB).
   - `field != NULL` $\rightarrow$ `field IS NOT NULL` (SQL) / `{"field": {"$ne": None}}` (MongoDB).
   - Scalar inequality `field != "val"` includes `NULL` values: `("field" != $1 OR "field" IS NULL)` in SQL, native `{"field": {"$ne": "val"}}` in MongoDB.
   - ValueSet equality `field = {"A", "B", NULL}` $\rightarrow$ `((field = $1 OR field = $2) OR field IS NULL)`.
   - ValueSet inequality `field != {"A", "B", NULL}` $\rightarrow$ `((field NOT IN ($1, $2)) AND field IS NOT NULL)`.
   - ValueSet inequality `field != {"A", "B"}` $\rightarrow$ `((field NOT IN ($1, $2)) OR field IS NULL)`.
3. **String Pattern Matching & Wildcard Escaping**:
   - `STARTS`, `ENDS`, `HAS`, `NOT HAS` support single values and ValueSets (`HAS {"a", "b"}`).
   - Special SQL wildcard characters (`%`, `_`, `\`) are safely escaped across all engines with explicit dialect escape clauses (`ESCAPE '\'` in PostgreSQL/SQLite, `ESCAPE '\\'` in MySQL, `re.escape()` in MongoDB).
   - `field NOT HAS "sub"` evaluates to `TRUE` for `NULL` fields (`("field" NOT LIKE $1 OR "field" IS NULL)`).
4. **Explicit `SORT` NULL Ordering Parity**:
   - `ASC` orders `NULL` / missing values **FIRST** across all backends.
   - `DESC` orders `NULL` / missing values **LAST** across all backends.
5. **Precision-Aware Temporal Equality**:
   - `@YYYY-MM-DD` literal comparisons against timestamp fields automatically expand into a half-open interval `[YYYY-MM-DD 00:00:00, YYYY-MM-DD+1 00:00:00)`.

### 4.2 `CREATE` (Single & Batch Insertions)

- **Single Record**:
  ```altrql
  CREATE users (
      username: "alice",
      email: "alice@example.com",
      metadata: NULL
  );
  ```
- **Batch Insertion**:
  ```altrql
  CREATE users (
      (username: "alice", email: "alice@example.com"),
      (username: "bob", email: "bob@example.com")
  );
  ```
- **Consecutive-Only Grouping**: Adjacent records with identical column shapes compile into a single multi-row `INSERT` (or MongoDB `insert_many`). Heterogeneous batches are split into minimal adjacent batches preserving logical ordering within an atomic transaction.

### 4.3 `UPDATE` (Set-Based Mutations)

```altrql
UPDATE users (
    full_name: "Alice Updated",
    metadata: NULL
) WHERE {
    email = "alice@example.com"
};
```
- **Mandatory WHERE**: Full-table updates without a `WHERE` clause are rejected at compile time.
- **NULL Assignments**: Nullable fields accept `field: NULL`. Non-nullable assignments are rejected during schema binding.

### 4.4 `DELETE` (Constrained & Mass Mutations)

- **Constrained DELETE**:
  ```altrql
  DELETE users WHERE { metadata = NULL };
  ```
- **Mass DELETE (Gated)**:
  ```altrql
  DELETE users;
  ```
  Requires passing `confirm_mass_mutation=true` in execution requests.

### 4.5 Resilient Federated Multi-Source Logical Execution

Altr Stream executes logical queries across multiple heterogeneous physical databases through the Logical Model & Source Mapping Registry (Path A) and runtime unmapped physical entity discovery (Path B).

#### 1. Path A vs Path B Execution:

- **Path A (Registered Logical Models)**:
  - Query: `GET students;`
  - Targets the registered `Student` logical model.
  - Queries all physical sources with an `ACTIVE` mapping.
  - Normalizes fields to the registered canonical logical model.

- **Path B (Ephemeral Unmapped Entity Discovery)**:
  - Query: `GET users;` (when `users` is not in the persistent logical model).
  - Inspects active physical database schemas using case-insensitive and singular/plural matching (`find_sources_with_physical_entity`).
  - Sources with matching tables/collections participate; non-matching sources are excluded with `PHYSICAL_ENTITY_NOT_FOUND`.
  - Synthesizes an in-memory `EphemeralLogicalProjection` from the common-field intersection across participating databases (excluding MongoDB `_id`).
  - Projections are ephemeral and strictly in-memory — no database records or source mappings are mutated or persisted.

#### 2. Resilient Execution & Error Isolation:

Physical query execution is isolated per source (`_execute_single_source_isolated`). If a participating source fails (e.g. `SOURCE_UNREACHABLE` or `EXECUTION_FAILED`), sibling executions continue uninterrupted, and the query returns rows from the surviving sources.

#### 3. Execution & Result Metadata Contract:

Every execution via `POST /api/v1/altrql/execute` returns machine-readable metadata in `meta`:
- `execution_mode`: `"federated"` or `"single"`
- `normalized`: `true` or `false`
- `is_ephemeral`: `true` (Path B) or `false` (Path A)
- `source_count`: Number of surviving / included sources
- `row_count`: Total rows returned across all included sources
- `duration_ms`: Total execution latency in milliseconds
- `included_sources`: Array of successful sources (`source_id`, `source_name`, `source_type`, `status`, `rows`, `execution_time_ms`)
- `excluded_sources`: Array of excluded or failed sources (`source_id`, `source_name`, `source_type`, `status`, `reason_code`, `message`)

```bash
# Example: Executing unmapped physical query via cURL
curl -X POST http://localhost:8000/api/v1/altrql/execute \
  -H "Content-Type: application/json" \
  -d '{
    "query": "GET users;",
    "normalize": true
  }'
```

---

## 5. Logical Model & Source Mapping Registry

Altr Stream provides unified business entity abstractions that map to physical database tables and collections.

### 5.1 REST API Endpoints

- **List Models**: `GET /api/v1/models`
- **Create Model**: `POST /api/v1/models`
- **Get Model Details**: `GET /api/v1/models/{model_id}`
- **List Model Mappings**: `GET /api/v1/models/{model_id}/mappings`
- **Create Source Mapping**: `POST /api/v1/models/{model_id}/mappings`
- **Validate Mapping**: `POST /api/v1/models/{model_id}/mappings/{mapping_id}/validate`

### 5.2 Mapping Lifecycle
1. **`DRAFT`**: Initial mapping created with source table/collection and field mappings.
2. **`VALIDATED`**: Schema validator verifies physical existence and data type compatibility.
3. **`ACTIVE`**: Mapping activated for runtime translation.
4. **`ERROR`**: Validation failure due to schema divergence or incompatible types.

---

## 6. Admin UI Features & Playgrounds

### 6.1 Global AltrQL Console (`/altrql`)
- Access via navigation sidebar or global FAB button.
- **Target Source**: Select explicit physical source or `Auto-Select / All Sources` for federated multi-DB queries.
- **Normalize (Logical)**: Toggle canonical logical schema translation on/off.
- **Parse Query**: Validates syntax and outputs Canonical AST (`AltrQueryIR`).
- **Bind Query**: Validates against target source schema and outputs Bound AST (`BoundAltrQueryIR`).
- **Execute Query** (`⌘ + Enter` / `Ctrl + Enter`): Lowers and executes across targeted/federated physical databases.
- **Multi-View Tabs**: Results table with execution telemetry badge, Physical Query (dialect SQL / Mongo BSON), Bound IR, Canonical IR.
- **Copy Actions**: Dedicated "Copy Response" and "Copy Error" buttons.

### 6.2 Source-Scoped Database Playground
- Access via `Data Sources → Select Source → Playground` tab.
- **Relational Sources (Postgres, MySQL, SQLite)**: Interactive SQL editor, schema explorer tree, and table templates.
- **Document Sources (MongoDB)**: Interactive Mongo Shell query interface, collection tree, and BSON result viewer.
- **Destructive Operation Safety**: Modal confirmation on `DROP`, `TRUNCATE`, `DELETE`, or `ALTER`.

---

## 7. Testing & Static Analysis

### Backend Test Suite (Pytest)
```bash
# Run all backend tests (880+ tests)
uv run pytest tests/ -v

# Run cross-database semantic parity tests only
uv run pytest tests/integration/test_cross_database_parity.py -v

# Run compiler unit tests only
uv run pytest tests/unit/ -v
```

### Flutter Widget Tests & Analysis
```bash
cd frontend/altr_stream_admin

# Run complete Flutter test suite (140+ tests)
flutter test

# Run Flutter static analysis
flutter analyze
```

---

## 8. Full Clean Reset (Destructive)

> [!WARNING]
> This command completely stops all containers, deletes all persistent SQLite, PostgreSQL, MySQL, and MongoDB Docker volumes, and resets the system to clean seed data.

```bash
docker compose down -v --remove-orphans
```

---

## 9. Developer Scenarios Cheat Sheet

| Scenario | Command |
| :--- | :--- |
| **Start Production Stack** | `docker compose up -d` |
| **Stop Stack (Preserve Data)** | `docker compose down` |
| **Start Flutter Development Mode** | `docker compose -f docker-compose.yml -f docker-compose.dev.yml up -d` |
| **Stop Development Mode** | `docker compose -f docker-compose.yml -f docker-compose.dev.yml down` |
| **Check Container Status** | `docker compose ps` |
| **View Live Tail Logs** | `docker compose logs -f altr-stream` |
| **Run Backend Tests (880+ tests)** | `uv run pytest tests/ -v` |
| **Run Parity Tests** | `uv run pytest tests/integration/test_cross_database_parity.py -v` |
| **Run Frontend Tests (140+ tests)** | `cd frontend/altr_stream_admin && flutter test` |
| **Run Frontend Analysis** | `cd frontend/altr_stream_admin && flutter analyze` |
| **Full Reset (Drop DB Volumes)** | `docker compose down -v --remove-orphans` |
| **Update Knowledge Graph** | `graphify update .` |

