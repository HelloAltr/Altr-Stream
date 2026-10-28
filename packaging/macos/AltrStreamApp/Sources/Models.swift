import Foundation

// MARK: - Engine Models

public struct DockerDiagnostics: Codable, Equatable, Sendable {
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

public struct EnvironmentInfo: Codable, Equatable, Sendable {
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

public struct ConflictInfo: Codable, Equatable, Sendable {
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

public struct InstallProgress: Codable, Equatable, Sendable {
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

public struct NodeStatus: Codable, Equatable, Sendable {
    public let installDir: String
    public let targetVersion: String
    public let activeImage: String?
    public let activeVersion: String?
    public let containerState: String
    public let port: Int
    public let webURL: String
    public let dockerDiag: DockerDiagnostics
    public let healthy: Bool
    public let healthResponse: String?
    public let dataVolumeName: String?
    public let technicalIssues: [String]?

    enum CodingKeys: String, CodingKey {
        case installDir = "install_dir"
        case targetVersion = "target_version"
        case activeImage = "active_image"
        case activeVersion = "active_version"
        case containerState = "container_state"
        case port
        case webURL = "web_url"
        case dockerDiag = "docker_diag"
        case healthy
        case healthResponse = "health_response"
        case dataVolumeName = "data_volume_name"
        case technicalIssues = "technical_issues"
    }

    public var lifecycleState: ContainerLifecycleState {
        return ContainerLifecycleState(rawValue: containerState) ?? .unknown
    }
}

public enum ContainerLifecycleState: String, Codable, Equatable, Sendable {
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

// MARK: - Developer Options Models

public struct ImageValidationResult: Codable, Equatable, Sendable {
    public let valid: Bool
    public let available: Bool
    public let image: String
    public let status: String // "available", "unavailable", "invalid_format", "network_error", "auth_error"
    public let message: String
    public let details: String?

    public init(valid: Bool, available: Bool, image: String, status: String, message: String, details: String? = nil) {
        self.valid = valid
        self.available = available
        self.image = image
        self.status = status
        self.message = message
        self.details = details
    }

    public var isAvailable: Bool {
        return valid && available && status == "available"
    }

    public var isUnavailable: Bool {
        return status == "unavailable"
    }

    public var isInvalidFormat: Bool {
        return status == "invalid_format"
    }

    public var isNetworkOrAuthError: Bool {
        return status == "network_error" || status == "auth_error"
    }
}

public struct PublishedReleaseInfo: Codable, Equatable, Sendable {
    public let version: String
    public let tagName: String
    public let imageReference: String
    public let isPrerelease: Bool
    public let publishedAt: String?

    public init(version: String, tagName: String, imageReference: String, isPrerelease: Bool = false, publishedAt: String? = nil) {
        self.version = version
        self.tagName = tagName
        self.imageReference = imageReference
        self.isPrerelease = isPrerelease
        self.publishedAt = publishedAt
    }
}

public struct DiscoveredRelease: Identifiable, Equatable, Hashable, Sendable {
    public var id: String { version }
    public let version: String
    public let tagName: String
    public let isRecommended: Bool
    public let isPrerelease: Bool
    public let imageRef: String
    public var isImageVerified: Bool

    public init(version: String, tagName: String, isRecommended: Bool, isPrerelease: Bool, imageRef: String, isImageVerified: Bool = true) {
        self.version = version
        self.tagName = tagName
        self.isRecommended = isRecommended
        self.isPrerelease = isPrerelease
        self.imageRef = imageRef
        self.isImageVerified = isImageVerified
    }
}

public enum ReleaseDiscoveryState: Equatable, Sendable {
    case loading
    case success([DiscoveredRelease], isStale: Bool = false)
    case empty
    case error(String)
}

public struct KnownReleaseImage: Identifiable, Hashable, Sendable {
    public let id: String
    public let displayName: String
    public let imageReference: String
    public let isPublished: Bool

    public init(id: String, displayName: String, imageReference: String, isPublished: Bool = true) {
        self.id = id
        self.displayName = displayName
        self.imageReference = imageReference
        self.isPublished = isPublished
    }
}

public enum DeveloperImageHelper {
    public static let canonicalRepo = "ghcr.io/helloaltr/altr-stream"
    public static let recommendedNodeVersion = "1.0.0-beta"
    public static let recommendedNodeImage = "\(canonicalRepo):\(recommendedNodeVersion)"
    public static let supportedKnownTags = ["1.0.0-beta", "0.13.7-alpha"]

    public static func isLocalDevImage(tagOrRef: String) -> Bool {
        let lower = tagOrRef.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return lower.contains(":dev") ||
               lower.contains("-dev") ||
               lower.contains("localhost") ||
               lower.hasPrefix("altr-stream-test") ||
               lower.contains("local")
    }

    public static func validateCustomImageSyntax(_ input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "Custom image reference cannot be empty."
        }
        if trimmed.contains(" ") || trimmed.contains("\t") {
            return "Image reference cannot contain whitespace."
        }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-/:")
        if trimmed.rangeOfCharacter(from: allowed.inverted) != nil {
            return "Invalid image format. Allowed characters: letters, numbers, '.', '_', '-', '/', and ':'. No spaces."
        }
        return nil
    }

    public static func validateCustomImageReference(_ input: String) -> String? {
        return validateCustomImageSyntax(input)
    }

    public static func formatImageReference(tagOrRef: String) -> String {
        let trimmed = tagOrRef.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains("/") || trimmed.contains(":") {
            return trimmed
        }
        return "\(canonicalRepo):\(trimmed)"
    }

    public static func isVersion(_ v1: String, newerThan v2: String) -> Bool {
        let clean1 = v1.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("v") ?
            String(v1.trimmingCharacters(in: .whitespacesAndNewlines).dropFirst()) :
            v1.trimmingCharacters(in: .whitespacesAndNewlines)
        let clean2 = v2.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("v") ?
            String(v2.trimmingCharacters(in: .whitespacesAndNewlines).dropFirst()) :
            v2.trimmingCharacters(in: .whitespacesAndNewlines)

        if clean1 == clean2 { return false }

        func parseSemver(_ ver: String) -> (major: Int, minor: Int, patch: Int, prerelease: String) {
            let parts = ver.split(separator: "-", maxSplits: 1)
            let core = String(parts[0])
            let pre = parts.count > 1 ? String(parts[1]) : ""

            let nums = core.split(separator: ".").compactMap { Int($0) }
            let major = nums.count > 0 ? nums[0] : 0
            let minor = nums.count > 1 ? nums[1] : 0
            let patch = nums.count > 2 ? nums[2] : 0
            return (major, minor, patch, pre)
        }

        let p1 = parseSemver(clean1)
        let p2 = parseSemver(clean2)

        if p1.major != p2.major { return p1.major > p2.major }
        if p1.minor != p2.minor { return p1.minor > p2.minor }
        if p1.patch != p2.patch { return p1.patch > p2.patch }

        if p1.prerelease.isEmpty && !p2.prerelease.isEmpty { return true }
        if !p1.prerelease.isEmpty && p2.prerelease.isEmpty { return false }

        return p1.prerelease > p2.prerelease
    }

    public static func extractCleanDisplayTag(imageRef: String) -> String {
        let trimmed = imageRef.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "" }
        let prefix = "\(canonicalRepo):"
        if trimmed.hasPrefix(prefix) {
            return String(trimmed.dropFirst(prefix.count))
        }
        if let lastColon = trimmed.lastIndex(of: ":") {
            let tag = String(trimmed[trimmed.index(after: lastColon)...])
            if !tag.contains("/") {
                return tag
            }
        }
        return trimmed
    }
}




