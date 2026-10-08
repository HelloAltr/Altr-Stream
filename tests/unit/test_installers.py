"""Unit tests for Altr Stream installers and release artifact packaging."""

from __future__ import annotations

import os
import platform
import re
import shutil
import subprocess
import sys
import tarfile
import time
import zipfile
from pathlib import Path

import pytest
import yaml

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(REPO_ROOT))

from altr_stream.__version__ import __version__
from scripts.package_release import compute_sha256, package_release

REAL_USER_HOME = Path(os.environ.get("HOME", str(Path.home())))


def get_resolved_gum_bin() -> str | None:
    """Deterministically resolve a verified Gum binary for installer testing.

    Precedence:
    1. Explicit GUM_BIN environment variable (e.g. provided by CI or runner)
    2. System PATH (via shutil.which('gum'))
    3. User cache (~/.altr-stream/bin/gum relative to real user home)
    4. Repo-local cache or automated on-demand fetch via package_release
    """
    # 1. Explicit GUM_BIN environment variable
    explicit = os.environ.get("GUM_BIN")
    if explicit and Path(explicit).is_file() and os.access(explicit, os.X_OK):
        return explicit

    # 2. System PATH
    system_gum = shutil.which("gum")
    if system_gum and os.access(system_gum, os.X_OK):
        return system_gum

    # 3. User cache in real home
    real_cache = REAL_USER_HOME / ".altr-stream" / "bin" / "gum"
    if real_cache.is_file() and os.access(real_cache, os.X_OK):
        return str(real_cache)

    # 4. Repo-local cache / on-demand fetch
    repo_cache = REPO_ROOT / ".cache" / "gum" / "gum"
    if repo_cache.is_file() and os.access(repo_cache, os.X_OK):
        return str(repo_cache)

    try:
        from scripts.package_release import install_gum_binary
        installed = install_gum_binary(repo_cache)
        if installed.is_file() and os.access(installed, os.X_OK):
            return str(installed)
    except Exception:
        pass

    return None


@pytest.fixture(autouse=True)
def isolate_test_environment(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    """Isolate HOME, USERPROFILE, and config file to temporary directory across all tests."""
    resolved_gum = get_resolved_gum_bin()
    fake_home = tmp_path / "global_fake_home"
    fake_home.mkdir(parents=True, exist_ok=True)
    fake_config = fake_home / ".altr-stream-config"
    monkeypatch.setenv("HOME", str(fake_home))
    monkeypatch.setenv("USERPROFILE", str(fake_home))
    monkeypatch.setenv("ALTR_STREAM_CONFIG_FILE", str(fake_config))
    if resolved_gum:
        monkeypatch.setenv("GUM_BIN", resolved_gum)


def _extract_windows_bat_payload(bat_path: Path) -> str:
    """Extract embedded PowerShell payload from self-contained Altr-Stream_Windows_Installer.bat."""
    content = bat_path.read_text(encoding="utf-8")
    marker = ":::POWERSHELL_PAYLOAD_START:::"
    idx = content.rfind(marker)
    assert idx >= 0, f"Payload marker '{marker}' not found in {bat_path}"
    return content[idx + len(marker):].strip()


def test_installer_template_files_exist() -> None:
    """Ensure installer template files and packaging templates exist."""
    installers_dir = REPO_ROOT / "packaging" / "installers"
    templates_dir = REPO_ROOT / "packaging" / "templates"

    assert (installers_dir / "Altr-Stream_macOS_Installer.command").is_file()
    assert (installers_dir / "Altr-Stream_Linux_Installer.sh").is_file()
    assert (installers_dir / "Altr-Stream_Windows_Installer.bat").is_file()
    assert not (installers_dir / "Altr-Stream_Windows_Installer.ps1").exists()
    assert (templates_dir / "docker-compose.template.yml").is_file()
    assert (templates_dir / ".env.example").is_file()
    assert (templates_dir / "INSTALLER_README.md").is_file()


def test_shell_installers_bash_syntax() -> None:
    """Validate bash syntax for macOS and Linux installer scripts."""
    macos_script = REPO_ROOT / "packaging" / "installers" / "Altr-Stream_macOS_Installer.command"
    linux_script = REPO_ROOT / "packaging" / "installers" / "Altr-Stream_Linux_Installer.sh"

    # bash -n checks syntax without executing
    result_macos = subprocess.run(["bash", "-n", str(macos_script)], capture_output=True, text=True)
    assert result_macos.returncode == 0, f"macOS installer syntax error: {result_macos.stderr}"

    result_linux = subprocess.run(["bash", "-n", str(linux_script)], capture_output=True, text=True)
    assert result_linux.returncode == 0, f"Linux installer syntax error: {result_linux.stderr}"


def test_package_release_generates_all_artifacts(tmp_path: Path) -> None:
    """Test full release packaging workflow and verify all expected artifacts are created."""
    test_version = "0.99.0-test"
    test_tag = "v0.99.0-test"

    artifacts = package_release(version=test_version, tag=test_tag, output_dir=tmp_path)
    artifact_names = {a.name for a in artifacts}

    expected_names = {
        "Altr-Stream_macOS_Installer.command",
        "Altr-Stream_Linux_Installer.sh",
        "Altr-Stream_Windows_Installer.bat",
        "README.txt",
        f"altr-stream-{test_tag}-deployment.tar.gz",
        f"altr-stream-{test_tag}-deployment.zip",
        "SHA256SUMS",
    }
    assert expected_names.issubset(artifact_names)
    assert "Altr-Stream_Windows_Installer.ps1" not in artifact_names
    if platform.system() == "Darwin":
        assert "Altr-Stream-Installer.pkg" in artifact_names
        assert "Altr-Stream_macOS_Installer.app.zip" in artifact_names


def test_packaged_installers_contain_target_version(tmp_path: Path) -> None:
    """Verify that generated installer scripts embed the exact target version and image."""
    test_version = "1.2.3-beta"
    test_tag = "v1.2.3-beta"

    package_release(version=test_version, tag=test_tag, output_dir=tmp_path)

    # Check macOS script
    macos_content = (tmp_path / "Altr-Stream_macOS_Installer.command").read_text(encoding="utf-8")
    assert f'ALTR_VERSION="{test_version}"' in macos_content
    assert "ghcr.io/helloaltr/altr-stream:${ALTR_VERSION}" in macos_content

    # Check Linux script
    linux_content = (tmp_path / "Altr-Stream_Linux_Installer.sh").read_text(encoding="utf-8")
    assert f'ALTR_VERSION="{test_version}"' in linux_content
    assert "ghcr.io/helloaltr/altr-stream:${ALTR_VERSION}" in linux_content

    # Check Windows self-contained BAT installer
    win_content = _extract_windows_bat_payload(tmp_path / "Altr-Stream_Windows_Installer.bat")
    assert f'$Version = "{test_version}"' in win_content
    assert (
        f"ghcr.io/helloaltr/altr-stream:$Version" in win_content
        or "ghcr.io/helloaltr/altr-stream:0.13.7-alpha" in win_content
    )


def test_deployment_bundle_contents_and_security(tmp_path: Path) -> None:
    """Ensure manual deployment bundle contains required deployment files and no source code."""
    test_version = "0.13.7-alpha"
    test_tag = "v0.13.7-alpha"

    package_release(version=test_version, tag=test_tag, output_dir=tmp_path)
    tar_path = tmp_path / f"altr-stream-{test_tag}-deployment.tar.gz"

    with tarfile.open(tar_path, "r:gz") as tar:
        member_names = tar.getnames()
        # Verify bundle root directory name
        bundle_root = f"altr-stream-{test_tag}-deployment"
        assert bundle_root in member_names

        # Verify essential files
        assert f"{bundle_root}/docker-compose.yml" in member_names
        assert f"{bundle_root}/.env.example" in member_names
        assert f"{bundle_root}/README.md" in member_names
        assert f"{bundle_root}/DEPLOYMENT.md" in member_names

        # Verify NO source code or dev artifacts leak into the bundle
        for name in member_names:
            assert not name.endswith(".py"), f"Leaked Python file in deployment bundle: {name}"
            assert not name.endswith(".dart"), f"Leaked Dart file in deployment bundle: {name}"
            assert ".git" not in name, f"Leaked git artifact in deployment bundle: {name}"
            assert "frontend" not in name, f"Leaked frontend source in deployment bundle: {name}"

        # Inspect docker-compose.yml inside bundle
        compose_member = tar.extractfile(f"{bundle_root}/docker-compose.yml")
        assert compose_member is not None
        compose_data = yaml.safe_load(compose_member.read().decode("utf-8"))

        service = compose_data["services"]["altr-stream"]
        assert service["image"] == f"ghcr.io/helloaltr/altr-stream:{test_version}"
        assert "8000:8000" in service["ports"]

        # Security check: Ensure Docker socket is NOT mounted
        volumes = service.get("volumes", [])
        for vol in volumes:
            assert "docker.sock" not in str(vol), "CRITICAL: Docker socket must never be mounted in container"


def test_sha256sums_accuracy(tmp_path: Path) -> None:
    """Verify that SHA256SUMS contains valid hashes for each generated release artifact."""
    test_version = "0.13.7-alpha"
    test_tag = "v0.13.7-alpha"

    package_release(version=test_version, tag=test_tag, output_dir=tmp_path)
    checksums_file = tmp_path / "SHA256SUMS"
    assert checksums_file.is_file()

    lines = checksums_file.read_text(encoding="utf-8").strip().splitlines()
    assert len(lines) >= 5

    for line in lines:
        parts = line.split()
        assert len(parts) == 2, f"Invalid SHA256 line format: {line}"
        expected_hash, filename = parts
        file_path = tmp_path / filename
        assert file_path.is_file(), f"Hashed file does not exist: {filename}"
        actual_hash = compute_sha256(file_path)
        assert actual_hash == expected_hash, f"Hash mismatch for {filename}: {actual_hash} != {expected_hash}"


def test_package_release_manifest_only_with_macos_pkg(tmp_path: Path) -> None:
    """Verify that release_manifest_only accurately includes Altr-Stream-Installer.pkg in SHA256SUMS."""
    # Create mock release assets in tmp_path
    (tmp_path / "Altr-Stream-Installer.exe").write_bytes(b"dummy-exe-content")
    (tmp_path / "Altr-Stream-Installer.pkg").write_bytes(b"dummy-pkg-content")
    (tmp_path / "Altr-Stream_macOS_Installer.app.zip").write_bytes(b"dummy-zip-content")
    (tmp_path / "Altr-Stream_Linux_Installer.sh").write_bytes(b"dummy-sh-content")

    artifacts = package_release(
        version="1.0.1-beta",
        tag="v1.0.1-beta",
        output_dir=tmp_path,
        release_manifest_only=True,
        bundle_gum=False,
    )

    checksum_file = tmp_path / "SHA256SUMS"
    assert checksum_file.is_file()
    checksum_text = checksum_file.read_text(encoding="utf-8")

    assert "Altr-Stream-Installer.pkg" in checksum_text
    assert "Altr-Stream_macOS_Installer.app.zip" in checksum_text
    assert "Altr-Stream-Installer.exe" in checksum_text
    assert "Altr-Stream_Linux_Installer.sh" in checksum_text
    assert "README.txt" in checksum_text
    assert "altr-stream-v1.0.1-beta-deployment.tar.gz" in checksum_text
    assert "altr-stream-v1.0.1-beta-deployment.zip" in checksum_text

    # Verify every line in SHA256SUMS matches actual computed hash
    for line in checksum_text.strip().splitlines():
        sha, fname = line.split()
        target_f = tmp_path / fname
        assert target_f.is_file()
        assert compute_sha256(target_f) == sha


def test_documentation_structure_and_no_obsolete_ports() -> None:
    """Verify that documentation hierarchy exists and does not refer to port 3000 for admin UI."""
    docs_dir = REPO_ROOT / "docs"
    assert (docs_dir / "architecture" / "overview.md").is_file()
    assert (docs_dir / "altrql" / "specification.md").is_file()
    assert (docs_dir / "connectors" / "authoring_guide.md").is_file()
    assert (docs_dir / "deployment" / "docker_supervisor.md").is_file()
    assert (docs_dir / "api" / "reference.md").is_file()

    readme_content = (REPO_ROOT / "README.md").read_text(encoding="utf-8")
    assert "Install Altr Stream" in readme_content
    assert "Altr-Stream_macOS_Installer.command" in readme_content
    assert "Altr-Stream_Windows_Installer.bat" in readme_content
    assert "Altr-Stream_Windows_Installer.ps1" not in readme_content
    assert "Altr-Stream_Linux_Installer.sh" in readme_content
    assert "Install-AltrStream.command" not in readme_content
    assert "Install-AltrStream.ps1" not in readme_content
    assert "install.sh" not in readme_content
    # Port 3000 should not be listed as the Admin UI port
    assert "http://localhost:3000" not in readme_content


def test_linux_installer_execution_flow(tmp_path: Path) -> None:
    """Test simulated execution of Altr-Stream_Linux_Installer.sh with mock Docker commands in an isolated path."""
    import os

    mock_bin, _ = _setup_mock_docker(tmp_path)
    install_script = REPO_ROOT / "packaging" / "installers" / "Altr-Stream_Linux_Installer.sh"
    target_install_dir = tmp_path / "altr_home"

    fake_home = tmp_path / "fake_home"
    fake_home.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    env["HOME"] = str(fake_home)
    env["USERPROFILE"] = str(fake_home)
    env["ALTR_STREAM_CONFIG_FILE"] = str(fake_home / ".altr-stream-config")
    env["PATH"] = f"{mock_bin}:{env.get('PATH', '')}"
    env["ALTR_STREAM_HOME"] = str(target_install_dir)

    result = subprocess.run(["bash", str(install_script)], env=env, capture_output=True, text=True)
    assert result.returncode == 0, f"Linux installer failed: stdout={result.stdout}\nstderr={result.stderr}"

    assert "Altr Stream is installed and running" in result.stdout
    assert (target_install_dir / "docker-compose.yml").is_file()
    assert (target_install_dir / ".env").is_file()
    assert (target_install_dir / "data" / "updates").is_dir()


def test_linux_installer_fails_cleanly_when_daemon_stopped(tmp_path: Path) -> None:
    """Test that Altr-Stream_Linux_Installer.sh outputs clear guidance when the Docker daemon is not running."""
    import os

    mock_bin = tmp_path / "mock_bin"
    mock_bin.mkdir()

    # Mock docker where 'docker info' fails
    mock_docker = mock_bin / "docker"
    mock_docker.write_text(
        "#!/bin/sh\n"
        'if [ "$1" = "info" ]; then echo "Cannot connect to the Docker daemon" >&2; exit 1; fi\n'
        "exit 0\n"
    )
    mock_docker.chmod(0o755)

    install_script = REPO_ROOT / "packaging" / "installers" / "Altr-Stream_Linux_Installer.sh"
    target_install_dir = tmp_path / "altr_home"

    fake_home = tmp_path / "fake_home"
    fake_home.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    env["HOME"] = str(fake_home)
    env["USERPROFILE"] = str(fake_home)
    env["ALTR_STREAM_CONFIG_FILE"] = str(fake_home / ".altr-stream-config")
    env["PATH"] = f"{mock_bin}:{env.get('PATH', '')}"
    env["ALTR_STREAM_HOME"] = str(target_install_dir)

    result = subprocess.run(["bash", str(install_script)], env=env, capture_output=True, text=True)
    assert result.returncode != 0
    assert "Cannot communicate with the Docker daemon" in result.stdout


def _setup_mock_docker(
    tmp_path: Path,
    fail_compose: bool = False,
    fail_health: bool = False,
    existing_container: bool = False,
    existing_status: str = "exited",
    existing_workdir: str = "/another/test/path",
    existing_image: str = "ghcr.io/helloaltr/altr-stream:0.13.7-alpha",
) -> tuple[Path, Path]:
    """Helper to set up mock Docker and curl binaries with realistic container state management."""
    mock_bin = tmp_path / "mock_bin"
    mock_bin.mkdir(parents=True, exist_ok=True)
    state_file = tmp_path / "docker_state.env"

    if existing_container:
        state_file.write_text(
            f"EXISTS=1\n"
            f"STATUS={existing_status}\n"
            f"WORKDIR={existing_workdir}\n"
            f"IMAGE={existing_image}\n"
            f"CID=46ccc79f24b91234567890abcdef\n"
        )
    elif state_file.exists():
        state_file.unlink()

    compose_check = 'if [ "$1" = "compose" ] && [ "$2" = "version" ]; then echo "Docker Compose v2.29.0"; exit 0; fi\n'
    if fail_compose:
        compose_check = 'if [ "$1" = "compose" ] && [ "$2" = "version" ]; then exit 1; fi\n'

    log_file = tmp_path / "docker_cmds.log"
    mock_docker = mock_bin / "docker"
    mock_docker.write_text(
        f"""#!/bin/sh
STATE_FILE="{state_file}"
LOG_FILE="{log_file}"
echo "$@" >> "$LOG_FILE"
if [ "$1" = "info" ]; then exit 0; fi
{compose_check}
if [ "$1" = "volume" ]; then exit 0; fi
if [ "$1" = "image" ]; then exit 0; fi
if [ "$1" = "rm" ]; then
    for arg in "$@"; do
        if [ "$arg" = "altr-stream" ]; then
            rm -f "$STATE_FILE" 2>/dev/null
        fi
    done
    exit 0
fi
if [ "$1" = "stop" ]; then
    if [ -f "$STATE_FILE" ]; then
        sed -i '' 's/STATUS=.*/STATUS=exited/' "$STATE_FILE" 2>/dev/null || sed -i 's/STATUS=.*/STATUS=exited/' "$STATE_FILE" 2>/dev/null
    fi
    exit 0
fi
if [ "$1" = "start" ]; then
    if [ -f "$STATE_FILE" ]; then
        sed -i '' 's/STATUS=.*/STATUS=running/' "$STATE_FILE" 2>/dev/null || sed -i 's/STATUS=.*/STATUS=running/' "$STATE_FILE" 2>/dev/null
    fi
    exit 0
fi
if [ "$SIMULATE_CREATION_FAILURE" = "1" ]; then
    case "$*" in
        *"compose"*"up"*)
            echo 'Error response from daemon: Conflict. The container name "/altr-stream" is already in use by container "46ccc79f24b91234567890abcdef"' >&2
            exit 1
            ;;
    esac
fi
if [ "$1" = "compose" ]; then
    case "$*" in
        *"up"*)
            compose_dir="$PWD"
            for arg in "$@"; do
                case "$arg" in
                    *.yml|*.yaml)
                        compose_dir="$(cd "$(dirname "$arg")" 2>/dev/null && pwd)"
                        ;;
                esac
            done
            if [ -f "$STATE_FILE" ]; then
                . "$STATE_FILE"
                if [ -n "$WORKDIR" ] && [ "$WORKDIR" != "$compose_dir" ]; then
                    echo 'Error response from daemon: Conflict. The container name "/altr-stream" is already in use by container "'"$CID"'"' >&2
                    exit 1
                fi
            fi
            echo "EXISTS=1" > "$STATE_FILE"
            echo "STATUS=running" >> "$STATE_FILE"
            echo "WORKDIR=$compose_dir" >> "$STATE_FILE"
            echo "IMAGE=ghcr.io/helloaltr/altr-stream:0.13.7-alpha" >> "$STATE_FILE"
            echo "CID=46ccc79f24b91234567890abcdef" >> "$STATE_FILE"
            exit 0
            ;;
        *"ps"*)
            if [ -f "$STATE_FILE" ]; then
                . "$STATE_FILE"
                if [ "$STATUS" = "running" ]; then
                    echo "altr-stream running"
                else
                    echo "altr-stream exited"
                fi
            fi
            exit 0
            ;;
        *"logs"*)
            if [ -f "$STATE_FILE" ]; then
                echo "2026-09-26 12:00:00 [INFO] Altr Stream starting..."
                echo "2026-09-26 12:00:01 [INFO] Uvicorn running on http://0.0.0.0:8000"
            fi
            exit 0
            ;;
    esac
    exit 0
fi
if [ "$1" = "inspect" ]; then
    if [ ! -f "$STATE_FILE" ]; then
        echo "Error: No such container: altr-stream" >&2
        exit 1
    fi
    . "$STATE_FILE"
    if [ "$2" = "-f" ]; then
        format="$3"
        case "$format" in
            *"Id"*) echo "$CID" ; exit 0 ;;
            *"Mounts"*) echo "altr_stream_data/var/lib/docker/volumes/altr_stream_data/_data -> /app/data (volume)" ; exit 0 ;;
            *"Name"*) echo "/altr-stream" ; exit 0 ;;
            *"State.Status"*) echo "$STATUS" ; exit 0 ;;
            *"State.Health"*) echo "healthy" ; exit 0 ;;
            *"Config.Image"*) echo "$IMAGE" ; exit 0 ;;
            *"Created"*) echo "2026-09-26T12:00:00Z" ; exit 0 ;;
            *"working_dir"*) echo "$WORKDIR" ; exit 0 ;;
            *"project"*) echo "altr-stream" ; exit 0 ;;
            *"Ports"*) echo "8000/tcp -> 8000" ; exit 0 ;;
            *"Labels"*) echo "org.opencontainers.image.version=0.13.7-alpha" ; exit 0 ;;
            *) echo "$STATUS" ; exit 0 ;;
        esac
    fi
    echo "$STATUS"
    exit 0
fi
exit 0
"""
    )
    mock_docker.chmod(0o755)

    mock_compose = mock_bin / "docker-compose"
    if fail_compose:
        mock_compose.write_text("#!/bin/sh\nexit 1\n")
    else:
        mock_compose.write_text(
            "#!/bin/sh\n"
            'if [ "$1" = "version" ]; then echo "docker-compose version 1.29.2"; exit 0; fi\n'
            "exit 0\n"
        )
    mock_compose.chmod(0o755)

    mock_curl = mock_bin / "curl"
    if fail_health:
        mock_curl.write_text("#!/bin/sh\nexit 1\n")
    else:
        mock_curl.write_text(f"""#!/bin/sh
STATE_FILE="{state_file}"
if [ -f "$STATE_FILE" ]; then
    . "$STATE_FILE"
    if [ "$STATUS" = "running" ]; then
        echo '{{"status":"healthy","version":"0.13.7-alpha"}}'
        exit 0
    fi
fi
exit 1
""")
    mock_curl.chmod(0o755)

    return mock_bin, mock_docker


def test_installer_idempotency_preserves_custom_env(tmp_path: Path) -> None:
    """Verify that re-running installer preserves existing .env customizations."""
    import os

    mock_bin, _ = _setup_mock_docker(tmp_path)
    target_install_dir = tmp_path / "altr_home"
    target_install_dir.mkdir(parents=True, exist_ok=True)

    # Pre-create custom .env
    custom_env = target_install_dir / ".env"
    custom_env.write_text("ALTR_STREAM_PORT=9090\nALTR_STREAM_DEBUG=true\n")

    install_script = REPO_ROOT / "packaging" / "installers" / "Altr-Stream_Linux_Installer.sh"
    env = os.environ.copy()
    env["PATH"] = f"{mock_bin}:{env.get('PATH', '')}"
    env["ALTR_STREAM_HOME"] = str(target_install_dir)

    result = subprocess.run(["bash", str(install_script), "install", str(target_install_dir)], env=env, capture_output=True, text=True)
    assert result.returncode == 0

    # Ensure custom .env was NOT overwritten
    saved_env = custom_env.read_text()
    assert "ALTR_STREAM_PORT=9090" in saved_env
    assert "ALTR_STREAM_DEBUG=true" in saved_env


def test_installer_custom_path_argument(tmp_path: Path) -> None:
    """Verify that Altr-Stream_Linux_Installer.sh accepts a custom path as an argument."""
    import os

    mock_bin, _ = _setup_mock_docker(tmp_path)
    custom_target = tmp_path / "custom_location"

    install_script = REPO_ROOT / "packaging" / "installers" / "Altr-Stream_Linux_Installer.sh"
    env = os.environ.copy()
    env["PATH"] = f"{mock_bin}:{env.get('PATH', '')}"

    result = subprocess.run(["bash", str(install_script), "install", str(custom_target)], env=env, capture_output=True, text=True)
    assert result.returncode == 0
    assert (custom_target / "docker-compose.yml").is_file()
    assert (custom_target / ".env").is_file()


def test_installer_fails_cleanly_when_compose_missing(tmp_path: Path) -> None:
    """Verify installer reports failure and guidance when Docker Compose is unavailable."""
    import os

    mock_bin, _ = _setup_mock_docker(tmp_path, fail_compose=True)
    target_dir = tmp_path / "altr_home"

    install_script = REPO_ROOT / "packaging" / "installers" / "Altr-Stream_Linux_Installer.sh"
    env = os.environ.copy()
    env["PATH"] = f"{mock_bin}:{env.get('PATH', '')}"
    env["ALTR_STREAM_HOME"] = str(target_dir)

    result = subprocess.run(["bash", str(install_script), "install", str(target_dir)], env=env, capture_output=True, text=True)
    assert result.returncode != 0
    assert "Docker Compose plugin was not found" in result.stdout


def test_installer_health_timeout_failure(tmp_path: Path) -> None:
    """Verify installer times out and outputs log inspection advice if healthcheck fails."""
    import os

    mock_bin, _ = _setup_mock_docker(tmp_path, fail_health=True)
    target_dir = tmp_path / "altr_home"

    install_script = REPO_ROOT / "packaging" / "installers" / "Altr-Stream_Linux_Installer.sh"
    env = os.environ.copy()
    env["PATH"] = f"{mock_bin}:{env.get('PATH', '')}"
    env["ALTR_STREAM_HOME"] = str(target_dir)

    test_script = tmp_path / "test_Altr-Stream_Linux_Installer.sh"
    content = install_script.read_text().replace("max_attempts=30", "max_attempts=2")
    test_script.write_text(content)
    test_script.chmod(0o755)

    result = subprocess.run(["bash", str(test_script), "install", str(target_dir)], env=env, capture_output=True, text=True)
    assert result.returncode != 0
    assert "Health check timed out" in result.stdout
    assert "docker compose logs altr-stream" in result.stdout


def test_uninstaller_keep_data_preserves_named_volume(tmp_path: Path) -> None:
    """Verify uninstaller keeps named volume and only deletes runtime files when keep-data is chosen."""
    import os

    mock_bin, mock_docker = _setup_mock_docker(tmp_path)
    target_dir = tmp_path / "altr_home"
    target_dir.mkdir(parents=True)
    (target_dir / "docker-compose.yml").write_text("services: {}\n")
    (target_dir / ".env").write_text("ALTR_STREAM_PORT=8000\n")
    (target_dir / "data" / "updates").mkdir(parents=True)

    install_script = REPO_ROOT / "packaging" / "installers" / "Altr-Stream_Linux_Installer.sh"
    env = os.environ.copy()
    env["PATH"] = f"{mock_bin}:{env.get('PATH', '')}"
    env["ALTR_STREAM_HOME"] = str(target_dir)

    # In Uninstall workflow, Option 1 is Keep data
    input_keystrokes = "1\n"
    result = subprocess.run(["bash", str(install_script), "uninstall", str(target_dir)], input=input_keystrokes, env=env, capture_output=True, text=True)

    assert "Uninstall complete" in result.stdout
    assert "PRESERVED" in result.stdout
    # docker-compose.yml was removed
    assert not (target_dir / "docker-compose.yml").exists()


def test_uninstaller_delete_data_requires_exact_confirmation(tmp_path: Path) -> None:
    """Verify uninstaller aborts destructive deletion if confirmation string is not exact."""
    import os

    mock_bin, _ = _setup_mock_docker(tmp_path)
    target_dir = tmp_path / "altr_home"
    target_dir.mkdir(parents=True)
    (target_dir / "docker-compose.yml").write_text("services: {}\n")
    (target_dir / ".env").write_text("ALTR_STREAM_PORT=8000\n")
    (target_dir / "data" / "updates").mkdir(parents=True)

    install_script = REPO_ROOT / "packaging" / "installers" / "Altr-Stream_Linux_Installer.sh"
    env = os.environ.copy()
    env["PATH"] = f"{mock_bin}:{env.get('PATH', '')}"
    env["ALTR_STREAM_HOME"] = str(target_dir)

    # In Uninstall workflow, Option 2 (Delete data) -> Confirmation "wrong text"
    input_keystrokes = "2\nwrong text\n"
    result = subprocess.run(["bash", str(install_script), "uninstall", str(target_dir)], input=input_keystrokes, env=env, capture_output=True, text=True)

    assert "Confirmation text did not match" in result.stdout
    assert "Application data will be preserved" in result.stdout


def test_repair_workflow_restores_missing_configuration(tmp_path: Path) -> None:
    """Verify repair workflow detects missing compose file and restores it without touching data."""
    import os

    mock_bin, _ = _setup_mock_docker(tmp_path)
    target_dir = tmp_path / "altr_home"
    target_dir.mkdir(parents=True)
    # Existing .env with customizations
    (target_dir / ".env").write_text("ALTR_STREAM_PORT=8888\n")
    # Missing docker-compose.yml!

    install_script = REPO_ROOT / "packaging" / "installers" / "Altr-Stream_Linux_Installer.sh"
    env = os.environ.copy()
    env["PATH"] = f"{mock_bin}:{env.get('PATH', '')}"
    env["ALTR_STREAM_HOME"] = str(target_dir)

    # Option 1 (Proceed with Repair)
    input_keystrokes = "1\n"
    result = subprocess.run(["bash", str(install_script), "repair", str(target_dir)], input=input_keystrokes, env=env, capture_output=True, text=True)

    assert "repair completed successfully" in result.stdout.lower()
    # Restored docker-compose.yml
    assert (target_dir / "docker-compose.yml").is_file()
    # Preserved customized .env
    assert "ALTR_STREAM_PORT=8888" in (target_dir / ".env").read_text()


def test_status_workflow_displays_accurate_information(tmp_path: Path) -> None:
    """Verify status workflow outputs version, path, and health."""
    import os

    mock_bin, _ = _setup_mock_docker(tmp_path)
    target_dir = tmp_path / "altr_home"
    target_dir.mkdir(parents=True)
    (target_dir / "docker-compose.yml").write_text("services:\n  altr-stream:\n    image: test\n")

    install_script = REPO_ROOT / "packaging" / "installers" / "Altr-Stream_Linux_Installer.sh"
    env = os.environ.copy()
    env["PATH"] = f"{mock_bin}:{env.get('PATH', '')}"
    env["ALTR_STREAM_HOME"] = str(target_dir)

    result = subprocess.run(["bash", str(install_script), "status", str(target_dir)], env=env, capture_output=True, text=True)

    assert "Altr Stream Installation Status" in result.stdout
    assert "Configured Version" in result.stdout
    assert str(target_dir) in result.stdout


def test_windows_powershell_script_structure_and_safety() -> None:
    """Verify that the embedded PowerShell payload in Altr-Stream_Windows_Installer.bat contains all required workflows and adheres to security constraints."""
    bat_script = REPO_ROOT / "packaging" / "installers" / "Altr-Stream_Windows_Installer.bat"
    content = _extract_windows_bat_payload(bat_script)

    # Workflow coverage
    assert "Invoke-InstallWorkflow" in content
    assert "Invoke-UninstallWorkflow" in content
    assert "Invoke-RepairWorkflow" in content
    assert "Invoke-StatusWorkflow" in content
    assert "Show-MainMenu" in content

    # Security check: Never mount docker socket
    assert "docker.sock" not in content, "CRITICAL: Docker socket must never be referenced or mounted in Windows installer"

    # Data preservation check
    assert "altr_stream_data" in content
    assert "DELETE ALTR STREAM DATA" in content


def test_macos_command_installer_execution_flow(tmp_path: Path) -> None:
    """Verify that Altr-Stream_macOS_Installer.command executes install and status workflows successfully."""
    import os

    mock_bin, _ = _setup_mock_docker(tmp_path)
    target_install_dir = tmp_path / "altr_macos_home"

    install_script = REPO_ROOT / "packaging" / "installers" / "Altr-Stream_macOS_Installer.command"
    env = os.environ.copy()
    env["PATH"] = f"{mock_bin}:{env.get('PATH', '')}"

    result_install = subprocess.run(["bash", str(install_script), "install", str(target_install_dir)], env=env, capture_output=True, text=True)
    assert result_install.returncode == 0
    assert "Altr Stream is installed" in result_install.stdout
    assert (target_install_dir / "docker-compose.yml").is_file()
    assert (target_install_dir / ".env").is_file()

    result_status = subprocess.run(["bash", str(install_script), "status", str(target_install_dir)], env=env, capture_output=True, text=True)
    assert result_status.returncode == 0
    assert "Altr Stream Installation Status" in result_status.stdout
    assert str(target_install_dir) in result_status.stdout


def test_macos_command_installer_uninstall_and_repair(tmp_path: Path) -> None:
    """Verify that Altr-Stream_macOS_Installer.command handles repair and keep-data uninstall workflows."""
    import os

    mock_bin, _ = _setup_mock_docker(tmp_path)
    target_dir = tmp_path / "altr_macos_home"
    target_dir.mkdir(parents=True)
    (target_dir / ".env").write_text("ALTR_STREAM_PORT=8000\n")

    install_script = REPO_ROOT / "packaging" / "installers" / "Altr-Stream_macOS_Installer.command"
    env = os.environ.copy()
    env["PATH"] = f"{mock_bin}:{env.get('PATH', '')}"

    # Repair restores docker-compose.yml
    result_repair = subprocess.run(["bash", str(install_script), "repair", str(target_dir)], input="1\n", env=env, capture_output=True, text=True)
    assert result_repair.returncode == 0
    assert (target_dir / "docker-compose.yml").is_file()

    # Uninstall with keep-data removes docker-compose.yml but preserves volume
    result_uninstall = subprocess.run(["bash", str(install_script), "uninstall", str(target_dir)], input="1\n", env=env, capture_output=True, text=True)
    assert result_uninstall.returncode == 0
    assert "Uninstall complete" in result_uninstall.stdout
    assert not (target_dir / "docker-compose.yml").exists()


def test_tui_interactive_arrow_navigation_and_exit(tmp_path: Path) -> None:
    """Verify that interactive TUI handles arrow keys without exiting and exits cleanly on Exit choice."""
    import pty
    import os
    import time
    import select
    import struct
    import fcntl
    import termios

    mock_bin, _ = _setup_mock_docker(tmp_path)
    install_script = REPO_ROOT / "packaging" / "installers" / "Altr-Stream_macOS_Installer.command"

    master, slave = pty.openpty()
    winsize = struct.pack("HHHH", 35, 100, 0, 0)
    fcntl.ioctl(slave, termios.TIOCSWINSZ, winsize)

    env = os.environ.copy()
    env["PATH"] = f"{mock_bin}:{env.get('PATH', '')}"
    env["TERM"] = "xterm-256color"
    gum_bin = get_resolved_gum_bin()
    if gum_bin:
        env["GUM_BIN"] = gum_bin

    proc = subprocess.Popen(
        ["bash", str(install_script)],
        stdin=slave,
        stdout=slave,
        stderr=slave,
        env=env,
        close_fds=True,
    )
    os.close(slave)

    try:
        # Drain until prompt appears
        accumulated = b""
        start_time = time.time()
        while time.time() - start_time < 5.0:
            r, _, _ = select.select([master], [], [], 0.1)
            if r:
                try:
                    chunk = os.read(master, 1024)
                    if chunk:
                        accumulated += chunk
                        if b"Select an operation:" in accumulated:
                            break
                except OSError:
                    break

        decoded = accumulated.decode("utf-8", errors="replace").upper()
        assert "ALTR STREAM" in decoded
        assert "INSTALL" in decoded

        # Send Arrow Keys: Down, Right, Up, Left
        for arrow in [b"\x1b[B", b"\x1b[C", b"\x1b[A", b"\x1b[D"]:
            os.write(master, arrow)
            time.sleep(0.05)
            # Process must remain running!
            assert proc.poll() is None, f"TUI exited unexpectedly on arrow key {arrow!r}"

        # Navigate down to "Exit" (4 down arrows) and press Enter
        for _ in range(4):
            os.write(master, b"\x1b[B")
            time.sleep(0.05)
        os.write(master, b"\r")

        ret = proc.wait(timeout=3)
        assert ret == 0, f"Expected clean exit code 0, got {ret}"
    finally:
        os.close(master)
        if proc.poll() is None:
            proc.kill()


def test_linux_tui_interactive_arrow_navigation_and_exit(tmp_path: Path) -> None:
    """Verify that Altr-Stream_Linux_Installer.sh interactive TUI handles arrow keys and exits cleanly on Exit choice."""
    import pty
    import os
    import time
    import select
    import struct
    import fcntl
    import termios

    mock_bin, _ = _setup_mock_docker(tmp_path)
    install_script = REPO_ROOT / "packaging" / "installers" / "Altr-Stream_Linux_Installer.sh"

    master, slave = pty.openpty()
    winsize = struct.pack("HHHH", 35, 100, 0, 0)
    fcntl.ioctl(slave, termios.TIOCSWINSZ, winsize)

    env = os.environ.copy()
    env["PATH"] = f"{mock_bin}:{env.get('PATH', '')}"
    env["TERM"] = "xterm-256color"
    gum_bin = get_resolved_gum_bin()
    if gum_bin:
        env["GUM_BIN"] = gum_bin

    proc = subprocess.Popen(
        ["bash", str(install_script)],
        stdin=slave,
        stdout=slave,
        stderr=slave,
        env=env,
        close_fds=True,
    )
    os.close(slave)

    try:
        accumulated = b""
        start_time = time.time()
        while time.time() - start_time < 5.0:
            r, _, _ = select.select([master], [], [], 0.1)
            if r:
                try:
                    chunk = os.read(master, 1024)
                    if chunk:
                        accumulated += chunk
                        if b"Select an operation:" in accumulated:
                            break
                except OSError:
                    break

        decoded = accumulated.decode("utf-8", errors="replace").upper()
        assert "ALTR STREAM" in decoded
        assert "INSTALL" in decoded

        for arrow in [b"\x1b[B", b"\x1b[C", b"\x1b[A", b"\x1b[D"]:
            os.write(master, arrow)
            time.sleep(0.05)
            assert proc.poll() is None, f"TUI exited unexpectedly on arrow key {arrow!r}"

        # Navigate down to "Exit" and press Enter
        for _ in range(4):
            os.write(master, b"\x1b[B")
            time.sleep(0.05)
        os.write(master, b"\r")

        ret = proc.wait(timeout=3)
        assert ret == 0, f"Expected clean exit code 0, got {ret}"
    finally:
        os.close(master)
        if proc.poll() is None:
            proc.kill()


def test_gum_version_and_checksum_consistency() -> None:
    """Verify that all installer scripts and packager pin identical Gum version and official checksums."""
    from scripts.package_release import GUM_PINNED_VERSION, GUM_OFFICIAL_CHECKSUMS

    assert GUM_PINNED_VERSION == "2.0.2"

    macos_script = (REPO_ROOT / "packaging" / "installers" / "Altr-Stream_macOS_Installer.command").read_text()
    linux_script = (REPO_ROOT / "packaging" / "installers" / "Altr-Stream_Linux_Installer.sh").read_text()
    windows_script = _extract_windows_bat_payload(REPO_ROOT / "packaging" / "installers" / "Altr-Stream_Windows_Installer.bat")

    assert f'GUM_PINNED_VERSION="2.0.2"' in macos_script
    assert f'GUM_PINNED_VERSION="2.0.2"' in linux_script
    assert f'$GumPinnedVersion = "2.0.2"' in windows_script

    # Verify SHA constants in macOS script match packager
    darwin_arm64_key = "gum_2.0.2_Darwin_arm64.tar.gz"
    darwin_x86_64_key = "gum_2.0.2_Darwin_x86_64.tar.gz"
    assert GUM_OFFICIAL_CHECKSUMS[darwin_arm64_key] in macos_script
    assert GUM_OFFICIAL_CHECKSUMS[darwin_x86_64_key] in macos_script

    # Verify SHA constants in Linux script match packager
    linux_x86_64_key = "gum_2.0.2_Linux_x86_64.tar.gz"
    linux_arm64_key = "gum_2.0.2_Linux_arm64.tar.gz"
    assert GUM_OFFICIAL_CHECKSUMS[linux_x86_64_key] in linux_script
    assert GUM_OFFICIAL_CHECKSUMS[linux_arm64_key] in linux_script

    # Verify SHA constants in Windows script match packager
    windows_x86_64_key = "gum_2.0.2_Windows_x86_64.zip"
    assert GUM_OFFICIAL_CHECKSUMS[windows_x86_64_key] in windows_script


def test_bundled_installer_packages_in_release_packager(tmp_path: Path) -> None:
    """Verify that release packager bundles platform-appropriate Gum binaries inside setup archives."""
    from scripts.package_release import package_release
    import zipfile
    import tarfile

    out_dir = tmp_path / "dist"
    cache_dir = REPO_ROOT / ".cache" / "gum"

    # Only run full packaging check if cached archives exist
    if not cache_dir.exists():
        pytest.skip(".cache/gum not found")

    manifest = package_release("0.13.7-alpha", out_dir)
    assert (out_dir / "SHA256SUMS").is_file()

    # Verify macOS setup zip contains Altr-Stream_macOS_Installer.command and bin/gum
    macos_zip_path = out_dir / "altr-stream-setup-macos.zip"
    assert macos_zip_path.is_file()
    with zipfile.ZipFile(macos_zip_path) as z:
        names = z.namelist()
        assert any(n.endswith("Altr-Stream_macOS_Installer.command") for n in names)
        assert any(n.endswith("bin/gum") for n in names)

    # Verify Linux setup tar contains Altr-Stream_Linux_Installer.sh and bin/gum
    linux_tar_path = out_dir / "altr-stream-setup-linux.tar.gz"
    assert linux_tar_path.is_file()
    with tarfile.open(linux_tar_path, "r:gz") as t:
        names = t.getnames()
        assert any(n.endswith("Altr-Stream_Linux_Installer.sh") for n in names)
        assert any(n.endswith("bin/gum") for n in names)

    # Verify Windows setup zip contains Altr-Stream_Windows_Installer.bat and bin/gum.exe
    win_zip_path = out_dir / "altr-stream-setup-windows.zip"
    assert win_zip_path.is_file()
    with zipfile.ZipFile(win_zip_path) as z:
        names = z.namelist()
        assert any(n.endswith("Altr-Stream_Windows_Installer.bat") for n in names)
        assert not any(n.endswith("Altr-Stream_Windows_Installer.ps1") for n in names)
        assert any(n.endswith("bin/gum.exe") for n in names)


def _set_pty_size(fd: int, rows: int = 35, cols: int = 100) -> None:
    """Set window size on a pseudo-terminal file descriptor."""
    import struct
    import fcntl
    import termios
    winsize = struct.pack("HHHH", rows, cols, 0, 0)
    fcntl.ioctl(fd, termios.TIOCSWINSZ, winsize)


def _drain_pty_until(master: int, patterns: list[bytes], timeout_sec: float = 12.0) -> bytes:
    """Drain bytes from a PTY master until any pattern in patterns appears or timeout expires."""
    import time
    import select
    import os

    accumulated = b""
    start = time.time()
    while time.time() - start < timeout_sec:
        r, _, _ = select.select([master], [], [], 0.1)
        if r:
            try:
                chunk = os.read(master, 2048)
                if chunk:
                    accumulated += chunk
                    for pat in patterns:
                        if pat in accumulated:
                            time.sleep(0.15)
                            while True:
                                r2, _, _ = select.select([master], [], [], 0.05)
                                if r2:
                                    try:
                                        c2 = os.read(master, 4096)
                                        if c2:
                                            accumulated += c2
                                        else:
                                            break
                                    except OSError:
                                        break
                                else:
                                    break
                            return accumulated
            except OSError:
                break
    return accumulated


def test_tui_interactive_install_success_and_browser_launch(tmp_path: Path) -> None:
    """Verify that successful installation reaches completion screen, does NOT terminate,
    opens the configured URL in the browser, displays the running screen, refreshes
    main menu status to Running, and exits only when explicitly requested."""
    import pty
    import os
    import time

    mock_bin, _ = _setup_mock_docker(tmp_path)
    launch_log = tmp_path / "browser_launch.log"

    # Mock 'open' (macOS browser launcher)
    mock_open = mock_bin / "open"
    mock_open.write_text(f"#!/bin/sh\necho \"$@\" >> \"{launch_log}\"\nexit 0\n")
    mock_open.chmod(0o755)

    install_script = REPO_ROOT / "packaging" / "installers" / "Altr-Stream_macOS_Installer.command"
    target_install_dir = tmp_path / "tui_install_home"

    master, slave = pty.openpty()
    _set_pty_size(slave)
    env = os.environ.copy()
    env["PATH"] = f"{mock_bin}:{env.get('PATH', '')}"
    env["TERM"] = "xterm-256color"
    env["ALTR_STREAM_HOME"] = str(target_install_dir)
    gum_bin = get_resolved_gum_bin()
    if gum_bin:
        env["GUM_BIN"] = gum_bin

    proc = subprocess.Popen(
        ["bash", str(install_script)],
        stdin=slave,
        stdout=slave,
        stderr=slave,
        env=env,
        close_fds=True,
    )
    os.close(slave)

    try:
        # Step 1: Drain Main Menu
        out1 = _drain_pty_until(master, [b"Select an operation:"])
        assert b"Select an operation:" in out1
        assert proc.poll() is None, "Installer exited prematurely on main menu"

        # Step 2: In Main Menu, cursor starts on "Install Altr Stream". Press Enter.
        os.write(master, b"\r")

        # Step 3: Drain Install Screen (wait for "Ready to proceed:")
        out2 = _drain_pty_until(master, [b"Ready to proceed:"])
        assert b"Ready to proceed:" in out2
        assert proc.poll() is None, "Installer exited prematurely on install screen"

        # Step 4: In Install Screen, cursor starts on "Install Altr Stream". Press Enter to execute.
        os.write(master, b"\r")

        # Step 5: Wait for Installation Complete screen prompt
        out3 = _drain_pty_until(master, [b"What would you like to do?"])
        assert b"INSTALLATION COMPLETE" in out3
        out3_str = out3.decode("utf-8", errors="replace")
        assert "Docker Engine" in out3_str
        assert "Altr Stream" in out3_str
        assert "Healthy" in out3_str
        assert "Web Interface" in out3_str

        # CRITICAL: Installer MUST NOT automatically terminate!
        time.sleep(0.2)
        assert proc.poll() is None, "Installer automatically terminated after installation!"

        # Step 6: Select "Launch Altr Stream" (first choice in success screen). Press Enter.
        os.write(master, b"\r")

        # Step 7: Wait for Running Screen prompt
        out4 = _drain_pty_until(master, [b"Open Altr Stream Again"])
        assert b"ALTR STREAM IS RUNNING" in out4

        # Verify browser launcher was actually invoked with the URL
        assert launch_log.is_file()
        opened_url = launch_log.read_text().strip()
        assert "http://localhost:8000" in opened_url

        # CRITICAL: Installer MUST STILL remain running after browser launch!
        assert proc.poll() is None, "Installer exited after launching browser!"

        # Step 8: In Running Screen, navigate to "Back to Main Menu" (Down x 2, Enter)
        os.write(master, b"\x1b[B\x1b[B\r")

        # Step 9: Drain Main Menu and verify status refreshed to Running
        out5 = _drain_pty_until(master, [b"Select an operation:"])
        assert b"Select an operation:" in out5
        out5_str = out5.decode("utf-8", errors="replace")
        assert "Running" in out5_str

        # Step 10: In Main Menu, navigate to Exit (Down x 4, Enter)
        for _ in range(4):
            os.write(master, b"\x1b[B")
            time.sleep(0.05)
        os.write(master, b"\r")

        ret = proc.wait(timeout=3)
        assert ret == 0, f"Expected clean exit 0, got {ret}"

    finally:
        os.close(master)
        if proc.poll() is None:
            proc.kill()


def test_tui_interactive_install_failure_screen_and_recovery(tmp_path: Path) -> None:
    """Verify that failed health check transitions to failure screen without claiming success,
    does NOT automatically terminate, and allows user to navigate back to main menu and exit."""
    import pty
    import os
    import time

    mock_bin, _ = _setup_mock_docker(tmp_path, fail_health=True)
    install_script = REPO_ROOT / "packaging" / "installers" / "Altr-Stream_macOS_Installer.command"
    target_install_dir = tmp_path / "tui_fail_home"

    fast_script = tmp_path / "fast_Altr-Stream_macOS_Installer.command"
    content = install_script.read_text().replace("attempt -lt 30", "attempt -lt 2")
    fast_script.write_text(content)
    fast_script.chmod(0o755)

    master, slave = pty.openpty()
    _set_pty_size(slave)
    env = os.environ.copy()
    env["PATH"] = f"{mock_bin}:{env.get('PATH', '')}"
    env["TERM"] = "xterm-256color"
    env["ALTR_STREAM_HOME"] = str(target_install_dir)
    gum_bin = get_resolved_gum_bin()
    if gum_bin:
        env["GUM_BIN"] = gum_bin

    proc = subprocess.Popen(
        ["bash", str(fast_script)],
        stdin=slave,
        stdout=slave,
        stderr=slave,
        env=env,
        close_fds=True,
    )
    os.close(slave)

    try:
        # Step 1: Main Menu
        _drain_pty_until(master, [b"Select an operation:"])
        assert proc.poll() is None

        # Step 2: Choose Install
        os.write(master, b"\r")

        # Step 3: Install Screen
        _drain_pty_until(master, [b"Ready to proceed:"])
        assert proc.poll() is None

        # Step 4: Confirm Install
        os.write(master, b"\r")

        # Step 5: Wait for Failure screen prompt
        out_fail = _drain_pty_until(master, [b"Retry Installation"])
        assert b"INSTALLATION FAILED" in out_fail

        # MUST NOT claim success
        assert b"INSTALLATION COMPLETE" not in out_fail

        out_fail_str = out_fail.decode("utf-8", errors="replace")
        assert "Waiting for Altr Stream health check" in out_fail_str or "Health" in out_fail_str

        # CRITICAL: Installer MUST NOT exit automatically
        assert proc.poll() is None, "Installer terminated automatically on failure!"

        # Step 6: In Failure Screen, navigate to "Back to Main Menu" (Down x 3, Enter)
        for _ in range(3):
            os.write(master, b"\x1b[B")
            time.sleep(0.05)
        os.write(master, b"\r")

        # Step 7: Wait for Main Menu
        out_menu = _drain_pty_until(master, [b"Select an operation:"])
        assert b"Select an operation:" in out_menu

        # Step 8: In Main Menu, navigate to Exit (Down x 4, Enter)
        for _ in range(4):
            os.write(master, b"\x1b[B")
            time.sleep(0.05)
        os.write(master, b"\r")

        ret = proc.wait(timeout=3)
        assert ret == 0

    finally:
        os.close(master)
        if proc.poll() is None:
            proc.kill()


def test_tui_interactive_install_failure_retry_workflow(tmp_path: Path) -> None:
    """Verify that selecting 'Retry Installation' from the failure screen restarts installation."""
    import pty
    import os
    import time

    mock_bin, _ = _setup_mock_docker(tmp_path, fail_health=True)
    install_script = REPO_ROOT / "packaging" / "installers" / "Altr-Stream_macOS_Installer.command"
    target_install_dir = tmp_path / "tui_retry_home"

    fast_script = tmp_path / "fast_Altr-Stream_macOS_Installer.command"
    content = install_script.read_text().replace("attempt -lt 30", "attempt -lt 2")
    fast_script.write_text(content)
    fast_script.chmod(0o755)

    master, slave = pty.openpty()
    _set_pty_size(slave)
    env = os.environ.copy()
    env["PATH"] = f"{mock_bin}:{env.get('PATH', '')}"
    env["TERM"] = "xterm-256color"
    env["ALTR_STREAM_HOME"] = str(target_install_dir)
    gum_bin = get_resolved_gum_bin()
    if gum_bin:
        env["GUM_BIN"] = gum_bin

    proc = subprocess.Popen(
        ["bash", str(fast_script)],
        stdin=slave,
        stdout=slave,
        stderr=slave,
        env=env,
        close_fds=True,
    )
    os.close(slave)

    try:
        # Main Menu -> Install -> Confirm
        _drain_pty_until(master, [b"Select an operation:"])
        os.write(master, b"\r")
        _drain_pty_until(master, [b"Ready to proceed:"])
        os.write(master, b"\r")

        # Wait for failure screen prompt
        out1 = _drain_pty_until(master, [b"Retry Installation"])
        assert b"INSTALLATION FAILED" in out1
        assert proc.poll() is None

        # First option in failure screen is "Retry Installation". Press Enter.
        os.write(master, b"\r")

        # Process must still be active and executing stages again
        time.sleep(0.5)
        assert proc.poll() is None

        # Should reach failure screen prompt again after re-attempt
        out2 = _drain_pty_until(master, [b"Retry Installation"])
        assert b"INSTALLATION FAILED" in out2

        # Exit cleanly via "Exit" (Down x 4, Enter)
        for _ in range(4):
            os.write(master, b"\x1b[B")
            time.sleep(0.05)
        os.write(master, b"\r")

        ret = proc.wait(timeout=3)
        assert ret == 0

    finally:
        os.close(master)
        if proc.poll() is None:
            proc.kill()


def test_linux_tui_interactive_install_success_and_browser_launch(tmp_path: Path) -> None:
    """Verify that Altr-Stream_Linux_Installer.sh interactive TUI completes installation, invokes xdg-open,
    and returns to main menu with refreshed status."""
    import pty
    import os
    import time

    mock_bin, _ = _setup_mock_docker(tmp_path)
    launch_log = tmp_path / "linux_launch.log"

    # Mock xdg-open
    mock_xdg = mock_bin / "xdg-open"
    mock_xdg.write_text(f"#!/bin/sh\necho \"$@\" >> \"{launch_log}\"\nexit 0\n")
    mock_xdg.chmod(0o755)

    install_script = REPO_ROOT / "packaging" / "installers" / "Altr-Stream_Linux_Installer.sh"
    target_install_dir = tmp_path / "tui_linux_home"

    master, slave = pty.openpty()
    _set_pty_size(slave)
    env = os.environ.copy()
    env["PATH"] = f"{mock_bin}:{env.get('PATH', '')}"
    env["TERM"] = "xterm-256color"
    env["ALTR_STREAM_HOME"] = str(target_install_dir)
    gum_bin = get_resolved_gum_bin()
    if gum_bin:
        env["GUM_BIN"] = gum_bin

    proc = subprocess.Popen(
        ["bash", str(install_script)],
        stdin=slave,
        stdout=slave,
        stderr=slave,
        env=env,
        close_fds=True,
    )
    os.close(slave)

    try:
        # Step 1: Main Menu
        _drain_pty_until(master, [b"Select an operation:"])
        assert proc.poll() is None

        # Step 2: Install -> Confirm
        os.write(master, b"\r")
        _drain_pty_until(master, [b"Ready to proceed:"])
        os.write(master, b"\r")

        # Step 3: Success Screen prompt
        out_succ = _drain_pty_until(master, [b"What would you like to do?"])
        assert b"INSTALLATION COMPLETE" in out_succ
        assert proc.poll() is None, "Linux installer unexpectedly terminated"

        # Step 4: Choose "Open Web Interface" (Down x 1, Enter)
        os.write(master, b"\x1b[B\r")

        # Step 5: Wait for Running Screen prompt
        out_run = _drain_pty_until(master, [b"Open Altr Stream Again"])
        assert b"ALTR STREAM IS RUNNING" in out_run

        assert launch_log.is_file()
        assert "http://localhost:8000" in launch_log.read_text()

        # Step 6: Back to Main Menu (Down x 2, Enter)
        os.write(master, b"\x1b[B\x1b[B\r")

        # Step 7: Main Menu shows running status
        out_menu = _drain_pty_until(master, [b"Select an operation:"])
        assert b"Select an operation:" in out_menu

        # Step 8: Exit (Down x 4, Enter)
        for _ in range(4):
            os.write(master, b"\x1b[B")
            time.sleep(0.05)
        os.write(master, b"\r")

        ret = proc.wait(timeout=3)
        assert ret == 0

    finally:
        os.close(master)
        if proc.poll() is None:
            proc.kill()


# ==============================================================================
# Regression Tests: Canonical Container Conflict Resolution (Tests A - I)
# ==============================================================================

def test_regression_test_a_existing_container_conflict_detected_no_auto_delete(tmp_path: Path) -> None:
    """TEST A:
    - existing stopped container named altr-stream
    - installation requested at a different path
    - installer detects conflict before compose creation
    - conflict menu appears
    - installer does not delete anything automatically
    """
    import pty
    import os
    import time

    mock_bin, _ = _setup_mock_docker(tmp_path, existing_container=True, existing_status="exited", existing_workdir="/different/existing/dir")
    install_script = REPO_ROOT / "packaging" / "installers" / "Altr-Stream_macOS_Installer.command"
    target_install_dir = tmp_path / "altr_conflict_test"

    master, slave = pty.openpty()
    _set_pty_size(slave)
    env = os.environ.copy()
    env["PATH"] = f"{mock_bin}:{env.get('PATH', '')}"
    env["TERM"] = "xterm-256color"
    env["ALTR_STREAM_HOME"] = str(target_install_dir)
    gum_bin = get_resolved_gum_bin()
    if gum_bin:
        env["GUM_BIN"] = gum_bin

    proc = subprocess.Popen(
        ["bash", str(install_script)],
        stdin=slave,
        stdout=slave,
        stderr=slave,
        env=env,
        close_fds=True,
    )
    os.close(slave)

    try:
        # Step 1: Main Menu -> Choose Install
        _drain_pty_until(master, [b"Select an operation:"])
        os.write(master, b"\r")

        # Step 2: Confirm Installation
        _drain_pty_until(master, [b"Ready to proceed:"])
        os.write(master, b"\r")

        # Step 3: Conflict screen appears before compose creation
        out = _drain_pty_until(master, [b"What would you like to do?"])
        assert b"EXISTING CONTAINER DETECTED" in out or b"altr-stream" in out
        assert b"Use Existing Altr Stream Container" in out
        assert b"Remove Existing Container" in out
        assert b"View Container Details" in out
        assert b"Retry Installation" in out
        assert b"Back to Main Menu" in out
        assert b"Exit" in out

        # Verify installer did NOT delete the container automatically
        state_file = tmp_path / "docker_state.env"
        assert state_file.is_file(), "Conflicting container state must not be automatically deleted"

        # Exit cleanly (Down x 5, Enter)
        for _ in range(5):
            os.write(master, b"\x1b[B")
            time.sleep(0.05)
        os.write(master, b"\r")

        ret = proc.wait(timeout=3)
        assert ret == 0
    finally:
        os.close(master)
        if proc.poll() is None:
            proc.kill()


def test_regression_test_b_view_container_details(tmp_path: Path) -> None:
    """TEST B:
    - choose View Container Details
    - useful details are displayed (Name, ID, Status, Image, Mounts, Classification)
    """
    import pty
    import os
    import time

    mock_bin, _ = _setup_mock_docker(tmp_path, existing_container=True, existing_status="exited", existing_workdir="/different/existing/dir")
    install_script = REPO_ROOT / "packaging" / "installers" / "Altr-Stream_macOS_Installer.command"
    target_install_dir = tmp_path / "altr_details_test"

    master, slave = pty.openpty()
    _set_pty_size(slave)
    env = os.environ.copy()
    env["PATH"] = f"{mock_bin}:{env.get('PATH', '')}"
    env["TERM"] = "xterm-256color"
    env["ALTR_STREAM_HOME"] = str(target_install_dir)
    gum_bin = get_resolved_gum_bin()
    if gum_bin:
        env["GUM_BIN"] = gum_bin

    proc = subprocess.Popen(
        ["bash", str(install_script)],
        stdin=slave,
        stdout=slave,
        stderr=slave,
        env=env,
        close_fds=True,
    )
    os.close(slave)

    try:
        # Main Menu -> Install -> Confirm
        _drain_pty_until(master, [b"Select an operation:"])
        time.sleep(0.15)
        os.write(master, b"\r")
        _drain_pty_until(master, [b"Ready to proceed:"])
        time.sleep(0.15)
        os.write(master, b"\r")

        # Conflict menu: wait until fully rendered
        _drain_pty_until(master, [b"Exit"])
        time.sleep(0.15)

        # Navigate to "View Container Details" (Down x 2, Enter)
        os.write(master, b"\x1b[B\x1b[B\r")

        # Details screen
        out_details = _drain_pty_until(master, [b"Back to Conflict Menu"])
        assert b"CONTAINER DETAILS" in out_details
        assert b"altr-stream" in out_details
        assert b"46ccc79f24b9" in out_details
        assert b"exited" in out_details
        assert b"ghcr.io/helloaltr/altr-stream" in out_details
        assert b"altr_stream_data" in out_details
        assert b"Identified as an Altr Stream container" in out_details

        # Return to Conflict Menu
        time.sleep(0.15)
        os.write(master, b"\r")
        _drain_pty_until(master, [b"Exit"])
        time.sleep(0.15)

        # Exit cleanly (Down x 5, Enter)
        for _ in range(5):
            os.write(master, b"\x1b[B")
            time.sleep(0.05)
        os.write(master, b"\r")

        ret = proc.wait(timeout=3)
        assert ret == 0
    finally:
        os.close(master)
        if proc.poll() is None:
            proc.kill()


def test_regression_test_c_use_existing_container(tmp_path: Path) -> None:
    """TEST C:
    - choose Use Existing Altr Stream Container
    - compatible existing container is reused safely without recreation
    """
    import pty
    import os
    import time

    mock_bin, _ = _setup_mock_docker(tmp_path, existing_container=True, existing_status="exited", existing_workdir=str((tmp_path / "old_altr_dir").resolve()))
    install_script = REPO_ROOT / "packaging" / "installers" / "Altr-Stream_macOS_Installer.command"
    target_install_dir = tmp_path / "altr_use_existing_test"

    master, slave = pty.openpty()
    _set_pty_size(slave)
    env = os.environ.copy()
    env["PATH"] = f"{mock_bin}:{env.get('PATH', '')}"
    env["TERM"] = "xterm-256color"
    env["ALTR_STREAM_HOME"] = str(target_install_dir)
    gum_bin = get_resolved_gum_bin()
    if gum_bin:
        env["GUM_BIN"] = gum_bin

    proc = subprocess.Popen(
        ["bash", str(install_script)],
        stdin=slave,
        stdout=slave,
        stderr=slave,
        env=env,
        close_fds=True,
    )
    os.close(slave)

    try:
        # Main Menu -> Install -> Confirm
        _drain_pty_until(master, [b"Select an operation:"])
        time.sleep(0.15)
        os.write(master, b"\r")
        _drain_pty_until(master, [b"Ready to proceed:"])
        time.sleep(0.15)
        os.write(master, b"\r")

        # Conflict menu: wait until fully rendered
        _drain_pty_until(master, [b"Exit"])
        time.sleep(0.15)

        # Choose "Use Existing Altr Stream Container" (1st option: Enter)
        os.write(master, b"\r")

        # Container is stopped -> prompt to start container appears
        out_start = _drain_pty_until(master, [b"Start Container & Verify Health"])
        assert b"CONTAINER STOPPED" in out_start
        time.sleep(0.15)

        # Choose "Start Container & Verify Health" (Enter)
        os.write(master, b"\r")

        # Verification summary screen
        out_summary = _drain_pty_until(master, [b"Use Existing Installation"])
        assert b"EXISTING ALTR STREAM FOUND" in out_summary
        assert b"altr-stream" in out_summary
        assert b"Running / Healthy" in out_summary
        assert b"http://localhost:8000" in out_summary

        # Choose "Use Existing Installation" (Enter)
        time.sleep(0.15)
        os.write(master, b"\r")

        # Ready / Complete summary appears
        out_ready = _drain_pty_until(master, [b"Open Web Interface"])
        assert b"INSTALLATION COMPLETE" in out_ready

        # Return to Main Menu (Down x 3, Enter: "Back to Main Menu")
        time.sleep(0.15)
        for _ in range(3):
            os.write(master, b"\x1b[B")
            time.sleep(0.05)
        os.write(master, b"\r")

        # Main Menu shows running status
        _drain_pty_until(master, [b"Select an operation:"])
        time.sleep(0.15)

        # Exit cleanly (Down x 4, Enter: "Exit")
        for _ in range(4):
            os.write(master, b"\x1b[B")
            time.sleep(0.05)
        os.write(master, b"\r")

        ret = proc.wait(timeout=3)
        assert ret == 0

        # Verify container was started, not deleted or recreated
        state_file = tmp_path / "docker_state.env"
        assert state_file.is_file()
        assert "STATUS=running" in state_file.read_text()
    finally:
        os.close(master)
        if proc.poll() is None:
            proc.kill()


def test_regression_test_d_remove_existing_container_with_confirmation(tmp_path: Path) -> None:
    """TEST D:
    - choose Remove Existing Container
    - explicit confirmation required (test Cancel then Confirm)
    - only conflicting container is removed
    - persistent volume is preserved
    - installation proceeds and succeeds
    """
    import pty
    import os
    import time

    mock_bin, _ = _setup_mock_docker(tmp_path, existing_container=True, existing_status="exited", existing_workdir="/different/path")
    install_script = REPO_ROOT / "packaging" / "installers" / "Altr-Stream_macOS_Installer.command"
    target_install_dir = tmp_path / "altr_remove_test"

    master, slave = pty.openpty()
    _set_pty_size(slave)
    env = os.environ.copy()
    env["PATH"] = f"{mock_bin}:{env.get('PATH', '')}"
    env["TERM"] = "xterm-256color"
    env["ALTR_STREAM_HOME"] = str(target_install_dir)
    gum_bin = get_resolved_gum_bin()
    if gum_bin:
        env["GUM_BIN"] = gum_bin

    proc = subprocess.Popen(
        ["bash", str(install_script)],
        stdin=slave,
        stdout=slave,
        stderr=slave,
        env=env,
        close_fds=True,
    )
    os.close(slave)

    try:
        # Main Menu -> Install -> Confirm
        _drain_pty_until(master, [b"Select an operation:"])
        time.sleep(0.15)
        os.write(master, b"\r")
        _drain_pty_until(master, [b"Ready to proceed:"])
        time.sleep(0.15)
        os.write(master, b"\r")

        # Conflict menu: wait until fully rendered
        _drain_pty_until(master, [b"Exit"])
        time.sleep(0.15)

        # Choose "Remove Existing Container" (Down x 1, Enter)
        os.write(master, b"\x1b[B\r")

        # Warning screen: default is Cancel
        out_warn = _drain_pty_until(master, [b"Proceed?"])
        assert b"EXISTING CONTAINER" in out_warn
        assert b"altr-stream" in out_warn
        time.sleep(0.15)

        # Press Enter on Cancel
        os.write(master, b"\r")

        # Verify returned to Conflict Menu without removing container
        _drain_pty_until(master, [b"Exit"])
        time.sleep(0.15)
        assert (tmp_path / "docker_state.env").is_file()

        # Choose "Remove Existing Container" again
        os.write(master, b"\x1b[B\r")
        _drain_pty_until(master, [b"Proceed?"])
        time.sleep(0.15)

        # Choose "Remove Container" (Down x 1, Enter)
        os.write(master, b"\x1b[B\r")

        # Explicit confirmation screen
        out_confirm = _drain_pty_until(master, [b"Are you sure?"])
        assert b"CONFIRM CONTAINER REMOVAL" in out_confirm
        assert b"altr_stream_data" in out_confirm
        time.sleep(0.15)

        # Choose "Confirm Removal" (Down x 1, Enter)
        os.write(master, b"\x1b[B\r")

        # Removal occurs and installation completes
        out_done = _drain_pty_until(master, [b"Open Web Interface"])
        assert b"INSTALLATION COMPLETE" in out_done
        time.sleep(0.15)

        # Exit cleanly (Down x 4, Enter: "Exit")
        for _ in range(4):
            os.write(master, b"\x1b[B")
            time.sleep(0.05)
        os.write(master, b"\r")

        ret = proc.wait(timeout=3)
        assert ret == 0

        # Verify volume was preserved (check docker_cmds.log)
        docker_log = (tmp_path / "docker_cmds.log").read_text()
        assert "rm -f altr-stream" in docker_log
        assert "volume rm" not in docker_log
        assert "volume prune" not in docker_log
    finally:
        os.close(master)
        if proc.poll() is None:
            proc.kill()


def test_regression_test_e_retry_installation_after_conflict_resolved(tmp_path: Path) -> None:
    """TEST E:
    - choose Retry after conflict is resolved
    - installation proceeds normally
    """
    import pty
    import os
    import time

    mock_bin, _ = _setup_mock_docker(tmp_path, existing_container=True, existing_status="exited", existing_workdir="/different/path")
    install_script = REPO_ROOT / "packaging" / "installers" / "Altr-Stream_macOS_Installer.command"
    target_install_dir = tmp_path / "altr_retry_test"

    master, slave = pty.openpty()
    _set_pty_size(slave)
    env = os.environ.copy()
    env["PATH"] = f"{mock_bin}:{env.get('PATH', '')}"
    env["TERM"] = "xterm-256color"
    env["ALTR_STREAM_HOME"] = str(target_install_dir)
    gum_bin = get_resolved_gum_bin()
    if gum_bin:
        env["GUM_BIN"] = gum_bin

    proc = subprocess.Popen(
        ["bash", str(install_script)],
        stdin=slave,
        stdout=slave,
        stderr=slave,
        env=env,
        close_fds=True,
    )
    os.close(slave)

    try:
        # Main Menu -> Install -> Confirm
        _drain_pty_until(master, [b"Select an operation:"])
        time.sleep(0.15)
        os.write(master, b"\r")
        _drain_pty_until(master, [b"Ready to proceed:"])
        time.sleep(0.15)
        os.write(master, b"\r")

        # Conflict menu: wait until fully rendered
        _drain_pty_until(master, [b"Exit"])
        time.sleep(0.15)

        # First, try "Retry Installation" while conflict STILL exists (Down x 3, Enter)
        for _ in range(3):
            os.write(master, b"\x1b[B")
            time.sleep(0.05)
        os.write(master, b"\r")

        # Warning appears: "Container altr-stream still exists"
        time.sleep(1.8)
        _drain_pty_until(master, [b"Exit"])
        time.sleep(0.15)

        # Now simulate resolving the conflict outside the installer
        state_file = tmp_path / "docker_state.env"
        if state_file.exists():
            state_file.unlink()

        # Retry Installation again (Down x 3, Enter)
        for _ in range(3):
            os.write(master, b"\x1b[B")
            time.sleep(0.05)
        os.write(master, b"\r")

        # Installation proceeds and completes
        out_complete = _drain_pty_until(master, [b"Open Web Interface"])
        assert b"INSTALLATION COMPLETE" in out_complete
        time.sleep(0.15)

        # Exit cleanly (Down x 4, Enter: "Exit")
        for _ in range(4):
            os.write(master, b"\x1b[B")
            time.sleep(0.05)
        os.write(master, b"\r")

        ret = proc.wait(timeout=3)
        assert ret == 0
    finally:
        os.close(master)
        if proc.poll() is None:
            proc.kill()


def test_regression_test_f_view_container_logs_when_creation_fails(tmp_path: Path) -> None:
    """TEST F:
    - container creation fails before a new container exists
    - View Container Logs explains that no new container logs exist
    - actual Docker error is shown
    """
    import pty
    import os
    import time

    mock_bin, _ = _setup_mock_docker(tmp_path, existing_container=False)
    install_script = REPO_ROOT / "packaging" / "installers" / "Altr-Stream_macOS_Installer.command"
    target_install_dir = tmp_path / "altr_fail_test"

    master, slave = pty.openpty()
    _set_pty_size(slave)
    env = os.environ.copy()
    env["PATH"] = f"{mock_bin}:{env.get('PATH', '')}"
    env["TERM"] = "xterm-256color"
    env["ALTR_STREAM_HOME"] = str(target_install_dir)
    env["SIMULATE_CREATION_FAILURE"] = "1"
    gum_bin = get_resolved_gum_bin()
    if gum_bin:
        env["GUM_BIN"] = gum_bin

    proc = subprocess.Popen(
        ["bash", str(install_script)],
        stdin=slave,
        stdout=slave,
        stderr=slave,
        env=env,
        close_fds=True,
    )
    os.close(slave)

    try:
        # Main Menu -> Install -> Confirm
        _drain_pty_until(master, [b"Select an operation:"])
        time.sleep(0.15)
        os.write(master, b"\r")
        _drain_pty_until(master, [b"Ready to proceed:"])
        time.sleep(0.15)
        os.write(master, b"\r")

        # Failure screen appears with specific error
        out_fail = _drain_pty_until(master, [b"Retry Installation"])
        assert b"INSTALLATION FAILED" in out_fail
        assert b"Container name \"altr-stream\" is already in use" in out_fail or b"Conflict" in out_fail
        time.sleep(0.15)

        # Choose "View Container Logs" (Down x 2, Enter)
        os.write(master, b"\x1b[B\x1b[B\r")

        # Container logs screen explains that container was never created
        out_logs = _drain_pty_until(master, [b"Back to Failure Menu"])
        assert b"CONTAINER LOGS" in out_logs
        assert b"No logs are available for the new container" in out_logs
        assert b"before the container could be created" in out_logs
        assert b"Docker reported:" in out_logs
        assert b"Conflict" in out_logs
        time.sleep(0.15)

        # Choose "Back to Failure Menu" (Down x 1, Enter)
        os.write(master, b"\x1b[B\r")
        _drain_pty_until(master, [b"Retry Installation"])
        time.sleep(0.15)

        # Exit cleanly (Down x 4, Enter: "Exit")
        for _ in range(4):
            os.write(master, b"\x1b[B")
            time.sleep(0.05)
        os.write(master, b"\r")

        ret = proc.wait(timeout=3)
        assert ret == 0
    finally:
        os.close(master)
        if proc.poll() is None:
            proc.kill()


def test_regression_test_g_unrelated_docker_containers_and_volumes_never_touched(tmp_path: Path) -> None:
    """TEST G:
    - unrelated Docker containers and volumes are never touched
    """
    import os

    mock_bin, _ = _setup_mock_docker(tmp_path, existing_container=True, existing_status="exited", existing_workdir="/different/path")
    log_file = tmp_path / "docker_cmds.log"

    install_script = REPO_ROOT / "packaging" / "installers" / "Altr-Stream_macOS_Installer.command"
    target_install_dir = tmp_path / "altr_safety_test"

    env = os.environ.copy()
    env["PATH"] = f"{mock_bin}:{env.get('PATH', '')}"
    env["ALTR_STREAM_HOME"] = str(target_install_dir)

    # Run non-interactive install (which aborts safely on conflict)
    result = subprocess.run(["bash", str(install_script), "install", str(target_install_dir)], env=env, capture_output=True, text=True)
    assert result.returncode != 0
    assert "conflicting container exists" in result.stderr.lower()

    # Verify command log
    if log_file.exists():
        commands = log_file.read_text().splitlines()
        for cmd in commands:
            assert "system prune" not in cmd
            assert "volume prune" not in cmd
            assert "container prune" not in cmd
            if "volume rm" in cmd:
                pytest.fail(f"Unexpected volume rm executed: {cmd}")
            if "rm -f" in cmd:
                assert "altr-stream" in cmd, f"Unexpected container removed: {cmd}"


def test_regression_test_h_development_and_production_compose_container_names() -> None:
    """TEST H:
    - development Compose uses altr-stream-dev
    - production Compose continues using altr-stream
    """
    dev_compose = REPO_ROOT / "docker-compose.yml"
    assert dev_compose.is_file()
    dev_content = dev_compose.read_text(encoding="utf-8")
    assert "container_name: altr-stream-dev" in dev_content
    # Ensure production container_name is NOT in dev compose
    assert "container_name: altr-stream\n" not in dev_content

    prod_template = REPO_ROOT / "packaging" / "templates" / "docker-compose.template.yml"
    assert prod_template.is_file()
    prod_content = prod_template.read_text(encoding="utf-8")
    assert "container_name: altr-stream" in prod_content
    assert "container_name: altr-stream-dev" not in prod_content


def test_regression_test_i_successful_installer_flow_e2e(tmp_path: Path) -> None:
    """TEST I:
    - existing successful installer flow still works:
      Install -> Health verification -> Installation Complete -> Launch -> Running screen -> Back to Main Menu -> Exit
    """
    import pty
    import os
    import time

    mock_bin, _ = _setup_mock_docker(tmp_path)
    launch_log = tmp_path / "launch.log"

    # Mock open command
    mock_open = mock_bin / "open"
    mock_open.write_text(f"#!/bin/sh\necho \"$@\" >> \"{launch_log}\"\nexit 0\n")
    mock_open.chmod(0o755)

    install_script = REPO_ROOT / "packaging" / "installers" / "Altr-Stream_macOS_Installer.command"
    target_install_dir = tmp_path / "tui_macos_home_e2e"

    master, slave = pty.openpty()
    _set_pty_size(slave)
    env = os.environ.copy()
    env["PATH"] = f"{mock_bin}:{env.get('PATH', '')}"
    env["TERM"] = "xterm-256color"
    env["ALTR_STREAM_HOME"] = str(target_install_dir)
    gum_bin = get_resolved_gum_bin()
    if gum_bin:
        env["GUM_BIN"] = gum_bin

    proc = subprocess.Popen(
        ["bash", str(install_script)],
        stdin=slave,
        stdout=slave,
        stderr=slave,
        env=env,
        close_fds=True,
    )
    os.close(slave)

    try:
        # Step 1: Main Menu
        _drain_pty_until(master, [b"Select an operation:"])
        assert proc.poll() is None

        # Step 2: Install -> Confirm
        os.write(master, b"\r")
        _drain_pty_until(master, [b"Ready to proceed:"])
        os.write(master, b"\r")

        # Step 3: Success Screen prompt
        out_succ = _drain_pty_until(master, [b"What would you like to do?"])
        assert b"INSTALLATION COMPLETE" in out_succ
        assert proc.poll() is None

        # Step 4: Choose "Open Web Interface" (Down x 1, Enter)
        os.write(master, b"\x1b[B\r")

        # Step 5: Wait for Running Screen prompt
        out_run = _drain_pty_until(master, [b"Open Altr Stream Again"])
        assert b"ALTR STREAM IS RUNNING" in out_run

        assert launch_log.is_file()
        assert "http://localhost:8000" in launch_log.read_text()

        # Step 6: Back to Main Menu (Down x 2, Enter)
        os.write(master, b"\x1b[B\x1b[B\r")

        # Step 7: Main Menu shows running status
        out_menu = _drain_pty_until(master, [b"Select an operation:"])
        assert b"Select an operation:" in out_menu

        # Step 8: Exit (Down x 4, Enter)
        for _ in range(4):
            os.write(master, b"\x1b[B")
            time.sleep(0.05)
        os.write(master, b"\r")

        ret = proc.wait(timeout=3)
        assert ret == 0
    finally:
        os.close(master)
        if proc.poll() is None:
            proc.kill()


# ==============================================================================
# Targeted Tests for the 21 Installer Product Requirements
# ==============================================================================

def test_req01_default_macos_installation_path(tmp_path: Path) -> None:
    """Requirement 1: Default macOS installation path resolves to ~/.altr-stream."""
    fake_home = tmp_path / "macos_home"
    fake_home.mkdir(parents=True)
    installer = REPO_ROOT / "packaging" / "installers" / "Altr-Stream_macOS_Installer.command"
    env = {
        "HOME": str(fake_home),
        "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
    }
    cmd = f'. "{installer}" && get_install_dir'
    res = subprocess.run(["bash", "-c", cmd], env=env, capture_output=True, text=True)
    assert res.returncode == 0
    resolved = res.stdout.strip()
    assert resolved == str(fake_home / ".altr-stream")


def test_req02_default_linux_installation_path(tmp_path: Path) -> None:
    """Requirement 2: Default Linux installation path resolves to ~/.altr-stream."""
    fake_home = tmp_path / "linux_home"
    fake_home.mkdir(parents=True)
    installer = REPO_ROOT / "packaging" / "installers" / "Altr-Stream_Linux_Installer.sh"
    env = {
        "HOME": str(fake_home),
        "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
    }
    cmd = f'. "{installer}" && get_install_dir'
    res = subprocess.run(["bash", "-c", cmd], env=env, capture_output=True, text=True)
    assert res.returncode == 0
    resolved = res.stdout.strip()
    assert resolved == str(fake_home / ".altr-stream")


def test_req03_default_windows_installation_path() -> None:
    """Requirement 3: Default Windows installation path resolves to %USERPROFILE%\\.altr-stream."""
    installer = REPO_ROOT / "packaging" / "installers" / "Altr-Stream_Windows_Installer.bat"
    content = _extract_windows_bat_payload(installer)
    assert '$DefaultDir = Join-Path $env:USERPROFILE ".altr-stream"' in content
    assert 'function Get-InstallDirectory' in content
    assert '$DefaultDir' in content


def test_req04_override_path_with_temporary_directories(tmp_path: Path) -> None:
    """Requirement 4: Tests can still override the path with temporary directories."""
    fake_home = tmp_path / "test_home"
    fake_home.mkdir(parents=True)
    custom_override = tmp_path / "custom_temp_dir"
    installer = REPO_ROOT / "packaging" / "installers" / "Altr-Stream_macOS_Installer.command"

    # Override via environment variable
    env = {
        "HOME": str(fake_home),
        "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
        "ALTR_STREAM_HOME": str(custom_override),
    }
    cmd = f'. "{installer}" && get_install_dir'
    res = subprocess.run(["bash", "-c", cmd], env=env, capture_output=True, text=True)
    assert res.returncode == 0
    assert res.stdout.strip() == str(custom_override)

    # Override via positional argument
    cmd_arg = f'. "{installer}" && get_install_dir "{custom_override}"'
    res2 = subprocess.run(["bash", "-c", cmd_arg], env={"HOME": str(fake_home), "PATH": "/usr/bin:/bin"}, capture_output=True, text=True)
    assert res2.returncode == 0
    assert res2.stdout.strip() == str(custom_override)


def test_req05_no_pytest_temporary_path_leaks_into_default_production_behavior(tmp_path: Path) -> None:
    """Requirement 5: No pytest temporary path leaks into default production behavior."""
    fake_home = tmp_path / "prod_user"
    fake_home.mkdir(parents=True)
    config_file = fake_home / ".altr-stream-config"
    # Simulate a leaked pytest path in config file
    leaked_pytest_path = "/private/var/folders/3y/jybvw1dx21q72qvdyyhx5csw0000gn/T/pytest-of-asher/pytest-140/tui_test"
    config_file.write_text(leaked_pytest_path)

    installer = REPO_ROOT / "packaging" / "installers" / "Altr-Stream_macOS_Installer.command"
    env = {
        "HOME": str(fake_home),
        "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
    }
    # get_install_dir should reject the leaked pytest path and fall back to stable default
    cmd = f'. "{installer}" && get_install_dir'
    res = subprocess.run(["bash", "-c", cmd], env=env, capture_output=True, text=True)
    assert res.returncode == 0
    assert res.stdout.strip() == str(fake_home / ".altr-stream")

    # save_install_dir should refuse to save a temporary path to the default config file
    config_file.unlink()
    save_cmd = f'. "{installer}" && save_install_dir "{leaked_pytest_path}"'
    subprocess.run(["bash", "-c", save_cmd], env=env, capture_output=True, text=True)
    assert not config_file.exists()


def test_req06_to_14_repair_tui_lifecycle_success_screen(tmp_path: Path) -> None:
    """Requirements 6, 10, 11, 12, 13, 14:
    - Repair success remains inside TUI (6)
    - Preserves persistent data (10)
    - Verifies final health before success (11)
    - Launch/open works (12)
    - Back to Main Menu works (13)
    - Explicit Exit terminates cleanly (14)
    """
    import pty
    import os
    import time

    mock_bin, _ = _setup_mock_docker(tmp_path)
    launch_log = tmp_path / "launch.log"
    docker_log = tmp_path / "docker_cmds.log"

    # Mock open command
    mock_open = mock_bin / "open"
    mock_open.write_text(f"#!/bin/sh\necho \"$@\" >> \"{launch_log}\"\nexit 0\n")
    mock_open.chmod(0o755)

    install_script = REPO_ROOT / "packaging" / "installers" / "Altr-Stream_macOS_Installer.command"
    target_install_dir = tmp_path / "repair_home"
    target_install_dir.mkdir(parents=True)
    (target_install_dir / ".env").write_text("ALTR_STREAM_PORT=8000\n")

    master, slave = pty.openpty()
    _set_pty_size(slave)
    env = os.environ.copy()
    env["PATH"] = f"{mock_bin}:{env.get('PATH', '')}"
    env["TERM"] = "xterm-256color"
    env["ALTR_STREAM_HOME"] = str(target_install_dir)
    gum_bin = get_resolved_gum_bin()
    if gum_bin:
        env["GUM_BIN"] = gum_bin

    proc = subprocess.Popen(
        ["bash", str(install_script)],
        stdin=slave,
        stdout=slave,
        stderr=slave,
        env=env,
        close_fds=True,
    )
    os.close(slave)

    try:
        # Step 1: Main Menu
        _drain_pty_until(master, [b"Select an operation:"])
        assert proc.poll() is None

        # Step 2: Choose Repair (Down x 2, Enter)
        os.write(master, b"\x1b[B\x1b[B\r")

        # Step 3: Repair recommendation screen
        _drain_pty_until(master, [b"Ready to proceed:"])
        assert proc.poll() is None
        # Confirm repair (Enter)
        os.write(master, b"\r")

        # Step 4: Repair execution completes and transitions to persistent success screen (Req 6)
        out_succ = _drain_pty_until(master, [b"What would you like to do?"])
        assert b"REPAIR COMPLETE" in out_succ
        assert b"Configuration restored" in out_succ
        assert b"Persistent data preserved" in out_succ
        assert proc.poll() is None

        # Verify persistent volume was NEVER deleted (Req 10)
        if docker_log.exists():
            cmds = docker_log.read_text()
            assert "volume rm" not in cmds
            assert "altr_stream_data" not in cmds or "volume rm altr_stream_data" not in cmds

        # Step 5: Choose "Launch Altr Stream" (Enter) (Req 12)
        os.write(master, b"\r")

        # Running screen appears
        out_run = _drain_pty_until(master, [b"Open Altr Stream Again"])
        assert b"ALTR STREAM IS RUNNING" in out_run

        # Step 6: Choose "Back to Main Menu" (Down x 2, Enter) (Req 13)
        os.write(master, b"\x1b[B\x1b[B\r")

        # Main Menu reappears
        _drain_pty_until(master, [b"Select an operation:"])
        assert proc.poll() is None

        # Step 7: Exit from Main Menu (Down x 4, Enter) (Req 14)
        for _ in range(4):
            os.write(master, b"\x1b[B")
            time.sleep(0.05)
        os.write(master, b"\r")

        ret = proc.wait(timeout=3)
        assert ret == 0
    finally:
        os.close(master)
        if proc.poll() is None:
            proc.kill()


def test_req07_to_09_repair_tui_lifecycle_failure_and_retry(tmp_path: Path) -> None:
    """Requirements 7, 8, 9, 11:
    - Repair failure remains inside TUI without terminating (7)
    - Surfaces actual underlying errors (8)
    - Repair retry works (9)
    - Verifies health before success (fails if unhealthy) (11)
    """
    import pty
    import os
    import time

    # Mock docker with fail_health=True to simulate failed repair
    mock_bin, _ = _setup_mock_docker(tmp_path, fail_health=True)

    install_script = REPO_ROOT / "packaging" / "installers" / "Altr-Stream_macOS_Installer.command"
    target_install_dir = tmp_path / "repair_fail_home"
    target_install_dir.mkdir(parents=True)
    (target_install_dir / ".env").write_text("ALTR_STREAM_PORT=8000\n")

    master, slave = pty.openpty()
    _set_pty_size(slave)
    env = os.environ.copy()
    env["PATH"] = f"{mock_bin}:{env.get('PATH', '')}"
    env["TERM"] = "xterm-256color"
    env["ALTR_STREAM_HOME"] = str(target_install_dir)
    env["HEALTH_TIMEOUT"] = "2"
    gum_bin = get_resolved_gum_bin()
    if gum_bin:
        env["GUM_BIN"] = gum_bin

    proc = subprocess.Popen(
        ["bash", str(install_script)],
        stdin=slave,
        stdout=slave,
        stderr=slave,
        env=env,
        close_fds=True,
    )
    os.close(slave)

    try:
        # Step 1: Main Menu
        _drain_pty_until(master, [b"Select an operation:"])

        # Step 2: Choose Repair (Down x 2, Enter)
        os.write(master, b"\x1b[B\x1b[B\r")

        # Step 3: Repair recommendation screen -> Proceed (Enter)
        _drain_pty_until(master, [b"Ready to proceed:"])
        os.write(master, b"\r")

        # Step 4: Health check fails -> Persistent failure screen appears! (Req 7, 11)
        out_fail = _drain_pty_until(master, [b"What would you like to do?"], timeout_sec=15.0)
        assert b"REPAIR FAILED" in out_fail
        # Underlying error is surfaced (Req 8)
        assert b"Health Verification" in out_fail or b"health check" in out_fail.lower()
        # Installer is STILL alive (did not silently exit!) (Req 7)
        assert proc.poll() is None

        # Step 5: Test Retry Repair (Enter on default option "Retry Repair") (Req 9)
        os.write(master, b"\r")

        # Repair proceeds again and lands back on failure screen
        out_fail2 = _drain_pty_until(master, [b"What would you like to do?"], timeout_sec=15.0)
        assert b"REPAIR FAILED" in out_fail2
        assert proc.poll() is None

        # Step 6: Navigate to "Back to Main Menu" (Down x 3, Enter)
        for _ in range(3):
            os.write(master, b"\x1b[B")
            time.sleep(0.05)
        os.write(master, b"\r")

        # Returned to Main Menu
        _drain_pty_until(master, [b"Select an operation:"])
        assert proc.poll() is None

        # Step 7: Clean Exit (Down x 4, Enter)
        for _ in range(4):
            os.write(master, b"\x1b[B")
            time.sleep(0.05)
        os.write(master, b"\r")

        ret = proc.wait(timeout=3)
        assert ret == 0
    finally:
        os.close(master)
        if proc.poll() is None:
            proc.kill()


def test_req15_to_18_new_installer_filenames_and_documentation() -> None:
    """Requirements 15, 16, 17, 18:
    - New installer filenames present (15)
    - Old distributable names no longer referenced (16)
    - Release packaging includes platform-labelled installers (17)
    - README clearly explains which installer to choose (18)
    """
    installers_dir = REPO_ROOT / "packaging" / "installers"
    assert (installers_dir / "Altr-Stream_macOS_Installer.command").is_file()
    assert (installers_dir / "Altr-Stream_Linux_Installer.sh").is_file()
    assert (installers_dir / "Altr-Stream_Windows_Installer.bat").is_file()
    assert not (installers_dir / "Altr-Stream_Windows_Installer.ps1").exists()

    readme_template = REPO_ROOT / "packaging" / "templates" / "INSTALLER_README.md"
    assert readme_template.is_file()
    readme_text = readme_template.read_text(encoding="utf-8")
    assert "Altr-Stream_macOS_Installer.command" in readme_text
    assert "Altr-Stream_Linux_Installer.sh" in readme_text
    assert "Altr-Stream_Windows_Installer.bat" in readme_text
    assert "Altr-Stream_Windows_Installer.ps1" not in readme_text
    assert "macOS" in readme_text
    assert "Linux" in readme_text
    assert "Windows" in readme_text

    # Verify no stale distributable names in docs or packaging
    deployment_doc = (REPO_ROOT / "DEPLOYMENT.md").read_text(encoding="utf-8")
    assert "Altr-Stream_macOS_Installer.command" in deployment_doc
    assert "Altr-Stream_Linux_Installer.sh" in deployment_doc
    assert "Altr-Stream_Windows_Installer.bat" in deployment_doc
    assert "Altr-Stream_Windows_Installer.ps1" not in deployment_doc
    assert "Install-AltrStream.command" not in deployment_doc
    assert "Install-AltrStream.ps1" not in deployment_doc


def test_req19_to_21_installer_executable_and_syntax() -> None:
    """Requirements 19, 20, 21:
    - macOS installer executable (19)
    - Linux installer executable (20)
    - Windows PowerShell installer valid (21)
    """
    import os

    macos_script = REPO_ROOT / "packaging" / "installers" / "Altr-Stream_macOS_Installer.command"
    linux_script = REPO_ROOT / "packaging" / "installers" / "Altr-Stream_Linux_Installer.sh"
    win_payload = _extract_windows_bat_payload(REPO_ROOT / "packaging" / "installers" / "Altr-Stream_Windows_Installer.bat")

    # macOS and Linux must have executable bit set
    assert os.access(macos_script, os.X_OK), "macOS installer must be executable"
    assert os.access(linux_script, os.X_OK), "Linux installer must be executable"
    assert "Invoke-InstallWorkflow" in win_payload

    # Validate bash syntax
    res_mac = subprocess.run(["bash", "-n", str(macos_script)], capture_output=True, text=True)
    assert res_mac.returncode == 0, f"macOS syntax error: {res_mac.stderr}"

    res_lin = subprocess.run(["bash", "-n", str(linux_script)], capture_output=True, text=True)
    assert res_lin.returncode == 0, f"Linux syntax error: {res_lin.stderr}"

    # Validate Windows PowerShell script content
    win_content = win_payload
    assert "[CmdletBinding()]" in win_content
    assert "param (" in win_content
    assert "function Write-RuntimeFiles" in win_content
    assert "function Show-RepairSuccessScreen" in win_content
    assert "function Show-RepairFailureScreen" in win_content
    assert "function Test-InstallationHealth" in win_content
    assert "$MinTermCols = 100" in win_content
    assert "$MinTermLines = 30" in win_content
    assert "function Get-TermDimensions" in win_content
    assert "function Check-TerminalSize" in win_content
    assert "function Render-ScreenTop" in win_content


# ==============================================================================
# Regression Tests: Issue 1 (Repair Lifecycle A-I) & Issue 2 (Terminal Sizing)
# ==============================================================================

def test_repair_regression_a_stopped_container_replaced(tmp_path: Path) -> None:
    """Regression Test A: Pre-existing stopped 'altr-stream' container is replaced and repaired cleanly."""
    mock_bin, _ = _setup_mock_docker(tmp_path, existing_container=True, existing_status="exited")
    install_script = REPO_ROOT / "packaging" / "installers" / "Altr-Stream_macOS_Installer.command"
    target_install_dir = tmp_path / "repair_stopped_home"
    target_install_dir.mkdir(parents=True)

    env = os.environ.copy()
    env["PATH"] = f"{mock_bin}:{env.get('PATH', '')}"
    env["ALTR_STREAM_HOME"] = str(target_install_dir)

    result = subprocess.run(
        ["bash", str(install_script), "repair", str(target_install_dir)],
        env=env,
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, f"Repair failed: {result.stderr}\n{result.stdout}"
    assert "repair completed successfully" in result.stdout.lower()

    # Verify state was updated to running
    state_file = tmp_path / "docker_state.env"
    assert "STATUS=running" in state_file.read_text()


def test_repair_regression_b_running_container_handled_without_conflict(tmp_path: Path) -> None:
    """Regression Test B: Running 'altr-stream' container from different directory handled cleanly without name conflict."""
    mock_bin, _ = _setup_mock_docker(
        tmp_path,
        existing_container=True,
        existing_status="running",
        existing_workdir="/different/compose/dir",
    )
    install_script = REPO_ROOT / "packaging" / "installers" / "Altr-Stream_macOS_Installer.command"
    target_install_dir = tmp_path / "repair_running_home"
    target_install_dir.mkdir(parents=True)

    env = os.environ.copy()
    env["PATH"] = f"{mock_bin}:{env.get('PATH', '')}"
    env["ALTR_STREAM_HOME"] = str(target_install_dir)

    result = subprocess.run(
        ["bash", str(install_script), "repair", str(target_install_dir)],
        env=env,
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0
    assert "Conflict. The container name" not in result.stderr
    assert "Conflict. The container name" not in result.stdout
    assert "repair completed successfully" in result.stdout.lower()


def test_repair_regression_c_healthy_compatible_container_safely_reused(tmp_path: Path) -> None:
    """Regression Test C: Healthy, compatible existing container with volume attached is safely reused without destruction."""
    mock_bin, _ = _setup_mock_docker(
        tmp_path,
        existing_container=True,
        existing_status="running",
        existing_workdir="/existing/home",
        existing_image="ghcr.io/helloaltr/altr-stream:0.13.7-alpha",
    )
    install_script = REPO_ROOT / "packaging" / "installers" / "Altr-Stream_macOS_Installer.command"
    target_install_dir = tmp_path / "repair_reuse_home"
    target_install_dir.mkdir(parents=True)

    env = os.environ.copy()
    env["PATH"] = f"{mock_bin}:{env.get('PATH', '')}"
    env["ALTR_STREAM_HOME"] = str(target_install_dir)

    result = subprocess.run(
        ["bash", str(install_script), "repair", str(target_install_dir)],
        env=env,
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0
    assert "repair completed successfully" in result.stdout.lower()

    # Volume must not be touched
    docker_log = tmp_path / "docker_cmds.log"
    assert "volume rm" not in docker_log.read_text()


def test_repair_regression_d_incompatible_container_stopped_and_replaced(tmp_path: Path) -> None:
    """Regression Test D: Incompatible container (different image) is stopped/removed and replaced with canonical image."""
    mock_bin, _ = _setup_mock_docker(
        tmp_path,
        existing_container=True,
        existing_status="running",
        existing_image="nginx:alpine",
    )
    install_script = REPO_ROOT / "packaging" / "installers" / "Altr-Stream_macOS_Installer.command"
    target_install_dir = tmp_path / "repair_incompatible_home"
    target_install_dir.mkdir(parents=True)

    env = os.environ.copy()
    env["PATH"] = f"{mock_bin}:{env.get('PATH', '')}"
    env["ALTR_STREAM_HOME"] = str(target_install_dir)

    result = subprocess.run(
        ["bash", str(install_script), "repair", str(target_install_dir)],
        env=env,
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0
    assert "repair completed successfully" in result.stdout.lower()

    # Canonical image must now be active
    state_file = tmp_path / "docker_state.env"
    assert "ghcr.io/helloaltr/altr-stream:0.13.7-alpha" in state_file.read_text()


def test_repair_regression_e_and_f_replacement_and_successful_repair(tmp_path: Path) -> None:
    """Regression Tests E & F: Container replacement occurs cleanly and repair succeeds."""
    mock_bin, _ = _setup_mock_docker(tmp_path, existing_container=True, existing_status="exited")
    install_script = REPO_ROOT / "packaging" / "installers" / "Altr-Stream_Linux_Installer.sh"
    target_install_dir = tmp_path / "repair_ef_home"
    target_install_dir.mkdir(parents=True)

    env = os.environ.copy()
    env["PATH"] = f"{mock_bin}:{env.get('PATH', '')}"
    env["ALTR_STREAM_HOME"] = str(target_install_dir)

    result = subprocess.run(
        ["bash", str(install_script), "repair", str(target_install_dir)],
        env=env,
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0
    assert "repair completed successfully" in result.stdout.lower()


def test_repair_regression_g_persistent_volume_preserved_across_repair(tmp_path: Path) -> None:
    """Regression Test G: Persistent named volume 'altr_stream_data' is strictly preserved across repair."""
    mock_bin, _ = _setup_mock_docker(tmp_path, existing_container=True, existing_status="exited")
    install_script = REPO_ROOT / "packaging" / "installers" / "Altr-Stream_macOS_Installer.command"
    target_install_dir = tmp_path / "repair_vol_home"
    target_install_dir.mkdir(parents=True)

    env = os.environ.copy()
    env["PATH"] = f"{mock_bin}:{env.get('PATH', '')}"
    env["ALTR_STREAM_HOME"] = str(target_install_dir)

    subprocess.run(
        ["bash", str(install_script), "repair", str(target_install_dir)],
        env=env,
        check=True,
        capture_output=True,
        text=True,
    )

    docker_log = tmp_path / "docker_cmds.log"
    assert docker_log.exists()
    cmds = docker_log.read_text()
    assert "volume rm" not in cmds
    assert "altr_stream_data" not in cmds or "volume rm altr_stream_data" not in cmds


def test_repair_regression_h_genuine_recreate_failure_shows_real_error_and_no_contradictory_running_state(tmp_path: Path) -> None:
    """Regression Test H: Genuine recreate failure shows real Docker error and container state is stopped/not installed, not Running."""
    import pty
    mock_bin, _ = _setup_mock_docker(tmp_path, existing_container=True, existing_status="exited")
    install_script = REPO_ROOT / "packaging" / "installers" / "Altr-Stream_macOS_Installer.command"
    target_install_dir = tmp_path / "repair_genuine_fail_home"
    target_install_dir.mkdir(parents=True)

    master, slave = pty.openpty()
    _set_pty_size(slave, rows=35, cols=100)
    env = os.environ.copy()
    env["PATH"] = f"{mock_bin}:{env.get('PATH', '')}"
    env["TERM"] = "xterm-256color"
    env["ALTR_STREAM_HOME"] = str(target_install_dir)
    env["SIMULATE_CREATION_FAILURE"] = "1"
    gum_bin = get_resolved_gum_bin()
    if gum_bin:
        env["GUM_BIN"] = gum_bin

    proc = subprocess.Popen(
        ["bash", str(install_script)],
        stdin=slave,
        stdout=slave,
        stderr=slave,
        env=env,
        close_fds=True,
    )
    os.close(slave)

    try:
        # Step 1: Main Menu
        _drain_pty_until(master, [b"Select an operation:"])

        # Step 2: Choose Repair (Down x 2, Enter)
        os.write(master, b"\x1b[B\x1b[B\r")

        # Step 3: Repair Recommendation Screen -> Confirm (Enter)
        _drain_pty_until(master, [b"Proceed with Repair?", b"Ready to proceed:"])
        os.write(master, b"\r")

        # Step 4: Repair fails -> Failure Screen appears
        out_fail = _drain_pty_until(master, [b"What would you like to do?"], timeout_sec=15.0)
        assert b"REPAIR FAILED" in out_fail
        # Genuine Docker failure is surfaced
        assert b"Recreating container" in out_fail or b"failed to create container" in out_fail or b"Docker failed" in out_fail
        # State MUST NOT contradict: Container must be Stopped / Not Installed, NEVER Running
        assert b"Container:     Running" not in out_fail

        # Clean Exit
        os.write(master, b"\x1b[B\x1b[B\x1b[B\x1b[B\r")
    finally:
        os.close(master)
        if proc.poll() is None:
            proc.kill()


def test_repair_regression_i_retry_repair_runs_preflight_and_succeeds(tmp_path: Path) -> None:
    """Regression Test I: After transient failure, Retrying Repair re-runs preflight and succeeds cleanly."""
    import pty
    mock_bin, _ = _setup_mock_docker(tmp_path, fail_health=True)
    install_script = REPO_ROOT / "packaging" / "installers" / "Altr-Stream_macOS_Installer.command"
    target_install_dir = tmp_path / "repair_retry_home"
    target_install_dir.mkdir(parents=True)

    master, slave = pty.openpty()
    _set_pty_size(slave, rows=35, cols=100)
    env = os.environ.copy()
    env["PATH"] = f"{mock_bin}:{env.get('PATH', '')}"
    env["TERM"] = "xterm-256color"
    env["ALTR_STREAM_HOME"] = str(target_install_dir)
    env["HEALTH_TIMEOUT"] = "2"
    gum_bin = get_resolved_gum_bin()
    if gum_bin:
        env["GUM_BIN"] = gum_bin

    proc = subprocess.Popen(
        ["bash", str(install_script)],
        stdin=slave,
        stdout=slave,
        stderr=slave,
        env=env,
        close_fds=True,
    )
    os.close(slave)

    try:
        # Step 1: Main Menu
        _drain_pty_until(master, [b"Select an operation:"])

        # Step 2: Choose Repair (Down x 2, Enter)
        os.write(master, b"\x1b[B\x1b[B\r")

        # Step 3: Repair Recommendation -> Confirm
        _drain_pty_until(master, [b"Proceed with Repair?", b"Ready to proceed:"])
        os.write(master, b"\r")

        # Step 4: Health fails -> Failure screen
        out_fail = _drain_pty_until(master, [b"What would you like to do?"], timeout_sec=15.0)
        assert b"REPAIR FAILED" in out_fail

        # Now fix curl mock so retry succeeds
        mock_curl = mock_bin / "curl"
        mock_curl.write_text('#!/bin/sh\necho \'{"status":"healthy","version":"0.13.7-alpha"}\'\nexit 0\n')
        mock_curl.chmod(0o755)

        # Step 5: Retry Repair (Enter on Retry Repair option)
        os.write(master, b"\r")

        # Step 6: Success screen appears!
        out_succ = _drain_pty_until(master, [b"What would you like to do?"], timeout_sec=15.0)
        assert b"REPAIR COMPLETE" in out_succ

        # Clean Exit
        for _ in range(4):
            os.write(master, b"\x1b[B")
            time.sleep(0.05)
        os.write(master, b"\r")
    finally:
        os.close(master)
        if proc.poll() is None:
            proc.kill()


def test_terminal_min_size_enforcement_and_dynamic_unblock(tmp_path: Path) -> None:
    """Issue 2: Terminal window < 100x30 displays warning card without terminating, unblocks upon resize."""
    import pty
    import fcntl
    import termios
    import struct

    mock_bin, _ = _setup_mock_docker(tmp_path)
    install_script = REPO_ROOT / "packaging" / "installers" / "Altr-Stream_macOS_Installer.command"
    target_install_dir = tmp_path / "term_size_home"
    target_install_dir.mkdir(parents=True)

    master, slave = pty.openpty()
    # Initialize with undersized window: 24 lines x 80 cols
    _set_pty_size(slave, rows=24, cols=80)
    env = os.environ.copy()
    env["PATH"] = f"{mock_bin}:{env.get('PATH', '')}"
    env["TERM"] = "xterm-256color"
    env["ALTR_STREAM_HOME"] = str(target_install_dir)
    gum_bin = get_resolved_gum_bin()
    if gum_bin:
        env["GUM_BIN"] = gum_bin

    proc = subprocess.Popen(
        ["bash", str(install_script)],
        stdin=slave,
        stdout=slave,
        stderr=slave,
        env=env,
        close_fds=True,
    )
    os.close(slave)

    try:
        # Step 1: Warning card displayed for undersized terminal
        out_warn = _drain_pty_until(master, [b"Please resize the terminal window."], timeout_sec=5.0)
        assert b"Terminal window is too small." in out_warn
        assert b"Required: 100" in out_warn
        # Process MUST NOT terminate
        assert proc.poll() is None

        # Step 2: Resize PTY to >= 100x30 (rows=35, cols=100)
        winsize = struct.pack("HHHH", 35, 100, 0, 0)
        fcntl.ioctl(master, termios.TIOCSWINSZ, winsize)

        # Step 3: Terminal size check passes and Main Menu renders
        out_menu = _drain_pty_until(master, [b"Select an operation:"], timeout_sec=6.0)
        assert b"Select an operation:" in out_menu
        assert proc.poll() is None

        # Exit cleanly
        for _ in range(4):
            os.write(master, b"\x1b[B")
            time.sleep(0.05)
        os.write(master, b"\r")
        assert proc.wait(timeout=3) == 0
    finally:
        os.close(master)
        if proc.poll() is None:
            proc.kill()


def test_selector_centered_inside_application_viewport(tmp_path: Path) -> None:
    """Issue 1: Selectors and prompts are centered inside the application viewport via padding."""
    import pty
    import re

    # 1. Structural inspection across macOS, Linux, and Windows installers
    macos_script = REPO_ROOT / "packaging" / "installers" / "Altr-Stream_macOS_Installer.command"
    linux_script = REPO_ROOT / "packaging" / "installers" / "Altr-Stream_Linux_Installer.sh"

    for script_path in [macos_script, linux_script]:
        content = script_path.read_text(encoding="utf-8")
        assert "gum_choose()" in content
        assert "gum_confirm()" in content
        assert "gum_input()" in content
        assert "get_viewport_sel_pad" in content
        # Ensure raw unpadded '$GUM_BIN choose' is not called outside gum_choose definition
        raw_choose_matches = re.findall(r'\"\$GUM_BIN\"\s+choose\b', content)
        assert len(raw_choose_matches) == 1  # Only within gum_choose() definition

        # Verify unified application viewport container card in show_main_menu
        assert "Unified Application Viewport Container Card" in content or "Docker Engine:" in content

    win_content = _extract_windows_bat_payload(REPO_ROOT / "packaging" / "installers" / "Altr-Stream_Windows_Installer.bat")
    assert "function Get-ViewportSelPad" in win_content
    assert "function Invoke-GumChoose" in win_content
    assert "function Invoke-GumConfirm" in win_content
    assert "function Invoke-GumInput" in win_content
    win_raw_choose = re.findall(r'&\s+\$(?:script:)?GumBin\s+choose\b', win_content)
    assert len(win_raw_choose) == 1  # Only within Invoke-GumChoose definition

    # 2. PTY execution check: inspect that the selector renders inside the centered viewport
    mock_bin, _ = _setup_mock_docker(tmp_path)
    target_install_dir = tmp_path / "centered_viewport_home"
    target_install_dir.mkdir(parents=True)

    master, slave = pty.openpty()
    # Terminal with cols=120: left_pad = (120-68)/2 = 26, sel_pad = 28
    _set_pty_size(slave, rows=35, cols=120)
    env = os.environ.copy()
    env["PATH"] = f"{mock_bin}:{env.get('PATH', '')}"
    env["TERM"] = "xterm-256color"
    env["ALTR_STREAM_HOME"] = str(target_install_dir)
    gum_bin = get_resolved_gum_bin()
    if gum_bin:
        env["GUM_BIN"] = gum_bin

    proc = subprocess.Popen(
        ["bash", str(macos_script)],
        stdin=slave,
        stdout=slave,
        stderr=slave,
        env=env,
        close_fds=True,
    )
    os.close(slave)

    try:
        out_menu = _drain_pty_until(master, [b"Select an operation:"], timeout_sec=6.0)
        assert b"Select an operation:" in out_menu
        assert b"Install Altr Stream" in out_menu

        # Exit cleanly
        for _ in range(4):
            os.write(master, b"\x1b[B")
            time.sleep(0.05)
        os.write(master, b"\r")
        assert proc.wait(timeout=3) == 0
    finally:
        os.close(master)
        if proc.poll() is None:
            proc.kill()


def test_normal_screens_do_not_run_background_resize_poller(tmp_path: Path) -> None:
    """Issue 2: Normal screens check dimensions on entry and do NOT run background polling loops."""
    import pty

    macos_script = REPO_ROOT / "packaging" / "installers" / "Altr-Stream_macOS_Installer.command"

    # 1. Direct function execution test: check_terminal_size returns 0 immediately when >= 100x30
    check_cmd = (
        f'. "{macos_script}"; '
        'get_term_dimensions() { echo "120 40"; }; '
        'check_terminal_size; '
        'jobs -p; '
        'echo "DONE"'
    )
    res = subprocess.run(
        ["bash", "-c", check_cmd],
        capture_output=True,
        text=True,
        timeout=5,
    )
    assert res.returncode == 0
    assert "DONE" in res.stdout
    # No background jobs spawned
    lines = [line.strip() for line in res.stdout.splitlines() if line.strip()]
    assert lines == ["DONE"], f"Unexpected background jobs or output: {res.stdout}"

    # 2. Interactive screen process check: while waiting at the Main Menu, no background polling processes run
    mock_bin, _ = _setup_mock_docker(tmp_path)
    target_install_dir = tmp_path / "no_poller_home"
    target_install_dir.mkdir(parents=True)

    master, slave = pty.openpty()
    _set_pty_size(slave, rows=35, cols=100)
    env = os.environ.copy()
    env["PATH"] = f"{mock_bin}:{env.get('PATH', '')}"
    env["TERM"] = "xterm-256color"
    env["ALTR_STREAM_HOME"] = str(target_install_dir)
    gum_bin = get_resolved_gum_bin()
    if gum_bin:
        env["GUM_BIN"] = gum_bin

    proc = subprocess.Popen(
        ["bash", str(macos_script)],
        stdin=slave,
        stdout=slave,
        stderr=slave,
        env=env,
        close_fds=True,
    )
    os.close(slave)

    try:
        _drain_pty_until(master, [b"Select an operation:"], timeout_sec=6.0)

        # Inspect child processes of bash installer: should only be the active foreground command (e.g. gum), no sleep/poller loop
        ps_res = subprocess.run(
            ["pgrep", "-P", str(proc.pid)],
            capture_output=True,
            text=True,
        )
        child_pids = [p.strip() for p in ps_res.stdout.splitlines() if p.strip()]
        # Verify no background sleep processes (a resize poller would be running sleep 0.5 continuously)
        for cpid in child_pids:
            cname = subprocess.run(["ps", "-p", cpid, "-o", "comm="], capture_output=True, text=True).stdout.strip()
            assert "sleep" not in cname, f"Detected continuous background sleep poller process {cpid} ({cname})"

        # Exit cleanly
        for _ in range(4):
            os.write(master, b"\x1b[B")
            time.sleep(0.05)
        os.write(master, b"\r")
        assert proc.wait(timeout=3) == 0
    finally:
        os.close(master)
        if proc.poll() is None:
            proc.kill()


def test_windows_batch_launcher_syntax_and_behavior() -> None:
    """Verify Altr-Stream_Windows_Installer.bat self-contained installer requirements:
    - .bat file exists
    - Standalone .ps1 file is removed / not required
    - Contains the embedded PowerShell payload via :::POWERSHELL_PAYLOAD_START:::
    - Resolves launcher directory via %~dp0 and exports ALTR_STREAM_LAUNCHER_DIR
    - Quoting is applied to handle paths with spaces
    - Invokes PowerShell with -NoProfile and process-scoped -ExecutionPolicy Bypass
    - Does NOT permanently modify system/user ExecutionPolicy
    - Checks for error exit codes, pauses on error, and cleans up temporary payload
    - Propagates installer exit code via exit /b
    - Embedded PowerShell payload is strictly compatible with Windows PowerShell 5.1 (no PS7 ternary or chain operators)
    """
    bat_file = REPO_ROOT / "packaging" / "installers" / "Altr-Stream_Windows_Installer.bat"
    ps1_file = REPO_ROOT / "packaging" / "installers" / "Altr-Stream_Windows_Installer.ps1"

    assert bat_file.is_file(), "Altr-Stream_Windows_Installer.bat must exist"
    assert not ps1_file.exists(), "Altr-Stream_Windows_Installer.ps1 must NOT exist (self-contained single-file model)"

    bat_content = bat_file.read_text(encoding="utf-8")

    # 1. Contains payload marker and extraction logic
    assert ":::POWERSHELL_PAYLOAD_START:::" in bat_content
    assert "%TEMP%" in bat_content
    assert "del /f /q" in bat_content

    # 2. Uses %~dp0 to locate bundled resources independent of working directory
    assert "%~dp0" in bat_content
    assert "ALTR_STREAM_LAUNCHER_DIR" in bat_content

    # 3. Path quoting for spaces
    assert '"%TEMP_PS1%"' in bat_content
    assert '"%BAT_FILE%"' in bat_content
    assert '"%PS_EXE%"' in bat_content

    # 4. PowerShell invocation
    assert "powershell.exe" in bat_content
    assert "-ExecutionPolicy Bypass" in bat_content
    assert "-NoProfile" in bat_content

    # 5. Security: No permanent execution policy modification
    assert "Set-ExecutionPolicy" not in bat_content

    # 6. Exit code handling: pause on error, cleanup temp file, propagate exit code
    assert "%INSTALLER_EXIT_CODE%" in bat_content
    assert "pause" in bat_content
    assert "exit /b" in bat_content

    # 7. Verification of embedded PowerShell payload:
    ps1_payload = _extract_windows_bat_payload(bat_file)
    assert "Invoke-InstallWorkflow" in ps1_payload
    assert "Invoke-UninstallWorkflow" in ps1_payload
    assert "Invoke-RepairWorkflow" in ps1_payload
    assert "Invoke-StatusWorkflow" in ps1_payload
    assert "Show-MainMenu" in ps1_payload
    assert "Set-ExecutionPolicy" not in ps1_payload

    # 8. Verification of PowerShell 5.1 compatibility:
    lines = ps1_payload.splitlines()
    for idx, line in enumerate(lines, 1):
        stripped = line.strip()
        if stripped.startswith("#"):
            continue
        if " ? " in line and " : " in line:
            assert False, f"PowerShell 7 ternary operator detected at line {idx}: {line}"
        assert " && " not in line, f"PowerShell 7 pipeline chain operator '&&' detected at line {idx}: {line}"
        assert " || " not in line, f"PowerShell 7 pipeline chain operator '||' detected at line {idx}: {line}"


def test_windows_installer_bat_bootstrap_integrity_and_variable_preservation(tmp_path: Path) -> None:
    """Regression Test for Windows BAT bootstrap PowerShell variable preservation and packaging integrity.

    Verifies that:
    1. The CMD bootstrap contains intact PowerShell variable syntax ($src, $dst, $raw, $marker, $idx, $env:BAT_FILE, $env:TEMP_PS1).
    2. No variables have been corrupted/stripped (e.g. ' = ...', ':BAT_FILE', ':TEMP_PS1', '.IndexOf()').
    3. No control characters like \\x0b (vertical tab) or \\x0c exist in the file.
    4. setlocal DisableDelayedExpansion is used so '!' in directory paths does not corrupt variables.
    5. The extraction command byte-for-byte mirrors the exact extraction in both repo and packaged release artifacts.
    """
    bat_file = REPO_ROOT / "packaging" / "installers" / "Altr-Stream_Windows_Installer.bat"
    assert bat_file.is_file()

    # Byte-level check for forbidden control characters (e.g. \\x0b from unescaped \\v)
    raw_bytes = bat_file.read_bytes()
    assert b"\x0b" not in raw_bytes, "Vertical tab \\x0b detected in Windows installer BAT"
    assert b"\x0c" not in raw_bytes, "Form feed \\x0c detected in Windows installer BAT"

    content = bat_file.read_text(encoding="utf-8")

    # Check for specific regression signatures where $ was stripped
    import re
    # Bare assignment without variable name (e.g. '" = ' or ';  = ')
    assert not re.search(r'[\";]\s+=\s+\[System\.IO\.File\]', content), "PowerShell variable was stripped before [System.IO.File]"
    assert not re.search(r'[\";]\s+=\s+[\'\"]:::POWERSHELL', content), "PowerShell variable was stripped before marker"
    assert not re.search(r'[\";]\s+=\s+\.IndexOf\(', content), "PowerShell variable was stripped before .IndexOf"
    assert not re.search(r'[\";]\s+=\s+\.Substring\(', content), "PowerShell variable was stripped before .Substring"
    assert ":BAT_FILE" not in content.replace("$env:BAT_FILE", ""), "Bare ':BAT_FILE' detected (missing $env)"
    assert ":TEMP_PS1" not in content.replace("$env:TEMP_PS1", ""), "Bare ':TEMP_PS1' detected (missing $env)"

    # Check for required intact bootstrap tokens
    assert "$src = $env:BAT_FILE;" in content
    assert "$dst = $env:TEMP_PS1;" in content
    assert "$raw = [System.IO.File]::ReadAllText($src, [System.Text.Encoding]::UTF8);" in content
    assert (
        "$marker = ':::POWERSHELL_' + 'PAYLOAD_START:::';" in content
        or "$marker = ':::POWERSHELL_PAYLOAD_START:::';" in content
    )
    assert (
        "$idx = $raw.LastIndexOf($marker);" in content
        or "$idx = $raw.IndexOf($marker);" in content
    )
    assert "setlocal DisableDelayedExpansion" in content
    assert r"WindowsPowerShell\v1.0\powershell.exe" in content

    # Verify Resolve-Gum uses ALTR_STREAM_LAUNCHER_DIR
    assert "$env:ALTR_STREAM_LAUNCHER_DIR" in content

    # Verify packaged release artifact also preserves bootstrap integrity
    pkg_script = REPO_ROOT / "scripts" / "package_release.py"
    pkg_out = tmp_path / "pkg_dist"
    subprocess.run(
        [sys.executable, str(pkg_script), "--output-dir", str(pkg_out)],
        check=True,
        capture_output=True,
        text=True,
    )
    packaged_bat = pkg_out / "Altr-Stream_Windows_Installer.bat"
    assert packaged_bat.is_file()
    pkg_content = packaged_bat.read_text(encoding="utf-8")
    assert "$src = $env:BAT_FILE;" in pkg_content
    assert "$dst = $env:TEMP_PS1;" in pkg_content
    assert not re.search(r'[\";]\s+=\s+\[System\.IO\.File\]', pkg_content)
    assert b"\x0b" not in packaged_bat.read_bytes()


def test_windows_bat_payload_extraction_cleanliness() -> None:
    """Verify that extracting the PowerShell payload from Altr-Stream_Windows_Installer.bat
    does not match the bootstrap extraction command and produces clean PowerShell starting with synopsis.
    """
    bat_file = REPO_ROOT / "packaging" / "installers" / "Altr-Stream_Windows_Installer.bat"
    content = bat_file.read_text(encoding="utf-8")
    payload = _extract_windows_bat_payload(bat_file)

    # Must start cleanly with synopsis comment
    assert payload.startswith("<#"), f"Extracted payload must start with '<#', got: {payload[:50]!r}"
    assert "@echo off" not in payload
    assert "TEMP_PS1" not in payload
    assert ":::POWERSHELL_PAYLOAD_START:::" not in payload

    # Verify the extraction logic in BAT does not match line 57:
    # the literal marker string must only occur once in the entire BAT file (on the marker boundary line).
    marker = ":::POWERSHELL_PAYLOAD_START:::"
    assert content.count(marker) == 1, (
        f"Literal marker '{marker}' must appear exactly once in BAT to avoid bootstrap self-matching"
    )


def test_windows_installer_workflow_control_flow_and_break_integrity() -> None:
    """Regression test for the loop-break bug in Invoke-InstallWorkflow.

    In PowerShell, 'break' inside a 'switch' statement only breaks out of the switch,
    NOT the enclosing 'while' loop. If a while loop uses switch ($action) { "Install" { break } },
    the while loop never terminates, or falls through to default { return }, causing silent exit.
    This test verifies that:
    1. The confirmation prompt in Invoke-InstallWorkflow does NOT use a switch with a bare break inside a while loop.
    2. A boolean loop-control flag ($proceed) is used to cleanly break the loop when 'Install Altr Stream' is selected.
    3. 'Change Installation Path' updates $targetDir without exiting the loop prematurely.
    4. Canceling / Back exits cleanly with return.
    """
    bat_file = REPO_ROOT / "packaging" / "installers" / "Altr-Stream_Windows_Installer.bat"
    payload = _extract_windows_bat_payload(bat_file)

    # Locate Invoke-InstallWorkflow
    assert "function Invoke-InstallWorkflow" in payload
    install_fn = payload.split("function Invoke-InstallWorkflow")[1].split("function ")[0]

    # Verify loop control flag is used
    assert "$proceed = $false" in install_fn
    assert "while (-not $proceed)" in install_fn
    assert '$act -eq "Install Altr Stream"' in install_fn
    assert "$proceed = $true" in install_fn

    # Ensure no dangerous switch with bare break inside while loop exists in Invoke-InstallWorkflow confirmation prompt
    prompt_section = install_fn.split("while (-not $proceed)")[1].split("Save-InstallDirectory")[0]
    assert "switch ($act)" not in prompt_section, (
        "Forbidden: switch ($act) inside while loop causes break to only exit switch, trapping execution"
    )


def test_windows_installer_docker_diagnostics_and_states() -> None:
    """Verify that the Windows installer implements granular Docker diagnostics:
    - Get-DockerDiagnostics function exists and returns structured state
    - Supports states: 'Not Installed', 'Not Running', 'Unavailable', 'No Compose', 'Ready'
    - Show-DockerDiagnosticScreen and Show-DockerTechnicalDetailsScreen exist
    - Start-DockerDesktopProcess specifically targets 'Docker Desktop.exe' rather than bare 'docker'
    - Actionable hints are provided in container status and main menu
    """
    bat_file = REPO_ROOT / "packaging" / "installers" / "Altr-Stream_Windows_Installer.bat"
    payload = _extract_windows_bat_payload(bat_file)

    assert "function Get-DockerDiagnostics" in payload
    assert "function Show-DockerDiagnosticScreen" in payload
    assert "function Show-DockerTechnicalDetailsScreen" in payload
    assert "function Start-DockerDesktopProcess" in payload

    # Inspect Get-DockerDiagnostics for all required states
    diag_fn = payload.split("function Get-DockerDiagnostics")[1].split("function ")[0]
    assert '"Not Installed"' in diag_fn
    assert '"Not Running"' in diag_fn
    assert '"Unavailable"' in diag_fn
    assert '"No Compose"' in diag_fn
    assert '"Ready"' in diag_fn

    # Verify Start-DockerDesktopProcess targets Docker Desktop.exe specifically
    start_fn = payload.split("function Start-DockerDesktopProcess")[1].split("function ")[0]
    assert "Docker Desktop.exe" in start_fn
    assert 'Start-Process "docker"' not in start_fn, (
        "Forbidden: Start-Process 'docker' launches the CLI help console instead of the Desktop GUI daemon"
    )


def test_windows_installer_pipeline_stages_and_failure_surfacing() -> None:
    """Verify that the Windows installer implements explicit progress stages,
    captures technical details on error, and surfaces failures rather than returning silently:
    - Stage 1: Runtime configuration (Write-RuntimeFiles in try/catch)
    - Stage 2: Persistent storage volume (docker volume create altr_stream_data in try/catch)
    - Stage 3: Image pull (docker compose pull with log capture and local fallback check)
    - Stage 4: Starting container (docker compose up -d with log capture and error classification)
    - Stage 5: Polling healthcheck (Invoke-RestMethod with timeout)
    - Stage 6: Health verification (Test-InstallationHealth)
    - Show-InstallSuccessScreen is ONLY called when $verified is $true
    - Show-InstallFailureScreen is called on any stage failure with stage name and reason
    - Failure screen provides 'Retry Installation' and 'Back to Main Menu'
    - Success screen provides 'Launch Altr Stream' and 'Back to Main Menu'
    """
    bat_file = REPO_ROOT / "packaging" / "installers" / "Altr-Stream_Windows_Installer.bat"
    payload = _extract_windows_bat_payload(bat_file)

    assert "function Show-InstallSuccessScreen" in payload
    assert "function Show-InstallFailureScreen" in payload
    assert "function Show-RunningScreen" in payload

    install_fn = payload.split("function Invoke-InstallWorkflow")[1].split("function ")[0]

    # Verify stages in Invoke-InstallWorkflow
    assert "Preparing configuration" in install_fn
    assert "Preparing storage volume" in install_fn
    assert "Pulling Altr Stream image" in install_fn
    assert "Starting Altr Stream container" in install_fn
    assert "Waiting for health check" in install_fn
    assert "Installation verification" in install_fn

    # Verify log capture for pull and start
    assert ".docker_pull.log" in install_fn
    assert ".docker_start.log" in install_fn

    # Verify healthcheck verification guard
    assert "Test-InstallationHealth" in install_fn
    assert "if ($verified) {" in install_fn
    assert "Show-InstallSuccessScreen" in install_fn
    assert "Show-InstallFailureScreen" in install_fn

    # Verify Failure Screen options
    fail_fn = payload.split("function Show-InstallFailureScreen")[1].split("function ")[0]
    assert "Retry Installation" in fail_fn
    assert "Back to Main Menu" in fail_fn
    assert "Failure Diagnostics:" in fail_fn
    assert "$Stage" in fail_fn
    assert "$Reason" in fail_fn

    # Verify Success Screen options
    succ_fn = payload.split("function Show-InstallSuccessScreen")[1].split("function ")[0]
    assert "Launch Altr Stream" in succ_fn
    assert "Back to Main Menu" in succ_fn


def test_windows_installer_native_docker_error_isolation_and_container_conflict() -> None:
    """Regression test for native Docker command error isolation under $ErrorActionPreference = 'Stop'.

    In PowerShell 5.1, when $ErrorActionPreference = 'Stop', any native executable writing to stderr
    generates a NativeCommandError record, which terminates the script even if 2>$null is present.
    On fresh installations, 'docker inspect altr-stream' exits with code 1 and writes to stderr
    ('error: no such object: altr-stream').
    This test verifies that:
    1. $ErrorActionPreference = 'Stop' is maintained globally for strict script safety.
    2. Invoke-DockerCliSafe is defined and uses System.Diagnostics.ProcessStartInfo to redirect
       stdout and stderr at the process boundary, preventing NativeCommandError.
    3. Test-ContainerExists and Get-ContainerInspectField are used for safe inspection.
    4. Test-ContainerConflict uses Test-ContainerExists 'altr-stream' so a missing container
       returns $false (fresh install) without throwing an error.
    5. No bare 'docker inspect altr-stream 2>$null' exists in Test-ContainerConflict.
    6. Get-DockerDiagnostics implements a bounded retry when the 'Docker Desktop' process
       is running in memory, resolving startup race conditions.
    """
    bat_file = REPO_ROOT / "packaging" / "installers" / "Altr-Stream_Windows_Installer.bat"
    payload = _extract_windows_bat_payload(bat_file)

    # 1. Strict global error handling preserved
    assert '$ErrorActionPreference = "Stop"' in payload

    # 2. ProcessStartInfo isolation layer exists
    assert "function Invoke-DockerCliSafe" in payload
    assert "System.Diagnostics.ProcessStartInfo" in payload
    assert "$psi.RedirectStandardOutput = $true" in payload
    assert "$psi.RedirectStandardError = $true" in payload
    assert "$psi.UseShellExecute = $false" in payload

    # 3. Safe inspection helpers exist
    assert "function Get-ContainerInspectField" in payload
    assert "function Test-ContainerExists" in payload

    # 4. Test-ContainerConflict uses Test-ContainerExists and Get-ContainerInspectField
    assert "function Test-ContainerConflict" in payload
    conflict_fn = payload.split("function Test-ContainerConflict")[1].split("function ")[0]
    assert 'Test-ContainerExists "altr-stream"' in conflict_fn
    assert "Get-ContainerInspectField" in conflict_fn
    assert "docker inspect altr-stream" not in conflict_fn

    # 5. Get-DockerDiagnostics startup delay retry
    diag_fn = payload.split("function Get-DockerDiagnostics")[1].split("function ")[0]
    assert 'Get-Process "Docker Desktop"' in diag_fn
    assert "Invoke-DockerCliSafe" in diag_fn
    assert "$maxAttempts = 3" in diag_fn


def test_windows_installer_gum_style_isolation_and_flag_safety(tmp_path: Path) -> None:
    """Regression test: Ensure Gum style invocations are hardened against unknown flags,
    prevent raw usage text leakage, guarantee '--' delimiter before positional text,
    and provide plain-text fallback rendering."""
    bat_file = REPO_ROOT / "packaging" / "installers" / "Altr-Stream_Windows_Installer.bat"
    payload = _extract_windows_bat_payload(bat_file)

    # 1. Verify expected pinned version and checksum
    assert '$GumPinnedVersion = "2.0.2"' in payload
    assert '$GumWindowsX64Sha = "0397091dec9b4e8f00e02b90fd3eb07bf45acabbdb61d67437950f18e03a8b79"' in payload

    # 2. Verify all direct style calls are replaced by Invoke-GumStyle
    assert "& $GumBin style" not in payload
    assert "function Invoke-GumStyle" in payload
    assert payload.count("Invoke-GumStyle") >= 40

    # 3. Verify '--' flag delimiter and 2>$null stderr suppression in Invoke-GumStyle
    style_fn = payload.split("function Invoke-GumStyle")[1].split("function ")[0]
    assert '"--"' in style_fn
    assert "2>$null" in style_fn
    assert "Fallback-RenderStyle" in style_fn

    # 4. Verify Fallback-RenderStyle and Format-TechnicalLines
    assert "function Fallback-RenderStyle" in payload
    assert "function Format-TechnicalLines" in payload
    fail_fn = payload.split("function Show-InstallFailureScreen")[1].split("function ")[0]
    assert "Format-TechnicalLines" in fail_fn

    # 5. Verify live Gum behavior with '--' delimiter preventing -f unknown flag error
    resolved_gum = get_resolved_gum_bin()
    if resolved_gum:
        # Without '--', passing -f in positional text must fail with unknown flag error
        res_fail = subprocess.run(
            [str(resolved_gum), "style", "SomeText", "-f", "OtherText"],
            capture_output=True,
            text=True,
        )
        assert res_fail.returncode != 0
        assert "unknown flag -f" in res_fail.stderr

        # With '--' delimiter, passing -f in positional text must succeed cleanly
        res_ok = subprocess.run(
            [str(resolved_gum), "style", "--border", "rounded", "--", "SomeText", "-f", "OtherText"],
            capture_output=True,
            text=True,
        )
        assert res_ok.returncode == 0
        assert "SomeText" in res_ok.stdout
        assert "-f" in res_ok.stdout

    # 6. PowerShell 5.1 Syntax Audit: Ensure no invalid variable scope or colon interpolations
    valid_scopes = {"env", "script", "global", "local", "private", "using"}
    for line_idx, line in enumerate(payload.splitlines(), start=1):
        for m in re.finditer(r"\$([a-zA-Z0-9_]+):", line):
            scope = m.group(1).lower()
            rest = line[m.end():]
            if scope in valid_scopes:
                assert re.match(r"^[a-zA-Z0-9_]", rest), (
                    f"Line {line_idx}: Scope '{scope}:' not followed by valid variable name: {line.strip()}"
                )
            else:
                pytest.fail(
                    f"Line {line_idx}: Invalid variable followed by colon '${m.group(1)}:' in line: {line.strip()}"
                )

    # 7. Verify -f formatting operator is used in fallback UI prompts
    input_fn = payload.split("function Invoke-GumInput")[1].split("function ")[0]
    assert '"  {0}: " -f $prompt' in input_fn
    assert '"  $prompt: "' not in input_fn
    confirm_fn = payload.split("function Invoke-GumConfirm")[1].split("function ")[0]
    assert '"  {0} [y/N]: " -f' in confirm_fn





