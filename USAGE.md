# Altr Stream — Developer Usage & Command Reference

This document provides a comprehensive, copy-pasteable command reference for running, developing, testing, querying, and maintaining Altr Stream across its multi-database ecosystem (**PostgreSQL**, **MySQL**, **SQLite**, and **MongoDB**).

---

## 1. Prerequisites

- **Docker:** Engine 24.0+
- **Docker Compose:** v2.20+
- *(Optional for host-native testing)*: Python 3.12+ with `uv`, Flutter SDK 3.24+

---

## 2. Production Stack Workflow (Port 3000)

Production mode compiles a release web bundle of the Flutter Admin application and serves it via an Nginx reverse proxy alongside the FastAPI backend and all three pre-seeded test databases (PostgreSQL, MySQL, MongoDB).

### Start Production Stack
```bash
docker compose up -d --build
```

### Check Container Status
```bash
docker compose ps
```

All 5 services should show `Up` / `healthy`:
- `altr-stream-app` (Port 8000)
- `altr-stream-admin` (Port 3000)
- `altr-postgres-test` (Port 5432)
- `altr-mysql-test` (Port 3306)
- `altr-mongodb-test` (Port 27017)

### View Live Logs
```bash
# All services
docker compose logs -f

# Specific service
docker compose logs -f altr-stream
docker compose logs -f altr-stream-admin
docker compose logs -f postgres-test
docker compose logs -f mysql-test
docker compose logs -f mongodb-test
```

### Stop Production Stack (Preserving Persistent Volumes)
```bash
docker compose down
```

### Rebuild Only Frontend
```bash
docker compose up -d --build altr-stream-admin
```

### Rebuild Frontend Without Cache
```bash
docker compose build --no-cache altr-stream-admin
docker compose up -d altr-stream-admin
```

---

## 3. Flutter Development Mode (Port 3001)

Development mode mounts your local `frontend/altr_stream_admin/` source code directly into a Flutter development container. Changes made to Dart files on your host machine take effect with hot reload without rebuilding Docker images.

### Start Development Stack
```bash
docker compose -f docker-compose.yml -f docker-compose.dev.yml up
```
*(Or in background)*:
```bash
docker compose -f docker-compose.yml -f docker-compose.dev.yml up -d --build
```

### Accessing the Application
- **Flutter Dev Server (Web):** [http://localhost:3001/](http://localhost:3001/)
- **FastAPI Backend:** [http://localhost:8000/](http://localhost:8000/)
- **Swagger API Docs:** [http://localhost:8000/docs](http://localhost:8000/docs)

### Reload Behavior & Iteration Workflow
1. Edit any Flutter file on your host machine (e.g., `lib/features/overview/screens/overview_screen.dart`).
2. The mounted Docker volume updates immediately inside the container.
3. If running interactively in foreground or attached via `docker attach altr-stream-admin-dev` (enabled by `stdin_open: true` and `tty: true`), press `r` in the terminal to trigger a hot reload, or `R` to trigger a hot restart.
4. Refresh your browser tab at [http://localhost:3001/](http://localhost:3001/) to see your changes immediately.

### Attaching to Development Container
If the stack was started in the background (`-d`), you can attach to the Flutter interactive terminal:
```bash
docker attach altr-stream-admin-dev
```
*(Use `Ctrl+C` or detach keys `Ctrl+P, Ctrl+Q` to detach without stopping the container)*

### Stop Development Mode
```bash
docker compose -f docker-compose.yml -f docker-compose.dev.yml down
```

### Switch Back to Production Mode
```bash
docker compose up -d
```

---

## 4. AltrQL v0.9.0-alpha Language & Federated Query Engine

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

### 4.5 Federated Multi-Source Logical Execution (v0.9.0-alpha)

Altr Stream executes logical queries across multiple heterogeneous physical databases through the Logical Model and Source Mapping Registry.

#### Auto-Select / All Sources (Federation Mode):
Targeting `Auto-Select / All Sources` evaluates the active logical model, discovers all active source mappings, lowers the logical query into dialect-specific physical queries, executes across all participating sources in parallel, normalizes columns into canonical logical fields, strips physical IDs (such as MongoDB `_id`), merges rows, and applies global logical sorting and pagination (`LIMIT`/`OFFSET`/`TOP`).

> [!IMPORTANT]
> **Auto-Select / All Sources** means **federated execution across all eligible active mappings**. It is **not** single-source selection or round-robin selection.

#### Explicit-Source Execution & Normalization Control:
- **`Normalize = OFF`**: Returns physical column names and raw engine types.
- **`Normalize = ON`**: Translates physical column names into the canonical logical entity schema.

#### Execution & Result Metadata Contract:
Every execution via `POST /api/v1/altrql/execute` returns machine-readable metadata in `meta`:
- `execution_mode`: `"federated"` or `"single"`
- `normalized`: `true` or `false`
- `source_count`: Number of participating sources
- `row_count`: Total rows returned
- `duration_ms`: Total execution latency in milliseconds
- `sources`: Array of per-source details (`source_id`, `source_name`, `source_type`, `status`, `rows`, `execution_time_ms`)

> [!NOTE]
> **Deferred to v0.10**: Partial logical-model discovery fallback (e.g. querying `GET users;` when `users` exists in physical databases but is not yet mapped to an active logical entity) is scheduled for v0.10.

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
# Run all 688 backend tests
uv run pytest tests/ -v

# Run cross-database semantic parity tests only
uv run pytest tests/integration/test_cross_db_parity.py -v

# Run compiler unit tests only
uv run pytest tests/unit/ -v
```

### Flutter Widget Tests & Analysis
```bash
cd frontend/altr_stream_admin

# Run all 86 Flutter widget & integration tests
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
| **Start Production Stack** | `docker compose up -d --build` |
| **Stop Stack (Preserve Data)** | `docker compose down` |
| **Start Flutter Development Mode** | `docker compose -f docker-compose.yml -f docker-compose.dev.yml up` |
| **Attach to Flutter Terminal (Hot Reload)** | `docker attach altr-stream-admin-dev` |
| **Stop Development Mode** | `docker compose -f docker-compose.yml -f docker-compose.dev.yml down` |
| **Rebuild Production Frontend Only** | `docker compose up -d --build altr-stream-admin` |
| **Force Rebuild Without Cache** | `docker compose build --no-cache altr-stream-admin && docker compose up -d` |
| **Check Container Status** | `docker compose ps` |
| **View Live Tail Logs** | `docker compose logs -f` |
| **Run Backend Tests (688 tests)** | `uv run pytest tests/ -v` |
| **Run Parity Tests** | `uv run pytest tests/integration/test_cross_db_parity.py -v` |
| **Run Frontend Tests (86 tests)** | `cd frontend/altr_stream_admin && flutter test` |
| **Run Frontend Analysis** | `cd frontend/altr_stream_admin && flutter analyze` |
| **Full Reset (Drop DB Volumes)** | `docker compose down -v --remove-orphans` |
| **Update Knowledge Graph** | `graphify update .` |
