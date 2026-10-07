//go:build windows

package main

import (
	"context"
	"os"
	"os/exec"
	"path/filepath"
	"syscall"
)

func setDetachedProcess(cmd *exec.Cmd) {
	cmd.SysProcAttr = &syscall.SysProcAttr{
		CreationFlags: syscall.CREATE_NEW_PROCESS_GROUP,
	}
}

func getPlatformOfficialDockerURL() string {
	return "https://desktop.docker.com/win/main/amd64/Docker%20Desktop%20Installer.exe"
}

func getPlatformDockerCLICandidates(home string) []string {
	progFiles := os.Getenv("ProgramFiles")
	progFilesX86 := os.Getenv("ProgramFiles(x86)")
	var candidates []string
	if progFiles != "" {
		candidates = append(candidates, filepath.Join(progFiles, "Docker", "Docker", "resources", "bin", "docker.exe"))
	}
	if progFilesX86 != "" {
		candidates = append(candidates, filepath.Join(progFilesX86, "Docker", "Docker", "resources", "bin", "docker.exe"))
	}
	return candidates
}

func (d *DockerManager) resolvePlatformDockerDesktop() (string, bool) {
	var exes []string

	// 1. Resolve relative to docker CLI binary if found
	cliPath := d.ResolveDockerCLI()
	if cliPath != "" {
		cliDir := filepath.Dir(cliPath)
		exes = append(exes,
			filepath.Join(cliDir, "..", "..", "Docker Desktop.exe"),
			filepath.Join(cliDir, "..", "Docker Desktop.exe"),
			filepath.Join(cliDir, "Docker Desktop.exe"),
		)
	}

	// 2. Standard Program Files (64-bit and 32-bit views)
	progW64 := os.Getenv("ProgramW6432")
	progFiles := os.Getenv("ProgramFiles")
	progFilesX86 := os.Getenv("ProgramFiles(x86)")
	localApp := os.Getenv("LOCALAPPDATA")

	if progW64 != "" {
		exes = append(exes, filepath.Join(progW64, "Docker", "Docker", "Docker Desktop.exe"))
	}
	if progFiles != "" {
		exes = append(exes, filepath.Join(progFiles, "Docker", "Docker", "Docker Desktop.exe"))
	}
	if progFilesX86 != "" {
		exes = append(exes, filepath.Join(progFilesX86, "Docker", "Docker", "Docker Desktop.exe"))
	}
	if localApp != "" {
		exes = append(exes, filepath.Join(localApp, "Programs", "Docker", "Docker", "Docker Desktop.exe"))
	}

	// 3. Fallback well-known paths
	exes = append(exes,
		`C:\Program Files\Docker\Docker\Docker Desktop.exe`,
		`C:\Program Files (x86)\Docker\Docker\Docker Desktop.exe`,
	)

	for _, e := range exes {
		cleanPath := filepath.Clean(e)
		if fi, err := d.stat(cleanPath); err == nil && !fi.IsDir() {
			return cleanPath, true
		}
	}

	// 4. Check Start Menu shortcuts
	appData := os.Getenv("APPDATA")
	allUsers := os.Getenv("ALLUSERSPROFILE")
	progData := os.Getenv("ProgramData")
	var lnks []string
	if appData != "" {
		lnks = append(lnks, filepath.Join(appData, `Microsoft\Windows\Start Menu\Programs\Docker Desktop.lnk`))
	}
	if allUsers != "" {
		lnks = append(lnks, filepath.Join(allUsers, `Microsoft\Windows\Start Menu\Programs\Docker Desktop.lnk`))
	}
	if progData != "" {
		lnks = append(lnks, filepath.Join(progData, `Microsoft\Windows\Start Menu\Programs\Docker Desktop.lnk`))
	}
	for _, l := range lnks {
		if fi, err := d.stat(l); err == nil && !fi.IsDir() {
			return l, true
		}
	}
	return "", false
}

func (d *DockerManager) launchPlatformDockerDesktop(ctx context.Context, desktopPath string, exists bool) error {
	if exists && desktopPath != "" {
		return d.executor.StartDetached(ctx, "cmd.exe", "/c", "start", "", desktopPath)
	}
	return d.executor.StartDetached(ctx, "cmd.exe", "/c", "start", "", "Docker Desktop")
}

func (d *DockerManager) openPlatformDockerSettings(ctx context.Context) error {
	return d.executor.StartDetached(ctx, "cmd.exe", "/c", "start", "", "docker-desktop://settings")
}

func launchPlatformBrowser(ctx context.Context, exec CommandExecutor, targetURL string) error {
	return exec.StartDetached(ctx, "cmd.exe", "/c", "start", "", targetURL)
}

func (d *DockerManager) isPlatformDockerDesktopPaused(ctx context.Context) bool {
	return false
}

func (d *DockerManager) unpausePlatformDockerDesktop(ctx context.Context) error {
	cli := d.ResolveDockerCLI()
	if cli == "" {
		cli = "docker"
	}
	_, _, exitCode, _ := d.executor.Run(ctx, cli, "desktop", "start")
	if exitCode == 0 {
		return nil
	}
	return d.LaunchDockerDesktop(ctx)
}

