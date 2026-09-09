# Altr Stream — Developer Usage & Command Reference

This document provides a concise, copy-pasteable command reference for running, developing, testing, and maintaining Altr Stream.

---

## 1. Prerequisites

- **Docker:** Engine 24.0+
- **Docker Compose:** v2.20+
- *(Optional for host-native testing)*: Python 3.12+ with `uv`, Flutter SDK 3.24+

---

## 2. Production Workflow (Port 3000)

Production mode compiles a release web bundle of the Flutter Admin application and serves it via an Nginx reverse proxy alongside the FastAPI backend and test PostgreSQL database.

### Start Production Stack
```bash
docker compose up -d --build
```

### Check Container Status
```bash
docker compose ps
```

### View Live Logs
```bash
# All services
docker compose logs -f

# Specific service
docker compose logs -f altr-stream
docker compose logs -f altr-stream-admin
```

### Stop Production Stack
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

Development mode mounts your local `frontend/altr_stream_admin/` source code directly into a Flutter development container. Changes made to Dart files on your host machine take effect without rebuilding Docker images.

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

## 4. Query Playgrounds Architecture & Usage

Altr Stream provides a clean separation between **Native Database Playgrounds** (source-scoped) and the **AltrQL Console** (global logical language tool).

### 4.1 AltrQL Console & Interactive Multi-View Execution Inspector (`/altrql`)
Accessible via the global **"AltrQL Console"** Floating Action Button (FAB) or navigation header:

1. **Language Operations & Syntax (AltrQL v0.5)**:
   - **`GET` (Logical Retrieval & Two-Valued Logic)**:
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
     - Projections with optional aliases (`id AS user_id`).
     - Rich boolean logic (`AND`, `,`, `OR`, `NOT`, `{ ... }`), ranges (`18..65`), compound bounds (`>=18 & <=65`), value sets (`{"A", "B"}`), and string pattern matchers (`STARTS`, `ENDS`, `HAS`, `NOT HAS`).
     - **Strict Two-Valued NULL Semantics**: Predicates resolve strictly to `TRUE` or `FALSE` (no SQL `UNKNOWN` in AST/IR):
       - `field = NULL` compiles to `"field" IS NULL`.
       - `field != NULL` compiles to `"field" IS NOT NULL`.
       - `field = {A, B, NULL}` compiles to `((field = $1 OR field = $2) OR field IS NULL)`.
       - `field != {A, B, NULL}` compiles to `((field NOT IN ($1, $2)) AND field IS NOT NULL)`.
       - `field != {A, B}` (without NULL) compiles to `((field NOT IN ($1, $2)) OR field IS NULL)`.
       - `field NOT HAS "sub"` evaluates to `TRUE` for `NULL` column values (`("field" NOT LIKE $1 OR "field" IS NULL)`).
     - **Precision-Aware Temporal Equality**: Comparing a date-only literal (`@YYYY-MM-DD`) against a `TIMESTAMP`/`TIMESTAMPTZ` field rewrites automatically into a half-open day range `("created_at" >= $1 AND "created_at" < $2)` covering the full calendar day `[00:00:00, 24:00:00)`.
   - **`CREATE` (Single & Batch Insertions, Explicit NULL vs Omission)**:
     - *Single-Record Syntax*:
       ```altrql
       CREATE users (
           username: "alice",
           email: "alice@example.com",
           metadata: NULL
       );
       ```
     - *Explicit NULL vs Omission*: Assigning `field: NULL` inserts an explicit `NULL` into nullable columns. Omitted columns are excluded from `INSERT`, allowing database column defaults to apply. Non-nullable fields assigned `NULL` fail validation at schema-binding time (`TypeCompatibilityError`).
     - *Grouped / Batch Syntax*:
       ```altrql
       CREATE users (
           (username: "alice", email: "alice@example.com"),
           (username: "bob", email: "bob@example.com")
       );
       ```
     - *Consecutive-Only Grouping Lowering*: Homogeneous batches merge into a single multi-row `INSERT INTO ... VALUES ($1, $2), ($3, $4) RETURNING *;`. Heterogeneous records with differing column shapes (e.g. `[A, A, B, A]`) group only across adjacent matching shapes (`[A, A]`, `[B]`, `[A]`), preserving exact logical record order and emitting a `PhysicalQueryBatch`.
     - *Atomic Batch Transaction*: `execute_batch()` runs statements sequentially inside an explicit database transaction (`async with conn.transaction():`), guaranteeing complete rollback on any error.
   - **`UPDATE` (Set-Based Mutations & NULL Support)**:
     ```altrql
     UPDATE users (
         full_name: "Alice Updated",
         metadata: NULL
     ) WHERE {
         email = "alice@example.com"
     };
     ```
     - *Mandatory WHERE*: Full-table mutations without a `WHERE` clause are rejected at parse and validation time as a language-level safety invariant.
     - *NULL Assignments*: Explicitly assigning `field: NULL` sets the column to `NULL` for nullable fields; non-nullable fields are rejected at binding time.
     - *Validation*: Duplicate assignment fields are rejected during semantic validation via `_validate_mutation_assignments()`.
     - *Lowering*: Compiles to a single `PhysicalQuery` with deterministic parameter ordering (`$1` for SET assignments before `$2` for WHERE conditions) and `RETURNING *`.
     - *Execution*: Returns all affected rows. Updating zero matching rows succeeds cleanly, returning 0 rows.
   - **`DELETE` (Constrained & Mass Mutations)**:
     - *Constrained DELETE*: `DELETE users WHERE { metadata = NULL };` (any predicate, including `= NULL` or `!= NULL`, is safely classified as `CONSTRAINED`).
     - *Mass DELETE*: `DELETE users;` (requires explicit `confirm_mass_mutation=true` in execution request, otherwise raising `MassMutationConfirmationRequiredError`).

2. **Compiler Pipeline & Multi-View Execution Inspector**:
   - **Interactive Language Parsing & Validation**:
     - Click **"Parse Query"** (`POST /api/v1/altrql/parse`) to validate syntax and inspect normalized `AltrQueryIR`.
   - **Schema Binding & Type Validation**:
     - Select any registered data source from the target source dropdown and click **"Bind Against Source"** (`POST /api/v1/altrql/bind`).
     - Inspect the strongly-typed `BoundAltrQueryIR` annotated with resolved entity metadata, column data types, and logical type categories (`NUMERIC`, `STRING`, `BOOLEAN`, `TEMPORAL`).
   - **Controlled Query Execution & Physical Lowering**:
     - Click **"Execute Query"** or press **`⌘ + Enter`** / **`Ctrl + Enter`** (`POST /api/v1/altrql/execute`).
     - **Multi-View Result Switcher**:
       - **Results:** Interactive tabular data with execution latency (`X ms`) and affected/returned row count badges.
       - **Physical Query:** Dialect-specific generated SQL (e.g. PostgreSQL `FROM "public"."users"`) and 100% parameterized placeholder chips (`$1 = ...`), supporting multi-statement batch inspection.
       - **Bound IR:** Monospace JSON view of the schema-bound AST.
       - **Canonical IR:** Monospace JSON view of the normalized language AST.
   - **Mutation Badges & Safety Scoping**:
     - Visual classification badges (`READ`, `CREATE`, `UPDATE`, `DELETE`, `BATCH`).
     - Destructive mass mutations trigger safety confirmation dialogs.
   - **Structured Error Diagnostics**:
     - Syntax violations (`AltrQueryParseError`), semantic errors (`AltrQuerySemanticError`), schema binding errors (`AltrQueryBindingError`), lowering errors (`AltrQueryLoweringError`), mass mutation gates (`MassMutationConfirmationRequiredError`), and execution failures render diagnostic callouts with `Line N · Column M` indicators and dedicated **"Copy Error"** buttons.
     - Failed executions preserve pipeline artifacts (`ir`, `bound_ir`, `physical_query`) for rapid debugging.
   - **Template Selector**:
     - One-click template insertion conforming to AltrQL v0.5 (`Simple Read`, `Range & Sets`, `String Patterns`, `NULL Predicates`, `Create Single Entity`, `Create Batch Entities`, `Update Entity`, `Constrained Delete`).

### 4.2 Source-Scoped Native Database Playground
Accessible inside any Data Source detail page (`Data Sources → Select Source → Playground` tab):
1. **Source Selection & Schema Snapshot**:
   - Selecting a source automatically loads its cached schema snapshot without redundant discovery calls.
   - Click the **"Refresh / Discover Schema"** button (`↻`) in the Schema Explorer header to trigger on-demand catalog re-introspection.
2. **Schema Tree Navigation**:
   - Filter tables and columns with the real-time search field.
   - Expand table rows to inspect column native data types, nullability indicators, and primary key badges (`🔑`).
   - Click the code icon (`</>`) on any table to insert a `SELECT * FROM <table> LIMIT 100;` query template into the editor.
   - Click any column to insert its name into the query editor at the cursor position.
3. **Query Execution**:
   - Write and edit arbitrary single-statement queries in the monospace editor.
   - Press **`⌘ + Enter`** (macOS) or **`Ctrl + Enter`** (Windows/Linux) to execute.
   - **Result-returning queries** (`SELECT`, `WITH`, `EXPLAIN`, `SHOW`) render interactive paginated data tables with column copy.
   - **Command/mutation queries** (`INSERT`, `UPDATE`, `DELETE`, `CREATE`, `DROP`, `ALTER`, `TRUNCATE`) render a **Command Outcome Panel** displaying affected rows and latency.
4. **UX Safety Guardrail**:
   - Queries beginning with `DROP`, `TRUNCATE`, `DELETE`, or `ALTER` (even with leading comments) trigger a **Destructive Operation Confirmation** modal before execution.

---

## 5. Testing & Static Analysis

### Backend Tests (Pytest)
```bash
# Using virtual environment
.venv/bin/pytest tests/ -v

# Or using uv
uv run pytest tests/ -v
```

### Flutter Widget Tests
```bash
cd frontend/altr_stream_admin
flutter test
```

### Flutter Static Analysis
```bash
cd frontend/altr_stream_admin
flutter analyze
```

---

## 6. Full Clean Reset (Destructive)

> [!WARNING]
> This command completely stops all containers, deletes all persistent SQLite and PostgreSQL Docker volumes, and resets the database state to initial seed data.

```bash
docker compose down -v --remove-orphans
```

### Optional: Clean Docker Build Cache
```bash
docker builder prune -af
```

---

## 7. Common Development Scenarios Cheat Sheet

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
| **Run Backend Tests** | `.venv/bin/pytest tests/ -v` |
| **Run Frontend Tests** | `cd frontend/altr_stream_admin && flutter test` |
| **Run Frontend Analysis** | `cd frontend/altr_stream_admin && flutter analyze` |
| **Full Reset (Drop DB Volumes)** | `docker compose down -v --remove-orphans` |
| **Update Knowledge Graph** | `graphify update .` |
