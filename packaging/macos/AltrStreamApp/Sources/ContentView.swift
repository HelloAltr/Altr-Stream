import SwiftUI
import AppKit

// MARK: - Design Tokens & Theme

public struct AltrTheme {
    public static let windowBackground = Color(hex: "191D26")
    public static let titleBarBackground = Color(hex: "252B37")
    public static let panelBackground = Color(hex: "151B25")
    public static let border = Color(hex: "303744")
    public static let dropdownBorder = Color(hex: "3A4352")
    public static let dropdownBackground = Color(hex: "1C2330")
    public static let primaryBlue = Color(hex: "0878F9")
    public static let successGreen = Color(hex: "20DC79")
    public static let linkBlue = Color(hex: "35AAFF")
    public static let secondaryText = Color(hex: "AEB7C7")
    public static let descriptionText = Color(hex: "C0C7D5")
    public static let secondaryButton = Color(hex: "3B404C")
    public static let errorRed = Color(hex: "FF5B61")
    public static let warningOrange = Color(hex: "FF9F2F")
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Button Styles

public struct AltrPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(.white.opacity(isEnabled ? 1.0 : 0.4))
            .padding(.horizontal, 14)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isEnabled ? (configuration.isPressed ? AltrTheme.primaryBlue.opacity(0.8) : AltrTheme.primaryBlue) : AltrTheme.primaryBlue.opacity(0.35))
            )
            .contentShape(Rectangle())
    }
}

public struct AltrSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(.white.opacity(isEnabled ? 1.0 : 0.4))
            .padding(.horizontal, 14)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isEnabled ? (configuration.isPressed ? AltrTheme.secondaryButton.opacity(0.7) : AltrTheme.secondaryButton) : AltrTheme.secondaryButton.opacity(0.35))
            )
            .contentShape(Rectangle())
    }
}

public struct AltrTableSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(.white.opacity(isEnabled ? 1.0 : 0.4))
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isEnabled ? (configuration.isPressed ? AltrTheme.secondaryButton.opacity(0.7) : AltrTheme.secondaryButton) : AltrTheme.secondaryButton.opacity(0.35))
            )
            .contentShape(Rectangle())
    }
}

// MARK: - Main ContentView

public struct ContentView: View {
    @EnvironmentObject private var state: AppState

    @State private var showCustomVersionSheet: Bool = false
    @State private var customVersionInput: String = ""

    public init() {}

    public var body: some View {
        VStack(spacing: 16) {
            headerSection
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 16) {
                    dashboardCard
                    Rectangle()
                        .fill(AltrTheme.border)
                        .frame(height: 1)
                    actionSection
                        .padding(.vertical, 2)
                }
            }
            footerSection
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 16)
        .frame(minWidth: 540, idealWidth: 868, minHeight: 460, idealHeight: 662)
        .background(AltrTheme.windowBackground)
        .sheet(isPresented: $state.showTechnicalDetails) {
            technicalDetailsSheet
        }
        .sheet(isPresented: $state.showUninstallSheet) {
            uninstallSheet
        }
        .alert("Stop Development Container?", isPresented: $state.showStopDevContainerAlert) {
            Button("Cancel", role: .cancel) {
                state.devContainerNameToStop = nil
            }
            Button("Stop Container", role: .destructive) {
                state.confirmStopDevContainer()
            }
        } message: {
            Text("This will execute 'docker stop' on development container '\(state.devContainerNameToStop ?? "")'.\n\nThe container will NOT be removed or deleted, and all files and volumes remain untouched.")
        }
        .alert("Confirm Version Switch", isPresented: $state.showSwitchConfirmationAlert) {
            Button("Cancel", role: .cancel) {
                state.targetSwitchVersion = nil
                state.targetSwitchImage = nil
            }
            Button(state.targetSwitchVersion != nil ? "Switch to v\(state.targetSwitchVersion!)" : "Switch Version") {
                state.confirmSwitchVersion()
            }
        } message: {
            let pendingTargetImage = state.targetSwitchImage ?? state.targetSwitchVersion ?? "selected version"
            let cleanTag = DeveloperImageHelper.extractCleanDisplayTag(imageRef: pendingTargetImage)
            Text("The Altr Stream Node will be switched to:\n\nv\(cleanTag)\n\nAll persistent data in 'altr_stream_data' will be preserved.\n\nDo you want to proceed?")
        }
        .alert("Custom Version Reference", isPresented: $showCustomVersionSheet) {
            TextField("Tag or image (e.g. 1.0.0-beta)", text: $customVersionInput)
            Button("Cancel", role: .cancel) {
                customVersionInput = ""
            }
            Button(state.activeNodeVersion != nil ? "Switch Version" : "Select Version") {
                let trimmed = customVersionInput.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                if state.activeNodeVersion != nil {
                    state.requestSwitchToVersion(version: trimmed, customImage: trimmed)
                } else {
                    state.isCustomVersionSelected = true
                    state.selectedCustomImage = trimmed
                    state.selectedVersion = trimmed
                }
                customVersionInput = ""
            }
        } message: {
            Text("Enter a custom Docker image reference or release tag to deploy.")
        }
    }

    private func handleVersionSelection(version: String) {
        if let current = state.activeNodeVersion, !current.isEmpty {
            if version != current {
                state.requestSwitchToVersion(version: version)
            }
        } else {
            state.selectedVersion = version
            state.isCustomVersionSelected = false
        }
    }

    private var dockerStatusColor: Color {
        if state.dockerStateText == "Ready" {
            return AltrTheme.successGreen
        } else if state.dockerStateText == "Paused" || state.dockerStateText == "Resuming..." {
            return AltrTheme.warningOrange
        } else if state.dockerStateText == "Stopped" {
            return AltrTheme.errorRed
        } else {
            return AltrTheme.errorRed
        }
    }

    private var altrStatusColor: Color {
        if state.altrStateText.contains("Running") {
            return AltrTheme.successGreen
        } else if state.altrStateText.contains("Paused") {
            return AltrTheme.warningOrange
        } else if state.altrStateText.contains("Not Installed") || state.altrStateText.contains("Docker Required") {
            return AltrTheme.errorRed
        } else if state.altrStateText.contains("Installing") || state.altrStateText.contains("Starting") {
            return .white
        } else if state.altrStateText.contains("Conflict") {
            return AltrTheme.warningOrange
        } else {
            return AltrTheme.secondaryText
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "server.rack")
                .font(.system(size: 26))
                .foregroundColor(AltrTheme.primaryBlue)
                .frame(width: 38, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text("Altr Stream")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)

                Text("Local Production Node Manager")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(AltrTheme.secondaryText)
            }

            Spacer()

            Button(action: {
                Task {
                    await state.refreshStatus()
                    await state.checkForPublishedReleases()
                }
            }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(AltrTheme.secondaryText)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(state.isExecutingAction)
            .help("Refresh Status")
        }
        .frame(height: 52)
    }

    // MARK: - Status & Configuration Panel

    private var dashboardCard: some View {
        VStack(spacing: 0) {
            // Row 1: Docker Desktop
            HStack(alignment: .center) {
                HStack(spacing: 10) {
                    Circle()
                        .fill(dockerStatusColor)
                        .frame(width: 9, height: 9)

                    Text("Docker Desktop")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
                }

                Spacer()

                Text(state.dockerStateText)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(dockerStatusColor)
            }
            .frame(height: 42)

            Rectangle()
                .fill(AltrTheme.border)
                .frame(height: 1)

            // Row 2: Altr Stream Node
            HStack(alignment: .center) {
                HStack(spacing: 10) {
                    Circle()
                        .fill(altrStatusColor)
                        .frame(width: 9, height: 9)

                    Text("Altr Stream Node")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
                }

                Spacer()

                Text(state.altrStateText)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(altrStatusColor)
            }
            .frame(height: 42)

            Rectangle()
                .fill(AltrTheme.border)
                .frame(height: 1)

            // Row 3: Altr Stream Node Version
            versionSwitcherCard
                .frame(minHeight: state.activeNodeVersion != nil ? 74 : 44)

            Rectangle()
                .fill(AltrTheme.border)
                .frame(height: 1)

            // Row 4: Data & Runtime
            HStack(alignment: .center) {
                HStack(spacing: 10) {
                    Image(systemName: "folder")
                        .font(.system(size: 15))
                        .foregroundColor(AltrTheme.secondaryText)
                        .frame(width: 18, height: 18)

                    Text("Data & Runtime")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 6) {
                    Text(state.installDir)
                        .font(.system(size: 12, weight: .regular, design: .monospaced))
                        .foregroundColor(AltrTheme.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 420, alignment: .trailing)

                    HStack(spacing: 10) {
                        Button("Change Installation Path") {
                            state.chooseCustomInstallDirectory()
                        }
                        .buttonStyle(AltrTableSecondaryButtonStyle())
                        .disabled(state.isExecutingAction)

                        Button("Reveal in Finder") {
                            state.revealDataDirectoryInFinder()
                        }
                        .buttonStyle(AltrTableSecondaryButtonStyle())
                        .disabled(state.isExecutingAction)
                    }
                }
            }
            .frame(minHeight: 74)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 4)
        .background(AltrTheme.panelBackground)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(AltrTheme.border, lineWidth: 1)
        )
    }

    // MARK: - Contextual Action Section (States 1 to 12)

    @ViewBuilder
    private var actionSection: some View {
        switch state.phase {
        case .checking:
            VStack(spacing: 10) {
                ProgressView()
                    .controlSize(.regular)
                Text("Checking environment and Docker status...")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(AltrTheme.descriptionText)
            }
            .frame(maxWidth: .infinity)

        // State 1: Docker stopped; Node not installed
        case .dockerStopped:
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(AltrTheme.errorRed)
                    Text("Docker Desktop is Stopped")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(AltrTheme.errorRed)
                }

                Text("The Docker background service is not running. Start Docker Desktop to continue.")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(AltrTheme.descriptionText)
                    .multilineTextAlignment(.center)

                HStack(spacing: 10) {
                    Button("Start Docker Desktop") {
                        state.startDockerDesktop()
                    }
                    .buttonStyle(AltrPrimaryButtonStyle())

                    Button("Retry Check") {
                        Task { await state.refreshStatus() }
                    }
                    .buttonStyle(AltrSecondaryButtonStyle())
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)

        // State 2: Docker paused or suspended; Node not installed
        case .dockerPaused:
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "pause.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(AltrTheme.warningOrange)
                    Text("Docker Desktop is Paused")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(AltrTheme.warningOrange)
                }

                Text("Docker Desktop is currently paused or suspended. Resume Docker Desktop to continue.")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(AltrTheme.descriptionText)
                    .multilineTextAlignment(.center)

                HStack(spacing: 10) {
                    Button("Resume Docker Desktop") {
                        state.resumeDockerDesktop()
                    }
                    .buttonStyle(AltrPrimaryButtonStyle())

                    Button("Open Docker Desktop") {
                        state.openDockerDesktop()
                    }
                    .buttonStyle(AltrSecondaryButtonStyle())

                    Button("Retry Check") {
                        Task { await state.refreshStatus() }
                    }
                    .buttonStyle(AltrSecondaryButtonStyle())
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)

        case .dockerNotInstalled:
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(AltrTheme.errorRed)
                    Text("Docker Desktop is Required")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(AltrTheme.errorRed)
                }

                Text("Altr Stream requires Docker Desktop for macOS to manage its containerized node.")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(AltrTheme.descriptionText)
                    .multilineTextAlignment(.center)

                HStack(spacing: 10) {
                    Button("Download Docker Desktop") {
                        state.downloadDockerDesktop()
                    }
                    .buttonStyle(AltrPrimaryButtonStyle())

                    Button("Retry Check") {
                        Task { await state.refreshStatus() }
                    }
                    .buttonStyle(AltrSecondaryButtonStyle())
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)

        case .startingDocker(let elapsed):
            VStack(spacing: 10) {
                ProgressView()
                    .controlSize(.regular)

                Text(state.dockerStateText == "Resuming..." ? "Resuming Docker Desktop..." : "Starting Docker Desktop...")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)

                Text(state.dockerStateText == "Resuming..." ?
                    "Please wait while Docker Desktop resumes (\(elapsed)s elapsed)." :
                    "Please wait while the Docker background service starts (\(elapsed)s elapsed).")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(AltrTheme.descriptionText)

                Button("Cancel") {
                    state.cancelOngoingOperation()
                }
                .buttonStyle(AltrSecondaryButtonStyle())
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)

        // State 3, 4, 5: Docker ready; Node not installed
        case .readyToInstall:
            installSection

        // State 6 & State 10: Installation / Version Switch in progress
        case .installing(let progress):
            VStack(spacing: 10) {
                Text("Installing Altr Stream")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)

                ProgressView(value: Double(progress.percent), total: 100.0)
                    .progressViewStyle(.linear)
                    .frame(maxWidth: 460)

                HStack {
                    Text(progress.stage)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
                    Spacer()
                    Text("\(progress.percent)%")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(AltrTheme.secondaryText)
                }
                .frame(maxWidth: 460)

                Text(progress.message)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(AltrTheme.descriptionText)
                    .frame(maxWidth: 460, alignment: .leading)
            }
            .frame(maxWidth: .infinity)

        case .repairing(let progress):
            VStack(spacing: 10) {
                Text("Repairing Altr Stream")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)

                ProgressView(value: Double(progress.percent), total: 100.0)
                    .progressViewStyle(.linear)
                    .frame(maxWidth: 460)

                HStack {
                    Text("Repairing: \(progress.stage)")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
                    Spacer()
                    Text("\(progress.percent)%")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(AltrTheme.secondaryText)
                }
                .frame(maxWidth: 460)

                Text(progress.message)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(AltrTheme.descriptionText)
                    .frame(maxWidth: 460, alignment: .leading)
            }
            .frame(maxWidth: .infinity)

        // State 7, 8, 11, 12: Docker ready; Node installed and running
        case .running(let status):
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 22))
                        .foregroundColor(AltrTheme.successGreen)
                    Text("Altr Stream is Running")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(AltrTheme.successGreen)
                }

                Text("Web Interface available at: \(status.webURL)")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(AltrTheme.descriptionText)

                HStack(spacing: 10) {
                    Button("Open Altr Stream") {
                        state.openWebUI()
                    }
                    .buttonStyle(AltrPrimaryButtonStyle())
                    .actionButton(minWidth: 140)
                    .disabled(state.isExecutingAction)

                    Button("Repair") {
                        state.repair()
                    }
                    .buttonStyle(AltrSecondaryButtonStyle())
                    .actionButton(minWidth: 90)
                    .disabled(state.isExecutingAction)

                    Button("Uninstall...") {
                        state.showUninstallSheet = true
                    }
                    .buttonStyle(AltrSecondaryButtonStyle())
                    .actionButton(minWidth: 110)
                    .disabled(state.isExecutingAction)
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)

        case .stopped:
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(AltrTheme.secondaryText)
                    Text("Altr Stream Node is Stopped")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(AltrTheme.secondaryText)
                }

                Text("The node is installed but currently not running.")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(AltrTheme.descriptionText)

                HStack(spacing: 10) {
                    Button("Start Altr Stream") {
                        state.startContainer()
                    }
                    .buttonStyle(AltrPrimaryButtonStyle())
                    .actionButton(minWidth: 140)
                    .disabled(state.isExecutingAction)

                    Button("Repair") {
                        state.repair()
                    }
                    .buttonStyle(AltrSecondaryButtonStyle())
                    .actionButton(minWidth: 90)
                    .disabled(state.isExecutingAction)

                    Button("Uninstall...") {
                        state.showUninstallSheet = true
                    }
                    .buttonStyle(AltrSecondaryButtonStyle())
                    .actionButton(minWidth: 110)
                    .disabled(state.isExecutingAction)
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)

        case .paused:
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "pause.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(AltrTheme.warningOrange)
                    Text("Altr Stream Node is Paused")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(AltrTheme.warningOrange)
                }

                Text("The container is currently paused in Docker Desktop.")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(AltrTheme.descriptionText)

                HStack(spacing: 10) {
                    Button("Resume Node") {
                        state.resumeContainer()
                    }
                    .buttonStyle(AltrPrimaryButtonStyle())
                    .actionButton(minWidth: 140)

                    Button("Repair") {
                        state.repair()
                    }
                    .buttonStyle(AltrSecondaryButtonStyle())
                    .actionButton(minWidth: 90)

                    Button("Uninstall...") {
                        state.showUninstallSheet = true
                    }
                    .buttonStyle(AltrSecondaryButtonStyle())
                    .actionButton(minWidth: 110)
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)

        case .conflictDetected(let conflict):
            conflictSection(conflict)

        case .fileSharingRequired(let message, let path):
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 22))
                        .foregroundColor(AltrTheme.warningOrange)
                    Text("File Sharing Permission Required")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(AltrTheme.warningOrange)
                }

                Text(message)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(AltrTheme.descriptionText)
                    .multilineTextAlignment(.center)

                if !path.isEmpty {
                    Text(path)
                        .font(.system(size: 12, weight: .regular, design: .monospaced))
                        .padding(6)
                        .background(AltrTheme.panelBackground)
                        .cornerRadius(6)
                }

                HStack(spacing: 10) {
                    Button("Open Docker Settings") {
                        state.openDockerSettings()
                    }
                    .buttonStyle(AltrPrimaryButtonStyle())

                    Button("Retry") {
                        state.install()
                    }
                    .buttonStyle(AltrSecondaryButtonStyle())
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)

        case .failed(let message, _):
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "xmark.octagon.fill")
                        .font(.system(size: 22))
                        .foregroundColor(AltrTheme.errorRed)
                    Text("Operation Failed")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(AltrTheme.errorRed)
                }

                Text(message)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(AltrTheme.descriptionText)
                    .multilineTextAlignment(.center)

                HStack(spacing: 10) {
                    Button("Retry") {
                        Task { await state.refreshStatus() }
                    }
                    .buttonStyle(AltrPrimaryButtonStyle())

                    Button("Technical Details") {
                        state.showTechnicalDetails = true
                    }
                    .buttonStyle(AltrSecondaryButtonStyle())
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Node Installation Section (States 3, 4, 5)

    private var installSection: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundColor(AltrTheme.errorRed)
                Text("Altr Stream not Installed")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(AltrTheme.errorRed)
            }

            Text("Docker is running and ready. Please select a version and install Altr Stream to continue.")
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(AltrTheme.descriptionText)
                .multilineTextAlignment(.center)

            HStack(spacing: 10) {
                Button("Install Altr Stream") {
                    state.install()
                }
                .buttonStyle(AltrPrimaryButtonStyle())
                .disabled(state.selectedVersion == nil && (!state.isCustomVersionSelected || state.selectedCustomImage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))

                Button("Retry Check") {
                    Task { await state.refreshStatus() }
                }
                .buttonStyle(AltrSecondaryButtonStyle())
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Node Version Management Row (Row 3 of Dashboard Card)

    private var versionDropdownButtonLabel: String {
        if state.isCustomVersionSelected {
            let tag = state.selectedCustomImage.trimmingCharacters(in: .whitespacesAndNewlines)
            return tag.isEmpty ? "Custom image/tag..." : tag
        }
        if let sel = state.selectedVersion, !sel.isEmpty {
            if let rel = state.discoveredReleases.first(where: { $0.version == sel }), rel.isRecommended {
                return "v\(sel) (Recommended)"
            }
            return "v\(sel)"
        }
        return "Select Version"
    }

    private var versionSwitcherCard: some View {
        HStack(alignment: .center) {
            HStack(spacing: 10) {
                Image(systemName: "cylinder.split.1x2")
                    .font(.system(size: 15))
                    .foregroundColor(AltrTheme.secondaryText)
                    .frame(width: 18, height: 18)

                Text("Altr Stream Node Version")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
            }

            Spacer()

            if let cur = state.activeNodeVersion, !cur.isEmpty {
                // When installed/running: show active version in green with compact Switch Version button below
                VStack(alignment: .trailing, spacing: 6) {
                    Text("v\(cur)")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(AltrTheme.successGreen)

                    Menu {
                        Section("Official Published Releases") {
                            ForEach(state.discoveredReleases) { rel in
                                Button {
                                    handleVersionSelection(version: rel.version)
                                } label: {
                                    if rel.version == state.activeNodeVersion {
                                        Text("✓ v\(rel.version) (Current)")
                                    } else if rel.isRecommended {
                                        Text("v\(rel.version) (Recommended)")
                                    } else {
                                        Text("v\(rel.version)")
                                    }
                                }
                            }
                        }

                        Section("Local & Custom Builds") {
                            Button("Custom image/tag...") {
                                showCustomVersionSheet = true
                            }
                        }
                    } label: {
                        Text("Switch Version")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(state.isExecutingAction ? 0.4 : 1.0))
                            .padding(.leading, 12)
                            .padding(.trailing, 6)
                            .frame(height: 30)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(AltrTheme.secondaryButton.opacity(state.isExecutingAction ? 0.35 : 1.0))
                            )
                    }
                    .fixedSize()
                    .disabled(state.isExecutingAction)
                }
            } else {
                // Pre-installation states (Docker stopped, paused, ready-uninstalled):
                // Closed Dropdown: width ~210px, height 30px, secondary button background #3B404C, corner radius 6px, font 12px medium
                Menu {
                    Section("Official Published Releases") {
                        ForEach(state.discoveredReleases) { rel in
                            Button {
                                state.selectedVersion = rel.version
                                state.isCustomVersionSelected = false
                            } label: {
                                if state.selectedVersion == rel.version && !state.isCustomVersionSelected {
                                    if rel.isRecommended {
                                        Text("✓ v\(rel.version) (Recommended)")
                                    } else {
                                        Text("✓ v\(rel.version)")
                                    }
                                } else {
                                    if rel.isRecommended {
                                        Text("v\(rel.version) (Recommended)")
                                    } else {
                                        Text("v\(rel.version)")
                                    }
                                }
                            }
                        }
                    }

                    Section("Local & Custom Builds") {
                        Button {
                            showCustomVersionSheet = true
                        } label: {
                            if state.isCustomVersionSelected {
                                Text("✓ Custom image/tag...")
                            } else {
                                Text("Custom image/tag...")
                            }
                        }
                    }
                } label: {
                    HStack {
                        Text(versionDropdownButtonLabel)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(state.isExecutingAction ? 0.4 : 1.0))
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.leading, 12)
                    .padding(.trailing, 6)
                    .frame(width: 210, height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(AltrTheme.secondaryButton.opacity(state.isExecutingAction ? 0.35 : 1.0))
                    )
                }
                .fixedSize()
                .disabled(state.isExecutingAction)
            }
        }
    }

    // MARK: - Conflict Resolution Section

    @ViewBuilder
    private func conflictSection(_ conflict: ConflictInfo) -> some View {
        if conflict.isPortConflict {
            if conflict.isDevContainer == true {
                let devName = conflict.containerName ?? conflict.occupiedBy ?? "altr-stream-dev"
                VStack(spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 22))
                            .foregroundColor(AltrTheme.warningOrange)
                        Text("Development Container Conflict Detected")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(AltrTheme.warningOrange)
                    }

                    Text("Port \(conflict.conflictingPort ?? 8000) is in use by development container '\(devName)'.\n\nThe Manager will not adopt, modify, or stop your development environment. Please stop your development container (e.g. 'docker compose down') or configure this instance to use a different port.")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(AltrTheme.descriptionText)
                        .multilineTextAlignment(.center)

                    HStack(spacing: 10) {
                        Button("Retry Check") {
                            Task { await state.refreshStatus() }
                        }
                        .buttonStyle(AltrPrimaryButtonStyle())

                        Button("Technical Details") {
                            state.showConflictDetails(conflict)
                        }
                        .buttonStyle(AltrSecondaryButtonStyle())
                    }
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity)
            } else {
                VStack(spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 22))
                            .foregroundColor(AltrTheme.warningOrange)
                        Text("Port Conflict Detected")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(AltrTheme.warningOrange)
                    }

                    if let occ = conflict.occupiedBy, !occ.isEmpty {
                        Text("Port \(conflict.conflictingPort ?? 8000) is already in use by service '\(occ)'.\n\nPlease stop the conflicting service and retry.")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundColor(AltrTheme.descriptionText)
                            .multilineTextAlignment(.center)
                    } else if let hint = conflict.remediationHint, !hint.isEmpty {
                        Text(hint)
                            .font(.system(size: 13, weight: .regular))
                            .foregroundColor(AltrTheme.descriptionText)
                            .multilineTextAlignment(.center)
                    } else {
                        Text("Port \(conflict.conflictingPort ?? 8000) is already in use by another application or process.\n\nPlease close the application using port \(conflict.conflictingPort ?? 8000) and retry.")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundColor(AltrTheme.descriptionText)
                            .multilineTextAlignment(.center)
                    }

                    HStack(spacing: 10) {
                        Button("Retry Check") {
                            Task { await state.refreshStatus() }
                        }
                        .buttonStyle(AltrPrimaryButtonStyle())

                        Button("Technical Details") {
                            state.showConflictDetails(conflict)
                        }
                        .buttonStyle(AltrSecondaryButtonStyle())
                    }
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity)
            }
        } else {
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(AltrTheme.warningOrange)
                    Text(
                        conflict.isAltrStream ? "Existing Altr Stream Container Found" : "Container Conflict Detected"
                    )
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(AltrTheme.warningOrange)
                }

                if conflict.isAltrStream {
                    Text("A previous Altr Stream container (Image: \(conflict.image ?? "unknown"), Status: \(conflict.status ?? "unknown")) is present on your system.")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(AltrTheme.descriptionText)
                        .multilineTextAlignment(.center)
                } else {
                    Text("Another container named 'altr-stream' (Image: \(conflict.image ?? "unknown")) already exists on your Docker host.")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(AltrTheme.descriptionText)
                        .multilineTextAlignment(.center)
                }

                Text("Replacing the container will remove the old container while preserving all persistent data volumes.")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(AltrTheme.secondaryText)
                    .multilineTextAlignment(.center)

                HStack(spacing: 10) {
                    if conflict.isCompatible && conflict.status != "running" {
                        Button(conflict.status == "paused" ? "Resume Existing Container" : "Start Existing Container") {
                            state.resolveConflictStartExisting()
                        }
                        .buttonStyle(AltrSecondaryButtonStyle())
                    }

                    Button(conflict.isAltrStream ? "Replace Container & Reinstall" : "Replace Conflicting Container") {
                        state.resolveConflictReplace()
                    }
                    .buttonStyle(AltrPrimaryButtonStyle())

                    Button("Technical Details") {
                        state.showConflictDetails(conflict)
                    }
                    .buttonStyle(AltrSecondaryButtonStyle())
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Footer

    private var footerSection: some View {
        HStack(alignment: .firstTextBaseline) {
            Button("Technical Details") {
                state.showTechnicalDetails = true
            }
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(AltrTheme.linkBlue)

            Spacer()

            Button(action: {
                state.showTechnicalDetails = true
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 12))
                    Text("Show Installation Logs")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(AltrTheme.linkBlue)
            }
            .buttonStyle(.plain)
        }
        .frame(height: 24)
    }

    // MARK: - Technical Details Sheet

    private var technicalDetailsSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Technical Details & Logs")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
                Button("Copy to Clipboard") {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(state.technicalDetails, forType: .string)
                }
                .buttonStyle(AltrSecondaryButtonStyle())
                .frame(height: 28)

                Button("Done") {
                    state.showTechnicalDetails = false
                }
                .buttonStyle(AltrPrimaryButtonStyle())
                .frame(height: 28)
                .keyboardShortcut(.defaultAction)
            }

            ScrollView {
                Text(state.technicalDetails.isEmpty ? "No diagnostics recorded." : state.technicalDetails)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(minHeight: 200, maxHeight: 320)
            .padding(10)
            .background(AltrTheme.panelBackground)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(AltrTheme.border, lineWidth: 1)
            )
        }
        .padding(16)
        .frame(minWidth: 460, idealWidth: 540, maxWidth: 640, minHeight: 300, idealHeight: 360, maxHeight: 440)
        .background(AltrTheme.windowBackground)
    }

    // MARK: - Uninstall Sheet

    private var uninstallSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "trash.fill")
                    .font(.system(size: 18))
                    .foregroundColor(AltrTheme.errorRed)
                Text("Uninstall Altr Stream")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(AltrTheme.errorRed)
            }

            Text("Select the components you wish to remove:")
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(AltrTheme.descriptionText)

            VStack(alignment: .leading, spacing: 8) {
                Text("Remove Docker & Runtime Resources")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)

                let volName = state.activeDataVolumeName ?? "altr_stream_data"
                Toggle("Remove Persistent Application Data (Docker volume \(volName))", isOn: $state.uninstallDeleteData)
                    .foregroundColor(state.uninstallDeleteData ? AltrTheme.errorRed : .white)
                    .font(.system(size: 12))

                Toggle("Move Altr Stream.app to Trash", isOn: $state.uninstallRemoveApp)
                    .foregroundColor(.white)
                    .font(.system(size: 12))
            }

            if state.uninstallDeleteData {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Type 'DELETE ALTR STREAM DATA' to confirm irreversible data deletion:")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(AltrTheme.errorRed)

                    TextField("DELETE ALTR STREAM DATA", text: $state.uninstallConfirmationInput)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11, design: .monospaced))
                }
                .padding(8)
                .background(AltrTheme.errorRed.opacity(0.1))
                .cornerRadius(6)
            }

            HStack {
                Button("Cancel") {
                    state.showUninstallSheet = false
                    state.uninstallDeleteData = false
                    state.uninstallRemoveApp = false
                    state.uninstallConfirmationInput = ""
                }
                .buttonStyle(AltrSecondaryButtonStyle())

                Spacer()

                Button("Proceed with Uninstall", role: .destructive) {
                    state.uninstall()
                }
                .buttonStyle(AltrPrimaryButtonStyle())
                .disabled(state.uninstallDeleteData && state.uninstallConfirmationInput != "DELETE ALTR STREAM DATA")
            }
        }
        .padding(20)
        .frame(minWidth: 460, minHeight: 280)
        .background(AltrTheme.windowBackground)
    }
}

// MARK: - Action Button Style Extension

public struct RunningActionButtonModifier: ViewModifier {
    let minWidth: CGFloat
    public func body(content: Content) -> some View {
        content
            .controlSize(.regular)
            .frame(minWidth: minWidth)
    }
}

extension View {
    func actionButton(minWidth: CGFloat = 130) -> some View {
        self.modifier(RunningActionButtonModifier(minWidth: minWidth))
    }
}
