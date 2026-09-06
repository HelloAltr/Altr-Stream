# Altr Stream

> **Physical source abstraction and data infrastructure service for the HelloAltr / Altr Mesh ecosystem.**

Altr Stream is responsible for knowing *how* to physically connect to, introspect, and operate on external data sources (PostgreSQL, with MySQL and MongoDB planned). It encapsulates connection pools, catalog discovery, schema normalization, native pushdown operations, and future Change Data Capture (CDC).

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

# Run backend test suite
pytest -v
```

### Frontend (Flutter Web)
```bash
cd frontend/altr_stream_admin

# Fetch dependencies
flutter pub get

# Run Flutter Web development server with Chrome
flutter run -d chrome

# Run multi-viewport Flutter tests
flutter test

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
│       │   │   ├── query_playground/ # Schema Explorer & Native Query Playground
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
│       ├── infrastructure/      # SQLite Metadata Store & PostgreSQL Connector
│       ├── application/         # SourceService & SchemaService
│       ├── presentation/api/    # REST API Routes (/api/v1/sources, /health)
│       └── main.py              # FastAPI Application Entry
├── tests/                       # Backend Pytest Test Suite
├── docker/
│   └── postgres/init.sql        # Seed database schemas & sample tables
├── docker-compose.yml           # Multi-container orchestration
├── Dockerfile                   # Python backend container
└── pyproject.toml               # Python packaging & dependencies
```