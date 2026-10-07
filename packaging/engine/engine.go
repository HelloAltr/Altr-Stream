package main

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"
	"time"
)

// InstallerEngine is the core implementation of the cross-platform contract.
type InstallerEngine struct {
	dockerManager    *DockerManager
	lifecycleManager *LifecycleManager
	executor         CommandExecutor
	httpClient       HTTPClient
}

// NewInstallerEngine creates an engine instance.
func NewInstallerEngine(exec CommandExecutor, client HTTPClient) *InstallerEngine {
	dm := NewDockerManager(exec)
	lm := NewLifecycleManager(exec, client, dm)
	// If mock executor is passed, default HostPortChecker to a hermetic no-op so test suites are isolated from host state
	if _, isReal := exec.(*OSCommandExecutor); !isReal {
		lm.HostPortChecker = func(port int) error { return nil }
	}
	return &InstallerEngine{
		dockerManager:    dm,
		lifecycleManager: lm,
		executor:         exec,
		httpClient:       client,
	}
}

// SetHostPortChecker configures host port validation behavior (primarily for tests).
func (e *InstallerEngine) SetHostPortChecker(fn func(port int) error) {
	if e.lifecycleManager != nil {
		e.lifecycleManager.HostPortChecker = fn
	}
}

// isTemporaryDirectory returns true if path is inside a system temporary folder or test harness directory.
func isTemporaryDirectory(path string) bool {
	if os.Getenv("ALTR_STREAM_ALLOW_TMP_DIR") == "1" {
		return false
	}
	if path == "" {
		return false
	}
	p := filepath.Clean(path)
	tmp := filepath.Clean(os.TempDir())
	if tmp != "" && (p == tmp || strings.HasPrefix(p, tmp+string(filepath.Separator))) {
		return true
	}
	tempPrefixes := []string{"/tmp", "/private/var/folders", "/var/folders", "/private/tmp"}
	for _, prefix := range tempPrefixes {
		cleanPrefix := filepath.Clean(prefix)
		if p == cleanPrefix || strings.HasPrefix(p, cleanPrefix+string(filepath.Separator)) {
			return true
		}
	}
	if strings.Contains(p, "pytest-") || strings.Contains(p, "pytest_") {
		return true
	}
	return false
}

// DetectEnvironment retrieves system paths and configuration pointers.
func (e *InstallerEngine) DetectEnvironment() (*EnvironmentInfo, error) {
	home, err := os.UserHomeDir()
	if err != nil {
		home = os.Getenv("USERPROFILE")
		if home == "" {
			home = os.Getenv("HOME")
		}
	}

	defaultDir := filepath.Join(home, ".altr-stream")
	configFile := filepath.Join(home, ".altr-stream-config")

	if envCfg := os.Getenv("ALTR_STREAM_CONFIG_FILE"); envCfg != "" {
		configFile = envCfg
	}

	savedDir := ""
	if data, err := os.ReadFile(configFile); err == nil {
		candidate := strings.TrimSpace(string(data))
		if candidate != "" {
			// Reject temporary test directories unless explicitly requested via ALTR_STREAM_HOME
			if !isTemporaryDirectory(candidate) {
				composeFile := filepath.Join(candidate, "docker-compose.yml")
				if _, err := os.Stat(composeFile); err == nil {
					savedDir = candidate
				}
			}
		}
	}

	effectiveDir := defaultDir
	if envHome := os.Getenv("ALTR_STREAM_HOME"); envHome != "" {
		effectiveDir = envHome
	} else if savedDir != "" {
		effectiveDir = savedDir
	}

	isOneDrive := strings.Contains(strings.ToLower(effectiveDir), "onedrive") || strings.Contains(strings.ToLower(defaultDir), "onedrive")

	return &EnvironmentInfo{
		OS:           runtime.GOOS,
		Arch:         runtime.GOARCH,
		UserHome:     home,
		DefaultDir:   defaultDir,
		ConfigFile:   configFile,
		SavedDir:     savedDir,
		EffectiveDir: effectiveDir,
		IsOneDrive:   isOneDrive,
	}, nil
}

// CheckDocker inspects Docker prerequisites.
func (e *InstallerEngine) CheckDocker(ctx context.Context) (*DockerDiagnostics, error) {
	diag := e.dockerManager.CheckDocker(ctx)
	return &diag, nil
}

// LaunchDockerDesktop starts the official Docker Desktop app.
func (e *InstallerEngine) LaunchDockerDesktop(ctx context.Context) error {
	return e.dockerManager.LaunchDockerDesktop(ctx)
}

// UnpauseDockerDesktop resumes Docker Desktop when it is paused.
func (e *InstallerEngine) UnpauseDockerDesktop(ctx context.Context) error {
	return e.dockerManager.UnpauseDockerDesktop(ctx)
}

// OpenDockerSettings opens Docker Desktop's Settings interface.
func (e *InstallerEngine) OpenDockerSettings(ctx context.Context) error {
	return e.dockerManager.OpenDockerSettings(ctx)
}

// WaitForDocker polls Docker until it is ready or timeout occurs.
func (e *InstallerEngine) WaitForDocker(ctx context.Context, timeout time.Duration, progress func(time.Duration)) error {
	return e.dockerManager.WaitForDocker(ctx, timeout, progress)
}

// CheckContainerConflict checks if an 'altr-stream' container or required port conflict exists.
func (e *InstallerEngine) CheckContainerConflict(ctx context.Context) (*ConflictInfo, error) {
	env, _ := e.DetectEnvironment()
	targetDir := ""
	if env != nil {
		targetDir = env.EffectiveDir
	}
	return e.lifecycleManager.CheckConflict(ctx, DefaultPort, targetDir)
}

// CheckConflict inspects both port availability and existing target container conflicts.
func (e *InstallerEngine) CheckConflict(ctx context.Context, port int, targetDir string) (*ConflictInfo, error) {
	return e.lifecycleManager.CheckConflict(ctx, port, targetDir)
}

// SaveInstallDirectory writes the active install directory to the configuration file.
func (e *InstallerEngine) SaveInstallDirectory(dir string) error {
	env, err := e.DetectEnvironment()
	if err != nil {
		return err
	}
	// Never save temporary or test paths to the persistent user config file
	// unless ALTR_STREAM_CONFIG_FILE was explicitly set by a test runner
	if os.Getenv("ALTR_STREAM_CONFIG_FILE") == "" && isTemporaryDirectory(dir) {
		return nil
	}
	return os.WriteFile(env.ConfigFile, []byte(strings.TrimSpace(dir)), 0644)
}

// Install executes the 6-stage installation pipeline.
func (e *InstallerEngine) Install(ctx context.Context, cfg InstallConfig, progress ProgressFunc) error {
	if cfg.Port <= 0 {
		cfg.Port = DefaultPort
	}
	if cfg.HealthTimeout <= 0 {
		cfg.HealthTimeout = 60
	}

	totalStages := 6

	report := func(stage InstallStage, idx, percent int, msg string) {
		if progress != nil {
			progress(InstallProgress{
				Stage:       stage,
				StageIndex:  idx,
				TotalStages: totalStages,
				Percent:     percent,
				Message:     msg,
			})
		}
	}

	// Pre-flight 1: verify Docker is running
	diag := e.dockerManager.CheckDocker(ctx)
	if diag.State != DockerStateReady {
		return fmt.Errorf("docker engine is not ready: %s (%s)", diag.StatusText, diag.FailureReason)
	}

	// Pre-flight 2: check container and port conflicts before touching disk or containers
	conflict, err := e.lifecycleManager.CheckConflict(ctx, cfg.Port, cfg.TargetDir)
	if err != nil {
		return fmt.Errorf("pre-flight conflict check failed: %w", err)
	}
	if conflict != nil && conflict.Exists {
		// Port occupied by another container or process -> STOP immediately, do not proceed
		if conflict.ConflictType == ConflictTypePortDocker || conflict.ConflictType == ConflictTypePortProcess {
			return fmt.Errorf("pre-flight check failed: %s", conflict.RemediationHint)
		}
		// Target container 'altr-stream' exists
		if conflict.ConflictType == ConflictTypeContainer {
			if !cfg.ReplaceExisting {
				return fmt.Errorf("container '%s' already exists. Re-run with --replace-existing to overwrite", ContainerName)
			}
			// User explicitly authorized replacing existing container
			_ = e.lifecycleManager.RemoveContainer(ctx)

			// Verify port is free after removing the container
			if portErr := e.lifecycleManager.VerifyPortFree(ctx, cfg.Port); portErr != nil {
				return fmt.Errorf("pre-flight port check failed after removing existing container: %w", portErr)
			}
		}
	} else if cfg.ReplaceExisting {
		_ = e.lifecycleManager.RemoveContainer(ctx)
	}

	composeCmd := diag.ComposeCommand
	if composeCmd == "" {
		cli := e.dockerManager.ResolveDockerCLI()
		if cli == "" {
			cli = "docker"
		}
		composeCmd = cli + " compose"
	}

	// Stage 1: Runtime configuration
	report(StagePreparingConfig, 1, 10, "Writing configuration files...")
	if err := e.lifecycleManager.WriteRuntimeFiles(cfg.TargetDir, cfg); err != nil {
		return fmt.Errorf("stage '%s' failed: %w", StagePreparingConfig, err)
	}
	_ = e.SaveInstallDirectory(cfg.TargetDir)

	// Stage 2: Persistent storage volume
	report(StagePreparingVolume, 2, 25, "Ensuring persistent volume 'altr_stream_data'...")
	if err := e.lifecycleManager.EnsureDataVolume(ctx); err != nil {
		return fmt.Errorf("stage '%s' failed: %w", StagePreparingVolume, err)
	}

	// Stage 3: Pull image
	report(StagePullingImage, 3, 40, fmt.Sprintf("Pulling image %s...", cfg.Image))
	if err := e.lifecycleManager.PullImage(ctx, cfg.TargetDir, composeCmd, cfg.Image); err != nil {
		return fmt.Errorf("stage '%s' failed: %w", StagePullingImage, err)
	}

	// Stage 4: Starting container
	report(StageStartingContainer, 4, 60, "Creating and starting Altr Stream container...")
	if cfg.StartTimeout > 0 {
		e.lifecycleManager.StartTimeout = time.Duration(cfg.StartTimeout) * time.Second
	}
	if err := e.lifecycleManager.StartContainer(ctx, cfg.TargetDir, composeCmd, func(msg string) {
		report(StageStartingContainer, 4, 60, msg)
	}); err != nil {
		return fmt.Errorf("stage '%s' failed: %w", StageStartingContainer, err)
	}

	// Stage 5: Polling Healthcheck
	report(StageWaitingHealth, 5, 80, fmt.Sprintf("Waiting for health check on port %d...", cfg.Port))
	healthTimeout := time.Duration(cfg.HealthTimeout) * time.Second
	expectedVer := cfg.Version
	if strings.Contains(cfg.Image, ":") {
		parts := strings.Split(cfg.Image, ":")
		tag := parts[len(parts)-1]
		if tag != "" && tag != "latest" && tag != cfg.Version {
			expectedVer = cfg.Version + "|" + tag
		}
	}
	healthResp, err := e.lifecycleManager.VerifyHealth(ctx, cfg.Port, expectedVer, healthTimeout)
	if err != nil {
		return fmt.Errorf("stage '%s' failed: %w", StageWaitingHealth, err)
	}

	// Stage 6: Verifying installation (Real-time live multi-point verification)
	report(StageVerifying, 6, 95, "Verifying container availability, port mapping, and runtime health...")
	if err := e.lifecycleManager.VerifyInstallation(ctx, cfg, expectedVer); err != nil {
		return fmt.Errorf("stage '%s' failed: %w", StageVerifying, err)
	}

	report(StageVerifying, 6, 100, "Installation verified successfully.")
	_ = healthResp
	return nil
}

// Repair restores configuration and safely recreates containers without touching persistent storage.
func (e *InstallerEngine) Repair(ctx context.Context, targetDir string, cfg InstallConfig, progress ProgressFunc) error {
	if cfg.Port <= 0 {
		cfg.Port = DefaultPort
	}
	if cfg.HealthTimeout <= 0 {
		cfg.HealthTimeout = 60
	}
	cfg.TargetDir = targetDir

	totalStages := 4
	report := func(stage InstallStage, idx, percent int, msg string) {
		if progress != nil {
			progress(InstallProgress{
				Stage:       stage,
				StageIndex:  idx,
				TotalStages: totalStages,
				Percent:     percent,
				Message:     msg,
			})
		}
	}

	diag := e.dockerManager.CheckDocker(ctx)
	if diag.State != DockerStateReady {
		return fmt.Errorf("docker engine is not ready: %s (%s)", diag.StatusText, diag.FailureReason)
	}

	// Pre-flight: verify port is not occupied by an unrelated container or process
	portConflict, err := e.lifecycleManager.CheckPortConflict(ctx, cfg.Port)
	if err == nil && portConflict != nil && portConflict.Exists {
		return fmt.Errorf("repair cannot proceed: %s", portConflict.RemediationHint)
	}

	composeCmd := diag.ComposeCommand
	if composeCmd == "" {
		cli := e.dockerManager.ResolveDockerCLI()
		if cli == "" {
			cli = "docker"
		}
		composeCmd = cli + " compose"
	}

	// Stage 1: Restore runtime files
	report(StagePreparingConfig, 1, 25, "Restoring configuration files...")
	if err := e.lifecycleManager.WriteRuntimeFiles(targetDir, cfg); err != nil {
		return fmt.Errorf("failed to restore configuration files: %w", err)
	}
	_ = e.SaveInstallDirectory(targetDir)

	// Stage 2: Ensure data volume exists (without touching data)
	report(StagePreparingVolume, 2, 50, "Checking persistent volume...")
	if err := e.lifecycleManager.EnsureDataVolume(ctx); err != nil {
		return fmt.Errorf("failed to verify persistent volume: %w", err)
	}

	// Stage 3: Recreate container
	report(StageStartingContainer, 3, 75, "Recreating Altr Stream container...")
	if cfg.StartTimeout > 0 {
		e.lifecycleManager.StartTimeout = time.Duration(cfg.StartTimeout) * time.Second
	}
	if err := e.lifecycleManager.StartContainer(ctx, targetDir, composeCmd, func(msg string) {
		report(StageStartingContainer, 3, 75, msg)
	}); err != nil {
		return fmt.Errorf("failed to recreate container: %w", err)
	}

	// Stage 4: Health and runtime verification
	report(StageWaitingHealth, 4, 85, fmt.Sprintf("Waiting for health check on port %d...", cfg.Port))
	healthTimeout := time.Duration(cfg.HealthTimeout) * time.Second
	expectedVer := cfg.Version
	if strings.Contains(cfg.Image, ":") {
		parts := strings.Split(cfg.Image, ":")
		tag := parts[len(parts)-1]
		if tag != "" && tag != "latest" && tag != cfg.Version {
			expectedVer = cfg.Version + "|" + tag
		}
	}
	if _, err := e.lifecycleManager.VerifyHealth(ctx, cfg.Port, expectedVer, healthTimeout); err != nil {
		return fmt.Errorf("repair health verification failed: %w", err)
	}
	if err := e.lifecycleManager.VerifyInstallation(ctx, cfg, expectedVer); err != nil {
		return fmt.Errorf("repair installation verification failed: %w", err)
	}
	report(StageWaitingHealth, 4, 100, "Repair verified successfully.")
	return nil
}

// Uninstall halts the deployment, removes the container, cleans up runtime files,
// and optionally removes persistent data.
func (e *InstallerEngine) Uninstall(ctx context.Context, targetDir string, deleteData bool) error {
	if targetDir == "" {
		env, _ := e.DetectEnvironment()
		if env != nil {
			targetDir = env.EffectiveDir
		}
	}
	return e.lifecycleManager.Uninstall(ctx, targetDir, deleteData)
}

// GetStatus retrieves the live status of the installation.
func (e *InstallerEngine) GetStatus(ctx context.Context, targetDir string) (*NodeStatus, error) {
	if targetDir == "" {
		env, err := e.DetectEnvironment()
		if err != nil {
			return nil, err
		}
		targetDir = env.EffectiveDir
	}

	diag := e.dockerManager.CheckDocker(ctx)

	port := DefaultPort
	envFile := filepath.Join(targetDir, ".env")
	if data, err := os.ReadFile(envFile); err == nil {
		for _, line := range strings.Split(string(data), "\n") {
			line = strings.TrimSpace(line)
			if strings.HasPrefix(line, "ALTR_STREAM_PORT=") {
				val := strings.TrimPrefix(line, "ALTR_STREAM_PORT=")
				if p, err := strconv.Atoi(strings.TrimSpace(val)); err == nil && p > 0 {
					port = p
				}
			}
		}
	}

	webURL := fmt.Sprintf("http://localhost:%d", port)
	containerState := "not_installed"

	var technicalIssues []string

	if diag.EngineRunning {
		conflict, err := e.lifecycleManager.CheckContainerConflict(ctx)
		if err == nil && conflict.Exists {
			containerState = conflict.Status
		}
	} else {
		if diag.State == DockerStatePaused {
			technicalIssues = append(technicalIssues, "Docker Desktop is paused.")
		} else {
			technicalIssues = append(technicalIssues, "Docker daemon is not running.")
		}
	}

	// Probe healthcheck
	healthy := false
	var healthResp string
	if containerState == "running" {
		hCtx, cancel := context.WithTimeout(ctx, 2*time.Second)
		defer cancel()
		resp, err := e.lifecycleManager.probeEndpoint(hCtx, fmt.Sprintf("%s/api/v1/health", webURL))
		if err == nil {
			healthy = true
			healthResp = resp
		}
	}

	return &NodeStatus{
		InstallDir:      targetDir,
		TargetVersion:   DefaultCanonical,
		ContainerState:  containerState,
		Port:            port,
		WebURL:          webURL,
		DockerDiag:      diag,
		Healthy:         healthy,
		HealthResponse:  healthResp,
		TechnicalIssues: technicalIssues,
	}, nil
}

// LaunchBrowser opens the web application after verifying endpoint availability.
func (e *InstallerEngine) LaunchBrowser(ctx context.Context, targetURL string) error {
	return LaunchBrowser(ctx, e.executor, e.httpClient, targetURL)
}

// RemoveExistingContainer stops and removes only the conflicting container, preserving data.
func (e *InstallerEngine) RemoveExistingContainer(ctx context.Context) error {
	return e.lifecycleManager.RemoveContainer(ctx)
}

// StartExistingContainer starts the existing stopped container.
func (e *InstallerEngine) StartExistingContainer(ctx context.Context) error {
	return e.lifecycleManager.StartExistingContainer(ctx)
}

// UnpauseContainer resumes the existing paused container.
func (e *InstallerEngine) UnpauseContainer(ctx context.Context) error {
	return e.lifecycleManager.UnpauseContainer(ctx)
}
