//go:build darwin

package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"syscall"
	"time"
)

func setDetachedProcess(cmd *exec.Cmd) {
	cmd.SysProcAttr = &syscall.SysProcAttr{
		Setpgid: true,
	}
}

func getPlatformOfficialDockerURL() string {
	if runtime.GOARCH == "arm64" {
		return "https://desktop.docker.com/mac/main/arm64/Docker.dmg"
	}
	return "https://desktop.docker.com/mac/main/amd64/Docker.dmg"
}

func getPlatformDockerCLICandidates(home string) []string {
	return []string{
		"/opt/homebrew/bin/docker",
		"/usr/local/bin/docker",
		"/Applications/Docker.app/Contents/Resources/bin/docker",
		filepath.Join(home, ".docker", "bin", "docker"),
	}
}

func (d *DockerManager) resolvePlatformDockerDesktop() (string, bool) {
	// 1. System Applications
	appPath := "/Applications/Docker.app"
	if fi, err := d.stat(appPath); err == nil && fi.IsDir() {
		return appPath, true
	}
	// 2. User-specific Applications (~/Applications)
	home, _ := os.UserHomeDir()
	if home != "" {
		userApp := filepath.Join(home, "Applications", "Docker.app")
		if fi, err := d.stat(userApp); err == nil && fi.IsDir() {
			return userApp, true
		}
	}
	return "", false
}

func (d *DockerManager) launchPlatformDockerDesktop(ctx context.Context, desktopPath string, exists bool) error {
	if exists && desktopPath != "" {
		return d.executor.StartDetached(ctx, "open", "-a", desktopPath)
	}
	return d.executor.StartDetached(ctx, "open", "-a", "Docker")
}

func (d *DockerManager) openPlatformDockerSettings(ctx context.Context) error {
	return d.executor.StartDetached(ctx, "open", "docker-desktop://settings")
}

func launchPlatformBrowser(ctx context.Context, exec CommandExecutor, targetURL string) error {
	return exec.StartDetached(ctx, "open", targetURL)
}

func (d *DockerManager) isPlatformDockerDesktopPaused(ctx context.Context) bool {
	home, _ := os.UserHomeDir()
	if home == "" {
		return false
	}
	sockPath := filepath.Join(home, "Library/Containers/com.docker.docker/Data/backend.sock")
	if _, err := d.stat(sockPath); err != nil {
		return false
	}

	client := &http.Client{
		Transport: &http.Transport{
			DialContext: func(ctx context.Context, network, addr string) (net.Conn, error) {
				return (&net.Dialer{}).DialContext(ctx, "unix", sockPath)
			},
		},
		Timeout: 2 * time.Second,
	}

	req, err := http.NewRequestWithContext(ctx, "GET", "http://localhost/pause/status", nil)
	if err != nil {
		return false
	}

	resp, err := client.Do(req)
	if err != nil {
		return false
	}
	defer resp.Body.Close()

	if resp.StatusCode == http.StatusOK {
		var status struct {
			IsPaused bool `json:"isPaused"`
		}
		if err := json.NewDecoder(resp.Body).Decode(&status); err == nil {
			return status.IsPaused
		}
	}
	return false
}

func (d *DockerManager) unpausePlatformDockerDesktop(ctx context.Context) error {
	home, _ := os.UserHomeDir()
	var sockErr error
	if home != "" {
		sockPath := filepath.Join(home, "Library/Containers/com.docker.docker/Data/backend.sock")
		if _, err := d.stat(sockPath); err == nil {
			client := &http.Client{
				Transport: &http.Transport{
					DialContext: func(ctx context.Context, network, addr string) (net.Conn, error) {
						return (&net.Dialer{}).DialContext(ctx, "unix", sockPath)
					},
				},
				Timeout: 5 * time.Second,
			}
			req, err := http.NewRequestWithContext(ctx, "POST", "http://localhost/unpause", nil)
			if err == nil {
				resp, err := client.Do(req)
				if err == nil {
					resp.Body.Close()
					if resp.StatusCode == http.StatusOK {
						log.Printf("[unpausePlatformDockerDesktop] Successfully unpaused Docker Desktop via backend.sock")
						return nil
					}
					sockErr = fmt.Errorf("backend.sock returned HTTP %d", resp.StatusCode)
				} else {
					sockErr = err
				}
			}
		}
	}

	// Fallback 1: Try CLI plugin if available
	cli := d.ResolveDockerCLI()
	if cli == "" {
		cli = "docker"
	}
	stdout, stderr, exitCode, _ := d.executor.Run(ctx, cli, "desktop", "start")
	if exitCode == 0 {
		log.Printf("[unpausePlatformDockerDesktop] Dispatched docker desktop start fallback")
		return nil
	}

	// Fallback 2: Launch/activate Docker Desktop app
	launchErr := d.LaunchDockerDesktop(ctx)
	if launchErr == nil {
		return nil
	}

	if sockErr != nil {
		return fmt.Errorf("failed to unpause Docker Desktop: %w", sockErr)
	}
	return fmt.Errorf("failed to unpause Docker Desktop (cli exit %d: %s)", exitCode, strings.TrimSpace(stderr+" "+stdout))
}

