import SwiftUI
import AppKit

public struct ContentView: View {
    @EnvironmentObject private var state: AppState

    public init() {}

    public var body: some View {
        VStack(spacing: 18) {
            headerSection
            dashboardCard
            Divider()
            actionSection
            Spacer()
            footerSection
        }
        .padding(22)
        .frame(width: 560, height: 500)
        .sheet(isPresented: $state.showTechnicalDetails) {
            technicalDetailsSheet
        }
        .sheet(isPresented: $state.showUninstallSheet) {
            uninstallSheet
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(alignment: .center) {
            Image(systemName: "server.rack")
                .font(.system(size: 32))
                .foregroundColor(.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text("Altr Stream")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("v\(state.appVersion)")
                        .font(.caption)
                        .fontWeight(.medium)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.15))
                        .cornerRadius(4)
                }

                Text("Local Production Node Manager")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: {
                Task { await state.refreshStatus() }
            }) {
                Image(systemName: "arrow.clockwise")
                    .font(.body)
            }
            .buttonStyle(.plain)
            .disabled(state.isExecutingAction)
            .help("Refresh Status")
        }
    }

    // MARK: - Dashboard Card

    private var dashboardCard: some View {
        VStack(spacing: 12) {
            // Docker Status Row
            HStack {
                Label {
                    Text("Docker Desktop")
                        .font(.body)
                        .fontWeight(.medium)
                } icon: {
                    Circle()
                        .fill(state.dockerStateColor)
                        .frame(width: 10, height: 10)
                }

                Spacer()

                Text(state.dockerStateText)
                    .font(.subheadline)
                    .foregroundColor(state.dockerStateColor)
                    .fontWeight(.semibold)
            }

            Divider()

            // Altr Stream Status Row
            HStack {
                Label {
                    Text("Altr Stream Node")
                        .font(.body)
                        .fontWeight(.medium)
                } icon: {
                    Circle()
                        .fill(state.altrStateColor)
                        .frame(width: 10, height: 10)
                }

                Spacer()

                Text(state.altrStateText)
                    .font(.subheadline)
                    .foregroundColor(state.altrStateColor)
                    .fontWeight(.semibold)
            }

            Divider()

            // Install Path Row
            HStack {
                Label {
                    Text("Install Path")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } icon: {
                    Image(systemName: "folder")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Text(state.installDir)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .truncationMode(.middle)

                if case .readyToInstall = state.phase {
                    Button("Change...") {
                        state.chooseCustomInstallDirectory()
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }
            }
        }
        .padding(14)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - Contextual Action Section

    @ViewBuilder
    private var actionSection: some View {
        switch state.phase {
        case .checking:
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.regular)
                Text("Checking environment and Docker status...")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .dockerNotInstalled:
            VStack(spacing: 12) {
                Label("Docker Desktop is Required", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundColor(.red)

                Text("Altr Stream requires Docker Desktop for macOS to manage its containerized node.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                HStack(spacing: 12) {
                    Button("Download Docker Desktop") {
                        state.downloadDockerDesktop()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Retry Check") {
                        Task { await state.refreshStatus() }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .dockerPaused:
            VStack(spacing: 12) {
                Label("Docker Desktop is Paused", systemImage: "pause.circle.fill")
                    .font(.headline)
                    .foregroundColor(.orange)

                Text("Docker Desktop is currently paused or suspended. Resume Docker Desktop to continue.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                HStack(spacing: 12) {
                    Button("Resume Docker Desktop") {
                        state.resumeDockerDesktop()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Open Docker Desktop") {
                        state.openDockerDesktop()
                    }

                    Button("Retry Check") {
                        Task { await state.refreshStatus() }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .dockerStopped:
            VStack(spacing: 12) {
                Label("Docker Desktop is Stopped", systemImage: "stop.circle.fill")
                    .font(.headline)
                    .foregroundColor(.secondary)

                Text("The Docker background service is not running. Start Docker Desktop to continue.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                HStack(spacing: 12) {
                    Button("Start Docker Desktop") {
                        state.startDockerDesktop()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Retry Check") {
                        Task { await state.refreshStatus() }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .startingDocker(let elapsed):
            VStack(spacing: 14) {
                ProgressView()
                    .controlSize(.regular)

                Text(state.dockerStateText == "Resuming..." ? "Resuming Docker Desktop..." : "Starting Docker Desktop...")
                    .font(.headline)

                Text(state.dockerStateText == "Resuming..." ?
                    "Please wait while Docker Desktop resumes (\(elapsed)s elapsed)." :
                    "Please wait while the Docker background service starts (\(elapsed)s elapsed).")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Button("Cancel") {
                    state.cancelOngoingOperation()
                }
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .readyToInstall:
            VStack(spacing: 14) {
                Label("Ready for Installation", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundColor(.green)

                Text("Docker Desktop is active. Initialize your Altr Stream node below.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                HStack(spacing: 12) {
                    Button("Install Altr Stream") {
                        state.install()
                    }
                    .buttonStyle(.borderedProminent)
                    .actionButton(minWidth: 140)

                    Button("Choose Location & Install...") {
                        state.install(customLocation: true)
                    }
                    .buttonStyle(.bordered)
                    .actionButton(minWidth: 180)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .conflictDetected(let conflict):
            conflictSection(conflict)

        case .installing(let progress):
            VStack(spacing: 10) {
                ProgressView(value: Double(progress.percent), total: 100.0)
                    .progressViewStyle(.linear)

                HStack {
                    Text(progress.stage)
                        .font(.headline)
                    Spacer()
                    Text("\(progress.percent)%")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }

                Text(progress.message)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .repairing(let progress):
            VStack(spacing: 10) {
                ProgressView(value: Double(progress.percent), total: 100.0)
                    .progressViewStyle(.linear)

                HStack {
                    Text("Repairing: \(progress.stage)")
                        .font(.headline)
                    Spacer()
                    Text("\(progress.percent)%")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }

                Text(progress.message)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .running(let status):
            VStack(spacing: 14) {
                Label("Altr Stream is Running", systemImage: "checkmark.seal.fill")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.green)

                Text("Web Interface available at: \(status.webURL)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                HStack(spacing: 12) {
                    Button("Open Altr Stream") {
                        state.openWebUI()
                    }
                    .buttonStyle(.borderedProminent)
                    .actionButton()

                    Button("Repair") {
                        state.repair()
                    }
                    .buttonStyle(.bordered)
                    .actionButton()

                    Button("Uninstall...") {
                        state.showUninstallSheet = true
                    }
                    .buttonStyle(.bordered)
                    .actionButton()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .paused(let status):
            VStack(spacing: 14) {
                Label("Altr Stream Node is Paused", systemImage: "pause.circle.fill")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.orange)

                Text("The container is currently paused in Docker Desktop.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                HStack(spacing: 12) {
                    Button("Resume Node") {
                        state.resumeContainer()
                    }
                    .buttonStyle(.borderedProminent)
                    .actionButton()

                    Button("Repair") {
                        state.repair()
                    }
                    .buttonStyle(.bordered)
                    .actionButton()

                    Button("Uninstall...") {
                        state.showUninstallSheet = true
                    }
                    .buttonStyle(.bordered)
                    .actionButton()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .stopped(let status):
            VStack(spacing: 14) {
                Label("Altr Stream Node is Stopped", systemImage: "stop.circle.fill")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)

                Text("The container is installed but currently not running.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                HStack(spacing: 12) {
                    Button("Start Altr Stream") {
                        state.startContainer()
                    }
                    .buttonStyle(.borderedProminent)
                    .actionButton()

                    Button("Repair") {
                        state.repair()
                    }
                    .buttonStyle(.bordered)
                    .actionButton()

                    Button("Uninstall...") {
                        state.showUninstallSheet = true
                    }
                    .buttonStyle(.bordered)
                    .actionButton()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .fileSharingRequired(let message, let path):
            VStack(spacing: 12) {
                Label("File Sharing Permission Required", systemImage: "lock.shield.fill")
                    .font(.headline)
                    .foregroundColor(.orange)

                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)

                if !path.isEmpty {
                    Text(path)
                        .font(.system(.caption, design: .monospaced))
                        .padding(6)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(4)
                }

                HStack(spacing: 12) {
                    Button("Open Docker Settings") {
                        state.openDockerSettings()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Retry") {
                        state.install()
                    }
                    .buttonStyle(.bordered)

                    Button("Technical Details") {
                        state.showTechnicalDetails = true
                    }
                    .buttonStyle(.borderless)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .failed(let message, _):
            VStack(spacing: 12) {
                Label("Operation Failed", systemImage: "xmark.octagon.fill")
                    .font(.headline)
                    .foregroundColor(.red)

                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                HStack(spacing: 12) {
                    Button("Retry") {
                        Task { await state.refreshStatus() }
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Technical Details") {
                        state.showTechnicalDetails = true
                    }
                    .buttonStyle(.bordered)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Conflict Resolution Section

    @ViewBuilder
    private func conflictSection(_ conflict: ConflictInfo) -> some View {
        if conflict.isPortConflict {
            VStack(spacing: 12) {
                Label("Port Conflict Detected", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundColor(.orange)

                if let hint = conflict.remediationHint, !hint.isEmpty {
                    Text(hint)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                } else if let occ = conflict.occupiedBy, !occ.isEmpty {
                    Text("Port \(conflict.conflictingPort ?? 8000) is already in use by container '\(occ)'.\n\nPlease stop the conflicting service and retry.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                } else {
                    Text("Port \(conflict.conflictingPort ?? 8000) is already in use by another application or process.\n\nPlease close the application using port \(conflict.conflictingPort ?? 8000) and retry.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }

                HStack(spacing: 12) {
                    Button("Retry Check") {
                        Task { await state.refreshStatus() }
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Technical Details") {
                        state.showConflictDetails(conflict)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 12) {
                Label(
                    conflict.isAltrStream ? "Existing Altr Stream Container Found" : "Container Conflict Detected",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.headline)
                .foregroundColor(.orange)

                if conflict.isAltrStream {
                    Text("A previous Altr Stream container (Image: \(conflict.image ?? "unknown"), Status: \(conflict.status ?? "unknown")) is present on your system.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                } else {
                    Text("Another container named 'altr-stream' (Image: \(conflict.image ?? "unknown")) already exists on your Docker host.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }

                Text("Replacing the container will remove the old container while preserving all persistent data volumes.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                HStack(spacing: 12) {
                    if conflict.isCompatible && conflict.status != "running" {
                        Button(conflict.status == "paused" ? "Resume Existing Container" : "Start Existing Container") {
                            state.resolveConflictStartExisting()
                        }
                        .buttonStyle(.bordered)
                    }

                    Button(conflict.isAltrStream ? "Replace Container & Reinstall" : "Replace Conflicting Container") {
                        state.resolveConflictReplace()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Technical Details") {
                        state.showConflictDetails(conflict)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Footer

    private var footerSection: some View {
        HStack {
            if !state.technicalDetails.isEmpty {
                Button("Technical Details") {
                    state.showTechnicalDetails = true
                }
                .buttonStyle(.link)
                .font(.caption)
            }

            Spacer()
        }
    }

    // MARK: - Technical Details Sheet

    private var technicalDetailsSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Technical Details")
                    .font(.headline)
                Spacer()
                Button("Done") {
                    state.showTechnicalDetails = false
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            ScrollView {
                Text(state.technicalDetails.isEmpty ? "No active error diagnostics." : state.technicalDetails)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(8)
            }
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            )

            HStack {
                Button("Copy to Clipboard") {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(state.technicalDetails, forType: .string)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer()
            }
        }
        .padding(20)
        .frame(width: 500, height: 350)
    }

    // MARK: - Uninstall Sheet

    private var uninstallSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Uninstall Altr Stream")
                .font(.title3)
                .fontWeight(.bold)

            Text("This will stop and remove the Altr Stream container node.")
                .font(.subheadline)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                Toggle(isOn: $state.uninstallDeleteData) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Delete persistent application data")
                            .fontWeight(.medium)
                        Text("Destroys volume 'altr_stream_data'. By default, data is preserved.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .toggleStyle(.checkbox)

                if state.uninstallDeleteData {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("To confirm destructive data deletion, type:")
                            .font(.caption)
                            .foregroundColor(.red)
                        Text("DELETE ALTR STREAM DATA")
                            .font(.system(.caption, design: .monospaced))
                            .fontWeight(.bold)
                            .foregroundColor(.red)

                        TextField("Confirmation text", text: $state.uninstallConfirmationInput)
                            .textFieldStyle(.roundedBorder)
                    }
                    .padding(10)
                    .background(Color.red.opacity(0.08))
                    .cornerRadius(6)
                }
            }

            Spacer()

            HStack {
                Button("Cancel") {
                    state.showUninstallSheet = false
                    state.uninstallDeleteData = false
                    state.uninstallConfirmationInput = ""
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Uninstall") {
                    state.uninstall()
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(state.uninstallDeleteData && state.uninstallConfirmationInput != "DELETE ALTR STREAM DATA")
            }
        }
        .padding(22)
        .frame(width: 480, height: 330)
    }
}

// MARK: - Reusable Action Button Modifier

struct RunningActionButtonModifier: ViewModifier {
    var minWidth: CGFloat = 130
    var height: CGFloat = 32

    func body(content: Content) -> some View {
        content
            .controlSize(.regular)
            .lineLimit(1)
            .padding(.horizontal, 4)
            .frame(minWidth: minWidth, minHeight: height)
    }
}

extension View {
    func actionButton(minWidth: CGFloat = 130) -> some View {
        self.modifier(RunningActionButtonModifier(minWidth: minWidth))
    }
}

