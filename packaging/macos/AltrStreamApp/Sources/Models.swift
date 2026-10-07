import Foundation

// MARK: - Engine Models

public struct DockerDiagnostics: Codable, Equatable {
    public let state: String
    public let cliInstalled: Bool?
    public let desktopInstalled: Bool?
    public let engineRunning: Bool?
    public let composeAvailable: Bool?
    public let composeCommand: String?
    public let statusText: String?
    public let actionHint: String?
    public let officialInstallerURL: String?
    public let technicalError: String?
    public let failureReason: String?

    enum CodingKeys: String, CodingKey {
        case state
        case cliInstalled = "cli_installed"
        case desktopInstalled = "desktop_installed"
        case engineRunning = "engine_running"
        case composeAvailable = "compose_available"
        case composeCommand = "compose_command"
        case statusText = "status_text"
        case actionHint = "action_hint"
        case officialInstallerURL = "official_installer_url"
        case technicalError = "technical_error"
        case failureReason = "failure_reason"
    }

    public var isReady: Bool {
        return state == "ready"
    }

    public var isPaused: Bool {
        return state == "paused"
    }

    public var isStopped: Bool {
        return state == "stopped"
    }

    public var isStarting: Bool {
        return state == "starting"
    }

    public var isNotInstalled: Bool {
        return state == "not_installed"
    }
}

public struct EnvironmentInfo: Codable, Equatable {
    public let os: String
    public let arch: String
    public let userHome: String
    public let defaultDir: String
    public let configFile: String
    public let savedDir: String?
    public let effectiveDir: String
    public let isOneDrive: Bool

    enum CodingKeys: String, CodingKey {
        case os, arch
        case userHome = "user_home"
        case defaultDir = "default_dir"
        case configFile = "config_file"
        case savedDir = "saved_dir"
        case effectiveDir = "effective_dir"
        case isOneDrive = "is_onedrive"
    }
}

public struct ConflictInfo: Codable, Equatable {
    public let exists: Bool
    public let conflictType: String?
    public let containerID: String?
    public let containerName: String?
    public let status: String?
    public let image: String?
    public let created: String?
    public let isAltrStream: Bool
    public let isCompatible: Bool
    public let isInstallerOwned: Bool?
    public let isDevContainer: Bool?
    public let portMapping: String?
    public let healthStatus: String?
    public let conflictingPort: Int?
    public let occupiedBy: String?
    public let remediationHint: String?
    public let details: String?
    public let rawInspect: String?

    enum CodingKeys: String, CodingKey {
        case exists
        case conflictType = "conflict_type"
        case containerID = "container_id"
        case containerName = "container_name"
        case status, image, created
        case isAltrStream = "is_altr_stream"
        case isCompatible = "is_compatible"
        case isInstallerOwned = "is_installer_owned"
        case isDevContainer = "is_dev_container"
        case portMapping = "port_mapping"
        case healthStatus = "health_status"
        case conflictingPort = "conflicting_port"
        case occupiedBy = "occupied_by"
        case remediationHint = "remediation_hint"
        case details
        case rawInspect = "raw_inspect"
    }

    public var isPortConflict: Bool {
        return conflictType == "port_docker" || conflictType == "port_process" || (conflictingPort != nil && conflictingPort! > 0)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        exists = try container.decode(Bool.self, forKey: .exists)
        conflictType = try container.decodeIfPresent(String.self, forKey: .conflictType)
        containerID = try container.decodeIfPresent(String.self, forKey: .containerID)
        containerName = try container.decodeIfPresent(String.self, forKey: .containerName)
        status = try container.decodeIfPresent(String.self, forKey: .status)
        image = try container.decodeIfPresent(String.self, forKey: .image)
        created = try container.decodeIfPresent(String.self, forKey: .created)
        isAltrStream = try container.decodeIfPresent(Bool.self, forKey: .isAltrStream) ?? false
        isCompatible = try container.decodeIfPresent(Bool.self, forKey: .isCompatible) ?? false
        isInstallerOwned = try container.decodeIfPresent(Bool.self, forKey: .isInstallerOwned)
        isDevContainer = try container.decodeIfPresent(Bool.self, forKey: .isDevContainer)
        portMapping = try container.decodeIfPresent(String.self, forKey: .portMapping)
        healthStatus = try container.decodeIfPresent(String.self, forKey: .healthStatus)
        conflictingPort = try container.decodeIfPresent(Int.self, forKey: .conflictingPort)
        occupiedBy = try container.decodeIfPresent(String.self, forKey: .occupiedBy)
        remediationHint = try container.decodeIfPresent(String.self, forKey: .remediationHint)
        details = try container.decodeIfPresent(String.self, forKey: .details)
        rawInspect = try container.decodeIfPresent(String.self, forKey: .rawInspect)
    }

    public var lifecycleState: ContainerLifecycleState {
        guard let st = status else { return .unknown }
        return ContainerLifecycleState(rawValue: st) ?? .unknown
    }
}

public struct InstallProgress: Codable, Equatable {
    public let stage: String
    public let stageIndex: Int
    public let totalStages: Int
    public let percent: Int
    public let message: String

    enum CodingKeys: String, CodingKey {
        case stage
        case stageIndex = "stage_index"
        case totalStages = "total_stages"
        case percent, message
    }
}

public struct NodeStatus: Codable, Equatable {
    public let installDir: String
    public let targetVersion: String
    public let containerState: String
    public let port: Int
    public let webURL: String
    public let dockerDiag: DockerDiagnostics
    public let healthy: Bool
    public let healthResponse: String?
    public let technicalIssues: [String]?

    enum CodingKeys: String, CodingKey {
        case installDir = "install_dir"
        case targetVersion = "target_version"
        case containerState = "container_state"
        case port
        case webURL = "web_url"
        case dockerDiag = "docker_diag"
        case healthy
        case healthResponse = "health_response"
        case technicalIssues = "technical_issues"
    }

    public var lifecycleState: ContainerLifecycleState {
        return ContainerLifecycleState(rawValue: containerState) ?? .unknown
    }
}

public enum ContainerLifecycleState: String, Codable, Equatable {
    case running = "running"
    case paused = "paused"
    case exited = "exited"
    case dead = "dead"
    case restarting = "restarting"
    case created = "created"
    case notInstalled = "not_installed"
    case unknown = "unknown"

    public var displayText: String {
        switch self {
        case .running:
            return "Running"
        case .paused:
            return "Paused"
        case .exited:
            return "Stopped"
        case .dead:
            return "Stopped / Failed"
        case .restarting:
            return "Restarting"
        case .created:
            return "Not Running / Stopped"
        case .notInstalled:
            return "Not Installed"
        case .unknown:
            return "Unknown"
        }
    }

    public var isRunning: Bool {
        return self == .running
    }

    public var isPaused: Bool {
        return self == .paused
    }

    public var isStopped: Bool {
        return self == .exited || self == .dead || self == .created
    }
}

