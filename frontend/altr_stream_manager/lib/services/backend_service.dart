import '../models/diagnostic_report.dart';
import '../models/install_progress.dart';
import '../models/node_status.dart';

/// Abstract contract connecting Flutter UI with the node management backend.
///
/// Implemented by:
/// - [EngineBackendService] for production execution using the native Go engine.
/// - [MockBackendService] for standalone UI preview and mock-state testing.
abstract class BackendService {
  /// Fetches the latest live operational status of Docker and the Altr Stream node.
  Future<NodeStatus> getStatus();

  /// Refreshes the environment check and returns updated [NodeStatus].
  Future<NodeStatus> refreshStatus();

  /// Retrieves list of official published releases and local custom images.
  Future<List<NodeVersion>> getAvailableVersions();

  /// Gets the currently installed version tag, or null if not installed.
  Future<String?> getInstalledVersion();

  /// Starts the Docker Desktop application / background service.
  Future<bool> startDockerDesktop();

  /// Resumes Docker Desktop when in a paused state.
  Future<bool> resumeDockerDesktop();

  /// Starts an existing stopped Altr Stream container.
  Future<bool> startNode();

  /// Stops a running Altr Stream container.
  Future<bool> stopNode();

  /// Pauses a running Altr Stream container.
  Future<bool> pauseNode();

  /// Resumes a paused Altr Stream container.
  Future<bool> resumeNode();

  /// Executes fresh installation of the node with the specified version.
  Stream<InstallProgress> installNode(String version, {String? customImage});

  /// Upgrades or switches the running node to the target version.
  Stream<InstallProgress> updateNodeVersion(String version);

  /// Recreates container configuration and repairs runtime bindings.
  Stream<InstallProgress> repairNode();

  /// Stops and removes container, optionally destroying persistent volume data.
  Future<bool> uninstallNode({bool deleteData = false});

  /// Updates the target persistent data directory path.
  Future<String> changeInstallationPath(String newPath);

  /// Launches default web browser to the node web interface (e.g. http://localhost:8000).
  Future<void> openWebInterface();

  /// Reveals installation directory in Finder (macOS) or Explorer (Windows).
  Future<void> openInstallationDirectory();

  /// Retrieves recent installation / runtime diagnostic log contents.
  /// When [raw] is true, returns raw container logs without collapsing health checks.
  Future<String> getInstallationLogs({bool forceRefresh = false, bool raw = false});

  /// Clears in-memory session logs and writable installation logs without deleting container data.
  Future<void> clearLogs();

  /// Records a structured, timestamped log event into the session diagnostics buffer.
  void logEvent(String category, String message, {String level = 'INFO'});

  /// Executes bounded diagnostic checks across Docker, daemon, container, and configuration.
  Future<DiagnosticReport> runDiagnostics();
}
