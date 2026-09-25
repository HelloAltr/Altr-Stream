#!/usr/bin/env bash
# Altr Stream — Supervisor Host Service Installer
# Installs and enables the Altr Stream Update Supervisor as a persistent system daemon.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OS="$(uname -s)"
UID_NUM="$(id -u)"

echo "=================================================="
echo " Altr Stream Supervisor Service Installer"
echo " Detected OS: $OS"
echo " Installation Root: $ROOT_DIR"
echo " Current UID: $UID_NUM"
echo "=================================================="

if [ -x "$ROOT_DIR/.venv/bin/python3" ]; then
    PYTHON_BIN="$ROOT_DIR/.venv/bin/python3"
elif [ -x "$ROOT_DIR/.venv/bin/python" ]; then
    PYTHON_BIN="$ROOT_DIR/.venv/bin/python"
elif command -v uv >/dev/null 2>&1; then
    PYTHON_BIN="$(uv run which python3 2>/dev/null || which python3)"
else
    PYTHON_BIN="$(which python3)"
fi

DOCKER_BIN_DIR="$(dirname "$(which docker 2>/dev/null || echo '/usr/local/bin/docker')")"
HOST_PATH="$ROOT_DIR/.venv/bin:$DOCKER_BIN_DIR:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

if [ "$OS" = "Linux" ]; then
    SERVICE_FILE="/etc/systemd/system/altr-supervisor.service"
    echo "Installing systemd service unit to $SERVICE_FILE..."
    
    cat <<EOF > /tmp/altr-supervisor.service
[Unit]
Description=Altr Stream Host Update Supervisor Daemon
After=network.target docker.service
Requires=docker.service

[Service]
Type=simple
User=${SUDO_USER:-$USER}
WorkingDirectory=$ROOT_DIR
Environment="PATH=$HOST_PATH"
Environment="PYTHONPATH=$ROOT_DIR/src"
ExecStart=$PYTHON_BIN scripts/altr_supervisor.py run
Restart=always
RestartSec=5
StandardOutput=append:$ROOT_DIR/data/updates/supervisor.log
StandardError=append:$ROOT_DIR/data/updates/supervisor.log

[Install]
WantedBy=multi-user.target
EOF

    sudo mv /tmp/altr-supervisor.service "$SERVICE_FILE"
    sudo systemctl daemon-reload
    sudo systemctl enable altr-supervisor
    sudo systemctl restart altr-supervisor
    echo "✔ Systemd service installed and started."
    sudo systemctl status altr-supervisor --no-pager

elif [ "$OS" = "Darwin" ]; then
    PLIST_DEST="$HOME/Library/LaunchAgents/com.helloaltr.altr-supervisor.plist"
    echo "Installing launchd agent to $PLIST_DEST..."
    mkdir -p "$HOME/Library/LaunchAgents"
    mkdir -p "$ROOT_DIR/data/updates"

    cat <<EOF > "$PLIST_DEST"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.helloaltr.altr-supervisor</string>
    <key>ProgramArguments</key>
    <array>
        <string>$PYTHON_BIN</string>
        <string>$ROOT_DIR/scripts/altr_supervisor.py</string>
        <string>run</string>
    </array>
    <key>WorkingDirectory</key>
    <string>$ROOT_DIR</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>$HOST_PATH</string>
        <key>PYTHONPATH</key>
        <string>$ROOT_DIR/src</string>
    </dict>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$ROOT_DIR/data/updates/supervisor.log</string>
    <key>StandardErrorPath</key>
    <string>$ROOT_DIR/data/updates/supervisor.log</string>
</dict>
</plist>
EOF

    # Boot out old service if loaded, then bootstrap
    launchctl bootout "gui/$UID_NUM/com.helloaltr.altr-supervisor" 2>/dev/null || true
    launchctl unload "$PLIST_DEST" 2>/dev/null || true
    sleep 0.5

    if launchctl bootstrap "gui/$UID_NUM" "$PLIST_DEST" 2>/dev/null; then
        launchctl enable "gui/$UID_NUM/com.helloaltr.altr-supervisor" 2>/dev/null || true
        launchctl kickstart -k "gui/$UID_NUM/com.helloaltr.altr-supervisor" 2>/dev/null || true
    else
        launchctl load -w "$PLIST_DEST" 2>/dev/null || true
    fi
    sleep 1

    # Verify execution
    echo "Verifying supervisor process..."
    if ps aux | grep '[a]ltr_supervisor' >/dev/null; then
        SUPERVISOR_PID=$(pgrep -f "altr_supervisor.py" | head -n 1)
        echo "✔ LaunchAgent installed and actively running (PID ${SUPERVISOR_PID})."
    else
        echo "⚠ Warning: LaunchAgent registered, but supervisor process not yet seen in ps aux."
    fi
else
    echo "Unsupported OS: $OS. Please run 'python3 scripts/altr_supervisor.py start' manually."
    exit 1
fi

echo ""
echo "Installation complete. Supervisor is now running as a persistent host daemon."
