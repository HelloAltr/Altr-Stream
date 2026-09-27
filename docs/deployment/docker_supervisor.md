# Host Update Supervisor & Automated Deployment

This document describes the design, deployment, and operational lifecycle of the **Altr Stream Host Update Supervisor**.

---

## 1. Supervisor Architecture

In production, Altr Stream provides automated, in-place software updates directly from the Web Admin UI without requiring manual SSH or terminal interventions.

To reconcile automated container replacement with container security, Altr Stream utilizes an out-of-process **Host Supervisor**:

```
[ Web Admin UI ]
       │ "Update Now"
       ▼
[ FastAPI Container (altr-stream) ]
  ├── Writes: /app/data/updates/update-request.json
  └── Reads:  /app/data/updates/update-status.json
       │
═══════╪═══════════════════════════════════════════════════════════
       │ Volume Bind Mount (./data/updates)
═══════╪═══════════════════════════════════════════════════════════
       │
[ Host Update Supervisor (scripts/altr_supervisor.py) ]
  ├── Running as Host Daemon (launchd or systemd)
  ├── Watches: data/updates/update-request.json
  ├── Executes: Docker CLI (`docker pull`, `docker compose up -d`)
  └── Writes: data/updates/update-status.json
```

---

## 2. Update State Machine

The update lifecycle progresses through strict, observable states:

```
  ┌────────┐
  │  IDLE  │
  └───┬────┘
      │ User clicks "Update Now" (update-request.json written)
      ▼
 ┌─────────┐
 │ STAGING │ ─── Pulls target GHCR image in background (with timeout protection)
 └────┬────┘
      │ Image pull successful
      ▼
 ┌──────────┐
 │ APPLYING │ ── Replaces container with new target image
 └────┬─────┘
      │ Container started
      ▼
 ┌───────────┐
 │ VERIFYING │ ── Polls http://localhost:8000/api/v1/health (up to 30 attempts)
 └────┬──────┘
      ├───────────────────────────────┐
      │ Health verified               │ Health check failed
      ▼                               ▼
 ┌─────────┐                    ┌──────────┐
 │ SUCCESS │                    │ ROLLBACK │ ── Reverts to previous stable container
 └─────────┘                    └──────────┘
```

1. **`idle`**: No active update workflow.
2. **`staging`**: The supervisor executes `docker pull <new_image>` on the host. If the network times out or fails, the workflow aborts safely without affecting the running container.
3. **`applying`**: The supervisor updates `docker-compose.yml` or restarts the container with the new image tag.
4. **`verifying`**: The supervisor polls `http://localhost:8000/api/v1/health` at 1-second intervals.
5. **`success`**: The new version is verified healthy. State returns to `idle`.
6. **`rollback`**: If the health check times out or fails, the supervisor immediately recreates the previous container image and marks status as `failed` with diagnostic logs.

---

## 3. Persistent Daemon Installation

### macOS (`launchd`)
To install the supervisor as a persistent background agent on macOS:
```bash
./scripts/install_supervisor.sh
```
This registers a LaunchAgent at `~/Library/LaunchAgents/com.helloaltr.altr-supervisor.plist` configured to `RunAtLoad` and `KeepAlive`.

To check supervisor status:
```bash
python3 scripts/altr_supervisor.py status
```

### Linux (`systemd`)
On Linux:
```bash
./scripts/install_supervisor.sh
```
This creates and enables `/etc/systemd/system/altr-supervisor.service`.

To inspect logs:
```bash
journalctl -u altr-supervisor -f
```

---

## 4. Manual / Development Invocation
For local development or environments where persistent system services are undesirable:
```bash
./start.sh   # Starts Docker Compose and launches supervisor daemon in background
./stop.sh    # Stops Docker Compose and halts supervisor daemon
```
