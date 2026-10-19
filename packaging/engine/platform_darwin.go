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
	candidates := []string{
		"/Applications/Docker.app",
		"/Applications/Docker Desktop.app",
	}

	home, _ := os.UserHomeDir()
	if home != "" {
		userApp := filepath.Join(home, "Applications", "Docker.app")
		candidates = append(candidates,
			userApp,
			filepath.Join(home, "Applications", "Docker Desktop.app"),
		)
	}

	for _, cand := range candidates {
		if fi, err := d.stat(cand); err == nil && fi.IsDir() {
			return cand, true
		}
	}

	// Check if docker CLI binary is within a Docker.app bundle or symlinks to one
	cliPath := d.ResolveDockerCLI()
	if cliPath != "" {
		if idx := strings.Index(cliPath, ".app"); idx != -1 {
			appDir := cliPath[:idx+4]
			if fi, err := d.stat(appDir); err == nil && fi.IsDir() {
				return appDir, true
			}
		}
		if target, err := filepath.EvalSymlinks(cliPath); err == nil && target != "" {
			if idx := strings.Index(target, ".app"); idx != -1 {
				appDir := target[:idx+4]
				if fi, err := d.stat(appDir); err == nil && fi.IsDir() {
					return appDir, true
				}
			}
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

func (d *DockerManager) isPlatformDockerDesktopProcessRunning(ctx context.Context) bool {
	if _, isReal := d.executor.(*OSCommandExecutor); !isReal {
		return false
	}
	pCtx, cancel := context.WithTimeout(ctx, 1*time.Second)
	defer cancel()
	stdout, _, exitCode, _ := d.executor.Run(pCtx, "pgrep", "-f", "Docker.app/Contents/MacOS")
	if exitCode == 0 && strings.TrimSpace(stdout) != "" {
		return true
	}
	pCtx2, cancel2 := context.WithTimeout(ctx, 1*time.Second)
	defer cancel2()
	stdout2, _, exitCode2, _ := d.executor.Run(pCtx2, "pgrep", "-x", "Docker Desktop")
	if exitCode2 == 0 && strings.TrimSpace(stdout2) != "" {
		return true
	}
	pCtx3, cancel3 := context.WithTimeout(ctx, 1*time.Second)
	defer cancel3()
	stdout3, _, exitCode3, _ := d.executor.Run(pCtx3, "pgrep", "-x", "Docker")
	return exitCode3 == 0 && strings.TrimSpace(stdout3) != ""
}


