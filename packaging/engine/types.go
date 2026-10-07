package main

import (
	"context"
	"fmt"
	"net/http"
)

// DockerState represents the high-level state of Docker on the system.
type DockerState string

const (
	DockerStateNotInstalled DockerState = "not_installed"
	DockerStateStopped      DockerState = "stopped"
	DockerStateStarting     DockerState = "starting"
	DockerStatePaused       DockerState = "paused"
	DockerStateReady        DockerState = "ready"
	DockerStateError        DockerState = "error"
)

// DockerDiagnostics contains granular detection telemetry.
type DockerDiagnostics struct {
	State                DockerState `json:"state"`
	CliInstalled         bool        `json:"cli_installed"`
	DesktopInstalled     bool        `json:"desktop_installed"`
	EngineRunning        bool        `json:"engine_running"`
	ComposeAvailable     bool        `json:"compose_available"`
	ComposeCommand       string      `json:"compose_command"`
	StatusText           string      `json:"status_text"`
	ActionHint           string      `json:"action_hint"`
	OfficialInstallerURL string      `json:"official_installer_url"`
	TechnicalError       string      `json:"technical_error,omitempty"`
	FailureReason        string      `json:"failure_reason,omitempty"`
}

// ConflictType identifies the category of conflict detected.
type ConflictType string

const (
	ConflictTypeNone        ConflictType = "none"
	ConflictTypeContainer   ConflictType = "container"    // target container named 'altr-stream' exists
	ConflictTypePortDocker  ConflictType = "port_docker"  // port occupied by another docker container
	ConflictTypePortProcess ConflictType = "port_process" // port occupied by a non-docker host process
)

// ConflictInfo details an existing container or port conflict.
type ConflictInfo struct {
	Exists           bool         `json:"exists"`
	ConflictType     ConflictType `json:"conflict_type"`
	ContainerID      string       `json:"container_id,omitempty"`
	ContainerName    string       `json:"container_name,omitempty"`
	Status           string       `json:"status,omitempty"`
	Image            string       `json:"image,omitempty"`
	Created          string       `json:"created,omitempty"`
	IsAltrStream     bool         `json:"is_altr_stream"`
	IsCompatible     bool         `json:"is_compatible"`
	IsInstallerOwned bool         `json:"is_installer_owned"`
	IsDevContainer   bool         `json:"is_dev_container"`
	PortMapping      string       `json:"port_mapping,omitempty"`
	HealthStatus     string       `json:"health_status,omitempty"`
	ConflictingPort  int          `json:"conflicting_port"`
	OccupiedBy       string       `json:"occupied_by,omitempty"`
	RemediationHint  string       `json:"remediation_hint"`
	Details          string       `json:"details,omitempty"`
	RawInspect       string       `json:"raw_inspect,omitempty"`
}

// InstallStage represents discrete milestones during execution.
type InstallStage string

const (
	StagePreparingConfig  InstallStage = "Preparing configuration"
	StagePreparingVolume  InstallStage = "Preparing storage volume"
	StagePullingImage     InstallStage = "Pulling Altr Stream image"
	StageStartingContainer InstallStage = "Starting container"
	StageWaitingHealth    InstallStage = "Waiting for health check"
	StageVerifying        InstallStage = "Verifying installation"
)

// InstallProgress reports real-time step progress.
type InstallProgress struct {
	Stage       InstallStage `json:"stage"`
	StageIndex  int          `json:"stage_index"`
	TotalStages int          `json:"total_stages"`
	Percent     int          `json:"percent"`
	Message     string       `json:"message"`
}

// InstallConfig holds parameters for installation.
type InstallConfig struct {
	TargetDir       string `json:"target_dir"`
	Version         string `json:"version"`
	Image           string `json:"image"`
	Port            int    `json:"port"`
	FeedbackURL     string `json:"feedback_url"`
	FeedbackKey     string `json:"feedback_key"`
	HealthTimeout   int    `json:"health_timeout"` // seconds
	StartTimeout    int    `json:"start_timeout"`  // seconds
	ReplaceExisting bool   `json:"replace_existing,omitempty"`
}

// NodeStatus represents the operational status of an Altr Stream installation.
type NodeStatus struct {
	InstallDir      string            `json:"install_dir"`
	TargetVersion   string            `json:"target_version"`
	ContainerState  string            `json:"container_state"`
	Port            int               `json:"port"`
	WebURL          string            `json:"web_url"`
	DockerDiag      DockerDiagnostics `json:"docker_diag"`
	Healthy         bool              `json:"healthy"`
	HealthResponse  string            `json:"health_response,omitempty"`
	TechnicalIssues []string          `json:"technical_issues,omitempty"`
}

// EnvironmentInfo provides host system context.
type EnvironmentInfo struct {
	OS             string `json:"os"`
	Arch           string `json:"arch"`
	UserHome       string `json:"user_home"`
	DefaultDir     string `json:"default_dir"`
	ConfigFile     string `json:"config_file"`
	SavedDir       string `json:"saved_dir,omitempty"`
	EffectiveDir   string `json:"effective_dir"`
	IsOneDrive     bool   `json:"is_onedrive"`
}

// CommandExecutor abstracts OS process execution for testing.
type CommandExecutor interface {
	Run(ctx context.Context, name string, args ...string) (stdout string, stderr string, exitCode int, err error)
	StartDetached(ctx context.Context, name string, args ...string) error
}

// HTTPClient abstracts HTTP calls for healthcheck verification.
type HTTPClient interface {
	Do(req *http.Request) (*http.Response, error)
}

// ProgressFunc receives progress updates during long-running tasks.
type ProgressFunc func(p InstallProgress)

// ErrFileSharingRequired represents a host-access prerequisite state where Docker Desktop
// requires host file sharing authorization before a container bind mount can proceed.
type ErrFileSharingRequired struct {
	Path    string `json:"path"`
	Details string `json:"details"`
}

func (e *ErrFileSharingRequired) Error() string {
	return fmt.Sprintf("FILE_SHARING_REQUIRED|%s|%s", e.Path, e.Details)
}
