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

### 4.1 AltrQL Console & Interactive AST Inspector (`/altrql`)
Accessible via the global **"AltrQL Console"** Floating Action Button (FAB) or navigation header:
1. **Interactive Language Parsing**:
   - Write declarative AltrQL queries in the editor (e.g. `GET users WHERE { status = "ACTIVE" };`).
   - Click **"Parse Query"** or press **`⌘ + Enter`** / **`Ctrl + Enter`**.
   - Inspect the resulting strongly typed `AltrQueryIR` AST in formatted monospace JSON.
   - Click **"Copy IR"** to copy the complete AST JSON to the clipboard.
2. **Schema Binding & Type Validation**:
   - Select any registered data source from the target source dropdown.
   - Click **"Bind Against Source"** (`POST /api/v1/altrql/bind`).
   - Inspect the strongly-typed `BoundAltrQueryIR` annotated with resolved entity metadata, column data types, and logical type categories (`NUMERIC`, `STRING`, `BOOLEAN`, `TEMPORAL`).
   - Switch seamlessly between **Bound IR** and **Canonical IR** result views.
3. **Temporal Literals**:
   - AltrQL v0.1 supports both temporal keywords (`TODAY`, `NOW`) and explicit ISO date literals (`@YYYY-MM-DD`, e.g. `@2026-01-01`).
   - Quoted date strings (`"2026-01-01"`) are treated strictly as strings and rejected for `TEMPORAL` fields without implicit coercion.
4. **Structured Error Diagnostics**:
   - Syntax violations, semantic errors, or schema mismatches (e.g. `UnknownEntityError`, `UnknownFieldError`, `TypeCompatibilityError`) render diagnostic callouts with `Line N · Column M` indicators.
   - Click **"Copy Error"** to copy diagnostic information.
5. **Template Selector**:
   - One-click template insertion conforming to AltrQL v0.1 (`Simple Read`, `Range & Sets`, `Logical Conditions`, `Ranking & Pagination`).

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
