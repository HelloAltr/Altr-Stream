# Altr Stream — Production Deployment Guide

This document describes how to deploy and operate **Altr Stream** as a single, unified production container node.

---

## 1. Architecture Overview

In production, Altr Stream runs as a self-contained service container:

```
┌────────────────────────────────────────────────────────┐
│             Altr Stream Production Node                │
│                                                        │
│  FastAPI Application Server (Port 8000)                │
│  ├── /api/v1/*        → REST APIs & AltrQL Execution    │
│  ├── /docs, /redoc    → OpenAPI Documentation          │
│  └── /                → Compiled Flutter Web Admin SPA │
│                                                        │
│  Internal Storage:                                     │
│  └── /app/data/altr_stream.db (SQLite Metadata Store)  │
│                                                        │
│  Security Context:                                     │
│  └── Unprivileged User: altr (UID 10001, GID 10001)    │
│  └── No Docker socket access                           │
└────────────────────────────────────────────────────────┘
```

The unified container serves both the backend data federation engine and the Flutter Web administrative interface on a single port (**8000**), eliminating CORS issues and multi-service orchestration overhead.

---

## 2. Prerequisites

- **Docker Engine**: Version 24.0 or higher
- **Docker Compose**: Version 2.20 or higher
- **Network**: Ingress on port 8000 (or reverse-proxied via Nginx, Traefik, or Caddy)
- **Disk Storage**: At least 1 GB free space for persistent metadata and container images

---

## 3. Production Deployment via Docker Compose

### Step 1: Prepare the `docker-compose.yml` File

Ensure your deployment directory contains the production `docker-compose.yml`:

```yaml
services:
  altr-stream:
    image: ghcr.io/helloaltr/altr-stream:0.13.1-alpha
    container_name: altr-stream
    restart: unless-stopped
    ports:
      - "8000:8000"
    environment:
      - ALTR_STREAM_HOST=0.0.0.0
      - ALTR_STREAM_PORT=8000
      - ALTR_STREAM_DATABASE_URL=sqlite+aiosqlite:////app/data/altr_stream.db
      - ALTR_STREAM_STATIC_DIR=/app/static
      - ALTR_STREAM_DEBUG=false
    volumes:
      - altr_stream_data:/app/data
    healthcheck:
      test: ["CMD-SHELL", "curl -f http://localhost:8000/api/v1/health || exit 1"]
      interval: 15s
      timeout: 5s
      retries: 3
      start_period: 10s
    networks:
      - altr-network

volumes:
  altr_stream_data:
    driver: local

networks:
  altr-network:
    driver: bridge
```

### Step 2: Start the Service

```bash
# Pull and start Altr Stream in the background
docker compose up -d

# Verify container status and healthcheck
docker compose ps
```

Expected output:
```text
NAME          IMAGE                                       COMMAND                  SERVICE       CREATED         STATUS                   PORTS
altr-stream   ghcr.io/helloaltr/altr-stream:0.13.1-alpha  "uvicorn altr_stream…"   altr-stream   5 seconds ago   Up 4 seconds (healthy)   0.0.0.0:8000->8000/tcp
```

---

## 4. Alternative: Standalone Docker Run

If running without Docker Compose, launch the container using `docker run`:

```bash
# Create persistent data volume
docker volume create altr_stream_data

# Run container
docker run -d \
  --name altr-stream \
  --restart unless-stopped \
  -p 8000:8000 \
  -v altr_stream_data:/app/data \
  -e ALTR_STREAM_HOST=0.0.0.0 \
  -e ALTR_STREAM_PORT=8000 \
  -e ALTR_STREAM_DATABASE_URL=sqlite+aiosqlite:////app/data/altr_stream.db \
  -e ALTR_STREAM_DEBUG=false \
  ghcr.io/helloaltr/altr-stream:0.13.1-alpha
```

---

## 5. Ports & Networking

| Port | Description | Scope |
| :--- | :--- | :--- |
| **8000** | Unified HTTP endpoint (FastAPI REST APIs + Flutter Web UI) | Expose to clients / reverse proxy |

- Access the Admin Web UI: `http://<HOST_IP>:8000/`
- Access the Interactive API Docs (Swagger): `http://<HOST_IP>:8000/docs`
- Access OpenAPI Specification: `http://<HOST_IP>:8000/api/v1/openapi.json`
- Access Healthcheck: `http://<HOST_IP>:8000/api/v1/health`

---

## 6. Persistent Storage

Altr Stream persists its operational state, registered data sources, logical entity schemas, field mappings, and telemetry to a local SQLite database located in `/app/data`:

- Volume: `altr_stream_data`
- Mount point: `/app/data`
- Database path: `/app/data/altr_stream.db`

> [!IMPORTANT]
> Always mount a named Docker volume or host bind-mount to `/app/data`. If this directory is not mounted, all registered data sources, schemas, and mappings will be lost when the container is recreated.

To back up metadata:
```bash
docker run --rm \
  -v altr_stream_data:/data \
  -v $(pwd)/backups:/backup \
  alpine tar czf /backup/altr_stream_backup_$(date +%Y%m%d_%H%M%S).tar.gz -C /data .
```

---

## 7. Environment Variables

All settings use the `ALTR_STREAM_` prefix:

| Variable | Default Value | Description |
| :--- | :--- | :--- |
| `ALTR_STREAM_HOST` | `0.0.0.0` | Host interface to bind within container. |
| `ALTR_STREAM_PORT` | `8000` | Port to listen on. |
| `ALTR_STREAM_DATABASE_URL` | `sqlite+aiosqlite:////app/data/altr_stream.db` | SQLAlchemy connection URL for internal metadata store. |
| `ALTR_STREAM_STATIC_DIR` | `/app/static` | Directory containing compiled Flutter Web static assets. |
| `ALTR_STREAM_DEBUG` | `false` | Enable verbose debugging logs and SQL echo. Must be `false` in production. |
| `ALTR_STREAM_DEFAULT_CONNECTION_TIMEOUT_SEC` | `5.0` | Socket connection timeout in seconds for physical databases. |

---

## 8. Connecting Physical Data Sources

Altr Stream connects outbound to physical databases (PostgreSQL, MySQL, MongoDB). Ensure that:

1. **Firewall / Ingress**: Physical database ports (e.g. 5432, 3306, 27017) are reachable from the Altr Stream container host.
2. **Docker Host Connectivity**: If your database runs on the Docker host machine, configure the source host as:
   - Linux: `172.17.0.1` (or add `extra_hosts: ["host.docker.internal:host-gateway"]` to Compose).
   - macOS / Windows: `host.docker.internal`.
3. **Database Credentials**: In the Admin UI or via API, configure database credentials using minimum required privileges for metadata discovery and query execution.

---

## 9. Health & Monitoring

The container defines a native Docker `HEALTHCHECK` using curl:
```bash
curl -f http://localhost:8000/api/v1/health
```

The health check validates that the FastAPI ASGI loop and the internal SQLite database engine are fully responsive:

```json
{
  "service": "Altr Stream",
  "version": "0.13.1-alpha",
  "status": "healthy",
  "timestamp": "2026-09-24T12:45:00.000000"
}
```

---

## 10. Operations & Lifecycle Commands

### Stop Container
```bash
docker compose stop
```

### Restart Container
```bash
docker compose restart
```

### View Live Logs
```bash
docker compose logs -f altr-stream
```

### Check Running User ID (Security Audit)
```bash
docker compose exec altr-stream id
# Expected output: uid=10001(altr) gid=10001(altr) groups=10001(altr)
```

---

## 11. Troubleshooting

### Container fails healthcheck
- Run `docker compose logs altr-stream` to inspect startup traces.
- Check file permissions on the persistent volume: `/app/data` must be writable by UID 10001.

### Cannot reach physical database
- Test connectivity from within the container:
  ```bash
  docker compose exec altr-stream python3 -c "import socket; s = socket.socket(); s.settimeout(3); s.connect(('your-db-host', 5432)); print('Connected!')"
  ```
- Verify network route and security group rules allow traffic from the container host.

### Client-side SPA routing returns 404
- The unified container automatically handles client-side routing fallback to `/index.html` for any web path that is not an `/api/*` endpoint. Ensure requests to the web interface pass through standard HTTP GET methods.
