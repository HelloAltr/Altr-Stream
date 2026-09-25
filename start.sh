#!/usr/bin/env bash
# Altr Stream — Unified Local / Development Startup Script
# Starts the Altr Stream container and the background host supervisor daemon.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "=================================================="
echo " Starting Altr Stream Node & Host Supervisor"
echo "=================================================="

# 1. Start or update application container
echo "[1/3] Starting container via Docker Compose..."
docker compose up -d

# 2. Start background host supervisor daemon
echo "[2/3] Ensuring host update supervisor daemon is running..."
python3 scripts/altr_supervisor.py start

# 3. Verify health
echo "[3/3] Verifying node health..."
HEALTH_URL="http://localhost:8000/api/v1/health"
MAX_ATTEMPTS=15
ATTEMPT=0
HEALTHY=false

while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
  ATTEMPT=$((ATTEMPT + 1))
  if curl -sf "$HEALTH_URL" > /dev/null 2>&1; then
    HEALTHY=true
    break
  fi
  sleep 1
done

if [ "$HEALTHY" = true ]; then
  echo ""
  echo "✔ Altr Stream is healthy and ready!"
  echo "  - Web Admin UI:  http://localhost:8000"
  echo "  - API Docs:      http://localhost:8000/docs"
  echo "  - Health API:    http://localhost:8000/api/v1/health"
  echo "  - Supervisor:    Running as host daemon (watching ./data/updates)"
  echo ""
else
  echo ""
  echo "⚠ Warning: Health check did not respond within ${MAX_ATTEMPTS}s."
  echo "  Inspect logs with: docker compose logs altr-stream"
  echo ""
fi
