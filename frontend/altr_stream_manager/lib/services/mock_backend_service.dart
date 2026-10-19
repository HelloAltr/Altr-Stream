import 'dart:async';
import 'package:flutter/foundation.dart';

import '../models/diagnostic_report.dart';
import '../models/install_progress.dart';
import '../models/node_status.dart';
import 'backend_service.dart';

/// Predefined representative UI scenarios for previewing the desktop interface without Docker.
enum MockScenario {
  /// Node is fully installed, Docker is running, web interface is healthy.
  running,

  /// Node is running an older version (v0.13.7-alpha) with an update available (v1.0.0-beta).
  updateAvailable,

  /// Docker Desktop is not installed on the host.
  dockerNotInstalled,

  /// Docker Desktop application service is stopped.
  dockerStopped,

  /// Docker Desktop is currently launching or starting up.
  dockerStarting,

  /// Docker Desktop is paused/suspended by the OS or user.
  dockerPaused,

  /// Docker is ready, but Altr Stream has not yet been installed.
  nodeNotInstalled,

  /// Docker is ready, but Altr Stream container is stopped.
  nodeStopped,

  /// Docker is ready, but Altr Stream container is paused.
  nodePaused,

  /// An active install, update, or repair operation is in progress.
  installing,

  /// Environmental error or container conflict detected.
  error,
}

/// Standalone mock backend service.
///
/// Allows full UI preview and testing on macOS and Windows without requiring
/// a running Docker daemon, local containers, or network access.
class MockBackendService implements BackendService {
  MockScenario currentScenario;

  String _currentInstallDir = '/Users/mockuser/.altr-stream';
  String _activeVersion = '1.0.0-beta';
  final String _recommendedVersion = '1.0.0-beta';

  MockBackendService({this.currentScenario = MockScenario.running});

  /// Allows switching the active UI scenario at runtime during development.
  void setScenario(MockScenario scenario) {
    currentScenario = scenario;
    debugPrint('[MockBackendService] Switched mock scenario to: $scenario');
  }

  /// Sets the active node version for testing scenarios.
  void setActiveVersionForTesting(String version) {
    _activeVersion = version;
  }

  @override
  Future<NodeStatus> getStatus() async {
    // Simulated brief network/IPC delay
    await Future.delayed(const Duration(milliseconds: 150));
    return _buildStatusForScenario(currentScenario);
  }

  @override
  Future<NodeStatus> refreshStatus() async {
    await Future.delayed(const Duration(milliseconds: 300));
    return _buildStatusForScenario(currentScenario);
  }

  @override
  Future<List<NodeVersion>> getAvailableVersions() async {
    return const [
      NodeVersion(
        version: '1.0.0-beta',
        isRecommended: true,
        isCurrent: true,
      ),
      NodeVersion(
        version: '0.13.7-alpha',
        isRecommended: false,
        isCurrent: false,
      ),
      NodeVersion(
        version: '0.13.6-alpha',
        isRecommended: false,
        isCurrent: false,
      ),
    ];
  }

  @override
  Future<String?> getInstalledVersion() async {
    if (currentScenario == MockScenario.nodeNotInstalled) return null;
    if (currentScenario == MockScenario.updateAvailable) return '0.13.7-alpha';
    return _activeVersion;
  }

  @override
  Future<bool> startDockerDesktop() async {
    debugPrint('[MockBackendService] Mock action: startDockerDesktop()');
    await Future.delayed(const Duration(milliseconds: 500));
    currentScenario = MockScenario.running;
    return true;
  }

  @override
  Future<bool> resumeDockerDesktop() async {
    debugPrint('[MockBackendService] Mock action: resumeDockerDesktop()');
    await Future.delayed(const Duration(milliseconds: 400));
    currentScenario = MockScenario.running;
    return true;
  }

  @override
  Future<bool> startNode() async {
    debugPrint('[MockBackendService] Mock action: startNode()');
    await Future.delayed(const Duration(milliseconds: 300));
    currentScenario = MockScenario.running;
    return true;
  }

  @override
  Future<bool> stopNode() async {
    debugPrint('[MockBackendService] Mock action: stopNode()');
    await Future.delayed(const Duration(milliseconds: 300));
    currentScenario = MockScenario.nodeStopped;
    return true;
  }

  @override
  Future<bool> pauseNode() async {
    debugPrint('[MockBackendService] Mock action: pauseNode()');
    await Future.delayed(const Duration(milliseconds: 300));
    currentScenario = MockScenario.nodePaused;
    return true;
  }

  @override
  Future<bool> resumeNode() async {
    debugPrint('[MockBackendService] Mock action: resumeNode()');
    await Future.delayed(const Duration(milliseconds: 300));
    currentScenario = MockScenario.running;
    return true;
  }

  @override
  Stream<InstallProgress> installNode(String version, {String? customImage}) async* {
    debugPrint('[MockBackendService] Mock action: installNode($version)');
    const stages = [
      'Preparing configuration',
      'Preparing storage volume',
      'Pulling Altr Stream image',
      'Starting container',
      'Waiting for health check',
      'Done',
    ];

    for (int i = 0; i < stages.length; i++) {
      await Future.delayed(const Duration(milliseconds: 400));
      final pct = ((i / (stages.length - 1)) * 100).toInt();
      yield InstallProgress(
        stage: stages[i],
        stageIndex: i + 1,
        totalStages: stages.length,
        percent: pct,
        message: i == stages.length - 1 ? 'Installation completed!' : 'Processing ${stages[i]}...',
        isDone: i == stages.length - 1,
      );
    }
    _activeVersion = version;
    currentScenario = MockScenario.running;
  }

  @override
  Stream<InstallProgress> updateNodeVersion(String version) async* {
    debugPrint('[MockBackendService] Mock action: updateNodeVersion($version)');
    yield* installNode(version);
  }

  @override
  Stream<InstallProgress> repairNode() async* {
    debugPrint('[MockBackendService] Mock action: repairNode()');
    yield* installNode(_activeVersion);
  }

  @override
  Future<bool> uninstallNode({bool deleteData = false}) async {
    debugPrint('[MockBackendService] Mock action: uninstallNode(deleteData: $deleteData)');
    await Future.delayed(const Duration(milliseconds: 500));
    currentScenario = MockScenario.nodeNotInstalled;
    return true;
  }

  @override
  Future<String> changeInstallationPath(String newPath) async {
    debugPrint('[MockBackendService] Mock action: changeInstallationPath($newPath)');
    _currentInstallDir = newPath;
    return _currentInstallDir;
  }

  @override
  Future<void> openWebInterface() async {
    debugPrint('[MockBackendService] Mock action: openWebInterface() -> http://localhost:8000');
  }

  @override
  Future<void> openInstallationDirectory() async {
    debugPrint('[MockBackendService] Mock action: openInstallationDirectory() -> $_currentInstallDir');
  }

  final List<String> _mockLogs = [
    '=== Session Activity & Installation Events ===',
    '[2026-10-18 11:30:01] [MOCK] Initializing Altr Stream Supervisor...',
    '[2026-10-18 11:30:02] [MOCK] Checking container runtime health on port 8000...',
    '[2026-10-18 11:30:03] [MOCK] Docker Engine diagnostics: state=ready, compose=available.',
    '[2026-10-18 11:30:04] [MOCK] Container \'altr-stream\' state: running (healthy).',
    '[2026-10-18 11:30:05] [MOCK] HTTP /healthz returned 200 OK.',
  ];

  @override
  Future<String> getInstallationLogs({bool forceRefresh = false, bool raw = false}) async {
    final buffer = StringBuffer();
    buffer.writeln('=== Manager Diagnostics & Operation Events (Session Activity & Installation Events) ===');
    if (_mockLogs.isNotEmpty) {
      buffer.writeln(_mockLogs.join('\n'));
    } else {
      buffer.writeln('No operations logged in current session.');
    }
    buffer.writeln();

    buffer.writeln('=== Container Logs (Docker Engine Managed - External) ===');
    buffer.writeln('# Note: Container logs are managed externally by Docker Engine.');
    if (currentScenario == MockScenario.running || currentScenario == MockScenario.nodePaused) {
      buffer.writeln('[2026-10-18 11:30:04] [CONTAINER] altr-stream running (healthy)');
      if (raw) {
        buffer.writeln('INFO:     127.0.0.1:45322 - "GET /api/v1/health HTTP/1.1" 200 OK');
        buffer.writeln('INFO:     172.20.0.1:51120 - "GET /api/v1/health HTTP/1.1" 200 OK');
        buffer.writeln('INFO:     127.0.0.1:45330 - "GET /api/v1/health HTTP/1.1" 200 OK');
      } else {
        buffer.writeln('... [3 successful GET /api/v1/health (200 OK) checks collapsed - switch to Raw Logs to view all] ...');
      }
    } else {
      buffer.writeln('Container altr-stream is not running.');
    }
    return buffer.toString().trim();
  }

  @override
  Future<void> clearLogs() async {
    _mockLogs.clear();
    debugPrint('[MockBackendService] Mock action: clearLogs() - buffer cleared');
  }

  @override
  void logEvent(String category, String message, {String level = 'INFO'}) {
    final now = DateTime.now().toIso8601String().replaceFirst('T', ' ').substring(0, 19);
    final entry = '[$now] [$level] [$category] $message';
    _mockLogs.add(entry);
    debugPrint('[MockBackendService] $entry');
  }

  @override
  Future<DiagnosticReport> runDiagnostics() async {
    await Future.delayed(const Duration(milliseconds: 150));
    final status = _buildStatusForScenario(currentScenario);
    final checks = <DiagnosticCheck>[
      DiagnosticCheck(
        title: 'Docker Desktop Installation',
        description: 'Verify Docker Desktop application bundle is installed',
        status: status.dockerDiag.desktopInstalled ? DiagnosticStatus.passed : DiagnosticStatus.failed,
        details: status.dockerDiag.desktopInstalled
            ? 'Docker Desktop application bundle located on host.'
            : 'Docker Desktop was not found at standard application locations.',
      ),
      DiagnosticCheck(
        title: 'Docker CLI Discovery',
        description: 'Verify docker command line executable',
        status: status.dockerDiag.cliInstalled ? DiagnosticStatus.passed : DiagnosticStatus.failed,
        details: status.dockerDiag.cliInstalled ? 'Docker CLI executable found in system PATH.' : 'docker CLI not found.',
      ),
      DiagnosticCheck(
        title: 'Docker Daemon Readiness',
        description: 'Verify connection to local Docker daemon',
        status: status.dockerDiag.engineRunning
            ? DiagnosticStatus.passed
            : (status.dockerDiag.state == DockerState.paused ? DiagnosticStatus.warning : DiagnosticStatus.failed),
        details: status.dockerDiag.engineRunning
            ? 'Docker daemon is active and responding.'
            : (status.dockerDiag.state == DockerState.paused
                ? 'Docker Desktop is currently paused.'
                : 'Cannot connect to Docker daemon: ${status.dockerDiag.technicalError ?? "Daemon stopped."}'),
      ),
      DiagnosticCheck(
        title: 'Altr Stream Configuration',
        description: 'Verify target installation files and docker-compose.yml',
        status: DiagnosticStatus.passed,
        details: 'Configuration directory valid at ${status.installDir}.',
      ),
      DiagnosticCheck(
        title: 'Port 8000 Availability',
        description: 'Verify web interface port binding',
        status: currentScenario == MockScenario.error ? DiagnosticStatus.failed : DiagnosticStatus.passed,
        details: currentScenario == MockScenario.error
            ? 'Port 8000 is occupied by another process PID 4120.'
            : 'Port 8000 is available for container binding.',
      ),
      DiagnosticCheck(
        title: 'Container State',
        description: 'Verify Altr Stream container runtime state',
        status: status.nodeState == NodeState.running
            ? DiagnosticStatus.passed
            : (status.nodeState == NodeState.stopped ? DiagnosticStatus.warning : DiagnosticStatus.info),
        details: status.nodeState == NodeState.running
            ? 'Container altr-stream is running and healthy.'
            : 'Container status is ${status.nodeState.displayName}.',
      ),
    ];

    String primaryFinding = 'All system and runtime checks passed.';
    String summary = 'Altr Stream Node is healthy and operating normally.';
    RecommendedActionType action = RecommendedActionType.none;
    String actionLabel = '';

    if (!status.dockerDiag.desktopInstalled) {
      primaryFinding = 'Docker Desktop Not Installed';
      summary = 'Docker Desktop is required to run Altr Stream containers. Please install Docker Desktop to proceed.';
      action = RecommendedActionType.installDocker;
      actionLabel = 'Install Docker Desktop';
    } else if (status.dockerDiag.state == DockerState.stopped) {
      primaryFinding = 'Docker Desktop Stopped';
      summary = 'Docker Desktop is installed but the background daemon is not running. Start Docker Desktop to continue.';
      action = RecommendedActionType.startDocker;
      actionLabel = 'Start Docker Desktop';
    } else if (status.dockerDiag.state == DockerState.paused) {
      primaryFinding = 'Docker Desktop Paused';
      summary = 'Docker Desktop is paused. Resume it to continue node operations.';
      action = RecommendedActionType.resumeDocker;
      actionLabel = 'Resume Docker Desktop';
    } else if (currentScenario == MockScenario.error) {
      primaryFinding = 'Port 8000 Conflict';
      summary = 'Port 8000 is occupied by another process. Repairing will reconfigure or restart container.';
      action = RecommendedActionType.repairNode;
      actionLabel = 'Repair Runtime Bindings';
    } else if (status.nodeState == NodeState.stopped) {
      primaryFinding = 'Altr Stream Node Stopped';
      summary = 'Docker is running, but the Altr Stream container is currently stopped.';
      action = RecommendedActionType.startNode;
      actionLabel = 'Start Altr Stream';
    }

    return DiagnosticReport(
      checks: checks,
      primaryFinding: primaryFinding,
      summaryExplanation: summary,
      recommendedAction: action,
      recommendedActionLabel: actionLabel,
      timestamp: DateTime.now(),
    );
  }

  NodeStatus _buildStatusForScenario(MockScenario scenario) {
    switch (scenario) {
      case MockScenario.running:
        return NodeStatus(
          installDir: _currentInstallDir,
          targetVersion: _activeVersion,
          activeVersion: _activeVersion,
          recommendedVersion: _recommendedVersion,
          nodeState: NodeState.running,
          dockerDiag: const DockerDiagnostics(
            state: DockerState.ready,
            cliInstalled: true,
            desktopInstalled: true,
            engineRunning: true,
            statusText: 'Ready',
          ),
          port: 8000,
          webUrl: 'http://localhost:8000',
          healthy: true,
        );

      case MockScenario.updateAvailable:
        return NodeStatus(
          installDir: _currentInstallDir,
          targetVersion: '1.0.0-beta',
          activeVersion: '0.13.7-alpha',
          recommendedVersion: '1.0.0-beta',
          nodeState: NodeState.running,
          dockerDiag: const DockerDiagnostics(
            state: DockerState.ready,
            cliInstalled: true,
            desktopInstalled: true,
            engineRunning: true,
            statusText: 'Ready',
          ),
          port: 8000,
          webUrl: 'http://localhost:8000',
          healthy: true,
        );

      case MockScenario.dockerNotInstalled:
        return NodeStatus(
          installDir: _currentInstallDir,
          targetVersion: '1.0.0-beta',
          activeVersion: null,
          nodeState: NodeState.stopped,
          dockerDiag: const DockerDiagnostics(
            state: DockerState.notInstalled,
            cliInstalled: false,
            desktopInstalled: false,
            engineRunning: false,
            statusText: 'Docker Desktop not Installed',
            actionHint: 'Install Docker Desktop to run Altr Stream.',
          ),
          healthy: false,
        );

      case MockScenario.dockerStopped:
        return NodeStatus(
          installDir: _currentInstallDir,
          targetVersion: '1.0.0-beta',
          activeVersion: null,
          nodeState: NodeState.stopped,
          dockerDiag: const DockerDiagnostics(
            state: DockerState.stopped,
            cliInstalled: true,
            desktopInstalled: true,
            engineRunning: false,
            statusText: 'Docker Desktop is Stopped',
            actionHint: 'Start Docker Desktop to continue.',
          ),
          healthy: false,
        );

      case MockScenario.dockerStarting:
        return NodeStatus(
          installDir: _currentInstallDir,
          targetVersion: '1.0.0-beta',
          activeVersion: null,
          nodeState: NodeState.stopped,
          dockerDiag: const DockerDiagnostics(
            state: DockerState.starting,
            cliInstalled: true,
            desktopInstalled: true,
            engineRunning: false,
            statusText: 'Docker Desktop Starting',
            actionHint: 'Waiting for Docker daemon to become ready...',
          ),
          healthy: false,
        );

      case MockScenario.dockerPaused:
        return NodeStatus(
          installDir: _currentInstallDir,
          targetVersion: '1.0.0-beta',
          activeVersion: null,
          nodeState: NodeState.stopped,
          dockerDiag: const DockerDiagnostics(
            state: DockerState.paused,
            cliInstalled: true,
            desktopInstalled: true,
            engineRunning: false,
            statusText: 'Docker Desktop is Paused',
            actionHint: 'Resume Docker Desktop to continue.',
          ),
          healthy: false,
        );

      case MockScenario.nodeNotInstalled:
        return NodeStatus(
          installDir: _currentInstallDir,
          targetVersion: '1.0.0-beta',
          activeVersion: null,
          recommendedVersion: _recommendedVersion,
          nodeState: NodeState.notInstalled,
          dockerDiag: const DockerDiagnostics(
            state: DockerState.ready,
            cliInstalled: true,
            desktopInstalled: true,
            engineRunning: true,
            statusText: 'Ready',
          ),
          healthy: false,
        );

      case MockScenario.nodeStopped:
        return NodeStatus(
          installDir: _currentInstallDir,
          targetVersion: '1.0.0-beta',
          activeVersion: _activeVersion,
          recommendedVersion: _recommendedVersion,
          nodeState: NodeState.stopped,
          dockerDiag: const DockerDiagnostics(
            state: DockerState.ready,
            cliInstalled: true,
            desktopInstalled: true,
            engineRunning: true,
            statusText: 'Ready',
          ),
          healthy: false,
        );

      case MockScenario.nodePaused:
        return NodeStatus(
          installDir: _currentInstallDir,
          targetVersion: '1.0.0-beta',
          activeVersion: _activeVersion,
          recommendedVersion: _recommendedVersion,
          nodeState: NodeState.paused,
          dockerDiag: const DockerDiagnostics(
            state: DockerState.ready,
            cliInstalled: true,
            desktopInstalled: true,
            engineRunning: true,
            statusText: 'Ready',
          ),
          healthy: false,
          technicalIssues: const ['Node container is paused.'],
        );

      case MockScenario.installing:
        return NodeStatus(
          installDir: _currentInstallDir,
          targetVersion: '1.0.0-beta',
          activeVersion: null,
          nodeState: NodeState.installing,
          dockerDiag: const DockerDiagnostics(
            state: DockerState.ready,
            cliInstalled: true,
            desktopInstalled: true,
            engineRunning: true,
            statusText: 'Ready',
          ),
          healthy: false,
        );

      case MockScenario.error:
        return NodeStatus(
          installDir: _currentInstallDir,
          targetVersion: '1.0.0-beta',
          activeVersion: null,
          nodeState: NodeState.error,
          dockerDiag: const DockerDiagnostics(
            state: DockerState.error,
            cliInstalled: true,
            desktopInstalled: true,
            engineRunning: false,
            statusText: 'Error',
            technicalError: 'Port 8000 conflict with another running service.',
          ),
          healthy: false,
          technicalIssues: const [
            'Port 8000 is occupied by process PID 4120',
            'Cannot bind container host port',
          ],
        );
    }
  }
}
