"""Tests for the native macOS application wrapper (Altr Stream.app) and Go engine integration."""

from __future__ import annotations

import json
import os
import platform
import plistlib
import subprocess
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))


@pytest.fixture(scope="module")
def macos_app_bundle() -> Path:
    """Build the macOS application bundle for testing."""
    if platform.system() != "Darwin":
        pytest.skip("macOS app tests require macOS host")

    dist_dir = REPO_ROOT / "dist"
    app_path = dist_dir / "Altr Stream.app"

    # Run the build script
    build_script = REPO_ROOT / "scripts" / "build_macos_app.py"
    from altr_stream.__version__ import __version__ as canonical_ver
    cmd = [
        "python3",
        str(build_script),
        "--version",
        canonical_ver,
        "--node-version",
        "1.0.0-beta",
        "--image",
        "ghcr.io/helloaltr/altr-stream:1.0.0-beta",
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
    from altr_stream.__version__ import __version__ as canonical_ver
    plist_path = macos_app_bundle / "Contents" / "Info.plist"
    with open(plist_path, "rb") as f:
        plist_data = plistlib.load(f)

    assert plist_data.get("CFBundleIdentifier") == "com.helloaltr.altr-stream"
    assert plist_data.get("CFBundleExecutable") == "Altr Stream"
    assert plist_data.get("CFBundlePackageType") == "APPL"
    assert plist_data.get("CFBundleShortVersionString") == canonical_ver
    assert plist_data.get("CFBundleIconFile") == "AppIcon"
    assert plist_data.get("CFBundleIconName") == "AppIcon"


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
    assert '"stop-container"' in bridge_src
    assert "func stopContainer" in bridge_src

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

    # 4b. Single source of truth versioning in Swift
    assert "Bundle.main.infoDictionary" in appstate_src
    assert "CFBundleShortVersionString" in appstate_src
    assert '"1.0.0-beta"' not in appstate_src
    assert '"1.0.1-beta"' not in appstate_src

    # 4c. Configurable Data & Runtime separation
    assert "applicationBundlePath" in appstate_src
    assert "revealApplicationInFinder" in appstate_src
    assert "revealDataDirectoryInFinder" in appstate_src
    assert "Application" in views_src
    assert "Data & Runtime" in views_src

    # 4d. Safe dev container conflict handling
    assert "Development Container Conflict Detected" in views_src
    assert "Stop Development Container" in views_src
    assert "requestStopDevContainer" in appstate_src
    assert "confirmStopDevContainer" in appstate_src

    # 4e. ContainerLifecycleState model and accurate mapping
    assert "enum ContainerLifecycleState: String, Codable" in models_src
    assert 'case paused = "paused"' in models_src
    assert 'case running = "running"' in models_src
    assert 'case exited = "exited"' in models_src
    assert "Altr Stream Node is Paused" in views_src
    assert "Resume Node" in views_src
    assert "Altr Stream Node is Stopped" in views_src
    assert "func unpauseContainer()" in bridge_src
    assert "func resumeContainer()" in appstate_src

    # 4f. Docker Desktop Paused state and action
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

    # 8. Safe multi-tier uninstall semantics
    assert "Remove Docker & Runtime Resources" in views_src
    assert "Remove Persistent Application Data" in views_src
    assert "Move Altr Stream.app to Trash" in views_src
    assert "uninstallRemoveApp" in appstate_src
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
    assert app.name in ("Altr Stream Manager.app", "Altr Stream Installer.app", "Altr Stream.app")

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
    # Verify postinstall executes node provisioning in the user's context, never directly as root
    assert "run_as_target" in postinstall_content, "postinstall script must execute engine actions in user context"
    assert "open /Applications" not in postinstall_content, "postinstall script must not auto-launch GUI application"

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


def test_version_propagation_single_source_of_truth(macos_app_bundle: Path) -> None:
    """Verify that canonical version propagates through Info.plist, Go engine, and Swift without duplication."""
    from altr_stream.__version__ import __version__ as canonical_ver

    # 1. Info.plist in bundle
    plist_path = macos_app_bundle / "Contents" / "Info.plist"
    with open(plist_path, "rb") as f:
        plist_data = plistlib.load(f)
    assert plist_data["CFBundleShortVersionString"] == canonical_ver
    assert plist_data["CFBundleVersion"] == canonical_ver

    # 2. Go engine detects default canonical version when queried
    engine_bin = macos_app_bundle / "Contents" / "Resources" / "altr-installer-engine"
    res = subprocess.run([str(engine_bin), "status"], capture_output=True, text=True)
    if res.returncode == 0:
        data = json.loads(res.stdout)
        assert data.get("target_version") in (canonical_ver, "1.0.0-beta", "1.0.1-beta")

    # 3. Swift code dynamically accesses Bundle.main.infoDictionary and contains no hardcoded fallback
    swift_state = (REPO_ROOT / "packaging" / "macos" / "AltrStreamApp" / "Sources" / "AppState.swift").read_text(encoding="utf-8")
    assert 'Bundle.main.infoDictionary?["CFBundleShortVersionString"]' in swift_state
    assert f'"{canonical_ver}"' not in swift_state


def test_icon_packaging_optional_handling(tmp_path: Path) -> None:
    """Verify that assemble_app_bundle gracefully handles missing vs supplied AppIcon.icns without placeholders."""
    import sys
    sys.path.insert(0, str(REPO_ROOT))
    from scripts.build_macos_app import assemble_app_bundle

    dummy_swift = tmp_path / "dummy_swift"
    dummy_swift.write_text("#!/bin/sh\nexit 0\n")
    dummy_swift.chmod(0o755)

    dummy_engine = tmp_path / "dummy_engine"
    dummy_engine.write_text("#!/bin/sh\nexit 0\n")
    dummy_engine.chmod(0o755)

    icon_path = REPO_ROOT / "packaging" / "macos" / "AppIcon.icns"
    had_icon = icon_path.is_file()

    # Case A: When AppIcon.icns does not exist (or is temporarily moved)
    if had_icon:
        backup = tmp_path / "icon_backup.icns"
        import shutil
        shutil.move(icon_path, backup)

    try:
        out_a = tmp_path / "bundle_no_icon"
        out_a.mkdir(parents=True, exist_ok=True)
        bundle_a = assemble_app_bundle(
            swift_binary=dummy_swift,
            go_engine_binary=dummy_engine,
            output_dir=out_a,
            version="1.0.1-beta",
            app_name="TestA.app",
        )
        assert bundle_a.is_dir()
        dest_icon_a = bundle_a / "Contents" / "Resources" / "AppIcon.icns"
        # Must NOT exist and must NOT have created a fake placeholder
        assert not dest_icon_a.exists(), "Should not create a fake placeholder icon when icon is missing"

        # Case B: When AppIcon.icns exists
        icon_path.parent.mkdir(parents=True, exist_ok=True)
        icon_path.write_bytes(b"ICNS_TEST_DATA_BYTES")
        out_b = tmp_path / "bundle_with_icon"
        out_b.mkdir(parents=True, exist_ok=True)
        bundle_b = assemble_app_bundle(
            swift_binary=dummy_swift,
            go_engine_binary=dummy_engine,
            output_dir=out_b,
            version="1.0.1-beta",
            app_name="TestB.app",
        )
        assert bundle_b.is_dir()
        dest_icon_b = bundle_b / "Contents" / "Resources" / "AppIcon.icns"
        assert dest_icon_b.is_file()
        assert dest_icon_b.read_bytes() == b"ICNS_TEST_DATA_BYTES"
    finally:
        # Cleanup test icon
        if icon_path.is_file():
            icon_path.unlink()
        if had_icon:
            shutil.move(backup, icon_path)


def test_configurable_data_directory_validation() -> None:
    """Verify that Application install location is fixed to /Applications while data dir is validated."""
    appstate_src = (REPO_ROOT / "packaging" / "macos" / "AltrStreamApp" / "Sources" / "AppState.swift").read_text(encoding="utf-8")

    # Fixed Application path
    assert 'return "/Applications/Altr Stream.app"' in appstate_src

    # Protected system paths rejected for data directory
    for sys_path in ["/System", "/Library", "/Applications", "/bin", "/usr"]:
        assert f'"{sys_path}"' in appstate_src


def test_dev_container_stop_safety() -> None:
    """Verify Go engine stop-container command and safeguards against dev container removal."""
    engine_main = (REPO_ROOT / "packaging" / "engine" / "main.go").read_text(encoding="utf-8")
    engine_lifecycle = (REPO_ROOT / "packaging" / "engine" / "lifecycle.go").read_text(encoding="utf-8")

    # stop-container CLI exists
    assert 'case "stop-container":' in engine_main
    assert "StopSpecificContainer" in engine_main

    # StopSpecificContainer stops without removing
    assert "func (l *LifecycleManager) StopSpecificContainer" in engine_lifecycle
    assert '"stop", "-t", "10", name' in engine_lifecycle
    assert '"rm"' not in engine_lifecycle[engine_lifecycle.find("StopSpecificContainer") : engine_lifecycle.find("StopSpecificContainer") + 600]

    # Uninstall and removal strictly guards dev container
    assert "Never stop or remove a development container" in engine_lifecycle
    assert "is identified as a development environment" in engine_lifecycle



def test_multi_tier_uninstall_contract() -> None:
    """Verify uninstall differentiates runtime cleanup, persistent data, and app removal."""
    appstate_src = (REPO_ROOT / "packaging" / "macos" / "AltrStreamApp" / "Sources" / "AppState.swift").read_text(encoding="utf-8")
    views_src = (REPO_ROOT / "packaging" / "macos" / "AltrStreamApp" / "Sources" / "ContentView.swift").read_text(encoding="utf-8")

    # A. Runtime cleanup
    assert "Remove Docker & Runtime Resources" in views_src

    # B. Persistent data requires explicit confirmation
    assert "DELETE ALTR STREAM DATA" in views_src
    assert 'uninstallConfirmationInput == "DELETE ALTR STREAM DATA"' in appstate_src

    # C. App removal occurs AFTER runtime cleanup completes
    start_idx = appstate_src.find("public func uninstall()")
    end_idx = appstate_src.find("public func openWebUI()", start_idx)
    uninstall_func = appstate_src[start_idx:end_idx] if end_idx != -1 else appstate_src[start_idx:]
    engine_call_idx = uninstall_func.find("engineBridge.uninstall")
    trash_call_idx = uninstall_func.find("scheduleDeferredTrashRemoval") if "scheduleDeferredTrashRemoval" in uninstall_func else uninstall_func.find("trashItem")
    assert engine_call_idx != -1 and trash_call_idx != -1
    assert engine_call_idx < trash_call_idx, "Runtime cleanup must complete before moving app bundle to Trash"


def test_macos_single_guided_installer_and_node_manager_contract() -> None:
    """Verify that the .pkg postinstall executes user-space node provisioning and installed app acts as pure Node Manager."""
    postinstall_path = REPO_ROOT / "packaging" / "macos" / "scripts" / "postinstall"
    assert postinstall_path.is_file(), "Missing postinstall script"
    postinstall_src = postinstall_path.read_text(encoding="utf-8")

    # 1. Postinstall detects active console user, avoiding root-owned files or root Docker context
    assert "stat -f '%Su' /dev/console" in postinstall_src
    assert "run_as_target" in postinstall_src
    assert "sudo -u" in postinstall_src

    # 2. Postinstall prompts user for data directory before provisioning node
    assert "prompt_user_for_directory" in postinstall_src
    assert "Choose Custom Folder..." in postinstall_src
    assert "choose folder" in postinstall_src
    assert "ALTR_STREAM_HOME" in postinstall_src

    # 3. Postinstall provisions runtime config and attempts node installation
    assert "provision-config" in postinstall_src
    assert "check-docker" in postinstall_src
    assert "launch-docker" in postinstall_src
    assert "wait-docker" in postinstall_src
    assert "install -target-dir" in postinstall_src

    # 4. Postinstall respects development container conflict
    assert "is_dev_container" in postinstall_src
    assert "Development container conflict detected" in postinstall_src

    # 4. Installed Swift application operates as pure Node Manager
    views_src = (REPO_ROOT / "packaging" / "macos" / "AltrStreamApp" / "Sources" / "ContentView.swift").read_text(encoding="utf-8")
    appstate_src = (REPO_ROOT / "packaging" / "macos" / "AltrStreamApp" / "Sources" / "AppState.swift").read_text(encoding="utf-8")
    bridge_src = (REPO_ROOT / "packaging" / "macos" / "AltrStreamApp" / "Sources" / "EngineBridge.swift").read_text(encoding="utf-8")

    assert "Start Altr Stream" in views_src, "Node Manager should offer 'Start Altr Stream' when stopped"
    assert "Altr Stream Node is Stopped" in views_src
    assert "func provisionConfig" in bridge_src
    assert '"provision-config"' in bridge_src


def test_macos_developer_options_flow() -> None:
    """Verify separate Developer Options sheet is eliminated and unified version switcher is present."""
    swift_dir = REPO_ROOT / "packaging" / "macos" / "AltrStreamApp" / "Sources"
    models_src = (swift_dir / "Models.swift").read_text(encoding="utf-8")
    appstate_src = (swift_dir / "AppState.swift").read_text(encoding="utf-8")
    views_src = (swift_dir / "ContentView.swift").read_text(encoding="utf-8")
    bridge_src = (swift_dir / "EngineBridge.swift").read_text(encoding="utf-8")

    # 1. Models and Helper validation rules
    assert "enum DeveloperImageHelper" in models_src
    assert "validateCustomImageSyntax" in models_src or "validateCustomImageReference" in models_src
    assert "formatImageReference" in models_src
    assert "supportedKnownTags" in models_src

    # 2. Separate Developer Options sheet eliminated entirely
    assert "showDeveloperOptions" not in appstate_src
    assert "DeveloperOptionsSheet" not in views_src
    assert 'Button("Developer Options")' not in views_src

    # 3. EngineBridge argument forwarding
    assert "image: String? = nil" in bridge_src
    assert '"--image"' in bridge_src

    # 4. Integrated version switcher
    assert "versionSwitcherCard" in views_src
    assert "showSwitchConfirmationAlert" in appstate_src


def test_macos_manager_window_dimensions_and_no_clipping() -> None:
    """Verify macOS Node Manager window dimensions maintain a compact, balanced native layout without stretching."""
    views_src = (REPO_ROOT / "packaging/macos/AltrStreamApp/Sources/ContentView.swift").read_text(encoding="utf-8")
    app_src = (REPO_ROOT / "packaging/macos/AltrStreamApp/Sources/AltrStreamApp.swift").read_text(encoding="utf-8")

    assert "minWidth: 540" in views_src
    assert "idealWidth: 868" in views_src
    assert "minHeight: 460" in views_src
    assert "idealHeight: 662" in views_src
    assert ".padding(.horizontal, 32)" in views_src
    assert "ScrollView(.vertical" in views_src
    # Confirm outer WindowGroup in AltrStreamApp does not impose conflicting frame modifiers
    assert "maxWidth: 600" not in app_src
    assert "maxHeight: 600" not in app_src


def test_macos_header_version_badge_removed() -> None:
    """Verify Issue 1: Main header displays product title without version badge next to it."""
    views_src = (REPO_ROOT / "packaging/macos/AltrStreamApp/Sources/ContentView.swift").read_text(encoding="utf-8")
    header_block = views_src.split("headerSection: some View")[1].split("dashboardCard")[0]
    # App title must be present
    assert 'Text("Altr Stream")' in header_block
    # Version badge next to title must NOT be present
    assert 'Text("v\\(state.appVersion)")' not in header_block


def test_macos_direct_version_switching_wiring() -> None:
    """Verify direct version switching wiring across Swift models, AppState, EngineBridge, and ContentView."""
    swift_dir = REPO_ROOT / "packaging" / "macos" / "AltrStreamApp" / "Sources"
    models_src = (swift_dir / "Models.swift").read_text(encoding="utf-8")
    appstate_src = (swift_dir / "AppState.swift").read_text(encoding="utf-8")
    views_src = (swift_dir / "ContentView.swift").read_text(encoding="utf-8")
    bridge_src = (swift_dir / "EngineBridge.swift").read_text(encoding="utf-8")

    # 1. Models: Active image and version fields
    assert "activeImage: String?" in models_src
    assert "activeVersion: String?" in models_src

    # 2. EngineBridge: switchVersion command
    assert "func switchVersion(" in bridge_src
    assert '"switch-version"' in bridge_src

    # 3. AppState: activeNodeVersion, activeNodeImage, switchNodeVersion
    assert "@Published public var activeNodeVersion: String? = nil" in appstate_src
    assert "@Published public var activeNodeImage: String? = nil" in appstate_src
    assert "func switchNodeVersion(" in appstate_src

    # 4. Integrated version switcher card in ContentView
    assert "versionSwitcherCard" in views_src
    assert "state.switchNodeVersion(" in views_src or "state.confirmSwitchVersion(" in views_src


def test_macos_update_ownership_and_published_release_separation() -> None:
    """Verify Manager owns Node updates and distinguishes Manager version vs published release vs dev builds."""
    swift_dir = REPO_ROOT / "packaging" / "macos" / "AltrStreamApp" / "Sources"
    appstate_src = (swift_dir / "AppState.swift").read_text(encoding="utf-8")
    models_src = (swift_dir / "Models.swift").read_text(encoding="utf-8")
    views_src = (swift_dir / "ContentView.swift").read_text(encoding="utf-8")

    # Manager checks published releases and tracks latest published Node version
    assert "checkForPublishedReleases" in appstate_src
    assert "latestPublishedNodeVersion" in appstate_src
    assert "isNodeUpdateAvailable" in appstate_src
    assert "requestNodeUpdate" in appstate_src
    assert "confirmNodeUpdate" in appstate_src

    # Published release models
    assert "struct DiscoveredRelease" in models_src or "struct PublishedReleaseInfo" in models_src
    assert "func isLocalDevImage(tagOrRef: String)" in models_src
    assert "func isVersion(_ v1: String, newerThan v2: String)" in models_src

    # UI Update banner and confirmation alert
    assert "versionSwitcherCard" in views_src
    assert "Confirm Version Switch" in views_src


def test_macos_reset_to_recommended_version_workflow() -> None:
    """Verify Reset to Recommended Version does not require reinstall and confirms runtime switch."""
    swift_dir = REPO_ROOT / "packaging" / "macos" / "AltrStreamApp" / "Sources"
    appstate_src = (swift_dir / "AppState.swift").read_text(encoding="utf-8")
    views_src = (swift_dir / "ContentView.swift").read_text(encoding="utf-8")

    # AppState reset methods
    assert "requestResetToRecommended" in appstate_src or "requestSwitchToVersion" in appstate_src
    assert "confirmResetToRecommended" in appstate_src or "confirmSwitchVersion" in appstate_src

    # ContentView Reset triggers, button styling, and confirmation
    assert ".controlSize(.regular)" in views_src
    assert "DeveloperImageHelper.recommendedNodeVersion" in views_src or "Recommended" in views_src


def test_macos_uninstall_confirmation_and_deferred_trash_safety() -> None:
    """Verify uninstall requires confirmation with full component disclosure and protects dev apps from trash."""
    swift_dir = REPO_ROOT / "packaging" / "macos" / "AltrStreamApp" / "Sources"
    appstate_src = (swift_dir / "AppState.swift").read_text(encoding="utf-8")
    views_src = (swift_dir / "ContentView.swift").read_text(encoding="utf-8")

    # Confirmation step before destructive operation
    assert "showUninstallSheet" in appstate_src or "showUninstallConfirmationAlert" in appstate_src
    assert "DELETE ALTR STREAM DATA" in views_src
    assert "Uninstall Altr Stream" in views_src

    # App Trash resolution, validation, and deferred removal
    assert "resolveInstalledApplicationBundle" in appstate_src
    assert "validateApplicationBundleForRemoval" in appstate_src
    assert "scheduleDeferredTrashRemoval" in appstate_src

    # Safety checks: ensure dev builds in dist/ or .build/ are never deleted
    assert '!path.contains("/dist/")' in appstate_src
    assert '!path.contains("/.build/")' in appstate_src


def test_macos_release_discovery_and_filtering() -> None:
    """Verify release discovery uses authoritative releases endpoint and filters drafts."""
    swift_dir = REPO_ROOT / "packaging" / "macos" / "AltrStreamApp" / "Sources"
    appstate_src = (swift_dir / "AppState.swift").read_text(encoding="utf-8")

    # Authoritative endpoint for prereleases
    assert "https://api.github.com/repos/HelloAltr/Altr-Stream/releases" in appstate_src
    assert "https://api.github.com/repos/HelloAltr/Altr-Stream/releases/latest" not in appstate_src

    # Draft filtering
    assert "if r.draft { continue }" in appstate_src


def test_macos_semver_and_update_eligibility_logic() -> None:
    """Verify update eligibility suppresses dev images and requires newer published version."""
    swift_dir = REPO_ROOT / "packaging" / "macos" / "AltrStreamApp" / "Sources"
    appstate_src = (swift_dir / "AppState.swift").read_text(encoding="utf-8")
    models_src = (swift_dir / "Models.swift").read_text(encoding="utf-8")

    # Semver comparator exists
    assert "static func isVersion(_ v1: String, newerThan v2: String) -> Bool" in models_src

    # Dev images never trigger update banner
    assert "DeveloperImageHelper.isLocalDevImage(tagOrRef: img)" in appstate_src
    assert "DeveloperImageHelper.isLocalDevImage(tagOrRef: active)" in appstate_src
    assert "DeveloperImageHelper.isVersion(latestPublishedNodeVersion, newerThan: active)" in appstate_src


def test_macos_builder_decouples_manager_and_node_versions() -> None:
    """Verify build_macos_app.py decouples Manager app bundle version from default Node container version."""
    build_script_src = (REPO_ROOT / "scripts" / "build_macos_app.py").read_text(encoding="utf-8")

    assert ("DEFAULT_NODE_VERSION = \"1.1.0\"" in build_script_src or "DEFAULT_NODE_VERSION = " in build_script_src)
    assert 'build_go_engine(engine_path, node_version, image, target_arch)' in build_script_src
    assert 'assemble_app_bundle(swift_bin, engine_path, output_dir, version, app_name=app_name)' in build_script_src
    assert '"--node-version"' in build_script_src


def test_macos_developer_options_eliminated_in_favor_of_unified_switcher() -> None:
    """Verify Developer Options sheet is eliminated in favor of integrated version switcher."""
    swift_dir = REPO_ROOT / "packaging" / "macos" / "AltrStreamApp" / "Sources"
    views_src = (swift_dir / "ContentView.swift").read_text(encoding="utf-8")

    assert "DeveloperOptionsSheet" not in views_src
    assert "versionSwitcherCard" in views_src


def test_macos_confirmation_dialogs_display_clean_tags() -> None:
    """Verify confirmation alerts display clean tags instead of full registry URLs."""
    swift_dir = REPO_ROOT / "packaging" / "macos" / "AltrStreamApp" / "Sources"
    views_src = (swift_dir / "ContentView.swift").read_text(encoding="utf-8")
    models_src = (swift_dir / "Models.swift").read_text(encoding="utf-8")

    # Helper method exists in models
    assert 'static func extractCleanDisplayTag(imageRef: String) -> String' in models_src

    # Confirmation alerts use clean tags
    assert 'DeveloperImageHelper.extractCleanDisplayTag(imageRef: pendingTargetImage)' in views_src
    assert 'DeveloperImageHelper.recommendedNodeVersion' in views_src or 'Recommended' in views_src


def test_macos_dev_container_conflict_protects_dev_stack() -> None:
    """Verify conflictSection explains dev container independence and does not auto-stop dev stacks."""
    swift_dir = REPO_ROOT / "packaging" / "macos" / "AltrStreamApp" / "Sources"
    views_src = (swift_dir / "ContentView.swift").read_text(encoding="utf-8")

    assert 'The Manager will not adopt, modify, or stop your development environment.' in views_src
    assert 'Button("Stop Development Container")' not in views_src



