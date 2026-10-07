import Foundation

public enum EngineError: LocalizedError {
    case engineNotFound
    case commandFailed(command: String, exitCode: Int32, stderr: String)
    case fileSharingRequired(message: String, path: String)
    case decodingFailed(Error, rawOutput: String)

    public var errorDescription: String? {
        switch self {
        case .engineNotFound:
            return "Installer engine binary could not be found."
        case .commandFailed(let cmd, let code, let err):
            return "Command '\(cmd)' failed with exit code \(code): \(err)"
        case .fileSharingRequired(let msg, _):
            return msg
        case .decodingFailed(let err, _):
            return "Failed to decode engine response: \(err.localizedDescription)"
        }
    }
}

public final class EngineBridge: @unchecked Sendable {
    public static let shared = EngineBridge()

    private let jsonDecoder: JSONDecoder = {
        let d = JSONDecoder()
        return d
    }()

    public init() {}

    /// Resolve the path to the bundled or development altr-installer-engine binary.
    public func resolveEngineBinary() -> String? {
        // 1. Explicit environment override
        if let envPath = ProcessInfo.processInfo.environment["ALTR_INSTALLER_ENGINE"],
           FileManager.default.isExecutableFile(atPath: envPath) {
            return envPath
        }

        // 2. Bundled inside application Resources
        if let resPath = Bundle.main.path(forResource: "altr-installer-engine", ofType: nil),
           FileManager.default.isExecutableFile(atPath: resPath) {
            return resPath
        }

        // 3. Application bundle structure relative to bundleURL
        let directBundlePath = Bundle.main.bundleURL
            .appendingPathComponent("Contents")
            .appendingPathComponent("Resources")
            .appendingPathComponent("altr-installer-engine").path
        if FileManager.default.isExecutableFile(atPath: directBundlePath) {
            return directBundlePath
        }

        // 4. Executable parent directory fallback (e.g. running from CLI or test harness)
        if let execURL = Bundle.main.executableURL {
            let adjacentPath = execURL.deletingLastPathComponent().appendingPathComponent("altr-installer-engine").path
            if FileManager.default.isExecutableFile(atPath: adjacentPath) {
                return adjacentPath
            }
            let resSibling = execURL.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/altr-installer-engine").path
            if FileManager.default.isExecutableFile(atPath: resSibling) {
                return resSibling
            }
        }

        // 5. Development well-known paths
        let currentDir = FileManager.default.currentDirectoryPath
        let candidates = [
            "\(currentDir)/packaging/engine/altr-installer-engine",
            "\(currentDir)/dist/Altr Stream.app/Contents/Resources/altr-installer-engine",
            "\(currentDir)/dist/altr-installer-engine",
            "/tmp/altr-installer-engine"
        ]
        for c in candidates {
            if FileManager.default.isExecutableFile(atPath: c) {
                return c
            }
        }

        return nil
    }

    /// Asynchronously runs an engine command capturing full stdout and stderr.
    public func runCommand(args: [String]) async throws -> (stdout: String, stderr: String, exitCode: Int32) {
        guard let binary = resolveEngineBinary() else {
            throw EngineError.engineNotFound
        }

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: binary)
                process.arguments = args

                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe

                do {
                    try process.run()
                    let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()

                    let stdoutStr = String(data: stdoutData, encoding: .utf8) ?? ""
                    let stderrStr = String(data: stderrData, encoding: .utf8) ?? ""

                    continuation.resume(returning: (stdoutStr, stderrStr, process.terminationStatus))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Asynchronously runs an engine command, streaming lines from stdout as they arrive.
    public func streamCommand(
        args: [String],
        onLine: @escaping (String) -> Void
    ) async throws -> (stderr: String, exitCode: Int32) {
        guard let binary = resolveEngineBinary() else {
            throw EngineError.engineNotFound
        }

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: binary)
                process.arguments = args

                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe

                var buffer = Data()
                stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    if data.isEmpty {
                        return
                    }
                    buffer.append(data)
                    while let newlineRange = buffer.range(of: Data([0x0A])) {
                        let lineData = buffer.subdata(in: 0..<newlineRange.lowerBound)
                        buffer.removeSubrange(0..<newlineRange.upperBound)
                        if let line = String(data: lineData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !line.isEmpty {
                            onLine(line)
                        }
                    }
                }

                do {
                    try process.run()
                    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    stdoutPipe.fileHandleForReading.readabilityHandler = nil

                    // Flush any remaining buffer
                    if !buffer.isEmpty, let line = String(data: buffer, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !line.isEmpty {
                        onLine(line)
                    }

                    let stderrStr = String(data: stderrData, encoding: .utf8) ?? ""
                    continuation.resume(returning: (stderrStr, process.terminationStatus))
                } catch {
                    stdoutPipe.fileHandleForReading.readabilityHandler = nil
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Subcommand Wrappers

    public func detectEnvironment() async throws -> EnvironmentInfo {
        let (stdout, stderr, code) = try await runCommand(args: ["detect-env"])
        guard code == 0, let data = stdout.data(using: .utf8) else {
            throw EngineError.commandFailed(command: "detect-env", exitCode: code, stderr: stderr)
        }
        do {
            return try jsonDecoder.decode(EnvironmentInfo.self, from: data)
        } catch {
            throw EngineError.decodingFailed(error, rawOutput: stdout)
        }
    }

    public func checkDocker() async throws -> DockerDiagnostics {
        let (stdout, stderr, code) = try await runCommand(args: ["check-docker"])
        guard code == 0, let data = stdout.data(using: .utf8) else {
            throw EngineError.commandFailed(command: "check-docker", exitCode: code, stderr: stderr)
        }
        do {
            return try jsonDecoder.decode(DockerDiagnostics.self, from: data)
        } catch {
            throw EngineError.decodingFailed(error, rawOutput: stdout)
        }
    }

    public func launchDockerDesktop() async throws {
        let (_, stderr, code) = try await runCommand(args: ["launch-docker"])
        if code != 0 {
            throw EngineError.commandFailed(command: "launch-docker", exitCode: code, stderr: stderr)
        }
    }

    public func unpauseDockerDesktop() async throws {
        let (_, stderr, code) = try await runCommand(args: ["unpause-docker-desktop"])
        if code != 0 {
            throw EngineError.commandFailed(command: "unpause-docker-desktop", exitCode: code, stderr: stderr)
        }
    }

    public func openDockerSettings() async throws {
        let (_, stderr, code) = try await runCommand(args: ["open-docker-settings"])
        if code != 0 {
            throw EngineError.commandFailed(command: "open-docker-settings", exitCode: code, stderr: stderr)
        }
    }

    public func waitForDocker(timeout: Int = 60) async throws {
        let (_, stderr, code) = try await runCommand(args: ["wait-docker", "--timeout", String(timeout), "--json"])
        if code != 0 {
            throw EngineError.commandFailed(command: "wait-docker", exitCode: code, stderr: stderr)
        }
    }

    public func checkConflict() async throws -> ConflictInfo {
        let (stdout, stderr, code) = try await runCommand(args: ["conflict"])
        guard code == 0, let data = stdout.data(using: .utf8) else {
            throw EngineError.commandFailed(command: "conflict", exitCode: code, stderr: stderr)
        }
        do {
            return try jsonDecoder.decode(ConflictInfo.self, from: data)
        } catch {
            throw EngineError.decodingFailed(error, rawOutput: stdout)
        }
    }

    public func removeContainer() async throws {
        let (_, stderr, code) = try await runCommand(args: ["remove-container"])
        if code != 0 {
            throw EngineError.commandFailed(command: "remove-container", exitCode: code, stderr: stderr)
        }
    }

    public func startContainer() async throws {
        let (_, stderr, code) = try await runCommand(args: ["start-container"])
        if code != 0 {
            throw EngineError.commandFailed(command: "start-container", exitCode: code, stderr: stderr)
        }
    }

    public func unpauseContainer() async throws {
        let (_, stderr, code) = try await runCommand(args: ["unpause-container"])
        if code != 0 {
            throw EngineError.commandFailed(command: "unpause-container", exitCode: code, stderr: stderr)
        }
    }

    public func install(
        targetDir: String? = nil,
        replaceExisting: Bool = false,
        onProgress: @escaping (InstallProgress) -> Void
    ) async throws {
        var args = ["install", "--json"]
        if let dir = targetDir, !dir.isEmpty {
            args.append(contentsOf: ["--target-dir", dir])
        }
        if replaceExisting {
            args.append("--replace-existing")
        }

        let (stderr, code) = try await streamCommand(args: args) { line in
            if let data = line.data(using: .utf8),
               let progress = try? self.jsonDecoder.decode(InstallProgress.self, from: data) {
                onProgress(progress)
            }
        }

        if code == 2 || stderr.contains("FILE_SHARING_REQUIRED") {
            let path = self.extractPathFromError(stderr)
            throw EngineError.fileSharingRequired(
                message: "Docker Desktop needs permission to access Altr Stream's data folder.",
                path: path
            )
        }

        if code != 0 {
            throw EngineError.commandFailed(command: "install", exitCode: code, stderr: stderr)
        }
    }

    public func repair(
        targetDir: String? = nil,
        onProgress: @escaping (InstallProgress) -> Void
    ) async throws {
        var args = ["repair", "--json"]
        if let dir = targetDir, !dir.isEmpty {
            args.append(contentsOf: ["--target-dir", dir])
        }

        let (stderr, code) = try await streamCommand(args: args) { line in
            if let data = line.data(using: .utf8),
               let progress = try? self.jsonDecoder.decode(InstallProgress.self, from: data) {
                onProgress(progress)
            }
        }

        if code != 0 {
            throw EngineError.commandFailed(command: "repair", exitCode: code, stderr: stderr)
        }
    }

    public func uninstall(targetDir: String? = nil, deleteData: Bool = false) async throws {
        var args = ["uninstall"]
        if let dir = targetDir, !dir.isEmpty {
            args.append(contentsOf: ["--target-dir", dir])
        }
        if deleteData {
            args.append("--delete-data")
        }

        let (_, stderr, code) = try await runCommand(args: args)
        if code != 0 {
            throw EngineError.commandFailed(command: "uninstall", exitCode: code, stderr: stderr)
        }
    }

    public func getStatus(targetDir: String? = nil) async throws -> NodeStatus {
        var args = ["status"]
        if let dir = targetDir, !dir.isEmpty {
            args.append(contentsOf: ["--target-dir", dir])
        }

        let (stdout, stderr, code) = try await runCommand(args: args)
        guard code == 0, let data = stdout.data(using: .utf8) else {
            throw EngineError.commandFailed(command: "status", exitCode: code, stderr: stderr)
        }
        do {
            return try jsonDecoder.decode(NodeStatus.self, from: data)
        } catch {
            throw EngineError.decodingFailed(error, rawOutput: stdout)
        }
    }

    public func launchBrowser(url: String? = nil) async throws {
        var args = ["launch-browser"]
        if let targetURL = url, !targetURL.isEmpty {
            args.append(contentsOf: ["--url", targetURL])
        }

        let (_, stderr, code) = try await runCommand(args: args)
        if code != 0 {
            throw EngineError.commandFailed(command: "launch-browser", exitCode: code, stderr: stderr)
        }
    }

    private func extractPathFromError(_ errorStr: String) -> String {
        // e.g. the path "/Users/.../.altr-stream/data/updates" is not shared
        let pattern = "\"([^\"]+)\""
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: errorStr, range: NSRange(errorStr.startIndex..., in: errorStr)),
           let range = Range(match.range(at: 1), in: errorStr) {
            return String(errorStr[range])
        }
        return ""
    }
}
