package main

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
	"testing"
	"time"
)

type fakeFileInfo struct {
	isDir bool
}

func (f *fakeFileInfo) Name() string       { return "fake" }
func (f *fakeFileInfo) Size() int64        { return 0 }
func (f *fakeFileInfo) Mode() os.FileMode  { return 0755 }
func (f *fakeFileInfo) ModTime() time.Time { return time.Now() }
func (f *fakeFileInfo) IsDir() bool        { return f.isDir }
func (f *fakeFileInfo) Sys() interface{}   { return nil }

// MockCommandExecutor allows mocking any CLI invocation.
type MockCommandExecutor struct {
	mu       sync.Mutex
	Handlers map[string]func(args []string) (string, string, int, error)
	CallLog  []string
}

func NewMockExecutor() *MockCommandExecutor {
	return &MockCommandExecutor{
		Handlers: make(map[string]func(args []string) (string, string, int, error)),
	}
}

func (m *MockCommandExecutor) Run(ctx context.Context, name string, args ...string) (string, string, int, error) {
	m.mu.Lock()
	baseName := filepath.Base(name)
	fullCmd := name + " " + strings.Join(args, " ")
	baseCmd := baseName + " " + strings.Join(args, " ")
	m.CallLog = append(m.CallLog, fullCmd)
	m.mu.Unlock()

	// 1. Direct matches
	if h, ok := m.Handlers[fullCmd]; ok {
		return h(args)
	}
	if h, ok := m.Handlers[baseCmd]; ok {
		return h(args)
	}

	// 2. Pattern matching
	for pat, h := range m.Handlers {
		if fullCmd == pat || baseCmd == pat ||
			strings.HasPrefix(fullCmd, pat) || strings.HasPrefix(baseCmd, pat) ||
			strings.Contains(fullCmd, pat) || strings.Contains(baseCmd, pat) {
			return h(args)
		}
	}

	// 3. Name matches
	if h, ok := m.Handlers[name]; ok {
		return h(args)
	}
	if h, ok := m.Handlers[baseName]; ok {
		return h(args)
	}

	return "", "", 0, nil
}

func (m *MockCommandExecutor) StartDetached(ctx context.Context, name string, args ...string) error {
	m.mu.Lock()
	fullCmd := name + " " + strings.Join(args, " ")
	m.CallLog = append(m.CallLog, "DETACHED: "+fullCmd)
	m.mu.Unlock()

	_, _, code, err := m.Run(ctx, name, args...)
	if err != nil {
		return err
	}
	if code != 0 {
		return fmt.Errorf("process failed with exit code %d", code)
	}
	return nil
}

// MockHTTPClient allows mocking HTTP responses.
type MockHTTPClient struct {
	DoFunc func(req *http.Request) (*http.Response, error)
}

func (m *MockHTTPClient) Do(req *http.Request) (*http.Response, error) {
	if m.DoFunc != nil {
		return m.DoFunc(req)
	}
	return &http.Response{
		StatusCode: 200,
		Body:       io.NopCloser(bytes.NewBufferString(`{"status":"healthy","version":"1.0.0-beta"}`)),
	}, nil
}

// Helper to create a temp isolated directory for tests
func setupTestDir(t *testing.T) string {
	t.Helper()
	dir, err := os.MkdirTemp("", "altr_engine_test_*")
	if err != nil {
		t.Fatalf("failed to create temp dir: %v", err)
	}
	t.Cleanup(func() { _ = os.RemoveAll(dir) })
	return dir
}

// 1. Test Clean Machine / Docker Missing
func TestDockerMissing(t *testing.T) {
	mockExec := NewMockExecutor()
	engine := NewInstallerEngine(mockExec, &MockHTTPClient{})

	// Simulate clean machine with zero Docker presence
	engine.dockerManager.lookPath = func(file string) (string, error) {
		return "", os.ErrNotExist
	}
	engine.dockerManager.stat = func(name string) (os.FileInfo, error) {
		return nil, os.ErrNotExist
	}

	ctx := context.Background()
	diag, err := engine.CheckDocker(ctx)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if diag.EngineRunning {
		t.Errorf("expected EngineRunning=false on clean machine without Docker")
	}
	if diag.State != DockerStateNotInstalled {
		t.Errorf("expected DockerStateNotInstalled, got: %s", diag.State)
	}
	if diag.OfficialInstallerURL == "" {
		t.Errorf("expected OfficialInstallerURL to be provided")
	}
}

// 2. Test Docker Installed but Stopped
func TestDockerInstalledButStopped(t *testing.T) {
	mockExec := NewMockExecutor()
	mockExec.Handlers["info"] = func(args []string) (string, string, int, error) {
		return "", "Cannot connect to the Docker daemon at unix:///var/run/docker.sock. Is the docker daemon running?", 1, nil
	}
	mockExec.Handlers["compose version"] = func(args []string) (string, string, int, error) {
		return "Docker Compose version v2.29.1", "", 0, nil
	}

	engine := NewInstallerEngine(mockExec, &MockHTTPClient{})
	engine.dockerManager.lookPath = func(file string) (string, error) {
		if file == "docker" {
			return "/usr/bin/docker", nil
		}
		return "", os.ErrNotExist
	}
	engine.dockerManager.stat = func(name string) (os.FileInfo, error) {
		if strings.Contains(name, "Docker Desktop") || strings.Contains(name, "Docker.app") {
			return &fakeFileInfo{isDir: true}, nil
		}
		return nil, os.ErrNotExist
	}

	ctx := context.Background()
	diag, err := engine.CheckDocker(ctx)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if diag.EngineRunning {
		t.Errorf("expected EngineRunning=false")
	}
	if diag.State != DockerStateStopped {
		t.Errorf("expected DockerStateStopped, got: %s", diag.State)
	}
	if diag.ActionHint != "Start Docker Desktop" {
		t.Errorf("expected 'Start Docker Desktop', got: %s", diag.ActionHint)
	}
}

// 3. Test Docker Compose Missing
func TestDockerComposeMissing(t *testing.T) {
	mockExec := NewMockExecutor()
	mockExec.Handlers["info"] = func(args []string) (string, string, int, error) {
		return "Server Version: 27.1.1", "", 0, nil
	}
	mockExec.Handlers["compose version"] = func(args []string) (string, string, int, error) {
		return "", "docker: 'compose' is not a docker command", 1, nil
	}

	engine := NewInstallerEngine(mockExec, &MockHTTPClient{})
	engine.dockerManager.lookPath = func(file string) (string, error) {
		if file == "docker" {
			return "/usr/bin/docker", nil
		}
		return "", os.ErrNotExist
	}
	engine.dockerManager.stat = func(name string) (os.FileInfo, error) {
		return nil, os.ErrNotExist
	}

	ctx := context.Background()
	diag, err := engine.CheckDocker(ctx)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if !diag.EngineRunning {
		t.Errorf("expected EngineRunning=true")
	}
	if diag.ComposeAvailable {
		t.Errorf("expected ComposeAvailable=false")
	}
	if diag.State != DockerStateError {
		t.Errorf("expected state=error, got: %s", diag.State)
	}
	if !strings.Contains(diag.FailureReason, "Docker Compose") {
		t.Errorf("expected failure reason to mention Docker Compose, got: %s", diag.FailureReason)
	}
}

// 4. Test Docker Startup Retry and Readiness
func TestDockerStartupRetry(t *testing.T) {
	mockExec := NewMockExecutor()
	attempts := 0

	mockExec.Handlers["info"] = func(args []string) (string, string, int, error) {
		attempts++
		if attempts < 3 {
			return "", "daemon is starting", 1, nil
		}
		return "Server Version: 27.1.1", "", 0, nil
	}
	mockExec.Handlers["compose version"] = func(args []string) (string, string, int, error) {
		return "Docker Compose version v2.29.1", "", 0, nil
	}

	engine := NewInstallerEngine(mockExec, &MockHTTPClient{})
	engine.dockerManager.lookPath = func(file string) (string, error) {
		if file == "docker" {
			return "/usr/bin/docker", nil
		}
		return "", os.ErrNotExist
	}
	engine.dockerManager.stat = func(name string) (os.FileInfo, error) {
		if strings.Contains(name, "Docker Desktop") || strings.Contains(name, "Docker.app") {
			return &fakeFileInfo{isDir: true}, nil
		}
		return nil, os.ErrNotExist
	}

	ctx := context.Background()

	progressCalls := 0
	err := engine.WaitForDocker(ctx, 10*time.Second, func(elapsed time.Duration) {
		progressCalls++
	})

	if err != nil {
		t.Fatalf("expected WaitForDocker to succeed on 3rd attempt, got error: %v", err)
	}
	if attempts < 3 {
		t.Errorf("expected at least 3 attempts, got: %d", attempts)
	}
}

// 5. Test Docker Unavailable Timeout
func TestDockerUnavailableTimeout(t *testing.T) {
	mockExec := NewMockExecutor()
	mockExec.Handlers["info"] = func(args []string) (string, string, int, error) {
		return "", "daemon is offline", 1, nil
	}

	engine := NewInstallerEngine(mockExec, &MockHTTPClient{})
	engine.dockerManager.lookPath = func(file string) (string, error) {
		if file == "docker" {
			return "/usr/bin/docker", nil
		}
		return "", os.ErrNotExist
	}
	engine.dockerManager.stat = func(name string) (os.FileInfo, error) {
		return nil, os.ErrNotExist
	}

	ctx := context.Background()

	err := engine.WaitForDocker(ctx, 1*time.Millisecond, nil)
	if err == nil {
		t.Fatalf("expected timeout error, got nil")
	}
	if !strings.Contains(err.Error(), "timeout waiting for Docker Engine") {
		t.Errorf("expected timeout message, got: %v", err)
	}
}

// 6. Test Container Conflict Detection
func TestContainerConflictDetection(t *testing.T) {
	mockExec := NewMockExecutor()

	// Scenario A: No container exists
	mockExec.Handlers["inspect altr-stream"] = func(args []string) (string, string, int, error) {
		return "", "Error: No such object: altr-stream", 1, nil
	}

	engine := NewInstallerEngine(mockExec, &MockHTTPClient{})
	ctx := context.Background()

	conflict, err := engine.CheckContainerConflict(ctx)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if conflict.Exists {
		t.Errorf("expected conflict.Exists=false for non-existent container")
	}

	// Scenario B: Container exists
	mockExec.Handlers["inspect altr-stream"] = func(args []string) (string, string, int, error) {
		inspectJSON := `[
			{
				"Id": "a1b2c3d4e5f67890",
				"Created": "2026-09-30T10:00:00Z",
				"State": {"Status": "running"},
				"Config": {"Image": "ghcr.io/helloaltr/altr-stream:0.13.7-alpha"}
			}
		]`
		return inspectJSON, "", 0, nil
	}

	conflict, err = engine.CheckContainerConflict(ctx)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !conflict.Exists {
		t.Errorf("expected conflict.Exists=true")
	}
	if conflict.ContainerID != "a1b2c3d4e5f6" {
		t.Errorf("expected 12-char ID 'a1b2c3d4e5f6', got: %s", conflict.ContainerID)
	}
	if conflict.Status != "running" {
		t.Errorf("expected status 'running', got: %s", conflict.Status)
	}
	if conflict.Image != "ghcr.io/helloaltr/altr-stream:0.13.7-alpha" {
		t.Errorf("unexpected image: %s", conflict.Image)
	}
}

// 7. Test Installation Success (6 Stages)
func TestInstallSuccess(t *testing.T) {
	testDir := setupTestDir(t)
	mockExec := NewMockExecutor()

	mockExec.Handlers["info"] = func(args []string) (string, string, int, error) {
		return "Server Version: 27.1.1", "", 0, nil
	}
	mockExec.Handlers["compose version"] = func(args []string) (string, string, int, error) {
		return "Docker Compose version v2.29.1", "", 0, nil
	}
	mockExec.Handlers["volume create altr_stream_data"] = func(args []string) (string, string, int, error) {
		return "altr_stream_data\n", "", 0, nil
	}
	mockExec.Handlers["pull"] = func(args []string) (string, string, int, error) {
		return "Status: Downloaded newer image for ghcr.io/helloaltr/altr-stream:0.13.7-alpha", "", 0, nil
	}
	containerStarted := false
	mockExec.Handlers["up -d"] = func(args []string) (string, string, int, error) {
		containerStarted = true
		return "Container altr-stream Started", "", 0, nil
	}
	mockExec.Handlers["inspect altr-stream"] = func(args []string) (string, string, int, error) {
		if !containerStarted {
			return "[]", "No such container", 1, nil
		}
		inspectJSON := `[{
			"Id": "abc123456789",
			"State": {"Status": "running", "Running": true, "ExitCode": 0, "Error": ""},
			"Config": {"Image": "ghcr.io/helloaltr/altr-stream:0.13.7-alpha"},
			"NetworkSettings": {"Ports": {"8000/tcp": [{"HostIp": "0.0.0.0", "HostPort": "8000"}]}}
		}]`
		return inspectJSON, "", 0, nil
	}

	mockHTTP := &MockHTTPClient{
		DoFunc: func(req *http.Request) (*http.Response, error) {
			return &http.Response{
				StatusCode: 200,
				Body:       io.NopCloser(bytes.NewBufferString(`{"status":"healthy","version":"0.13.7-alpha"}`)),
			}, nil
		},
	}

	engine := NewInstallerEngine(mockExec, mockHTTP)
	ctx := context.Background()

	cfg := InstallConfig{
		TargetDir:     testDir,
		Version:       "0.13.7-alpha",
		Image:         "ghcr.io/helloaltr/altr-stream:0.13.7-alpha",
		Port:          8000,
		HealthTimeout: 5,
	}

	var stagesSeen []InstallStage
	err := engine.Install(ctx, cfg, func(p InstallProgress) {
		stagesSeen = append(stagesSeen, p.Stage)
	})

	if err != nil {
		t.Fatalf("Install failed unexpectedly: %v", err)
	}

	// Verify all 6 stages observed
	expectedStages := []InstallStage{
		StagePreparingConfig,
		StagePreparingVolume,
		StagePullingImage,
		StageStartingContainer,
		StageWaitingHealth,
		StageVerifying,
	}

	for _, es := range expectedStages {
		found := false
		for _, s := range stagesSeen {
			if s == es {
				found = true
				break
			}
		}
		if !found {
			t.Errorf("stage %s was not reported in progress", es)
		}
	}

	// Verify docker-compose.yml and .env exist
	composeFile := filepath.Join(testDir, "docker-compose.yml")
	if _, err := os.Stat(composeFile); os.IsNotExist(err) {
		t.Errorf("docker-compose.yml was not created")
	}
	envFile := filepath.Join(testDir, ".env")
	if _, err := os.Stat(envFile); os.IsNotExist(err) {
		t.Errorf(".env was not created")
	}
}

// 8. Test Image Pull Failure
func TestImagePullFailure(t *testing.T) {
	testDir := setupTestDir(t)
	mockExec := NewMockExecutor()

	mockExec.Handlers["info"] = func(args []string) (string, string, int, error) {
		return "Server Version: 27.1.1", "", 0, nil
	}
	mockExec.Handlers["compose version"] = func(args []string) (string, string, int, error) {
		return "Docker Compose version v2.29.1", "", 0, nil
	}
	mockExec.Handlers["volume create altr_stream_data"] = func(args []string) (string, string, int, error) {
		return "altr_stream_data", "", 0, nil
	}
	mockExec.Handlers["pull"] = func(args []string) (string, string, int, error) {
		return "", "Error response from daemon: manifest unknown: requested access to the resource is denied", 1, nil
	}
	mockExec.Handlers["images -q"] = func(args []string) (string, string, int, error) {
		return "", "", 0, nil
	}

	engine := NewInstallerEngine(mockExec, &MockHTTPClient{})
	ctx := context.Background()

	cfg := InstallConfig{
		TargetDir:     testDir,
		Version:       "1.0.0-beta",
		Image:         "ghcr.io/helloaltr/altr-stream:nonexistent",
		Port:          8000,
		HealthTimeout: 2,
	}

	err := engine.Install(ctx, cfg, nil)
	if err == nil {
		t.Fatalf("expected install to fail on pull, but it succeeded")
	}
	if !strings.Contains(err.Error(), "Pulling Altr Stream image") {
		t.Errorf("expected stage name in error, got: %v", err)
	}
}

// 9. Test Container Startup Failure (Port Conflict)
func TestContainerStartupPortConflict(t *testing.T) {
	testDir := setupTestDir(t)
	mockExec := NewMockExecutor()

	mockExec.Handlers["info"] = func(args []string) (string, string, int, error) {
		return "Server Version: 27.1.1", "", 0, nil
	}
	mockExec.Handlers["compose version"] = func(args []string) (string, string, int, error) {
		return "Docker Compose version v2.29.1", "", 0, nil
	}
	mockExec.Handlers["volume create altr_stream_data"] = func(args []string) (string, string, int, error) {
		return "altr_stream_data", "", 0, nil
	}
	mockExec.Handlers["pull"] = func(args []string) (string, string, int, error) {
		return "Image up to date", "", 0, nil
	}
	mockExec.Handlers["up -d"] = func(args []string) (string, string, int, error) {
		return "", "Error response from daemon: driver failed programming external connectivity: bind: address already in use (0.0.0.0:8000)", 1, nil
	}

	engine := NewInstallerEngine(mockExec, &MockHTTPClient{})
	ctx := context.Background()

	cfg := InstallConfig{
		TargetDir:     testDir,
		Version:       "0.13.7-alpha",
		Image:         "ghcr.io/helloaltr/altr-stream:0.13.7-alpha",
		Port:          8000,
		HealthTimeout: 2,
	}

	err := engine.Install(ctx, cfg, nil)
	if err == nil {
		t.Fatalf("expected install to fail on port conflict, but it succeeded")
	}
	if !strings.Contains(err.Error(), "Port conflict") && !strings.Contains(err.Error(), "address already in use") {
		t.Errorf("expected port conflict message, got: %v", err)
	}
}

// 10. Test Health Timeout Failure
func TestHealthTimeoutFailure(t *testing.T) {
	testDir := setupTestDir(t)
	mockExec := NewMockExecutor()

	mockExec.Handlers["info"] = func(args []string) (string, string, int, error) {
		return "Server Version: 27.1.1", "", 0, nil
	}
	mockExec.Handlers["compose version"] = func(args []string) (string, string, int, error) {
		return "Docker Compose version v2.29.1", "", 0, nil
	}
	mockExec.Handlers["volume create altr_stream_data"] = func(args []string) (string, string, int, error) {
		return "altr_stream_data", "", 0, nil
	}
	mockExec.Handlers["pull"] = func(args []string) (string, string, int, error) {
		return "OK", "", 0, nil
	}
	mockExec.Handlers["up -d"] = func(args []string) (string, string, int, error) {
		return "Started", "", 0, nil
	}

	mockHTTP := &MockHTTPClient{
		DoFunc: func(req *http.Request) (*http.Response, error) {
			return nil, fmt.Errorf("connection refused")
		},
	}

	engine := NewInstallerEngine(mockExec, mockHTTP)
	ctx := context.Background()

	cfg := InstallConfig{
		TargetDir:     testDir,
		Version:       "0.13.7-alpha",
		Image:         "ghcr.io/helloaltr/altr-stream:0.13.7-alpha",
		Port:          8000,
		HealthTimeout: 1, // 1 second timeout
	}

	err := engine.Install(ctx, cfg, nil)
	if err == nil {
		t.Fatalf("expected health check failure, got nil")
	}
	if !strings.Contains(err.Error(), "health check timed out") && !strings.Contains(err.Error(), "Waiting for health check") {
		t.Errorf("unexpected error: %v", err)
	}
}

// 11. Test Version Mismatch in Healthcheck
func TestVersionMismatch(t *testing.T) {
	testDir := setupTestDir(t)
	mockExec := NewMockExecutor()

	mockExec.Handlers["info"] = func(args []string) (string, string, int, error) {
		return "Server Version: 27.1.1", "", 0, nil
	}
	mockExec.Handlers["compose version"] = func(args []string) (string, string, int, error) {
		return "Docker Compose version v2.29.1", "", 0, nil
	}
	mockExec.Handlers["volume create altr_stream_data"] = func(args []string) (string, string, int, error) {
		return "altr_stream_data", "", 0, nil
	}
	mockExec.Handlers["pull"] = func(args []string) (string, string, int, error) {
		return "OK", "", 0, nil
	}
	containerStarted := false
	mockExec.Handlers["up -d"] = func(args []string) (string, string, int, error) {
		containerStarted = true
		return "Started", "", 0, nil
	}
	mockExec.Handlers["inspect altr-stream"] = func(args []string) (string, string, int, error) {
		if !containerStarted {
			return "[]", "No such container", 1, nil
		}
		return `[{
			"Id": "abc123456789",
			"State": {"Status": "running", "Running": true},
			"Config": {"Image": "ghcr.io/helloaltr/altr-stream:1.0.0-beta"},
			"NetworkSettings": {"Ports": {"8000/tcp": [{"HostIp": "0.0.0.0", "HostPort": "8000"}]}}
		}]`, "", 0, nil
	}

	mockHTTP := &MockHTTPClient{
		DoFunc: func(req *http.Request) (*http.Response, error) {
			return &http.Response{
				StatusCode: 200,
				Body:       io.NopCloser(bytes.NewBufferString(`{"status":"healthy","version":"0.12.0"}`)),
			}, nil
		},
	}

	engine := NewInstallerEngine(mockExec, mockHTTP)
	ctx := context.Background()

	cfg := InstallConfig{
		TargetDir:     testDir,
		Version:       "1.0.0-beta",
		Image:         "ghcr.io/helloaltr/altr-stream:1.0.0-beta",
		Port:          8000,
		HealthTimeout: 2,
	}

	err := engine.Install(ctx, cfg, nil)
	if err == nil {
		t.Fatalf("expected version mismatch error, got nil")
	}
	if !strings.Contains(err.Error(), "version mismatch") {
		t.Errorf("expected version mismatch error message, got: %v", err)
	}
}

// 12. Test Repair Preserves Named Data Volume
func TestRepairPreservesDataVolume(t *testing.T) {
	testDir := setupTestDir(t)
	mockExec := NewMockExecutor()

	mockExec.Handlers["info"] = func(args []string) (string, string, int, error) {
		return "Server Version: 27.1.1", "", 0, nil
	}
	mockExec.Handlers["compose version"] = func(args []string) (string, string, int, error) {
		return "Docker Compose version v2.29.1", "", 0, nil
	}
	mockExec.Handlers["volume create altr_stream_data"] = func(args []string) (string, string, int, error) {
		return "altr_stream_data", "", 0, nil
	}
	mockExec.Handlers["up -d"] = func(args []string) (string, string, int, error) {
		return "Container altr-stream Recreated", "", 0, nil
	}
	mockExec.Handlers["inspect altr-stream"] = func(args []string) (string, string, int, error) {
		inspectJSON := `[{
			"Id": "abc123456789",
			"State": {"Status": "running", "Running": true, "ExitCode": 0, "Error": ""},
			"Config": {"Image": "ghcr.io/helloaltr/altr-stream:0.13.7-alpha"},
			"NetworkSettings": {"Ports": {"8000/tcp": [{"HostIp": "0.0.0.0", "HostPort": "8000"}]}}
		}]`
		return inspectJSON, "", 0, nil
	}

	mockHTTP := &MockHTTPClient{
		DoFunc: func(req *http.Request) (*http.Response, error) {
			return &http.Response{
				StatusCode: 200,
				Body:       io.NopCloser(bytes.NewBufferString(`{"status":"healthy","version":"0.13.7-alpha"}`)),
			}, nil
		},
	}

	engine := NewInstallerEngine(mockExec, mockHTTP)
	ctx := context.Background()

	cfg := InstallConfig{
		Version:       "0.13.7-alpha",
		Image:         "ghcr.io/helloaltr/altr-stream:0.13.7-alpha",
		Port:          8000,
		HealthTimeout: 5,
	}

	err := engine.Repair(ctx, testDir, cfg, nil)
	if err != nil {
		t.Fatalf("repair failed: %v", err)
	}

	// Verify volume was NOT deleted
	for _, call := range mockExec.CallLog {
		if strings.Contains(call, "volume rm") {
			t.Errorf("CRITICAL VIOLATION: Repair must never execute volume rm! Call was: %s", call)
		}
	}
}

// 13. Test Uninstall With Data Preserved
func TestUninstallPreservesData(t *testing.T) {
	testDir := setupTestDir(t)
	composeFile := filepath.Join(testDir, "docker-compose.yml")
	_ = os.WriteFile(composeFile, []byte("services: {}"), 0644)

	mockExec := NewMockExecutor()
	mockExec.Handlers["info"] = func(args []string) (string, string, int, error) {
		return "Server Version: 27.1.1", "", 0, nil
	}
	mockExec.Handlers["compose"] = func(args []string) (string, string, int, error) {
		return "Docker Compose v2", "", 0, nil
	}
	mockExec.Handlers["down"] = func(args []string) (string, string, int, error) {
		return "Container stopped and removed", "", 0, nil
	}

	engine := NewInstallerEngine(mockExec, &MockHTTPClient{})
	ctx := context.Background()

	err := engine.Uninstall(ctx, testDir, false) // deleteData = false
	if err != nil {
		t.Fatalf("uninstall failed: %v", err)
	}

	for _, call := range mockExec.CallLog {
		if strings.Contains(call, "volume rm") {
			t.Errorf("volume rm should not be called when deleteData=false: %s", call)
		}
	}

	// Directory should still exist
	if _, err := os.Stat(testDir); os.IsNotExist(err) {
		t.Errorf("install directory should be preserved when deleteData=false")
	}
}

// 14. Test Uninstall With Data Deleted
func TestUninstallDeletesData(t *testing.T) {
	testDir := setupTestDir(t)
	composeFile := filepath.Join(testDir, "docker-compose.yml")
	_ = os.WriteFile(composeFile, []byte("services: {}"), 0644)

	mockExec := NewMockExecutor()
	mockExec.Handlers["info"] = func(args []string) (string, string, int, error) {
		return "Server Version: 27.1.1", "", 0, nil
	}
	mockExec.Handlers["inspect altr-stream"] = func(args []string) (string, string, int, error) {
		return `[{"State":{"Status":"running","Running":true},"Mounts":[{"Type":"volume","Name":"altr_stream_data","Destination":"/app/data"}]}]`, "", 0, nil
	}
	mockExec.Handlers["down"] = func(args []string) (string, string, int, error) {
		return "Container stopped and removed", "", 0, nil
	}
	mockExec.Handlers["stop"] = func(args []string) (string, string, int, error) {
		return "altr-stream", "", 0, nil
	}
	mockExec.Handlers["rm -f altr-stream"] = func(args []string) (string, string, int, error) {
		return "altr-stream", "", 0, nil
	}
	mockExec.Handlers["volume rm altr_stream_data"] = func(args []string) (string, string, int, error) {
		return "altr_stream_data", "", 0, nil
	}

	engine := NewInstallerEngine(mockExec, &MockHTTPClient{})
	ctx := context.Background()

	err := engine.Uninstall(ctx, testDir, true) // deleteData = true
	if err != nil {
		t.Fatalf("uninstall failed: %v", err)
	}

	volumeRmCalled := false
	for _, call := range mockExec.CallLog {
		if strings.Contains(call, "volume rm altr_stream_data") {
			volumeRmCalled = true
			break
		}
	}
	if !volumeRmCalled {
		t.Errorf("expected 'docker volume rm altr_stream_data' to be called")
	}
}

// 15. Test Status Query
func TestStatusQuery(t *testing.T) {
	testDir := setupTestDir(t)
	envFile := filepath.Join(testDir, ".env")
	_ = os.WriteFile(envFile, []byte("ALTR_STREAM_PORT=8080\n"), 0644)

	mockExec := NewMockExecutor()
	mockExec.Handlers["info"] = func(args []string) (string, string, int, error) {
		return "Server Version: 27.1.1", "", 0, nil
	}
	mockExec.Handlers["compose version"] = func(args []string) (string, string, int, error) {
		return "Docker Compose v2", "", 0, nil
	}
	mockExec.Handlers["inspect altr-stream"] = func(args []string) (string, string, int, error) {
		return `[{"State": {"Status": "running"}}]`, "", 0, nil
	}

	mockHTTP := &MockHTTPClient{
		DoFunc: func(req *http.Request) (*http.Response, error) {
			if strings.Contains(req.URL.String(), ":8080/api/v1/health") {
				return &http.Response{
					StatusCode: 200,
					Body:       io.NopCloser(bytes.NewBufferString(`{"status":"healthy","version":"1.0.0-beta"}`)),
				}, nil
			}
			return nil, fmt.Errorf("wrong port")
		},
	}

	engine := NewInstallerEngine(mockExec, mockHTTP)
	ctx := context.Background()

	status, err := engine.GetStatus(ctx, testDir)
	if err != nil {
		t.Fatalf("status query failed: %v", err)
	}

	if status.Port != 8080 {
		t.Errorf("expected port 8080 from .env, got: %d", status.Port)
	}
	if status.ContainerState != "running" {
		t.Errorf("expected container state 'running', got: %s", status.ContainerState)
	}
	if !status.Healthy {
		t.Errorf("expected healthy=true")
	}
}

// 16. Test Browser Launch
func TestLaunchBrowser(t *testing.T) {
	mockExec := NewMockExecutor()
	engine := NewInstallerEngine(mockExec, &MockHTTPClient{})
	ctx := context.Background()

	err := engine.LaunchBrowser(ctx, "http://localhost:8000")
	if err != nil {
		t.Fatalf("launch browser failed: %v", err)
	}

	if len(mockExec.CallLog) == 0 {
		t.Errorf("expected at least one command execution for browser launch")
	}
}

// 17. Test Actionable Error Extraction & No %w(<nil>) Formatting
func TestExtractActionableError(t *testing.T) {
	// Simulated Docker Compose output from real Windows failure with file sharing / volume issue
	simulatedLog := `[+] Running 1/2
 - Volume altr-stream_altr_stream_data Creating
 - Container altr-stream Creating
Error response from daemon: Drive has not been shared`

	extracted := extractActionableError(simulatedLog)
	if strings.Contains(extracted, "Volume altr-stream_altr_stream_data Creating") {
		t.Errorf("expected actionable error, but got volume creating line: %s", extracted)
	}
	if !strings.Contains(extracted, "Error response from daemon: Drive has not been shared") {
		t.Errorf("expected daemon error response, got: %s", extracted)
	}

	// Verify StartContainer error does not produce %w(<nil>)
	mockExec := NewMockExecutor()
	mockExec.Handlers["up -d"] = func(args []string) (string, string, int, error) {
		return simulatedLog, "", 1, nil // Exit error with nil err (standard for non-zero exit)
	}

	lm := NewLifecycleManager(mockExec, &MockHTTPClient{})
	lm.StartTimeout = 50 * time.Millisecond
	lm.RetryInterval = 10 * time.Millisecond
	ctx := context.Background()
	testDir := t.TempDir()

	err := lm.StartContainer(ctx, testDir, "docker compose")
	if err == nil {
		t.Fatal("expected StartContainer to fail")
	}

	errStr := err.Error()
	if strings.Contains(errStr, "%w(<nil>)") || strings.Contains(errStr, "%!w(<nil>)") {
		t.Errorf("error contains nil-wrap formatting artifact: %s", errStr)
	}
	if !strings.Contains(errStr, "Error response from daemon: Drive has not been shared") {
		t.Errorf("expected error to contain extracted daemon error, got: %s", errStr)
	}
}

// 18. Test Version Matching with Image Tag Override
func TestCheckVersionMatchWithImageTagOverride(t *testing.T) {
	lm := NewLifecycleManager(NewMockExecutor(), &MockHTTPClient{})

	body := `{"status":"healthy","version":"0.13.7-alpha"}`

	// Canonical version alone should not match 0.13.7-alpha
	if lm.checkVersionMatch(body, "1.0.0-beta") {
		t.Errorf("expected 1.0.0-beta not to match 0.13.7-alpha")
	}

	// Pipe-separated version candidates should match 0.13.7-alpha
	if !lm.checkVersionMatch(body, "1.0.0-beta|0.13.7-alpha") {
		t.Errorf("expected 1.0.0-beta|0.13.7-alpha to match 0.13.7-alpha")
	}

	// Unhealthy status should always fail
	unhealthyBody := `{"status":"starting","version":"0.13.7-alpha"}`
	if lm.checkVersionMatch(unhealthyBody, "1.0.0-beta|0.13.7-alpha") {
		t.Errorf("expected starting status to fail")
	}
}

// 19. Test DetectEnvironment with OneDrive Detection
func TestDetectEnvironmentOneDrive(t *testing.T) {
	mockExec := NewMockExecutor()
	engine := NewInstallerEngine(mockExec, &MockHTTPClient{})

	// Set temporary OneDrive env to simulate Windows redirected environment
	t.Setenv("ALTR_STREAM_HOME", `C:\Users\testuser\OneDrive\.altr-stream`)

	env, err := engine.DetectEnvironment()
	if err != nil {
		t.Fatalf("DetectEnvironment failed: %v", err)
	}
	if !env.IsOneDrive {
		t.Errorf("expected IsOneDrive=true for OneDrive path, got false")
	}

	// Test non-OneDrive path
	t.Setenv("ALTR_STREAM_HOME", `C:\Users\testuser\.altr-stream`)
	env2, err := engine.DetectEnvironment()
	if err != nil {
		t.Fatalf("DetectEnvironment failed: %v", err)
	}
	if env2.IsOneDrive {
		t.Errorf("expected IsOneDrive=false for standard path, got true")
	}
}

// 20. Test VerifyInstallation: Compose succeeds but container immediately exits
func TestVerifyInstallation_ComposeSucceedsButContainerImmediatelyExits(t *testing.T) {
	mockExec := NewMockExecutor()
	// docker inspect returns container in exited state with non-zero exit code
	mockExec.Handlers["docker inspect altr-stream"] = func(args []string) (string, string, int, error) {
		inspectJSON := `[{
			"Id": "abc123456789",
			"State": {"Status": "exited", "Running": false, "ExitCode": 137, "Error": "OOMKilled"},
			"Config": {"Image": "ghcr.io/helloaltr/altr-stream:1.0.0-beta"},
			"NetworkSettings": {"Ports": {"8000/tcp": [{"HostIp": "0.0.0.0", "HostPort": "8000"}]}}
		}]`
		return inspectJSON, "", 0, nil
	}
	mockExec.Handlers["docker logs --tail 25 altr-stream"] = func(args []string) (string, string, int, error) {
		return "Fatal error: memory limit exceeded\nServer terminated", "", 0, nil
	}

	lm := NewLifecycleManager(mockExec, &MockHTTPClient{})
	cfg := InstallConfig{Port: 8000, Image: "ghcr.io/helloaltr/altr-stream:1.0.0-beta"}

	err := lm.VerifyInstallation(context.Background(), cfg, "1.0.0-beta")
	if err == nil {
		t.Fatal("expected VerifyInstallation to fail when container exited")
	}
	if !strings.Contains(err.Error(), "is not running (status: exited, exit code: 137)") {
		t.Errorf("expected status and exit code in error, got: %v", err)
	}
	if !strings.Contains(err.Error(), "Fatal error: memory limit exceeded") {
		t.Errorf("expected container logs in error, got: %v", err)
	}
}

// 21. Test VerifyInstallation: Compose succeeds but container is missing
func TestVerifyInstallation_ComposeSucceedsButContainerMissing(t *testing.T) {
	mockExec := NewMockExecutor()
	mockExec.Handlers["docker inspect altr-stream"] = func(args []string) (string, string, int, error) {
		return "[]", "Error: No such container: altr-stream", 1, nil
	}

	lm := NewLifecycleManager(mockExec, &MockHTTPClient{})
	cfg := InstallConfig{Port: 8000, Image: "ghcr.io/helloaltr/altr-stream:1.0.0-beta"}

	err := lm.VerifyInstallation(context.Background(), cfg, "1.0.0-beta")
	if err == nil {
		t.Fatal("expected VerifyInstallation to fail when container missing")
	}
	if !strings.Contains(err.Error(), "container 'altr-stream' does not exist after startup") {
		t.Errorf("expected missing container error, got: %v", err)
	}
}

// 22. Test VerifyInstallation: Container exists but is not running (e.g. restarting or created)
func TestVerifyInstallation_ContainerExistsButNotRunning(t *testing.T) {
	mockExec := NewMockExecutor()
	mockExec.Handlers["docker inspect altr-stream"] = func(args []string) (string, string, int, error) {
		inspectJSON := `[{
			"Id": "abc123456789",
			"State": {"Status": "restarting", "Running": false, "ExitCode": 1, "Error": ""},
			"Config": {"Image": "ghcr.io/helloaltr/altr-stream:1.0.0-beta"},
			"NetworkSettings": {"Ports": {}}
		}]`
		return inspectJSON, "", 0, nil
	}

	lm := NewLifecycleManager(mockExec, &MockHTTPClient{})
	cfg := InstallConfig{Port: 8000, Image: "ghcr.io/helloaltr/altr-stream:1.0.0-beta"}

	err := lm.VerifyInstallation(context.Background(), cfg, "1.0.0-beta")
	if err == nil {
		t.Fatal("expected VerifyInstallation to fail for restarting container")
	}
	if !strings.Contains(err.Error(), "is not running (status: restarting, exit code: 1)") {
		t.Errorf("expected restarting status in error, got: %v", err)
	}
}

// 23. Test VerifyInstallation: Container running but port is not mapped
func TestVerifyInstallation_ContainerRunningButPortNotMapped(t *testing.T) {
	mockExec := NewMockExecutor()
	mockExec.Handlers["docker inspect altr-stream"] = func(args []string) (string, string, int, error) {
		inspectJSON := `[{
			"Id": "abc123456789",
			"State": {"Status": "running", "Running": true, "ExitCode": 0, "Error": ""},
			"Config": {"Image": "ghcr.io/helloaltr/altr-stream:1.0.0-beta"},
			"NetworkSettings": {"Ports": {"8000/tcp": null}}
		}]`
		return inspectJSON, "", 0, nil
	}

	lm := NewLifecycleManager(mockExec, &MockHTTPClient{})
	cfg := InstallConfig{Port: 8000, Image: "ghcr.io/helloaltr/altr-stream:1.0.0-beta"}

	err := lm.VerifyInstallation(context.Background(), cfg, "1.0.0-beta")
	if err == nil {
		t.Fatal("expected VerifyInstallation to fail when port not mapped")
	}
	if !strings.Contains(err.Error(), "port 8000/tcp is not mapped to host port 8000") {
		t.Errorf("expected port mapping error, got: %v", err)
	}
}

// 24. Test VerifyInstallation: Health endpoint unreachable
func TestVerifyInstallation_HealthEndpointUnreachable(t *testing.T) {
	mockExec := NewMockExecutor()
	mockExec.Handlers["docker inspect altr-stream"] = func(args []string) (string, string, int, error) {
		inspectJSON := `[{
			"Id": "abc123456789",
			"State": {"Status": "running", "Running": true, "ExitCode": 0, "Error": ""},
			"Config": {"Image": "ghcr.io/helloaltr/altr-stream:1.0.0-beta"},
			"NetworkSettings": {"Ports": {"8000/tcp": [{"HostIp": "0.0.0.0", "HostPort": "8000"}]}}
		}]`
		return inspectJSON, "", 0, nil
	}

	failingHTTP := &MockHTTPClient{
		DoFunc: func(req *http.Request) (*http.Response, error) {
			return nil, fmt.Errorf("connection refused")
		},
	}

	lm := NewLifecycleManager(mockExec, failingHTTP)
	cfg := InstallConfig{Port: 8000, Image: "ghcr.io/helloaltr/altr-stream:1.0.0-beta"}

	err := lm.VerifyInstallation(context.Background(), cfg, "1.0.0-beta")
	if err == nil {
		t.Fatal("expected VerifyInstallation to fail when health unreachable")
	}
	if !strings.Contains(err.Error(), "health endpoint is unreachable") {
		t.Errorf("expected health unreachable error, got: %v", err)
	}
}

// 25. Test VerifyInstallation: Health endpoint returns failure status
func TestVerifyInstallation_HealthEndpointReturnsFailure(t *testing.T) {
	mockExec := NewMockExecutor()
	mockExec.Handlers["docker inspect altr-stream"] = func(args []string) (string, string, int, error) {
		inspectJSON := `[{
			"Id": "abc123456789",
			"State": {"Status": "running", "Running": true, "ExitCode": 0, "Error": ""},
			"Config": {"Image": "ghcr.io/helloaltr/altr-stream:1.0.0-beta"},
			"NetworkSettings": {"Ports": {"8000/tcp": [{"HostIp": "0.0.0.0", "HostPort": "8000"}]}}
		}]`
		return inspectJSON, "", 0, nil
	}

	errorHTTP := &MockHTTPClient{
		DoFunc: func(req *http.Request) (*http.Response, error) {
			return &http.Response{
				StatusCode: 200,
				Body:       io.NopCloser(bytes.NewBufferString(`{"status":"degraded","version":"1.0.0-beta"}`)),
			}, nil
		},
	}

	lm := NewLifecycleManager(mockExec, errorHTTP)
	cfg := InstallConfig{Port: 8000, Image: "ghcr.io/helloaltr/altr-stream:1.0.0-beta"}

	err := lm.VerifyInstallation(context.Background(), cfg, "1.0.0-beta")
	if err == nil {
		t.Fatal("expected VerifyInstallation to fail when status is degraded")
	}
	if !strings.Contains(err.Error(), "health endpoint reported unhealthy status: degraded") {
		t.Errorf("expected unhealthy status error, got: %v", err)
	}
}

// 26. Test VerifyInstallation: Health endpoint returns wrong version
func TestVerifyInstallation_HealthEndpointReturnsWrongVersion(t *testing.T) {
	mockExec := NewMockExecutor()
	mockExec.Handlers["docker inspect altr-stream"] = func(args []string) (string, string, int, error) {
		inspectJSON := `[{
			"Id": "abc123456789",
			"State": {"Status": "running", "Running": true, "ExitCode": 0, "Error": ""},
			"Config": {"Image": "ghcr.io/helloaltr/altr-stream:1.0.0-beta"},
			"NetworkSettings": {"Ports": {"8000/tcp": [{"HostIp": "0.0.0.0", "HostPort": "8000"}]}}
		}]`
		return inspectJSON, "", 0, nil
	}

	oldVerHTTP := &MockHTTPClient{
		DoFunc: func(req *http.Request) (*http.Response, error) {
			return &http.Response{
				StatusCode: 200,
				Body:       io.NopCloser(bytes.NewBufferString(`{"status":"healthy","version":"0.8.0"}`)),
			}, nil
		},
	}

	lm := NewLifecycleManager(mockExec, oldVerHTTP)
	cfg := InstallConfig{Port: 8000, Image: "ghcr.io/helloaltr/altr-stream:1.0.0-beta"}

	err := lm.VerifyInstallation(context.Background(), cfg, "1.0.0-beta")
	if err == nil {
		t.Fatal("expected VerifyInstallation to fail on version mismatch")
	}
	if !strings.Contains(err.Error(), "version mismatch in health response") {
		t.Errorf("expected version mismatch error, got: %v", err)
	}
}

// 27. Test VerifyInstallation: Genuine Success
func TestVerifyInstallation_GenuineSuccess(t *testing.T) {
	mockExec := NewMockExecutor()
	mockExec.Handlers["docker inspect altr-stream"] = func(args []string) (string, string, int, error) {
		inspectJSON := `[{
			"Id": "abc123456789",
			"State": {"Status": "running", "Running": true, "ExitCode": 0, "Error": ""},
			"Config": {"Image": "ghcr.io/helloaltr/altr-stream:1.0.0-beta"},
			"NetworkSettings": {"Ports": {"8000/tcp": [{"HostIp": "0.0.0.0", "HostPort": "8000"}]}}
		}]`
		return inspectJSON, "", 0, nil
	}

	successHTTP := &MockHTTPClient{
		DoFunc: func(req *http.Request) (*http.Response, error) {
			return &http.Response{
				StatusCode: 200,
				Body:       io.NopCloser(bytes.NewBufferString(`{"status":"healthy","version":"1.0.0-beta"}`)),
			}, nil
		},
	}

	lm := NewLifecycleManager(mockExec, successHTTP)
	cfg := InstallConfig{Port: 8000, Image: "ghcr.io/helloaltr/altr-stream:1.0.0-beta"}

	err := lm.VerifyInstallation(context.Background(), cfg, "1.0.0-beta")
	if err != nil {
		t.Fatalf("expected VerifyInstallation to succeed, got: %v", err)
	}
}

// 28. Test LaunchBrowser: Guarded by Actual Availability
func TestLaunchBrowser_GuardedByActualAvailability(t *testing.T) {
	mockExec := NewMockExecutor()

	// 1. When local application is down, LaunchBrowser fails and does not execute OS command
	downHTTP := &MockHTTPClient{
		DoFunc: func(req *http.Request) (*http.Response, error) {
			return nil, fmt.Errorf("dial tcp 127.0.0.1:8000: connect: connection refused")
		},
	}

	err := LaunchBrowser(context.Background(), mockExec, downHTTP, "http://localhost:8000")
	if err == nil {
		t.Fatal("expected LaunchBrowser to fail when application is down")
	}
	if !strings.Contains(err.Error(), "application is not reachable at http://localhost:8000") {
		t.Errorf("expected reachability error, got: %v", err)
	}
	if len(mockExec.CallLog) > 0 {
		t.Errorf("expected no OS launch command when application is down, got: %v", mockExec.CallLog)
	}

	// 2. When local application is healthy, LaunchBrowser executes OS launch command
	upHTTP := &MockHTTPClient{
		DoFunc: func(req *http.Request) (*http.Response, error) {
			return &http.Response{StatusCode: 200, Body: io.NopCloser(bytes.NewBufferString("ok"))}, nil
		},
	}

	err = LaunchBrowser(context.Background(), mockExec, upHTTP, "http://localhost:8000")
	if err != nil {
		t.Fatalf("expected LaunchBrowser to succeed when application is up, got: %v", err)
	}
	if len(mockExec.CallLog) == 0 {
		t.Errorf("expected OS launch command to be called when application is up")
	}
}

// 29. Test Actionable Error Extraction for Docker Desktop File Sharing
func TestExtractActionableError_FileSharing_TranslatesExactPath(t *testing.T) {
	rawLog := `Container altr-stream Creating
service:altr-stream:1 Error response from daemon:
the path
"C:\Users\santh.VICTUS\.altr-stream\data\updates"
is not shared from the host;
add it in Settings > Resources > File Sharing before using it in a container`

	errStr := extractActionableError(rawLog)

	if !strings.Contains(errStr, "Docker Desktop needs permission to access Altr Stream's data folder.") {
		t.Errorf("expected user-friendly explanation, got: %s", errStr)
	}
	if !strings.Contains(errStr, `C:\Users\santh.VICTUS\.altr-stream\data\updates`) {
		t.Errorf("expected extracted path in error message, got: %s", errStr)
	}
	if !strings.Contains(errStr, "Settings > Resources > File Sharing") {
		t.Errorf("expected file sharing settings hint, got: %s", errStr)
	}
}

// 30. Test Docker Check Classifies Offline Engine as DockerStateStopped
func TestCheckDocker_ClassifiesDaemonOfflineAsStopped(t *testing.T) {
	mockExec := NewMockExecutor()
	// CLI is found
	mockExec.Handlers["docker --version"] = func(args []string) (string, string, int, error) {
		return "Docker version 27.2.0, build 3ab4256", "", 0, nil
	}
	// Compose is found
	mockExec.Handlers["docker compose version"] = func(args []string) (string, string, int, error) {
		return "Docker Compose version v2.29.2", "", 0, nil
	}
	// Engine ping fails (daemon offline)
	mockExec.Handlers["docker info"] = func(args []string) (string, string, int, error) {
		return "", "error during connect: This error may indicate that the docker daemon is not running.", 1, fmt.Errorf("exit status 1")
	}

	dm := NewDockerManager(mockExec)
	dm.stat = func(name string) (os.FileInfo, error) {
		return nil, os.ErrNotExist
	}
	status := dm.CheckDocker(context.Background())

	if status.State != DockerStateStopped {
		t.Errorf("expected state to be %s, got: %s", DockerStateStopped, status.State)
	}
	if status.StatusText != "Docker Desktop is Stopped" {
		t.Errorf("expected StatusText 'Docker Desktop is Stopped', got: %s", status.StatusText)
	}
	if status.ActionHint != "Start Docker Desktop" {
		t.Errorf("expected ActionHint 'Start Docker Desktop', got: %s", status.ActionHint)
	}
}

// 31. Test StartContainer Classifies File-Sharing Error Immediately Without Hammering
func TestStartContainer_FileSharing_ReturnsFileSharingRequiredWithoutHammering(t *testing.T) {
	mockExec := NewMockExecutor()
	testDir := t.TempDir()

	composeAttempts := 0
	fileSharingErr := `Container altr-stream Creating
service:altr-stream:1 Error response from daemon: the path "C:\Users\santh.VICTUS\.altr-stream\data\updates" is not shared from the host; add it in Settings > Resources > File Sharing before using it in a container`

	mockExec.Handlers["up -d"] = func(args []string) (string, string, int, error) {
		composeAttempts++
		return "", fileSharingErr, 1, nil
	}
	mockExec.Handlers["inspect -f {{.State.Running}} altr-stream"] = func(args []string) (string, string, int, error) {
		return "false", "", 1, fmt.Errorf("no such container")
	}

	lm := NewLifecycleManager(mockExec, &MockHTTPClient{})

	err := lm.StartContainer(context.Background(), testDir, "docker compose")
	if err == nil {
		t.Fatal("expected StartContainer to return ErrFileSharingRequired")
	}

	// Must NOT hammer in an automated loop: exactly 1 attempt
	if composeAttempts != 1 {
		t.Errorf("expected exactly 1 compose attempt (no automated hammering), got %d", composeAttempts)
	}

	// Check typed error
	var fileShareErr *ErrFileSharingRequired
	if !errors.As(err, &fileShareErr) {
		t.Fatalf("expected error of type *ErrFileSharingRequired, got: %T (%v)", err, err)
	}

	if fileShareErr.Path != `C:\Users\santh.VICTUS\.altr-stream\data\updates` {
		t.Errorf("expected path 'C:\\Users\\santh.VICTUS\\.altr-stream\\data\\updates', got: %s", fileShareErr.Path)
	}

	errStr := err.Error()
	if !strings.HasPrefix(errStr, "FILE_SHARING_REQUIRED|") {
		t.Errorf("expected error to start with FILE_SHARING_REQUIRED|, got: %s", errStr)
	}

	// Verify log contains Attempt 1
	logPath := filepath.Join(testDir, ".docker_start.log")
	logContent, readErr := os.ReadFile(logPath)
	if readErr != nil {
		t.Fatalf("failed to read .docker_start.log: %v", readErr)
	}
	logStr := string(logContent)
	if !strings.Contains(logStr, "=== Container Startup Attempt 1 ===") {
		t.Errorf("expected Attempt 1 in log, got: %s", logStr)
	}
	if !strings.Contains(logStr, "is not shared from the host") {
		t.Errorf("expected daemon error in log, got: %s", logStr)
	}
}

// 32. Test StartContainer Explicit Retry Flow: Attempt 1 Fails -> User Grants Access -> Attempt 2 Succeeds
func TestStartContainer_ExplicitRetry_SucceedsAfterPermissionGranted(t *testing.T) {
	mockExec := NewMockExecutor()
	testDir := t.TempDir()

	composeAttempts := 0
	fileSharingErr := `Container altr-stream Creating
service:altr-stream:1 Error response from daemon: the path "C:\Users\santh.VICTUS\.altr-stream\data\updates" is not shared from the host; add it in Settings > Resources > File Sharing before using it in a container`

	mockExec.Handlers["up -d"] = func(args []string) (string, string, int, error) {
		composeAttempts++
		if composeAttempts == 1 {
			// First attempt fails with file-sharing requirement
			return "", fileSharingErr, 1, nil
		}
		// Second attempt (after user grants permission and clicks Retry) succeeds
		return "Container altr-stream Starting\nContainer altr-stream Started", "", 0, nil
	}
	mockExec.Handlers["inspect -f {{.State.Running}} altr-stream"] = func(args []string) (string, string, int, error) {
		if composeAttempts >= 2 {
			return "true", "", 0, nil
		}
		return "false", "", 1, fmt.Errorf("no such container")
	}

	lm := NewLifecycleManager(mockExec, &MockHTTPClient{})

	// Attempt 1: Fails with ErrFileSharingRequired
	err1 := lm.StartContainer(context.Background(), testDir, "docker compose")
	if err1 == nil {
		t.Fatal("expected attempt 1 to fail with ErrFileSharingRequired")
	}
	var fsErr *ErrFileSharingRequired
	if !errors.As(err1, &fsErr) {
		t.Fatalf("expected ErrFileSharingRequired on attempt 1, got %v", err1)
	}
	if composeAttempts != 1 {
		t.Fatalf("expected 1 attempt after first call, got %d", composeAttempts)
	}

	// User grants permission in Docker Desktop and clicks explicit [Retry]
	// Attempt 2: Re-invoked cleanly
	err2 := lm.StartContainer(context.Background(), testDir, "docker compose")
	if err2 != nil {
		t.Fatalf("expected attempt 2 to succeed after user granted permission, got: %v", err2)
	}
	if composeAttempts != 2 {
		t.Fatalf("expected 2 compose attempts total, got %d", composeAttempts)
	}

	// Verify log contains both Attempt 1 and Attempt 2
	logPath := filepath.Join(testDir, ".docker_start.log")
	logContent, readErr := os.ReadFile(logPath)
	if readErr != nil {
		t.Fatalf("failed to read .docker_start.log: %v", readErr)
	}
	logStr := string(logContent)
	if !strings.Contains(logStr, "=== Container Startup Attempt 1 ===") {
		t.Errorf("expected Attempt 1 in log, got: %s", logStr)
	}
	if !strings.Contains(logStr, "=== Container Startup Attempt 2 ===") {
		t.Errorf("expected Attempt 2 in log, got: %s", logStr)
	}
	if !strings.Contains(logStr, "Container altr-stream Started") {
		t.Errorf("expected successful startup output in log, got: %s", logStr)
	}
}

// 32b. Test StartContainer Explicit Retry Flow: Permission Still Unavailable Remains In State
func TestStartContainer_ExplicitRetry_RemainsInFileSharingStateWhenNotGranted(t *testing.T) {
	mockExec := NewMockExecutor()
	testDir := t.TempDir()

	composeAttempts := 0
	fileSharingErr := `Container altr-stream Creating
service:altr-stream:1 Error response from daemon: the path "C:\Users\santh.VICTUS\.altr-stream\data\updates" is not shared from the host; add it in Settings > Resources > File Sharing before using it in a container`

	mockExec.Handlers["up -d"] = func(args []string) (string, string, int, error) {
		composeAttempts++
		return "", fileSharingErr, 1, nil
	}
	mockExec.Handlers["inspect -f {{.State.Running}} altr-stream"] = func(args []string) (string, string, int, error) {
		return "false", "", 1, fmt.Errorf("no such container")
	}

	lm := NewLifecycleManager(mockExec, &MockHTTPClient{})

	// Attempt 1:
	err1 := lm.StartContainer(context.Background(), testDir, "docker compose")
	if err1 == nil || !strings.Contains(err1.Error(), "FILE_SHARING_REQUIRED") {
		t.Fatalf("expected FILE_SHARING_REQUIRED on attempt 1, got %v", err1)
	}

	// Attempt 2 (user clicked Retry without granting permission):
	err2 := lm.StartContainer(context.Background(), testDir, "docker compose")
	if err2 == nil || !strings.Contains(err2.Error(), "FILE_SHARING_REQUIRED") {
		t.Fatalf("expected FILE_SHARING_REQUIRED on attempt 2, got %v", err2)
	}

	if composeAttempts != 2 {
		t.Fatalf("expected exactly 2 attempts total, got %d", composeAttempts)
	}

	// Verify log contains both attempts
	logPath := filepath.Join(testDir, ".docker_start.log")
	logContent, _ := os.ReadFile(logPath)
	logStr := string(logContent)
	if !strings.Contains(logStr, "=== Container Startup Attempt 1 ===") || !strings.Contains(logStr, "=== Container Startup Attempt 2 ===") {
		t.Errorf("expected both attempts logged, got: %s", logStr)
	}
}


// 33. Test StartContainer Unrelated Failure Exits Immediately Without Retrying
func TestStartContainer_UnrelatedFailure_DoesNotRetry(t *testing.T) {
	mockExec := NewMockExecutor()
	testDir := t.TempDir()

	composeAttempts := 0
	portErr := `Error response from daemon: driver failed programming external connectivity on endpoint altr-stream: Bind for 0.0.0.0:8000 failed: port is already allocated`

	mockExec.Handlers["up -d"] = func(args []string) (string, string, int, error) {
		composeAttempts++
		return "", portErr, 1, nil
	}
	mockExec.Handlers["inspect -f {{.State.Running}} altr-stream"] = func(args []string) (string, string, int, error) {
		return "false", "", 1, fmt.Errorf("no such container")
	}

	lm := NewLifecycleManager(mockExec, &MockHTTPClient{})
	lm.StartTimeout = 2 * time.Second
	lm.RetryInterval = 20 * time.Millisecond

	err := lm.StartContainer(context.Background(), testDir, "docker compose")
	if err == nil {
		t.Fatal("expected StartContainer to fail on port conflict")
	}

	if composeAttempts != 1 {
		t.Errorf("expected exactly 1 attempt for non-file-sharing error, got %d", composeAttempts)
	}

	errStr := err.Error()
	if !strings.Contains(errStr, "Port conflict") && !strings.Contains(errStr, "port is already allocated") {
		t.Errorf("expected port conflict error, got: %s", errStr)
	}
}

// 34. Test StartContainer Detects Already Running Container
func TestStartContainer_DetectsContainerAlreadyRunning(t *testing.T) {
	mockExec := NewMockExecutor()
	testDir := t.TempDir()

	composeCalled := false
	mockExec.Handlers["up -d"] = func(args []string) (string, string, int, error) {
		composeCalled = true
		return "", "", 0, nil
	}
	mockExec.Handlers["inspect -f {{.State.Running}} altr-stream"] = func(args []string) (string, string, int, error) {
		return "true", "", 0, nil
	}

	lm := NewLifecycleManager(mockExec, &MockHTTPClient{})
	err := lm.StartContainer(context.Background(), testDir, "docker compose")
	if err != nil {
		t.Fatalf("expected StartContainer to succeed when container is already running, got: %v", err)
	}

	if composeCalled {
		t.Errorf("expected compose up not to be called when container is already running")
	}
}

// 34b. Test StartContainer Recreates Running Container When Image Differs
func TestStartContainer_RecreatesContainerWhenImageDiffers(t *testing.T) {
	mockExec := NewMockExecutor()
	testDir := t.TempDir()

	_ = os.WriteFile(filepath.Join(testDir, ".env"), []byte("ALTR_STREAM_IMAGE=ghcr.io/helloaltr/altr-stream:1.0.1-beta\n"), 0644)

	composeCalled := false
	mockExec.Handlers["up -d"] = func(args []string) (string, string, int, error) {
		composeCalled = true
		return "", "", 0, nil
	}
	mockExec.Handlers["inspect -f {{.State.Running}} altr-stream"] = func(args []string) (string, string, int, error) {
		return "true", "", 0, nil
	}
	mockExec.Handlers["inspect -f {{.Config.Image}} altr-stream"] = func(args []string) (string, string, int, error) {
		return "ghcr.io/helloaltr/altr-stream:0.13.7-alpha", "", 0, nil
	}

	lm := NewLifecycleManager(mockExec, &MockHTTPClient{})
	err := lm.StartContainer(context.Background(), testDir, "docker compose")
	if err != nil {
		t.Fatalf("expected StartContainer to succeed, got: %v", err)
	}

	if !composeCalled {
		t.Errorf("expected compose up to be called to recreate container with updated image")
	}
}

// 35. Test OpenDockerSettings Execution & Application Fallback
func TestOpenDockerSettings(t *testing.T) {
	if runtime.GOOS != "darwin" {
		t.Skip("skipping Darwin-specific Docker settings deep-link test on non-Darwin host")
	}
	mockExec := NewMockExecutor()
	dm := NewDockerManager(mockExec)

	err := dm.OpenDockerSettings(context.Background())
	if err != nil {
		t.Fatalf("OpenDockerSettings failed: %v", err)
	}

	settingsAttempted := false
	launchAttempted := false

	for _, call := range mockExec.CallLog {
		if strings.Contains(call, "docker-desktop://settings") {
			settingsAttempted = true
		}
		if strings.Contains(call, "open -a") || strings.Contains(call, "Docker Desktop") || strings.Contains(call, "docker-desktop") {
			launchAttempted = true
		}
	}

	if !settingsAttempted {
		t.Errorf("expected settings URI command to be attempted in CallLog: %v", mockExec.CallLog)
	}
	if !launchAttempted {
		t.Errorf("expected Docker Desktop launch fallback to be executed in CallLog: %v", mockExec.CallLog)
	}
}

func TestOpenDockerSettings_DeepLinkFailure_FallsBackToApplicationLaunch(t *testing.T) {
	mockExec := NewMockExecutor()
	// Deep link fails or is unsupported
	mockExec.Handlers["docker-desktop://settings"] = func(args []string) (string, string, int, error) {
		return "", "protocol not found", 1, errors.New("protocol not found")
	}

	dm := NewDockerManager(mockExec)
	err := dm.OpenDockerSettings(context.Background())
	if err != nil {
		t.Fatalf("expected OpenDockerSettings to succeed via application launch fallback, got: %v", err)
	}

	launchAttempted := false
	for _, call := range mockExec.CallLog {
		if strings.Contains(call, "open -a") || strings.Contains(call, "Docker Desktop") || strings.Contains(call, "docker-desktop") {
			launchAttempted = true
		}
	}
	if !launchAttempted {
		t.Errorf("expected application launch fallback to be recorded in CallLog: %v", mockExec.CallLog)
	}
}

// 36. Test Install Pipeline Returns FILE_SHARING_REQUIRED Error
func TestInstall_FileSharingRequired_PipelineOutput(t *testing.T) {
	mockExec := NewMockExecutor()
	mockClient := &MockHTTPClient{}
	engine := NewInstallerEngine(mockExec, mockClient)
	testDir := t.TempDir()

	// Pre-requisites pass
	mockExec.Handlers["docker --version"] = func(args []string) (string, string, int, error) {
		return "Docker version 27.2.0", "", 0, nil
	}
	mockExec.Handlers["docker compose version"] = func(args []string) (string, string, int, error) {
		return "Docker Compose version v2.29.2", "", 0, nil
	}
	mockExec.Handlers["docker info"] = func(args []string) (string, string, int, error) {
		return "Server Version: 27.2.0", "", 0, nil
	}
	mockExec.Handlers["docker volume create altr_stream_data"] = func(args []string) (string, string, int, error) {
		return "altr_stream_data", "", 0, nil
	}
	mockExec.Handlers["pull"] = func(args []string) (string, string, int, error) {
		return "Status: Image is up to date", "", 0, nil
	}
	fileSharingErr := `service:altr-stream:1 Error response from daemon: the path "C:\Users\santh.VICTUS\.altr-stream\data\updates" is not shared from the host; add it in Settings > Resources > File Sharing before using it in a container`
	mockExec.Handlers["up -d"] = func(args []string) (string, string, int, error) {
		return "", fileSharingErr, 1, nil
	}
	mockExec.Handlers["inspect -f {{.State.Running}} altr-stream"] = func(args []string) (string, string, int, error) {
		return "false", "", 1, fmt.Errorf("no such container")
	}

	cfg := InstallConfig{
		TargetDir: testDir,
		Version:   "1.0.0-beta",
		Image:     "ghcr.io/helloaltr/altr-stream:0.13.7-alpha",
		Port:      8000,
	}

	var stages []InstallStage
	err := engine.Install(context.Background(), cfg, func(p InstallProgress) {
		stages = append(stages, p.Stage)
	})

	if err == nil {
		t.Fatal("expected Install to return error for file sharing requirement")
	}

	errStr := err.Error()
	if !strings.Contains(errStr, "FILE_SHARING_REQUIRED") {
		t.Errorf("expected error to contain FILE_SHARING_REQUIRED, got: %s", errStr)
	}
	if !strings.Contains(errStr, `C:\Users\santh.VICTUS\.altr-stream\data\updates`) {
		t.Errorf("expected error to contain updates path, got: %s", errStr)
	}
}

// 40. Test LaunchDockerDesktop uses StartDetached
func TestLaunchDockerDesktop_DetachedWithoutPipes(t *testing.T) {
	mockExec := NewMockExecutor()
	engine := NewInstallerEngine(mockExec, &MockHTTPClient{})
	engine.dockerManager.stat = func(name string) (os.FileInfo, error) {
		return &fakeFileInfo{isDir: false}, nil
	}

	ctx := context.Background()
	err := engine.dockerManager.LaunchDockerDesktop(ctx)
	if err != nil {
		t.Fatalf("unexpected error launching docker: %v", err)
	}

	foundDetached := false
	for _, call := range mockExec.CallLog {
		if strings.HasPrefix(call, "DETACHED:") {
			foundDetached = true
			break
		}
	}
	if !foundDetached {
		t.Errorf("expected detached launch, calls were: %v", mockExec.CallLog)
	}
}

// 41. Test WaitForDocker happy path returns immediately when Docker is already ready
func TestWaitForDocker_AlreadyReady_ReturnsImmediately(t *testing.T) {
	mockExec := NewMockExecutor()
	mockExec.Handlers["info"] = func(args []string) (string, string, int, error) {
		return "Server Version: 27.2.0", "", 0, nil
	}
	mockExec.Handlers["compose version"] = func(args []string) (string, string, int, error) {
		return "Docker Compose version v2.29.2", "", 0, nil
	}

	engine := NewInstallerEngine(mockExec, &MockHTTPClient{})
	engine.dockerManager.lookPath = func(file string) (string, error) {
		return "/usr/bin/" + file, nil
	}
	engine.dockerManager.stat = func(name string) (os.FileInfo, error) {
		return &fakeFileInfo{isDir: true}, nil
	}

	ctx := context.Background()
	progressCalled := false
	start := time.Now()
	err := engine.WaitForDocker(ctx, 5*time.Second, func(elapsed time.Duration) {
		progressCalled = true
	})
	elapsed := time.Since(start)

	if err != nil {
		t.Fatalf("expected WaitForDocker to succeed immediately, got: %v", err)
	}
	if progressCalled {
		t.Errorf("progress should not be called when Docker is already ready")
	}
	if elapsed > 500*time.Millisecond {
		t.Errorf("expected near-instant completion, took: %v", elapsed)
	}
}

// 42. Test WaitForDocker bounded timeout when daemon never becomes ready
func TestWaitForDocker_DaemonNeverReady_BoundedTimeout(t *testing.T) {
	mockExec := NewMockExecutor()
	mockExec.Handlers["info"] = func(args []string) (string, string, int, error) {
		return "", "daemon is offline", 1, nil
	}

	engine := NewInstallerEngine(mockExec, &MockHTTPClient{})
	engine.dockerManager.lookPath = func(file string) (string, error) {
		return "/usr/bin/" + file, nil
	}
	engine.dockerManager.stat = func(name string) (os.FileInfo, error) {
		return &fakeFileInfo{isDir: true}, nil
	}

	ctx := context.Background()
	start := time.Now()
	timeout := 50 * time.Millisecond
	err := engine.WaitForDocker(ctx, timeout, nil)
	elapsed := time.Since(start)

	if err == nil {
		t.Fatalf("expected timeout error, got nil")
	}
	if !strings.Contains(err.Error(), "timeout waiting for Docker Engine") {
		t.Errorf("unexpected error format: %v", err)
	}
	if elapsed > 2*time.Second {
		t.Errorf("timeout took too long: %v", elapsed)
	}
}

// 43. Test WaitForDocker context cancellation
func TestWaitForDocker_ContextCancelled(t *testing.T) {
	mockExec := NewMockExecutor()
	mockExec.Handlers["info"] = func(args []string) (string, string, int, error) {
		return "", "daemon is offline", 1, nil
	}

	engine := NewInstallerEngine(mockExec, &MockHTTPClient{})
	engine.dockerManager.lookPath = func(file string) (string, error) {
		return "/usr/bin/" + file, nil
	}
	engine.dockerManager.stat = func(name string) (os.FileInfo, error) {
		return &fakeFileInfo{isDir: true}, nil
	}

	ctx, cancel := context.WithCancel(context.Background())
	go func() {
		time.Sleep(50 * time.Millisecond)
		cancel()
	}()

	err := engine.WaitForDocker(ctx, 10*time.Second, nil)
	if !errors.Is(err, context.Canceled) {
		t.Fatalf("expected context.Canceled, got: %v", err)
	}
}

// 44. Test Darwin Platform Docker Detection & Launching
func TestDarwinPlatform_DockerDesktopDetectionAndLaunch(t *testing.T) {
	if runtime.GOOS != "darwin" {
		t.Skip("skipping Darwin-specific unit test on non-Darwin host")
	}

	mockExec := NewMockExecutor()
	engine := NewInstallerEngine(mockExec, &MockHTTPClient{})

	// Case 1: /Applications/Docker.app exists
	engine.dockerManager.stat = func(name string) (os.FileInfo, error) {
		if name == "/Applications/Docker.app" {
			return &fakeFileInfo{isDir: true}, nil
		}
		return nil, os.ErrNotExist
	}

	path, exists := engine.dockerManager.ResolveDockerDesktop()
	if !exists || path != "/Applications/Docker.app" {
		t.Errorf("expected /Applications/Docker.app, got path=%q exists=%v", path, exists)
	}

	ctx := context.Background()
	err := engine.dockerManager.LaunchDockerDesktop(ctx)
	if err != nil {
		t.Fatalf("unexpected error launching docker: %v", err)
	}

	expectedCall := "DETACHED: open -a /Applications/Docker.app"
	found := false
	for _, call := range mockExec.CallLog {
		if call == expectedCall {
			found = true
			break
		}
	}
	if !found {
		t.Errorf("expected call %q, got: %v", expectedCall, mockExec.CallLog)
	}
}

// 45. Test Darwin Platform Docker CLI Candidates
func TestDarwinPlatform_CLICandidates(t *testing.T) {
	candidates := getPlatformDockerCLICandidates("/Users/testuser")
	if runtime.GOOS == "darwin" {
		expected := []string{
			"/opt/homebrew/bin/docker",
			"/usr/local/bin/docker",
			"/Applications/Docker.app/Contents/Resources/bin/docker",
			"/Users/testuser/.docker/bin/docker",
		}
		if len(candidates) != len(expected) {
			t.Fatalf("expected %d candidates, got: %v", len(expected), candidates)
		}
		for i, exp := range expected {
			if candidates[i] != exp {
				t.Errorf("candidate %d mismatch: expected %q, got %q", i, exp, candidates[i])
			}
		}
	}
}

// 46. Test Darwin Platform Browser Launch
func TestDarwinPlatform_LaunchBrowser(t *testing.T) {
	if runtime.GOOS != "darwin" {
		t.Skip("skipping Darwin-specific unit test on non-Darwin host")
	}

	mockExec := NewMockExecutor()
	ctx := context.Background()
	err := launchPlatformBrowser(ctx, mockExec, "http://localhost:8000")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	expectedCall := "DETACHED: open http://localhost:8000"
	found := false
	for _, call := range mockExec.CallLog {
		if call == expectedCall {
			found = true
			break
		}
	}
	if !found {
		t.Errorf("expected call %q, got: %v", expectedCall, mockExec.CallLog)
	}
}

// 47. Test Darwin Platform Official Docker URL
func TestDarwinPlatform_OfficialDockerURL(t *testing.T) {
	if runtime.GOOS != "darwin" {
		t.Skip("skipping Darwin-specific unit test on non-Darwin host")
	}

	url := getPlatformOfficialDockerURL()
	if !strings.HasPrefix(url, "https://desktop.docker.com/mac/main/") || !strings.HasSuffix(url, "/Docker.dmg") {
		t.Errorf("unexpected macOS Docker URL: %s", url)
	}
}

// 48. Test Docker Resolution with GUI-like restricted PATH (Finder launch)
func TestDockerResolution_GUILikePath_UsesResolvedCLIForInstallAndVolumes(t *testing.T) {
	if runtime.GOOS != "darwin" {
		t.Skip("skipping Darwin-specific GUI launch path resolution test on non-Darwin host")
	}
	testDir := setupTestDir(t)
	mockExec := NewMockExecutor()

	resolvedDocker := "/opt/homebrew/bin/docker"

	mockExec.Handlers["info"] = func(args []string) (string, string, int, error) {
		return "Server Version: 27.1.1", "", 0, nil
	}
	mockExec.Handlers["compose version"] = func(args []string) (string, string, int, error) {
		return "Docker Compose version v2.29.1", "", 0, nil
	}
	mockExec.Handlers["volume create altr_stream_data"] = func(args []string) (string, string, int, error) {
		return "altr_stream_data\n", "", 0, nil
	}
	mockExec.Handlers["pull"] = func(args []string) (string, string, int, error) {
		return "Status: Downloaded newer image for ghcr.io/helloaltr/altr-stream:0.13.7-alpha", "", 0, nil
	}
	containerStarted := false
	mockExec.Handlers["up -d"] = func(args []string) (string, string, int, error) {
		containerStarted = true
		return "Container altr-stream Started", "", 0, nil
	}
	mockExec.Handlers["inspect altr-stream"] = func(args []string) (string, string, int, error) {
		if !containerStarted {
			return "", "Error: No such container: altr-stream", 1, errors.New("exit status 1")
		}
		inspectJSON := `[{
			"Id": "abc123456789",
			"State": {"Status": "running", "Running": true, "ExitCode": 0, "Error": ""},
			"Config": {"Image": "ghcr.io/helloaltr/altr-stream:0.13.7-alpha"},
			"NetworkSettings": {"Ports": {"8000/tcp": [{"HostIp": "0.0.0.0", "HostPort": "8000"}]}}
		}]`
		return inspectJSON, "", 0, nil
	}

	mockHTTP := &MockHTTPClient{
		DoFunc: func(req *http.Request) (*http.Response, error) {
			return &http.Response{
				StatusCode: 200,
				Body:       io.NopCloser(bytes.NewBufferString(`{"status":"healthy","version":"0.13.7-alpha"}`)),
			}, nil
		},
	}

	engine := NewInstallerEngine(mockExec, mockHTTP)

	// Simulate GUI launch environment where "docker" is NOT in PATH
	engine.dockerManager.lookPath = func(file string) (string, error) {
		return "", os.ErrNotExist
	}
	// But candidate exists on disk
	engine.dockerManager.stat = func(name string) (os.FileInfo, error) {
		if name == resolvedDocker {
			return &fakeFileInfo{isDir: false}, nil
		}
		return nil, os.ErrNotExist
	}

	ctx := context.Background()

	// 1. CheckDocker should resolve the candidate
	diag, err := engine.CheckDocker(ctx)
	if err != nil {
		t.Fatalf("CheckDocker failed: %v", err)
	}
	if diag.State != DockerStateReady {
		t.Fatalf("expected state ready, got: %s", diag.State)
	}
	if engine.dockerManager.ResolveDockerCLI() != resolvedDocker {
		t.Fatalf("expected ResolveDockerCLI %q, got %q", resolvedDocker, engine.dockerManager.ResolveDockerCLI())
	}
	if diag.ComposeCommand != resolvedDocker+" compose" {
		t.Fatalf("expected ComposeCommand %q, got %q", resolvedDocker+" compose", diag.ComposeCommand)
	}

	cfg := InstallConfig{
		TargetDir:     testDir,
		Version:       "0.13.7-alpha",
		Image:         "ghcr.io/helloaltr/altr-stream:0.13.7-alpha",
		Port:          8000,
		HealthTimeout: 5,
	}

	// 2. Install must succeed without bare "docker" in PATH
	err = engine.Install(ctx, cfg, nil)
	if err != nil {
		t.Fatalf("Install failed: %v", err)
	}

	// 3. Inspect mockExec.CallLog to verify NO bare "docker" execution occurred and resolvedDocker was used
	foundResolvedCall := false
	for _, call := range mockExec.CallLog {
		if strings.HasPrefix(call, "docker ") {
			t.Errorf("found forbidden bare 'docker' call in GUI mode: %s", call)
		}
		if strings.HasPrefix(call, resolvedDocker) {
			foundResolvedCall = true
		}
	}
	if !foundResolvedCall {
		t.Errorf("expected resolved docker CLI call starting with %q, but calls were: %v",
			resolvedDocker, mockExec.CallLog)
	}
}

// 49. Test DetectEnvironment rejects temporary and pytest paths
func TestDetectEnvironment_RejectsTemporaryDirectories(t *testing.T) {
	testDir := setupTestDir(t)
	cfgFile := filepath.Join(testDir, ".altr-stream-config")

	// Create fake pytest directory with docker-compose.yml
	pytestDir := filepath.Join(testDir, "pytest-255", "test_go_engine_progress_file", "inst_target")
	if err := os.MkdirAll(pytestDir, 0755); err != nil {
		t.Fatalf("failed to create pytestDir: %v", err)
	}
	if err := os.WriteFile(filepath.Join(pytestDir, "docker-compose.yml"), []byte("version: '3'"), 0644); err != nil {
		t.Fatalf("failed to write dummy compose: %v", err)
	}

	// Write temp path into config file
	if err := os.WriteFile(cfgFile, []byte(pytestDir), 0644); err != nil {
		t.Fatalf("failed to write config file: %v", err)
	}

	t.Setenv("ALTR_STREAM_CONFIG_FILE", cfgFile)
	t.Setenv("ALTR_STREAM_HOME", "")

	mockExec := NewMockExecutor()
	engine := NewInstallerEngine(mockExec, &MockHTTPClient{})

	env, err := engine.DetectEnvironment()
	if err != nil {
		t.Fatalf("DetectEnvironment failed: %v", err)
	}

	if env.SavedDir != "" {
		t.Errorf("expected SavedDir to be empty for temporary directory, got: %s", env.SavedDir)
	}
	if strings.Contains(env.EffectiveDir, "pytest") || strings.Contains(env.EffectiveDir, "inst_target") {
		t.Errorf("EffectiveDir leaked temporary test path: %s", env.EffectiveDir)
	}
	if env.EffectiveDir != env.DefaultDir {
		t.Errorf("expected EffectiveDir to fall back to DefaultDir %q, got %q", env.DefaultDir, env.EffectiveDir)
	}
}

// 50. Test DetectEnvironment explicit override via ALTR_STREAM_HOME
func TestDetectEnvironment_ExplicitOverride(t *testing.T) {
	t.Setenv("ALTR_STREAM_HOME", "/custom/configured/altr-stream")

	mockExec := NewMockExecutor()
	engine := NewInstallerEngine(mockExec, &MockHTTPClient{})

	env, err := engine.DetectEnvironment()
	if err != nil {
		t.Fatalf("DetectEnvironment failed: %v", err)
	}

	if env.EffectiveDir != "/custom/configured/altr-stream" {
		t.Errorf("expected EffectiveDir='/custom/configured/altr-stream', got: %s", env.EffectiveDir)
	}
}

// 51. Test CheckContainerConflict distinguishes compatible Altr Stream from third-party containers
func TestCheckContainerConflict_DistinguishesIdentity(t *testing.T) {
	mockExec := NewMockExecutor()
	engine := NewInstallerEngine(mockExec, &MockHTTPClient{})
	ctx := context.Background()

	// Case 1: Compatible Altr Stream container
	mockExec.Handlers["inspect altr-stream"] = func(args []string) (string, string, int, error) {
		return `[{
			"Id": "abc1234567890123",
			"Created": "2026-10-01T12:00:00Z",
			"State": {"Status": "running", "Running": true, "Health": {"Status": "healthy"}},
			"Config": {"Image": "ghcr.io/helloaltr/altr-stream:0.13.7-alpha"},
			"NetworkSettings": {"Ports": {"8000/tcp": [{"HostIp": "0.0.0.0", "HostPort": "8000"}]}}
		}]`, "", 0, nil
	}

	conflict, err := engine.CheckContainerConflict(ctx)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !conflict.Exists || !conflict.IsAltrStream || !conflict.IsCompatible {
		t.Errorf("expected exists=true, isAltr=true, isCompat=true; got: exists=%v, isAltr=%v, isCompat=%v",
			conflict.Exists, conflict.IsAltrStream, conflict.IsCompatible)
	}
	if conflict.PortMapping != "8000:8000" {
		t.Errorf("expected PortMapping='8000:8000', got: %s", conflict.PortMapping)
	}
	if conflict.HealthStatus != "healthy" {
		t.Errorf("expected HealthStatus='healthy', got: %s", conflict.HealthStatus)
	}

	// Case 2: Third-party container with name altr-stream (e.g. nginx)
	mockExec.Handlers["inspect altr-stream"] = func(args []string) (string, string, int, error) {
		return `[{
			"Id": "def9876543210987",
			"Created": "2026-09-15T08:00:00Z",
			"State": {"Status": "running", "Running": true},
			"Config": {"Image": "nginx:alpine"},
			"NetworkSettings": {"Ports": {"80/tcp": [{"HostIp": "0.0.0.0", "HostPort": "80"}]}}
		}]`, "", 0, nil
	}

	conflict, err = engine.CheckContainerConflict(ctx)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !conflict.Exists {
		t.Fatalf("expected conflict.Exists=true")
	}
	if conflict.IsAltrStream {
		t.Errorf("expected isAltr=false for nginx:alpine, got true")
	}
	if conflict.IsCompatible {
		t.Errorf("expected isCompat=false for nginx:alpine, got true")
	}
}

// 52. Test RemoveContainer removes ONLY the container and preserves data volumes
func TestRemoveContainer_PreservesDataVolumes(t *testing.T) {
	mockExec := NewMockExecutor()
	engine := NewInstallerEngine(mockExec, &MockHTTPClient{})
	ctx := context.Background()

	var rmContainerCalled bool
	var rmVolumeCalled bool

	mockExec.Handlers["rm -f altr-stream"] = func(args []string) (string, string, int, error) {
		rmContainerCalled = true
		return "altr-stream\n", "", 0, nil
	}
	mockExec.Handlers["volume rm"] = func(args []string) (string, string, int, error) {
		rmVolumeCalled = true
		return "", "", 0, nil
	}

	err := engine.RemoveExistingContainer(ctx)
	if err != nil {
		t.Fatalf("RemoveExistingContainer failed: %v", err)
	}
	if !rmContainerCalled {
		t.Errorf("expected 'docker rm -f altr-stream' to be executed")
	}
	if rmVolumeCalled {
		t.Errorf("CRITICAL: volume was removed! Volume must be preserved.")
	}
}

// 53. Test StartExistingContainer dispatches docker start
func TestStartExistingContainer(t *testing.T) {
	mockExec := NewMockExecutor()
	engine := NewInstallerEngine(mockExec, &MockHTTPClient{})
	ctx := context.Background()

	var startCalled bool
	mockExec.Handlers["start altr-stream"] = func(args []string) (string, string, int, error) {
		startCalled = true
		return "altr-stream\n", "", 0, nil
	}

	err := engine.StartExistingContainer(ctx)
	if err != nil {
		t.Fatalf("StartExistingContainer failed: %v", err)
	}
	if !startCalled {
		t.Errorf("expected 'docker start altr-stream' to be called")
	}
}

// 54. Test Install with ReplaceExisting=true removes conflicting container before startup
func TestInstall_WithReplaceExisting(t *testing.T) {
	testDir := setupTestDir(t)
	mockExec := NewMockExecutor()

	var containerRemoved bool
	mockExec.Handlers["info"] = func(args []string) (string, string, int, error) {
		return "Server Version: 27.1.1", "", 0, nil
	}
	mockExec.Handlers["compose version"] = func(args []string) (string, string, int, error) {
		return "Docker Compose version v2.29.1", "", 0, nil
	}
	mockExec.Handlers["rm -f altr-stream"] = func(args []string) (string, string, int, error) {
		containerRemoved = true
		return "altr-stream\n", "", 0, nil
	}
	mockExec.Handlers["volume create altr_stream_data"] = func(args []string) (string, string, int, error) {
		return "altr_stream_data\n", "", 0, nil
	}
	mockExec.Handlers["pull"] = func(args []string) (string, string, int, error) {
		return "Status: Downloaded", "", 0, nil
	}
	mockExec.Handlers["up -d"] = func(args []string) (string, string, int, error) {
		return "Container altr-stream Started", "", 0, nil
	}
	mockExec.Handlers["inspect altr-stream"] = func(args []string) (string, string, int, error) {
		return `[{
			"Id": "abc123456789",
			"State": {"Status": "running", "Running": true, "ExitCode": 0, "Error": ""},
			"Config": {"Image": "ghcr.io/helloaltr/altr-stream:0.13.7-alpha"},
			"NetworkSettings": {"Ports": {"8000/tcp": [{"HostIp": "0.0.0.0", "HostPort": "8000"}]}}
		}]`, "", 0, nil
	}

	mockHTTP := &MockHTTPClient{
		DoFunc: func(req *http.Request) (*http.Response, error) {
			return &http.Response{
				StatusCode: 200,
				Body:       io.NopCloser(bytes.NewBufferString(`{"status":"healthy","version":"0.13.7-alpha"}`)),
			}, nil
		},
	}

	engine := NewInstallerEngine(mockExec, mockHTTP)
	ctx := context.Background()

	cfg := InstallConfig{
		TargetDir:       testDir,
		Version:         "0.13.7-alpha",
		Image:           "ghcr.io/helloaltr/altr-stream:0.13.7-alpha",
		Port:            8000,
		HealthTimeout:   5,
		ReplaceExisting: true,
	}

	err := engine.Install(ctx, cfg, nil)
	if err != nil {
		t.Fatalf("Install failed: %v", err)
	}
	if !containerRemoved {
		t.Errorf("expected container 'altr-stream' to be removed before startup when ReplaceExisting=true")
	}
}

// 55. Test CheckPortConflict identifies Docker development container occupying port 8000
func TestCheckPortConflict_DockerDevContainer(t *testing.T) {
	mockExec := NewMockExecutor()
	mockExec.Handlers["ps --filter publish=8000"] = func(args []string) (string, string, int, error) {
		return `{"ID":"c1d2e3f4a5b6","Names":"altr-stream-dev","Image":"altr-stream-backend:latest","Status":"Up 2 hours","Ports":"0.0.0.0:8000->8000/tcp"}` + "\n", "", 0, nil
	}
	mockExec.Handlers["inspect c1d2e3f4a5b6"] = func(args []string) (string, string, int, error) {
		inspectJSON := `[{
			"Id": "c1d2e3f4a5b67890abcdef",
			"Name": "/altr-stream-dev",
			"State": {"Status": "running", "Running": true},
			"Config": {
				"Image": "altr-stream-backend:latest",
				"Labels": {
					"com.docker.compose.project": "01-altrstream",
					"com.docker.compose.service": "backend",
					"com.docker.compose.project.working_dir": "/Users/developer/project"
				}
			},
			"NetworkSettings": {
				"Ports": {"8000/tcp": [{"HostIp": "0.0.0.0", "HostPort": "8000"}]}
			}
		}]`
		return inspectJSON, "", 0, nil
	}

	engine := NewInstallerEngine(mockExec, &MockHTTPClient{})
	ctx := context.Background()

	conflict, err := engine.lifecycleManager.CheckPortConflict(ctx, 8000)
	if err != nil {
		t.Fatalf("CheckPortConflict failed: %v", err)
	}

	if conflict.ConflictType != ConflictTypePortDocker {
		t.Errorf("expected ConflictTypePortDocker, got %s", conflict.ConflictType)
	}
	if !conflict.Exists {
		t.Errorf("expected conflict.Exists=true")
	}
	if conflict.ContainerName != "altr-stream-dev" {
		t.Errorf("expected container name 'altr-stream-dev', got %s", conflict.ContainerName)
	}
	if !conflict.IsDevContainer {
		t.Errorf("expected IsDevContainer=true")
	}
	if conflict.IsInstallerOwned {
		t.Errorf("expected IsInstallerOwned=false")
	}
	if !strings.Contains(conflict.RemediationHint, "development container") {
		t.Errorf("expected remediation hint to mention development container, got: %s", conflict.RemediationHint)
	}
}

// 56. Test CheckPortConflict identifies host process when Docker has no publishing container
func TestCheckPortConflict_HostProcess(t *testing.T) {
	mockExec := NewMockExecutor()
	mockExec.Handlers["ps --filter publish=8000"] = func(args []string) (string, string, int, error) {
		return "", "", 0, nil
	}

	engine := NewInstallerEngine(mockExec, &MockHTTPClient{})
	engine.SetHostPortChecker(func(port int) error {
		return fmt.Errorf("bind: address already in use")
	})
	ctx := context.Background()

	conflict, err := engine.lifecycleManager.CheckPortConflict(ctx, 8000)
	if err != nil {
		t.Fatalf("CheckPortConflict failed: %v", err)
	}

	if conflict.ConflictType != ConflictTypePortProcess {
		t.Errorf("expected ConflictTypePortProcess, got %s", conflict.ConflictType)
	}
	if !conflict.Exists {
		t.Errorf("expected conflict.Exists=true")
	}
	if !strings.Contains(conflict.OccupiedBy, "host process") {
		t.Errorf("expected occupied_by to mention host process, got: %s", conflict.OccupiedBy)
	}
}

// 57. Test Install is blocked by Docker port conflict before creating or removing any container
func TestInstall_BlockedByDockerPortConflict_NeverCreatesOrRemoves(t *testing.T) {
	testDir := setupTestDir(t)
	mockExec := NewMockExecutor()

	mockExec.Handlers["info"] = func(args []string) (string, string, int, error) {
		return "Server Version: 27.1.1", "", 0, nil
	}
	mockExec.Handlers["compose version"] = func(args []string) (string, string, int, error) {
		return "Docker Compose version v2.29.1", "", 0, nil
	}
	// Target container does not exist
	mockExec.Handlers["inspect altr-stream"] = func(args []string) (string, string, int, error) {
		return "", "Error: No such container: altr-stream", 1, errors.New("not found")
	}
	// Port 8000 occupied by altr-stream-dev
	mockExec.Handlers["ps --filter publish=8000"] = func(args []string) (string, string, int, error) {
		return `{"ID":"dev123456789","Names":"altr-stream-dev","Image":"altr-stream-backend:dev","Status":"Up 1 hour","Ports":"0.0.0.0:8000->8000/tcp"}` + "\n", "", 0, nil
	}
	mockExec.Handlers["inspect dev123456789"] = func(args []string) (string, string, int, error) {
		return `[{
			"Id": "dev123456789abcdef",
			"Name": "/altr-stream-dev",
			"State": {"Status": "running", "Running": true},
			"Config": {"Image": "altr-stream-backend:dev", "Labels": {"environment": "development"}},
			"NetworkSettings": {"Ports": {"8000/tcp": [{"HostIp": "0.0.0.0", "HostPort": "8000"}]}}
		}]`, "", 0, nil
	}

	var rmCalled, upCalled, volCalled bool
	mockExec.Handlers["rm -f altr-stream"] = func(args []string) (string, string, int, error) {
		rmCalled = true
		return "", "", 0, nil
	}
	mockExec.Handlers["rm -f dev123456789"] = func(args []string) (string, string, int, error) {
		rmCalled = true
		return "", "", 0, nil
	}
	mockExec.Handlers["volume create altr_stream_data"] = func(args []string) (string, string, int, error) {
		volCalled = true
		return "altr_stream_data\n", "", 0, nil
	}
	mockExec.Handlers["up -d"] = func(args []string) (string, string, int, error) {
		upCalled = true
		return "", "", 0, nil
	}

	engine := NewInstallerEngine(mockExec, &MockHTTPClient{})
	ctx := context.Background()

	cfg := InstallConfig{
		TargetDir:       testDir,
		Version:         "0.13.7-alpha",
		Image:           "ghcr.io/helloaltr/altr-stream:0.13.7-alpha",
		Port:            8000,
		HealthTimeout:   5,
		ReplaceExisting: false,
	}

	err := engine.Install(ctx, cfg, nil)
	if err == nil {
		t.Fatal("expected Install to fail due to port conflict, but it succeeded")
	}

	if !strings.Contains(err.Error(), "Port 8000 is already in use") {
		t.Errorf("expected error to mention port 8000 in use, got: %v", err)
	}
	if !strings.Contains(err.Error(), "altr-stream-dev") {
		t.Errorf("expected error to name conflicting container 'altr-stream-dev', got: %v", err)
	}

	// Verify no destructive or creation actions took place
	if rmCalled {
		t.Errorf("rm was called: conflicting container must NOT be removed!")
	}
	if volCalled {
		t.Errorf("volume create was called: pre-flight should have aborted before Stage 1!")
	}
	if upCalled {
		t.Errorf("up -d was called: pre-flight should have aborted before container creation!")
	}
}

// 58. Test Install is blocked by host process port conflict before creating container
func TestInstall_BlockedByHostProcessPortConflict_NeverCreates(t *testing.T) {
	testDir := setupTestDir(t)
	mockExec := NewMockExecutor()

	mockExec.Handlers["info"] = func(args []string) (string, string, int, error) {
		return "Server Version: 27.1.1", "", 0, nil
	}
	mockExec.Handlers["compose version"] = func(args []string) (string, string, int, error) {
		return "Docker Compose version v2.29.1", "", 0, nil
	}
	mockExec.Handlers["inspect altr-stream"] = func(args []string) (string, string, int, error) {
		return "", "Error: No such container: altr-stream", 1, errors.New("not found")
	}
	mockExec.Handlers["ps -a -q --filter publish=8000"] = func(args []string) (string, string, int, error) {
		return "", "", 0, nil
	}

	var upCalled bool
	mockExec.Handlers["up -d"] = func(args []string) (string, string, int, error) {
		upCalled = true
		return "", "", 0, nil
	}

	engine := NewInstallerEngine(mockExec, &MockHTTPClient{})
	engine.SetHostPortChecker(func(port int) error {
		return fmt.Errorf("listen tcp :8000: bind: address already in use")
	})

	ctx := context.Background()
	cfg := InstallConfig{
		TargetDir:       testDir,
		Version:         "0.13.7-alpha",
		Image:           "ghcr.io/helloaltr/altr-stream:0.13.7-alpha",
		Port:            8000,
		HealthTimeout:   5,
		ReplaceExisting: false,
	}

	err := engine.Install(ctx, cfg, nil)
	if err == nil {
		t.Fatal("expected Install to fail due to host port conflict, but it succeeded")
	}

	if !strings.Contains(err.Error(), "Port 8000 is already in use") {
		t.Errorf("expected error to mention port 8000, got: %v", err)
	}
	if upCalled {
		t.Errorf("up -d was called despite host port conflict!")
	}
}

// 59. Test Install is blocked when target container already exists and ReplaceExisting=false
func TestInstall_BlockedByExistingTargetContainer_WhenReplaceFalse(t *testing.T) {
	testDir := setupTestDir(t)
	mockExec := NewMockExecutor()

	mockExec.Handlers["info"] = func(args []string) (string, string, int, error) {
		return "Server Version: 27.1.1", "", 0, nil
	}
	mockExec.Handlers["compose version"] = func(args []string) (string, string, int, error) {
		return "Docker Compose version v2.29.1", "", 0, nil
	}
	// Target container exists
	mockExec.Handlers["inspect altr-stream"] = func(args []string) (string, string, int, error) {
		return `[{
			"Id": "abc123456789",
			"State": {"Status": "running", "Running": true},
			"Config": {"Image": "ghcr.io/helloaltr/altr-stream:0.13.6-alpha"}
		}]`, "", 0, nil
	}

	var upCalled bool
	mockExec.Handlers["up -d"] = func(args []string) (string, string, int, error) {
		upCalled = true
		return "", "", 0, nil
	}

	engine := NewInstallerEngine(mockExec, &MockHTTPClient{})
	ctx := context.Background()

	cfg := InstallConfig{
		TargetDir:       testDir,
		Version:         "0.13.7-alpha",
		Image:           "ghcr.io/helloaltr/altr-stream:0.13.7-alpha",
		Port:            8000,
		HealthTimeout:   5,
		ReplaceExisting: false,
	}

	err := engine.Install(ctx, cfg, nil)
	if err == nil {
		t.Fatal("expected Install to fail due to existing container conflict, but it succeeded")
	}

	if !strings.Contains(err.Error(), "already exists") {
		t.Errorf("expected error to mention container already exists, got: %v", err)
	}
	if upCalled {
		t.Errorf("up -d was called despite target container conflict!")
	}
}

// 60. Test VerifyHealth cannot falsely succeed if target container lacks port mapping,
// even if another service is listening on localhost:8000 and returning 200 OK.
func TestVerifyHealth_CannotFalselySucceedFromAnotherService_WhenNoMapping(t *testing.T) {
	mockExec := NewMockExecutor()

	// Container is running, but has NO port mappings (e.g. Docker silently dropped mapping due to conflict)
	mockExec.Handlers["inspect altr-stream"] = func(args []string) (string, string, int, error) {
		return `[{
			"Id": "target123456",
			"State": {"Status": "running", "Running": true, "ExitCode": 0},
			"Config": {"Image": "ghcr.io/helloaltr/altr-stream:0.13.7-alpha"},
			"NetworkSettings": {
				"Ports": {
					"8000/tcp": null
				}
			}
		}]`, "", 0, nil
	}

	// Another service (e.g., altr-stream-dev) is listening on localhost:8000 and answers 200 OK
	mockHTTP := &MockHTTPClient{
		DoFunc: func(req *http.Request) (*http.Response, error) {
			return &http.Response{
				StatusCode: 200,
				Body:       io.NopCloser(bytes.NewBufferString(`{"status":"healthy","version":"0.13.7-alpha"}`)),
			}, nil
		},
	}

	engine := NewInstallerEngine(mockExec, mockHTTP)
	ctx := context.Background()

	// VerifyHealth MUST fail because the target container does NOT have host port 8000 mapped
	_, err := engine.lifecycleManager.VerifyHealth(ctx, 8000, "0.13.7-alpha", 2*time.Second)
	if err == nil {
		t.Fatal("expected VerifyHealth to fail because target container lacks port mapping, but it falsely succeeded!")
	}

	if !strings.Contains(err.Error(), "port 8000/tcp is not mapped") {
		t.Errorf("expected error to mention port mapping missing, got: %v", err)
	}
}

// 61. Test Uninstall: Running Installer-Managed Container
// Verifies that a RUNNING installer-managed container is gracefully stopped,
// removed, runtime files cleaned up, and volume preserved when deleteData=false.
func TestUninstall_RunningInstallerManagedContainer(t *testing.T) {
	testDir := setupTestDir(t)
	composeFile := filepath.Join(testDir, "docker-compose.yml")
	envFile := filepath.Join(testDir, ".env")
	logFile := filepath.Join(testDir, ".docker_start.log")
	_ = os.WriteFile(composeFile, []byte("services: {}"), 0644)
	_ = os.WriteFile(envFile, []byte("PORT=8000"), 0644)
	_ = os.WriteFile(logFile, []byte("started"), 0644)

	mockExec := NewMockExecutor()
	mockExec.Handlers["info"] = func(args []string) (string, string, int, error) {
		return "Server Version: 27.1.1", "", 0, nil
	}
	mockExec.Handlers["inspect altr-stream"] = func(args []string) (string, string, int, error) {
		return `[{
			"Id": "abc123456789",
			"State": {"Status": "running", "Running": true},
			"Config": {
				"Image": "ghcr.io/helloaltr/altr-stream:0.13.7-alpha",
				"Labels": {"com.helloaltr.altr-stream.managed-by": "installer"}
			},
			"NetworkSettings": {"Ports": {"8000/tcp": [{"HostPort": "8000"}]}}
		}]`, "", 0, nil
	}
	mockExec.Handlers["down"] = func(args []string) (string, string, int, error) {
		return "Container stopped and removed", "", 0, nil
	}
	mockExec.Handlers["stop"] = func(args []string) (string, string, int, error) {
		return "altr-stream", "", 0, nil
	}
	mockExec.Handlers["inspect -f {{.State.Running}} altr-stream"] = func(args []string) (string, string, int, error) {
		return "false\n", "", 0, nil
	}
	mockExec.Handlers["rm -f altr-stream"] = func(args []string) (string, string, int, error) {
		return "altr-stream", "", 0, nil
	}
	mockExec.Handlers["inspect -f {{.State.Status}} altr-stream"] = func(args []string) (string, string, int, error) {
		return "", "Error: No such container: altr-stream", 1, nil
	}

	engine := NewInstallerEngine(mockExec, &MockHTTPClient{})
	ctx := context.Background()

	err := engine.Uninstall(ctx, testDir, false)
	if err != nil {
		t.Fatalf("Uninstall failed on running container: %v", err)
	}

	// Verify stop and rm were called
	rmCalled := false
	for _, call := range mockExec.CallLog {
		if strings.Contains(call, "rm -f altr-stream") || strings.Contains(call, "down") {
			rmCalled = true
		}
		if strings.Contains(call, "volume rm") {
			t.Errorf("CRITICAL: volume rm must NOT be called when deleteData=false: %s", call)
		}
	}
	if !rmCalled {
		t.Errorf("expected container removal to be called")
	}

	// Verify runtime files were cleaned up
	if _, err := os.Stat(composeFile); !os.IsNotExist(err) {
		t.Errorf("expected docker-compose.yml to be removed")
	}
	if _, err := os.Stat(envFile); !os.IsNotExist(err) {
		t.Errorf("expected .env to be removed")
	}
	if _, err := os.Stat(logFile); !os.IsNotExist(err) {
		t.Errorf("expected .docker_start.log to be removed")
	}

	// Install dir itself should still exist when deleteData=false
	if _, err := os.Stat(testDir); os.IsNotExist(err) {
		t.Errorf("install directory should be preserved when deleteData=false")
	}
}

// 62. Test Uninstall: Stopped Installer-Managed Container
// Verifies that an already stopped/exited container is cleanly removed without error.
func TestUninstall_StoppedInstallerManagedContainer(t *testing.T) {
	testDir := setupTestDir(t)
	mockExec := NewMockExecutor()
	mockExec.Handlers["info"] = func(args []string) (string, string, int, error) {
		return "Server Version: 27.1.1", "", 0, nil
	}
	mockExec.Handlers["inspect altr-stream"] = func(args []string) (string, string, int, error) {
		return `[{
			"Id": "abc123456789",
			"State": {"Status": "exited", "Running": false, "ExitCode": 0},
			"Config": {
				"Image": "ghcr.io/helloaltr/altr-stream:0.13.7-alpha",
				"Labels": {"com.helloaltr.altr-stream.managed-by": "installer"}
			}
		}]`, "", 0, nil
	}
	mockExec.Handlers["rm -f altr-stream"] = func(args []string) (string, string, int, error) {
		return "altr-stream", "", 0, nil
	}
	mockExec.Handlers["inspect -f {{.State.Status}} altr-stream"] = func(args []string) (string, string, int, error) {
		return "", "Error: No such container: altr-stream", 1, nil
	}

	engine := NewInstallerEngine(mockExec, &MockHTTPClient{})
	ctx := context.Background()

	err := engine.Uninstall(ctx, testDir, false)
	if err != nil {
		t.Fatalf("Uninstall failed on stopped container: %v", err)
	}

	// Should NOT call stop or kill since it is already stopped
	for _, call := range mockExec.CallLog {
		if strings.Contains(call, "stop -t") || strings.Contains(call, "kill altr-stream") {
			t.Errorf("should not call stop or kill on already stopped container: %s", call)
		}
	}
}

// 63. Test Uninstall: Absent Container
// Verifies idempotency when altr-stream does not exist at all.
func TestUninstall_AbsentContainer(t *testing.T) {
	testDir := setupTestDir(t)
	mockExec := NewMockExecutor()
	mockExec.Handlers["info"] = func(args []string) (string, string, int, error) {
		return "Server Version: 27.1.1", "", 0, nil
	}
	mockExec.Handlers["inspect altr-stream"] = func(args []string) (string, string, int, error) {
		return "", "Error: No such container: altr-stream", 1, nil
	}

	engine := NewInstallerEngine(mockExec, &MockHTTPClient{})
	ctx := context.Background()

	err := engine.Uninstall(ctx, testDir, false)
	if err != nil {
		t.Fatalf("Uninstall should succeed idempotently when container is absent, but got: %v", err)
	}
}

// 64. Test Uninstall: Stop Failure Fallback
// Verifies that if compose down / graceful stop fails, fallback kill and rm -f is executed.
func TestUninstall_StopFailureFallback(t *testing.T) {
	testDir := setupTestDir(t)
	mockExec := NewMockExecutor()
	mockExec.Handlers["info"] = func(args []string) (string, string, int, error) {
		return "Server Version: 27.1.1", "", 0, nil
	}
	mockExec.Handlers["inspect altr-stream"] = func(args []string) (string, string, int, error) {
		return `[{
			"Id": "abc123456789",
			"State": {"Status": "running", "Running": true},
			"Config": {"Image": "ghcr.io/helloaltr/altr-stream:0.13.7-alpha"}
		}]`, "", 0, nil
	}
	// docker stop fails
	mockExec.Handlers["stop -t 10 altr-stream"] = func(args []string) (string, string, int, error) {
		return "", "error stopping container", 1, errors.New("exit status 1")
	}
	// docker kill succeeds
	killCalled := false
	mockExec.Handlers["kill altr-stream"] = func(args []string) (string, string, int, error) {
		killCalled = true
		return "altr-stream", "", 0, nil
	}
	mockExec.Handlers["inspect -f {{.State.Running}} altr-stream"] = func(args []string) (string, string, int, error) {
		return "false\n", "", 0, nil
	}
	mockExec.Handlers["rm -f altr-stream"] = func(args []string) (string, string, int, error) {
		return "altr-stream", "", 0, nil
	}
	mockExec.Handlers["inspect -f {{.State.Status}} altr-stream"] = func(args []string) (string, string, int, error) {
		return "", "Error: No such container", 1, nil
	}

	engine := NewInstallerEngine(mockExec, &MockHTTPClient{})
	ctx := context.Background()

	err := engine.Uninstall(ctx, testDir, false)
	if err != nil {
		t.Fatalf("Uninstall failed despite kill fallback: %v", err)
	}
	if !killCalled {
		t.Errorf("expected kill altr-stream fallback to be called")
	}
}

// 65. Test Uninstall: Remove Failure Returns Error
func TestUninstall_RemoveFailure(t *testing.T) {
	testDir := setupTestDir(t)
	mockExec := NewMockExecutor()
	mockExec.Handlers["info"] = func(args []string) (string, string, int, error) {
		return "Server Version: 27.1.1", "", 0, nil
	}
	mockExec.Handlers["inspect altr-stream"] = func(args []string) (string, string, int, error) {
		return `[{
			"Id": "abc123456789",
			"State": {"Status": "exited", "Running": false},
			"Config": {"Image": "ghcr.io/helloaltr/altr-stream:0.13.7-alpha"}
		}]`, "", 0, nil
	}
	mockExec.Handlers["rm -f altr-stream"] = func(args []string) (string, string, int, error) {
		return "", "device or resource busy", 1, errors.New("exit status 1")
	}

	engine := NewInstallerEngine(mockExec, &MockHTTPClient{})
	ctx := context.Background()

	err := engine.Uninstall(ctx, testDir, false)
	if err == nil {
		t.Fatalf("expected Uninstall to return error on rm failure, but it succeeded")
	}
	if !strings.Contains(err.Error(), "failed to remove container") {
		t.Errorf("expected error message about container removal failure, got: %v", err)
	}
}

// 66. Test Uninstall: Dev Container Is Never Stopped Or Removed
func TestUninstall_NeverTouchesDevContainer(t *testing.T) {
	testDir := setupTestDir(t)
	mockExec := NewMockExecutor()
	mockExec.Handlers["info"] = func(args []string) (string, string, int, error) {
		return "Server Version: 27.1.1", "", 0, nil
	}
	// Target container altr-stream happens to have dev container labels
	mockExec.Handlers["inspect altr-stream"] = func(args []string) (string, string, int, error) {
		return `[{
			"Id": "dev123456789",
			"State": {"Status": "running", "Running": true},
			"Config": {
				"Image": "ghcr.io/helloaltr/altr-stream:dev",
				"Labels": {"com.docker.compose.project": "altr-stream-dev"}
			}
		}]`, "", 0, nil
	}

	engine := NewInstallerEngine(mockExec, &MockHTTPClient{})
	ctx := context.Background()

	err := engine.Uninstall(ctx, testDir, false)
	if err == nil {
		t.Fatalf("expected Uninstall to abort when container is dev container, but it succeeded")
	}
	if !strings.Contains(err.Error(), "development environment") {
		t.Errorf("expected error to mention development environment, got: %v", err)
	}

	// Verify no stop or rm calls were made
	for _, call := range mockExec.CallLog {
		if strings.Contains(call, "stop") || strings.Contains(call, "kill") || strings.Contains(call, "rm") {
			t.Errorf("CRITICAL VIOLATION: dev container must NEVER be stopped or removed! Call was: %s", call)
		}
	}
}

// 67. Test Uninstall: Unrelated / Dev Container 'altr-stream-dev' Is Never Affected
func TestUninstall_NeverTouchesUnrelatedOrDevContainer(t *testing.T) {
	testDir := setupTestDir(t)
	mockExec := NewMockExecutor()
	mockExec.Handlers["info"] = func(args []string) (string, string, int, error) {
		return "Server Version: 27.1.1", "", 0, nil
	}
	// altr-stream is stopped
	mockExec.Handlers["inspect altr-stream"] = func(args []string) (string, string, int, error) {
		return `[{
			"Id": "target123",
			"State": {"Status": "exited", "Running": false},
			"Config": {"Image": "ghcr.io/helloaltr/altr-stream:0.13.7-alpha"}
		}]`, "", 0, nil
	}
	mockExec.Handlers["rm -f altr-stream"] = func(args []string) (string, string, int, error) {
		return "altr-stream", "", 0, nil
	}
	mockExec.Handlers["inspect -f {{.State.Status}} altr-stream"] = func(args []string) (string, string, int, error) {
		return "", "Error: No such container", 1, nil
	}

	engine := NewInstallerEngine(mockExec, &MockHTTPClient{})
	ctx := context.Background()

	err := engine.Uninstall(ctx, testDir, false)
	if err != nil {
		t.Fatalf("uninstall failed: %v", err)
	}

	for _, call := range mockExec.CallLog {
		if strings.Contains(call, "altr-stream-dev") {
			t.Fatalf("CRITICAL VIOLATION: call referenced altr-stream-dev! Call: %s", call)
		}
	}
}

// 68. Test GetStatus: Docker state 'paused' is preserved and strictly distinguished from 'stopped'/'exited'.
func TestGetStatus_DockerStatePaused_DistinguishedFromStopped(t *testing.T) {
	testDir := setupTestDir(t)
	mockExec := NewMockExecutor()
	mockExec.Handlers["info"] = func(args []string) (string, string, int, error) {
		return "Server Version: 27.1.1", "", 0, nil
	}
	mockExec.Handlers["inspect altr-stream"] = func(args []string) (string, string, int, error) {
		return `[{
			"Id": "abc123456789",
			"State": {
				"Status": "paused",
				"Running": true,
				"Paused": true
			},
			"Config": {"Image": "ghcr.io/helloaltr/altr-stream:0.13.7-alpha"}
		}]`, "", 0, nil
	}

	engine := NewInstallerEngine(mockExec, &MockHTTPClient{})
	ctx := context.Background()

	status, err := engine.GetStatus(ctx, testDir)
	if err != nil {
		t.Fatalf("GetStatus failed: %v", err)
	}

	if status.ContainerState != "paused" {
		t.Errorf("expected container_state 'paused', got: '%s'", status.ContainerState)
	}
	if status.ContainerState == "stopped" || status.ContainerState == "exited" {
		t.Errorf("CRITICAL REGRESSION: container_state 'paused' was collapsed into '%s'", status.ContainerState)
	}
	if status.Healthy {
		t.Errorf("paused container must not be reported as healthy")
	}
}

// 69. Test GetStatus: Maps all discrete Docker container states without collapsing
func TestGetStatus_AllContainerLifecycleStates(t *testing.T) {
	testCases := []struct {
		dockerStatus  string
		expectedState string
	}{
		{"running", "running"},
		{"paused", "paused"},
		{"exited", "exited"},
		{"dead", "dead"},
		{"restarting", "restarting"},
		{"created", "created"},
	}

	for _, tc := range testCases {
		t.Run("Status_"+tc.dockerStatus, func(t *testing.T) {
			testDir := setupTestDir(t)
			mockExec := NewMockExecutor()
			mockExec.Handlers["info"] = func(args []string) (string, string, int, error) {
				return "Server Version: 27.1.1", "", 0, nil
			}
			mockExec.Handlers["inspect altr-stream"] = func(args []string) (string, string, int, error) {
				return fmt.Sprintf(`[{
					"Id": "test123",
					"State": {"Status": "%s"},
					"Config": {"Image": "ghcr.io/helloaltr/altr-stream:0.13.7-alpha"}
				}]`, tc.dockerStatus), "", 0, nil
			}

			engine := NewInstallerEngine(mockExec, &MockHTTPClient{})
			ctx := context.Background()

			status, err := engine.GetStatus(ctx, testDir)
			if err != nil {
				t.Fatalf("GetStatus failed: %v", err)
			}

			if status.ContainerState != tc.expectedState {
				t.Errorf("expected container_state '%s', got '%s'", tc.expectedState, status.ContainerState)
			}
		})
	}
}

// Test PauseContainer command
func TestPauseContainer(t *testing.T) {
	mockExec := NewMockExecutor()
	pauseCalled := false
	mockExec.Handlers["pause altr-stream"] = func(args []string) (string, string, int, error) {
		pauseCalled = true
		return "altr-stream", "", 0, nil
	}

	engine := NewInstallerEngine(mockExec, &MockHTTPClient{})
	ctx := context.Background()

	err := engine.PauseContainer(ctx)
	if err != nil {
		t.Fatalf("PauseContainer failed: %v", err)
	}
	if !pauseCalled {
		t.Errorf("expected 'docker pause altr-stream' to be called")
	}
}

// 70. Test UnpauseContainer command
func TestUnpauseContainer(t *testing.T) {
	mockExec := NewMockExecutor()
	unpauseCalled := false
	mockExec.Handlers["unpause altr-stream"] = func(args []string) (string, string, int, error) {
		unpauseCalled = true
		return "altr-stream", "", 0, nil
	}

	engine := NewInstallerEngine(mockExec, &MockHTTPClient{})
	ctx := context.Background()

	err := engine.UnpauseContainer(ctx)
	if err != nil {
		t.Fatalf("UnpauseContainer failed: %v", err)
	}
	if !unpauseCalled {
		t.Errorf("expected 'docker unpause altr-stream' to be called")
	}
}

// 71. Test StartExistingContainer when container is paused: unpauses cleanly
func TestStartExistingContainer_WhenPaused_UnpausesCleanly(t *testing.T) {
	mockExec := NewMockExecutor()
	// docker start returns paused error
	mockExec.Handlers["start altr-stream"] = func(args []string) (string, string, int, error) {
		return "", "Error response from daemon: cannot start a paused container, try unpause instead", 1, errors.New("exit status 1")
	}
	unpauseCalled := false
	mockExec.Handlers["unpause altr-stream"] = func(args []string) (string, string, int, error) {
		unpauseCalled = true
		return "altr-stream", "", 0, nil
	}

	engine := NewInstallerEngine(mockExec, &MockHTTPClient{})
	ctx := context.Background()

	err := engine.StartExistingContainer(ctx)
	if err != nil {
		t.Fatalf("StartExistingContainer failed: %v", err)
	}
	if !unpauseCalled {
		t.Errorf("expected unpause fallback when container is paused")
	}
}

// 72. Test Uninstall when container is PAUSED
// Verifies that a paused container is unpaused first, gracefully stopped, removed,
// and volume preserved.
func TestUninstall_PausedInstallerManagedContainer(t *testing.T) {
	testDir := setupTestDir(t)
	mockExec := NewMockExecutor()
	mockExec.Handlers["info"] = func(args []string) (string, string, int, error) {
		return "Server Version: 27.1.1", "", 0, nil
	}
	mockExec.Handlers["inspect altr-stream"] = func(args []string) (string, string, int, error) {
		return `[{
			"Id": "paused123",
			"State": {"Status": "paused", "Running": true, "Paused": true},
			"Config": {"Image": "ghcr.io/helloaltr/altr-stream:0.13.7-alpha"}
		}]`, "", 0, nil
	}
	unpauseCalled := false
	mockExec.Handlers["unpause altr-stream"] = func(args []string) (string, string, int, error) {
		unpauseCalled = true
		return "altr-stream", "", 0, nil
	}
	mockExec.Handlers["stop"] = func(args []string) (string, string, int, error) {
		return "altr-stream", "", 0, nil
	}
	mockExec.Handlers["rm -f altr-stream"] = func(args []string) (string, string, int, error) {
		return "altr-stream", "", 0, nil
	}
	mockExec.Handlers["inspect -f {{.State.Status}} altr-stream"] = func(args []string) (string, string, int, error) {
		return "", "Error: No such container", 1, nil
	}

	engine := NewInstallerEngine(mockExec, &MockHTTPClient{})
	ctx := context.Background()

	err := engine.Uninstall(ctx, testDir, false)
	if err != nil {
		t.Fatalf("Uninstall failed on paused container: %v", err)
	}

	if !unpauseCalled {
		t.Errorf("expected unpause altr-stream to be called before stopping paused container")
	}

	for _, call := range mockExec.CallLog {
		if strings.Contains(call, "volume rm") {
			t.Errorf("CRITICAL VIOLATION: volume rm was called when deleteData=false: %s", call)
		}
	}
}

// 73. Test CheckDocker: Classifies Docker Desktop Paused strictly as DockerStatePaused (NOT stopped)
func TestCheckDocker_ClassifiesDaemonPausedAsPaused(t *testing.T) {
	mockExec := NewMockExecutor()
	mockExec.Handlers["docker compose version"] = func(args []string) (string, string, int, error) {
		return "Docker Compose version v2.29.2", "", 0, nil
	}
	// Docker daemon returns standard Docker Desktop paused error
	mockExec.Handlers["docker info"] = func(args []string) (string, string, int, error) {
		return "", "Error response from daemon: Docker Desktop is manually paused. Unpause it through the Whale menu or Dashboard.", 1, fmt.Errorf("exit status 1")
	}

	dm := NewDockerManager(mockExec)
	status := dm.CheckDocker(context.Background())

	if status.State != DockerStatePaused {
		t.Errorf("expected DockerStatePaused, got %s", status.State)
	}
	if status.State == DockerStateStopped {
		t.Errorf("REGRESSION: DockerStatePaused must not equal DockerStateStopped")
	}
	if status.StatusText != "Docker Desktop is Paused" {
		t.Errorf("expected 'Docker Desktop is Paused', got '%s'", status.StatusText)
	}
	if status.ActionHint != "Resume Docker Desktop" {
		t.Errorf("expected ActionHint 'Resume Docker Desktop', got '%s'", status.ActionHint)
	}
}

// 74. Test CheckDocker: Comprehensive coverage of Docker Desktop states
func TestCheckDocker_AllDockerStates(t *testing.T) {
	cases := []struct {
		name          string
		infoErr       string
		desktopStatus string
		infoExit      int
		cliInstalled  bool
		expectedState DockerState
		expectedHint  string
	}{
		{
			name:          "Ready",
			infoErr:       "",
			infoExit:      0,
			cliInstalled:  true,
			expectedState: DockerStateReady,
			expectedHint:  "",
		},
		{
			name:          "Paused via daemon error string",
			infoErr:       "Error response from daemon: Docker Desktop is manually paused.",
			infoExit:      1,
			cliInstalled:  true,
			expectedState: DockerStatePaused,
			expectedHint:  "Resume Docker Desktop",
		},
		{
			name:          "Paused via CLI plugin status",
			infoErr:       "Cannot connect to the Docker daemon",
			desktopStatus: `{"Status": "paused"}`,
			infoExit:      1,
			cliInstalled:  true,
			expectedState: DockerStatePaused,
			expectedHint:  "Resume Docker Desktop",
		},
		{
			name:          "Stopped",
			infoErr:       "Cannot connect to the Docker daemon at unix:///var/run/docker.sock. Is the docker daemon running?",
			infoExit:      1,
			cliInstalled:  true,
			expectedState: DockerStateStopped,
			expectedHint:  "Start Docker Desktop",
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			mockExec := NewMockExecutor()
			if tc.cliInstalled {
				mockExec.Handlers["docker compose version"] = func(args []string) (string, string, int, error) {
					return "Docker Compose version v2.29.2", "", 0, nil
				}
			}
			mockExec.Handlers["docker info"] = func(args []string) (string, string, int, error) {
				if tc.infoExit == 0 {
					return "Server Version: 27.2.0", "", 0, nil
				}
				return "", tc.infoErr, tc.infoExit, fmt.Errorf("exit status %d", tc.infoExit)
			}
			if tc.desktopStatus != "" {
				mockExec.Handlers["desktop status --format json"] = func(args []string) (string, string, int, error) {
					return tc.desktopStatus, "", 0, nil
				}
			}

			dm := NewDockerManager(mockExec)
			dm.stat = func(name string) (os.FileInfo, error) {
				return nil, os.ErrNotExist
			}
			status := dm.CheckDocker(context.Background())

			if status.State != tc.expectedState {
				t.Errorf("expected state %s, got %s", tc.expectedState, status.State)
			}
			if status.ActionHint != tc.expectedHint {
				t.Errorf("expected ActionHint '%s', got '%s'", tc.expectedHint, status.ActionHint)
			}
		})
	}
}

// 75. Test UnpauseDockerDesktop
func TestUnpauseDockerDesktop(t *testing.T) {
	if runtime.GOOS != "darwin" {
		t.Skip("skipping Darwin-specific Docker Desktop unpause test on non-Darwin host")
	}
	t.Run("Direct Socket or Platform Unpause", func(t *testing.T) {
		mockExec := NewMockExecutor()
		engine := NewInstallerEngine(mockExec, &MockHTTPClient{})
		ctx := context.Background()

		err := engine.UnpauseDockerDesktop(ctx)
		if err != nil {
			t.Fatalf("UnpauseDockerDesktop failed: %v", err)
		}
	})

	t.Run("Fallback to CLI desktop start", func(t *testing.T) {
		mockExec := NewMockExecutor()
		unpauseDispatched := false
		mockExec.Handlers["desktop start"] = func(args []string) (string, string, int, error) {
			unpauseDispatched = true
			return "Docker Desktop started", "", 0, nil
		}

		engine := NewInstallerEngine(mockExec, &MockHTTPClient{})
		engine.dockerManager.stat = func(name string) (os.FileInfo, error) {
			return nil, os.ErrNotExist
		}
		ctx := context.Background()

		err := engine.UnpauseDockerDesktop(ctx)
		if err != nil {
			t.Fatalf("UnpauseDockerDesktop failed: %v", err)
		}
		if !unpauseDispatched {
			t.Errorf("expected desktop start fallback to be dispatched")
		}
	})

	t.Run("Socket Unavailable and Fallback Fails", func(t *testing.T) {
		mockExec := NewMockExecutor()
		mockExec.Handlers["desktop start"] = func(args []string) (string, string, int, error) {
			return "", "Docker Desktop is not installed", 1, fmt.Errorf("exit status 1")
		}
		mockExec.Handlers["open -a"] = func(args []string) (string, string, int, error) {
			return "", "Unable to find application", 1, fmt.Errorf("exit status 1")
		}

		engine := NewInstallerEngine(mockExec, &MockHTTPClient{})
		engine.dockerManager.stat = func(name string) (os.FileInfo, error) {
			return nil, os.ErrNotExist
		}
		ctx := context.Background()

		err := engine.UnpauseDockerDesktop(ctx)
		if err == nil {
			t.Fatalf("expected UnpauseDockerDesktop to return error when socket and fallbacks fail")
		}
	})
}

// 76. Test CheckDocker: Backend socket unavailable still gracefully detects paused state
func TestCheckDocker_BackendSockUnavailable_GracefulPausedDetection(t *testing.T) {
	mockExec := NewMockExecutor()
	mockExec.Handlers["docker compose version"] = func(args []string) (string, string, int, error) {
		return "Docker Compose version v2.29.2", "", 0, nil
	}
	mockExec.Handlers["docker info"] = func(args []string) (string, string, int, error) {
		return "", "Error response from daemon: Docker Desktop is manually paused. Unpause it through the Whale menu or Dashboard.", 1, fmt.Errorf("exit status 1")
	}

	dm := NewDockerManager(mockExec)
	// Mock stat so backend.sock definitely does not exist
	dm.stat = func(name string) (os.FileInfo, error) {
		return nil, os.ErrNotExist
	}

	status := dm.CheckDocker(context.Background())

	if status.State != DockerStatePaused {
		t.Errorf("expected DockerStatePaused, got %s", status.State)
	}
	if status.ActionHint != "Resume Docker Desktop" {
		t.Errorf("expected 'Resume Docker Desktop', got '%s'", status.ActionHint)
	}
}

// 76. Test StopSpecificContainer stops without removing
func TestStopSpecificContainer_StopsWithoutRemoving(t *testing.T) {
	mockExec := NewMockExecutor()
	stopCalled := false
	rmCalled := false

	mockExec.Handlers["stop -t 10 altr-stream-dev"] = func(args []string) (string, string, int, error) {
		stopCalled = true
		return "altr-stream-dev\n", "", 0, nil
	}
	mockExec.Handlers["rm"] = func(args []string) (string, string, int, error) {
		rmCalled = true
		return "", "", 0, nil
	}

	engine := NewInstallerEngine(mockExec, &MockHTTPClient{})
	ctx := context.Background()

	err := engine.StopSpecificContainer(ctx, "altr-stream-dev")
	if err != nil {
		t.Fatalf("StopSpecificContainer failed unexpectedly: %v", err)
	}

	if !stopCalled {
		t.Errorf("expected docker stop -t 10 altr-stream-dev to be called")
	}
	if rmCalled {
		t.Errorf("docker rm MUST NEVER be called when stopping a specific container")
	}
}

// 77. Test StopSpecificContainer input validation
func TestStopSpecificContainer_Validation(t *testing.T) {
	mockExec := NewMockExecutor()
	engine := NewInstallerEngine(mockExec, &MockHTTPClient{})
	ctx := context.Background()

	// Empty name
	if err := engine.StopSpecificContainer(ctx, ""); err == nil {
		t.Errorf("expected error for empty container name")
	}

	// Dangerous characters
	if err := engine.StopSpecificContainer(ctx, "dev; rm -rf /"); err == nil {
		t.Errorf("expected error for container name with injection characters")
	}
}

// 78. Test CheckPortConflict covers all 5 scenarios:
// - no conflict
// - Altr Stream dev container conflict
// - production Altr Stream container conflict
// - unrelated Docker container conflict
// - unrelated host process conflict
func TestCheckPortConflict_FiveScenarios(t *testing.T) {
	ctx := context.Background()

	// Scenario 1: No conflict
	t.Run("NoConflict", func(t *testing.T) {
		mockExec := NewMockExecutor()
		mockExec.Handlers["ps --filter publish=8000"] = func(args []string) (string, string, int, error) {
			return "", "", 0, nil
		}
		engine := NewInstallerEngine(mockExec, &MockHTTPClient{})
		engine.SetHostPortChecker(func(port int) error { return nil })

		conflict, err := engine.lifecycleManager.CheckPortConflict(ctx, 8000)
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if conflict.Exists {
			t.Errorf("expected conflict.Exists=false for free port")
		}
	})

	// Scenario 2: Altr Stream dev container conflict
	t.Run("AltrStreamDevContainerConflict", func(t *testing.T) {
		mockExec := NewMockExecutor()
		mockExec.Handlers["ps --filter publish=8000"] = func(args []string) (string, string, int, error) {
			return `{"ID":"dev123456789","Names":"altr-stream-dev","Image":"altr-stream-backend:latest","Status":"Up 3 hours","Ports":"0.0.0.0:8000->8000/tcp"}` + "\n", "", 0, nil
		}
		mockExec.Handlers["inspect dev123456789"] = func(args []string) (string, string, int, error) {
			return `[{"Id":"dev123456789","Name":"/altr-stream-dev","State":{"Status":"running","Running":true},"Config":{"Image":"altr-stream-backend:latest","Labels":{"dev":"true"}},"NetworkSettings":{"Ports":{"8000/tcp":[{"HostIp":"0.0.0.0","HostPort":"8000"}]}}}]`, "", 0, nil
		}
		engine := NewInstallerEngine(mockExec, &MockHTTPClient{})

		conflict, err := engine.lifecycleManager.CheckPortConflict(ctx, 8000)
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if !conflict.Exists {
			t.Fatalf("expected conflict.Exists=true")
		}
		if !conflict.IsDevContainer {
			t.Errorf("expected IsDevContainer=true")
		}
		if conflict.ContainerName != "altr-stream-dev" {
			t.Errorf("expected ContainerName 'altr-stream-dev', got %s", conflict.ContainerName)
		}
	})

	// Scenario 3: Production Altr Stream container conflict (e.g. other production instance)
	t.Run("ProductionAltrStreamContainerConflict", func(t *testing.T) {
		mockExec := NewMockExecutor()
		mockExec.Handlers["ps --filter publish=8000"] = func(args []string) (string, string, int, error) {
			return `{"ID":"prod12345678","Names":"altr-stream-prod-2","Image":"ghcr.io/helloaltr/altr-stream:0.13.7-alpha","Status":"Up 1 day","Ports":"0.0.0.0:8000->8000/tcp"}` + "\n", "", 0, nil
		}
		mockExec.Handlers["inspect prod12345678"] = func(args []string) (string, string, int, error) {
			return `[{"Id":"prod12345678","Name":"/altr-stream-prod-2","State":{"Status":"running","Running":true},"Config":{"Image":"ghcr.io/helloaltr/altr-stream:0.13.7-alpha","Labels":{}},"NetworkSettings":{"Ports":{"8000/tcp":[{"HostIp":"0.0.0.0","HostPort":"8000"}]}}}]`, "", 0, nil
		}
		engine := NewInstallerEngine(mockExec, &MockHTTPClient{})

		conflict, err := engine.lifecycleManager.CheckPortConflict(ctx, 8000)
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if !conflict.Exists {
			t.Fatalf("expected conflict.Exists=true")
		}
		if !conflict.IsAltrStream {
			t.Errorf("expected IsAltrStream=true")
		}
		if conflict.IsDevContainer {
			t.Errorf("expected IsDevContainer=false for production instance")
		}
		if conflict.ContainerName != "altr-stream-prod-2" {
			t.Errorf("expected ContainerName 'altr-stream-prod-2', got %s", conflict.ContainerName)
		}
	})

	// Scenario 4: Unrelated Docker container conflict
	t.Run("UnrelatedDockerContainerConflict", func(t *testing.T) {
		mockExec := NewMockExecutor()
		mockExec.Handlers["ps --filter publish=8000"] = func(args []string) (string, string, int, error) {
			return `{"ID":"nginx1234567","Names":"custom-nginx","Image":"nginx:alpine","Status":"Up 5 days","Ports":"0.0.0.0:8000->80/tcp"}` + "\n", "", 0, nil
		}
		mockExec.Handlers["inspect nginx1234567"] = func(args []string) (string, string, int, error) {
			return `[{"Id":"nginx1234567","Name":"/custom-nginx","State":{"Status":"running","Running":true},"Config":{"Image":"nginx:alpine","Labels":{}},"NetworkSettings":{"Ports":{"8000/tcp":[{"HostIp":"0.0.0.0","HostPort":"8000"}]}}}]`, "", 0, nil
		}
		engine := NewInstallerEngine(mockExec, &MockHTTPClient{})

		conflict, err := engine.lifecycleManager.CheckPortConflict(ctx, 8000)
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if !conflict.Exists {
			t.Fatalf("expected conflict.Exists=true")
		}
		if conflict.IsAltrStream {
			t.Errorf("expected IsAltrStream=false for custom-nginx")
		}
		if conflict.IsDevContainer {
			t.Errorf("expected IsDevContainer=false for custom-nginx")
		}
		if conflict.ContainerName != "custom-nginx" {
			t.Errorf("expected ContainerName 'custom-nginx', got %s", conflict.ContainerName)
		}
	})

	// Scenario 5: Unrelated host process conflict
	t.Run("HostProcessConflict", func(t *testing.T) {
		mockExec := NewMockExecutor()
		mockExec.Handlers["ps --filter publish=8000"] = func(args []string) (string, string, int, error) {
			return "", "", 0, nil
		}
		engine := NewInstallerEngine(mockExec, &MockHTTPClient{})
		engine.SetHostPortChecker(func(port int) error {
			return fmt.Errorf("bind: address already in use")
		})

		conflict, err := engine.lifecycleManager.CheckPortConflict(ctx, 8000)
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if !conflict.Exists {
			t.Fatalf("expected conflict.Exists=true for bound port")
		}
		if conflict.ConflictType != ConflictTypePortProcess {
			t.Errorf("expected ConflictTypePortProcess, got %s", conflict.ConflictType)
		}
		if conflict.IsDevContainer {
			t.Errorf("expected IsDevContainer=false for host process")
		}
	})
}

func TestProvisionConfig_WritesRuntimeFilesWithoutDocker(t *testing.T) {
	testDir := setupTestDir(t)
	mockExec := NewMockExecutor()
	engine := NewInstallerEngine(mockExec, &MockHTTPClient{})

	cfg := InstallConfig{
		TargetDir: testDir,
		Version:   "1.0.1-beta",
		Image:     "ghcr.io/helloaltr/altr-stream:1.0.1-beta",
		Port:      8000,
	}

	err := engine.ProvisionConfig(testDir, cfg)
	if err != nil {
		t.Fatalf("ProvisionConfig failed: %v", err)
	}

	// Verify docker-compose.yml exists
	composeFile := filepath.Join(testDir, "docker-compose.yml")
	composeData, err := os.ReadFile(composeFile)
	if err != nil {
		t.Fatalf("missing docker-compose.yml: %v", err)
	}
	if !strings.Contains(string(composeData), "altr-stream:1.0.1-beta") {
		t.Errorf("expected image reference in docker-compose.yml, got: %s", string(composeData))
	}

	// Verify .env exists
	envFile := filepath.Join(testDir, ".env")
	envData, err := os.ReadFile(envFile)
	if err != nil {
		t.Fatalf("missing .env: %v", err)
	}
	if !strings.Contains(string(envData), "ALTR_STREAM_PORT=8000") {
		t.Errorf("expected port 8000 in .env, got: %s", string(envData))
	}

	// Verify updates directory exists
	updatesDir := filepath.Join(testDir, "data", "updates")
	if fi, err := os.Stat(updatesDir); err != nil || !fi.IsDir() {
		t.Errorf("expected updates directory at %s", updatesDir)
	}
}

func TestInspectImageRegistry(t *testing.T) {
	ctx := context.Background()

	t.Run("ValidAndAvailableOnRegistry", func(t *testing.T) {
		mockExec := NewMockExecutor()
		mockExec.Handlers["images -q"] = func(args []string) (string, string, int, error) {
			return "", "", 0, nil // not in local cache
		}
		mockExec.Handlers["manifest inspect"] = func(args []string) (string, string, int, error) {
			return `{"schemaVersion": 2}`, "", 0, nil
		}

		dm := NewDockerManager(mockExec)
		dm.lookPath = func(file string) (string, error) { return "/usr/local/bin/docker", nil }

		res := dm.InspectImageRegistry(ctx, "ghcr.io/helloaltr/altr-stream:1.0.1-beta")
		if !res.Valid || !res.Available || res.Status != "available" {
			t.Fatalf("expected available, got: %+v", res)
		}
	})

	t.Run("AvailableInLocalCache", func(t *testing.T) {
		mockExec := NewMockExecutor()
		mockExec.Handlers["images -q"] = func(args []string) (string, string, int, error) {
			return "sha256:123456", "", 0, nil
		}

		dm := NewDockerManager(mockExec)
		dm.lookPath = func(file string) (string, error) { return "/usr/local/bin/docker", nil }

		res := dm.InspectImageRegistry(ctx, "1.0.0-beta")
		if !res.Valid || !res.Available || res.Status != "available" {
			t.Fatalf("expected available from cache, got: %+v", res)
		}
		if res.Image != "ghcr.io/helloaltr/altr-stream:1.0.0-beta" {
			t.Errorf("expected normalized image, got: %s", res.Image)
		}
	})

	t.Run("UnavailableTag_ManifestUnknown", func(t *testing.T) {
		mockExec := NewMockExecutor()
		mockExec.Handlers["images -q"] = func(args []string) (string, string, int, error) {
			return "", "", 0, nil
		}
		mockExec.Handlers["manifest inspect"] = func(args []string) (string, string, int, error) {
			return "", "manifest unknown", 1, nil
		}

		dm := NewDockerManager(mockExec)
		dm.lookPath = func(file string) (string, error) { return "/usr/local/bin/docker", nil }

		res := dm.InspectImageRegistry(ctx, "ghcr.io/helloaltr/altr-stream:0.0.1")
		if !res.Valid {
			t.Errorf("syntax is valid, expected Valid=true, got false")
		}
		if res.Available {
			t.Errorf("tag does not exist, expected Available=false")
		}
		if res.Status != "unavailable" {
			t.Errorf("expected status 'unavailable', got: %s", res.Status)
		}
		if !strings.Contains(res.Message, "not found on the container registry") {
			t.Errorf("expected actionable error message, got: %s", res.Message)
		}
	})

	t.Run("InvalidFormat_WhitespaceOrBadChars", func(t *testing.T) {
		mockExec := NewMockExecutor()
		dm := NewDockerManager(mockExec)

		resSpace := dm.InspectImageRegistry(ctx, "my image:tag")
		if resSpace.Valid || resSpace.Available || resSpace.Status != "invalid_format" {
			t.Errorf("expected invalid_format for whitespace, got: %+v", resSpace)
		}

		resEmpty := dm.InspectImageRegistry(ctx, "   ")
		if resEmpty.Valid || resEmpty.Available || resEmpty.Status != "invalid_format" {
			t.Errorf("expected invalid_format for empty, got: %+v", resEmpty)
		}

		resBad := dm.InspectImageRegistry(ctx, "image$tag")
		if resBad.Valid || resBad.Available || resBad.Status != "invalid_format" {
			t.Errorf("expected invalid_format for '$', got: %+v", resBad)
		}
	})

	t.Run("NetworkFailure", func(t *testing.T) {
		mockExec := NewMockExecutor()
		mockExec.Handlers["images -q"] = func(args []string) (string, string, int, error) {
			return "", "", 0, nil
		}
		mockExec.Handlers["manifest inspect"] = func(args []string) (string, string, int, error) {
			return "", "dial tcp: connection refused", 1, nil
		}

		dm := NewDockerManager(mockExec)
		dm.lookPath = func(file string) (string, error) { return "/usr/local/bin/docker", nil }

		res := dm.InspectImageRegistry(ctx, "ghcr.io/helloaltr/altr-stream:1.0.0-beta")
		if res.Status != "network_error" {
			t.Errorf("expected network_error, got: %s", res.Status)
		}
	})

	t.Run("AuthFailure", func(t *testing.T) {
		mockExec := NewMockExecutor()
		mockExec.Handlers["images -q"] = func(args []string) (string, string, int, error) {
			return "", "", 0, nil
		}
		mockExec.Handlers["manifest inspect"] = func(args []string) (string, string, int, error) {
			return "", "Error response from daemon: unauthorized: authentication required", 1, nil
		}

		dm := NewDockerManager(mockExec)
		dm.lookPath = func(file string) (string, error) { return "/usr/local/bin/docker", nil }

		res := dm.InspectImageRegistry(ctx, "private.repo/image:tag")
		if res.Status != "auth_error" {
			t.Errorf("expected auth_error, got: %s", res.Status)
		}
	})
}

func TestSwitchVersion_SuccessfulCutover(t *testing.T) {
	mockExec := NewMockExecutor()
	mockClient := &MockHTTPClient{
		DoFunc: func(req *http.Request) (*http.Response, error) {
			return &http.Response{
				StatusCode: 200,
				Body:       io.NopCloser(strings.NewReader(`{"status":"ok","version":"0.13.7-alpha"}`)),
			}, nil
		},
	}

	testDir := t.TempDir()
	origCompose := filepath.Join(testDir, "docker-compose.yml")
	origEnv := filepath.Join(testDir, ".env")
	_ = os.WriteFile(origCompose, []byte("image: ghcr.io/helloaltr/altr-stream:1.0.0-beta\n"), 0644)
	_ = os.WriteFile(origEnv, []byte("ALTR_STREAM_IMAGE=ghcr.io/helloaltr/altr-stream:1.0.0-beta\nALTR_STREAM_PORT=8000\n"), 0644)

	pulledImages := []string{}
	removedContainers := []string{}
	startedContainers := []string{}

	mockExec.Handlers["manifest inspect"] = func(args []string) (string, string, int, error) {
		return `{"schemaVersion": 2}`, "", 0, nil
	}
	mockExec.Handlers["pull"] = func(args []string) (string, string, int, error) {
		for i, arg := range args {
			if arg == "pull" && i+1 < len(args) {
				pulledImages = append(pulledImages, args[i+1])
			}
		}
		return "Downloaded newer image", "", 0, nil
	}
	mockExec.Handlers["inspect -f {{.Config.Image}} altr-stream"] = func(args []string) (string, string, int, error) {
		return "ghcr.io/helloaltr/altr-stream:1.0.0-beta", "", 0, nil
	}
	mockExec.Handlers["rm -f altr-stream"] = func(args []string) (string, string, int, error) {
		removedContainers = append(removedContainers, "altr-stream")
		return "altr-stream", "", 0, nil
	}
	mockExec.Handlers["up -d"] = func(args []string) (string, string, int, error) {
		startedContainers = append(startedContainers, "altr-stream")
		return "Container altr-stream Started", "", 0, nil
	}
	mockExec.Handlers["inspect altr-stream"] = func(args []string) (string, string, int, error) {
		return `[{"State":{"Status":"running","Running":true},"NetworkSettings":{"Ports":{"8000/tcp":[{"HostPort":"8000"}]}}}]`, "", 0, nil
	}
	mockExec.Handlers["inspect -f {{.State.Running}} altr-stream"] = func(args []string) (string, string, int, error) {
		return "true", "", 0, nil
	}

	engine := NewInstallerEngine(mockExec, mockClient)
	engine.dockerManager.lookPath = func(file string) (string, error) { return "/usr/local/bin/docker", nil }

	var progressStages []InstallStage
	err := engine.SwitchVersion(context.Background(), testDir, InstallConfig{
		Image:   "ghcr.io/helloaltr/altr-stream:0.13.7-alpha",
		Version: "0.13.7-alpha",
		Port:    8000,
	}, func(p InstallProgress) {
		progressStages = append(progressStages, p.Stage)
	})

	if err != nil {
		t.Fatalf("expected successful switch, got: %v", err)
	}

	if len(pulledImages) == 0 || pulledImages[0] != "ghcr.io/helloaltr/altr-stream:0.13.7-alpha" {
		t.Errorf("expected target image to be pre-pulled, got: %v", pulledImages)
	}
	if len(removedContainers) != 1 {
		t.Errorf("expected old container to be removed, got: %v", removedContainers)
	}
	if len(startedContainers) != 1 {
		t.Errorf("expected new container to be started, got: %v", startedContainers)
	}

	// Verify .env was updated to target image
	envData, _ := os.ReadFile(origEnv)
	if !strings.Contains(string(envData), "ALTR_STREAM_IMAGE=ghcr.io/helloaltr/altr-stream:0.13.7-alpha") {
		t.Errorf("expected updated .env, got: %s", string(envData))
	}
}

func TestSwitchVersion_PrePullFails_ContainerUntouched(t *testing.T) {
	mockExec := NewMockExecutor()
	mockClient := &MockHTTPClient{}
	testDir := t.TempDir()

	mockExec.Handlers["manifest inspect"] = func(args []string) (string, string, int, error) {
		return `{"schemaVersion": 2}`, "", 0, nil
	}
	mockExec.Handlers["pull"] = func(args []string) (string, string, int, error) {
		return "", "Error response from daemon: connection timed out", 1, nil
	}
	mockExec.Handlers["images -q"] = func(args []string) (string, string, int, error) {
		return "", "", 0, nil
	}

	removed := false
	mockExec.Handlers["rm -f altr-stream"] = func(args []string) (string, string, int, error) {
		removed = true
		return "", "", 0, nil
	}

	engine := NewInstallerEngine(mockExec, mockClient)
	engine.dockerManager.lookPath = func(file string) (string, error) { return "/usr/local/bin/docker", nil }

	err := engine.SwitchVersion(context.Background(), testDir, InstallConfig{
		Image:   "ghcr.io/helloaltr/altr-stream:0.13.7-alpha",
		Version: "0.13.7-alpha",
		Port:    8000,
	}, nil)

	if err == nil {
		t.Fatal("expected pre-pull failure to error out")
	}
	if !strings.Contains(err.Error(), "failed to pre-pull target image") {
		t.Errorf("expected pre-pull error message, got: %v", err)
	}
	if removed {
		t.Error("old container must NOT be removed when pre-pull fails")
	}
}

func TestSwitchVersion_HealthCheckFails_RollsBackSuccessfully(t *testing.T) {
	mockExec := NewMockExecutor()

	testDir := t.TempDir()
	origCompose := filepath.Join(testDir, "docker-compose.yml")
	origEnv := filepath.Join(testDir, ".env")
	_ = os.WriteFile(origCompose, []byte("image: ghcr.io/helloaltr/altr-stream:1.0.0-beta\n"), 0644)
	_ = os.WriteFile(origEnv, []byte("ALTR_STREAM_IMAGE=ghcr.io/helloaltr/altr-stream:1.0.0-beta\nALTR_STREAM_PORT=8000\n"), 0644)

	mockExec.Handlers["manifest inspect"] = func(args []string) (string, string, int, error) {
		return `{"schemaVersion": 2}`, "", 0, nil
	}
	mockExec.Handlers["pull"] = func(args []string) (string, string, int, error) {
		return "Downloaded image", "", 0, nil
	}
	mockExec.Handlers["inspect -f {{.Config.Image}} altr-stream"] = func(args []string) (string, string, int, error) {
		return "ghcr.io/helloaltr/altr-stream:1.0.0-beta", "", 0, nil
	}
	mockExec.Handlers["rm -f altr-stream"] = func(args []string) (string, string, int, error) {
		return "altr-stream", "", 0, nil
	}
	mockExec.Handlers["up -d"] = func(args []string) (string, string, int, error) {
		return "Container started", "", 0, nil
	}
	mockExec.Handlers["inspect altr-stream"] = func(args []string) (string, string, int, error) {
		return `[{"State":{"Status":"running","Running":true},"NetworkSettings":{"Ports":{"8000/tcp":[{"HostPort":"8000"}]}}}]`, "", 0, nil
	}
	mockExec.Handlers["inspect -f {{.State.Running}} altr-stream"] = func(args []string) (string, string, int, error) {
		return "true", "", 0, nil
	}

	callCount := 0
	mockClient := &MockHTTPClient{
		DoFunc: func(req *http.Request) (*http.Response, error) {
			callCount++
			if callCount == 1 {
				// Target container health fails / wrong version
				return &http.Response{
					StatusCode: 500,
					Body:       io.NopCloser(strings.NewReader(`{"status":"error"}`)),
				}, nil
			}
			// Restored container health succeeds
			return &http.Response{
				StatusCode: 200,
				Body:       io.NopCloser(strings.NewReader(`{"status":"ok","version":"1.0.0-beta"}`)),
			}, nil
		},
	}

	engine := NewInstallerEngine(mockExec, mockClient)
	engine.dockerManager.lookPath = func(file string) (string, error) { return "/usr/local/bin/docker", nil }

	err := engine.SwitchVersion(context.Background(), testDir, InstallConfig{
		Image:         "ghcr.io/helloaltr/altr-stream:0.13.7-alpha",
		Version:       "0.13.7-alpha",
		Port:          8000,
		HealthTimeout: 2,
	}, nil)

	if err == nil {
		t.Fatal("expected error due to health check failure")
	}
	if !strings.Contains(err.Error(), "Successfully rolled back to ghcr.io/helloaltr/altr-stream:1.0.0-beta") {
		t.Errorf("expected clear rollback success message, got: %v", err)
	}

	// Verify original docker-compose.yml was restored
	restoredCompose, _ := os.ReadFile(origCompose)
	if !strings.Contains(string(restoredCompose), "image: ghcr.io/helloaltr/altr-stream:1.0.0-beta") {
		t.Errorf("expected restored docker-compose.yml, got: %s", string(restoredCompose))
	}
}

func TestGetStatus_ReportsActiveImageAndVersion(t *testing.T) {
	mockExec := NewMockExecutor()
	mockClient := &MockHTTPClient{
		DoFunc: func(req *http.Request) (*http.Response, error) {
			return &http.Response{
				StatusCode: 200,
				Body:       io.NopCloser(strings.NewReader(`{"status":"ok","version":"1.0.0-beta"}`)),
			}, nil
		},
	}

	mockExec.Handlers["inspect altr-stream"] = func(args []string) (string, string, int, error) {
		return `[{"State":{"Status":"running","Running":true},"Config":{"Image":"ghcr.io/helloaltr/altr-stream:1.0.0-beta"},"NetworkSettings":{"Ports":{"8000/tcp":[{"HostPort":"8000"}]}}}]`, "", 0, nil
	}

	engine := NewInstallerEngine(mockExec, mockClient)
	engine.dockerManager.lookPath = func(file string) (string, error) { return "/usr/local/bin/docker", nil }

	st, err := engine.GetStatus(context.Background(), t.TempDir())
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if st.ActiveImage != "ghcr.io/helloaltr/altr-stream:1.0.0-beta" {
		t.Errorf("expected ActiveImage to be populated, got: %s", st.ActiveImage)
	}
	if st.ActiveVersion != "1.0.0-beta" {
		t.Errorf("expected ActiveVersion to be 1.0.0-beta, got: %s", st.ActiveVersion)
	}
}

func TestIsolatedInstance_WriteRuntimeFiles_HasCompleteSeparation(t *testing.T) {
	testDir := t.TempDir()
	lm := NewLifecycleManager(NewMockExecutor(), &MockHTTPClient{})

	cfg := InstallConfig{
		TargetDir:     testDir,
		Version:       "1.0.0-beta",
		Image:         "ghcr.io/helloaltr/altr-stream:1.0.0-beta",
		Port:          8001,
		ContainerName: "altr-stream-test",
		DataVolume:    "altr_stream_test_data",
		NetworkName:   "altr-stream-test-net",
	}

	err := lm.WriteRuntimeFiles(testDir, cfg)
	if err != nil {
		t.Fatalf("WriteRuntimeFiles failed: %v", err)
	}

	// Verify docker-compose.yml
	composeBytes, err := os.ReadFile(filepath.Join(testDir, "docker-compose.yml"))
	if err != nil {
		t.Fatalf("failed to read compose file: %v", err)
	}
	composeStr := string(composeBytes)

	if !strings.Contains(composeStr, "container_name: altr-stream-test") {
		t.Errorf("expected compose file to have container_name: altr-stream-test, got:\n%s", composeStr)
	}
	if !strings.Contains(composeStr, "altr_stream_test_data:/app/data") {
		t.Errorf("expected compose file to mount altr_stream_test_data, got:\n%s", composeStr)
	}
	if !strings.Contains(composeStr, "altr_stream_test_data:") {
		t.Errorf("expected compose file to declare named volume altr_stream_test_data, got:\n%s", composeStr)
	}
	if !strings.Contains(composeStr, "\"8001:8000\"") {
		t.Errorf("expected compose file to map port 8001:8000, got:\n%s", composeStr)
	}
	// Verify test environment metadata labels
	if !strings.Contains(composeStr, "com.helloaltr.altr-stream.environment=test") {
		t.Errorf("expected compose file to label environment=test, got:\n%s", composeStr)
	}
	if !strings.Contains(composeStr, "com.helloaltr.altr-stream.instance=altr-stream-test") {
		t.Errorf("expected compose file to label instance=altr-stream-test, got:\n%s", composeStr)
	}
	if strings.Contains(composeStr, "com.helloaltr.altr-stream.environment=production") {
		t.Errorf("compose file must not label test instance as environment=production")
	}

	// Crucial: Must NOT contain default production container name as container_name
	if strings.Contains(composeStr, "container_name: altr-stream\n") {
		t.Errorf("compose file must not set container_name to production 'altr-stream'")
	}
	if strings.Contains(composeStr, "altr_stream_data:/app/data") {
		t.Errorf("compose file must not bind production volume 'altr_stream_data'")
	}

	// Verify .env file
	envBytes, err := os.ReadFile(filepath.Join(testDir, ".env"))
	if err != nil {
		t.Fatalf("failed to read .env file: %v", err)
	}
	envStr := string(envBytes)

	if !strings.Contains(envStr, "ALTR_STREAM_ENVIRONMENT=test") {
		t.Errorf("expected .env to specify ALTR_STREAM_ENVIRONMENT=test, got:\n%s", envStr)
	}
	if !strings.Contains(envStr, "ALTR_STREAM_CONTAINER_NAME=altr-stream-test") {
		t.Errorf("expected .env to specify ALTR_STREAM_CONTAINER_NAME=altr-stream-test, got:\n%s", envStr)
	}
	if !strings.Contains(envStr, "ALTR_STREAM_DATA_VOLUME=altr_stream_test_data") {
		t.Errorf("expected .env to specify ALTR_STREAM_DATA_VOLUME=altr_stream_test_data, got:\n%s", envStr)
	}
	if !strings.Contains(envStr, "ALTR_STREAM_PORT=8001") {
		t.Errorf("expected .env to specify ALTR_STREAM_PORT=8001, got:\n%s", envStr)
	}
}

func TestSwitchVersion_IsolatedTestInstance_NeverTouchesProduction(t *testing.T) {
	mockExec := NewMockExecutor()
	testDir := t.TempDir()

	origCompose := filepath.Join(testDir, "docker-compose.yml")
	origEnv := filepath.Join(testDir, ".env")

	_ = os.WriteFile(origCompose, []byte(`services:
  altr-stream-test:
    container_name: altr-stream-test
    image: ghcr.io/helloaltr/altr-stream:1.0.0-beta
    volumes:
      - altr_stream_test_data:/app/data
`), 0644)
	_ = os.WriteFile(origEnv, []byte("ALTR_STREAM_CONTAINER_NAME=altr-stream-test\nALTR_STREAM_DATA_VOLUME=altr_stream_test_data\nALTR_STREAM_PORT=8001\nALTR_STREAM_IMAGE=ghcr.io/helloaltr/altr-stream:1.0.0-beta\n"), 0644)

	var testContainerRemoved bool
	var testContainerStarted bool

	mockExec.Handlers["manifest inspect"] = func(args []string) (string, string, int, error) {
		return `{"schemaVersion": 2}`, "", 0, nil
	}
	mockExec.Handlers["pull"] = func(args []string) (string, string, int, error) {
		return "Downloaded image", "", 0, nil
	}

	// Handlers for isolated test container
	mockExec.Handlers["inspect -f {{.Config.Image}} altr-stream-test"] = func(args []string) (string, string, int, error) {
		return "ghcr.io/helloaltr/altr-stream:1.0.0-beta", "", 0, nil
	}
	mockExec.Handlers["rm -f altr-stream-test"] = func(args []string) (string, string, int, error) {
		testContainerRemoved = true
		return "altr-stream-test", "", 0, nil
	}
	mockExec.Handlers["up -d"] = func(args []string) (string, string, int, error) {
		testContainerStarted = true
		return "Container altr-stream-test Started", "", 0, nil
	}
	mockExec.Handlers["inspect altr-stream-test"] = func(args []string) (string, string, int, error) {
		return `[{"State":{"Status":"running","Running":true},"NetworkSettings":{"Ports":{"8000/tcp":[{"HostPort":"8001"}]}}}]`, "", 0, nil
	}
	mockExec.Handlers["inspect -f {{.State.Running}} altr-stream-test"] = func(args []string) (string, string, int, error) {
		return "true", "", 0, nil
	}

	mockClient := &MockHTTPClient{
		DoFunc: func(req *http.Request) (*http.Response, error) {
			if !strings.Contains(req.URL.Host, "8001") {
				t.Errorf("health check sent to unexpected host: %s (must be port 8001)", req.URL.Host)
			}
			return &http.Response{
				StatusCode: 200,
				Body:       io.NopCloser(strings.NewReader(`{"status":"ok","version":"0.13.7-alpha"}`)),
			}, nil
		},
	}

	engine := NewInstallerEngine(mockExec, mockClient)
	engine.dockerManager.lookPath = func(file string) (string, error) { return "/usr/local/bin/docker", nil }

	err := engine.SwitchVersion(context.Background(), testDir, InstallConfig{
		Image:         "ghcr.io/helloaltr/altr-stream:0.13.7-alpha",
		Version:       "0.13.7-alpha",
		Port:          8001,
		ContainerName: "altr-stream-test",
		DataVolume:    "altr_stream_test_data",
		HealthTimeout: 5,
	}, nil)

	if err != nil {
		t.Fatalf("SwitchVersion failed unexpectedly: %v", err)
	}

	// Verify no lifecycle operations targeted production container or volume
	for _, call := range mockExec.CallLog {
		for _, w := range strings.Fields(call) {
			if w == "altr-stream" {
				t.Fatalf("CRITICAL DEFECT: Command '%s' targeted production container 'altr-stream'!", call)
			}
			if w == "altr_stream_data" {
				t.Fatalf("CRITICAL DEFECT: Command '%s' targeted production volume 'altr_stream_data'!", call)
			}
		}
	}

	if !testContainerRemoved {
		t.Error("expected test container 'altr-stream-test' to be removed during switch")
	}
	if !testContainerStarted {
		t.Error("expected test container 'altr-stream-test' to be started during switch")
	}

	// Verify updated files
	envData, _ := os.ReadFile(origEnv)
	if !strings.Contains(string(envData), "ALTR_STREAM_CONTAINER_NAME=altr-stream-test") {
		t.Errorf("expected .env to retain ALTR_STREAM_CONTAINER_NAME=altr-stream-test, got: %s", string(envData))
	}
	if !strings.Contains(string(envData), "ALTR_STREAM_DATA_VOLUME=altr_stream_test_data") {
		t.Errorf("expected .env to retain ALTR_STREAM_DATA_VOLUME=altr_stream_test_data, got: %s", string(envData))
	}
	if !strings.Contains(string(envData), "ALTR_STREAM_IMAGE=ghcr.io/helloaltr/altr-stream:0.13.7-alpha") {
		t.Errorf("expected .env to update image, got: %s", string(envData))
	}
}

func TestRollbackVersion_IsolatedTestInstance_NeverTouchesProduction(t *testing.T) {
	mockExec := NewMockExecutor()
	testDir := t.TempDir()

	origCompose := filepath.Join(testDir, "docker-compose.yml")
	origEnv := filepath.Join(testDir, ".env")

	_ = os.WriteFile(origCompose, []byte(`services:
  altr-stream-test:
    container_name: altr-stream-test
    image: ghcr.io/helloaltr/altr-stream:1.0.0-beta
    volumes:
      - altr_stream_test_data:/app/data
`), 0644)
	_ = os.WriteFile(origEnv, []byte("ALTR_STREAM_CONTAINER_NAME=altr-stream-test\nALTR_STREAM_DATA_VOLUME=altr_stream_test_data\nALTR_STREAM_PORT=8001\nALTR_STREAM_IMAGE=ghcr.io/helloaltr/altr-stream:1.0.0-beta\n"), 0644)

	var testContainerRemovedCount int

	mockExec.Handlers["manifest inspect"] = func(args []string) (string, string, int, error) {
		return `{"schemaVersion": 2}`, "", 0, nil
	}
	mockExec.Handlers["pull"] = func(args []string) (string, string, int, error) {
		return "Downloaded image", "", 0, nil
	}

	// Handlers for test container
	mockExec.Handlers["inspect -f {{.Config.Image}} altr-stream-test"] = func(args []string) (string, string, int, error) {
		return "ghcr.io/helloaltr/altr-stream:1.0.0-beta", "", 0, nil
	}
	mockExec.Handlers["rm -f altr-stream-test"] = func(args []string) (string, string, int, error) {
		testContainerRemovedCount++
		return "altr-stream-test", "", 0, nil
	}
	mockExec.Handlers["up -d"] = func(args []string) (string, string, int, error) {
		return "Container altr-stream-test Started", "", 0, nil
	}
	mockExec.Handlers["inspect altr-stream-test"] = func(args []string) (string, string, int, error) {
		return `[{"State":{"Status":"running","Running":true},"NetworkSettings":{"Ports":{"8000/tcp":[{"HostPort":"8001"}]}}}]`, "", 0, nil
	}
	mockExec.Handlers["inspect -f {{.State.Running}} altr-stream-test"] = func(args []string) (string, string, int, error) {
		return "true", "", 0, nil
	}

	callCount := 0
	mockClient := &MockHTTPClient{
		DoFunc: func(req *http.Request) (*http.Response, error) {
			if !strings.Contains(req.URL.Host, "8001") {
				t.Errorf("health check sent to unexpected host: %s (must be port 8001)", req.URL.Host)
			}
			callCount++
			if callCount == 1 {
				// Target image health check fails
				return &http.Response{
					StatusCode: 500,
					Body:       io.NopCloser(strings.NewReader(`{"status":"error"}`)),
				}, nil
			}
			// Restored rollback container health check succeeds
			return &http.Response{
				StatusCode: 200,
				Body:       io.NopCloser(strings.NewReader(`{"status":"ok","version":"1.0.0-beta"}`)),
			}, nil
		},
	}

	engine := NewInstallerEngine(mockExec, mockClient)
	engine.dockerManager.lookPath = func(file string) (string, error) { return "/usr/local/bin/docker", nil }

	err := engine.SwitchVersion(context.Background(), testDir, InstallConfig{
		Image:         "ghcr.io/helloaltr/altr-stream:0.13.7-alpha",
		Version:       "0.13.7-alpha",
		Port:          8001,
		ContainerName: "altr-stream-test",
		DataVolume:    "altr_stream_test_data",
		HealthTimeout: 2,
	}, nil)

	if err == nil {
		t.Fatal("expected error due to health check failure")
	}
	if !strings.Contains(err.Error(), "Successfully rolled back to ghcr.io/helloaltr/altr-stream:1.0.0-beta") {
		t.Errorf("expected clean rollback message, got: %v", err)
	}

	// Verify no lifecycle operations targeted production container or volume
	for _, call := range mockExec.CallLog {
		for _, w := range strings.Fields(call) {
			if w == "altr-stream" {
				t.Fatalf("CRITICAL DEFECT: Command '%s' targeted production container 'altr-stream'!", call)
			}
			if w == "altr_stream_data" {
				t.Fatalf("CRITICAL DEFECT: Command '%s' targeted production volume 'altr_stream_data'!", call)
			}
		}
	}

	// SwitchVersion calls rm once for switch cutover, and rollback calls rm once more
	if testContainerRemovedCount != 2 {
		t.Errorf("expected test container 'altr-stream-test' to be removed twice (switch + rollback), got: %d", testContainerRemovedCount)
	}

	// Verify original docker-compose.yml was restored
	restoredCompose, _ := os.ReadFile(origCompose)
	if !strings.Contains(string(restoredCompose), "image: ghcr.io/helloaltr/altr-stream:1.0.0-beta") {
		t.Errorf("expected restored docker-compose.yml, got: %s", string(restoredCompose))
	}
}

func TestUninstall_IsolatedTestInstance_NeverTouchesProduction(t *testing.T) {
	mockExec := NewMockExecutor()
	testDir := t.TempDir()

	origEnv := filepath.Join(testDir, ".env")
	_ = os.WriteFile(origEnv, []byte("ALTR_STREAM_CONTAINER_NAME=altr-stream-test\nALTR_STREAM_DATA_VOLUME=altr_stream_test_data\nALTR_STREAM_PORT=8001\n"), 0644)

	var testContainerRemoved bool
	var testVolumeRemoved bool

	mockExec.Handlers["inspect altr-stream-test"] = func(args []string) (string, string, int, error) {
		return `[{"State":{"Status":"running","Running":true}}]`, "", 0, nil
	}
	mockExec.Handlers["stop altr-stream-test"] = func(args []string) (string, string, int, error) {
		return "altr-stream-test", "", 0, nil
	}
	mockExec.Handlers["rm -f altr-stream-test"] = func(args []string) (string, string, int, error) {
		testContainerRemoved = true
		return "altr-stream-test", "", 0, nil
	}
	mockExec.Handlers["volume rm altr_stream_test_data"] = func(args []string) (string, string, int, error) {
		testVolumeRemoved = true
		return "altr_stream_test_data", "", 0, nil
	}

	engine := NewInstallerEngine(mockExec, &MockHTTPClient{})
	engine.dockerManager.lookPath = func(file string) (string, error) { return "/usr/local/bin/docker", nil }

	err := engine.Uninstall(context.Background(), testDir, true)
	if err != nil {
		t.Fatalf("Uninstall failed unexpectedly: %v", err)
	}

	// Verify no lifecycle operations targeted production container or volume
	for _, call := range mockExec.CallLog {
		for _, w := range strings.Fields(call) {
			if w == "altr-stream" {
				t.Fatalf("CRITICAL DEFECT: Command '%s' targeted production container 'altr-stream'!", call)
			}
			if w == "altr_stream_data" {
				t.Fatalf("CRITICAL DEFECT: Command '%s' targeted production volume 'altr_stream_data'!", call)
			}
		}
	}

	if !testContainerRemoved {
		t.Error("expected test container to be removed")
	}
	if !testVolumeRemoved {
		t.Error("expected test volume to be removed")
	}
}

func TestOfficialImageLocalCacheCannotShadowManifestUnknown(t *testing.T) {
	ctx := context.Background()
	mockExec := NewMockExecutor()
	// Local cache has an image tagged with the unpublished version
	mockExec.Handlers["images -q"] = func(args []string) (string, string, int, error) {
		return "sha256:abc123locallybuilt", "", 0, nil
	}
	// But remote registry returns manifest unknown
	mockExec.Handlers["manifest inspect"] = func(args []string) (string, string, int, error) {
		return "", "Error: manifest unknown", 1, nil
	}

	dm := NewDockerManager(mockExec)
	dm.lookPath = func(file string) (string, error) { return "/usr/local/bin/docker", nil }

	res := dm.InspectImageRegistry(ctx, "ghcr.io/helloaltr/altr-stream:1.0.1-beta")
	if res.Available {
		t.Errorf("CRITICAL DEFECT: Local image shadowed remote registry! Expected Available=false, got Available=true")
	}
	if res.Status != "unavailable" {
		t.Errorf("expected status 'unavailable', got '%s'", res.Status)
	}
}

func TestGetStatus_DoesNotAdoptDevContainer(t *testing.T) {
	testDir := setupTestDir(t)
	mockExec := NewMockExecutor()
	mockExec.Handlers["info"] = func(args []string) (string, string, int, error) {
		return "Server Version: 27.1.1", "", 0, nil
	}
	mockExec.Handlers["compose version"] = func(args []string) (string, string, int, error) {
		return "Docker Compose v2", "", 0, nil
	}
	// Return a running container labeled with a compose project from dev
	mockExec.Handlers["inspect altr-stream"] = func(args []string) (string, string, int, error) {
		return `[{
			"Config": {
				"Image": "ghcr.io/helloaltr/altr-stream:1.0.0-beta",
				"Labels": {
					"com.docker.compose.project": "01-altrstream",
					"com.docker.compose.project.working_dir": "/dev/01 - altr stream"
				}
			},
			"State": {"Status": "running"}
		}]`, "", 0, nil
	}

	engine := NewInstallerEngine(mockExec, &MockHTTPClient{})
	ctx := context.Background()

	status, err := engine.GetStatus(ctx, testDir)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if status.ContainerState != "not_installed" {
		t.Errorf("CRITICAL DEFECT: Dev container was adopted! Expected containerState 'not_installed', got '%s'", status.ContainerState)
	}
	foundIssue := false
	for _, issue := range status.TechnicalIssues {
		if strings.Contains(issue, "development container") && strings.Contains(issue, "not adopt") {
			foundIssue = true
			break
		}
	}
	if !foundIssue {
		t.Errorf("expected technical issue warning about unmanaged dev container, got: %v", status.TechnicalIssues)
	}
}

func TestRemoveContainerByName_RefusesDevContainer(t *testing.T) {
	mockExec := NewMockExecutor()
	mockExec.Handlers["inspect altr-stream-dev"] = func(args []string) (string, string, int, error) {
		return `[{
			"Config": {
				"Image": "altr-stream:dev",
				"Labels": {
					"com.docker.compose.project": "01-altrstream",
					"com.helloaltr.altr-stream.environment": "development"
				}
			},
			"State": {"Status": "running"}
		}]`, "", 0, nil
	}

	lm := NewLifecycleManager(mockExec, &MockHTTPClient{})
	err := lm.RemoveContainerByName(context.Background(), "altr-stream-dev")
	if err == nil {
		t.Fatal("CRITICAL DEFECT: RemoveContainerByName succeeded on development container! Expected error.")
	}
	if !strings.Contains(err.Error(), "development environment") {
		t.Errorf("expected error message mentioning development environment, got: %v", err)
	}
}

// =========================================================================
// REGRESSION TESTS: LIFECYCLE SAFETY AUDIT & REMEDIATION
// =========================================================================

// 1. Default-name container removal with development labels is strictly rejected
func TestRegression_DefaultNameContainerRemovalWithDevelopmentLabels(t *testing.T) {
	mockExec := NewMockExecutor()
	mockExec.Handlers["inspect altr-stream"] = func(args []string) (string, string, int, error) {
		return `[{
			"Config": {
				"Image": "altr-stream:dev",
				"Labels": {
					"com.docker.compose.project": "altr-stream-dev-proj",
					"com.helloaltr.altr-stream.environment": "development"
				}
			},
			"State": {"Status": "running"}
		}]`, "", 0, nil
	}

	lm := NewLifecycleManager(mockExec, &MockHTTPClient{})
	ctx := context.Background()

	// A. RemoveContainer (uses default name altr-stream)
	if err := lm.RemoveContainer(ctx); err == nil {
		t.Fatal("CRITICAL: RemoveContainer succeeded on altr-stream with development labels! Expected rejection.")
	} else if !strings.Contains(err.Error(), "development environment") {
		t.Errorf("expected development environment error, got: %v", err)
	}

	// B. RemoveContainerByName("altr-stream")
	if err := lm.RemoveContainerByName(ctx, "altr-stream"); err == nil {
		t.Fatal("CRITICAL: RemoveContainerByName succeeded on altr-stream with development labels! Expected rejection.")
	}

	// C. RemoveContainerForcefullyByName("altr-stream")
	if err := lm.RemoveContainerForcefullyByName(ctx, "altr-stream"); err == nil {
		t.Fatal("CRITICAL: RemoveContainerForcefullyByName succeeded on altr-stream with development labels! Expected rejection.")
	}

	// Verify docker rm -f was NEVER executed
	for _, call := range mockExec.CallLog {
		if strings.Contains(call, "rm -f altr-stream") {
			t.Fatalf("CRITICAL DEFECT: docker rm -f was executed against development container: %s", call)
		}
	}
}

// 2. Uninstall of a development or unrelated container is strictly rejected
func TestRegression_UninstallDevelopmentOrUnrelatedContainer(t *testing.T) {
	testDir := t.TempDir()

	// A. Development container
	mockExecDev := NewMockExecutor()
	mockExecDev.Handlers["inspect altr-stream"] = func(args []string) (string, string, int, error) {
		return `[{
			"Config": {
				"Image": "altr-stream:dev",
				"Labels": {
					"com.docker.compose.project": "dev-project",
					"com.helloaltr.altr-stream.environment": "development"
				}
			},
			"State": {"Status": "running"}
		}]`, "", 0, nil
	}

	engineDev := NewInstallerEngine(mockExecDev, &MockHTTPClient{})
	engineDev.dockerManager.lookPath = func(file string) (string, error) { return "/usr/local/bin/docker", nil }
	err := engineDev.Uninstall(context.Background(), testDir, false)
	if err == nil {
		t.Fatal("CRITICAL: Uninstall succeeded on development container! Expected rejection.")
	}
	if !strings.Contains(err.Error(), "development environment") {
		t.Errorf("expected development environment error, got: %v", err)
	}
	for _, call := range mockExecDev.CallLog {
		if strings.Contains(call, "stop") || strings.Contains(call, "rm") {
			t.Fatalf("CRITICAL DEFECT: Lifecycle operation executed on dev container during uninstall: %s", call)
		}
	}

	// B. Unrelated third-party container
	mockExecUnrelated := NewMockExecutor()
	mockExecUnrelated.Handlers["inspect altr-stream"] = func(args []string) (string, string, int, error) {
		return `[{
			"Config": {
				"Image": "nginx:alpine",
				"Labels": {}
			},
			"State": {"Status": "running"}
		}]`, "", 0, nil
	}

	engineUnrelated := NewInstallerEngine(mockExecUnrelated, &MockHTTPClient{})
	engineUnrelated.dockerManager.lookPath = func(file string) (string, error) { return "/usr/local/bin/docker", nil }
	err = engineUnrelated.Uninstall(context.Background(), testDir, false)
	if err == nil {
		t.Fatal("CRITICAL: Uninstall succeeded on unrelated container! Expected rejection.")
	}
	if !strings.Contains(err.Error(), "unrelated third-party container") {
		t.Errorf("expected unrelated third-party container error, got: %v", err)
	}
	for _, call := range mockExecUnrelated.CallLog {
		if strings.Contains(call, "stop") || strings.Contains(call, "rm") {
			t.Fatalf("CRITICAL DEFECT: Lifecycle operation executed on unrelated container during uninstall: %s", call)
		}
	}
}

// 3. Forceful removal of a development container is strictly rejected
func TestRegression_ForcefulRemovalDevelopmentContainer(t *testing.T) {
	mockExec := NewMockExecutor()
	mockExec.Handlers["inspect altr-stream-dev"] = func(args []string) (string, string, int, error) {
		return `[{
			"Config": {
				"Image": "altr-stream:dev",
				"Labels": {"com.helloaltr.altr-stream.environment": "development"}
			},
			"State": {"Status": "running"}
		}]`, "", 0, nil
	}

	lm := NewLifecycleManager(mockExec, &MockHTTPClient{})
	err := lm.RemoveContainerForcefullyByName(context.Background(), "altr-stream-dev")
	if err == nil {
		t.Fatal("CRITICAL: RemoveContainerForcefullyByName succeeded on dev container! Expected rejection.")
	}
	if !strings.Contains(err.Error(), "development environment") {
		t.Errorf("expected error mentioning development environment, got: %v", err)
	}
	for _, call := range mockExec.CallLog {
		if strings.Contains(call, "rm -f") {
			t.Fatalf("CRITICAL DEFECT: docker rm -f executed on dev container: %s", call)
		}
	}
}

// 4. Production, test, and development Compose-prefixed volume names
func TestRegression_ComposePrefixedVolumeNames(t *testing.T) {
	ctx := context.Background()

	// A. Production compose-prefixed volume resolved via container inspection
	mockExecProd := NewMockExecutor()
	mockExecProd.Handlers["inspect altr-stream"] = func(args []string) (string, string, int, error) {
		return `[{
			"Config": {"Image": "ghcr.io/helloaltr/altr-stream:1.0.0-beta"},
			"Mounts": [{"Type": "volume", "Name": "altrstream_altr_stream_data", "Destination": "/app/data"}]
		}]`, "", 0, nil
	}
	lmProd := NewLifecycleManager(mockExecProd, &MockHTTPClient{})
	volProd, isBindProd, err := lmProd.ResolveActualDataVolume(ctx, "/path/to/prod", "altr-stream")
	if err != nil {
		t.Fatalf("unexpected error resolving prod volume: %v", err)
	}
	if isBindProd || volProd != "altrstream_altr_stream_data" {
		t.Errorf("expected volume 'altrstream_altr_stream_data', got '%s' (isBind=%v)", volProd, isBindProd)
	}

	// B. Test compose-prefixed volume resolved via directory inspection and compose project label
	mockExecTest := NewMockExecutor()
	testDir := t.TempDir()
	_ = os.WriteFile(filepath.Join(testDir, ".env"), []byte("COMPOSE_PROJECT_NAME=altr-stream-test\n"), 0644)
	_ = os.WriteFile(filepath.Join(testDir, "docker-compose.yml"), []byte("volumes:\n  altr_stream_data:\n"), 0644)
	mockExecTest.Handlers["volume inspect altr-stream-test_altr_stream_data"] = func(args []string) (string, string, int, error) {
		return `[{
			"Name": "altr-stream-test_altr_stream_data",
			"Labels": {
				"com.docker.compose.project": "altr-stream-test",
				"com.docker.compose.volume": "altr_stream_data"
			}
		}]`, "", 0, nil
	}
	lmTest := NewLifecycleManager(mockExecTest, &MockHTTPClient{})
	lmTest.ContainerName = "altr-stream-test"
	volTest, isBindTest, err := lmTest.ResolveActualDataVolume(ctx, testDir, "altr-stream-test")
	if err != nil {
		t.Fatalf("unexpected error resolving test volume: %v", err)
	}
	if isBindTest || volTest != "altr-stream-test_altr_stream_data" {
		t.Errorf("expected volume 'altr-stream-test_altr_stream_data', got '%s' (isBind=%v)", volTest, isBindTest)
	}

	// C. Dev container volume resolution is strictly rejected
	mockExecDev := NewMockExecutor()
	mockExecDev.Handlers["inspect altr-stream-dev"] = func(args []string) (string, string, int, error) {
		return `[{
			"Config": {
				"Image": "altr-stream:dev",
				"Labels": {"com.helloaltr.altr-stream.environment": "development"}
			},
			"Mounts": [{"Type": "volume", "Name": "altr-stream-dev_data", "Destination": "/app/data"}]
		}]`, "", 0, nil
	}
	lmDev := NewLifecycleManager(mockExecDev, &MockHTTPClient{})
	_, _, err = lmDev.ResolveActualDataVolume(ctx, testDir, "altr-stream-dev")
	if err == nil {
		t.Fatal("CRITICAL: ResolveActualDataVolume succeeded on development container! Expected rejection.")
	}
}

// 5. Unlabelled or ambiguous volume aborts destructive cleanup
func TestRegression_UnlabelledOrAmbiguousVolume_AbortsDestructiveCleanup(t *testing.T) {
	ctx := context.Background()

	// A. Unlabelled volume in custom directory without container inspection
	mockExecUnlabelled := NewMockExecutor()
	testDir := t.TempDir()
	_ = os.WriteFile(filepath.Join(testDir, "docker-compose.yml"), []byte("volumes:\n  altr_stream_data:\n"), 0644)
	mockExecUnlabelled.Handlers["volume inspect altr_stream_data"] = func(args []string) (string, string, int, error) {
		// Volume exists in Docker but has NO labels associating it with this installation directory
		return `[{"Name": "altr_stream_data", "Labels": {}}]`, "", 0, nil
	}

	lm := NewLifecycleManager(mockExecUnlabelled, &MockHTTPClient{})
	_, _, err := lm.ResolveActualDataVolume(ctx, testDir, "")
	if err == nil {
		t.Fatal("CRITICAL: ResolveActualDataVolume succeeded on unlabelled ambiguous volume! Expected abortion.")
	}
	if !strings.Contains(err.Error(), "ambiguous ownership") {
		t.Errorf("expected error mentioning ambiguous ownership, got: %v", err)
	}

	// B. Test instance attempting to delete production altr_stream_data is aborted
	mockExecTestProd := NewMockExecutor()
	testDir2 := t.TempDir()
	_ = os.WriteFile(filepath.Join(testDir2, ".env"), []byte("ALTR_STREAM_CONTAINER_NAME=altr-stream-test\n"), 0644)
	_ = os.WriteFile(filepath.Join(testDir2, "docker-compose.yml"), []byte("volumes:\n  altr_stream_data:\n"), 0644)
	mockExecTestProd.Handlers["volume inspect altr_stream_data"] = func(args []string) (string, string, int, error) {
		return `[{"Name": "altr_stream_data", "Labels": {}}]`, "", 0, nil
	}
	lmTest := NewLifecycleManager(mockExecTestProd, &MockHTTPClient{})
	lmTest.ContainerName = "altr-stream-test"
	lmTest.DataVolume = "altr_stream_test_data"
	_, _, err = lmTest.ResolveActualDataVolume(ctx, testDir2, "altr-stream-test")
	if err == nil {
		t.Fatal("CRITICAL: Test instance succeeded in resolving production volume altr_stream_data! Expected safety abortion.")
	}
}

// 6. Data-preserving uninstall preserves volumes and directories
func TestRegression_DataPreservingUninstall(t *testing.T) {
	mockExec := NewMockExecutor()
	testDir := t.TempDir()
	dataFile := filepath.Join(testDir, "node_identity.key")
	_ = os.WriteFile(dataFile, []byte("secret-key"), 0644)
	_ = os.WriteFile(filepath.Join(testDir, "docker-compose.yml"), []byte("services: {}\n"), 0644)
	_ = os.WriteFile(filepath.Join(testDir, ".env"), []byte("ALTR_STREAM_PORT=8000\n"), 0644)

	mockExec.Handlers["inspect altr-stream"] = func(args []string) (string, string, int, error) {
		return `[{"State":{"Status":"running","Running":true},"Config":{"Image":"ghcr.io/helloaltr/altr-stream:1.0.0-beta"}}]`, "", 0, nil
	}
	mockExec.Handlers["stop"] = func(args []string) (string, string, int, error) { return "altr-stream", "", 0, nil }
	mockExec.Handlers["rm -f altr-stream"] = func(args []string) (string, string, int, error) { return "altr-stream", "", 0, nil }

	engine := NewInstallerEngine(mockExec, &MockHTTPClient{})
	engine.dockerManager.lookPath = func(file string) (string, error) { return "/usr/local/bin/docker", nil }

	// Run uninstall with deleteData = false (the default)
	err := engine.Uninstall(context.Background(), testDir, false)
	if err != nil {
		t.Fatalf("Uninstall failed: %v", err)
	}

	// Verify data volume rm was NEVER called
	for _, call := range mockExec.CallLog {
		if strings.Contains(call, "volume rm") {
			t.Fatalf("CRITICAL DEFECT: volume rm was executed during data-preserving uninstall: %s", call)
		}
	}

	// Verify directory and data file still exist
	if _, err := os.Stat(testDir); os.IsNotExist(err) {
		t.Fatalf("CRITICAL DEFECT: installation directory was deleted during data-preserving uninstall")
	}
	if _, err := os.Stat(dataFile); os.IsNotExist(err) {
		t.Fatalf("CRITICAL DEFECT: persistent data file was deleted during data-preserving uninstall")
	}
}

// 7. Explicit data deletion targets only the selected instance's verified volume
func TestRegression_ExplicitDataDeletion_TargetsOnlySelectedInstance(t *testing.T) {
	mockExec := NewMockExecutor()
	testDir := t.TempDir()
	_ = os.WriteFile(filepath.Join(testDir, ".env"), []byte("ALTR_STREAM_CONTAINER_NAME=altr-stream-test\nALTR_STREAM_DATA_VOLUME=altr_stream_test_data\nALTR_STREAM_PORT=8001\n"), 0644)

	var testVolumeDeleted bool
	mockExec.Handlers["inspect altr-stream-test"] = func(args []string) (string, string, int, error) {
		return `[{
			"Config": {"Image": "ghcr.io/helloaltr/altr-stream:1.0.0-beta"},
			"Mounts": [{"Type": "volume", "Name": "altr_stream_test_data", "Destination": "/app/data"}],
			"State": {"Status": "running", "Running": true}
		}]`, "", 0, nil
	}
	mockExec.Handlers["stop"] = func(args []string) (string, string, int, error) { return "altr-stream-test", "", 0, nil }
	mockExec.Handlers["rm -f altr-stream-test"] = func(args []string) (string, string, int, error) { return "altr-stream-test", "", 0, nil }
	mockExec.Handlers["volume rm altr_stream_test_data"] = func(args []string) (string, string, int, error) {
		testVolumeDeleted = true
		return "altr_stream_test_data", "", 0, nil
	}

	engine := NewInstallerEngine(mockExec, &MockHTTPClient{})
	engine.dockerManager.lookPath = func(file string) (string, error) { return "/usr/local/bin/docker", nil }

	err := engine.Uninstall(context.Background(), testDir, true)
	if err != nil {
		t.Fatalf("Uninstall failed: %v", err)
	}

	if !testVolumeDeleted {
		t.Fatal("expected test volume 'altr_stream_test_data' to be removed")
	}

	// Strictly verify production container and volume were NEVER targeted
	for _, call := range mockExec.CallLog {
		for _, w := range strings.Fields(call) {
			if w == "altr-stream" {
				t.Fatalf("CRITICAL DEFECT: Production container 'altr-stream' was targeted in call: %s", call)
			}
			if w == "altr_stream_data" {
				t.Fatalf("CRITICAL DEFECT: Production volume 'altr_stream_data' was targeted in call: %s", call)
			}
		}
	}
}

// 8. Volume-removal and directory-cleanup failures are visible
func TestRegression_UninstallFailuresVisible(t *testing.T) {
	// A. Volume removal failure
	mockExecVolFail := NewMockExecutor()
	testDir := t.TempDir()
	_ = os.WriteFile(filepath.Join(testDir, ".env"), []byte("ALTR_STREAM_DATA_VOLUME=altr_stream_data\n"), 0644)
	mockExecVolFail.Handlers["inspect altr-stream"] = func(args []string) (string, string, int, error) {
		return `[{
			"Config": {"Image": "ghcr.io/helloaltr/altr-stream:1.0.0-beta"},
			"Mounts": [{"Type": "volume", "Name": "altr_stream_data", "Destination": "/app/data"}],
			"State": {"Status": "exited"}
		}]`, "", 0, nil
	}
	mockExecVolFail.Handlers["rm -f altr-stream"] = func(args []string) (string, string, int, error) { return "altr-stream", "", 0, nil }
	mockExecVolFail.Handlers["volume rm altr_stream_data"] = func(args []string) (string, string, int, error) {
		return "", "Error response from daemon: volume is in use by another container", 1, errors.New("volume in use")
	}

	engineVolFail := NewInstallerEngine(mockExecVolFail, &MockHTTPClient{})
	engineVolFail.dockerManager.lookPath = func(file string) (string, error) { return "/usr/local/bin/docker", nil }
	err := engineVolFail.Uninstall(context.Background(), testDir, true)
	if err == nil {
		t.Fatal("CRITICAL: Uninstall succeeded despite volume removal failure! Expected visible error.")
	}
	if !strings.Contains(err.Error(), "volume removal failed") {
		t.Errorf("expected error mentioning volume removal failure, got: %v", err)
	}
}

// 9. Version-switch rollback without affecting another instance
func TestRegression_VersionSwitchRollback_DoesNotAffectAnotherInstance(t *testing.T) {
	mockExec := NewMockExecutor()
	testDir := t.TempDir()
	_ = os.WriteFile(filepath.Join(testDir, "docker-compose.yml"), []byte("image: ghcr.io/helloaltr/altr-stream:1.0.0-beta\n"), 0644)
	_ = os.WriteFile(filepath.Join(testDir, ".env"), []byte("ALTR_STREAM_CONTAINER_NAME=altr-stream-test\nALTR_STREAM_PORT=8001\n"), 0644)

	mockExec.Handlers["manifest inspect"] = func(args []string) (string, string, int, error) {
		return `{"schemaVersion": 2}`, "", 0, nil
	}
	mockExec.Handlers["pull"] = func(args []string) (string, string, int, error) {
		return "Downloaded newer image", "", 0, nil
	}
	mockExec.Handlers["inspect -f {{.Config.Image}} altr-stream-test"] = func(args []string) (string, string, int, error) {
		return "ghcr.io/helloaltr/altr-stream:1.0.0-beta", "", 0, nil
	}
	mockExec.Handlers["inspect altr-stream-test"] = func(args []string) (string, string, int, error) {
		return `[{"State":{"Status":"running","Running":true},"Config":{"Image":"ghcr.io/helloaltr/altr-stream:1.0.0-beta"},"NetworkSettings":{"Ports":{"8000/tcp":[{"HostPort":"8001"}]}}}]`, "", 0, nil
	}
	mockExec.Handlers["rm -f altr-stream-test"] = func(args []string) (string, string, int, error) {
		return "altr-stream-test", "", 0, nil
	}
	mockExec.Handlers["up -d"] = func(args []string) (string, string, int, error) {
		return "Started altr-stream-test", "", 0, nil
	}

	// HTTP client fails health check on new version, triggering rollback
	callCount := 0
	mockClient := &MockHTTPClient{
		DoFunc: func(req *http.Request) (*http.Response, error) {
			callCount++
			if callCount <= 1 {
				// Initial switch healthcheck fails
				return nil, errors.New("connection refused")
			}
			// Restored rollback healthcheck succeeds
			return &http.Response{
				StatusCode: 200,
				Body:       io.NopCloser(strings.NewReader(`{"status":"ok","version":"1.0.0-beta"}`)),
			}, nil
		},
	}

	engine := NewInstallerEngine(mockExec, mockClient)
	engine.dockerManager.lookPath = func(file string) (string, error) { return "/usr/local/bin/docker", nil }

	err := engine.SwitchVersion(context.Background(), testDir, InstallConfig{
		TargetDir:     testDir,
		Version:       "1.0.1-beta",
		Image:         "ghcr.io/helloaltr/altr-stream:1.0.1-beta",
		Port:          8001,
		HealthTimeout: 1,
	}, nil)

	if err == nil {
		t.Fatal("expected SwitchVersion to fail and rollback, got nil")
	}
	if !strings.Contains(err.Error(), "Successfully rolled back") {
		t.Errorf("expected clean rollback message, got: %v", err)
	}

	// Strictly verify production container was NEVER touched
	for _, call := range mockExec.CallLog {
		for _, w := range strings.Fields(call) {
			if w == "altr-stream" {
				t.Fatalf("CRITICAL DEFECT: Production container 'altr-stream' was touched during test instance switch/rollback: %s", call)
			}
			if w == "altr_stream_data" {
				t.Fatalf("CRITICAL DEFECT: Production volume 'altr_stream_data' was touched: %s", call)
			}
		}
	}
}

// 10. Regression test: Compose installations do not execute raw 'docker volume create', preventing orphan unlabelled volumes
func TestRegression_ComposeInstall_DoesNotCreateOrphanUnprefixedVolume(t *testing.T) {
	mockExec := NewMockExecutor()
	testDir := t.TempDir()

	containerStarted := false
	mockExec.Handlers["up -d"] = func(args []string) (string, string, int, error) {
		containerStarted = true
		return "Container altr-stream Started", "", 0, nil
	}
	mockExec.Handlers["inspect altr-stream"] = func(args []string) (string, string, int, error) {
		if !containerStarted {
			return "[]", "No such container", 1, nil
		}
		return `[{
			"Id": "abc123456789",
			"State": {"Status": "running", "Running": true, "ExitCode": 0, "Error": ""},
			"Config": {"Image": "ghcr.io/helloaltr/altr-stream:1.0.0-beta"},
			"NetworkSettings": {"Ports": {"8000/tcp": [{"HostIp": "0.0.0.0", "HostPort": "8000"}]}}
		}]`, "", 0, nil
	}

	mockHTTP := &MockHTTPClient{
		DoFunc: func(req *http.Request) (*http.Response, error) {
			return &http.Response{
				StatusCode: 200,
				Body:       io.NopCloser(bytes.NewBufferString(`{"status":"healthy","version":"1.0.0-beta"}`)),
			}, nil
		},
	}

	engine := NewInstallerEngine(mockExec, mockHTTP)
	engine.dockerManager.lookPath = func(file string) (string, error) { return "/usr/local/bin/docker", nil }

	cfg := InstallConfig{
		TargetDir:     testDir,
		Version:       "1.0.0-beta",
		Image:         "ghcr.io/helloaltr/altr-stream:1.0.0-beta",
		Port:          8000,
		HealthTimeout: 5,
	}

	// Install should succeed
	err := engine.Install(context.Background(), cfg, nil)
	if err != nil {
		t.Fatalf("Install failed: %v", err)
	}

	// Assert that raw 'volume create' was NEVER executed
	for _, call := range mockExec.CallLog {
		if strings.Contains(call, "volume create") {
			t.Fatalf("CRITICAL DEFECT: raw volume create was executed during Compose installation, creating orphan volume: %s", call)
		}
	}
}

// 11. Regression test: Standalone EnsureDataVolume still creates volume when Compose is absent
func TestRegression_StandaloneEnsureDataVolume_CreatesVolumeWhenNoCompose(t *testing.T) {
	mockExec := NewMockExecutor()
	emptyDir := t.TempDir() // empty directory, no docker-compose.yml

	volumeCreated := false
	mockExec.Handlers["volume create altr_stream_data"] = func(args []string) (string, string, int, error) {
		volumeCreated = true
		return "altr_stream_data", "", 0, nil
	}

	lm := NewLifecycleManager(mockExec, &MockHTTPClient{})
	lm.dockerManager.lookPath = func(file string) (string, error) { return "/usr/local/bin/docker", nil }

	// A. EnsureDataVolumeForTarget on directory without docker-compose.yml must fall back to volume create
	err := lm.EnsureDataVolumeForTarget(context.Background(), emptyDir)
	if err != nil {
		t.Fatalf("EnsureDataVolumeForTarget failed: %v", err)
	}
	if !volumeCreated {
		t.Errorf("expected volume create to be called when docker-compose.yml is absent")
	}

	// Reset flag and test direct EnsureDataVolume
	volumeCreated = false
	err = lm.EnsureDataVolume(context.Background())
	if err != nil {
		t.Fatalf("EnsureDataVolume failed: %v", err)
	}
	if !volumeCreated {
		t.Errorf("expected volume create to be called by direct EnsureDataVolume")
	}
}

// 12. Regression test: Prefixed Compose volume is preserved and selected, never replaced with unprefixed volume
func TestRegression_ComposeInstall_PrefixedVolumePreservedAndSelected(t *testing.T) {
	mockExec := NewMockExecutor()
	testDir := t.TempDir()

	// Compose file declaring volume altr_stream_data
	composeContent := `services:
  altr-stream:
    image: ghcr.io/helloaltr/altr-stream:1.0.0-beta
    volumes:
      - altr_stream_data:/app/data
volumes:
  altr_stream_data:
    driver: local
`
	_ = os.WriteFile(filepath.Join(testDir, "docker-compose.yml"), []byte(composeContent), 0644)
	_ = os.WriteFile(filepath.Join(testDir, ".env"), []byte("COMPOSE_PROJECT_NAME=myproject\n"), 0644)

	// Container is running with prefixed volume myproject_altr_stream_data mounted at /app/data
	mockExec.Handlers["inspect altr-stream"] = func(args []string) (string, string, int, error) {
		return `[{
			"Config": {
				"Image": "ghcr.io/helloaltr/altr-stream:1.0.0-beta",
				"Labels": {
					"com.docker.compose.project": "myproject",
					"com.helloaltr.altr-stream.managed-by": "installer"
				}
			},
			"Mounts": [{
				"Type": "volume",
				"Name": "myproject_altr_stream_data",
				"Destination": "/app/data"
			}],
			"State": {"Status": "running"}
		}]`, "", 0, nil
	}

	lm := NewLifecycleManager(mockExec, &MockHTTPClient{})
	lm.dockerManager.lookPath = func(file string) (string, error) { return "/usr/local/bin/docker", nil }

	vol, isBind, err := lm.ResolveActualDataVolume(context.Background(), testDir, "altr-stream")
	if err != nil {
		t.Fatalf("ResolveActualDataVolume failed: %v", err)
	}
	if isBind {
		t.Errorf("expected isBind=false")
	}
	if vol != "myproject_altr_stream_data" {
		t.Errorf("expected resolved volume 'myproject_altr_stream_data', got '%s'", vol)
	}
}

// 13. Regression test: Comprehensive EnsureDataVolumeForTarget validation
func TestRegression_EnsureDataVolumeForTarget_DetailedValidation(t *testing.T) {
	ctx := context.Background()

	setupLM := func() (*LifecycleManager, *[]string) {
		mockExec := NewMockExecutor()
		var calls []string
		mockExec.Handlers["volume create altr_stream_data"] = func(args []string) (string, string, int, error) {
			calls = append(calls, "volume create altr_stream_data")
			return "altr_stream_data", "", 0, nil
		}
		mockExec.Handlers["volume create altr_stream_test_data"] = func(args []string) (string, string, int, error) {
			calls = append(calls, "volume create altr_stream_test_data")
			return "altr_stream_test_data", "", 0, nil
		}
		lm := NewLifecycleManager(mockExec, &MockHTTPClient{})
		lm.dockerManager.lookPath = func(file string) (string, error) { return "/usr/local/bin/docker", nil }
		return lm, &calls
	}

	// Case 1: Standard valid Compose YAML -> skips volume create
	t.Run("StandardValidCompose", func(t *testing.T) {
		lm, calls := setupLM()
		dir := t.TempDir()
		compose := `services:
  altr-stream:
    volumes:
      - altr_stream_data:/app/data
      - ./data/updates:/app/data/updates
volumes:
  altr_stream_data:
    driver: local
`
		_ = os.WriteFile(filepath.Join(dir, "docker-compose.yml"), []byte(compose), 0644)
		if err := lm.EnsureDataVolumeForTarget(ctx, dir); err != nil {
			t.Fatalf("EnsureDataVolumeForTarget failed: %v", err)
		}
		if len(*calls) != 0 {
			t.Errorf("expected no volume create calls for valid Compose, got: %v", *calls)
		}
	})

	// Case 2: Custom volume name via .env -> skips volume create for custom volume
	t.Run("CustomVolumeFromEnv", func(t *testing.T) {
		lm, calls := setupLM()
		dir := t.TempDir()
		_ = os.WriteFile(filepath.Join(dir, ".env"), []byte("ALTR_STREAM_DATA_VOLUME=altr_stream_test_data\n"), 0644)
		compose := `services:
  altr-stream-test:
    volumes:
      - altr_stream_test_data:/app/data
volumes:
  altr_stream_test_data:
    driver: local
`
		_ = os.WriteFile(filepath.Join(dir, "docker-compose.yml"), []byte(compose), 0644)
		if err := lm.EnsureDataVolumeForTarget(ctx, dir); err != nil {
			t.Fatalf("EnsureDataVolumeForTarget failed: %v", err)
		}
		if len(*calls) != 0 {
			t.Errorf("expected no volume create calls for custom Compose volume, got: %v", *calls)
		}
	})

	// Case 3: Custom volume name via explicit parameter
	t.Run("CustomVolumeExplicitParam", func(t *testing.T) {
		lm, calls := setupLM()
		dir := t.TempDir()
		compose := `services:
  altr-stream-test:
    volumes:
      - altr_stream_test_data:/app/data
volumes:
  altr_stream_test_data:
    driver: local
`
		_ = os.WriteFile(filepath.Join(dir, "docker-compose.yml"), []byte(compose), 0644)
		if err := lm.EnsureDataVolumeForTarget(ctx, dir, "altr_stream_test_data"); err != nil {
			t.Fatalf("EnsureDataVolumeForTarget failed: %v", err)
		}
		if len(*calls) != 0 {
			t.Errorf("expected no volume create calls when custom volume matches explicit param, got: %v", *calls)
		}
	})

	// Case 4: Commented-out volume declarations -> must fall back to standalone volume create
	t.Run("CommentedOutDeclarations", func(t *testing.T) {
		lm, calls := setupLM()
		dir := t.TempDir()
		compose := `services:
  altr-stream:
    # volumes:
    #   - altr_stream_data:/app/data
# volumes:
#   altr_stream_data:
#     driver: local
`
		_ = os.WriteFile(filepath.Join(dir, "docker-compose.yml"), []byte(compose), 0644)
		if err := lm.EnsureDataVolumeForTarget(ctx, dir); err != nil {
			t.Fatalf("EnsureDataVolumeForTarget failed: %v", err)
		}
		if len(*calls) != 1 || (*calls)[0] != "volume create altr_stream_data" {
			t.Errorf("expected standalone volume create for commented-out Compose, got: %v", *calls)
		}
	})

	// Case 5: Unrelated named volumes -> must fall back to standalone volume create
	t.Run("UnrelatedNamedVolumes", func(t *testing.T) {
		lm, calls := setupLM()
		dir := t.TempDir()
		compose := `services:
  cache:
    volumes:
      - redis_data:/data
volumes:
  redis_data:
    driver: local
`
		_ = os.WriteFile(filepath.Join(dir, "docker-compose.yml"), []byte(compose), 0644)
		if err := lm.EnsureDataVolumeForTarget(ctx, dir); err != nil {
			t.Fatalf("EnsureDataVolumeForTarget failed: %v", err)
		}
		if len(*calls) != 1 || (*calls)[0] != "volume create altr_stream_data" {
			t.Errorf("expected standalone volume create for unrelated volumes, got: %v", *calls)
		}
	})

	// Case 6: Bind mounts only -> must fall back to standalone volume create
	t.Run("BindMountsOnly", func(t *testing.T) {
		lm, calls := setupLM()
		dir := t.TempDir()
		compose := `services:
  altr-stream:
    volumes:
      - ./data/updates:/app/data/updates
      - ./data:/app/data
`
		_ = os.WriteFile(filepath.Join(dir, "docker-compose.yml"), []byte(compose), 0644)
		if err := lm.EnsureDataVolumeForTarget(ctx, dir); err != nil {
			t.Fatalf("EnsureDataVolumeForTarget failed: %v", err)
		}
		if len(*calls) != 1 || (*calls)[0] != "volume create altr_stream_data" {
			t.Errorf("expected standalone volume create for bind-mount-only Compose, got: %v", *calls)
		}
	})

	// Case 7: Missing top-level volume declaration -> must fall back to standalone volume create
	t.Run("MissingTopLevelVolume", func(t *testing.T) {
		lm, calls := setupLM()
		dir := t.TempDir()
		compose := `services:
  altr-stream:
    volumes:
      - altr_stream_data:/app/data
`
		_ = os.WriteFile(filepath.Join(dir, "docker-compose.yml"), []byte(compose), 0644)
		if err := lm.EnsureDataVolumeForTarget(ctx, dir); err != nil {
			t.Fatalf("EnsureDataVolumeForTarget failed: %v", err)
		}
		if len(*calls) != 1 || (*calls)[0] != "volume create altr_stream_data" {
			t.Errorf("expected standalone volume create when top-level volume declaration is missing, got: %v", *calls)
		}
	})

	// Case 8: Missing service mount declaration -> must fall back to standalone volume create
	t.Run("MissingServiceMount", func(t *testing.T) {
		lm, calls := setupLM()
		dir := t.TempDir()
		compose := `services:
  altr-stream:
    ports:
      - "8000:8000"
volumes:
  altr_stream_data:
    driver: local
`
		_ = os.WriteFile(filepath.Join(dir, "docker-compose.yml"), []byte(compose), 0644)
		if err := lm.EnsureDataVolumeForTarget(ctx, dir); err != nil {
			t.Fatalf("EnsureDataVolumeForTarget failed: %v", err)
		}
		if len(*calls) != 1 || (*calls)[0] != "volume create altr_stream_data" {
			t.Errorf("expected standalone volume create when service mount is missing, got: %v", *calls)
		}
	})

	// Case 9: Malformed YAML -> must fall back to standalone volume create
	t.Run("MalformedYAML", func(t *testing.T) {
		lm, calls := setupLM()
		dir := t.TempDir()
		_ = os.WriteFile(filepath.Join(dir, "docker-compose.yml"), []byte("volumes: { malformed: [ syntax\nservices:\n"), 0644)
		if err := lm.EnsureDataVolumeForTarget(ctx, dir); err != nil {
			t.Fatalf("EnsureDataVolumeForTarget failed: %v", err)
		}
		if len(*calls) != 1 || (*calls)[0] != "volume create altr_stream_data" {
			t.Errorf("expected standalone volume create for malformed YAML, got: %v", *calls)
		}
	})

	// Case 10: Missing docker-compose.yml -> must fall back to standalone volume create
	t.Run("MissingComposeFile", func(t *testing.T) {
		lm, calls := setupLM()
		emptyDir := t.TempDir()
		if err := lm.EnsureDataVolumeForTarget(ctx, emptyDir); err != nil {
			t.Fatalf("EnsureDataVolumeForTarget failed: %v", err)
		}
		if len(*calls) != 1 || (*calls)[0] != "volume create altr_stream_data" {
			t.Errorf("expected standalone volume create for missing Compose file, got: %v", *calls)
		}
	})
}

// 14. Unit tests for hasDeclaredComposeDataVolume scanner
func TestHasDeclaredComposeDataVolume(t *testing.T) {
	tests := []struct {
		name        string
		content     string
		expectedVol string
		want        bool
	}{
		{
			name: "StandardValid",
			content: `services:
  altr-stream:
    volumes:
      - altr_stream_data:/app/data
volumes:
  altr_stream_data:
    driver: local`,
			expectedVol: "altr_stream_data",
			want:        true,
		},
		{
			name: "ValidWithQuotes",
			content: `services:
  altr-stream:
    volumes:
      - "altr_stream_data:/app/data"
volumes:
  "altr_stream_data":
    driver: local`,
			expectedVol: "altr_stream_data",
			want:        true,
		},
		{
			name: "ValidWithMountFlags",
			content: `services:
  altr-stream:
    volumes:
      - altr_stream_data:/app/data:rw
volumes:
  altr_stream_data:
    driver: local`,
			expectedVol: "altr_stream_data",
			want:        true,
		},
		{
			name: "CustomVolumeName",
			content: `services:
  altr-stream-test:
    volumes:
      - altr_stream_test_data:/app/data
volumes:
  altr_stream_test_data:
    driver: local`,
			expectedVol: "altr_stream_test_data",
			want:        true,
		},
		{
			name: "CommentedOut",
			content: `# services:
#   altr-stream:
#     volumes:
#       - altr_stream_data:/app/data
# volumes:
#   altr_stream_data:`,
			expectedVol: "altr_stream_data",
			want:        false,
		},
		{
			name: "InlineCommentIgnored",
			content: `services:
  altr-stream:
    volumes:
      - altr_stream_data:/app/data # persistent mount
volumes:
  altr_stream_data: # local volume
    driver: local`,
			expectedVol: "altr_stream_data",
			want:        true,
		},
		{
			name: "UnrelatedVolume",
			content: `services:
  cache:
    volumes:
      - redis_data:/data
volumes:
  redis_data:`,
			expectedVol: "altr_stream_data",
			want:        false,
		},
		{
			name: "BindMountOnly",
			content: `services:
  altr-stream:
    volumes:
      - ./data:/app/data
volumes:
  altr_stream_data:`,
			expectedVol: "altr_stream_data",
			want:        false,
		},
		{
			name: "MissingTopLevelVolume",
			content: `services:
  altr-stream:
    volumes:
      - altr_stream_data:/app/data`,
			expectedVol: "altr_stream_data",
			want:        false,
		},
		{
			name: "MissingServiceMount",
			content: `services:
  altr-stream:
    ports:
      - "8000:8000"
volumes:
  altr_stream_data:`,
			expectedVol: "altr_stream_data",
			want:        false,
		},
		{
			name:        "EmptyContent",
			content:     "",
			expectedVol: "altr_stream_data",
			want:        false,
		},
		{
			name:        "EmptyExpectedVol",
			content:     "services:\n  altr-stream:\n",
			expectedVol: "",
			want:        false,
		},
		{
			name: "MalformedYAML",
			content: `services: [broken
volumes: {also broken`,
			expectedVol: "altr_stream_data",
			want:        false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := hasDeclaredComposeDataVolume(tt.content, tt.expectedVol)
			if got != tt.want {
				t.Errorf("hasDeclaredComposeDataVolume() = %v, want %v", got, tt.want)
			}
		})
	}
}

// 15. Regression test: resolveConfig preserves explicit target versions and images without falling back to default
func TestRegression_ResolveConfig_ExplicitVersionAndImage(t *testing.T) {
	// A. Explicit version resolves to exact canonical image
	cfgA := resolveConfig("/test", "0.13.7-alpha", "", 8000, "altr-stream", "altr_stream_data", "production")
	if cfgA.Version != "0.13.7-alpha" {
		t.Errorf("expected version 0.13.7-alpha, got: %s", cfgA.Version)
	}
	if cfgA.Image != "ghcr.io/helloaltr/altr-stream:0.13.7-alpha" {
		t.Errorf("expected image ghcr.io/helloaltr/altr-stream:0.13.7-alpha, got: %s", cfgA.Image)
	}

	// B. Explicit image with tag resolves to exact version tag
	cfgB := resolveConfig("/test", "", "ghcr.io/helloaltr/altr-stream:0.13.7-alpha", 8000, "altr-stream", "altr_stream_data", "production")
	if cfgB.Version != "0.13.7-alpha" {
		t.Errorf("expected version 0.13.7-alpha extracted from image, got: %s", cfgB.Version)
	}
	if cfgB.Image != "ghcr.io/helloaltr/altr-stream:0.13.7-alpha" {
		t.Errorf("expected image ghcr.io/helloaltr/altr-stream:0.13.7-alpha, got: %s", cfgB.Image)
	}

	// C. Explicit v-prefixed version is normalized
	cfgC := resolveConfig("/test", "v0.13.7-alpha", "", 8000, "altr-stream", "altr_stream_data", "production")
	if cfgC.Image != "ghcr.io/helloaltr/altr-stream:0.13.7-alpha" {
		t.Errorf("expected v-prefixed version to generate clean image, got: %s", cfgC.Image)
	}

	// D. Both empty falls back to DefaultVersion and DefaultImage
	cfgD := resolveConfig("/test", "", "", 8000, "altr-stream", "altr_stream_data", "production")
	if cfgD.Version != DefaultVersion || cfgD.Image != DefaultImage {
		t.Errorf("expected default fallback, got version %s, image %s", cfgD.Version, cfgD.Image)
	}
}

// 16. Regression test: SwitchVersion preserves target version and image unchanged through all stages
func TestRegression_SwitchVersion_ExplicitTargetPropagation(t *testing.T) {
	mockExec := NewMockExecutor()
	testDir := t.TempDir()

	// Initial container running 1.0.0-beta
	mockExec.Handlers["inspect -f {{.Config.Image}} altr-stream"] = func(args []string) (string, string, int, error) {
		return "ghcr.io/helloaltr/altr-stream:1.0.0-beta", "", 0, nil
	}
	mockExec.Handlers["manifest inspect ghcr.io/helloaltr/altr-stream:0.13.7-alpha"] = func(args []string) (string, string, int, error) {
		return `{"schemaVersion": 2, "mediaType": "application/vnd.oci.image.index.v1+json"}`, "", 0, nil
	}
	mockExec.Handlers["info"] = func(args []string) (string, string, int, error) {
		return "Docker info output", "", 0, nil
	}
	var pulledImage string
	mockExec.Handlers["pull ghcr.io/helloaltr/altr-stream:0.13.7-alpha"] = func(args []string) (string, string, int, error) {
		pulledImage = "ghcr.io/helloaltr/altr-stream:0.13.7-alpha"
		return "Image pulled", "", 0, nil
	}
	mockExec.Handlers["stop"] = func(args []string) (string, string, int, error) {
		return "altr-stream", "", 0, nil
	}
	mockExec.Handlers["rm -f altr-stream"] = func(args []string) (string, string, int, error) {
		return "altr-stream", "", 0, nil
	}
	mockExec.Handlers["inspect altr-stream"] = func(args []string) (string, string, int, error) {
		return `[{
			"State": {"Status": "running", "Running": true},
			"Config": {"Image": "ghcr.io/helloaltr/altr-stream:0.13.7-alpha"},
			"NetworkSettings": {"Ports": {"8000/tcp": [{"HostPort": "8000"}]}}
		}]`, "", 0, nil
	}
	mockExec.Handlers["exec altr-stream curl -f -s http://localhost:8000/api/v1/health"] = func(args []string) (string, string, int, error) {
		return `{"status": "healthy", "version": "0.13.7-alpha"}`, "", 0, nil
	}

	mockHTTP := &MockHTTPClient{
		DoFunc: func(req *http.Request) (*http.Response, error) {
			return &http.Response{
				StatusCode: 200,
				Body:       io.NopCloser(bytes.NewBufferString(`{"status":"healthy","version":"0.13.7-alpha"}`)),
			}, nil
		},
	}

	engine := NewInstallerEngine(mockExec, mockHTTP)
	engine.dockerManager.lookPath = func(file string) (string, error) { return "/usr/local/bin/docker", nil }

	cfg := InstallConfig{
		TargetDir:     testDir,
		Version:       "0.13.7-alpha",
		Image:         "ghcr.io/helloaltr/altr-stream:0.13.7-alpha",
		Port:          8000,
		HealthTimeout: 5,
	}

	var stagesReported []string
	err := engine.SwitchVersion(context.Background(), testDir, cfg, func(p InstallProgress) {
		stagesReported = append(stagesReported, string(p.Stage))
	})

	if err != nil {
		t.Fatalf("SwitchVersion failed: %v", err)
	}

	if pulledImage != "ghcr.io/helloaltr/altr-stream:0.13.7-alpha" {
		t.Errorf("CRITICAL: expected target image 0.13.7-alpha to be pulled, got: %s", pulledImage)
	}

	// Verify runtime files have target version and image
	envData, _ := os.ReadFile(filepath.Join(testDir, ".env"))
	if !strings.Contains(string(envData), "ghcr.io/helloaltr/altr-stream:0.13.7-alpha") {
		t.Errorf("expected .env to contain switched image 0.13.7-alpha, got: %s", string(envData))
	}
}
