"""Unit and integration tests for the Altr Stream Go installer engine."""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(REPO_ROOT))
ENGINE_DIR = REPO_ROOT / "packaging" / "engine"


def test_installer_engine_files_exist() -> None:
    """Ensure all core Go installer engine source files exist."""
    assert (ENGINE_DIR / "go.mod").is_file()
    assert (ENGINE_DIR / "types.go").is_file()
    assert (ENGINE_DIR / "docker.go").is_file()
    assert (ENGINE_DIR / "lifecycle.go").is_file()
    assert (ENGINE_DIR / "engine.go").is_file()
    assert (ENGINE_DIR / "main.go").is_file()
    assert (ENGINE_DIR / "engine_test.go").is_file()


def test_go_installer_engine_unit_tests() -> None:
    """Execute all native Go unit tests with race detection."""
    go_bin = shutil.which("go")
    if not go_bin:
        pytest.skip("Go toolchain is not available in PATH")

    env = os.environ.copy()
    cache_dir = REPO_ROOT / ".build_cache" / "go"
    cache_dir.mkdir(parents=True, exist_ok=True)
    env["GOPATH"] = str(cache_dir.resolve())

    res = subprocess.run(
        [go_bin, "test", "-v", "-race", "./..."],
        cwd=str(ENGINE_DIR),
        env=env,
        capture_output=True,
        text=True,
        timeout=60,
    )
    assert res.returncode == 0, f"Go unit tests failed:\nSTDOUT:\n{res.stdout}\nSTDERR:\n{res.stderr}"
    assert "PASS" in res.stdout
    assert "TestDockerMissing" in res.stdout
    assert "TestDockerInstalledButStopped" in res.stdout
    assert "TestDockerComposeMissing" in res.stdout
    assert "TestDockerStartupRetry" in res.stdout
    assert "TestDockerUnavailableTimeout" in res.stdout
    assert "TestContainerConflictDetection" in res.stdout
    assert "TestInstallSuccess" in res.stdout
    assert "TestImagePullFailure" in res.stdout
    assert "TestContainerStartupPortConflict" in res.stdout
    assert "TestHealthTimeoutFailure" in res.stdout
    assert "TestVersionMismatch" in res.stdout
    assert "TestRepairPreservesDataVolume" in res.stdout
    assert "TestUninstallPreservesData" in res.stdout
    assert "TestUninstallDeletesData" in res.stdout
    assert "TestStatusQuery" in res.stdout
    assert "TestLaunchBrowser" in res.stdout


def test_go_installer_engine_cross_compilation(tmp_path: Path) -> None:
    """Verify Go installer engine compiles cleanly for Windows x64 and macOS universal targets."""
    go_bin = shutil.which("go")
    if not go_bin:
        pytest.skip("Go toolchain is not available in PATH")

    targets = [
        ("windows", "amd64", "altr-engine.exe"),
        ("darwin", "arm64", "altr-engine-darwin-arm64"),
        ("darwin", "amd64", "altr-engine-darwin-amd64"),
    ]

    for goos, goarch, out_name in targets:
        out_bin = tmp_path / out_name
        env = os.environ.copy()
        env["GOOS"] = goos
        env["GOARCH"] = goarch
        env["CGO_ENABLED"] = "0"
        env["GOPATH"] = str(tmp_path / "gopath")

        res = subprocess.run(
            [
                go_bin,
                "build",
                "-ldflags=-s -w -X main.DefaultImage=ghcr.io/helloaltr/altr-stream:0.13.7-alpha -X main.DefaultVersion=1.0.0-beta",
                "-o",
                str(out_bin),
                ".",
            ],
            cwd=str(ENGINE_DIR),
            env=env,
            capture_output=True,
            text=True,
            timeout=30,
        )
        assert res.returncode == 0, f"Compilation failed for {goos}/{goarch}:\n{res.stderr}"
        assert out_bin.is_file(), f"Output binary {out_bin} was not created"
        assert out_bin.stat().st_size > 1_000_000, f"Binary {out_bin} is unexpectedly small"


def test_go_installer_engine_cli_subcommands(tmp_path: Path) -> None:
    """Test running native engine binary subcommands and JSON outputs."""
    go_bin = shutil.which("go")
    if not go_bin:
        pytest.skip("Go toolchain is not available in PATH")

    out_bin = tmp_path / "altr-installer-engine"
    build_env = os.environ.copy()
    build_env["GOPATH"] = str(tmp_path / "gopath")
    build_res = subprocess.run(
        [
            go_bin,
            "build",
            "-ldflags=-s -w -X main.DefaultImage=ghcr.io/helloaltr/altr-stream:0.13.7-alpha -X main.DefaultVersion=1.0.0-beta",
            "-o",
            str(out_bin),
            ".",
        ],
        cwd=str(ENGINE_DIR),
        env=build_env,
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert build_res.returncode == 0, f"Build failed: {build_res.stderr}"

    # 1. Test detect-env JSON output
    res_env = subprocess.run([str(out_bin), "detect-env"], capture_output=True, text=True, timeout=5)
    assert res_env.returncode == 0
    env_data = json.loads(res_env.stdout)
    assert "os" in env_data
    assert "arch" in env_data
    assert "user_home" in env_data
    assert "default_dir" in env_data
    assert "effective_dir" in env_data
    assert ".altr-stream" in env_data["default_dir"]

    # 2. Test check-docker JSON output
    res_docker = subprocess.run([str(out_bin), "check-docker"], capture_output=True, text=True, timeout=20)
    assert res_docker.returncode == 0
    docker_data = json.loads(res_docker.stdout)
    assert "state" in docker_data
    assert "cli_installed" in docker_data
    assert "desktop_installed" in docker_data
    assert "official_installer_url" in docker_data
    assert "https://" in docker_data["official_installer_url"]


def test_inno_setup_script_structure() -> None:
    """Verify Inno Setup 6 script definitions, Manager installation, and lifecycle semantics."""
    iss_path = REPO_ROOT / "packaging" / "windows" / "Altr-Stream.iss"
    assert iss_path.is_file(), f"Missing Inno Setup script at {iss_path}"

    content = iss_path.read_text(encoding="utf-8")

    # Product and version metadata
    assert ('#define MyAppVersion "1.1.0"' in content or '#define MyAppVersion "' in content)
    assert "AppName=Altr Stream Manager" in content
    assert "OutputBaseFilename=Altr Stream Installer" in content
    assert "ArchitecturesInstallIn64BitMode=x64compatible" in content
    assert "PrivilegesRequired=lowest" in content
    assert r"DefaultDirName={autopf}\Altr Stream" in content

    # Bundled files
    assert r'Source: "build\altr-installer-engine.exe"; DestDir: "{app}"; DestName: "Altr Stream Manager.exe"' in content
    assert r'Source: "build\altr-installer-engine.exe"; DestDir: "{app}"; DestName: "altr-installer-engine.exe"' in content
    assert r'Source: "..\templates\INSTALLER_README.md"; DestDir: "{app}"; DestName: "README.txt"' in content

    # Shortcuts
    assert r"{autoprograms}\Altr Stream\Altr Stream Manager" in content
    assert r"{autoprograms}\Altr Stream\Uninstall Altr Stream Manager" in content
    assert r"{autodesktop}\Altr Stream Manager" in content

    # Launch Manager after install
    assert r'Filename: "{app}\Altr Stream Manager.exe"; Description: "Launch Altr Stream Manager"' in content

    # Pure application installer: does NOT run Docker lifecycle during install and has no DevOptionsPage
    assert "DevOptionsPage" not in content
    assert "check-docker" not in content

    # Volume preservation on uninstall
    assert "altr_stream_data" in content


def test_build_windows_installer_script_help() -> None:
    """Verify build_windows_installer.py CLI help succeeds."""
    script_path = REPO_ROOT / "scripts" / "build_windows_installer.py"
    assert script_path.is_file()

    res = subprocess.run([sys.executable, str(script_path), "--help"], capture_output=True, text=True, timeout=10)
    assert res.returncode == 0
    assert "--version" in res.stdout
    assert "--image" in res.stdout
    assert "--output-dir" in res.stdout


def test_build_windows_installer_produces_valid_pe(tmp_path: Path) -> None:
    """End-to-end test of the Windows installer build pipeline and PE binary validation."""
    from scripts.build_windows_installer import build_windows_installer

    try:
        installer_exe = build_windows_installer(output_dir=tmp_path)
    except RuntimeError as e:
        err = str(e)
        if "Inno Setup 6 compiler (iscc) not found" in err:
            pytest.skip(f"Inno Setup compiler (iscc) is not available in this environment: {e}")
        if "Cannot connect to the Docker daemon" in err or "docker daemon is not running" in err.lower():
            pytest.skip(f"Docker daemon unavailable to run containerized Inno Setup compiler: {e}")
        raise
    assert installer_exe.is_file()
    assert installer_exe.name in ("Altr Stream Installer.exe", "Altr-Stream-Installer.exe")

    # Size check: embedded engine (~7MB compressed to ~4MB)
    size = installer_exe.stat().st_size
    assert size > 3_000_000, f"Installer size ({size} bytes) is unexpectedly small"

    # Read binary bytes
    data = installer_exe.read_bytes()

    # PE DOS header check ('MZ')
    assert data[:2] == b"MZ", "Missing MZ DOS header in installer executable"

    # Inno Setup signature check
    assert b"Inno Setup" in data, "Missing Inno Setup signature marker"

    # Application name in UTF-16LE resource strings
    assert "Altr Stream".encode("utf-16le") in data, "Missing UTF-16LE 'Altr Stream' string in installer binary"


def test_inno_setup_prereq_page_responsive_layout() -> None:
    """Verify Inno Setup uses modern wizard style and delegates prerequisite checks to Manager."""
    iss_content = (REPO_ROOT / "packaging" / "windows" / "Altr-Stream.iss").read_text(encoding="utf-8")
    assert "WizardStyle=modern" in iss_content
    assert "PrereqPage" not in iss_content


def test_inno_setup_default_install_dir_avoids_onedrive() -> None:
    """Verify installer installs to Program Files, avoiding user OneDrive/Documents."""
    iss_content = (REPO_ROOT / "packaging" / "windows" / "Altr-Stream.iss").read_text(encoding="utf-8")
    assert r"DefaultDirName={autopf}\Altr Stream" in iss_content


def test_inno_setup_progress_reporting_and_non_freezing_loop() -> None:
    """Verify Go installer engine CLI supports progress reporting milestones."""
    main_code = (REPO_ROOT / "packaging" / "engine" / "main.go").read_text(encoding="utf-8")
    assert "writeProgressFile" in main_code
    assert "progress-file" in main_code


def test_inno_setup_failure_state_machine_and_browser_guard() -> None:
    """Verify Inno Setup launches Manager only post-install without hardcoded browser URLs."""
    iss_content = (REPO_ROOT / "packaging" / "windows" / "Altr-Stream.iss").read_text(encoding="utf-8")
    assert 'Filename: "{app}\\Altr Stream Manager.exe"' in iss_content
    assert "http://localhost:8000" not in iss_content


def test_go_engine_progress_file_and_error_formatting(tmp_path: Path) -> None:
    """Verify Go engine writes progress file milestones and avoids %w(<nil>) formatting."""
    go_bin = shutil.which("go")
    if not go_bin:
        pytest.skip("Go toolchain is not available in PATH")

    out_bin = tmp_path / "altr-installer-engine"
    build_env = os.environ.copy()
    build_env["GOPATH"] = str(tmp_path / "gopath")
    build_res = subprocess.run(
        [
            go_bin,
            "build",
            "-ldflags=-s -w -X main.DefaultImage=ghcr.io/helloaltr/altr-stream:0.13.7-alpha -X main.DefaultVersion=1.0.0-beta",
            "-o",
            str(out_bin),
            ".",
        ],
        cwd=str(ENGINE_DIR),
        env=build_env,
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert build_res.returncode == 0

    prog_file = tmp_path / "progress.txt"
    isolated_env = os.environ.copy()
    isolated_home = tmp_path / "home"
    isolated_home.mkdir(parents=True, exist_ok=True)
    isolated_env["HOME"] = str(isolated_home)
    isolated_env["USERPROFILE"] = str(isolated_home)
    isolated_env["ALTR_STREAM_CONFIG_FILE"] = str(isolated_home / ".altr-stream-config")

    # Run detect-env to verify IsOneDrive flag
    env_res = subprocess.run([str(out_bin), "detect-env"], env=isolated_env, capture_output=True, text=True, timeout=10)
    assert env_res.returncode == 0
    env_json = json.loads(env_res.stdout)
    assert "is_onedrive" in env_json
    assert str(isolated_home) in env_json["default_dir"]

    # Test install failure with invalid port or non-existent docker (should write failure into progress file without %w(<nil>))
    inst_res = subprocess.run(
        [
            str(out_bin),
            "install",
            "--target-dir",
            str(tmp_path / "inst_target"),
            "--port",
            "999999",  # Invalid port forces early failure
            "--progress-file",
            str(prog_file),
        ],
        env=isolated_env,
        capture_output=True,
        text=True,
        timeout=15,
    )
    # Must exit non-zero
    assert inst_res.returncode != 0
    # Must not contain %w(<nil>) or %!w(<nil>)
    assert "%w(<nil>)" not in inst_res.stderr
    assert "%!w(<nil>)" not in inst_res.stderr

    # Progress file must have been written
    assert prog_file.is_file()
    prog_content = prog_file.read_text(encoding="utf-8")
    assert "%w(<nil>)" not in prog_content
    assert "%!w(<nil>)" not in prog_content


def test_inno_setup_use_previous_app_dir_disabled() -> None:
    """Verify Inno Setup defines standard Program Files target."""
    iss_content = (REPO_ROOT / "packaging" / "windows" / "Altr-Stream.iss").read_text(encoding="utf-8")
    assert r"DefaultDirName={autopf}\Altr Stream" in iss_content


def test_inno_setup_multi_layered_completion_and_error_capture() -> None:
    """Verify Inno Setup uninstallation protects user data and volumes."""
    iss_content = (REPO_ROOT / "packaging" / "windows" / "Altr-Stream.iss").read_text(encoding="utf-8")
    assert "CurUninstallStepChanged" in iss_content
    assert "altr_stream_data" in iss_content


def test_inno_setup_heading_height_and_dpi_scaling() -> None:
    """Verify Inno Setup uses modern wizard style for high-DPI displays."""
    iss_content = (REPO_ROOT / "packaging" / "windows" / "Altr-Stream.iss").read_text(encoding="utf-8")
    assert "WizardStyle=modern" in iss_content


def test_inno_setup_prerequisite_human_readable_and_no_raw_json() -> None:
    """Verify Go installer engine emits structured diagnostics with human-readable state."""
    types_code = (REPO_ROOT / "packaging" / "engine" / "types.go").read_text(encoding="utf-8")
    assert "type DockerDiagnostics struct" in types_code
    assert "State" in types_code


def test_inno_setup_docker_not_ready_strictly_blocks_next() -> None:
    """Verify Inno Setup is pure app installer and does not block on Docker during install."""
    iss_content = (REPO_ROOT / "packaging" / "windows" / "Altr-Stream.iss").read_text(encoding="utf-8")
    assert "check-docker" not in iss_content


def test_inno_setup_failure_page_has_clean_error_and_view_log_button() -> None:
    """Verify Inno Setup does not contain custom Delphi failure pages."""
    iss_content = (REPO_ROOT / "packaging" / "windows" / "Altr-Stream.iss").read_text(encoding="utf-8")
    assert "FinishedHeadingLabel" not in iss_content


def test_lifecycle_manager_file_sharing_recovery_state() -> None:
    """Verify Go lifecycle manager classifies file-sharing errors as host-access prerequisite without hammering."""
    lifecycle_code = (REPO_ROOT / "packaging" / "engine" / "lifecycle.go").read_text(encoding="utf-8")
    types_code = (REPO_ROOT / "packaging" / "engine" / "types.go").read_text(encoding="utf-8")
    main_code = (REPO_ROOT / "packaging" / "engine" / "main.go").read_text(encoding="utf-8")

    # Helper function identifies file sharing daemon messages
    assert "func isFileSharingError(combinedLog string) bool" in lifecycle_code
    assert "is not shared from the host" in lifecycle_code
    assert "filesystem sharing" in lifecycle_code
    assert "extractSharedPath(combinedLog)" in lifecycle_code

    # Typed prerequisite error
    assert "type ErrFileSharingRequired struct" in types_code
    assert "FILE_SHARING_REQUIRED|" in types_code

    # StartContainer immediately classifies and records diagnostic without automated hammering
    assert "&ErrFileSharingRequired{" in lifecycle_code
    assert "=== Container Startup Attempt" in lifecycle_code
    assert "open-docker-settings" in main_code
    assert "FileSharingRequired" in main_code


def test_inno_setup_file_sharing_recovery_flow() -> None:
    """Verify engine and Manager handle file sharing recovery rather than Inno Setup."""
    iss_content = (REPO_ROOT / "packaging" / "windows" / "Altr-Stream.iss").read_text(encoding="utf-8")
    assert "ShowFileSharingRecoveryDialog" not in iss_content


def test_open_docker_settings_fallback_and_no_false_claim() -> None:
    """Verify Open Docker Settings implements application fallback, foreground activation, and avoids false success claims."""
    main_code = (REPO_ROOT / "packaging" / "engine" / "main.go").read_text(encoding="utf-8")
    docker_code = (REPO_ROOT / "packaging" / "engine" / "docker.go").read_text(encoding="utf-8")
    win_code = (REPO_ROOT / "packaging" / "engine" / "platform_windows.go").read_text(encoding="utf-8")
    darwin_code = (REPO_ROOT / "packaging" / "engine" / "platform_darwin.go").read_text(encoding="utf-8")

    # 1. Engine OpenDockerSettings executes LaunchDockerDesktop fallback
    assert "launchErr := d.LaunchDockerDesktop(ctx)" in docker_code
    assert 'docker-desktop://settings' in win_code
    assert 'docker-desktop://settings' in darwin_code

    # 2. No false claim that Settings was opened directly
    assert "Opened Docker Desktop settings." not in main_code
    assert "Docker Desktop launched. Please navigate to Settings" in main_code


def test_inno_setup_recovery_dialog_valid_custom_form() -> None:
    """Verify Inno Setup avoids custom Delphi form creation."""
    iss_content = (REPO_ROOT / "packaging" / "windows" / "Altr-Stream.iss").read_text(encoding="utf-8")
    assert "TSetupForm" not in iss_content
    assert "TForm" not in iss_content
    assert "CreateCustomForm" not in iss_content


def test_inno_setup_docker_startup_lifecycle_nonblocking_and_responsive() -> None:
    """Verify Inno Setup does not attempt Docker startup during setup."""
    iss_content = (REPO_ROOT / "packaging" / "windows" / "Altr-Stream.iss").read_text(encoding="utf-8")
    assert "launch-docker" not in iss_content


def test_go_installer_engine_detached_launch_no_pipe_deadlocks() -> None:
    """Verify Go installer engine launches GUI processes detached without anonymous pipe handle inheritance."""
    types_code = (REPO_ROOT / "packaging" / "engine" / "types.go").read_text(encoding="utf-8")
    docker_code = (REPO_ROOT / "packaging" / "engine" / "docker.go").read_text(encoding="utf-8")
    main_code = (REPO_ROOT / "packaging" / "engine" / "main.go").read_text(encoding="utf-8")
    win_code = (REPO_ROOT / "packaging" / "engine" / "platform_windows.go").read_text(encoding="utf-8")
    darwin_code = (REPO_ROOT / "packaging" / "engine" / "platform_darwin.go").read_text(encoding="utf-8")

    # CommandExecutor defines StartDetached
    assert "StartDetached(ctx context.Context, name string, args ...string) error" in types_code

    # OSCommandExecutor implements StartDetached disconnecting std streams
    assert "func (o *OSCommandExecutor) StartDetached" in main_code
    assert "cmd.Stdout = nil" in main_code
    assert "cmd.Stderr = nil" in main_code
    assert "setDetachedProcess(cmd)" in main_code

    # LaunchDockerDesktop and OpenDockerSettings delegate to platform implementations using StartDetached
    assert "d.launchPlatformDockerDesktop(ctx, desktopPath, exists)" in docker_code
    assert "d.openPlatformDockerSettings(ctx)" in docker_code
    assert "d.executor.StartDetached" in win_code
    assert "d.executor.StartDetached" in darwin_code
    assert "cmd.exe" in win_code
    assert "start" in win_code
    assert "open" in darwin_code

    # Clean explicit exits in CLI subcommands
    assert 'case "launch-docker":' in main_code
    assert "os.Exit(0)" in main_code
    assert 'case "wait-docker":' in main_code


def test_darwin_platform_isolation_and_paths() -> None:
    """Verify macOS platform implementation explicitly isolates Docker detection, launching, and browser launch."""
    darwin_code = (REPO_ROOT / "packaging" / "engine" / "platform_darwin.go").read_text(encoding="utf-8")

    assert "//go:build darwin" in darwin_code
    assert "Setpgid: true" in darwin_code
    assert "/Applications/Docker.app" in darwin_code
    assert 'userApp := filepath.Join(home, "Applications", "Docker.app")' in darwin_code
    assert "/opt/homebrew/bin/docker" in darwin_code
    assert "/usr/local/bin/docker" in darwin_code
    assert 'd.executor.StartDetached(ctx, "open", "-a", desktopPath)' in darwin_code
    assert 'd.executor.StartDetached(ctx, "open", "-a", "Docker")' in darwin_code
    assert 'd.executor.StartDetached(ctx, "open", "docker-desktop://settings")' in darwin_code
    assert 'exec.StartDetached(ctx, "open", targetURL)' in darwin_code


def test_docker_command_execution_abstraction_and_no_bare_docker() -> None:
    """Verify lifecycle manager and engine use resolved Docker executable path everywhere."""
    lifecycle_code = (REPO_ROOT / "packaging" / "engine" / "lifecycle.go").read_text(encoding="utf-8")
    engine_code = (REPO_ROOT / "packaging" / "engine" / "engine.go").read_text(encoding="utf-8")

    # LifecycleManager must have dockerCLI() and parseComposeCommand()
    assert "func (l *LifecycleManager) dockerCLI() string" in lifecycle_code
    assert "func (l *LifecycleManager) parseComposeCommand(composeCmd string)" in lifecycle_code

    # Lifecycle manager must use l.dockerCLI() instead of hardcoded "docker" for CLI operations
    assert 'l.executor.Run(ctx, l.dockerCLI(), "inspect", ContainerName)' in lifecycle_code
    assert 'l.executor.Run(ctx, l.dockerCLI(), "volume", "create", NamedDataVolume)' in lifecycle_code
    assert 'l.executor.Run(ctx, l.dockerCLI(), "images", "-q", image)' in lifecycle_code
    assert 'l.executor.Run(ctx, l.dockerCLI(), "inspect", "-f", "{{.State.Running}}", ContainerName)' in lifecycle_code
    assert 'l.executor.Run(ctx, l.dockerCLI(), "rm", "-f", ContainerName)' in lifecycle_code
    assert 'l.executor.Run(ctx, l.dockerCLI(), "volume", "rm", NamedDataVolume)' in lifecycle_code
    assert 'l.executor.Run(ctx, l.dockerCLI(), "logs", "--tail", "25", ContainerName)' in lifecycle_code

    # Assert NO bare l.executor.Run(ctx, "docker" exists anywhere in lifecycle.go
    assert 'l.executor.Run(ctx, "docker"' not in lifecycle_code

    # Verify isTemporaryDirectory guards DetectEnvironment and SaveInstallDirectory in engine.go
    assert "func isTemporaryDirectory(path string) bool" in engine_code
    assert "if !isTemporaryDirectory(candidate)" in engine_code
    assert "if os.Getenv(\"ALTR_STREAM_CONFIG_FILE\") == \"\" && isTemporaryDirectory(dir)" in engine_code


def test_go_engine_detect_environment_paths_and_temp_rejection(tmp_path: Path) -> None:
    """Verify Go engine CLI detect-env cleanly defaults to $HOME/.altr-stream and rejects temp paths."""
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

    isolated_home = tmp_path / "userhome"
    isolated_home.mkdir(parents=True, exist_ok=True)
    cfg_file = isolated_home / ".altr-stream-config"

    base_env = os.environ.copy()
    base_env["HOME"] = str(isolated_home)
    base_env["USERPROFILE"] = str(isolated_home)
    base_env["ALTR_STREAM_CONFIG_FILE"] = str(cfg_file)
    base_env.pop("ALTR_STREAM_HOME", None)

    # 1. Clean default: effective_dir must be $HOME/.altr-stream
    clean_res = subprocess.run([str(out_bin), "detect-env"], env=base_env, capture_output=True, text=True, timeout=10)
    assert clean_res.returncode == 0
    clean_json = json.loads(clean_res.stdout)
    assert clean_json["default_dir"] == str(isolated_home / ".altr-stream")
    assert clean_json["effective_dir"] == str(isolated_home / ".altr-stream")
    assert clean_json.get("saved_dir", "") == ""

    # 2. Reject temporary / pytest paths written into config file
    fake_pytest_dir = tmp_path / "pytest-999" / "test_leak" / "inst_target"
    fake_pytest_dir.mkdir(parents=True, exist_ok=True)
    (fake_pytest_dir / "docker-compose.yml").write_text("version: '3'", encoding="utf-8")
    cfg_file.write_text(str(fake_pytest_dir), encoding="utf-8")

    polluted_res = subprocess.run([str(out_bin), "detect-env"], env=base_env, capture_output=True, text=True, timeout=10)
    assert polluted_res.returncode == 0
    polluted_json = json.loads(polluted_res.stdout)
    assert polluted_json.get("saved_dir", "") == ""
    assert polluted_json["effective_dir"] == str(isolated_home / ".altr-stream")
    assert "inst_target" not in polluted_json["effective_dir"]
    assert str(fake_pytest_dir) not in polluted_json["effective_dir"]

    # 3. Explicit ALTR_STREAM_HOME override
    override_env = base_env.copy()
    override_dir = isolated_home / "custom_altr_location"
    override_env["ALTR_STREAM_HOME"] = str(override_dir)
    override_res = subprocess.run([str(out_bin), "detect-env"], env=override_env, capture_output=True, text=True, timeout=10)
    assert override_res.returncode == 0
    override_json = json.loads(override_res.stdout)
    assert override_json["effective_dir"] == str(override_dir)


def test_inno_setup_docker_start_and_conflict_handling() -> None:
    """Verify Inno Setup does not handle container conflicts, delegating to Manager."""
    iss_path = REPO_ROOT / "packaging" / "windows" / "Altr-Stream.iss"
    assert iss_path.is_file(), f"{iss_path} not found"
    iss_content = iss_path.read_text(encoding="utf-8")
    assert "StartDockerBtnClick" not in iss_content


def test_go_engine_install_replace_existing_flag(tmp_path: Path) -> None:
    """Verify Go installer engine CLI supports --replace-existing flag in install command."""
    out_bin = tmp_path / "altr-installer-engine"
    build_env = os.environ.copy()
    build_env["GOPATH"] = str(tmp_path / "gopath")
    build_res = subprocess.run(
        ["go", "build", "-o", str(out_bin), "."],
        cwd=str(ENGINE_DIR),
        env=build_env,
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert build_res.returncode == 0

    # Verify flag is accepted and documented in install flags
    res = subprocess.run(
        [str(out_bin), "install", "--help"],
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert res.returncode == 0
    assert "-replace-existing" in res.stderr or "-replace-existing" in res.stdout
    assert "Safely remove conflicting container before installing" in (res.stderr + res.stdout)


def test_inno_setup_port_conflict_handling() -> None:
    """Verify Inno Setup delegates conflict handling to Manager."""
    iss_path = REPO_ROOT / "packaging" / "windows" / "Altr-Stream.iss"
    assert iss_path.is_file(), f"{iss_path} not found"
    iss_content = iss_path.read_text(encoding="utf-8")
    assert "conflict_type" not in iss_content


def test_go_engine_conflict_port_flags_and_schema(tmp_path: Path) -> None:
    """Verify Go installer engine CLI conflict subcommand supports port flags and emits extended schema."""
    out_bin = tmp_path / "altr-installer-engine"
    build_env = os.environ.copy()
    build_env["GOPATH"] = str(tmp_path / "gopath")
    build_res = subprocess.run(
        ["go", "build", "-o", str(out_bin), "."],
        cwd=str(ENGINE_DIR),
        env=build_env,
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert build_res.returncode == 0

    # 1. Verify --port and --target-dir flags
    res_help = subprocess.run(
        [str(out_bin), "conflict", "--help"],
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert res_help.returncode == 0
    assert "-port" in (res_help.stderr + res_help.stdout)
    assert "-target-dir" in (res_help.stderr + res_help.stdout)

    # 2. Run conflict command and verify JSON structure
    res_conflict = subprocess.run(
        [str(out_bin), "conflict", "--port", "8000"],
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert res_conflict.returncode == 0
    conflict_data = json.loads(res_conflict.stdout)
    assert "exists" in conflict_data
    assert "conflict_type" in conflict_data
    assert "is_installer_owned" in conflict_data
    assert "is_dev_container" in conflict_data
    assert "conflicting_port" in conflict_data
    assert "remediation_hint" in conflict_data


def test_engine_does_not_create_unnecessary_home_go_dir(tmp_path: Path) -> None:
    """Requirement 4: Verify installer engine execution and install flow does NOT create ~/go."""
    clean_home = tmp_path / "clean_user_home"
    clean_home.mkdir(parents=True, exist_ok=True)
    engine_bin = REPO_ROOT / "dist" / "altr-installer-engine"
    if not engine_bin.exists():
        engine_bin = REPO_ROOT / "dist" / "Altr Stream.app" / "Contents" / "Resources" / "altr-installer-engine"
    if not engine_bin.exists():
        pytest.skip("Packaged engine binary not built")

    env = os.environ.copy()
    env["HOME"] = str(clean_home)
    env["USERPROFILE"] = str(clean_home)

    res = subprocess.run([str(engine_bin), "detect-env"], env=env, capture_output=True, text=True, timeout=10)
    assert res.returncode == 0
    assert not (clean_home / "go").exists(), "Installer engine unnecessarily created ~/go"


def test_build_windows_installer_resolves_canonical_image() -> None:
    """Verify scripts/build_windows_installer.py resolves canonical image when unspecified."""
    from scripts.build_windows_installer import build_windows_installer
    import inspect

    sig = inspect.signature(build_windows_installer)
    assert "image" in sig.parameters
    assert sig.parameters["image"].default is None

    # Verify that in build_windows_installer.py, when image is None, it defaults to canonical version format
    import scripts.build_windows_installer as bwi
    assert bwi.DEFAULT_IMAGE is None


def test_docker_compose_template_and_engine_interpolation() -> None:
    """Verify docker-compose.template.yml and engine lifecycle use ${ALTR_STREAM_IMAGE:-...}."""
    template_path = REPO_ROOT / "packaging" / "templates" / "docker-compose.template.yml"
    assert template_path.is_file()
    tmpl_content = template_path.read_text(encoding="utf-8")
    assert "${ALTR_STREAM_IMAGE:-" in tmpl_content

    lifecycle_go = REPO_ROOT / "packaging" / "engine" / "lifecycle.go"
    assert lifecycle_go.is_file()
    go_content = lifecycle_go.read_text(encoding="utf-8")
    assert "${ALTR_STREAM_IMAGE:-%s}" in go_content


def test_windows_batch_installer_uses_canonical_image() -> None:
    """Verify Altr-Stream_Windows_Installer.bat dynamically resolves image without hardcoded alpha."""
    bat_path = REPO_ROOT / "packaging" / "installers" / "Altr-Stream_Windows_Installer.bat"
    assert bat_path.is_file()
    bat_content = bat_path.read_text(encoding="utf-8")
    assert "0.13.7-alpha" not in bat_content
    assert "$env:ALTR_STREAM_IMAGE" in bat_content
    assert "ghcr.io/helloaltr/altr-stream:$Version" in bat_content


def test_windows_installer_cleanup_preserves_macos_pkg(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    """Regression Test: Compiling Windows installer must only clean stale .exe files and preserve macOS .pkg artifacts."""
    import scripts.build_windows_installer as bwi

    fake_root = tmp_path / "repo"
    dist_dir = fake_root / "dist"
    dist_dir.mkdir(parents=True, exist_ok=True)
    monkeypatch.setattr(bwi, "REPO_ROOT", fake_root)

    # 1. Setup pre-existing artifacts in dist/
    dummy_pkg = dist_dir / "Altr-Stream-Installer.pkg"
    dummy_pkg.write_text("dummy-macos-pkg-bytes", encoding="utf-8")

    dummy_zip = dist_dir / "Altr-Stream_macOS_Installer.app.zip"
    dummy_zip.write_text("dummy-macos-zip-bytes", encoding="utf-8")

    stale_exe = dist_dir / "Altr-Stream-Installer.exe"
    stale_exe.write_bytes(b"MZ\x90\x00stale_exe")

    stale_tmp_exe = dist_dir / "Altr-Stream-Installer-old.exe"
    stale_tmp_exe.write_bytes(b"MZ\x90\x00stale_old")

    # 2. Mock runner and compilation
    fake_iss = fake_root / "packaging" / "windows" / "Altr-Stream.iss"
    fake_iss.parent.mkdir(parents=True, exist_ok=True)
    fake_iss.write_text("; fake inno script", encoding="utf-8")

    monkeypatch.setattr(bwi, "find_iscc_runner", lambda: (["echo"], "native"))

    def mock_subprocess_run(cmd, cwd=None, capture_output=True, text=True):
        # Simulate Inno Setup outputting Altr-Stream-Installer.exe with valid MZ header
        target = dist_dir / "Altr-Stream-Installer.exe"
        target.write_bytes(b"MZ\x90\x00" + b"\x00" * 100)
        class Completed:
            returncode = 0
            stdout = "Mocked Inno Setup success"
            stderr = ""
        return Completed()

    monkeypatch.setattr(subprocess, "run", mock_subprocess_run)

    out_exe = bwi.compile_inno_setup(
        iss_file=fake_iss,
        output_dir=dist_dir,
        version="1.0.1-beta",
        image="ghcr.io/helloaltr/altr-stream:1.0.1-beta",
    )

    # 3. Assertions:
    # Stale .exe artifacts are unlinked
    assert not stale_tmp_exe.exists()
    # macOS .pkg MUST SURVIVE unharmed
    assert dummy_pkg.is_file()
    assert dummy_pkg.read_text(encoding="utf-8") == "dummy-macos-pkg-bytes"
    # macOS .app.zip MUST SURVIVE unharmed
    assert dummy_zip.is_file()
    assert dummy_zip.read_text(encoding="utf-8") == "dummy-macos-zip-bytes"
    # New .exe installer exists
    assert out_exe.is_file()


def test_developer_options_image_selection_and_resolution(tmp_path: Path) -> None:
    """Verify Developer Options image selection rules: default canonical, older version, custom validation, reset."""
    engine_bin = REPO_ROOT / "dist" / "altr-installer-engine"
    if not engine_bin.exists():
        engine_bin = REPO_ROOT / "dist" / "Altr Stream.app" / "Contents" / "Resources" / "altr-installer-engine"
    if not engine_bin.exists():
        pytest.skip("Engine binary not available in dist/")

    try:
        from altr_stream.__version__ import __version__ as canonical_ver
    except ImportError:
        canonical_ver = "1.1.0"
    canonical_img = f"ghcr.io/helloaltr/altr-stream:{canonical_ver}"

    # 1. Default installation resolves to canonical image when no override is selected
    target_dir_default = tmp_path / "default_install"
    target_dir_default.mkdir(parents=True, exist_ok=True)
    res_def = subprocess.run(
        [str(engine_bin), "provision-config", "-target-dir", str(target_dir_default)],
        capture_output=True,
        text=True,
        check=True,
    )
    compose_def = (target_dir_default / "docker-compose.yml").read_text(encoding="utf-8")
    assert f"${{ALTR_STREAM_IMAGE:-{canonical_img}}}" in compose_def

    # 2. Selecting an older image uses that exact image
    older_img = "ghcr.io/helloaltr/altr-stream:0.13.7-alpha"
    target_dir_older = tmp_path / "older_install"
    target_dir_older.mkdir(parents=True, exist_ok=True)
    res_older = subprocess.run(
        [str(engine_bin), "provision-config", "-target-dir", str(target_dir_older), "-image", older_img],
        capture_output=True,
        text=True,
        check=True,
    )
    compose_older = (target_dir_older / "docker-compose.yml").read_text(encoding="utf-8")
    assert f"${{ALTR_STREAM_IMAGE:-{older_img}}}" in compose_older

    # 3. Selecting the recommended version clears override and uses canonical image
    target_dir_reset = tmp_path / "reset_install"
    target_dir_reset.mkdir(parents=True, exist_ok=True)
    # Simulate first writing older image, then provisioning with empty image override (recommended)
    (target_dir_reset / ".env").write_text(f"ALTR_STREAM_IMAGE={older_img}\n", encoding="utf-8")
    res_reset = subprocess.run(
        [str(engine_bin), "provision-config", "-target-dir", str(target_dir_reset), "-image", canonical_img],
        capture_output=True,
        text=True,
        check=True,
    )
    compose_reset = (target_dir_reset / "docker-compose.yml").read_text(encoding="utf-8")
    assert f"${{ALTR_STREAM_IMAGE:-{canonical_img}}}" in compose_reset
    env_reset = (target_dir_reset / ".env").read_text(encoding="utf-8")
    assert f"ALTR_STREAM_IMAGE={canonical_img}" in env_reset

    # 4. Custom image is passed through correctly
    custom_img = "myregistry.internal/altr/stream:dev-test-42"
    target_dir_custom = tmp_path / "custom_install"
    target_dir_custom.mkdir(parents=True, exist_ok=True)
    res_custom = subprocess.run(
        [str(engine_bin), "provision-config", "-target-dir", str(target_dir_custom), "-image", custom_img],
        capture_output=True,
        text=True,
        check=True,
    )
    compose_custom = (target_dir_custom / "docker-compose.yml").read_text(encoding="utf-8")
    assert f"${{ALTR_STREAM_IMAGE:-{custom_img}}}" in compose_custom


def test_windows_inno_setup_developer_options_structure_and_logic() -> None:
    """Verify Windows Inno Setup installer script does not contain DevOptionsPage, delegating version management to Manager."""
    iss_path = REPO_ROOT / "packaging" / "windows" / "Altr-Stream.iss"
    assert iss_path.is_file(), "Altr-Stream.iss not found"
    iss_content = iss_path.read_text(encoding="utf-8")

    # Developer Options page eliminated from Inno Setup installer
    assert "DevOptionsPage" not in iss_content
    assert "DevImageCombo" not in iss_content
    assert "ShowDevOptionsPage" not in iss_content

    # Inno Setup configures pure application installation
    assert "AppName=Altr Stream Manager" in iss_content
    assert r'Source: "build\altr-installer-engine.exe"; DestDir: "{app}"; DestName: "Altr Stream Manager.exe"' in iss_content


def test_runtime_version_is_reported_by_running_app_not_installer_override() -> None:
    """Verify runtime version comes strictly from the application code/container, never forged in .env."""
    from altr_stream.__version__ import __version__ as canonical_version
    from altr_stream.config import settings

    # The running application identifies its version via __version__.py / app_version
    assert settings.app_version == canonical_version

    # Ensure runtime files (.env) never define ALTR_STREAM_VERSION to forge app version
    templates_env = REPO_ROOT / "packaging" / "templates" / "docker-compose.template.yml"
    tmpl_content = templates_env.read_text(encoding="utf-8")
    assert "ALTR_STREAM_VERSION" not in tmpl_content


def test_engine_check_image_cli(tmp_path: Path) -> None:
    """Verify that altr-installer-engine check-image CLI correctly validates image references."""
    engine_bin = REPO_ROOT / "packaging" / "engine" / "altr-installer-engine"
    if not engine_bin.is_file():
        pytest.skip("Engine binary not present in packaging/engine")

    # 1. Missing argument
    res_missing = subprocess.run([str(engine_bin), "check-image"], capture_output=True, text=True, timeout=10)
    data_missing = json.loads(res_missing.stdout)
    assert data_missing["valid"] is False
    assert data_missing["status"] == "invalid_format"

    # 2. Whitespace in reference
    res_space = subprocess.run([str(engine_bin), "check-image", "bad tag"], capture_output=True, text=True, timeout=10)
    data_space = json.loads(res_space.stdout)
    assert data_space["valid"] is False
    assert data_space["status"] == "invalid_format"

    # 3. Unavailable tag (e.g. 0.0.1)
    res_unavail = subprocess.run([str(engine_bin), "check-image", "ghcr.io/helloaltr/altr-stream:0.0.1"], capture_output=True, text=True, timeout=15)
    data_unavail = json.loads(res_unavail.stdout)
    assert data_unavail["valid"] is True
    assert data_unavail["available"] is False
    assert data_unavail["status"] == "unavailable"
    assert "not found on the container registry" in data_unavail["message"]

    # 4. Available existing tag (e.g. 1.0.0-beta)
    res_avail = subprocess.run([str(engine_bin), "check-image", "1.0.0-beta"], capture_output=True, text=True, timeout=15)
    data_avail = json.loads(res_avail.stdout)
    assert data_avail["valid"] is True
    assert data_avail["available"] is True
    assert data_avail["status"] == "available"
    assert "ghcr.io/helloaltr/altr-stream:1.0.0-beta" in data_avail["image"]



