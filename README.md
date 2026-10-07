# Altr Stream

> **Physical source abstraction, multi-database query compilation, and data infrastructure service for the HelloAltr / Altr Mesh ecosystem.**

Altr Stream is a self-contained data infrastructure node that physically connects to, introspects, and federates queries across heterogeneous data sources (**PostgreSQL**, **MySQL**, **SQLite**, and **MongoDB**). It features the **AltrQL Federated Query Engine**, an integrated **Logical Model & Source Mapping Registry**, and a desktop-grade **Flutter Web Administration Console** running directly inside a unified, unprivileged container on port **8000**.

---

## What Problem It Solves

Modern applications often span disparate databases—relational tables in PostgreSQL/MySQL, local stores in SQLite, and dynamic JSON documents in MongoDB. Querying across them typically requires bespoke ETL pipelines, disparate database drivers, and complex join logic.

**Altr Stream solves this by providing:**
- A **single connection endpoint** and unified declarative query language (**AltrQL**).
- **Physical source abstraction** with automated schema introspection.
- **Logical data modeling and source mapping** to normalize disparate schemas into unified business entities.
- **Fault-isolated concurrent query execution** where surviving sources return valid data even if one source encounters network latency or errors.
- **Zero-privileged container runtime** with built-in web management console, in-place updates, and feedback submission.

---

## High-Level Architecture

Altr Stream operates as a single, unprivileged container on port `8000`:

```text
User / Browser / Application
              │
              │ HTTP (Port 8000)
              ▼
┌────────────────────────────────────────────────────────────────────────┐
│               Unified Altr Stream Node (Port 8000)                     │
│                                                                        │
│   FastAPI Web Server (Uvicorn ASGI)                                    │
│   ├── /api/v1/*       → REST APIs & AltrQL Execution Pipeline          │
│   ├── /docs, /redoc   → Interactive OpenAPI Documentation              │
│   └── /*              → Compiled Flutter Web Admin SPA                 │
│                                                                        │
│   In-Process Core Engine:                                              │
│   ├── AltrQL Lexer, Parser & AST Generator                             │
│   ├── Logical Model & Source Mapping Registry                          │
│   ├── Dialect Lowerers (PostgreSQL, MySQL, SQLite, MongoDB)            │
│   ├── Async Connectors (asyncpg, aiomysql, aiosqlite, pymongo)         │
│   └── In-Memory Federated Merger                                       │
│                                                                        │
│   Security Boundaries:                                                 │
│   ├── Unprivileged User: altr (UID 10001, GID 10001)                   │
│   └── Zero Docker Socket Access (No /var/run/docker.sock)              │
└────────────────────────────────────────────────────────────────────────┘
              │ Outbound Driver Connections
      ┌───────┼───────────────┬───────────────┐
      ▼       ▼               ▼               ▼
 PostgreSQL  MySQL          SQLite         MongoDB
   (5432)   (3306)      (Local File)       (27017)
```

<details>
<summary>Architecture Details</summary>

### In-Process Pipeline
1. **API Layer (`/api/v1/*`)**: Dispatches health, source configuration, schema registry, and query requests.
2. **Lexer, Parser & AST**: Transforms declarative AltrQL text into an abstract syntax tree (`AltrQueryIR`).
3. **Binding & Planning**:
   - **Path A (Registered Models)**: Resolves query against persistent Logical Models and active source mappings.
   - **Path B (Ephemeral Auto-Discovery)**: Introspects live physical database catalogs for unmapped tables, synthesizing in-memory projections without persisting changes.
4. **Dialect Lowerers**: Compiles the Bound AST into parameterized native SQL (PostgreSQL, MySQL, SQLite) or MQL pipelines (MongoDB).
5. **Concurrent Execution & Merger**: Executes physical queries asynchronously across target sources inside isolated error boundaries, merging records into normalized result sets.

### Out-of-Process Host Supervisor
Container updates are applied by a lightweight host daemon (`scripts/altr_supervisor.py`) communicating via an isolated filesystem mount (`./data/updates`). The application container never has access to the Docker socket (`/var/run/docker.sock`). For full architecture specs, see [Architecture Overview](docs/architecture/overview.md).

</details>

---

## Core Capabilities

- **Unified Declarative Language (AltrQL)**: Query and mutate relational and document databases using consistent syntax with strict two-valued NULL semantics and pattern matchers.
- **Physical Connectors**: Native async drivers for PostgreSQL, MySQL, SQLite, and MongoDB with credentials encrypted at rest.
- **Logical Model Registry**: Define business entity schemas with strongly typed fields and map them to physical tables/collections.
- **Resilient Multi-Source Federation**: Concurrent query execution with fault isolation—individual source failures do not crash federated requests.

<details>
<summary>AltrQL Details</summary>

### Query Syntax Overview
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

### Key Semantics
- **Two-Valued NULL Logic**: Predictable NULL handling across all SQL dialects and MongoDB (`field = NULL`, `field != NULL`).
- **Pattern Matchers**: `STARTS`, `ENDS`, and `HAS` compile to optimal native patterns (`LIKE` or regex) with automatic wildcard escaping.
- **Mutations**: Parameterized `CREATE`, `UPDATE`, and `DELETE` with safety guards against accidental mass modification.

For detailed grammar and examples, see the [AltrQL Specification](docs/altrql/specification.md).

</details>

<details>
<summary>Connector Details</summary>

| Database | Driver | Introspection Capabilities | Connection Type |
| :--- | :--- | :--- | :--- |
| **PostgreSQL** | `asyncpg` | Schemas, tables, columns, primary keys, foreign keys | TCP / Network |
| **MySQL** | `aiomysql` | Tables, columns, keys, data types | TCP / Network |
| **SQLite** | `aiosqlite` | Tables, columns, indexes, foreign keys | Local File |
| **MongoDB** | `pymongo` | Collections, sample document schemas, field inference | TCP / Network / Replica |

All connection credentials are encrypted at rest using AES-256-GCM. For instructions on authoring new connectors, see the [Connector Authoring Guide](docs/connectors/authoring_guide.md).

</details>

<details>
<summary>Federation Details</summary>

Altr Stream supports two distinct execution paths:
1. **Path A (Registered Logical Models)**: Queries execute against defined logical entities and translate to physical schemas via validated `ACTIVE` mappings.
2. **Path B (Ephemeral Auto-Discovery)**: Ad-hoc queries for unmapped entities dynamically introspect active sources, find common schema intersections, and execute without persisting metadata.

### Fault Isolation & Metadata
Every execution response includes structured telemetry:
```json
{
  "execution_mode": "federated",
  "normalized": true,
  "source_count": 2,
  "row_count": 45,
  "duration_ms": 12.4,
  "included_sources": [ ... ],
  "excluded_sources": [ ... ]
}
```

</details>

---

## Quick Start

### Option 1: Interactive Setup Utility (Recommended)

Altr Stream includes an interactive setup utility for macOS, Linux, and Windows:

- **macOS**: Download and double-click **`Altr-Stream_macOS_Installer.command`** from the [Latest Release](https://github.com/HelloAltr/Altr-Stream/releases/latest).
- **Linux**: Download and run **`Altr-Stream_Linux_Installer.sh`**:
  ```bash
  curl -fsSL https://github.com/HelloAltr/Altr-Stream/releases/latest/download/Altr-Stream_Linux_Installer.sh -o Altr-Stream_Linux_Installer.sh
  chmod +x Altr-Stream_Linux_Installer.sh
  ./Altr-Stream_Linux_Installer.sh
  ```
- **Windows**: Download and double-click **`Altr-Stream_Windows_Installer.bat`** from the [Latest Release](https://github.com/HelloAltr/Altr-Stream/releases/latest).

The utility guides you through Docker verification, installation directory selection (`~/.altr-stream`), container startup, health verification, and browser launch at **[http://localhost:8000](http://localhost:8000)**.

### Option 2: Docker Compose (Manual / Headless)

```bash
# 1. Start the container
docker compose up -d

# 2. Access the Web Admin UI
open http://localhost:8000

# 3. Stop the container (persisting data volume)
docker compose down
```

<details>
<summary>Distribution & Installer Details</summary>

### Setup Utility Menu
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
│                                              │
╰──────────────────────────────────────────────╯
```

| Action | What It Does | Data Safety |
| :--- | :--- | :--- |
| **Install** | Verifies Docker prerequisites, prepares directory (`~/.altr-stream`), pulls pinned image, starts container, verifies health, launches browser. | Safe: Preserves existing `.env` and database. |
| **Uninstall** | Stops container, cleans configuration. Prompts whether to keep or delete data volume. | Safe by default: Keeps `altr_stream_data` volume unless explicit deletion is confirmed. |
| **Repair** | Diagnoses directory, compose file, image cache, and container health. Restores configuration without touching data. | Safe: Never resets data. |
| **Status** | Displays running status, version, path, and health status. | Read-only inspection. |

For detailed installer validation and manual test protocols, see [Setup & Lifecycle Validation](docs/deployment/installation_testing.md).

</details>

---

## Configuration

Altr Stream is configured via environment variables in `.env` (or via Docker Compose):

| Variable | Default | Description |
| :--- | :--- | :--- |
| `ALTR_STREAM_PORT` | `8000` | Host port mapped to the web admin UI and REST API |
| `ALTR_STREAM_HOST` | `0.0.0.0` | Container bind address |
| `ALTR_STREAM_DATABASE_URL` | `sqlite+aiosqlite:////app/data/altr_stream.db` | Path to persistent metadata SQLite database |
| `ALTR_STREAM_DEBUG` | `false` | Enable verbose debugging logs |
| `ALTR_STREAM_ENCRYPTION_KEY` | *(Generated)* | Key for encrypting stored database passwords at rest |
| `ALTR_STREAM_FEEDBACK_SERVICE_URL` | `https://altr-feedback.onrender.com` | Upstream Altr Feedback routing service |
| `ALTR_FEEDBACK_API_KEY` | *(None)* | Optional API key for internal/priority feedback mode |

<details>
<summary>Configuration Details</summary>

### Local Environment Setup
Copy the example configuration to create your local `.env`:
```bash
cp .env.example .env
```
Public Beta installations operate completely out-of-the-box with zero secret configuration. For deployment best practices, see the [Production Deployment Guide](DEPLOYMENT.md).

</details>

---

## In-App Feedback

Public Beta users can submit feedback directly from the Web Admin UI:
- **Zero Configuration**: No API keys or tokens are required for Public Beta users.
- **Privacy-Preserving**: System diagnostics are strictly opt-in and sanitized before dispatch (stripping passwords, URLs, and secrets).
- **Stateless Dispatch**: Feedback is routed through the external Altr Feedback service into GitHub Issues (`Flutter → Altr Stream → Altr Feedback → GitHub`). Altr Stream stores no telemetry in SQLite and contains no GitHub tokens.

---

## Updates & Releases

Altr Stream includes an automated in-place update subsystem:
- **Check for Updates**: Check GitHub Releases directly from the UI (*Brand Beacon $\rightarrow$ Version Info*).
- **One-Click Update**: Triggers the host supervisor to pull the new container image, verify health, and automatically roll back if the health check fails.
- **Packaging Releases**: Maintainers can bundle distribution packages using `python3 scripts/package_release.py`.

For operational supervisor documentation, see [Host Update Supervisor](docs/deployment/docker_supervisor.md).

---

## Development & Testing

### Quick Development Commands
```bash
# Backend tests (880+ tests)
uv run pytest tests/ -v

# Frontend tests & analyzer (140+ tests)
cd frontend/altr_stream_admin
flutter analyze
flutter test
```

<details>
<summary>Development & Testing Details</summary>

### Local Backend Setup (FastAPI)
```bash
# Setup Python virtual environment
uv venv --python 3.12 .venv
source .venv/bin/activate
uv pip install -e ".[dev]"

# Run FastAPI backend with hot reload
uvicorn altr_stream.main:app --reload --host 0.0.0.0 --port 8000
```

### Local Frontend Setup (Flutter Web)
```bash
cd frontend/altr_stream_admin

# Fetch dependencies
flutter pub get

# Run Flutter Web development server in Chrome
flutter run -d chrome

# Build production web bundle (compiled into /app/static in Dockerfile)
flutter build web --release
```

### Pre-seeded Integration Databases
```bash
# Start local PostgreSQL, MySQL, and MongoDB test databases
docker compose -f docker-compose.test-dbs.yml up -d
```

### Update Knowledge Graph
```bash
graphify update .
```

For complete developer command scenarios and workflows, see the [Developer Usage Guide](USAGE.md).

</details>

---

## Documentation Index

- [Architecture Overview](docs/architecture/overview.md) — System boundaries, components, and security
- [AltrQL Specification](docs/altrql/specification.md) — Complete query and mutation language grammar
- [Connector Authoring Guide](docs/connectors/authoring_guide.md) — Developing and testing physical connectors
- [Host Update Supervisor](docs/deployment/docker_supervisor.md) — Automated deployment and update lifecycle
- [REST API Reference](docs/api/reference.md) — OpenAPI endpoint reference and response schemas
- [Production Deployment Guide](DEPLOYMENT.md) — Containerized deployment and security hardening
- [Developer Usage Guide](USAGE.md) — Command reference, workflows, and developer scenarios
- [Setup & Lifecycle Validation](docs/deployment/installation_testing.md) — Cross-platform installer test protocol
endencies
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