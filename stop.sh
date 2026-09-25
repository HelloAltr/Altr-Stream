#!/usr/bin/env bash
# Altr Stream — Shutdown Script
# Stops the Altr Stream container and the background host supervisor daemon.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "=================================================="
echo " Stopping Altr Stream Node & Host Supervisor"
echo "=================================================="

# 1. Stop host supervisor daemon
echo "[1/2] Stopping host update supervisor daemon..."
python3 scripts/altr_supervisor.py stop || true

# 2. Stop application container
echo "[2/2] Stopping container via Docker Compose..."
docker compose stop

echo ""
echo "✔ Altr Stream and supervisor stopped."
echo ""
