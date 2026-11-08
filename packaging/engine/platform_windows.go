//go:build windows

package main

import (
	"context"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"
	"time"
)

func setDetachedProcess(cmd *exec.Cmd) {
	cmd.SysProcAttr = &syscall.SysProcAttr{
		CreationFlags: syscall.CREATE_NEW_PROCESS_GROUP,
	}
}

func getPlatformOfficialDockerURL() string {
	return "https://desktop.docker.com/win/main/amd64/Docker%20Desktop%20Installer.exe"
}

// queryWindowsRegistryValue retrieves a string value from the Windows registry using reg.exe.
// If valueName is empty, it queries the default value ((Default) / /ve).
func queryWindowsRegistryValue(key, valueName string) string {
	for _, regFlag := range []string{"/reg:64", "/reg:32"} {
		args := []string{"query", key}
		if valueName == "" {
			args = append(args, "/ve")
		} else {
			args = append(args, "/v", valueName)
		}
		args = append(args, regFlag)

		ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
		cmd := exec.CommandContext(ctx, "reg.exe", args...)
		out, err := cmd.Output()
		cancel()
		if err == nil {
			for _, line := range strings.Split(string(out), "\n") {
				line = strings.TrimSpace(line)
				for _, typeName := range []string{"REG_SZ", "REG_EXPAND_SZ"} {
					if idx := strings.Index(line, typeName); idx != -1 {
						val := strings.TrimSpace(line[idx+len(typeName):])
						if val != "" {
							return expandWindowsEnv(val)
						}
					}
				}
			}
		}
	}
	return ""
}

func expandWindowsEnv(s string) string {
	if !strings.Contains(s, "%") {
		return s
	}
	parts := strings.Split(s, "%")
	for i := 1; i < len(parts); i += 2 {
		parts[i] = os.Getenv(parts[i])
	}
	return strings.Join(parts, "")
}

// syncProcessPathWithRegistry reads Machine and User PATH from registry and prepends missing directories to process PATH.
func syncProcessPathWithRegistry() {
	keys := []struct {
		key string
		val string
	}{
		{`HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment`, "Path"},
		{`HKCU\Environment`, "Path"},
	}

	currentPath := os.Getenv("PATH")
	existing := make(map[string]bool)
	for _, p := range filepath.SplitList(currentPath) {
		existing[strings.ToLower(filepath.Clean(p))] = true
	}

	var toAdd []string
	for _, kv := range keys {
		if raw := queryWindowsRegistryValue(kv.key, kv.val); raw != "" {
			for _, entry := range filepath.SplitList(raw) {
				entry = strings.TrimSpace(entry)
				if entry != "" {
					clean := strings.ToLower(filepath.Clean(entry))
					if !existing[clean] {
						existing[clean] = true
						toAdd = append(toAdd, entry)
					}
				}
			}
		}
	}

	if len(toAdd) > 0 {
		newPath := strings.Join(toAdd, string(os.PathListSeparator)) + string(os.PathListSeparator) + currentPath
		_ = os.Setenv("PATH", newPath)
	}
}

func getPlatformDockerCLICandidates(home string) []string {
	syncProcessPathWithRegistry()

	var candidates []string

	// 1. Registry queries for registered CLI paths
	regKeys := []string{
		`HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\docker.exe`,
		`HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\docker.exe`,
	}
	for _, k := range regKeys {
		if val := queryWindowsRegistryValue(k, ""); val != "" {
			candidates = append(candidates, val)
		}
	}

	if appPath := queryWindowsRegistryValue(`HKLM\SOFTWARE\Docker Inc.\Docker\Application`, "AppPath"); appPath != "" {
		cliDir := filepath.Dir(appPath)
		candidates = append(candidates,
			filepath.Join(cliDir, "resources", "bin", "docker.exe"),
			filepath.Join(cliDir, "resources", "docker.exe"),
			filepath.Join(cliDir, "docker.exe"),
		)
	}

	if instLoc := queryWindowsRegistryValue(`HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Docker Desktop`, "InstallLocation"); instLoc != "" {
		candidates = append(candidates,
			filepath.Join(instLoc, "resources", "bin", "docker.exe"),
			filepath.Join(instLoc, "version-bin", "docker.exe"),
			filepath.Join(instLoc, "docker.exe"),
		)
	}

	// 2. ProgramData / All Users (Docker Desktop 4.18+ version-bin)
	progData := os.Getenv("ProgramData")
	if progData != "" {
		candidates = append(candidates, filepath.Join(progData, "DockerDesktop", "version-bin", "docker.exe"))
	}
	allUsers := os.Getenv("ALLUSERSPROFILE")
	if allUsers != "" && allUsers != progData {
		candidates = append(candidates, filepath.Join(allUsers, "DockerDesktop", "version-bin", "docker.exe"))
	}
	candidates = append(candidates, `C:\ProgramData\DockerDesktop\version-bin\docker.exe`)

	// 3. Program Files (64-bit and 32-bit views)
	progW64 := os.Getenv("ProgramW6432")
	progFiles := os.Getenv("ProgramFiles")
	progFilesX86 := os.Getenv("ProgramFiles(x86)")

	checkDirs := []string{progW64, progFiles, progFilesX86, `C:\Program Files`, `C:\Program Files (x86)`}
	for _, dir := range checkDirs {
		if dir != "" {
			candidates = append(candidates,
				filepath.Join(dir, "Docker", "Docker", "resources", "bin", "docker.exe"),
				filepath.Join(dir, "Docker", "Docker", "resources", "docker.exe"),
				filepath.Join(dir, "Docker", "Docker", "docker.exe"),
			)
		}
	}

	// 4. LocalAppData and User Home
	localApp := os.Getenv("LOCALAPPDATA")
	userProfile := os.Getenv("USERPROFILE")
	userDirs := []string{localApp}
	if home != "" {
		userDirs = append(userDirs, filepath.Join(home, "AppData", "Local"))
	}
	if userProfile != "" {
		userDirs = append(userDirs, filepath.Join(userProfile, "AppData", "Local"))
	}
	for _, uDir := range userDirs {
		if uDir != "" {
			candidates = append(candidates,
				filepath.Join(uDir, "Programs", "Docker", "Docker", "resources", "bin", "docker.exe"),
				filepath.Join(uDir, "Programs", "Docker", "resources", "bin", "docker.exe"),
				filepath.Join(uDir, "Docker", "resources", "bin", "docker.exe"),
				filepath.Join(uDir, "DockerDesktop", "version-bin", "docker.exe"),
			)
		}
	}

	// 5. Alternate system drives
	for _, drive := range []string{`D:\`, `E:\`} {
		candidates = append(candidates,
			filepath.Join(drive, "Program Files", "Docker", "Docker", "resources", "bin", "docker.exe"),
			filepath.Join(drive, "Docker", "Docker", "resources", "bin", "docker.exe"),
			filepath.Join(drive, "Docker", "resources", "bin", "docker.exe"),
			filepath.Join(drive, "ProgramData", "DockerDesktop", "version-bin", "docker.exe"),
		)
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
			filepath.Join(cliDir, "..", "..", "Docker", "Docker Desktop.exe"),
		)
	}

	// 2. Query Windows Registry for registered application paths
	regKeys := []string{
		`HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\Docker Desktop.exe`,
		`HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\Docker Desktop.exe`,
	}
	for _, k := range regKeys {
		if val := queryWindowsRegistryValue(k, ""); val != "" {
			exes = append(exes, val)
		}
	}

	if appPath := queryWindowsRegistryValue(`HKLM\SOFTWARE\Docker Inc.\Docker\Application`, "AppPath"); appPath != "" {
		exes = append(exes, appPath)
	}

	if instLoc := queryWindowsRegistryValue(`HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Docker Desktop`, "InstallLocation"); instLoc != "" {
		exes = append(exes,
			filepath.Join(instLoc, "Docker Desktop.exe"),
			filepath.Join(instLoc, "Docker", "Docker Desktop.exe"),
		)
	}
	if instLoc := queryWindowsRegistryValue(`HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Docker Desktop`, "InstallLocation"); instLoc != "" {
		exes = append(exes,
			filepath.Join(instLoc, "Docker Desktop.exe"),
			filepath.Join(instLoc, "Docker", "Docker Desktop.exe"),
		)
	}

	// 3. Standard Program Files (64-bit and 32-bit views)
	progW64 := os.Getenv("ProgramW6432")
	progFiles := os.Getenv("ProgramFiles")
	progFilesX86 := os.Getenv("ProgramFiles(x86)")
	localApp := os.Getenv("LOCALAPPDATA")
	userProfile := os.Getenv("USERPROFILE")

	checkDirs := []string{progW64, progFiles, progFilesX86, `C:\Program Files`, `C:\Program Files (x86)`}
	for _, dir := range checkDirs {
		if dir != "" {
			exes = append(exes,
				filepath.Join(dir, "Docker", "Docker", "Docker Desktop.exe"),
				filepath.Join(dir, "Docker", "Docker Desktop.exe"),
			)
		}
	}

	userDirs := []string{localApp}
	if userProfile != "" {
		userDirs = append(userDirs, filepath.Join(userProfile, "AppData", "Local"))
	}
	for _, uDir := range userDirs {
		if uDir != "" {
			exes = append(exes,
				filepath.Join(uDir, "Programs", "Docker", "Docker", "Docker Desktop.exe"),
				filepath.Join(uDir, "Programs", "Docker", "Docker Desktop.exe"),
				filepath.Join(uDir, "Docker", "Docker Desktop.exe"),
			)
		}
	}

	// 4. Alternate drives
	for _, drive := range []string{`D:\`, `E:\`} {
		exes = append(exes,
			filepath.Join(drive, "Program Files", "Docker", "Docker", "Docker Desktop.exe"),
			filepath.Join(drive, "Docker", "Docker", "Docker Desktop.exe"),
			filepath.Join(drive, "Docker", "Docker Desktop.exe"),
		)
	}

	for _, e := range exes {
		cleanPath := filepath.Clean(e)
		if fi, err := d.stat(cleanPath); err == nil && !fi.IsDir() {
			return cleanPath, true
		}
	}

	// 5. Check Start Menu shortcuts
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

	// 6. Running process fallback: if Docker Desktop.exe is actively running, it is definitely installed!
	if d.isPlatformDockerDesktopProcessRunning(context.Background()) {
		return "Docker Desktop.exe", true
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

func (d *DockerManager) isPlatformDockerDesktopProcessRunning(ctx context.Context) bool {
	pCtx, cancel := context.WithTimeout(ctx, 3*time.Second)
	defer cancel()
	stdout, _, exitCode, _ := d.executor.Run(pCtx, "tasklist", "/FI", "IMAGENAME eq Docker Desktop.exe")
	return exitCode == 0 && strings.Contains(strings.ToLower(stdout), "docker desktop.exe")
}



