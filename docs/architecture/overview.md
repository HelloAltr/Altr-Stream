# Altr Stream — System Architecture Overview

This document provides a comprehensive description of the architectural design, execution model, and security boundaries of **Altr Stream**.

---

## 1. Unified Container Model

Altr Stream runs as a self-contained, single-container service. Rather than distributing the administrative user interface and the query engine across separate containers behind a reverse proxy, Altr Stream serves both the frontend Single Page Application (SPA) and the REST API from a single process on port **8000**:

```
                              Client Browser / API Consumer
                                            │
                                            │ HTTP (Port 8000)
                                            ▼
┌────────────────────────────────────────────────────────────────────────────────────────┐
│                        Unified Altr Stream Container (Port 8000)                       │
│                                                                                        │
│   FastAPI Application Server (Uvicorn ASGI)                                            │
│   ├── /api/v1/*       → REST APIs & AltrQL Execution Pipeline                          │
│   ├── /docs, /redoc   → OpenAPI Interactive Documentation                              │
│   └── /*              → Pre-compiled Flutter Web Static Assets (/app/static)           │
│                                                                                        │
│   In-Process Core Engine:                                                              │
│   ├── AltrQL Lexer, Parser & AST Generator                                             │
│   ├── Logical Model & Source Mapping Registry                                          │
│   ├── Lowerer Registry (Postgres, MySQL, SQLite, MongoDB)                              │
│   ├── Asynchronous Connector Engine (asyncpg, aiomysql, aiosqlite, pymongo)            │
│   ├── Resilient Execution Boundary & In-Memory Merger                                  │
│   └── Update Client Service (GitHub Release Discovery & IPC Initiator)                 │
│                                                                                        │
│   Storage & IPC:                                                                       │
│   ├── /app/data/altr_stream.db (SQLite Metadata Store)                                 │
│   └── /app/data/updates (Shared IPC Volume for Host Supervisor)                        │
│                                                                                        │
│   Security Context:                                                                    │
│   ├── User: altr (UID 10001, GID 10001)                                                │
│   └── Docker Socket: NOT MOUNTED (Zero Docker access inside container)                 │
└────────────────────────────────────────────────────────────────────────────────────────┘
                                            │ Outbound DB Drivers
                   ┌────────────────────────┼────────────────────────┐
                   ▼                        ▼                        ▼
           PostgreSQL (5432)           MySQL (3306)           MongoDB (27017)
```

### Key Architectural Properties
1. **Elimination of Multi-Container Overhead**: No Nginx container, no inter-container networking for the UI, and no cross-origin resource sharing (CORS) complexity in production.
2. **Deterministic SPA Routing**: Requests to `/api/*` are handled by FastAPI route handlers. All other non-API routes serve `index.html` from `/app/static`, enabling Flutter client-side routing across `/overview`, `/sources`, `/models`, `/altrql`, and `/settings`.
3. **Single Process Lifecycle**: The container lifecycle is managed by standard Docker restart policies (`restart: unless-stopped`).

---

## 2. Security & Update Boundary

Altr Stream implements strict privilege separation between application execution and host container management:

```
┌────────────────────────────────────────────────────────┐
│            Host Machine (User Space / Daemon)          │
│                                                        │
│  Host Update Supervisor (scripts/altr_supervisor.py)   │
│  - Runs as host daemon (launchd on macOS / systemd)    │
│  - Has access to Docker CLI (`docker pull`, etc.)      │
│  - Polls: data/updates/update-request.json             │
│  - Writes: data/updates/update-status.json             │
└───────────────────────────┬────────────────────────────┘
                            │ File IPC via Volume Mount
                            ▼ (./data/updates -> /app/data/updates)
┌────────────────────────────────────────────────────────┐
│             Altr Stream Unprivileged Container         │
│                                                        │
│  - UID 10001 / GID 10001 (Non-root user: altr)         │
│  - Read/Write access ONLY to /app/data                 │
│  - NO access to /var/run/docker.sock                   │
│  - Writes update requests to /app/data/updates         │
└────────────────────────────────────────────────────────┘
```

- **Zero Docker Socket Exposure**: The Docker socket (`/var/run/docker.sock`) is never mounted into the container. An attacker compromising the application cannot manage containers or escalate privileges to the host.
- **Rootless Container Execution**: The application process executes as `altr` (UID 10001, GID 10001).
- **Asymmetric IPC**: When an administrator triggers an update via the Web UI (`POST /api/v1/updates/apply`), the application writes an `update-request.json` file to the shared updates directory. The external host supervisor detects the request, verifies the target image signature/tag, pulls the image, recreates the container, runs health checks, and rolls back if the new container fails.

---

## 3. Core Engine: Single-Engine Federation

Altr Stream preserves the **Hard Truth** architecture: all query parsing, semantic validation, schema binding, dialect lowering, connector execution, and federated merging take place **in-process** within the Altr Stream container.

There is no external federation service or distributed coordinator:

1. **AltrQL Parsing**: Textual queries are converted into an Abstract Syntax Tree (`AltrQueryIR`).
2. **Logical Planning**: The `QueryPlanner` determines which sources participate (via pre-registered Logical Model mappings or ephemeral physical catalog discovery).
3. **Dialect Lowering**: Pure lowerers (`PostgresLowerer`, `MySqlLowerer`, `SqliteLowerer`, `MongoDbLowerer`) transform logical AST nodes into physical parametrized queries.
4. **Resilient Parallel Execution**: The query dispatcher executes queries against physical connectors concurrently using `asyncio.gather`. Each source executes inside an error boundary; if one source fails, surviving sources continue and return partial results with deterministic exclusion reasons.
5. **Canonical Merging**: Results are converted to uniform logical records and joined in-memory using hash-join and Cartesian product algorithms, followed by global sorting and pagination.
