//go:build !windows && !darwin

package main

import (
	"context"
	"os/exec"
	"syscall"
)

func setDetachedProcess(cmd *exec.Cmd) {
	cmd.SysProcAttr = &syscall.SysProcAttr{
		Setpgid: true,
	}
}

func getPlatformOfficialDockerURL() string {
	return "https://docs.docker.com/engine/install/"
}

func getPlatformDockerCLICandidates(home string) []string {
	return []string{
		"/usr/bin/docker",
		"/usr/local/bin/docker",
	}
}

func (d *DockerManager) resolvePlatformDockerDesktop() (string, bool) {
	if p, err := d.lookPath("docker-desktop"); err == nil {
		return p, true
	}
	return "", false
}

func (d *DockerManager) launchPlatformDockerDesktop(ctx context.Context, desktopPath string, exists bool) error {
	if exists && desktopPath != "" {
		return d.executor.StartDetached(ctx, desktopPath)
	}
	return d.executor.StartDetached(ctx, "systemctl", "--user", "start", "docker-desktop")
}

func (d *DockerManager) openPlatformDockerSettings(ctx context.Context) error {
	return nil
}

func launchPlatformBrowser(ctx context.Context, exec CommandExecutor, targetURL string) error {
	return exec.StartDetached(ctx, "xdg-open", targetURL)
}

func (d *DockerManager) isPlatformDockerDesktopPaused(ctx context.Context) bool {
	return false
}

func (d *DockerManager) unpausePlatformDockerDesktop(ctx context.Context) error {
	return d.LaunchDockerDesktop(ctx)
}

