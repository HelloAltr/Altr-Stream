package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/exec"
	"strings"
	"time"
)

// Build-time injected variables (via -ldflags)
var (
	DefaultVersion = "1.0.0-beta"
	DefaultImage   = "ghcr.io/helloaltr/altr-stream:0.13.7-alpha" // Configurable; defaults to current E2E target
)

// OSCommandExecutor runs real system processes.
type OSCommandExecutor struct{}

func (o *OSCommandExecutor) Run(ctx context.Context, name string, args ...string) (string, string, int, error) {
	cmd := exec.CommandContext(ctx, name, args...)
	var stdoutBuf, stderrBuf bytes.Buffer
	cmd.Stdout = &stdoutBuf
	cmd.Stderr = &stderrBuf

	err := cmd.Run()
	stdout := stdoutBuf.String()
	stderr := stderrBuf.String()

	if err != nil {
		if exitErr, ok := err.(*exec.ExitError); ok {
			return stdout, stderr, exitErr.ExitCode(), nil
		}
		return stdout, stderr, 1, err
	}
	return stdout, stderr, 0, nil
}

func (o *OSCommandExecutor) StartDetached(ctx context.Context, name string, args ...string) error {
	cmd := exec.CommandContext(ctx, name, args...)
	// Disconnect standard streams to avoid anonymous pipe creation and handle inheritance deadlocks
	cmd.Stdin = nil
	cmd.Stdout = nil
	cmd.Stderr = nil
	setDetachedProcess(cmd)
	if err := cmd.Start(); err != nil {
		return err
	}
	// Reap the process asynchronously so OS resources are freed promptly
	go func() {
		_ = cmd.Wait()
	}()
	return nil
}

func printJSON(v interface{}) {
	data, err := json.MarshalIndent(v, "", "  ")
	if err != nil {
		fmt.Fprintf(os.Stderr, "JSON encoding error: %v\n", err)
		os.Exit(1)
	}
	fmt.Println(string(data))
}

func writeProgressFile(path string, p InstallProgress) {
	if path == "" {
		return
	}
	line := fmt.Sprintf("%d|%d|%d|%s|%s\n", p.Percent, p.StageIndex, p.TotalStages, p.Stage, p.Message)
	_ = os.WriteFile(path, []byte(line), 0644)
}

func resolveConfig(targetDir, version, image string, port int) InstallConfig {
	if version == "" {
		if envVer := os.Getenv("ALTR_STREAM_VERSION"); envVer != "" {
			version = envVer
		} else {
			version = DefaultVersion
		}
	}
	if image == "" {
		if envImg := os.Getenv("ALTR_STREAM_IMAGE"); envImg != "" {
			image = envImg
		} else {
			image = DefaultImage
		}
	}
	if port <= 0 {
		port = DefaultPort
	}
	return InstallConfig{
		TargetDir:     targetDir,
		Version:       version,
		Image:         image,
		Port:          port,
		FeedbackURL:   os.Getenv("ALTR_STREAM_FEEDBACK_SERVICE_URL"),
		FeedbackKey:   os.Getenv("ALTR_FEEDBACK_API_KEY"),
		HealthTimeout: 60,
		StartTimeout:  45,
	}
}

func main() {
	if len(os.Args) < 2 {
		fmt.Println("Altr Stream Installer Engine")
		fmt.Println("Usage: altr-installer-engine <command> [flags]")
		fmt.Println("\nCommands:")
		fmt.Println("  detect-env       Detect system environment and install path")
		fmt.Println("  check-docker     Inspect Docker installation and daemon readiness")
		fmt.Println("  launch-docker    Start Docker Desktop process")
		fmt.Println("  wait-docker      Wait for Docker daemon readiness with timeout")
		fmt.Println("  conflict         Check for existing 'altr-stream' container conflict")
		fmt.Println("  remove-container Stop and remove conflicting container, preserving data")
		fmt.Println("  start-container  Start existing container")
		fmt.Println("  unpause-container Resume paused container")
		fmt.Println("  install          Execute installation pipeline")
		fmt.Println("  repair           Repair configuration and recreate container")
		fmt.Println("  uninstall        Remove container and optionally delete data")
		fmt.Println("  status           Query live node status and health")
		fmt.Println("  launch-browser   Open web UI in default browser")
		os.Exit(0)
	}

	command := os.Args[1]
	ctx := context.Background()

	engine := NewInstallerEngine(&OSCommandExecutor{}, http.DefaultClient)

	switch command {
	case "detect-env":
		env, err := engine.DetectEnvironment()
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error: %v\n", err)
			os.Exit(1)
		}
		printJSON(env)

	case "check-docker":
		diag, err := engine.CheckDocker(ctx)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error: %v\n", err)
			os.Exit(1)
		}
		printJSON(diag)

	case "launch-docker":
		log.Printf("[main] Received launch-docker command")
		if err := engine.LaunchDockerDesktop(ctx); err != nil {
			log.Printf("[main] LaunchDockerDesktop failed: %v", err)
			fmt.Fprintf(os.Stderr, "Error launching Docker Desktop: %v\n", err)
			os.Exit(1)
		}
		log.Printf("[main] LaunchDockerDesktop completed successfully, exiting 0")
		fmt.Println("Launched Docker Desktop process.")
		os.Exit(0)

	case "unpause-docker-desktop":
		log.Printf("[main] Received unpause-docker-desktop command")
		if err := engine.UnpauseDockerDesktop(ctx); err != nil {
			log.Printf("[main] UnpauseDockerDesktop failed: %v", err)
			printJSON(map[string]any{
				"success": false,
				"error":   err.Error(),
			})
			os.Exit(1)
		}
		log.Printf("[main] UnpauseDockerDesktop completed successfully, exiting 0")
		printJSON(map[string]any{
			"success": true,
			"message": "Docker Desktop unpaused successfully.",
		})
		os.Exit(0)

	case "open-docker-settings":
		log.Printf("[main] Received open-docker-settings command")
		if err := engine.OpenDockerSettings(ctx); err != nil {
			log.Printf("[main] OpenDockerSettings failed: %v", err)
			fmt.Fprintf(os.Stderr, "Error launching Docker Desktop: %v\n", err)
			os.Exit(1)
		}
		log.Printf("[main] OpenDockerSettings completed successfully, exiting 0")
		fmt.Println("Docker Desktop launched. Please navigate to Settings (gear icon) > Resources > File Sharing.")
		os.Exit(0)

	case "wait-docker":
		fs := flag.NewFlagSet("wait-docker", flag.ExitOnError)
		timeoutSec := fs.Int("timeout", 60, "Timeout in seconds")
		jsonOut := fs.Bool("json", false, "Output JSON")
		_ = fs.Parse(os.Args[2:])

		log.Printf("[main] Received wait-docker command (timeout=%ds)", *timeoutSec)
		err := engine.WaitForDocker(ctx, time.Duration(*timeoutSec)*time.Second, func(elapsed time.Duration) {
			if !*jsonOut {
				fmt.Printf("Waiting for Docker Engine... (%vs)\n", int(elapsed.Seconds()))
			}
		})
		if err != nil {
			log.Printf("[main] WaitForDocker failed: %v", err)
			if *jsonOut {
				printJSON(map[string]interface{}{"success": false, "error": err.Error()})
			} else {
				fmt.Fprintf(os.Stderr, "Error: %v\n", err)
			}
			os.Exit(1)
		}
		log.Printf("[main] WaitForDocker completed successfully (Docker is ready), exiting 0")
		if *jsonOut {
			printJSON(map[string]interface{}{"success": true, "state": "ready"})
		} else {
			fmt.Println("Docker Engine is ready.")
		}
		os.Exit(0)

	case "conflict":
		fs := flag.NewFlagSet("conflict", flag.ExitOnError)
		port := fs.Int("port", DefaultPort, "Host port to check")
		targetDir := fs.String("target-dir", "", "Target install directory")
		_ = fs.Parse(os.Args[2:])

		if *targetDir == "" {
			env, _ := engine.DetectEnvironment()
			if env != nil {
				*targetDir = env.EffectiveDir
			}
		}

		conflict, err := engine.CheckConflict(ctx, *port, *targetDir)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error checking conflict: %v\n", err)
			os.Exit(1)
		}
		printJSON(conflict)

	case "remove-container":
		err := engine.RemoveExistingContainer(ctx)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error removing container: %v\n", err)
			os.Exit(1)
		}
		printJSON(map[string]interface{}{"success": true, "message": "Container 'altr-stream' removed successfully. Persistent data preserved."})
		os.Exit(0)

	case "start-container":
		err := engine.StartExistingContainer(ctx)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error starting container: %v\n", err)
			os.Exit(1)
		}
		printJSON(map[string]interface{}{"success": true, "message": "Container 'altr-stream' started successfully."})
		os.Exit(0)

	case "unpause-container":
		err := engine.UnpauseContainer(ctx)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error unpausing container: %v\n", err)
			os.Exit(1)
		}
		printJSON(map[string]interface{}{"success": true, "message": "Container 'altr-stream' unpaused successfully."})
		os.Exit(0)

	case "install":
		fs := flag.NewFlagSet("install", flag.ExitOnError)
		targetDir := fs.String("target-dir", "", "Target install directory")
		version := fs.String("version", "", "Altr Stream version")
		image := fs.String("image", "", "Docker image reference")
		port := fs.Int("port", DefaultPort, "Host port binding")
		replaceExisting := fs.Bool("replace-existing", false, "Safely remove conflicting container before installing")
		jsonOut := fs.Bool("json", false, "Stream JSON progress")
		progressFile := fs.String("progress-file", "", "Path to write real-time stage progress")
		doneFile := fs.String("done-file", "", "Path to write completion status code")
		_ = fs.Parse(os.Args[2:])

		if *targetDir == "" {
			env, _ := engine.DetectEnvironment()
			if env != nil {
				*targetDir = env.EffectiveDir
			}
		}

		cfg := resolveConfig(*targetDir, *version, *image, *port)
		cfg.ReplaceExisting = *replaceExisting

		err := engine.Install(ctx, cfg, func(p InstallProgress) {
			if *progressFile != "" {
				writeProgressFile(*progressFile, p)
			}
			if *jsonOut {
				data, _ := json.Marshal(p)
				fmt.Println(string(data))
			} else {
				fmt.Printf("[%d/%d] %s (%d%%): %s\n", p.StageIndex, p.TotalStages, p.Stage, p.Percent, p.Message)
			}
		})

		if err != nil {
			var fileShareErr *ErrFileSharingRequired
			isFileShare := errors.As(err, &fileShareErr) || strings.Contains(err.Error(), "FILE_SHARING_REQUIRED")

			if *progressFile != "" {
				var errLine string
				if isFileShare {
					errLine = fmt.Sprintf("-1|4|6|FileSharingRequired|%s\n", err.Error())
				} else {
					errLine = fmt.Sprintf("-1|0|6|Failed|%s\n", err.Error())
				}
				_ = os.WriteFile(*progressFile, []byte(errLine), 0644)
			}
			if *doneFile != "" {
				var doneLine string
				if isFileShare {
					doneLine = fmt.Sprintf("2|%s\n", err.Error())
				} else {
					doneLine = fmt.Sprintf("1|%s\n", err.Error())
				}
				_ = os.WriteFile(*doneFile, []byte(doneLine), 0644)
			}
			fmt.Fprintf(os.Stderr, "Installation failed: %v\n", err)
			if isFileShare {
				os.Exit(2)
			}
			os.Exit(1)
		}
		if *progressFile != "" {
			doneLine := "100|6|6|Done|Installation completed successfully.\n"
			_ = os.WriteFile(*progressFile, []byte(doneLine), 0644)
		}
		if *doneFile != "" {
			_ = os.WriteFile(*doneFile, []byte("0|Success\n"), 0644)
		}
		fmt.Println("Installation completed successfully.")

	case "repair":
		fs := flag.NewFlagSet("repair", flag.ExitOnError)
		targetDir := fs.String("target-dir", "", "Target install directory")
		version := fs.String("version", "", "Altr Stream version")
		image := fs.String("image", "", "Docker image reference")
		port := fs.Int("port", DefaultPort, "Host port binding")
		jsonOut := fs.Bool("json", false, "Stream JSON progress")
		progressFile := fs.String("progress-file", "", "Path to write real-time stage progress")
		doneFile := fs.String("done-file", "", "Path to write completion status code")
		_ = fs.Parse(os.Args[2:])

		if *targetDir == "" {
			env, _ := engine.DetectEnvironment()
			if env != nil {
				*targetDir = env.EffectiveDir
			}
		}

		cfg := resolveConfig(*targetDir, *version, *image, *port)

		err := engine.Repair(ctx, *targetDir, cfg, func(p InstallProgress) {
			if *progressFile != "" {
				writeProgressFile(*progressFile, p)
			}
			if *jsonOut {
				data, _ := json.Marshal(p)
				fmt.Println(string(data))
			} else {
				fmt.Printf("[%d/%d] %s (%d%%): %s\n", p.StageIndex, p.TotalStages, p.Stage, p.Percent, p.Message)
			}
		})
		if err != nil {
			if *progressFile != "" {
				errLine := fmt.Sprintf("-1|0|4|Failed|%s\n", err.Error())
				_ = os.WriteFile(*progressFile, []byte(errLine), 0644)
			}
			if *doneFile != "" {
				doneLine := fmt.Sprintf("1|%s\n", err.Error())
				_ = os.WriteFile(*doneFile, []byte(doneLine), 0644)
			}
			fmt.Fprintf(os.Stderr, "Repair failed: %v\n", err)
			os.Exit(1)
		}
		if *progressFile != "" {
			doneLine := "100|4|4|Done|Repair completed successfully.\n"
			_ = os.WriteFile(*progressFile, []byte(doneLine), 0644)
		}
		if *doneFile != "" {
			_ = os.WriteFile(*doneFile, []byte("0|Success\n"), 0644)
		}
		fmt.Println("Repair completed successfully.")

	case "uninstall":
		fs := flag.NewFlagSet("uninstall", flag.ExitOnError)
		targetDir := fs.String("target-dir", "", "Target install directory")
		deleteData := fs.Bool("delete-data", false, "Permanently delete named volume and data")
		_ = fs.Parse(os.Args[2:])

		if *targetDir == "" {
			env, _ := engine.DetectEnvironment()
			if env != nil {
				*targetDir = env.EffectiveDir
			}
		}

		if err := engine.Uninstall(ctx, *targetDir, *deleteData); err != nil {
			fmt.Fprintf(os.Stderr, "Uninstall failed: %v\n", err)
			os.Exit(1)
		}
		fmt.Println("Uninstallation completed successfully.")

	case "status":
		fs := flag.NewFlagSet("status", flag.ExitOnError)
		targetDir := fs.String("target-dir", "", "Target install directory")
		_ = fs.Parse(os.Args[2:])

		st, err := engine.GetStatus(ctx, *targetDir)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error querying status: %v\n", err)
			os.Exit(1)
		}
		printJSON(st)

	case "launch-browser":
		fs := flag.NewFlagSet("launch-browser", flag.ExitOnError)
		targetURL := fs.String("url", "http://localhost:8000", "Target URL to open")
		_ = fs.Parse(os.Args[2:])

		if err := engine.LaunchBrowser(ctx, *targetURL); err != nil {
			fmt.Fprintf(os.Stderr, "Failed to launch browser: %v\n", err)
			os.Exit(1)
		}
		fmt.Println("Browser launched successfully.")

	default:
		fmt.Fprintf(os.Stderr, "Unknown command: %s\n", command)
		os.Exit(1)
	}
}
