# Altr Stream

> **Physical source abstraction, multi-database query compilation, and data infrastructure service for the HelloAltr / Altr Mesh ecosystem.**

Altr Stream is a self-contained data infrastructure node that physically connects to, introspects, and federates queries across heterogeneous data sources (**PostgreSQL**, **MySQL**, **SQLite**, and **MongoDB**). It features the **AltrQL Federated Query Engine**, an integrated **Logical Model & Source Mapping Registry**, and a desktop-grade **Flutter Web Administration Console** running directly inside a unified, unprivileged container on port **8000**.

---

## ⚡ Altr Stream Setup Utility

Altr Stream includes an interactive, terminal-based **Setup Utility** across macOS, Linux, and Windows. It guides you through prerequisites, directory selection, container management, repair diagnostics, status checks, and safe uninstallation.

```text
╭──────────────────────────────────────────────╮
│              ALTR STREAM                     │
│              Setup Utility                   │
│                                              │
│   ❯ Install Altr Stream                      │
│     Uninstall Altr Stream                    │
│     Repair Installation                      │
│     Installation Status                      │
│     Exit                                     │
╰──────────────────────────────────────────────╯
```

### 1. macOS (Double-Click Setup Utility)
1. Download **`Altr-Stream_macOS_Installer.command`** from the [Latest GitHub Release](https://github.com/HelloAltr/Altr-Stream/releases/latest).
2. Double-click **`Altr-Stream_macOS_Installer.command`** in Finder (or run `./Altr-Stream_macOS_Installer.command` in Terminal).
3. Select **Install Altr Stream** (or use arrow keys and press Enter).
4. The utility checks Docker, selects or customizes the target directory (`~/.altr-stream`), starts Altr Stream, verifies health, and opens **[http://localhost:8000](http://localhost:8000)** in your browser.

### 2. Linux (Terminal Setup Utility)
1. Download **`Altr-Stream_Linux_Installer.sh`** from the [Latest GitHub Release](https://github.com/HelloAltr/Altr-Stream/releases/latest) or fetch via curl:
   ```bash
   curl -fsSL https://github.com/HelloAltr/Altr-Stream/releases/latest/download/Altr-Stream_Linux_Installer.sh -o Altr-Stream_Linux_Installer.sh
   chmod +x Altr-Stream_Linux_Installer.sh
   ./Altr-Stream_Linux_Installer.sh
   ```
2. Navigate the menu with arrow keys or enter numbers:
   - **`1` Install Altr Stream**: Verifies Docker prerequisites, prepares `~/.altr-stream`, pulls image, starts container.
   - **`2` Uninstall Altr Stream**: Clean container teardown with choice to keep or delete data.
   - **`3` Repair Installation**: Diagnoses broken configs or containers and automatically restores service.
   - **`4` Installation Status**: Displays running status, version, path, and healthcheck.

### 3. Windows (PowerShell Setup Utility)
1. Download **`Altr-Stream_Windows_Installer.ps1`** from the [Latest GitHub Release](https://github.com/HelloAltr/Altr-Stream/releases/latest).
2. Right-click and select **Run with PowerShell** (or launch from PowerShell):
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\Altr-Stream_Windows_Installer.ps1
   ```
3. Follow the interactive menu to Install, Repair, or check Status.

---

### Setup Utility Capabilities

| Action | What It Does | Data Impact |
| :--- | :--- | :--- |
| **Install** | Detects Docker engine/daemon/compose, allows default (`~/.altr-stream`) or custom path selection, prepares Compose runtime, pulls pinned image, starts container, verifies health, launches browser. | Safe: Idempotent. Re-running preserves existing `.env` and database. |
| **Uninstall** | Stops and removes container, removes installer-created configuration. Prompts to keep or delete application data. | **Safe by default**: Keeps `altr_stream_data` volume unless explicit `DELETE ALTR STREAM DATA` confirmation is entered. |
| **Repair** | Diagnoses directory, compose file, image cache, container status, and healthcheck. Restores missing configurations and recreates container. | Safe: Never touches or resets persistent data. |
| **Status** | Displays configured version, active path, Docker daemon responsiveness, container running state, and health status. | Read-only inspection. |

---

### 4. Manual Docker Deployment (Secondary / Fallback)
For headless servers, custom container orchestrators, or air-gapped environments:

1. Download **`altr-stream-v<version>-deployment.tar.gz`** from the release page.
2. Extract the archive:
   ```bash
   tar -xzf altr-stream-v*-deployment.tar.gz
   cd altr-stream-v*-deployment
   ```
3. Start Altr Stream:
   ```bash
   docker compose up -d
   ```
4. Verify health at **[http://localhost:8000/api/v1/health](http://localhost:8000/api/v1/health)**.

---

### 5. Troubleshooting & FAQ

- **Docker is required**: If Docker is not found or not running, the setup utility guides you directly to the official installation for your OS. It will never silently modify system package configuration or weaken permissions.
- **Port conflicts**: If port 8000 is occupied, edit `.env` in your installation directory (`~/.altr-stream/.env`) to set `ALTR_STREAM_PORT=8001`, then run **Repair Installation**.
- **Data safety**: Your registered database connections, schemas, and queries live in the Docker volume `altr_stream_data`. Normal updates, reinstallations, and repairs never delete this volume.
- **Container logs**:
  ```bash
  cd ~/.altr-stream
  docker compose logs -f altr-stream
  ```

---

## 🏗️ System Architecture

Altr Stream operates as a single, unified production container:

```text
                                User Browser / Client
                                          │
                                          │ HTTP (Port 8000)
                                          ▼
┌────────────────────────────────────────────────────────────────────────────────────────┐
│                        Unified Altr Stream Container (Port 8000)                       │
│                                                                                        │
│   FastAPI Web Server (Uvicorn ASGI)                                                    │
│   ├── /api/v1/*       → REST APIs & AltrQL Execution Pipeline                          │
│   ├── /docs, /redoc   → OpenAPI Interactive Documentation                              │
│   └── /*              → Compiled Flutter Web Admin SPA (/app/static)                   │
│                                                                                        │
│   In-Process Core Engine:                                                              │
│   ├── AltrQL Lexer, Parser & AST Generator                                             │
│   ├── Logical Model & Source Mapping Registry                                          │
│   ├── Dialect Lowerers (Postgres, MySQL, SQLite, MongoDB)                              │
│   ├── Asynchronous Connectors (asyncpg, aiomysql, aiosqlite, pymongo)                  │
│   └── In-Memory Federated Merger                                                       │
│                                                                                        │
│   Security Boundaries:                                                                 │
│   ├── Unprivileged User: altr (UID 10001, GID 10001)                                   │
│   └── Zero Docker Socket Access (No /var/run/docker.sock)                              │
└────────────────────────────────────────────────────────────────────────────────────────┘
                                          │ Outbound Driver Connections
                   ┌──────────────────────┼──────────────────────┐
                   ▼                      ▼                      ▼
           PostgreSQL (5432)         MySQL (3306)         MongoDB (27017)
```

For comprehensive architectural specifications and security boundaries, see the [Architecture Overview](docs/architecture/overview.md).

---

## ⚡ AltrQL Federated Query Engine

AltrQL is a declarative, database-neutral logical query and mutation language designed for federated data environments. Queries compile into parameterized native SQL or MQL pipelines executed concurrently across participating sources:

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

### Core Engine Capabilities
- **Cross-Database Semantic Parity**: Strict two-valued NULL logic, explicit NULL sort ordering (`ASC NULLS FIRST`, `DESC NULLS LAST`), pattern matchers (`STARTS`, `ENDS`, `HAS`), and precision-aware temporal ranges.
- **Dual-Path Resolution**:
  - **Path A (Registered Models)**: Executes against pre-configured Logical Models and active source mappings.
  - **Path B (Ephemeral Auto-Discovery)**: Introspects live physical catalogs at runtime for unmapped tables, dynamically synthesizing unified query projections without mutating database schemas.
- **Fault-Isolated Concurrent Execution**: Each physical source executes inside an isolated error boundary. If a source encounters a network timeout or query error, the overall federated query completes successfully, returning available rows alongside machine-readable diagnostic reason codes.

For detailed language syntax, mutations, and telemetry schemas, see the [AltrQL Specification](docs/altrql/specification.md).

---

## 🗂️ Logical Model & Source Mapping Registry

Altr Stream provides a centralized registry for abstract business entities and their physical schema bindings:
- **Logical Models**: Agnostic entity schemas with strongly-typed fields (`STRING`, `INTEGER`, `DECIMAL`, `BOOLEAN`, `TIMESTAMP`, `JSON`, `BINARY`).
- **Source Mappings**: Bindings connecting logical entities and attributes to physical tables/collections and columns/paths.
- **Validation Lifecycle**: Mappings transition through strict validation states (`DRAFT` $\rightarrow$ `VALIDATED` $\rightarrow$ `ACTIVE` $\rightarrow$ `ERROR`) with automated type-compatibility checking.

---

## 🌐 Endpoints & Management

| Service / Interface | URL / Port | Description |
| :--- | :--- | :--- |
| **Admin Web UI** | [http://localhost:8000](http://localhost:8000) | Web-based management console for sources, models, and query execution |
| **Interactive API Docs** | [http://localhost:8000/docs](http://localhost:8000/docs) | Swagger UI for exploring and testing REST API endpoints |
| **API Healthcheck** | [http://localhost:8000/api/v1/health](http://localhost:8000/api/v1/health) | Node health and engine version status |
| **AltrQL Compiler API** | `POST /api/v1/altrql/execute` | End-to-end query parsing, planning, and federated execution |

For the complete API contract, see the [REST API Reference](docs/api/reference.md).

---

## 💻 Local Development Workflow

For developers contributing to Altr Stream:

### Backend Development (FastAPI)
```bash
# Setup Python virtual environment
uv venv --python 3.12 .venv
source .venv/bin/activate
uv pip install -e ".[dev]"

# Run FastAPI backend with hot reload
uvicorn altr_stream.main:app --reload --host 0.0.0.0 --port 8000

# Run complete backend test suite (800+ tests)
pytest tests/ -v
```

### Frontend Development (Flutter Web)
```bash
cd frontend/altr_stream_admin

# Fetch dependencies
flutter pub get

# Run Flutter Web development server in Chrome
flutter run -d chrome

# Run Flutter test suite (130 tests)
flutter test

# Build production web bundle (compiled into /app/static in Dockerfile)
flutter build web --release
```

### Pre-seeded Integration Databases
```bash
# Start local PostgreSQL, MySQL, and MongoDB test databases
docker compose -f docker-compose.test-dbs.yml up -d
```

---

## 📚 Documentation Index

- [Architecture Overview](docs/architecture/overview.md)
- [AltrQL Specification](docs/altrql/specification.md)
- [Connector Authoring Guide](docs/connectors/authoring_guide.md)
- [Host Supervisor & Automated Deployment](docs/deployment/docker_supervisor.md)
- [REST API Reference](docs/api/reference.md)
- [Production Deployment Guide](DEPLOYMENT.md)
- [Operational Manual & Usage Reference](USAGE.md)