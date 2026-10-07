import Foundation
import SwiftUI
import AppKit

public enum AppPhase: Equatable {
    case checking
    case dockerNotInstalled(DockerDiagnostics)
    case dockerPaused(DockerDiagnostics)
    case dockerStopped(DockerDiagnostics)
    case startingDocker(secondsElapsed: Int)
    case readyToInstall(effectiveDir: String)
    case conflictDetected(ConflictInfo)
    case installing(progress: InstallProgress)
    case repairing(progress: InstallProgress)
    case running(NodeStatus)
    case paused(NodeStatus)
    case stopped(NodeStatus)
    case fileSharingRequired(message: String, path: String)
    case failed(message: String, details: String)
}

@MainActor
public final class AppState: ObservableObject {
    @Published public var phase: AppPhase = .checking
    @Published public var installDir: String = "~/.altr-stream"
    @Published public var appVersion: String = "1.0.0-beta"

    // Dashboard Telemetry
    @Published public var dockerStateText: String = "Checking..."
    @Published public var dockerStateColor: Color = .gray
    @Published public var altrStateText: String = "Checking..."
    @Published public var altrStateColor: Color = .gray

    // Modal and Sheet state
    @Published public var showTechnicalDetails: Bool = false
    @Published public var technicalDetails: String = ""
    @Published public var showUninstallSheet: Bool = false
    @Published public var uninstallDeleteData: Bool = false
    @Published public var uninstallConfirmationInput: String = ""
    @Published public var isExecutingAction: Bool = false

    private let engineBridge = EngineBridge.shared
    private var dockerPollingTask: Task<Void, Never>?

    public init() {
        Task {
            await refreshStatus()
        }
    }

    deinit {
        dockerPollingTask?.cancel()
    }

    // MARK: - Status & Inspection

    public func refreshStatus() async {
        isExecutingAction = true
        defer { isExecutingAction = false }

        do {
            // 1. Detect Environment
            if let env = try? await engineBridge.detectEnvironment() {
                self.installDir = env.effectiveDir
            }

            // 2. Check Docker Diagnostics
            let dockerDiag = try await engineBridge.checkDocker()
            updateDockerTelemetry(diag: dockerDiag)

            if dockerDiag.isNotInstalled {
                self.phase = .dockerNotInstalled(dockerDiag)
                self.altrStateText = "Docker Required"
                self.altrStateColor = .gray
                return
            }

            if dockerDiag.isPaused {
                self.phase = .dockerPaused(dockerDiag)
                self.altrStateText = "Offline (Docker Paused)"
                self.altrStateColor = .orange
                return
            }

            if dockerDiag.isStopped {
                self.phase = .dockerStopped(dockerDiag)
                self.altrStateText = "Offline (Docker Stopped)"
                self.altrStateColor = .gray
                return
            }

            // 3. Docker is Ready: Query Altr Stream Node Status
            let nodeStatus = try await engineBridge.getStatus(targetDir: self.installDir)
            self.appVersion = nodeStatus.targetVersion

            let state = nodeStatus.lifecycleState

            switch state {
            case .running:
                if nodeStatus.healthy {
                    self.altrStateText = "Running"
                    self.altrStateColor = .green
                    self.phase = .running(nodeStatus)
                } else {
                    self.altrStateText = "Starting / Unhealthy"
                    self.altrStateColor = .yellow
                    self.phase = .running(nodeStatus)
                }

            case .paused:
                self.altrStateText = "Paused"
                self.altrStateColor = .orange
                self.phase = .paused(nodeStatus)

            case .restarting:
                self.altrStateText = "Restarting"
                self.altrStateColor = .yellow
                self.phase = .running(nodeStatus)

            case .exited:
                self.altrStateText = "Stopped"
                self.altrStateColor = .secondary
                self.phase = .stopped(nodeStatus)

            case .dead:
                self.altrStateText = "Stopped / Failed"
                self.altrStateColor = .red
                self.phase = .stopped(nodeStatus)

            case .created:
                self.altrStateText = "Not Running / Stopped"
                self.altrStateColor = .secondary
                self.phase = .stopped(nodeStatus)

            case .notInstalled, .unknown:
                // Check if an existing container or port conflict exists
                if let conflict = try? await engineBridge.checkConflict(), conflict.exists {
                    if conflict.isPortConflict || conflict.isDevContainer == true || conflict.isInstallerOwned != true {
                        self.altrStateText = "Conflict"
                        self.altrStateColor = .orange
                        self.phase = .conflictDetected(conflict)
                    } else if conflict.isAltrStream {
                        let conflictState = conflict.lifecycleState
                        self.altrStateText = conflictState.displayText
                        if conflictState == .paused {
                            self.altrStateColor = .orange
                            self.phase = .paused(nodeStatus)
                        } else {
                            self.altrStateColor = .secondary
                            self.phase = .stopped(nodeStatus)
                        }
                    } else {
                        self.altrStateText = "Conflict"
                        self.altrStateColor = .orange
                        self.phase = .conflictDetected(conflict)
                    }
                } else {
                    self.altrStateText = "Not Installed"
                    self.altrStateColor = .secondary
                    self.phase = .readyToInstall(effectiveDir: self.installDir)
                }
            }

        } catch {
            self.phase = .failed(
                message: "Could not communicate with installer engine.",
                details: error.localizedDescription
            )
            self.technicalDetails = error.localizedDescription
        }
    }

    private func updateDockerTelemetry(diag: DockerDiagnostics) {
        if diag.isReady {
            self.dockerStateText = "Ready"
            self.dockerStateColor = .green
        } else if diag.isPaused {
            self.dockerStateText = "Paused"
            self.dockerStateColor = .orange
        } else if diag.isStopped {
            self.dockerStateText = "Stopped"
            self.dockerStateColor = .secondary
        } else {
            self.dockerStateText = "Not Installed"
            self.dockerStateColor = .red
        }
    }

    // MARK: - Docker Lifecycle Actions

    public func resumeDockerDesktop() {
        dockerPollingTask?.cancel()
        phase = .startingDocker(secondsElapsed: 0)
        dockerStateText = "Resuming..."
        dockerStateColor = .orange

        dockerPollingTask = Task {
            do {
                try await engineBridge.unpauseDockerDesktop()
            } catch {
                self.phase = .failed(
                    message: "Could not automatically resume Docker Desktop.",
                    details: "Docker Desktop is paused. Please resume it through the Whale menu or Dashboard, then click Retry."
                )
                self.technicalDetails = error.localizedDescription
                return
            }

            var elapsed = 0
            let maxWaitSec = 20

            while !Task.isCancelled && elapsed < maxWaitSec {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                elapsed += 1
                self.phase = .startingDocker(secondsElapsed: elapsed)

                if let diag = try? await engineBridge.checkDocker(), diag.isReady {
                    self.updateDockerTelemetry(diag: diag)
                    await self.refreshStatus()
                    return
                }
            }

            if elapsed >= maxWaitSec {
                self.phase = .failed(
                    message: "Docker Desktop took too long to resume (timed out after \(maxWaitSec)s).",
                    details: "Please open Docker Desktop and resume it manually via the Whale menu or Dashboard, then click Retry."
                )
                self.technicalDetails = "Timeout waiting for Docker Desktop to unpause."
            }
        }
    }

    public func openDockerDesktop() {
        Task {
            _ = try? await engineBridge.launchDockerDesktop()
        }
    }

    // MARK: - Docker Lifecycle Actions

    public func startDockerDesktop() {
        dockerPollingTask?.cancel()
        phase = .startingDocker(secondsElapsed: 0)
        dockerStateText = "Starting..."
        dockerStateColor = .orange

        dockerPollingTask = Task {
            do {
                try await engineBridge.launchDockerDesktop()
            } catch {
                self.phase = .failed(
                    message: "Failed to dispatch Docker Desktop launch.",
                    details: error.localizedDescription
                )
                self.technicalDetails = error.localizedDescription
                return
            }

            var elapsed = 0
            let maxWaitSec = 75

            while !Task.isCancelled && elapsed < maxWaitSec {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                elapsed += 1
                self.phase = .startingDocker(secondsElapsed: elapsed)

                if let diag = try? await engineBridge.checkDocker() {
                    if diag.isReady {
                        self.updateDockerTelemetry(diag: diag)
                        await self.refreshStatus()
                        return
                    }
                    if diag.isPaused {
                        self.updateDockerTelemetry(diag: diag)
                        await self.refreshStatus()
                        return
                    }
                }
            }

            if elapsed >= maxWaitSec {
                self.phase = .failed(
                    message: "Docker Desktop took too long to start (timed out after \(maxWaitSec)s).",
                    details: "Please verify Docker Desktop is running and responsive, then click Retry."
                )
                self.technicalDetails = "Timeout waiting for Docker daemon socket."
            }
        }
    }

    public func downloadDockerDesktop() {
        Task {
            if let diag = try? await engineBridge.checkDocker(),
               let urlStr = diag.officialInstallerURL,
               let url = URL(string: urlStr) {
                NSWorkspace.shared.open(url)
            } else {
                let fallback = URL(string: "https://www.docker.com/products/docker-desktop/")!
                NSWorkspace.shared.open(fallback)
            }
        }
    }

    public func openDockerSettings() {
        Task {
            do {
                try await engineBridge.openDockerSettings()
            } catch {
                self.technicalDetails = error.localizedDescription
            }
        }
    }

    // MARK: - Directory Selection & Validation

    @discardableResult
    public func chooseCustomInstallDirectory() -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Choose an installation directory for Altr Stream"

        let expanded = NSString(string: self.installDir).expandingTildeInPath
        if FileManager.default.fileExists(atPath: expanded) {
            panel.directoryURL = URL(fileURLWithPath: expanded)
        } else {
            panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        }

        let response = panel.runModal()
        guard response == .OK, let selectedURL = panel.url else {
            return false // User cancelled selection
        }

        let chosenPath = selectedURL.path
        if let validationError = validateInstallDirectory(chosenPath) {
            self.technicalDetails = "Invalid installation path: \(validationError)"
            self.showTechnicalDetails = true
            return false
        }

        self.installDir = chosenPath
        return true
    }

    public func validateInstallDirectory(_ path: String) -> String? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "Installation directory cannot be empty."
        }

        let forbidden = ["/", "/System", "/Library", "/Applications", "/bin", "/sbin", "/usr", "/var", "/etc", "/dev"]
        for sysPath in forbidden {
            if trimmed == sysPath || (trimmed.hasPrefix(sysPath + "/") && (sysPath == "/System" || sysPath == "/bin" || sysPath == "/sbin" || sysPath == "/usr")) {
                return "Cannot install into protected system directory: \(trimmed)"
            }
        }

        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: trimmed, isDirectory: &isDir) {
            if !isDir.boolValue {
                return "Selected path is a file, not a directory: \(trimmed)"
            }
            if !FileManager.default.isWritableFile(atPath: trimmed) {
                return "Directory is not writeable: \(trimmed)"
            }
        } else {
            var ancestor = (trimmed as NSString).deletingLastPathComponent
            while !FileManager.default.fileExists(atPath: ancestor) && ancestor != "/" && !ancestor.isEmpty {
                ancestor = (ancestor as NSString).deletingLastPathComponent
            }
            if !FileManager.default.isWritableFile(atPath: ancestor) {
                return "Destination location is not writeable: \(ancestor)"
            }
        }

        return nil
    }

    // MARK: - Altr Stream Lifecycle Actions

    public func install(customLocation: Bool = false) {
        if customLocation {
            let selected = chooseCustomInstallDirectory()
            if !selected {
                // User cancelled directory selection, installation must not proceed
                return
            }
        }

        let expandedPath = NSString(string: self.installDir).expandingTildeInPath
        if let validationError = validateInstallDirectory(expandedPath) {
            self.technicalDetails = "Validation error: \(validationError)"
            self.showTechnicalDetails = true
            return
        }

        let initialProgress = InstallProgress(
            stage: "Preparing installation",
            stageIndex: 1,
            totalStages: 6,
            percent: 5,
            message: "Initializing deployment..."
        )
        self.phase = .installing(progress: initialProgress)
        self.isExecutingAction = true

        Task {
            do {
                try await engineBridge.install(targetDir: self.installDir) { progress in
                    Task { @MainActor in
                        self.phase = .installing(progress: progress)
                    }
                }
                await self.refreshStatus()
            } catch let EngineError.fileSharingRequired(message, path) {
                self.phase = .fileSharingRequired(message: message, path: path)
                self.technicalDetails = "FILE_SHARING_REQUIRED: \(path)\nDocker Desktop must be authorized to access this path in Settings > Resources > File Sharing."
            } catch {
                self.phase = .failed(
                    message: "Installation encountered an error.",
                    details: error.localizedDescription
                )
                self.technicalDetails = error.localizedDescription
            }
            self.isExecutingAction = false
        }
    }

    public func resolveConflictReplace() {
        let initialProgress = InstallProgress(
            stage: "Preparing clean installation",
            stageIndex: 1,
            totalStages: 6,
            percent: 5,
            message: "Removing conflicting container and reinstalling..."
        )
        self.phase = .installing(progress: initialProgress)
        self.isExecutingAction = true

        Task {
            do {
                try await engineBridge.install(targetDir: self.installDir, replaceExisting: true) { progress in
                    Task { @MainActor in
                        self.phase = .installing(progress: progress)
                    }
                }
                await self.refreshStatus()
            } catch let EngineError.fileSharingRequired(message, path) {
                self.phase = .fileSharingRequired(message: message, path: path)
                self.technicalDetails = "FILE_SHARING_REQUIRED: \(path)\nDocker Desktop must be authorized to access this path in Settings > Resources > File Sharing."
            } catch {
                self.phase = .failed(
                    message: "Installation encountered an error.",
                    details: error.localizedDescription
                )
                self.technicalDetails = error.localizedDescription
            }
            self.isExecutingAction = false
        }
    }

    public func resolveConflictStartExisting() {
        self.isExecutingAction = true
        Task {
            do {
                try await engineBridge.startContainer()
                await self.refreshStatus()
            } catch {
                self.phase = .failed(
                    message: "Failed to start existing container.",
                    details: error.localizedDescription
                )
                self.technicalDetails = error.localizedDescription
            }
            self.isExecutingAction = false
        }
    }

    public func startContainer() {
        self.isExecutingAction = true
        Task {
            do {
                try await engineBridge.startContainer()
                await self.refreshStatus()
            } catch {
                self.phase = .failed(
                    message: "Failed to start container.",
                    details: error.localizedDescription
                )
                self.technicalDetails = error.localizedDescription
            }
            self.isExecutingAction = false
        }
    }

    public func resumeContainer() {
        self.isExecutingAction = true
        Task {
            do {
                try await engineBridge.unpauseContainer()
                await self.refreshStatus()
            } catch {
                self.phase = .failed(
                    message: "Failed to resume container.",
                    details: error.localizedDescription
                )
                self.technicalDetails = error.localizedDescription
            }
            self.isExecutingAction = false
        }
    }

    public func showConflictDetails(_ conflict: ConflictInfo) {
        var lines: [String] = []
        if conflict.isPortConflict {
            lines.append("PORT CONFLICT ANALYSIS")
            lines.append("======================")
            lines.append("Conflict Type:      \(conflict.conflictType ?? "port")")
            lines.append("Conflicting Port:   \(conflict.conflictingPort ?? 8000)")
            lines.append("Occupied By:        \(conflict.occupiedBy ?? "unknown")")
            if let cName = conflict.containerName {
                lines.append("Container Name:     \(cName)")
            }
            if let id = conflict.containerID {
                lines.append("Container ID:       \(id)")
            }
            if let st = conflict.status {
                lines.append("Status:             \(st)")
            }
            if let img = conflict.image {
                lines.append("Image:              \(img)")
            }
            if let isDev = conflict.isDevContainer {
                lines.append("Dev Container:      \(isDev)")
            }
            if let ports = conflict.portMapping, !ports.isEmpty {
                lines.append("Port Mappings:      \(ports)")
            }
            if let hint = conflict.remediationHint {
                lines.append("")
                lines.append("Remediation Hint:")
                lines.append(hint)
            }
        } else {
            lines.append("CONTAINER CONFLICT ANALYSIS")
            lines.append("==========================")
            lines.append("Container Name: altr-stream")
            lines.append("Container ID:   \(conflict.containerID ?? "unknown")")
            lines.append("Status:         \(conflict.status ?? "unknown")")
            lines.append("Image:          \(conflict.image ?? "unknown")")
            lines.append("Created:        \(conflict.created ?? "unknown")")
            lines.append("Is Altr Stream: \(conflict.isAltrStream)")
            lines.append("Compatible:     \(conflict.isCompatible)")
            if let ports = conflict.portMapping, !ports.isEmpty {
                lines.append("Port Mappings:  \(ports)")
            }
            if let health = conflict.healthStatus, !health.isEmpty {
                lines.append("Health Status:  \(health)")
            }
        }
        if let raw = conflict.rawInspect, !raw.isEmpty {
            lines.append("")
            lines.append("RAW TELEMETRY:")
            lines.append(raw)
        }
        self.technicalDetails = lines.joined(separator: "\n")
        self.showTechnicalDetails = true
    }

    public func repair() {
        let initialProgress = InstallProgress(
            stage: "Restoring configuration",
            stageIndex: 1,
            totalStages: 4,
            percent: 10,
            message: "Checking files..."
        )
        self.phase = .repairing(progress: initialProgress)
        self.isExecutingAction = true

        Task {
            do {
                try await engineBridge.repair(targetDir: self.installDir) { progress in
                    Task { @MainActor in
                        self.phase = .repairing(progress: progress)
                    }
                }
                await self.refreshStatus()
            } catch {
                self.phase = .failed(
                    message: "Repair failed.",
                    details: error.localizedDescription
                )
                self.technicalDetails = error.localizedDescription
            }
            self.isExecutingAction = false
        }
    }

    public func uninstall() {
        guard !uninstallDeleteData || uninstallConfirmationInput == "DELETE ALTR STREAM DATA" else {
            return
        }

        self.showUninstallSheet = false
        self.phase = .checking
        self.isExecutingAction = true

        Task {
            do {
                try await engineBridge.uninstall(
                    targetDir: self.installDir,
                    deleteData: self.uninstallDeleteData
                )
                self.uninstallConfirmationInput = ""
                self.uninstallDeleteData = false
                await self.refreshStatus()
            } catch {
                self.phase = .failed(
                    message: "Uninstallation failed.",
                    details: error.localizedDescription
                )
                self.technicalDetails = error.localizedDescription
            }
            self.isExecutingAction = false
        }
    }

    public func openWebUI() {
        Task {
            do {
                try await engineBridge.launchBrowser()
            } catch {
                if let url = URL(string: "http://localhost:8000") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }

    public func cancelOngoingOperation() {
        dockerPollingTask?.cancel()
        dockerPollingTask = nil
        Task {
            await refreshStatus()
        }
    }
}
