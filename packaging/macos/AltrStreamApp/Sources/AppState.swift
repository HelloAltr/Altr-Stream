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
    public static var bundleAppVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "Unknown"
    }

    @Published public var phase: AppPhase = .checking
    @Published public var installDir: String = "~/.altr-stream"
    @Published public var appVersion: String = AppState.bundleAppVersion
    @Published public var applicationBundlePath: String = {
        let bundleURL = Bundle.main.bundleURL
        if bundleURL.path.hasSuffix(".app") {
            return bundleURL.path
        }
        return "/Applications/Altr Stream.app"
    }()

    // Dashboard Telemetry
    @Published public var dockerStateText: String = "Checking..."
    @Published public var dockerStateColor: Color = .gray
    @Published public var altrStateText: String = "Checking..."
    @Published public var altrStateColor: Color = .gray
    @Published public var activeNodeVersion: String? = nil
    @Published public var activeNodeImage: String? = nil
    @Published public var activeDataVolumeName: String? = nil

    // Published Releases & Discovery
    @Published public var releaseDiscoveryState: ReleaseDiscoveryState = .loading
    @Published public var discoveredReleases: [DiscoveredRelease] = DeveloperImageHelper.supportedKnownTags.map { tag in
        DiscoveredRelease(
            version: tag,
            tagName: "v\(tag)",
            isRecommended: (tag == DeveloperImageHelper.recommendedNodeVersion),
            isPrerelease: tag.contains("alpha") || tag.contains("beta"),
            imageRef: DeveloperImageHelper.formatImageReference(tagOrRef: tag),
            isImageVerified: true
        )
    }
    @Published public var latestPublishedNodeVersion: String = DeveloperImageHelper.recommendedNodeVersion
    @Published public var isCheckingForPublishedRelease: Bool = false
    @Published public var selectedVersion: String? = nil
    @Published public var selectedCustomImage: String = ""
    @Published public var isCustomVersionSelected: Bool = false
    @Published public var targetSwitchVersion: String? = nil
    @Published public var targetSwitchImage: String? = nil
    @Published public var showSwitchConfirmationAlert: Bool = false

    // Modal, Sheet, and Conflict state
    @Published public var showTechnicalDetails: Bool = false
    @Published public var technicalDetails: String = ""
    @Published public var showUninstallSheet: Bool = false
    @Published public var showUninstallConfirmationAlert: Bool = false
    @Published public var uninstallDeleteData: Bool = false
    @Published public var uninstallRemoveApp: Bool = false
    @Published public var uninstallConfirmationInput: String = ""
    @Published public var showStopDevContainerAlert: Bool = false
    @Published public var devContainerNameToStop: String? = nil
    @Published public var isExecutingAction: Bool = false

    // Image & Recommendation Helpers
    @Published public var selectedImageOverride: String? = nil

    private let engineBridge = EngineBridge.shared
    private var dockerPollingTask: Task<Void, Never>?

    public func canonicalImage() -> String {
        return DeveloperImageHelper.recommendedNodeImage
    }

    public func effectiveTargetImage() -> String {
        if isCustomVersionSelected, !selectedCustomImage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return DeveloperImageHelper.formatImageReference(tagOrRef: selectedCustomImage.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if let sel = selectedVersion, !sel.isEmpty {
            return DeveloperImageHelper.formatImageReference(tagOrRef: sel)
        }
        if let override = selectedImageOverride?.trimmingCharacters(in: .whitespacesAndNewlines), !override.isEmpty {
            return override
        }
        return canonicalImage()
    }

    public func isNonDefaultImageSelected() -> Bool {
        return effectiveTargetImage() != canonicalImage()
    }

    public func isNonDefaultImageActive() -> Bool {
        guard let active = activeNodeImage, !active.isEmpty else { return false }
        return active != canonicalImage()
    }

    public func clearDeveloperOverride() {
        self.selectedImageOverride = nil
        self.isCustomVersionSelected = false
        self.selectedCustomImage = ""
    }

    public func setDeveloperOverride(_ image: String?) {
        if let img = image?.trimmingCharacters(in: .whitespacesAndNewlines), !img.isEmpty, img != canonicalImage() {
            self.selectedImageOverride = img
        } else {
            self.selectedImageOverride = nil
        }
    }

    public func validateImageReference(_ image: String) async -> ImageValidationResult {
        return await engineBridge.validateImage(image: image)
    }

    public init() {
        Task {
            await refreshStatus()
            await checkForPublishedReleases()
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
            self.activeNodeVersion = nodeStatus.activeVersion
            self.activeNodeImage = nodeStatus.activeImage
            self.activeDataVolumeName = nodeStatus.dataVolumeName

            self.appVersion = AppState.bundleAppVersion

            let state = nodeStatus.lifecycleState

            switch state {
            case .running:
                let versionSuffix = (nodeStatus.activeVersion != nil && !nodeStatus.activeVersion!.isEmpty) ? " (v\(nodeStatus.activeVersion!))" : ""
                if nodeStatus.healthy {
                    self.altrStateText = "Running\(versionSuffix)"
                    self.altrStateColor = .green
                    self.phase = .running(nodeStatus)
                } else {
                    self.altrStateText = "Starting / Unhealthy\(versionSuffix)"
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
        panel.message = "Choose Data & Runtime Directory for Altr Stream"

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
        Task {
            _ = try? await engineBridge.provisionConfig(targetDir: chosenPath)
            await self.refreshStatus()
        }
        return true
    }

    public func revealApplicationInFinder() {
        let path = applicationBundlePath
        if FileManager.default.fileExists(atPath: path) {
            NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: (path as NSString).deletingLastPathComponent)
        } else {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: "/Applications")
        }
    }

    public func revealDataDirectoryInFinder() {
        let expanded = NSString(string: self.installDir).expandingTildeInPath
        if FileManager.default.fileExists(atPath: expanded) {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: expanded)
        } else {
            NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser)
        }
    }

    public func requestStopDevContainer(name: String) {
        self.devContainerNameToStop = name
        self.showStopDevContainerAlert = true
    }

    public func confirmStopDevContainer() {
        guard let name = self.devContainerNameToStop, !name.isEmpty else { return }
        self.showStopDevContainerAlert = false
        self.isExecutingAction = true
        Task {
            do {
                try await engineBridge.stopContainer(name: name)
                self.devContainerNameToStop = nil
                await self.refreshStatus()
            } catch {
                self.phase = .failed(
                    message: "Failed to stop development container '\(name)'.",
                    details: error.localizedDescription
                )
                self.technicalDetails = error.localizedDescription
            }
            self.isExecutingAction = false
        }
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

        let targetVer: String?
        let targetImg: String
        if isCustomVersionSelected {
            let custom = selectedCustomImage.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !custom.isEmpty else {
                self.technicalDetails = "No custom image reference specified."
                self.showTechnicalDetails = true
                return
            }
            targetImg = DeveloperImageHelper.formatImageReference(tagOrRef: custom)
            targetVer = DeveloperImageHelper.extractCleanDisplayTag(imageRef: custom)
        } else if let sel = selectedVersion, !sel.isEmpty {
            targetVer = sel
            targetImg = DeveloperImageHelper.formatImageReference(tagOrRef: sel)
        } else {
            // State 3: No version selected -> installation disabled
            return
        }

        let initialProgress = InstallProgress(
            stage: "Preparing installation",
            stageIndex: 1,
            totalStages: 6,
            percent: 5,
            message: "Initializing deployment of \(targetVer ?? targetImg)..."
        )
        self.phase = .installing(progress: initialProgress)
        self.isExecutingAction = true

        Task {
            do {
                try await engineBridge.install(
                    targetDir: self.installDir,
                    image: targetImg,
                    version: targetVer
                ) { progress in
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
                try await engineBridge.install(targetDir: self.installDir, replaceExisting: true, image: self.selectedImageOverride) { progress in
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
                let conflict = try? await engineBridge.checkConflict()
                if let c = conflict, c.exists && c.isAltrStream {
                    try await engineBridge.startContainer()
                } else {
                    let initialProgress = InstallProgress(
                        stage: "Starting Altr Stream",
                        stageIndex: 1,
                        totalStages: 6,
                        percent: 10,
                        message: "Initializing node container..."
                    )
                    self.phase = .installing(progress: initialProgress)
                    try await engineBridge.install(targetDir: self.installDir, image: self.selectedImageOverride) { progress in
                        Task { @MainActor in
                            self.phase = .installing(progress: progress)
                        }
                    }
                }
                await self.refreshStatus()
            } catch let EngineError.fileSharingRequired(message, path) {
                self.phase = .fileSharingRequired(message: message, path: path)
                self.technicalDetails = "FILE_SHARING_REQUIRED: \(path)\nDocker Desktop must be authorized to access this path in Settings > Resources > File Sharing."
            } catch {
                self.phase = .failed(
                    message: "Failed to start Altr Stream node.",
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
                try await engineBridge.repair(targetDir: self.installDir, image: self.selectedImageOverride) { progress in
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

    // MARK: - Node Release & Update Management

    public var isNodeUpdateAvailable: Bool {
        guard let active = activeNodeVersion, !active.isEmpty else { return false }
        if let img = activeNodeImage, DeveloperImageHelper.isLocalDevImage(tagOrRef: img) {
            return false
        }
        if DeveloperImageHelper.isLocalDevImage(tagOrRef: active) {
            return false
        }
        return DeveloperImageHelper.isVersion(latestPublishedNodeVersion, newerThan: active)
    }

    public func checkForPublishedReleases() async {
        guard !isCheckingForPublishedRelease else { return }
        isCheckingForPublishedRelease = true
        releaseDiscoveryState = .loading
        defer { isCheckingForPublishedRelease = false }

        guard let url = URL(string: "https://api.github.com/repos/HelloAltr/Altr-Stream/releases") else {
            handleReleaseFetchError("Invalid GitHub releases URL.")
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 7.0
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.setValue("Altr-Stream-Manager/\(appVersion)", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                handleReleaseFetchError("Invalid HTTP response.")
                return
            }
            if httpResponse.statusCode == 200 {
                struct GitHubRelease: Decodable {
                    let tagName: String
                    let draft: Bool
                    let prerelease: Bool
                    enum CodingKeys: String, CodingKey {
                        case tagName = "tag_name"
                        case draft
                        case prerelease
                    }
                }
                let rawReleases = try JSONDecoder().decode([GitHubRelease].self, from: data)
                var candidates: [DiscoveredRelease] = []
                for r in rawReleases {
                    if r.draft { continue }
                    let clean = r.tagName.hasPrefix("v") ? String(r.tagName.dropFirst()) : r.tagName
                    let trimmed = clean.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty, DeveloperImageHelper.validateCustomImageSyntax(trimmed) == nil else { continue }
                    let imgRef = DeveloperImageHelper.formatImageReference(tagOrRef: trimmed)
                    let isRec = (trimmed == DeveloperImageHelper.recommendedNodeVersion)
                    candidates.append(DiscoveredRelease(
                        version: trimmed,
                        tagName: r.tagName,
                        isRecommended: isRec,
                        isPrerelease: r.prerelease,
                        imageRef: imgRef,
                        isImageVerified: true
                    ))
                }

                candidates.sort { DeveloperImageHelper.isVersion($0.version, newerThan: $1.version) }

                if candidates.isEmpty {
                    self.discoveredReleases = []
                    self.releaseDiscoveryState = .empty
                } else {
                    self.discoveredReleases = candidates
                    self.releaseDiscoveryState = .success(candidates, isStale: false)
                    if let first = candidates.first {
                        self.latestPublishedNodeVersion = first.version
                    }
                }
            } else if httpResponse.statusCode == 403 || httpResponse.statusCode == 429 {
                handleReleaseFetchError("GitHub API rate limit encountered. Showing cached releases.")
            } else {
                handleReleaseFetchError("GitHub returned status code \(httpResponse.statusCode).")
            }
        } catch {
            handleReleaseFetchError(error.localizedDescription)
        }
    }

    private func handleReleaseFetchError(_ msg: String) {
        if !discoveredReleases.isEmpty {
            releaseDiscoveryState = .success(discoveredReleases, isStale: true)
        } else {
            let fallbacks = DeveloperImageHelper.supportedKnownTags.map { tag in
                DiscoveredRelease(
                    version: tag,
                    tagName: "v\(tag)",
                    isRecommended: (tag == DeveloperImageHelper.recommendedNodeVersion),
                    isPrerelease: tag.contains("alpha") || tag.contains("beta"),
                    imageRef: DeveloperImageHelper.formatImageReference(tagOrRef: tag),
                    isImageVerified: true
                )
            }
            self.discoveredReleases = fallbacks
            self.releaseDiscoveryState = .success(fallbacks, isStale: true)
        }
    }

    public func requestSwitchToVersion(version: String, customImage: String? = nil) {
        if let custom = customImage, !custom.isEmpty {
            let trimmed = custom.trimmingCharacters(in: .whitespacesAndNewlines)
            self.targetSwitchImage = DeveloperImageHelper.formatImageReference(tagOrRef: trimmed)
            self.targetSwitchVersion = DeveloperImageHelper.extractCleanDisplayTag(imageRef: trimmed)
        } else {
            self.targetSwitchVersion = version
            self.targetSwitchImage = DeveloperImageHelper.formatImageReference(tagOrRef: version)
        }
        self.showSwitchConfirmationAlert = true
    }

    public func confirmSwitchVersion() {
        guard let img = targetSwitchImage else { return }
        let ver = targetSwitchVersion
        self.showSwitchConfirmationAlert = false
        self.switchNodeVersion(targetImage: img, targetVersion: ver)
    }

    public func requestNodeUpdate() {
        requestSwitchToVersion(version: latestPublishedNodeVersion)
    }

    public func confirmNodeUpdate() {
        confirmSwitchVersion()
    }

    public func requestResetToRecommended() {
        requestSwitchToVersion(version: DeveloperImageHelper.recommendedNodeVersion)
    }

    public func confirmResetToRecommended() {
        confirmSwitchVersion()
    }

    // MARK: - Version Switching

    public func switchNodeVersion(targetImage: String, targetVersion: String? = nil) {
        let initialProgress = InstallProgress(
            stage: "Validating target image",
            stageIndex: 1,
            totalStages: 5,
            percent: 10,
            message: "Validating and preparing switch to \(targetImage)..."
        )
        self.phase = .installing(progress: initialProgress)
        self.isExecutingAction = true

        Task {
            do {
                try await engineBridge.switchVersion(
                    targetDir: self.installDir,
                    image: targetImage,
                    version: targetVersion
                ) { progress in
                    Task { @MainActor in
                        self.phase = .installing(progress: progress)
                    }
                }
                if targetImage == self.canonicalImage() {
                    self.clearDeveloperOverride()
                } else {
                    self.setDeveloperOverride(targetImage)
                }
                await self.refreshStatus()
            } catch {
                await self.refreshStatus()
                self.phase = .failed(
                    message: "Version switch failed.",
                    details: error.localizedDescription
                )
                self.technicalDetails = error.localizedDescription
            }
            self.isExecutingAction = false
        }
    }

    // MARK: - Uninstall Safety & Bundle Resolution

    public func buildUninstallSummaryMessage() -> String {
        let volName = activeDataVolumeName ?? "altr_stream_data"
        var lines: [String] = []
        lines.append("The following actions will be performed:")
        lines.append("• Remove Altr Stream Docker containers and networks")
        if uninstallDeleteData {
            lines.append("• PERMANENTLY DELETE all persistent application data (volume '\(volName)' and '\(installDir)')")
        } else {
            lines.append("• PRESERVE all persistent application data (volume '\(volName)' and '\(installDir)' will be kept)")
        }
        if uninstallRemoveApp {
            lines.append("• Move desktop application bundle to Trash after exit")
        } else {
            lines.append("• Retain desktop application bundle")
        }
        lines.append("\nAre you sure you want to proceed with uninstallation?")
        return lines.joined(separator: "\n")
    }

    public func resolveInstalledApplicationBundle() -> String? {
        let standardPath = "/Applications/Altr Stream.app"
        let runningPath = Bundle.main.bundleURL.path

        if runningPath.hasPrefix("/Applications/") && runningPath.hasSuffix(".app") && runningPath.contains("Altr Stream") {
            return runningPath
        }

        if FileManager.default.fileExists(atPath: standardPath) {
            return standardPath
        }

        let userAppPath = NSString(string: "~/Applications/Altr Stream.app").expandingTildeInPath
        if FileManager.default.fileExists(atPath: userAppPath) {
            return userAppPath
        }

        return nil
    }

    public func validateApplicationBundleForRemoval(path: String) -> Bool {
        guard path.hasSuffix(".app"),
              path.contains("Altr Stream"),
              path != "/",
              path != "/Applications",
              path != "/Applications/",
              !path.contains("/dist/"),
              !path.contains("/.build/"),
              !path.contains("/DerivedData/") else {
            return false
        }

        let inSystemApps = path.hasPrefix("/Applications/")
        let userAppsPrefix = NSString(string: "~/Applications/").expandingTildeInPath
        let inUserApps = path.hasPrefix(userAppsPrefix)

        guard inSystemApps || inUserApps else {
            return false
        }

        return true
    }

    public func scheduleDeferredTrashRemoval(targetAppPath: String) -> Bool {
        guard validateApplicationBundleForRemoval(path: targetAppPath) else {
            return false
        }

        let pid = ProcessInfo.processInfo.processIdentifier
        let escapedPath = targetAppPath.replacingOccurrences(of: "\"", with: "\\\"")

        let shellScript = """
        (
            while kill -0 \(pid) 2>/dev/null; do
                sleep 0.2
            done
            /usr/bin/osascript -e 'tell application "Finder" to delete (POSIX file "\(escapedPath)")' >/dev/null 2>&1
            if [ -d "\(escapedPath)" ]; then
                /bin/rm -rf "\(escapedPath)" >/dev/null 2>&1
            fi
        ) >/dev/null 2>&1 &
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", shellScript]

        do {
            try process.run()
            return true
        } catch {
            return false
        }
    }

    public func uninstall() {
        guard !uninstallDeleteData || uninstallConfirmationInput == "DELETE ALTR STREAM DATA" else {
            return
        }

        self.showUninstallSheet = false
        self.phase = .checking
        self.isExecutingAction = true

        let shouldRemoveApp = self.uninstallRemoveApp

        Task {
            do {
                // Step 1: Remove Altr Stream Docker/runtime resources (and persistent data if confirmed)
                try await engineBridge.uninstall(
                    targetDir: self.installDir,
                    deleteData: self.uninstallDeleteData
                )
                self.uninstallConfirmationInput = ""
                self.uninstallDeleteData = false
                self.uninstallRemoveApp = false

                // Step 2: If requested, remove the desktop application bundle after runtime cleanup completes
                if shouldRemoveApp {
                    guard let targetAppPath = self.resolveInstalledApplicationBundle(),
                          self.validateApplicationBundleForRemoval(path: targetAppPath) else {
                        self.phase = .failed(
                            message: "Runtime files cleaned up, but no installed /Applications bundle found to remove.",
                            details: "Development copies under dist/ and unverified paths are protected from automatic removal."
                        )
                        self.technicalDetails = "Safety check: No valid installed application bundle found in /Applications."
                        self.isExecutingAction = false
                        return
                    }

                    let scheduled = self.scheduleDeferredTrashRemoval(targetAppPath: targetAppPath)
                    if scheduled {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            NSApplication.shared.terminate(nil)
                        }
                        return
                    } else {
                        self.phase = .failed(
                            message: "Runtime files cleaned up, but could not schedule application removal.",
                            details: "You may manually move \(targetAppPath) to Trash."
                        )
                        self.technicalDetails = "Failed to spawn deferred removal process for \(targetAppPath)."
                        self.isExecutingAction = false
                        return
                    }
                }

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
