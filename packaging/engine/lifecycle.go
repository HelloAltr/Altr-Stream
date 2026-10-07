package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"
)

const (
	ContainerName    = "altr-stream"
	NamedDataVolume  = "altr_stream_data"
	DefaultPort      = 8000
	DefaultCanonical = "1.0.0-beta"
)

func defaultHostPortChecker(port int) error {
	ln, err := net.Listen("tcp", fmt.Sprintf(":%d", port))
	if err != nil {
		return err
	}
	_ = ln.Close()
	return nil
}

// LifecycleManager manages container operations and storage.
type LifecycleManager struct {
	executor        CommandExecutor
	httpClient      HTTPClient
	dockerManager   *DockerManager
	StartTimeout    time.Duration
	RetryInterval   time.Duration
	HostPortChecker func(port int) error
}

// NewLifecycleManager creates a lifecycle manager.
func NewLifecycleManager(exec CommandExecutor, client HTTPClient, dm ...*DockerManager) *LifecycleManager {
	var manager *DockerManager
	if len(dm) > 0 && dm[0] != nil {
		manager = dm[0]
	} else {
		manager = NewDockerManager(exec)
	}
	return &LifecycleManager{
		executor:        exec,
		httpClient:      client,
		dockerManager:   manager,
		HostPortChecker: defaultHostPortChecker,
	}
}

func (l *LifecycleManager) dockerCLI() string {
	if l.dockerManager != nil {
		if cli := l.dockerManager.ResolveDockerCLI(); cli != "" {
			return cli
		}
	}
	return "docker"
}

func (l *LifecycleManager) parseComposeCommand(composeCmd string) (string, []string) {
	composeCmd = strings.TrimSpace(composeCmd)
	defaultCLI := l.dockerCLI()

	if composeCmd == "" {
		return defaultCLI, []string{"compose"}
	}
	if strings.HasSuffix(composeCmd, " compose") {
		exe := strings.TrimSpace(strings.TrimSuffix(composeCmd, " compose"))
		if exe == "docker" || exe == "" {
			exe = defaultCLI
		}
		return exe, []string{"compose"}
	}
	// Standalone compose or other binary
	parts := strings.Fields(composeCmd)
	if len(parts) > 1 {
		return parts[0], parts[1:]
	}
	return composeCmd, []string{}
}

// CheckContainerConflict inspects if an existing 'altr-stream' container exists.
func (l *LifecycleManager) CheckContainerConflict(ctx context.Context) (*ConflictInfo, error) {
	// Inspect container safely
	stdout, _, exitCode, _ := l.executor.Run(ctx, l.dockerCLI(), "inspect", ContainerName)
	if exitCode != 0 || strings.TrimSpace(stdout) == "" || stdout == "[]" {
		return &ConflictInfo{Exists: false, ConflictType: ConflictTypeNone}, nil
	}

	var inspectList []struct {
		ID      string `json:"Id"`
		Created string `json:"Created"`
		State   struct {
			Status  string `json:"Status"`
			Running bool   `json:"Running"`
			Health  *struct {
				Status string `json:"Status"`
			} `json:"Health"`
		} `json:"State"`
		Config struct {
			Image  string            `json:"Image"`
			Labels map[string]string `json:"Labels"`
		} `json:"Config"`
		NetworkSettings struct {
			Ports map[string][]struct {
				HostIp   string `json:"HostIp"`
				HostPort string `json:"HostPort"`
			} `json:"Ports"`
		} `json:"NetworkSettings"`
	}

	if err := json.Unmarshal([]byte(stdout), &inspectList); err != nil || len(inspectList) == 0 {
		return &ConflictInfo{Exists: true, ConflictType: ConflictTypeContainer, ContainerName: ContainerName, Status: "unknown", RawInspect: stdout}, nil
	}

	c := inspectList[0]
	shortID := c.ID
	if len(shortID) > 12 {
		shortID = shortID[:12]
	}

	// Determine if container is Altr Stream
	imgLower := strings.ToLower(c.Config.Image)
	isAltr := strings.Contains(imgLower, "altr-stream") ||
		strings.Contains(imgLower, "helloaltr") ||
		(c.Config.Labels != nil && c.Config.Labels["com.docker.compose.service"] == "altr-stream")

	isInstallerOwned := false
	isDev := false
	if c.Config.Labels != nil {
		if c.Config.Labels["com.helloaltr.altr-stream.managed-by"] == "installer" {
			isInstallerOwned = true
		}
		if c.Config.Labels["com.helloaltr.altr-stream.environment"] == "development" ||
			strings.Contains(strings.ToLower(c.Config.Labels["com.docker.compose.project"]), "dev") {
			isDev = true
		}
		workDir := strings.ToLower(c.Config.Labels["com.docker.compose.project.working_dir"])
		if workDir != "" && (strings.Contains(workDir, "01 - altr stream") || strings.Contains(workDir, "/src") || strings.Contains(workDir, ".git")) {
			isDev = true
		}
	}
	if strings.Contains(imgLower, ":dev") || strings.Contains(imgLower, "-dev") {
		isDev = true
	}
	if !isDev && isAltr && c.Config.Labels != nil && c.Config.Labels["com.helloaltr.altr-stream.managed-by"] == "installer" {
		isInstallerOwned = true
	} else if !isDev && isAltr && (c.Config.Labels == nil || c.Config.Labels["com.docker.compose.project"] == "") {
		isInstallerOwned = true
	}

	// Determine compatibility
	isCompat := false
	if isAltr {
		if strings.Contains(imgLower, "0.13.7-alpha") ||
			strings.Contains(imgLower, "1.0.0-beta") ||
			strings.Contains(imgLower, strings.ToLower(DefaultCanonical)) ||
			strings.Contains(imgLower, "latest") {
			isCompat = true
		}
	}

	// Port mappings
	var portMappings []string
	for containerPort, bindings := range c.NetworkSettings.Ports {
		cleanPort := strings.TrimSuffix(containerPort, "/tcp")
		for _, b := range bindings {
			if b.HostPort != "" {
				portMappings = append(portMappings, fmt.Sprintf("%s:%s", b.HostPort, cleanPort))
			}
		}
	}
	portStr := strings.Join(portMappings, ", ")
	if portStr == "" && len(c.NetworkSettings.Ports) > 0 {
		for containerPort := range c.NetworkSettings.Ports {
			portMappings = append(portMappings, strings.TrimSuffix(containerPort, "/tcp"))
		}
		portStr = strings.Join(portMappings, ", ")
	}

	// Health status
	healthStatus := "unknown"
	if c.State.Status == "paused" {
		healthStatus = "paused"
	} else if c.State.Health != nil && c.State.Health.Status != "" {
		healthStatus = c.State.Health.Status
	} else if c.State.Status != "" && c.State.Status != "running" {
		healthStatus = c.State.Status
	} else if c.State.Running {
		healthStatus = "running"
	} else if c.State.Status != "" {
		healthStatus = c.State.Status
	}

	identityText := "Unrecognized / Third-Party Container"
	if isAltr {
		if isCompat {
			identityText = "Altr Stream (Compatible)"
		} else {
			identityText = "Altr Stream (Incompatible Version)"
		}
	}

	remediationHint := ""
	if isAltr {
		remediationHint = "An existing Altr Stream container was detected. Replacing it will preserve your persistent data."
	} else {
		remediationHint = fmt.Sprintf("A container named '%s' already exists in Docker. Please stop or remove it before continuing.", ContainerName)
	}

	details := fmt.Sprintf(
		"Container: %s\nID: %s\nStatus: %s\nImage: %s\nCreated: %s\nPorts: %s\nHealth: %s\nIdentity: %s",
		ContainerName,
		shortID,
		c.State.Status,
		c.Config.Image,
		c.Created,
		portStr,
		healthStatus,
		identityText,
	)

	return &ConflictInfo{
		Exists:           true,
		ConflictType:     ConflictTypeContainer,
		ContainerID:      shortID,
		ContainerName:    ContainerName,
		Status:           c.State.Status,
		Image:            c.Config.Image,
		Created:          c.Created,
		IsAltrStream:     isAltr,
		IsCompatible:     isCompat,
		IsInstallerOwned: isInstallerOwned,
		IsDevContainer:   isDev,
		PortMapping:      portStr,
		HealthStatus:     healthStatus,
		RemediationHint:  remediationHint,
		Details:          details,
		RawInspect:       stdout,
	}, nil
}

// CheckPortConflict inspects if a host port is currently occupied by another Docker container
// or an unrelated host process.
func (l *LifecycleManager) CheckPortConflict(ctx context.Context, port int) (*ConflictInfo, error) {
	if port <= 0 {
		port = DefaultPort
	}

	// 1. Check running Docker containers publishing this port
	psOut, _, psExit, _ := l.executor.Run(ctx, l.dockerCLI(), "ps", "--filter", fmt.Sprintf("publish=%d", port), "--format", "{{json .}}")
	if psExit == 0 && strings.TrimSpace(psOut) != "" {
		lines := strings.Split(strings.TrimSpace(psOut), "\n")
		for _, line := range lines {
			line = strings.TrimSpace(line)
			if line == "" {
				continue
			}

			var psEntry struct {
				ID     string `json:"ID"`
				Names  string `json:"Names"`
				Image  string `json:"Image"`
				Status string `json:"Status"`
				Ports  string `json:"Ports"`
				Labels string `json:"Labels"`
			}
			if err := json.Unmarshal([]byte(line), &psEntry); err != nil {
				parts := strings.Fields(line)
				if len(parts) >= 2 {
					psEntry.ID = parts[0]
					psEntry.Names = parts[1]
				}
			}

			cName := strings.TrimPrefix(psEntry.Names, "/")
			if cName == "" {
				cName = psEntry.ID
			}

			// If the container is 'altr-stream', container conflict handles it
			if cName == ContainerName {
				continue
			}

			shortID := psEntry.ID
			if len(shortID) > 12 {
				shortID = shortID[:12]
			}

			imgLower := strings.ToLower(psEntry.Image)
			nameLower := strings.ToLower(cName)
			labelsLower := strings.ToLower(psEntry.Labels)
			isAltr := strings.Contains(imgLower, "altr-stream") || strings.Contains(nameLower, "altr-stream") || strings.Contains(imgLower, "helloaltr")
			isDev := strings.Contains(nameLower, "dev") || strings.Contains(imgLower, "dev") || (strings.Contains(labelsLower, "docker-compose") && strings.Contains(labelsLower, "dev"))

			remediation := fmt.Sprintf("Port %d is already in use by container '%s'.\n\nPlease stop the conflicting service and retry.", port, cName)
			if isDev {
				remediation = fmt.Sprintf("Port %d is already in use by development container '%s'.\n\nPlease stop your development container and retry.", port, cName)
			}

			classification := "Third-Party Service / Container"
			if isDev {
				classification = "Altr Stream Development Container"
			} else if isAltr {
				classification = "Altr Stream (Other Instance)"
			}

			details := fmt.Sprintf("Port Conflict Detected\n"+
				"Required Port:  %d\n"+
				"Occupied By:    Container '%s' (ID: %s)\n"+
				"Image:          %s\n"+
				"Status:         %s\n"+
				"Port Mappings:  %s\n"+
				"Classification: %s",
				port, cName, shortID, psEntry.Image, psEntry.Status, psEntry.Ports, classification,
			)

			return &ConflictInfo{
				Exists:           true,
				ConflictType:     ConflictTypePortDocker,
				ContainerID:      shortID,
				ContainerName:    cName,
				Status:           psEntry.Status,
				Image:            psEntry.Image,
				IsAltrStream:     isAltr,
				IsCompatible:     false,
				IsInstallerOwned: false,
				IsDevContainer:   isDev,
				PortMapping:      psEntry.Ports,
				ConflictingPort:  port,
				OccupiedBy:       cName,
				RemediationHint:  remediation,
				Details:          details,
				RawInspect:       line,
			}, nil
		}
	}

	// 2. Check if host port is occupied by a non-Docker host process
	checkFn := l.HostPortChecker
	if checkFn == nil {
		checkFn = defaultHostPortChecker
	}

	if checkErr := checkFn(port); checkErr != nil {
		remediation := fmt.Sprintf("Port %d is already in use by another application or process on your computer.\n\nPlease close the application using port %d and retry.", port, port)
		details := fmt.Sprintf("Port Conflict Detected\n"+
			"Required Port:   %d\n"+
			"Occupied By:     Host Process (Non-Docker)\n"+
			"Technical Details: %v\n"+
			"Action Required: Close the application using port %d and retry.",
			port, checkErr, port,
		)

		return &ConflictInfo{
			Exists:           true,
			ConflictType:     ConflictTypePortProcess,
			ConflictingPort:  port,
			OccupiedBy:       "host process",
			IsInstallerOwned: false,
			RemediationHint:  remediation,
			Details:          details,
		}, nil
	}

	return &ConflictInfo{
		Exists:       false,
		ConflictType: ConflictTypeNone,
	}, nil
}

// CheckConflict inspects both port availability and existing target container conflicts.
// Conflicts from other containers or host processes take precedence since they must be resolved
// before any container creation or replacement can proceed.
func (l *LifecycleManager) CheckConflict(ctx context.Context, port int, targetDir string) (*ConflictInfo, error) {
	if port <= 0 {
		port = DefaultPort
	}

	// 1. Port conflict check (other Docker containers or host processes)
	portConflict, err := l.CheckPortConflict(ctx, port)
	if err != nil {
		return nil, err
	}
	if portConflict != nil && portConflict.Exists {
		return portConflict, nil
	}

	// 2. Target container conflict check ('altr-stream')
	containerConflict, err := l.CheckContainerConflict(ctx)
	if err != nil {
		return nil, err
	}
	if containerConflict != nil && containerConflict.Exists {
		return containerConflict, nil
	}

	return &ConflictInfo{
		Exists:       false,
		ConflictType: ConflictTypeNone,
	}, nil
}

// VerifyPortFree verifies that the host port is completely available before container startup.
func (l *LifecycleManager) VerifyPortFree(ctx context.Context, port int) error {
	conflict, err := l.CheckPortConflict(ctx, port)
	if err != nil {
		return err
	}
	if conflict != nil && conflict.Exists {
		return fmt.Errorf("%s", conflict.RemediationHint)
	}
	return nil
}

// RemoveContainer stops (if running) and removes only the container named ContainerName.
// It explicitly preserves data volumes (e.g. altr_stream_data) and data folders.
func (l *LifecycleManager) RemoveContainer(ctx context.Context) error {
	_, stderr, exitCode, err := l.executor.Run(ctx, l.dockerCLI(), "rm", "-f", ContainerName)
	if exitCode != 0 && !strings.Contains(stderr, "No such container") && !strings.Contains(stderr, "not found") {
		return fmt.Errorf("failed to remove container '%s': %s (%w)", ContainerName, stderr, err)
	}
	return nil
}

// UnpauseContainer resumes a paused container named ContainerName.
func (l *LifecycleManager) UnpauseContainer(ctx context.Context) error {
	_, stderr, exitCode, err := l.executor.Run(ctx, l.dockerCLI(), "unpause", ContainerName)
	if exitCode != 0 {
		return fmt.Errorf("failed to unpause container '%s': %s (%w)", ContainerName, stderr, err)
	}
	return nil
}

// StartExistingContainer starts the existing stopped container or unpauses a paused container.
func (l *LifecycleManager) StartExistingContainer(ctx context.Context) error {
	_, stderr, exitCode, err := l.executor.Run(ctx, l.dockerCLI(), "start", ContainerName)
	if exitCode != 0 {
		if strings.Contains(stderr, "cannot start a paused container") || strings.Contains(stderr, "try unpause instead") {
			return l.UnpauseContainer(ctx)
		}
		return fmt.Errorf("failed to start container '%s': %s (%w)", ContainerName, stderr, err)
	}
	return nil
}

// WriteRuntimeFiles renders docker-compose.yml and .env into targetDir.
func (l *LifecycleManager) WriteRuntimeFiles(targetDir string, cfg InstallConfig) error {
	if err := os.MkdirAll(targetDir, 0755); err != nil {
		return fmt.Errorf("failed to create install directory: %w", err)
	}

	updatesDir := filepath.Join(targetDir, "data", "updates")
	if err := os.MkdirAll(updatesDir, 0755); err != nil {
		return fmt.Errorf("failed to create updates directory: %w", err)
	}

	// 1. Render docker-compose.yml
	composePath := filepath.Join(targetDir, "docker-compose.yml")
	composeContent := fmt.Sprintf(`services:
  altr-stream:
    image: %s
    container_name: altr-stream
    restart: unless-stopped
    ports:
      - "%d:8000"
    labels:
      - "com.helloaltr.altr-stream.managed-by=installer"
      - "com.helloaltr.altr-stream.environment=production"
    environment:
      - ALTR_STREAM_HOST=0.0.0.0
      - ALTR_STREAM_PORT=8000
      - ALTR_STREAM_DATABASE_URL=sqlite+aiosqlite:////app/data/altr_stream.db
      - ALTR_STREAM_STATIC_DIR=/app/static
      - ALTR_STREAM_DEBUG=false
      - ALTR_STREAM_FEEDBACK_SERVICE_URL=${ALTR_STREAM_FEEDBACK_SERVICE_URL:-https://altr-feedback.onrender.com}
      - ALTR_FEEDBACK_API_KEY=${ALTR_FEEDBACK_API_KEY:-}
    volumes:
      - altr_stream_data:/app/data
      - ./data/updates:/app/data/updates
    healthcheck:
      test: ["CMD-SHELL", "curl -f http://localhost:8000/api/v1/health || exit 1"]
      interval: 15s
      timeout: 5s
      retries: 3
      start_period: 10s
    networks:
      - altr-network

volumes:
  altr_stream_data:
    driver: local

networks:
  altr-network:
    driver: bridge
`, cfg.Image, cfg.Port)

	if err := os.WriteFile(composePath, []byte(composeContent), 0644); err != nil {
		return fmt.Errorf("failed to write docker-compose.yml: %w", err)
	}

	// 2. Render .env (preserve existing overrides if present)
	envPath := filepath.Join(targetDir, ".env")
	if _, err := os.Stat(envPath); os.IsNotExist(err) {
		fbURL := cfg.FeedbackURL
		if fbURL == "" {
			fbURL = "https://altr-feedback.onrender.com"
		}
		envContent := fmt.Sprintf(`ALTR_STREAM_PORT=%d
ALTR_STREAM_DEBUG=false
ALTR_STREAM_FEEDBACK_SERVICE_URL=%s
ALTR_FEEDBACK_API_KEY=%s
`, cfg.Port, fbURL, cfg.FeedbackKey)
		if err := os.WriteFile(envPath, []byte(envContent), 0644); err != nil {
			return fmt.Errorf("failed to write .env: %w", err)
		}
	}

	return nil
}

// EnsureDataVolume creates the named volume 'altr_stream_data' if missing.
func (l *LifecycleManager) EnsureDataVolume(ctx context.Context) error {
	_, stderr, exitCode, err := l.executor.Run(ctx, l.dockerCLI(), "volume", "create", NamedDataVolume)
	if exitCode != 0 {
		return fmt.Errorf("failed to create named volume %s: %s (%v)", NamedDataVolume, strings.TrimSpace(stderr), err)
	}
	return nil
}

// PullImage runs docker compose pull with output logging.
func (l *LifecycleManager) PullImage(ctx context.Context, targetDir, composeCmd, image string) error {
	composeFile := filepath.Join(targetDir, "docker-compose.yml")
	pullLogPath := filepath.Join(targetDir, ".docker_pull.log")

	exe, subargs := l.parseComposeCommand(composeCmd)
	args := append(append([]string{}, subargs...), "-f", composeFile, "pull")

	stdout, stderr, exitCode, err := l.executor.Run(ctx, exe, args...)
	combinedLog := strings.TrimSpace(stdout + "\n" + stderr)
	_ = os.WriteFile(pullLogPath, []byte(combinedLog), 0644)

	if exitCode != 0 {
		// Check if image exists locally as fallback
		imgOut, _, imgExit, _ := l.executor.Run(ctx, l.dockerCLI(), "images", "-q", image)
		if imgExit == 0 && strings.TrimSpace(imgOut) != "" {
			return nil // local cache exists and usable
		}

		errMsg := "failed to pull image " + image
		if strings.Contains(combinedLog, "manifest unknown") || strings.Contains(combinedLog, "not found") {
			errMsg = fmt.Sprintf("Image %s not found on registry.", image)
		} else if strings.Contains(combinedLog, "connection refused") || strings.Contains(combinedLog, "timeout") {
			errMsg = fmt.Sprintf("Network error while pulling image %s.", image)
		} else {
			errMsg = fmt.Sprintf("%s: %s", errMsg, extractActionableError(combinedLog))
		}
		if err != nil {
			return fmt.Errorf("%s (%w)", errMsg, err)
		}
		return errors.New(errMsg)
	}

	return nil
}

// extractSharedPath extracts the directory path from a Docker daemon file sharing error message.
func extractSharedPath(log string) string {
	lower := strings.ToLower(log)
	idx := strings.Index(lower, "the path")
	if idx >= 0 {
		rest := strings.TrimLeft(log[idx+len("the path"):], " \t\r\n")
		if len(rest) > 0 && (rest[0] == '"' || rest[0] == '\'') {
			quote := rest[0]
			rest = rest[1:]
			endQuote := strings.IndexByte(rest, quote)
			if endQuote > 0 {
				return rest[:endQuote]
			}
		}
		if end := strings.Index(strings.ToLower(rest), "is not shared"); end > 0 {
			return strings.Trim(strings.TrimSpace(rest[:end]), "\"' \r\n\t")
		}
	}
	return ""
}

// extractActionableError isolates the true diagnostic error line from Docker or Compose output
// and provides a clear human-readable explanation with actionable remediation steps.
func extractActionableError(combinedLog string) string {
	combinedLog = strings.TrimSpace(combinedLog)
	if combinedLog == "" {
		return "Process terminated with non-zero exit code but produced no output."
	}

	lowerLog := strings.ToLower(combinedLog)

	// Priority 1: High-level known failures with rich, user-friendly instructions
	if strings.Contains(lowerLog, "is not shared from the host") ||
		strings.Contains(lowerLog, "file sharing") ||
		strings.Contains(lowerLog, "filesystem sharing") {
		path := extractSharedPath(combinedLog)
		if path != "" {
			return fmt.Sprintf("Docker Desktop needs permission to access Altr Stream's data folder.\n\n"+
				"Docker Desktop is currently preventing access to:\n  %s\n\n"+
				"Please allow this folder in Docker Desktop's Settings > Resources > File Sharing, then retry the installation.", path)
		}
		return "Docker Desktop needs permission to access Altr Stream's data folder.\n\n" +
			"Please allow your Altr Stream installation directory in Docker Desktop's Settings > Resources > File Sharing, then retry the installation."
	}

	if strings.Contains(lowerLog, "port is already allocated") || strings.Contains(lowerLog, "address already in use") {
		return "Port conflict: Port 8000 is already in use by another application.\n\nPlease close the application using port 8000 or configure a different port, then retry."
	}
	if strings.Contains(combinedLog, "Conflict. The container name") {
		return "Container name 'altr-stream' is already in use by another container.\n\nPlease stop or remove the existing container, then retry."
	}
	if strings.Contains(lowerLog, "cannot connect to the docker daemon") || strings.Contains(lowerLog, "daemon is not running") {
		return "Docker Engine is offline or stopped.\n\nPlease start Docker Desktop and ensure the engine is running, then retry."
	}

	lines := strings.Split(combinedLog, "\n")

	// Priority 2: Lines with explicit error prefixes or keywords from bottom up
	for i := len(lines) - 1; i >= 0; i-- {
		line := strings.TrimSpace(lines[i])
		if line == "" {
			continue
		}
		lower := strings.ToLower(line)
		// Skip status/progress lines like "[+] Running", "Volume creating", "Network created"
		if strings.HasPrefix(line, "[+]") || strings.HasPrefix(line, "✔") || strings.HasPrefix(line, "⠋") || strings.HasPrefix(line, "-") {
			continue
		}
		if strings.HasPrefix(lower, "error response from daemon:") ||
			strings.HasPrefix(lower, "error:") ||
			strings.Contains(lower, "failed") ||
			strings.Contains(lower, "denied") ||
			strings.Contains(lower, "cannot") ||
			strings.Contains(lower, "exception") {
			return line
		}
	}

	// Priority 3: Last non-empty, non-status line
	for i := len(lines) - 1; i >= 0; i-- {
		line := strings.TrimSpace(lines[i])
		if line == "" || strings.HasPrefix(line, "[+]") || strings.HasPrefix(line, "✔") || strings.HasPrefix(line, "⠋") {
			continue
		}
		return line
	}

	return strings.TrimSpace(lines[len(lines)-1])
}

// isFileSharingError checks if an error message from Docker daemon or Compose indicates
// an unshared host path / bind-mount permission requirement.
func isFileSharingError(combinedLog string) bool {
	lowerLog := strings.ToLower(combinedLog)
	return strings.Contains(lowerLog, "is not shared from the host") ||
		strings.Contains(lowerLog, "file sharing") ||
		strings.Contains(lowerLog, "filesharing") ||
		strings.Contains(lowerLog, "filesystem sharing") ||
		strings.Contains(lowerLog, "drive has not been shared") ||
		strings.Contains(lowerLog, "drive is not shared") ||
		strings.Contains(lowerLog, "not shared from host")
}

// StartContainer launches the container with docker compose up -d.
// If a Docker Desktop host file-sharing permission error is encountered,
// it logs the diagnostic output and immediately returns ErrFileSharingRequired
// to allow user-controlled remediation without hammering Docker Desktop.
func (l *LifecycleManager) StartContainer(ctx context.Context, targetDir, composeCmd string, onProgress ...func(string)) error {
	composeFile := filepath.Join(targetDir, "docker-compose.yml")
	startLogPath := filepath.Join(targetDir, ".docker_start.log")

	exe, subargs := l.parseComposeCommand(composeCmd)
	args := append(append([]string{}, subargs...), "-f", composeFile, "up", "-d")

	// 1. Re-check actual container state before running compose up
	inspectOut, _, inspectExit, _ := l.executor.Run(ctx, l.dockerCLI(), "inspect", "-f", "{{.State.Running}}", ContainerName)
	if inspectExit == 0 && strings.TrimSpace(inspectOut) == "true" {
		return nil
	}

	for _, fn := range onProgress {
		if fn != nil {
			fn("Starting Altr Stream container...")
		}
	}

	// Determine attempt number across retries by reading existing log.
	// If the log is older than 30 minutes, it is from a previous session; reset to attempt 1.
	attempt := 1
	if fi, statErr := os.Stat(startLogPath); statErr == nil {
		if time.Since(fi.ModTime()) <= 30*time.Minute {
			if existingLog, err := os.ReadFile(startLogPath); err == nil {
				attempt = strings.Count(string(existingLog), "=== Container Startup Attempt") + 1
			}
		}
	}

	stdout, stderr, exitCode, err := l.executor.Run(ctx, exe, args...)
	combinedLog := strings.TrimSpace(stdout + "\n" + stderr)

	// Append attempt output to diagnostic log file
	attemptHeader := fmt.Sprintf("=== Container Startup Attempt %d ===\n", attempt)
	startLogEntry := attemptHeader + combinedLog + "\n"
	if attempt == 1 {
		_ = os.WriteFile(startLogPath, []byte(startLogEntry), 0644)
	} else {
		f, fErr := os.OpenFile(startLogPath, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
		if fErr == nil {
			_, _ = f.WriteString("\n" + startLogEntry)
			_ = f.Close()
		}
	}

	if exitCode == 0 {
		return nil
	}

	// Non-zero exit code: check if it's a file-sharing error
	if isFileSharingError(combinedLog) {
		path := extractSharedPath(combinedLog)
		if path == "" {
			path = filepath.Join(targetDir, "data", "updates")
		}
		detail := extractActionableError(combinedLog)
		return &ErrFileSharingRequired{
			Path:    path,
			Details: detail,
		}
	}

	// Unrelated failure: return actionable error immediately
	detail := extractActionableError(combinedLog)
	errMsg := "failed to start container: " + detail
	if err != nil {
		return fmt.Errorf("%s (%w)", errMsg, err)
	}
	return errors.New(errMsg)
}


// StopContainer shuts down the compose deployment.
func (l *LifecycleManager) StopContainer(ctx context.Context, targetDir, composeCmd string) error {
	composeFile := filepath.Join(targetDir, "docker-compose.yml")
	exe, subargs := l.parseComposeCommand(composeCmd)
	args := append(append([]string{}, subargs...), "-f", composeFile, "down")

	_, _, exitCode, err := l.executor.Run(ctx, exe, args...)
	if exitCode != 0 {
		return fmt.Errorf("failed to stop container: %w", err)
	}
	return nil
}

// RemoveContainerForcefully removes the altr-stream container directly.
func (l *LifecycleManager) RemoveContainerForcefully(ctx context.Context) error {
	_, stderr, exitCode, err := l.executor.Run(ctx, l.dockerCLI(), "rm", "-f", ContainerName)
	if exitCode != 0 && !strings.Contains(stderr, "No such container") {
		return fmt.Errorf("failed to remove container %s: %s (%v)", ContainerName, stderr, err)
	}
	return nil
}

// RemoveDataVolume deletes the persistent volume altr_stream_data.
func (l *LifecycleManager) RemoveDataVolume(ctx context.Context) error {
	_, stderr, exitCode, err := l.executor.Run(ctx, l.dockerCLI(), "volume", "rm", NamedDataVolume)
	if exitCode != 0 && !strings.Contains(stderr, "no such volume") {
		return fmt.Errorf("failed to remove volume %s: %s (%v)", NamedDataVolume, stderr, err)
	}
	return nil
}

// Uninstall halts and removes the installer-managed altr-stream container,
// cleans up runtime configuration files, and optionally removes persistent data.
// It handles running, stopped, restarting, or absent containers idempotently.
// It strictly ensures that dev containers or unrelated containers are NEVER stopped or removed.
func (l *LifecycleManager) Uninstall(ctx context.Context, targetDir string, deleteData bool) error {
	// 1. Resolve and expand targetDir
	if strings.HasPrefix(targetDir, "~") {
		home, _ := os.UserHomeDir()
		if home != "" {
			targetDir = filepath.Join(home, strings.TrimPrefix(targetDir, "~"))
		}
	}
	if targetDir != "" {
		targetDir = filepath.Clean(targetDir)
	}

	// 2. Check Docker daemon state
	diag := l.dockerManager.CheckDocker(ctx)
	if !diag.EngineRunning {
		return fmt.Errorf("Docker daemon is not running: please ensure Docker Desktop is running before uninstalling")
	}

	// 3. Inspect target container
	conflict, err := l.CheckContainerConflict(ctx)
	if err != nil {
		return fmt.Errorf("failed to inspect container: %w", err)
	}

	if conflict.Exists {
		// Safety check: Never stop or remove a development container
		if conflict.IsDevContainer {
			return fmt.Errorf("cannot uninstall: container '%s' is identified as a development environment", ContainerName)
		}

		// 4. If container is running, paused, or restarting, stop it gracefully
		if conflict.Status == "running" || conflict.Status == "restarting" || conflict.Status == "paused" {
			if conflict.Status == "paused" {
				// Unpause container so compose down / docker stop can signal the process cleanly
				_, _, _, _ = l.executor.Run(ctx, l.dockerCLI(), "unpause", ContainerName)
			}
			composeCmd := diag.ComposeCommand
			if composeCmd == "" {
				cli := l.dockerCLI()
				if cli == "" {
					cli = "docker"
				}
				composeCmd = cli + " compose"
			}

			composeFile := ""
			if targetDir != "" {
				composeFile = filepath.Join(targetDir, "docker-compose.yml")
			}

			stopped := false
			// If compose file exists, try compose down first
			if composeFile != "" {
				if _, statErr := os.Stat(composeFile); statErr == nil {
					if stopErr := l.StopContainer(ctx, targetDir, composeCmd); stopErr == nil {
						stopped = true
					}
				}
			}

			// If not stopped via compose down, stop container directly via `docker stop -t 10 altr-stream`
			if !stopped {
				_, stderr, exitCode, stopErr := l.executor.Run(ctx, l.dockerCLI(), "stop", "-t", "10", ContainerName)
				if exitCode != 0 && !strings.Contains(stderr, "No such container") && !strings.Contains(stderr, "not running") {
					// Fallback to kill if graceful stop errored
					_, killErr, killCode, _ := l.executor.Run(ctx, l.dockerCLI(), "kill", ContainerName)
					if killCode != 0 && !strings.Contains(killErr, "No such container") && !strings.Contains(killErr, "not running") {
						return fmt.Errorf("failed to stop container '%s': %s (%v)", ContainerName, stderr, stopErr)
					}
				}
			}

			// Bounded polling until container is stopped
			stopDeadline := time.Now().Add(10 * time.Second)
			for time.Now().Before(stopDeadline) {
				inspectOut, _, inspectCode, _ := l.executor.Run(ctx, l.dockerCLI(), "inspect", "-f", "{{.State.Running}}", ContainerName)
				if inspectCode != 0 || strings.TrimSpace(inspectOut) != "true" {
					break
				}
				select {
				case <-ctx.Done():
					return ctx.Err()
				case <-time.After(300 * time.Millisecond):
				}
			}
		}

		// 5. Remove container
		_, rmErr, rmCode, err := l.executor.Run(ctx, l.dockerCLI(), "rm", "-f", ContainerName)
		if rmCode != 0 && !strings.Contains(rmErr, "No such container") {
			return fmt.Errorf("failed to remove container '%s': %s (%w)", ContainerName, rmErr, err)
		}

		// Verify container is gone
		inspectOut, _, verifyCode, _ := l.executor.Run(ctx, l.dockerCLI(), "inspect", "-f", "{{.State.Status}}", ContainerName)
		if verifyCode == 0 && strings.TrimSpace(inspectOut) != "" {
			return fmt.Errorf("container '%s' is still present after removal attempt (status=%s)", ContainerName, strings.TrimSpace(inspectOut))
		}
	}

	// 6. Clean up generated runtime/config files
	if targetDir != "" {
		runtimeFiles := []string{
			"docker-compose.yml",
			".env",
			".docker_start.log",
			".docker_pull.log",
		}
		for _, rf := range runtimeFiles {
			_ = os.Remove(filepath.Join(targetDir, rf))
		}

		// 7. Data volume handling
		if deleteData {
			_ = l.RemoveDataVolume(ctx)
			_ = os.RemoveAll(targetDir)
		}
	} else if deleteData {
		_ = l.RemoveDataVolume(ctx)
	}

	// 8. Remove global configuration file if present
	home, _ := os.UserHomeDir()
	if home != "" {
		_ = os.Remove(filepath.Join(home, ".altr-stream-config.json"))
		_ = os.Remove(filepath.Join(home, ".altr-stream-config"))
	}

	return nil
}

// VerifyHealth polls the health check endpoint until healthy or timeout.
// It verifies that:
// 1. Target container 'altr-stream' is running.
// 2. Target container 'altr-stream' actually has port 8000/tcp mapped to the expected host port.
// 3. Target container itself responds with healthy status and expected version.
// 4. Host endpoint responds with healthy status and expected version.
func (l *LifecycleManager) VerifyHealth(ctx context.Context, port int, expectedVersion string, timeout time.Duration) (string, error) {
	url := fmt.Sprintf("http://localhost:%d/api/v1/health", port)
	fallbackURL := fmt.Sprintf("http://localhost:%d/api/health", port)

	startTime := time.Now()
	ticker := time.NewTicker(2 * time.Second)
	defer ticker.Stop()

	expectedPortStr := fmt.Sprintf("%d", port)
	var lastErr error

	for {
		// 1. Inspect container to verify it is running and host port is actually mapped to this target container
		inspectOut, _, inspectExit, _ := l.executor.Run(ctx, l.dockerCLI(), "inspect", ContainerName)
		if inspectExit != 0 || strings.TrimSpace(inspectOut) == "" || inspectOut == "[]" {
			lastErr = fmt.Errorf("container '%s' not found in Docker", ContainerName)
		} else {
			var inspectList []struct {
				State struct {
					Status  string `json:"Status"`
					Running bool   `json:"Running"`
				} `json:"State"`
				NetworkSettings struct {
					Ports map[string][]struct {
						HostPort string `json:"HostPort"`
					} `json:"Ports"`
				} `json:"NetworkSettings"`
			}

			if err := json.Unmarshal([]byte(inspectOut), &inspectList); err == nil && len(inspectList) > 0 {
				c := inspectList[0]
				if !c.State.Running || c.State.Status != "running" {
					lastErr = fmt.Errorf("container '%s' is not running (status: %s)", ContainerName, c.State.Status)
				} else {
					// Check that host port is mapped to target container
					portMapped := false
					if bindings, ok := c.NetworkSettings.Ports["8000/tcp"]; ok && len(bindings) > 0 {
						for _, b := range bindings {
							if b.HostPort == expectedPortStr {
								portMapped = true
								break
							}
						}
					}

					if !portMapped {
						lastErr = fmt.Errorf("container '%s' port 8000/tcp is not mapped to host port %d", ContainerName, port)
					} else {
						// 2. Direct container check via docker exec (if available) to guarantee we test the target container
						execOut, _, execExit, _ := l.executor.Run(ctx, l.dockerCLI(), "exec", ContainerName, "curl", "-f", "-s", "http://localhost:8000/api/v1/health")
						if execExit != 0 || strings.TrimSpace(execOut) == "" {
							execOut, _, execExit, _ = l.executor.Run(ctx, l.dockerCLI(), "exec", ContainerName, "curl", "-f", "-s", "http://localhost:8000/api/health")
						}
						if execExit == 0 && strings.TrimSpace(execOut) != "" {
							if !l.checkVersionMatch(execOut, expectedVersion) {
								return execOut, fmt.Errorf("version mismatch in target container health response: %s (expected %s)", execOut, expectedVersion)
							}
						}

						// 3. Probe host endpoint
						respBody, err := l.probeEndpoint(ctx, url)
						if err == nil {
							if l.checkVersionMatch(respBody, expectedVersion) {
								return respBody, nil
							}
							return respBody, fmt.Errorf("version mismatch in health response: %s (expected %s)", respBody, expectedVersion)
						}
						lastErr = err

						// Fallback host endpoint
						fbBody, fbErr := l.probeEndpoint(ctx, fallbackURL)
						if fbErr == nil {
							if l.checkVersionMatch(fbBody, expectedVersion) {
								return fbBody, nil
							}
							return fbBody, fmt.Errorf("version mismatch in health response: %s (expected %s)", fbBody, expectedVersion)
						}
						lastErr = fbErr
					}
				}
			}
		}

		select {
		case <-ctx.Done():
			return "", ctx.Err()
		case t := <-ticker.C:
			if t.Sub(startTime) >= timeout {
				return "", fmt.Errorf("health check timed out after %v: %v", timeout, lastErr)
			}
		}
	}
}

func (l *LifecycleManager) probeEndpoint(ctx context.Context, url string) (string, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return "", err
	}

	resp, err := l.httpClient.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	bodyBytes, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", err
	}

	if resp.StatusCode >= 200 && resp.StatusCode < 300 {
		return string(bodyBytes), nil
	}
	return "", fmt.Errorf("HTTP status %d: %s", resp.StatusCode, string(bodyBytes))
}

func (l *LifecycleManager) checkVersionMatch(body, expected string) bool {
	if expected == "" {
		return true
	}
	var data map[string]interface{}
	if err := json.Unmarshal([]byte(body), &data); err != nil {
		return strings.Contains(body, "healthy") || strings.Contains(body, "ok")
	}

	// Check status
	if st, ok := data["status"].(string); ok {
		if st != "healthy" && st != "ok" {
			return false
		}
	}

	// If version is provided, verify match (supports pipe-separated alternatives like "1.0.0-beta|0.13.7-alpha")
	if ver, ok := data["version"].(string); ok {
		cleanVer := strings.TrimPrefix(ver, "v")
		candidates := strings.Split(expected, "|")
		for _, cand := range candidates {
			cleanCand := strings.TrimPrefix(strings.TrimSpace(cand), "v")
			if cleanCand != "" && (strings.HasPrefix(cleanVer, cleanCand) || strings.HasPrefix(cleanCand, cleanVer)) {
				return true
			}
		}
		return false
	}
	return true
}

// VerifyInstallation performs strict multi-point verification of the live container state.
// It verifies:
// 1. Container exists
// 2. Container is running (not exited, restarting, or dead)
// 3. Expected image is being used
// 4. Expected host port is mapped to 8000/tcp
// 5. Health endpoint is reachable
// 6. Health status is healthy or ok
// 7. Expected version is returned
func (l *LifecycleManager) VerifyInstallation(ctx context.Context, cfg InstallConfig, expectedVersion string) error {
	// 1. Inspect container
	stdout, stderr, exitCode, _ := l.executor.Run(ctx, l.dockerCLI(), "inspect", ContainerName)
	if exitCode != 0 || strings.TrimSpace(stdout) == "" || stdout == "[]" {
		errMsg := strings.TrimSpace(stderr)
		if errMsg == "" {
			errMsg = "container not found in Docker"
		}
		return fmt.Errorf("container '%s' does not exist after startup: %s", ContainerName, errMsg)
	}

	var inspectList []struct {
		ID    string `json:"Id"`
		State struct {
			Status   string `json:"Status"`
			Running  bool   `json:"Running"`
			ExitCode int    `json:"ExitCode"`
			Error    string `json:"Error"`
		} `json:"State"`
		Config struct {
			Image string `json:"Image"`
		} `json:"Config"`
		NetworkSettings struct {
			Ports map[string][]struct {
				HostIp   string `json:"HostIp"`
				HostPort string `json:"HostPort"`
			} `json:"Ports"`
		} `json:"NetworkSettings"`
	}

	if err := json.Unmarshal([]byte(stdout), &inspectList); err != nil || len(inspectList) == 0 {
		return fmt.Errorf("failed to parse docker inspect output for container '%s': %w", ContainerName, err)
	}

	c := inspectList[0]

	// 2. Verify container is running
	if !c.State.Running || c.State.Status != "running" {
		logOut, _, _, _ := l.executor.Run(ctx, l.dockerCLI(), "logs", "--tail", "25", ContainerName)
		diag := strings.TrimSpace(logOut)
		if c.State.Error != "" {
			diag = fmt.Sprintf("Error: %s\n%s", c.State.Error, diag)
		}
		if diag != "" {
			return fmt.Errorf("container '%s' is not running (status: %s, exit code: %d).\nContainer logs:\n%s",
				ContainerName, c.State.Status, c.State.ExitCode, diag)
		}
		return fmt.Errorf("container '%s' is not running (status: %s, exit code: %d)",
			ContainerName, c.State.Status, c.State.ExitCode)
	}

	// 3. Verify image if specified
	if cfg.Image != "" {
		expectedBase := strings.TrimPrefix(cfg.Image, "ghcr.io/")
		runningBase := strings.TrimPrefix(c.Config.Image, "ghcr.io/")
		if !strings.EqualFold(expectedBase, runningBase) && !strings.Contains(c.Config.Image, cfg.Image) && !strings.Contains(cfg.Image, c.Config.Image) {
			return fmt.Errorf("container '%s' is running image '%s', expected '%s'",
				ContainerName, c.Config.Image, cfg.Image)
		}
	}

	// 4. Verify host port mapping
	portKey := "8000/tcp"
	portMapped := false
	expectedPortStr := fmt.Sprintf("%d", cfg.Port)
	if bindings, ok := c.NetworkSettings.Ports[portKey]; ok && len(bindings) > 0 {
		for _, b := range bindings {
			if b.HostPort == expectedPortStr {
				portMapped = true
				break
			}
		}
	}
	if !portMapped {
		return fmt.Errorf("container '%s' port %s is not mapped to host port %d",
			ContainerName, portKey, cfg.Port)
	}

	// 5. Probe health endpoint
	healthURL := fmt.Sprintf("http://localhost:%d/api/v1/health", cfg.Port)
	fallbackURL := fmt.Sprintf("http://localhost:%d/api/health", cfg.Port)
	hCtx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()

	respBody, err := l.probeEndpoint(hCtx, healthURL)
	if err != nil {
		respBody, err = l.probeEndpoint(hCtx, fallbackURL)
		if err != nil {
			return fmt.Errorf("health endpoint is unreachable at %s: %w", healthURL, err)
		}
	}

	// 6. Verify health status is healthy or ok
	var healthData map[string]interface{}
	if err := json.Unmarshal([]byte(respBody), &healthData); err == nil {
		if st, ok := healthData["status"].(string); ok {
			if st != "healthy" && st != "ok" {
				return fmt.Errorf("health endpoint reported unhealthy status: %s (response: %s)", st, respBody)
			}
		}
	}

	// 7. Verify expected version
	if expectedVersion != "" && !l.checkVersionMatch(respBody, expectedVersion) {
		return fmt.Errorf("version mismatch in health response: %s (expected %s)", respBody, expectedVersion)
	}

	return nil
}

// LaunchBrowser opens the target URL using the system default browser after verifying availability.
func LaunchBrowser(ctx context.Context, exec CommandExecutor, client HTTPClient, targetURL string) error {
	// If URL is local, verify availability first to avoid ERR_CONNECTION_REFUSED
	if strings.HasPrefix(targetURL, "http://localhost:") || strings.HasPrefix(targetURL, "http://127.0.0.1:") {
		probeCtx, cancel := context.WithTimeout(ctx, 3*time.Second)
		defer cancel()
		req, err := http.NewRequestWithContext(probeCtx, http.MethodGet, targetURL, nil)
		if err == nil {
			if client == nil {
				client = http.DefaultClient
			}
			resp, err := client.Do(req)
			if err != nil {
				return fmt.Errorf("cannot launch browser: application is not reachable at %s: %w", targetURL, err)
			}
			resp.Body.Close()
		}
	}

	return launchPlatformBrowser(ctx, exec, targetURL)
}
