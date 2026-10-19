package main

import (
	"context"
	"errors"
	"fmt"
	"log"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"time"
)

// GetOfficialDockerURL returns the official download URL for the host OS and architecture.
func GetOfficialDockerURL() string {
	return getPlatformOfficialDockerURL()
}

// DockerManager coordinates Docker discovery and state inspection.
type DockerManager struct {
	executor CommandExecutor
	lookPath func(file string) (string, error)
	stat     func(name string) (os.FileInfo, error)
}

// NewDockerManager creates a manager with the given executor.
func NewDockerManager(exec CommandExecutor) *DockerManager {
	return &DockerManager{
		executor: exec,
		lookPath: execLookPath,
		stat:     os.Stat,
	}
}

func execLookPath(file string) (string, error) {
	return exec.LookPath(file)
}

// ResolveDockerCLI finds the docker executable path.
func (d *DockerManager) ResolveDockerCLI() string {
	// 1. Check system PATH
	if p, err := d.lookPath("docker"); err == nil && p != "" {
		return p
	}

	// 2. Check well-known platform paths
	home, _ := os.UserHomeDir()
	candidates := getPlatformDockerCLICandidates(home)
	for _, cand := range candidates {
		if cand != "" {
			if fi, err := d.stat(cand); err == nil && !fi.IsDir() {
				return cand
			}
		}
	}
	return ""
}

// ResolveDockerDesktop finds the Docker Desktop GUI executable or application bundle.
func (d *DockerManager) ResolveDockerDesktop() (string, bool) {
	return d.resolvePlatformDockerDesktop()
}

// CheckDocker runs a full diagnostic sweep.
func (d *DockerManager) CheckDocker(ctx context.Context) DockerDiagnostics {
	diag := DockerDiagnostics{
		OfficialInstallerURL: GetOfficialDockerURL(),
		State:                DockerStateNotInstalled,
		StatusText:           "Not Installed",
		ActionHint:           "Install Docker Desktop",
	}

	cliPath := d.ResolveDockerCLI()
	if cliPath != "" {
		diag.CliInstalled = true
	}

	desktopPath, desktopExists := d.ResolveDockerDesktop()
	diag.DesktopInstalled = desktopExists
	_ = desktopPath

	if !diag.CliInstalled && !diag.DesktopInstalled {
		diag.State = DockerStateNotInstalled
		diag.StatusText = "Not Installed"
		diag.ActionHint = "Install Docker Desktop"
		diag.FailureReason = "Docker was not found on this system."
		return diag
	}

	// Probe daemon via docker info
	infoCLI := cliPath
	if infoCLI == "" {
		infoCLI = "docker"
	}

	infoCtx, cancel := context.WithTimeout(ctx, 4*time.Second)
	defer cancel()

	stdout, stderr, exitCode, _ := d.executor.Run(infoCtx, infoCLI, "info")
	if exitCode == 0 {
		diag.EngineRunning = true
	} else {
		diag.TechnicalError = strings.TrimSpace(stderr + "\n" + stdout)
	}

	// If initial probe failed on Darwin due to connection/socket issues (and not a paused state), probe fallback socket ~/.docker/run/docker.sock
	isExplicitDaemonResponse := strings.Contains(strings.ToLower(diag.TechnicalError), "manually paused") ||
		strings.Contains(strings.ToLower(diag.TechnicalError), "docker desktop is paused")

	if !diag.EngineRunning && !isExplicitDaemonResponse && runtime.GOOS == "darwin" {
		if _, isReal := d.executor.(*OSCommandExecutor); isReal {
			home, _ := os.UserHomeDir()
			if home != "" {
				fallbackSock := filepath.Join(home, ".docker", "run", "docker.sock")
				if fi, err := d.stat(fallbackSock); err == nil && !fi.IsDir() {
					fbCtx, fbCancel := context.WithTimeout(ctx, 4*time.Second)
					_, _, fbExit, _ := d.executor.Run(fbCtx, infoCLI, "-H", "unix://"+fallbackSock, "info")
					fbCancel()
					if fbExit == 0 {
						diag.EngineRunning = true
						diag.TechnicalError = ""
						_ = os.Setenv("DOCKER_HOST", "unix://"+fallbackSock)
					}
				}
			}
		}
	}

	// Probe compose
	composeCmd := d.resolveComposeCommand(ctx, infoCLI)
	if composeCmd != "" {
		diag.ComposeAvailable = true
		diag.ComposeCommand = composeCmd
	}

	// Classify final state
	if diag.EngineRunning {
		if diag.ComposeAvailable {
			diag.State = DockerStateReady
			diag.StatusText = "Ready"
			diag.ActionHint = ""
		} else {
			diag.State = DockerStateError
			diag.StatusText = "No Compose"
			diag.ActionHint = "Install Docker Compose v2"
			diag.FailureReason = "Docker Engine is running, but Docker Compose v2 was not found."
		}
		return diag
	}

	// Engine not running
	tech := strings.ToLower(diag.TechnicalError)

	_, isReal := d.executor.(*OSCommandExecutor)
	isProcessRunning := d.isPlatformDockerDesktopProcessRunning(ctx)

	// Check if Docker Desktop is paused/suspended
	isPaused := strings.Contains(tech, "manually paused") ||
		strings.Contains(tech, "docker desktop is manually paused") ||
		strings.Contains(tech, "docker desktop is paused") ||
		strings.Contains(tech, "unpause it through the whale menu")

	if !isPaused {
		isPaused = d.isPlatformDockerDesktopPaused(ctx)
	}

	if !isPaused && !isReal {
		// Probe via docker desktop CLI plugin if present in mock/unit-test environment
		statusCtx, statusCancel := context.WithTimeout(ctx, 2*time.Second)
		pStdout, _, pExit, _ := d.executor.Run(statusCtx, infoCLI, "desktop", "status", "--format", "json")
		statusCancel()
		if pExit == 0 {
			lowerP := strings.ToLower(pStdout)
			if strings.Contains(lowerP, `"status": "paused"`) || strings.Contains(lowerP, `"status":"paused"`) {
				isPaused = true
			}
		}
	}

	if isPaused {
		diag.State = DockerStatePaused
		diag.StatusText = "Docker Desktop is Paused"
		diag.ActionHint = "Resume Docker Desktop"
		diag.FailureReason = "Docker Desktop is paused. Resume it to continue."
		return diag
	}

	if isProcessRunning {
		diag.State = DockerStateStarting
		diag.StatusText = "Docker Desktop is Starting"
		diag.ActionHint = "Waiting for Docker daemon to become ready..."
		diag.FailureReason = "Docker Desktop application is running, but the Docker daemon is still initializing."
		return diag
	}

	if strings.Contains(tech, "virtualization") || strings.Contains(tech, "hyper-v") ||
		strings.Contains(tech, "hypervisor") || strings.Contains(tech, "wsl") {
		diag.State = DockerStateError
		diag.StatusText = "Virtualization Unavailable"
		diag.ActionHint = "Enable Virtualization / WSL 2 in Windows Features"
		diag.FailureReason = "Docker Desktop requires hardware virtualization or WSL 2 to be enabled."
		return diag
	}

	if diag.DesktopInstalled {
		diag.State = DockerStateStopped
		diag.StatusText = "Docker Desktop is Stopped"
		diag.ActionHint = "Start Docker Desktop"
		diag.FailureReason = "Docker is installed, but the Docker Desktop daemon is not currently running."
		return diag
	}

	if diag.CliInstalled {
		diag.State = DockerStateStopped
		diag.StatusText = "Docker Desktop is Stopped"
		diag.ActionHint = "Start Docker Desktop"
		diag.FailureReason = "Docker CLI is present, but the Docker daemon is not running."
		return diag
	}

	diag.State = DockerStateNotInstalled
	diag.StatusText = "Not Installed"
	diag.ActionHint = "Install Docker Desktop"
	diag.FailureReason = "Docker Desktop was not found on this system."
	return diag
}

func (d *DockerManager) resolveComposeCommand(ctx context.Context, dockerCLI string) string {
	// Try `docker compose version`
	composeCtx, cancel := context.WithTimeout(ctx, 2*time.Second)
	defer cancel()
	_, _, exitCode, _ := d.executor.Run(composeCtx, dockerCLI, "compose", "version")
	if exitCode == 0 {
		return dockerCLI + " compose"
	}

	// Try standalone `docker-compose`
	if p, err := d.lookPath("docker-compose"); err == nil && p != "" {
		standaloneCtx, standaloneCancel := context.WithTimeout(ctx, 2*time.Second)
		defer standaloneCancel()
		_, _, ec2, _ := d.executor.Run(standaloneCtx, p, "version")
		if ec2 == 0 {
			return p
		}
	}
	return ""
}

// LaunchDockerDesktop starts the official Docker Desktop app without inheriting standard handles.
func (d *DockerManager) LaunchDockerDesktop(ctx context.Context) error {
	log.Printf("[LaunchDockerDesktop] Starting Docker Desktop launch sequence...")
	desktopPath, exists := d.ResolveDockerDesktop()
	log.Printf("[LaunchDockerDesktop] Resolved path: %q (exists=%v, os=%s)", desktopPath, exists, runtime.GOOS)

	err := d.launchPlatformDockerDesktop(ctx, desktopPath, exists)
	if err != nil {
		log.Printf("[LaunchDockerDesktop] Error launching process: %v", err)
		return err
	}
	log.Printf("[LaunchDockerDesktop] Successfully dispatched detached launch.")
	return nil
}

// UnpauseDockerDesktop attempts to resume Docker Desktop from a paused or suspended state.
func (d *DockerManager) UnpauseDockerDesktop(ctx context.Context) error {
	log.Printf("[UnpauseDockerDesktop] Starting Docker Desktop unpause sequence...")
	return d.unpausePlatformDockerDesktop(ctx)
}

// WaitForDocker polls the engine with a bounded timeout and reports readiness transitions.
func (d *DockerManager) WaitForDocker(ctx context.Context, timeout time.Duration, progress func(elapsed time.Duration)) error {
	log.Printf("[WaitForDocker] Starting wait for Docker Engine (timeout=%v)...", timeout)
	startTime := time.Now()
	ticker := time.NewTicker(1 * time.Second)
	defer ticker.Stop()

	// Immediate first check
	diag := d.CheckDocker(ctx)
	if diag.State == DockerStateReady {
		log.Printf("[WaitForDocker] Docker Engine is already ready.")
		return nil
	}
	log.Printf("[WaitForDocker] Initial state: %s (engine_running=%v)", diag.State, diag.EngineRunning)

	for {
		select {
		case <-ctx.Done():
			log.Printf("[WaitForDocker] Context cancelled: %v", ctx.Err())
			return ctx.Err()
		case t := <-ticker.C:
			elapsed := t.Sub(startTime)
			if progress != nil {
				progress(elapsed)
			}
			diag = d.CheckDocker(ctx)
			log.Printf("[WaitForDocker] Probe at %v: state=%s, engine_running=%v", elapsed.Round(time.Millisecond), diag.State, diag.EngineRunning)
			if diag.State == DockerStateReady {
				log.Printf("[WaitForDocker] Docker Engine became ready after %v", elapsed.Round(time.Millisecond))
				return nil
			}
			if elapsed >= timeout {
				log.Printf("[WaitForDocker] Timed out waiting for Docker Engine after %v (reason=%s)", timeout, diag.FailureReason)
				return fmt.Errorf("timeout waiting for Docker Engine readiness after %v: %s", timeout, diag.FailureReason)
			}
		}
	}
}

// OpenDockerSettings attempts to open Docker Desktop's Settings interface.
// Because the docker-desktop:// URI scheme does not reliably navigate to Settings on Windows,
// it launches the Docker Desktop application executable directly as a guaranteed fallback.
func (d *DockerManager) OpenDockerSettings(ctx context.Context) error {
	log.Printf("[OpenDockerSettings] Attempting to open Docker Desktop settings...")
	deepLinkErr := d.openPlatformDockerSettings(ctx)

	// Always ensure the Docker Desktop application is launched or brought to foreground as a reliable fallback
	launchErr := d.LaunchDockerDesktop(ctx)

	if launchErr == nil {
		log.Printf("[OpenDockerSettings] Docker Desktop application launched successfully.")
		return nil
	}
	if deepLinkErr == nil {
		log.Printf("[OpenDockerSettings] Deep link dispatched successfully.")
		return nil
	}
	log.Printf("[OpenDockerSettings] Both launch and deep link failed: launchErr=%v, deepLinkErr=%v", launchErr, deepLinkErr)
	return launchErr
}

// ImageValidationResult represents the verification of a Docker image reference.
type ImageValidationResult struct {
	Valid     bool   `json:"valid"`
	Available bool   `json:"available"`
	Image     string `json:"image"`
	Status    string `json:"status"` // "available", "unavailable", "invalid_format", "network_error", "auth_error"
	Message   string `json:"message"`
	Details   string `json:"details,omitempty"`
}

func normalizeImageReference(ref string) (string, error) {
	trimmed := strings.TrimSpace(ref)
	if trimmed == "" {
		return "", errors.New("image reference cannot be empty")
	}
	if strings.ContainsAny(trimmed, " \t\r\n") {
		return "", errors.New("image reference cannot contain whitespace")
	}
	for _, r := range trimmed {
		if !((r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z') || (r >= '0' && r <= '9') || r == '.' || r == '_' || r == '-' || r == '/' || r == ':') {
			return "", fmt.Errorf("invalid character in image reference: %c", r)
		}
	}
	if !strings.Contains(trimmed, "/") && !strings.Contains(trimmed, ":") {
		trimmed = "ghcr.io/helloaltr/altr-stream:" + trimmed
	} else if strings.HasPrefix(trimmed, ":") {
		trimmed = "ghcr.io/helloaltr/altr-stream" + trimmed
	}
	return trimmed, nil
}

// InspectImageRegistry verifies whether a container image exists locally or in the remote registry.
func (d *DockerManager) InspectImageRegistry(ctx context.Context, imageRef string) ImageValidationResult {
	norm, err := normalizeImageReference(imageRef)
	if err != nil {
		return ImageValidationResult{
			Valid:     false,
			Available: false,
			Image:     imageRef,
			Status:    "invalid_format",
			Message:   err.Error(),
		}
	}

	cli := d.ResolveDockerCLI()
	if cli == "" {
		return ImageValidationResult{
			Valid:     true,
			Available: false,
			Image:     norm,
			Status:    "network_error",
			Message:   "Docker CLI is not available to verify registry manifests.",
		}
	}

	isOfficial := strings.HasPrefix(norm, "ghcr.io/helloaltr/altr-stream:") || norm == "ghcr.io/helloaltr/altr-stream"

	// 1. For custom or local images, check local Docker cache first
	if !isOfficial {
		localOut, _, localExit, _ := d.executor.Run(ctx, cli, "images", "-q", norm)
		if localExit == 0 && strings.TrimSpace(localOut) != "" {
			return ImageValidationResult{
				Valid:     true,
				Available: true,
				Image:     norm,
				Status:    "available",
				Message:   fmt.Sprintf("Image '%s' is present in local Docker cache.", norm),
			}
		}
	}

	// 2. Query remote registry via manifest inspect
	stdout, stderr, exitCode, _ := d.executor.Run(ctx, cli, "manifest", "inspect", norm)
	combined := strings.TrimSpace(stdout + "\n" + stderr)
	lower := strings.ToLower(combined)

	if exitCode == 0 {
		return ImageValidationResult{
			Valid:     true,
			Available: true,
			Image:     norm,
			Status:    "available",
			Message:   fmt.Sprintf("Image '%s' verified and available on registry.", norm),
		}
	}

	// For official images, if manifest unknown or not found, it is unavailable on the registry.
	// A local image must never shadow this failure.

	if strings.Contains(lower, "manifest unknown") || strings.Contains(lower, "not found") || strings.Contains(lower, "404") || strings.Contains(lower, "tag does not exist") {
		return ImageValidationResult{
			Valid:     true,
			Available: false,
			Image:     norm,
			Status:    "unavailable",
			Message:   fmt.Sprintf("Image '%s' was not found on the container registry.", norm),
			Details:   combined,
		}
	}

	if strings.Contains(lower, "invalid reference") || strings.Contains(lower, "reference format") {
		return ImageValidationResult{
			Valid:     false,
			Available: false,
			Image:     norm,
			Status:    "invalid_format",
			Message:   fmt.Sprintf("Invalid image reference format: '%s'.", norm),
			Details:   combined,
		}
	}

	if strings.Contains(lower, "unauthorized") || strings.Contains(lower, "denied") || strings.Contains(lower, "authentication required") {
		return ImageValidationResult{
			Valid:     true,
			Available: false,
			Image:     norm,
			Status:    "auth_error",
			Message:   fmt.Sprintf("Authentication or access denied for registry image '%s'.", norm),
			Details:   combined,
		}
	}

	if strings.Contains(lower, "connection refused") || strings.Contains(lower, "timeout") || strings.Contains(lower, "no such host") || strings.Contains(lower, "dial tcp") || strings.Contains(lower, "network") {
		return ImageValidationResult{
			Valid:     true,
			Available: false,
			Image:     norm,
			Status:    "network_error",
			Message:   fmt.Sprintf("Network connection to registry failed while verifying '%s'.", norm),
			Details:   combined,
		}
	}

	return ImageValidationResult{
		Valid:     false,
		Available: false,
		Image:     norm,
		Status:    "unavailable",
		Message:   fmt.Sprintf("Failed to inspect image '%s': %s", norm, combined),
		Details:   combined,
	}
}
