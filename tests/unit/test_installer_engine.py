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
    res_docker = subprocess.run([str(out_bin), "check-docker"], capture_output=True, text=True, timeout=10)
    assert res_docker.returncode == 0
    docker_data = json.loads(res_docker.stdout)
    assert "state" in docker_data
    assert "cli_installed" in docker_data
    assert "desktop_installed" in docker_data
    assert "official_installer_url" in docker_data
    assert "https://" in docker_data["official_installer_url"]


def test_inno_setup_script_structure() -> None:
    """Verify Inno Setup 6 script definitions, engine bundling, and lifecycle semantics."""
    iss_path = REPO_ROOT / "packaging" / "windows" / "Altr-Stream.iss"
    assert iss_path.is_file(), f"Missing Inno Setup script at {iss_path}"

    content = iss_path.read_text(encoding="utf-8")

    # Product and version metadata
    assert '#define MyAppVersion "1.0.0-beta"' in content
    assert '#define MyDockerImage "ghcr.io/helloaltr/altr-stream:0.13.7-alpha"' in content
    assert "AppName=Altr Stream" in content
    assert "OutputBaseFilename=Altr-Stream-Installer" in content
    assert "ArchitecturesInstallIn64BitMode=x64compatible" in content
    assert "PrivilegesRequired=lowest" in content

    # Bundled files
    assert r'Source: "build\altr-installer-engine.exe"; DestDir: "{app}"' in content
    assert r'Source: "build\altr-installer-engine.exe"; DestDir: "{tmp}"; Flags: dontcopy' in content
    assert r'Source: "..\templates\INSTALLER_README.md"; DestDir: "{app}"; DestName: "README.txt"' in content

    # Engine-driven semantics
    assert "check-docker" in content
    assert "launch-docker" in content
    assert "wait-docker" in content
    assert "conflict" in content
    assert "install" in content
    assert "repair" in content
    assert "status" in content
    assert "uninstall" in content
    assert "--delete-data" in content

    # Start menu shortcuts
    assert "Altr Stream Web UI" in content
    assert "Altr Stream Status" in content
    assert "Altr Stream Repair" in content
    assert "Uninstall Altr Stream" in content

    # CLI parameter handling
    assert "InitializeSetup" in content
    assert "/REPAIR" in content
    assert "/STATUS" in content


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
    assert installer_exe.name == "Altr-Stream-Installer.exe"

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
    """Verify PrereqPage uses responsive full-width layout instead of narrow column."""
    iss_content = (REPO_ROOT / "packaging" / "windows" / "Altr-Stream.iss").read_text(encoding="utf-8")

    # Responsive width tied to SurfaceWidth
    assert "PrereqPage.SurfaceWidth - ScaleX(16)" in iss_content
    # AutoSize disabled so full width is respected
    assert "DockerStatusLabel.AutoSize := False;" in iss_content
    assert "DockerDetailLabel.AutoSize := False;" in iss_content
    # Word wrap enabled for detail explanation
    assert "DockerDetailLabel.WordWrap := True;" in iss_content
    # Narrow hardcoded widths must not be present
    assert "DockerStatusLabel.Width := ScaleX(400);" not in iss_content
    assert "DockerDetailLabel.Width := ScaleX(460);" not in iss_content


def test_inno_setup_default_install_dir_avoids_onedrive() -> None:
    """Verify installer resolves user profile directly and avoids redirected Documents/OneDrive."""
    iss_content = (REPO_ROOT / "packaging" / "windows" / "Altr-Stream.iss").read_text(encoding="utf-8")

    # Must use dynamic function instead of redirected {userdocs}\..
    assert "DefaultDirName={code:GetDefaultInstallDir}" in iss_content
    assert "DefaultDirName={userdocs}" not in iss_content

    # GetDefaultInstallDir checks USERPROFILE first
    assert "UserProfile := GetEnv('USERPROFILE');" in iss_content
    assert r"Result := UserProfile + '\.altr-stream';" in iss_content

    # wpSelectDir validates against accidental OneDrive directories
    assert "if CurPageID = wpSelectDir then" in iss_content
    assert r"Pos('\ONEDRIVE\', Uppercase(SelectedDir)) > 0" in iss_content


def test_inno_setup_progress_reporting_and_non_freezing_loop() -> None:
    """Verify live progress reporting, non-blocking execution, and message pumping."""
    iss_content = (REPO_ROOT / "packaging" / "windows" / "Altr-Stream.iss").read_text(encoding="utf-8")

    # Engine execution with real-time progress file and completion marker
    assert "--progress-file" in iss_content
    assert "install_progress.txt" in iss_content
    assert "install_done.txt" in iss_content
    assert "ewNoWait" in iss_content

    # Non-blocking loop updates UI and pumps Win32 messages
    assert "ProcessSystemMessages;" in iss_content
    assert "WizardForm.Refresh;" in iss_content
    assert "WizardForm.ProgressGauge.Position := CurPercent;" in iss_content
    assert "WizardForm.StatusLabel.Caption :=" in iss_content

    # Cancel button disabled during container provisioning for safety
    assert "WizardForm.CancelButton.Enabled := False;" in iss_content


def test_inno_setup_failure_state_machine_and_browser_guard() -> None:
    """Verify failure state machine never shows success finish page or runs browser launch."""
    iss_content = (REPO_ROOT / "packaging" / "windows" / "Altr-Stream.iss").read_text(encoding="utf-8")

    # Browser launch is strictly guarded by Check: IsInstallSuccessful
    assert "Check: IsInstallSuccessful" in iss_content
    assert "function IsInstallSuccessful: Boolean;" in iss_content

    # Finished page handles failure state distinctly from success
    assert "CurPageID = wpFinished" in iss_content
    assert "if not InstallSucceeded then" in iss_content
    assert "WizardForm.FinishedHeadingLabel.Caption := 'Altr Stream Setup Incomplete';" in iss_content
    assert "WizardForm.RunList.Visible := False;" in iss_content
    assert "start notepad.exe" in iss_content


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
    """Verify Inno Setup disables UsePreviousAppDir to avoid preserving stale OneDrive paths."""
    iss_content = (REPO_ROOT / "packaging" / "windows" / "Altr-Stream.iss").read_text(encoding="utf-8")

    # UsePreviousAppDir must be set to no
    assert "UsePreviousAppDir=no" in iss_content

    # DirEdit.Text is explicitly initialized in InitializeWizard
    assert "WizardForm.DirEdit.Text := GetDefaultInstallDir('');" in iss_content

    # wpSelectDir page entry checks and clears any OneDrive pre-fill
    assert "if CurPageID = wpSelectDir then" in iss_content
    assert "WizardForm.DirEdit.Text := GetDefaultInstallDir('');" in iss_content


def test_inno_setup_multi_layered_completion_and_error_capture() -> None:
    """Verify RunEngineWithProgress validates engine DoneFile, cmd !ERRORLEVEL!, progress, and output."""
    iss_content = (REPO_ROOT / "packaging" / "windows" / "Altr-Stream.iss").read_text(encoding="utf-8")

    # Delayed expansion /v:on and engine --done-file
    assert "/v:on" in iss_content
    assert "--done-file" in iss_content
    assert "!ERRORLEVEL!" in iss_content

    # Multi-point result validation
    assert "Pos('0|', DoneCodeStr) = 1" in iss_content
    assert "Pos('-1|', ProgLine)" in iss_content
    assert "Pos('|Failed|', ProgLine)" in iss_content
    assert "Pos('Installation failed:', FullOutput)" in iss_content


def test_inno_setup_heading_height_and_dpi_scaling() -> None:
    """Verify status heading and finish heading have explicit DPI-scaled heights preventing text clipping."""
    iss_content = (REPO_ROOT / "packaging" / "windows" / "Altr-Stream.iss").read_text(encoding="utf-8")

    # DockerStatusLabel has explicit height scaled with ScaleY
    assert "DockerStatusLabel.Height := ScaleY(30);" in iss_content
    assert "DockerStatusLabel.Font.Size := 11;" in iss_content
    assert "DockerDetailLabel.Top := ScaleY(48);" in iss_content
    assert "DockerDetailLabel.Height := ScaleY(120);" in iss_content

    # Finished page labels have enlarged height to avoid clipping multi-line explanations
    assert "WizardForm.FinishedHeadingLabel.Height := ScaleY(48);" in iss_content
    assert "WizardForm.FinishedLabel.Height := ScaleY(220);" in iss_content


def test_inno_setup_prerequisite_human_readable_and_no_raw_json() -> None:
    """Verify prerequisite UI uses human-readable explanations and hides raw diagnostic JSON."""
    iss_content = (REPO_ROOT / "packaging" / "windows" / "Altr-Stream.iss").read_text(encoding="utf-8")

    # Buttons for user actions
    assert "StartDockerBtn := TNewButton.Create(WizardForm);" in iss_content
    assert "StartDockerBtn.Caption := 'Start Docker Desktop';" in iss_content
    assert "RetryPrereqBtn := TNewButton.Create(WizardForm);" in iss_content
    assert "RetryPrereqBtn.Caption := 'Retry Check';" in iss_content
    assert "ViewPrereqDetailsBtn := TNewButton.Create(WizardForm);" in iss_content
    assert "ViewPrereqDetailsBtn.Caption := 'Technical Details...';" in iss_content

    # Technical diagnostics stored separately and only shown on demand
    assert "LastDockerDiagText := Trim(OutputStr);" in iss_content
    assert "Technical Diagnostic Details:" in iss_content

    # Human-readable state texts
    assert "Docker Desktop is Stopped" in iss_content
    assert "Docker Engine is currently offline" in iss_content
    assert "Docker Desktop is Not Installed" in iss_content
    assert "Docker Status: Attention Required" in iss_content

    # Primary label is never assigned raw OutputStr directly
    assert "DockerDetailLabel.Caption :=\n        'Docker was found, but reported an issue:' +\n        OutputStr" not in iss_content


def test_inno_setup_docker_not_ready_strictly_blocks_next() -> None:
    """Verify NextButtonClick strictly blocks proceeding if Docker is not ready."""
    iss_content = (REPO_ROOT / "packaging" / "windows" / "Altr-Stream.iss").read_text(encoding="utf-8")

    assert "if not DockerReady then" in iss_content
    assert "StartDockerBtnClick(nil);" in iss_content
    assert "Docker Engine must be running before installation can continue." in iss_content


def test_inno_setup_failure_page_has_clean_error_and_view_log_button() -> None:
    """Verify failure page isolates actionable error from milestones and includes View Log button."""
    iss_content = (REPO_ROOT / "packaging" / "windows" / "Altr-Stream.iss").read_text(encoding="utf-8")

    # Clean actionable error isolated in RunEngineWithProgress
    assert "DoneCodeStr, 3, Length(DoneCodeStr)" in iss_content
    assert "Pos('|Failed|', ProgLine)" in iss_content

    # View Log button on Finished page
    assert "ViewLogBtn := TNewButton.Create(WizardForm);" in iss_content
    assert "ViewLogBtn.Caption := 'View Installation Log';" in iss_content
    assert "ViewLogBtn.Parent := WizardForm.FinishedPage;" in iss_content
    assert "start notepad.exe" in iss_content


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
    """Verify Inno Setup script implements user-controlled file-sharing recovery dialog and explicit retry."""
    iss_content = (REPO_ROOT / "packaging" / "windows" / "Altr-Stream.iss").read_text(encoding="utf-8")

    # Recovery Dialog Form and Controls
    assert "ShowFileSharingRecoveryDialog" in iss_content
    assert "IsFileSharingRequired" in iss_content
    assert "RecovOpenBtn.Caption := 'Open Docker Settings';" in iss_content
    assert "RecovRetryBtn.Caption := 'Retry';" in iss_content
    assert "RecovDetailsBtn.Caption := 'Technical Details';" in iss_content
    assert "RecovCancelBtn.Caption := 'Cancel';" in iss_content

    # Launcher via engine and direct executable fallback
    assert "open-docker-settings" in iss_content
    assert "Docker Desktop.exe" in iss_content
    assert "BringDockerToFront" in iss_content

    # User-controlled retry loop in ssPostInstall
    assert "KeepRetrying := True;" in iss_content
    assert "while KeepRetrying do" in iss_content
    assert "UserChoice = CHOICE_RETRY" in iss_content


def test_open_docker_settings_fallback_and_no_false_claim() -> None:
    """Verify Open Docker Settings implements application fallback, foreground activation, and avoids false success claims."""
    main_code = (REPO_ROOT / "packaging" / "engine" / "main.go").read_text(encoding="utf-8")
    docker_code = (REPO_ROOT / "packaging" / "engine" / "docker.go").read_text(encoding="utf-8")
    win_code = (REPO_ROOT / "packaging" / "engine" / "platform_windows.go").read_text(encoding="utf-8")
    darwin_code = (REPO_ROOT / "packaging" / "engine" / "platform_darwin.go").read_text(encoding="utf-8")
    iss_content = (REPO_ROOT / "packaging" / "windows" / "Altr-Stream.iss").read_text(encoding="utf-8")

    # 1. Engine OpenDockerSettings executes LaunchDockerDesktop fallback
    assert "launchErr := d.LaunchDockerDesktop(ctx)" in docker_code
    assert 'docker-desktop://settings' in win_code
    assert 'docker-desktop://settings' in darwin_code

    # 2. No false claim that Settings was opened directly
    assert "Opened Docker Desktop settings." not in main_code
    assert "Docker Desktop Settings is opening." not in iss_content
    assert "Docker Desktop is opening." in iss_content
    assert "Docker Desktop launched. Please navigate to Settings" in main_code

    # 3. Inno Setup brings Docker Desktop to foreground with Win32 APIs
    assert "function FindWindow" in iss_content
    assert "function SetForegroundWindow" in iss_content
    assert "function ShowWindow" in iss_content
    assert "BringDockerToFront;" in iss_content


def test_inno_setup_recovery_dialog_valid_custom_form() -> None:
    """Verify recovery dialog avoids TSetupForm.Create (Resource TSetupForm not found) and uses CreateCustomForm."""
    iss_content = (REPO_ROOT / "packaging" / "windows" / "Altr-Stream.iss").read_text(encoding="utf-8")

    # Guard against invalid Delphi .dfm resource lookup
    assert "TSetupForm.Create" not in iss_content, (
        "TSetupForm.Create must NOT be used in Inno Setup Pascal Script; "
        "it causes runtime error 'Resource TSetupForm not found'. Use CreateCustomForm instead."
    )
    assert "TForm.Create" not in iss_content

    # Correct Inno Setup form API with dimension and scaling parameters
    assert "CreateCustomForm(ScaleX(520), ScaleY(340), False, False)" in iss_content
    assert "FlipAndCenterIfNeeded(True, WizardForm, False)" in iss_content
    assert "RecovPathEdit := TNewEdit.Create(RecoveryForm);" in iss_content
    assert "RecovRetryBtn.Default := True;" in iss_content
    assert "RecovCancelBtn.Cancel := True;" in iss_content

    # Stale log file cleanup before installation retry loop
    assert "DeleteFile(ExpandConstant('{app}\\.docker_start.log'));" in iss_content


def test_inno_setup_docker_startup_lifecycle_nonblocking_and_responsive() -> None:
    """Verify Inno Setup uses non-blocking execution, message pumping, and bounded polling for Docker startup."""
    iss_content = (REPO_ROOT / "packaging" / "windows" / "Altr-Stream.iss").read_text(encoding="utf-8")

    # 1. RunEngineCapture must use ewNoWait with message pumping instead of blocking ewWaitUntilTerminated
    assert "RunEngineCapture" in iss_content
    assert "ewNoWait" in iss_content
    assert "while (not FileExists(DoneFile)) and (GetTickCount - StartTick < 15000) do" in iss_content
    assert "ProcessSystemMessages;" in iss_content

    # 2. StartDockerBtnClick must implement bounded polling with active message pumping
    assert "procedure StartDockerBtnClick(Sender: TObject);" in iss_content
    assert "RunEngineCapture(EngineTmp, 'launch-docker', OutputStr);" in iss_content
    assert "MaxWaitMs := 75000;" in iss_content
    assert "while (GetTickCount - StartTick < MaxWaitMs) and (not DockerBecameReady) do" in iss_content
    assert "RunEngineCapture(EngineTmp, 'check-docker', OutputStr);" in iss_content
    assert "Pos('\"state\": \"ready\"', OutputStr) > 0" in iss_content
    assert "DockerBecameReady := True;" in iss_content

    # 3. Transitions to ready and enables NextButton
    assert "WizardForm.NextButton.Enabled := True;" in iss_content

    # 4. Monolithic blocking wait-docker with 60s freeze must NOT be in StartDockerBtnClick
    assert "RunEngineCapture(EngineTmp, 'wait-docker --timeout 60', OutputStr);" not in iss_content


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
    """Verify Altr-Stream.iss implements responsive Docker start polling and conflict resolution."""
    iss_path = REPO_ROOT / "packaging" / "windows" / "Altr-Stream.iss"
    assert iss_path.is_file(), f"{iss_path} not found"
    iss_content = iss_path.read_text(encoding="utf-8")

    # 1. Responsive non-blocking Docker Desktop start polling
    assert "StartDockerBtnClick" in iss_content
    assert "ProcessSystemMessages" in iss_content
    assert "WizardForm.Refresh" in iss_content
    assert "GetTickCount - StartTick < MaxWaitMs" in iss_content
    assert "check-docker" in iss_content
    assert "wait-docker --timeout" not in iss_content, (
        "Altr-Stream.iss must not call synchronous wait-docker inside StartDockerBtnClick to avoid UI freeze"
    )

    # 2. Container conflict detection & replacement flag forwarding
    assert "ShouldReplaceExisting: Boolean;" in iss_content
    assert "ShouldReplaceExisting := True;" in iss_content
    assert "if ShouldReplaceExisting then" in iss_content
    assert "InstallCmd := InstallCmd + ' --replace-existing';" in iss_content


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
    """Verify Altr-Stream.iss inspects conflict_type, detects port conflicts, and blocks installation."""
    iss_path = REPO_ROOT / "packaging" / "windows" / "Altr-Stream.iss"
    assert iss_path.is_file(), f"{iss_path} not found"
    iss_content = iss_path.read_text(encoding="utf-8")

    # Verify conflict_type parsing and handling
    assert "conflict_type" in iss_content
    assert "port_docker" in iss_content
    assert "port_process" in iss_content
    assert "Port conflict detected:" in iss_content
    assert 'Pos(\'"conflict_type": "port_docker"\', OutputStr) > 0' in iss_content
    assert 'Pos(\'"conflict_type": "port_process"\', OutputStr) > 0' in iss_content


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
