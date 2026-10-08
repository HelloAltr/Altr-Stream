"""Tests for the native macOS application wrapper (Altr Stream.app) and Go engine integration."""

from __future__ import annotations

import json
import os
import platform
import plistlib
import subprocess
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parent.parent.parent


@pytest.fixture(scope="module")
def macos_app_bundle() -> Path:
    """Build the macOS application bundle for testing."""
    if platform.system() != "Darwin":
        pytest.skip("macOS app tests require macOS host")

    dist_dir = REPO_ROOT / "dist"
    app_path = dist_dir / "Altr Stream.app"

    # Run the build script
    build_script = REPO_ROOT / "scripts" / "build_macos_app.py"
    cmd = [
        "python3",
        str(build_script),
        "--version",
        "1.0.0-beta",
        "--image",
        "ghcr.io/helloaltr/altr-stream:0.13.7-alpha",
        "--output-dir",
        str(dist_dir),
    ]
    result = subprocess.run(cmd, cwd=REPO_ROOT, capture_output=True, text=True)
    assert result.returncode == 0, f"App build failed:\nstdout: {result.stdout}\nstderr: {result.stderr}"
    assert app_path.is_dir(), f"Expected app bundle at {app_path}"
    return app_path


def test_app_bundle_structure(macos_app_bundle: Path) -> None:
    """Verify Altr Stream.app conforms to standard macOS application bundle layout."""
    contents = macos_app_bundle / "Contents"
    macos_dir = contents / "MacOS"
    resources_dir = contents / "Resources"
    info_plist = contents / "Info.plist"

    assert contents.is_dir()
    assert macos_dir.is_dir()
    assert resources_dir.is_dir()
    assert info_plist.is_file()

    # Executable check
    app_bin = macos_dir / "Altr Stream"
    assert app_bin.is_file()
    assert os.access(app_bin, os.X_OK)

    # Embedded Go engine check
    engine_bin = resources_dir / "altr-installer-engine"
    assert engine_bin.is_file()
    assert os.access(engine_bin, os.X_OK)


def test_app_info_plist_metadata(macos_app_bundle: Path) -> None:
    """Verify Info.plist contains proper bundle metadata and versioning."""
    plist_path = macos_app_bundle / "Contents" / "Info.plist"
    with open(plist_path, "rb") as f:
        plist_data = plistlib.load(f)

    assert plist_data.get("CFBundleIdentifier") == "com.helloaltr.altr-stream"
    assert plist_data.get("CFBundleExecutable") == "Altr Stream"
    assert plist_data.get("CFBundlePackageType") == "APPL"
    assert plist_data.get("CFBundleShortVersionString") == "1.0.0-beta"


def test_binary_architectures(macos_app_bundle: Path) -> None:
    """Verify both the Swift wrapper and Go engine match host Mach-O architecture."""
    app_bin = macos_app_bundle / "Contents" / "MacOS" / "Altr Stream"
    engine_bin = macos_app_bundle / "Contents" / "Resources" / "altr-installer-engine"

    host_machine = platform.machine().lower()
    expected_arch = "arm64" if host_machine in ("arm64", "aarch64") else "x86_64"

    for binary in (app_bin, engine_bin):
        res = subprocess.run(["file", str(binary)], capture_output=True, text=True, check=True)
        assert "Mach-O 64-bit executable" in res.stdout
        assert expected_arch in res.stdout or (expected_arch == "x86_64" and "amd64" in res.stdout)


def test_embedded_engine_execution(macos_app_bundle: Path) -> None:
    """Verify the embedded engine binary executes from inside the bundle and emits valid JSON."""
    engine_bin = macos_app_bundle / "Contents" / "Resources" / "altr-installer-engine"

    res = subprocess.run([str(engine_bin), "detect-env"], capture_output=True, text=True, check=True)
    data = json.loads(res.stdout)
    assert data["os"] == "darwin"
    assert "user_home" in data
    assert "effective_dir" in data

    res_diag = subprocess.run([str(engine_bin), "check-docker"], capture_output=True, text=True, check=True)
    diag_data = json.loads(res_diag.stdout)
    assert "state" in diag_data
    assert diag_data["state"] in ("ready", "stopped", "not_installed")


def test_swift_code_architecture_and_constraints() -> None:
    """Verify Swift source code adheres to architecture requirements and handles states."""
    swift_dir = REPO_ROOT / "packaging" / "macos" / "AltrStreamApp" / "Sources"

    models_src = (swift_dir / "Models.swift").read_text(encoding="utf-8")
    bridge_src = (swift_dir / "EngineBridge.swift").read_text(encoding="utf-8")
    appstate_src = (swift_dir / "AppState.swift").read_text(encoding="utf-8")
    views_src = (swift_dir / "ContentView.swift").read_text(encoding="utf-8")

    # 1. Models map Go engine contract
    assert "struct DockerDiagnostics: Codable" in models_src
    assert "struct InstallProgress: Codable" in models_src
    assert "struct NodeStatus: Codable" in models_src
    assert "struct EnvironmentInfo: Codable" in models_src
    assert "struct ConflictInfo: Codable" in models_src
    assert "var isPortConflict: Bool" in models_src
    assert 'conflictType == "port_docker"' in models_src
    assert 'conflictType == "port_process"' in models_src
    assert "Port Conflict Detected" in views_src

    # 2. Engine bridge resolution and non-blocking process invocation
    assert 'Bundle.main.path(forResource: "altr-installer-engine", ofType: nil)' in bridge_src
    assert "func streamCommand" in bridge_src
    assert "withCheckedThrowingContinuation" in bridge_src
    assert "DispatchQueue.global(qos: .userInitiated).async" in bridge_src

    # 3. Dedicated commands invoked correctly
    assert '"install", "--json"' in bridge_src
    assert '"repair", "--json"' in bridge_src
    assert '"launch-docker"' in bridge_src
    assert '"open-docker-settings"' in bridge_src
    assert '"check-docker"' in bridge_src
    assert '"detect-env"' in bridge_src
    assert '"uninstall"' in bridge_src
    assert '"status"' in bridge_src

    # 4. AppState reactive state machine covers all required states
    for state_case in [
        "case checking",
        "case dockerNotInstalled",
        "case dockerPaused",
        "case dockerStopped",
        "case startingDocker",
        "case readyToInstall",
        "case installing",
        "case repairing",
        "case running",
        "case paused",
        "case stopped",
        "case fileSharingRequired",
        "case failed",
    ]:
        assert state_case in appstate_src

    # 4b. ContainerLifecycleState model and accurate mapping
    assert "enum ContainerLifecycleState: String, Codable" in models_src
    assert 'case paused = "paused"' in models_src
    assert 'case running = "running"' in models_src
    assert 'case exited = "exited"' in models_src
    assert "Altr Stream Node is Paused" in views_src
    assert "Resume Node" in views_src
    assert "Altr Stream Node is Stopped" in views_src
    assert "func unpauseContainer()" in bridge_src
    assert "func resumeContainer()" in appstate_src

    # 4c. Docker Desktop Paused state and action
    assert "isPaused" in models_src
    assert "Docker Desktop is Paused" in views_src
    assert "Resume Docker Desktop" in views_src
    assert "func unpauseDockerDesktop()" in bridge_src
    assert "func resumeDockerDesktop()" in appstate_src

    # 5. Non-blocking Docker startup with bounded polling
    assert "func startDockerDesktop()" in appstate_src
    assert "maxWaitSec = 75" in appstate_src
    assert "Task.sleep(nanoseconds: 1_000_000_000)" in appstate_src

    # 6. FILE_SHARING_REQUIRED friendly mapping
    assert "FILE_SHARING_REQUIRED" in bridge_src
    assert "case .fileSharingRequired(let message, let path):" in views_src
    assert "Open Docker Settings" in views_src

    # 7. Technical Details sheet availability
    assert "Technical Details" in views_src
    assert "technicalDetailsSheet" in views_src
    assert "Copy to Clipboard" in views_src

    # 8. Safe uninstall semantics: default preserves data; explicit confirmation required for purge
    assert "Delete persistent application data" in views_src
    assert "DELETE ALTR STREAM DATA" in views_src
    assert "altr_stream_data" in views_src


def test_no_forbidden_dependencies_or_secrets() -> None:
    """Verify the Swift application contains no embedded secrets, tokens, or external runtimes."""
    swift_dir = REPO_ROOT / "packaging" / "macos" / "AltrStreamApp" / "Sources"
    combined_code = ""
    for f in swift_dir.glob("*.swift"):
        combined_code += f.read_text(encoding="utf-8")

    forbidden = [
        "github_pat_",
        "ghp_",
        "AIzaSy",
        "BEGIN OPENSSH PRIVATE KEY",
        "BEGIN RSA PRIVATE KEY",
        "password",
        "secret_key",
    ]
    for term in forbidden:
        assert term not in combined_code


def test_macos_engine_gui_restricted_path_and_clean_environment(tmp_path: Path) -> None:
    """Verify Go engine works under macOS GUI restricted PATH and isolates user environment."""
    out_bin = tmp_path / "altr-installer-engine"
    build_env = os.environ.copy()
    build_env["GOPATH"] = str(tmp_path / "gopath")
    build_res = subprocess.run(
        ["go", "build", "-o", str(out_bin), "."],
        cwd=str(REPO_ROOT / "packaging" / "engine"),
        env=build_env,
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert build_res.returncode == 0

    isolated_home = tmp_path / "gui_home"
    isolated_home.mkdir(parents=True, exist_ok=True)

    # Simulate restricted GUI app PATH (launchd / Finder)
    gui_env = {
        "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
        "HOME": str(isolated_home),
        "USERPROFILE": str(isolated_home),
    }

    # 1. detect-env must resolve cleanly to default $HOME/.altr-stream
    detect_res = subprocess.run([str(out_bin), "detect-env"], env=gui_env, capture_output=True, text=True, timeout=10)
    assert detect_res.returncode == 0
    env_info = json.loads(detect_res.stdout)
    assert env_info["default_dir"] == str(isolated_home / ".altr-stream")
    assert env_info["effective_dir"] == str(isolated_home / ".altr-stream")
    assert "inst_target" not in env_info["effective_dir"]

    # 2. check-docker under restricted GUI PATH
    check_res = subprocess.run([str(out_bin), "check-docker"], env=gui_env, capture_output=True, text=True, timeout=10)
    assert check_res.returncode == 0
    diag = json.loads(check_res.stdout)
    # If Docker CLI or Desktop is installed on the host, CLI or Desktop must be detected even without /usr/local/bin or /opt/homebrew/bin in PATH
    if Path("/Applications/Docker.app").is_dir():
        assert diag["desktop_installed"] is True
    if Path("/opt/homebrew/bin/docker").is_file() or Path("/usr/local/bin/docker").is_file():
        assert diag["cli_installed"] is True
        assert diag["compose_available"] is True
        assert diag["compose_command"] != ""


def test_macos_app_window_termination_and_no_quit_button() -> None:
    """Verify Quit button is removed from UI and window close terminates the application."""
    app_swift = (REPO_ROOT / "packaging" / "macos" / "AltrStreamApp" / "Sources" / "AltrStreamApp.swift").read_text(encoding="utf-8")
    content_swift = (REPO_ROOT / "packaging" / "macos" / "AltrStreamApp" / "Sources" / "ContentView.swift").read_text(encoding="utf-8")

    # 1. Ensure window close delegate terminates application
    assert "applicationShouldTerminateAfterLastWindowClosed" in app_swift
    assert "@NSApplicationDelegateAdaptor" in app_swift

    # 2. Ensure custom Quit button was removed from ContentView
    assert 'Button("Quit")' not in content_swift


def test_macos_app_running_state_action_buttons_uniform() -> None:
    """Verify running-state buttons use reusable .actionButton() modifier with consistent geometry."""
    content_swift = (REPO_ROOT / "packaging" / "macos" / "AltrStreamApp" / "Sources" / "ContentView.swift").read_text(encoding="utf-8")

    assert "struct RunningActionButtonModifier: ViewModifier" in content_swift
    assert "func actionButton(minWidth: CGFloat = 130)" in content_swift
    assert 'Button("Open Altr Stream")' in content_swift
    assert 'Button("Repair")' in content_swift
    assert 'Button("Uninstall...")' in content_swift
    # Verify neither uses .controlSize(.large) in running state
    assert ".controlSize(.large)" not in content_swift.split("case .running")[1].split("case .paused")[0]


def test_macos_app_custom_directory_persistence(tmp_path: Path) -> None:
    """Verify custom install location is read from .altr-stream-config and used across operations."""
    engine_bin = REPO_ROOT / "dist" / "altr-installer-engine"
    if not engine_bin.exists():
        engine_bin = REPO_ROOT / "dist" / "Altr Stream.app" / "Contents" / "Resources" / "altr-installer-engine"
    if not engine_bin.exists():
        pytest.skip("Packaged engine binary not built")

    isolated_home = tmp_path / "custom_home"
    isolated_home.mkdir(parents=True, exist_ok=True)
    custom_install_dir = tmp_path / "custom_apps" / "altr-stream"
    custom_install_dir.mkdir(parents=True, exist_ok=True)

    # Place a dummy docker-compose.yml so engine validates it as active installation
    (custom_install_dir / "docker-compose.yml").write_text("version: '3.8'\nservices:\n  altr-stream:\n", encoding="utf-8")
    (isolated_home / ".altr-stream-config").write_text(str(custom_install_dir), encoding="utf-8")

    env = os.environ.copy()
    env["HOME"] = str(isolated_home)
    env["USERPROFILE"] = str(isolated_home)
    env["ALTR_STREAM_ALLOW_TMP_DIR"] = "1"

    detect_res = subprocess.run([str(engine_bin), "detect-env"], env=env, capture_output=True, text=True, timeout=10)
    assert detect_res.stdout
    env_data = json.loads(detect_res.stdout)
    assert env_data["effective_dir"] == str(custom_install_dir)
    assert env_data["saved_dir"] == str(custom_install_dir)


def test_macos_app_archive_integrity(tmp_path: Path, macos_app_bundle: Path) -> None:
    """Verify that the generated macOS app zip archive preserves bundle structure and permissions."""
    archive_path = REPO_ROOT / "dist" / "Altr-Stream_macOS_Installer.app.zip"
    if not archive_path.is_file():
        from scripts.build_macos_app import archive_app_bundle
        archive_app_bundle(macos_app_bundle, archive_path)

    assert archive_path.is_file()
    assert archive_path.stat().st_size > 500_000

    # Extract to tmp_path and verify permissions
    extract_dir = tmp_path / "extracted_app"
    extract_dir.mkdir(parents=True, exist_ok=True)
    subprocess.run(["unzip", "-q", str(archive_path), "-d", str(extract_dir)], check=True)

    extracted_bundle = list(extract_dir.glob("*.app"))
    assert len(extracted_bundle) == 1, f"Expected 1 .app bundle, found: {extracted_bundle}"
    app = extracted_bundle[0]
    assert app.name in ("Altr Stream Installer.app", "Altr Stream.app")

    exe_bin = app / "Contents" / "MacOS" / "Altr Stream"
    engine_bin = app / "Contents" / "Resources" / "altr-installer-engine"
    plist_file = app / "Contents" / "Info.plist"

    assert exe_bin.is_file()
    assert os.access(exe_bin, os.X_OK), "Main binary lost executable permission in zip"
    assert engine_bin.is_file()
    assert os.access(engine_bin, os.X_OK), "Embedded Go engine lost executable permission in zip"
    assert plist_file.is_file()


def test_macos_pkg_creation_and_integrity(tmp_path: Path, macos_app_bundle: Path) -> None:
    """Verify that the native macOS .pkg installer is created and has valid size."""
    pkg_path = REPO_ROOT / "dist" / "Altr-Stream-Installer.pkg"
    if not pkg_path.is_file():
        from scripts.build_macos_app import build_pkg_installer
        build_pkg_installer(macos_app_bundle, pkg_path, version="1.0.1-beta")

    assert pkg_path.is_file()
    assert pkg_path.stat().st_size > 500_000


def test_macos_pkg_payload_and_metadata(tmp_path: Path, macos_app_bundle: Path) -> None:
    """Verify macOS .pkg package metadata, payload structure, permissions, and install location."""
    pkg_path = REPO_ROOT / "dist" / "Altr-Stream-Installer.pkg"
    if not pkg_path.is_file():
        from scripts.build_macos_app import build_pkg_installer
        build_pkg_installer(macos_app_bundle, pkg_path, version="1.0.1-beta")

    expand_dir = tmp_path / "expanded_pkg"
    if expand_dir.exists():
        import shutil
        shutil.rmtree(expand_dir)

    # Use native pkgutil to expand package fully (pkgutil creates destination dir)
    subprocess.run(["pkgutil", "--expand-full", str(pkg_path), str(expand_dir)], check=True)

    # 1. Verify Distribution XML metadata
    dist_file = expand_dir / "Distribution"
    assert dist_file.is_file(), "Distribution file missing from expanded product archive"
    dist_content = dist_file.read_text(encoding="utf-8")
    assert 'id="com.helloaltr.altr-stream"' in dist_content
    assert 'path="Altr Stream.app"' in dist_content

    # 2. Locate component package directory
    component_pkgs = list(expand_dir.glob("*.pkg"))
    assert len(component_pkgs) >= 1, "No component package found inside expanded product archive"
    comp_dir = component_pkgs[0]

    # 3. Verify PackageInfo metadata
    pkg_info_file = comp_dir / "PackageInfo"
    assert pkg_info_file.is_file(), "PackageInfo missing from component package"
    pkg_info_content = pkg_info_file.read_text(encoding="utf-8")
    assert 'install-location="/Applications"' in pkg_info_content
    assert 'identifier="com.helloaltr.altr-stream"' in pkg_info_content
    assert 'path="./Altr Stream.app"' in pkg_info_content
    assert '<postinstall file="./postinstall"' in pkg_info_content

    # 4. Verify postinstall script presence and permissions
    postinstall_script = comp_dir / "Scripts" / "postinstall"
    assert postinstall_script.is_file(), "postinstall script missing from package scripts"
    assert os.access(postinstall_script, os.X_OK), "postinstall script is not executable"
    postinstall_content = postinstall_script.read_text(encoding="utf-8")
    # Verify postinstall does not contain Docker install/launch logic
    assert "docker" not in postinstall_content.lower(), "postinstall script must not manage Docker engine lifecycle"
    assert "open " not in postinstall_content, "postinstall script must not auto-launch application"

    # 5. Verify Payload structure (/Applications/Altr Stream.app)
    payload_dir = comp_dir / "Payload"
    assert payload_dir.is_dir(), "Payload directory missing"
    installed_app = payload_dir / "Altr Stream.app"
    assert installed_app.is_dir(), "Payload does not contain Altr Stream.app bundle"

    # 6. Verify embedded executable and altr-installer-engine
    contents_dir = installed_app / "Contents"
    app_bin = contents_dir / "MacOS" / "Altr Stream"
    engine_bin = contents_dir / "Resources" / "altr-installer-engine"
    plist_file = contents_dir / "Info.plist"

    assert app_bin.is_file(), "Contents/MacOS/Altr Stream missing from package payload"
    assert engine_bin.is_file(), "Contents/Resources/altr-installer-engine missing from package payload"
    assert plist_file.is_file(), "Contents/Info.plist missing from package payload"

    # 7. Verify executable permissions in package payload
    assert os.access(app_bin, os.X_OK), "Main binary lost executable permission in pkg payload"
    assert os.access(engine_bin, os.X_OK), "Embedded Go engine lost executable permission in pkg payload"
    assert app_bin.stat().st_mode & 0o111, "Executable bits missing on Altr Stream"
    assert engine_bin.stat().st_mode & 0o111, "Executable bits missing on altr-installer-engine"



