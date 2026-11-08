package main

import (
	"archive/zip"
	"bytes"
	_ "embed"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"
	"unsafe"
)

//go:embed app.zip
var appZipData []byte

var AppVersion = "1.1.0"

func main() {
	localAppData := os.Getenv("LOCALAPPDATA")
	if localAppData == "" {
		localAppData = os.Getenv("USERPROFILE")
		if localAppData == "" {
			localAppData = os.TempDir()
		} else {
			localAppData = filepath.Join(localAppData, "AppData", "Local")
		}
	}

	appDir := filepath.Join(localAppData, "Programs", "AltrStreamManager", AppVersion)
	exePath := filepath.Join(appDir, "altr_stream_manager.exe")
	aliasPath := filepath.Join(appDir, "Altr-Stream-Manager.exe")

	// Verify target executable exists; if not, unpack embedded payload
	targetExe := exePath
	if _, err := os.Stat(targetExe); err != nil {
		if _, err2 := os.Stat(aliasPath); err2 == nil {
			targetExe = aliasPath
		} else {
			if len(appZipData) == 0 {
				showErrorBox("Altr Stream Manager", "Embedded application payload is missing.")
				os.Exit(1)
			}
			if err := unpackZip(appZipData, appDir); err != nil {
				showErrorBox("Altr Stream Manager", "Failed to unpack application files: "+err.Error())
				os.Exit(1)
			}
			if _, err := os.Stat(exePath); err == nil {
				targetExe = exePath
			} else if _, err := os.Stat(aliasPath); err == nil {
				targetExe = aliasPath
			} else {
				showErrorBox("Altr Stream Manager", "Application executable missing after unpack in: "+appDir)
				os.Exit(1)
			}
		}
	}

	// Launch the Flutter Manager app detached with arguments forwarded
	cmd := exec.Command(targetExe, os.Args[1:]...)
	cmd.Dir = appDir
	cmd.SysProcAttr = &syscall.SysProcAttr{
		HideWindow:    false,
		CreationFlags: 0x08000000, // CREATE_NO_WINDOW for launcher parent process
	}
	if err := cmd.Start(); err != nil {
		showErrorBox("Altr Stream Manager", "Failed to launch application: "+err.Error())
		os.Exit(1)
	}
}

func unpackZip(zipBytes []byte, destDir string) error {
	_ = os.MkdirAll(destDir, 0755)
	r, err := zip.NewReader(bytes.NewReader(zipBytes), int64(len(zipBytes)))
	if err != nil {
		return err
	}
	for _, f := range r.File {
		targetPath := filepath.Join(destDir, f.Name)
		// Guard against ZipSlip vulnerability
		cleanTarget := filepath.Clean(targetPath)
		cleanDest := filepath.Clean(destDir)
		if !strings.HasPrefix(cleanTarget, cleanDest+string(os.PathSeparator)) && cleanTarget != cleanDest {
			continue
		}
		if f.FileInfo().IsDir() {
			_ = os.MkdirAll(targetPath, 0755)
			continue
		}
		_ = os.MkdirAll(filepath.Dir(targetPath), 0755)
		outFile, err := os.OpenFile(targetPath, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, f.Mode())
		if err != nil {
			return err
		}
		rc, err := f.Open()
		if err != nil {
			outFile.Close()
			return err
		}
		_, err = io.Copy(outFile, rc)
		rc.Close()
		outFile.Close()
		if err != nil {
			return err
		}
	}
	return nil
}

func showErrorBox(title, message string) {
	user32 := syscall.NewLazyDLL("user32.dll")
	msgBox := user32.NewProc("MessageBoxW")
	t, _ := syscall.UTF16PtrFromString(title)
	m, _ := syscall.UTF16PtrFromString(message)
	msgBox.Call(0, uintptr(unsafe.Pointer(m)), uintptr(unsafe.Pointer(t)), 0x10) // MB_ICONERROR
}
