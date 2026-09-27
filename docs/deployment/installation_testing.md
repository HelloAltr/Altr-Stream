# Altr Stream — Cross-Platform Setup & Lifecycle Validation Checklist

This document defines the formal Batch 1 manual validation protocol for Altr Stream's OS-specific Setup Utility across macOS, Linux, and Windows.

| Platform | Responsible Tester | Test Environment | Date Executed | Overall Status |
| :--- | :--- | :--- | :--- | :--- |
| **macOS** | Human Tester (Primary) | Apple Silicon / Intel macOS (Darwin 24+) | Pending | ⏳ PENDING |
| **Linux** | Teammate | Ubuntu 22.04+ / Debian / Fedora / Arch | Pending | ⏳ PENDING |
| **Windows** | Teammate | Windows 10/11 x64 (PowerShell 5.1 / 7+) | Pending | ⏳ PENDING |

---

## Validation Scenarios

### Scenario A: Fresh Installation (Default Location)
- **Preconditions**:
  - Target machine has Docker & Docker Compose installed and daemon running.
  - No existing container named `altr-stream` or volume named `altr_stream_data`.
  - Default installation directory (`~/.altr-stream` on macOS/Linux, `%USERPROFILE%\.altr-stream` on Windows) does not exist.
- **Steps**:
  1. Launch installer:
     - **macOS**: Double-click `Altr-Stream_macOS_Installer.command` in Finder (or run `./Altr-Stream_macOS_Installer.command`).
     - **Linux**: Execute `./Altr-Stream_Linux_Installer.sh` in terminal.
     - **Windows**: Right-click `Altr-Stream_Windows_Installer.ps1` -> *Run with PowerShell* (or `powershell -ExecutionPolicy Bypass -File .\Altr-Stream_Windows_Installer.ps1`).
  2. In the interactive TUI menu, select `Install Altr Stream` (Option 1).
  3. Accept the default installation directory.
  4. Allow the installer to prepare runtime files, pull the pinned `ghcr.io/helloaltr/altr-stream:0.13.7-alpha` image, and start the container.
- **Expected Result**:
  - Menu navigation works cleanly with arrow keys and Enter (or numeric shortcuts).
  - All prerequisite checkmarks appear green: Docker installed, Docker daemon running, Docker Compose available.
  - Image downloads successfully with progress output.
  - Container starts in detached mode; health check polls `http://localhost:8000/api/v1/health` and succeeds within 30 seconds.
  - System browser opens automatically to `http://localhost:8000`.
  - Summary banner displays access URLs and the installation path.
- **Pass / Fail**: [ ] Pass &nbsp;&nbsp;&nbsp;&nbsp; [ ] Fail
- **Notes**:

---

### Scenario B: Missing Docker Prerequisites
- **Preconditions**:
  - Machine has Docker CLI uninstalled, removed from `PATH`, or Docker Desktop uninstalled.
- **Steps**:
  1. Launch the Setup Utility.
  2. Select `Install Altr Stream`.
- **Expected Result**:
  - Utility does NOT fail silently or attempt silent root/system modifications.
  - Displays clear error: `✗ Docker was not found in PATH`.
  - Presents guided prerequisite prompt:
    - On macOS: Guides user to download Docker Desktop for Mac (`https://www.docker.com/products/docker-desktop/`) and prompts to open URL.
    - On Windows: Guides user to Docker Desktop for Windows with WSL2 backend.
    - On Linux: Displays standard package manager instructions (`apt-get install docker-ce docker-compose-plugin`).
  - Does NOT proceed with installation until Docker and Docker Compose are present.
- **Pass / Fail**: [ ] Pass &nbsp;&nbsp;&nbsp;&nbsp; [ ] Fail
- **Notes**:

---

### Scenario C: Docker Daemon Stopped
- **Preconditions**:
  - Docker is installed, but Docker Desktop is quit or `dockerd` service is stopped (`systemctl stop docker`).
- **Steps**:
  1. Launch the Setup Utility.
  2. Select `Install Altr Stream`.
- **Expected Result**:
  - Docker binary detected (`✓ Docker is installed`).
  - Docker daemon check reports error: `✗ Cannot communicate with the Docker daemon`.
  - On macOS/Windows: Offers to launch Docker Desktop application automatically and waits with a progress countdown.
  - On Linux: Explains how to start the service (`sudo systemctl start docker`).
  - Gracefully returns to menu or allows retry once daemon is active without crashing.
- **Pass / Fail**: [ ] Pass &nbsp;&nbsp;&nbsp;&nbsp; [ ] Fail
- **Notes**:

---

### Scenario D: Custom Installation Path Selection
- **Preconditions**:
  - Clean target machine or uninstalled Altr Stream.
  - An alternate destination path designated (e.g., `/opt/my-altr` or `~/custom-altr` or `D:\AltrStream`).
- **Steps**:
  1. Launch Setup Utility -> Select `Install Altr Stream`.
  2. When prompted for Installation Directory, select `[2] Specify a custom directory`.
  3. Enter custom directory path.
  4. Complete installation.
- **Expected Result**:
  - Custom directory is created with proper user permissions.
  - `docker-compose.yml` and `.env` are written inside the custom path.
  - Custom location is persisted in `~/.altr-stream-config` (or `%USERPROFILE%\.altr-stream-config`).
  - Container starts successfully and health check passes.
  - Subsequent invocations of Status, Repair, and Uninstall detect this custom directory automatically.
- **Pass / Fail**: [ ] Pass &nbsp;&nbsp;&nbsp;&nbsp; [ ] Fail
- **Notes**:

---

### Scenario E: Idempotent Re-Run / Upgrade Over Existing
- **Preconditions**:
  - Altr Stream is already installed and healthy.
  - User has customized `.env` (e.g., modified `ALTR_STREAM_PORT=8000` or added custom env variables).
- **Steps**:
  1. Launch Setup Utility -> Select `Install Altr Stream`.
  2. Confirm target directory.
- **Expected Result**:
  - Setup utility detects existing configuration.
  - Existing `.env` customizations are PRESERVED (not overwritten).
  - `docker-compose.yml` is updated if necessary.
  - Container is safely restarted (`docker compose up -d`).
  - Application remains operational without data corruption.
- **Pass / Fail**: [ ] Pass &nbsp;&nbsp;&nbsp;&nbsp; [ ] Fail
- **Notes**:

---

### Scenario F: Installation Status Inspection
- **Preconditions**:
  - Altr Stream is installed (either running or stopped).
- **Steps**:
  1. Launch Setup Utility.
  2. Select `Installation Status` (Option 4).
- **Expected Result**:
  - Terminal displays a structured overview:
    - Configured / Image Version (`0.13.7-alpha`)
    - Installation Path
    - Docker daemon state (`Running`)
    - Container status (`Running` or `Stopped`)
    - Health endpoint state (`Healthy` or `Unhealthy/Unreachable`)
    - Named Volume state (`Present`)
    - Host supervisor integration status
  - Returns cleanly to the main menu on key press.
- **Pass / Fail**: [ ] Pass &nbsp;&nbsp;&nbsp;&nbsp; [ ] Fail
- **Notes**:

---

### Scenario G: Repair Workflow
- **Preconditions**:
  - Altr Stream installation is damaged in one of the following ways:
    - `docker-compose.yml` was deleted.
    - Container was stopped or removed (`docker rm -f altr-stream`).
- **Steps**:
  1. Launch Setup Utility.
  2. Select `Repair Installation` (Option 3).
  3. Review diagnostic findings.
  4. Confirm `[1] Proceed with Repair`.
- **Expected Result**:
  - Diagnostic scan accurately highlights missing elements (`✗ docker-compose.yml missing`, `⚠ Container not running`).
  - Repair restores `docker-compose.yml` and updates directory structure.
  - Recreates container using `docker compose up -d --force-recreate`.
  - Preserves persistent database and data sources on `altr_stream_data` volume.
  - Health check verifies service returns to `healthy`.
- **Pass / Fail**: [ ] Pass &nbsp;&nbsp;&nbsp;&nbsp; [ ] Fail
- **Notes**:

---

### Scenario H: Uninstall with Application Data Preserved (Default)
- **Preconditions**:
  - Altr Stream is running with sample sources or configuration saved.
- **Steps**:
  1. Launch Setup Utility -> Select `Uninstall Altr Stream` (Option 2).
  2. When asked *"What should happen to your application data?"*, choose `[1] Keep application data (Recommended)`.
- **Expected Result**:
  - Container `altr-stream` is stopped and removed (`docker compose down`).
  - Deployment configuration (`docker-compose.yml`, `.env`, update IPC folder) is removed.
  - Named Docker volume `altr_stream_data` is strictly PRESERVED (`docker volume ls | grep altr_stream_data` still exists).
  - No unrelated Docker containers, images, or volumes are touched.
  - Clear message reports: `Application data PRESERVED in volume: altr_stream_data`.
- **Pass / Fail**: [ ] Pass &nbsp;&nbsp;&nbsp;&nbsp; [ ] Fail
- **Notes**:

---

### Scenario I: Reinstall Using Preserved Data
- **Preconditions**:
  - Altr Stream was uninstalled under Scenario H with `altr_stream_data` preserved.
- **Steps**:
  1. Launch Setup Utility -> Select `Install Altr Stream`.
  2. Proceed with installation.
  3. Open `http://localhost:8000` in browser.
- **Expected Result**:
  - New container is created and mounts the existing `altr_stream_data` volume.
  - All previously registered sources, schemas, and credentials remain intact.
  - Health check passes immediately.
- **Pass / Fail**: [ ] Pass &nbsp;&nbsp;&nbsp;&nbsp; [ ] Fail
- **Notes**:

---

### Scenario J: Destructive Uninstall (Data Deletion)
- **Preconditions**:
  - Altr Stream is installed.
- **Steps**:
  1. Launch Setup Utility -> Select `Uninstall Altr Stream`.
  2. Select `[2] Delete application data permanently`.
  3. Observe prompt warning: `⚠ DESTRUCTIVE ACTION WARNING`.
  4. Intentionally enter incorrect string (e.g. `yes` or `DELETE`) -> Verify abortion.
  5. Repeat and enter exact confirmation string: `DELETE ALTR STREAM DATA`.
- **Expected Result**:
  - Entering invalid text aborts data deletion and keeps the volume intact.
  - Entering exact `DELETE ALTR STREAM DATA` deletes the `altr_stream_data` Docker volume.
  - Removes deployment directory files and saved configuration pointer.
  - Clearly reports complete removal.
- **Pass / Fail**: [ ] Pass &nbsp;&nbsp;&nbsp;&nbsp; [ ] Fail
- **Notes**:

---

### Scenario K: Application Health & Single-Container Port 8000
- **Preconditions**:
  - Altr Stream container running.
- **Steps**:
  1. In terminal, run: `curl -s http://localhost:8000/api/v1/health | jq`
  2. In browser, navigate to `http://localhost:8000`.
  3. Verify port 3000 is NOT used or required.
- **Expected Result**:
  - `/api/v1/health` returns HTTP 200 with JSON payload:
    - `"status": "healthy"`
    - `"version": "0.13.7-alpha"`
  - Browser loads Flutter Web Admin UI directly on port 8000.
  - Navigation between Sources, Query, and Settings works without 404s.
- **Pass / Fail**: [ ] Pass &nbsp;&nbsp;&nbsp;&nbsp; [ ] Fail
- **Notes**:

---

### Scenario L: Native OS Browser Launching
- **Preconditions**:
  - Desktop GUI session active on test machine.
- **Steps**:
  1. Run `Install Altr Stream` or `Repair Installation`.
- **Expected Result**:
  - On macOS: Invokes `open "http://localhost:8000"` to launch the default macOS browser.
  - On Linux: Invokes `xdg-open "http://localhost:8000"` when a desktop session (`$DISPLAY` or `$WAYLAND_DISPLAY`) is present; does not crash in headless/SSH environments.
  - On Windows: Invokes `Start-Process "http://localhost:8000"` to launch default Windows browser.
- **Pass / Fail**: [ ] Pass &nbsp;&nbsp;&nbsp;&nbsp; [ ] Fail
- **Notes**:

---

### Scenario M: Supervisor & Update Integration
- **Preconditions**:
  - Altr Stream running from standalone deployment directory.
- **Steps**:
  1. Inspect update IPC directory: `<install_dir>/data/updates/`
  2. Check host supervisor service:
     - macOS: `launchctl list | grep altr` or check `~/Library/LaunchAgents/io.helloaltr.altr-supervisor.plist`
     - Linux: `systemctl status altr-supervisor`
  3. Test update check API: `curl -s http://localhost:8000/api/v1/updates/check | jq`
- **Expected Result**:
  - The single unified container runs without `/var/run/docker.sock` mounted inside.
  - IPC directory `<install_dir>/data/updates` exists and is mounted read-write into container at `/app/data/updates`.
  - Supervisor service operates on host, watching for `update-request.json` via IPC.
  - Update check returns release discovery response from GitHub Releases.
- **Pass / Fail**: [ ] Pass &nbsp;&nbsp;&nbsp;&nbsp; [ ] Fail
- **Notes**:

---

### Scenario N: Failure and Recovery Behavior
- **Preconditions**:
  - Docker daemon is running, but port 8000 is intentionally blocked by another process (`nc -l 8000` or test listener).
- **Steps**:
  1. Launch Setup Utility -> Select `Install Altr Stream`.
- **Expected Result**:
  - Compose output indicates port binding conflict.
  - Health check polling times out gracefully after 30 seconds.
  - Utility does NOT hang indefinitely.
  - Displays actionable troubleshooting message:
    `✗ Health check timed out after 30s.`
    `Inspect container logs with: cd ~/.altr-stream && docker compose logs altr-stream`
  - Re-running installer after clearing the port conflict resolves successfully.
- **Pass / Fail**: [ ] Pass &nbsp;&nbsp;&nbsp;&nbsp; [ ] Fail
- **Notes**:
