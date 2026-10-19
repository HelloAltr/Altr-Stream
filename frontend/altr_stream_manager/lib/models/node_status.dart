/// Docker service state.
enum DockerState {
  ready,
  stopped,
  paused,
  starting,
  notInstalled,
  error,
  unknown;

  static DockerState fromString(String? val) {
    switch (val?.toLowerCase().trim()) {
      case 'ready':
        return DockerState.ready;
      case 'stopped':
        return DockerState.stopped;
      case 'paused':
        return DockerState.paused;
      case 'starting':
        return DockerState.starting;
      case 'not_installed':
        return DockerState.notInstalled;
      case 'error':
        return DockerState.error;
      default:
        return DockerState.unknown;
    }
  }

  String get displayName {
    switch (this) {
      case DockerState.ready:
        return 'Ready';
      case DockerState.stopped:
        return 'Stopped';
      case DockerState.paused:
        return 'Paused';
      case DockerState.starting:
        return 'Starting...';
      case DockerState.notInstalled:
        return 'Not Installed';
      case DockerState.error:
        return 'Error';
      case DockerState.unknown:
        return 'Unknown';
    }
  }
}

/// Altr Stream Node runtime state.
enum NodeState {
  running,
  stopped,
  paused,
  installing,
  notInstalled,
  updating,
  error,
  unknown;

  static NodeState fromString(String? val) {
    switch (val?.toLowerCase().trim()) {
      case 'running':
        return NodeState.running;
      case 'stopped':
        return NodeState.stopped;
      case 'paused':
        return NodeState.paused;
      case 'installing':
        return NodeState.installing;
      case 'not_installed':
        return NodeState.notInstalled;
      case 'updating':
        return NodeState.updating;
      case 'error':
        return NodeState.error;
      default:
        return NodeState.unknown;
    }
  }

  String get displayName {
    switch (this) {
      case NodeState.running:
        return 'Running';
      case NodeState.stopped:
        return 'Stopped';
      case NodeState.paused:
        return 'Paused';
      case NodeState.installing:
        return 'Installing...';
      case NodeState.notInstalled:
        return 'Not Installed';
      case NodeState.updating:
        return 'Updating...';
      case NodeState.error:
        return 'Error';
      case NodeState.unknown:
        return 'Unknown';
    }
  }
}

/// Docker diagnostics output from engine.
class DockerDiagnostics {
  final DockerState state;
  final bool cliInstalled;
  final bool desktopInstalled;
  final bool engineRunning;
  final String statusText;
  final String actionHint;
  final String? failureReason;
  final String? technicalError;

  const DockerDiagnostics({
    required this.state,
    this.cliInstalled = false,
    this.desktopInstalled = false,
    this.engineRunning = false,
    this.statusText = '',
    this.actionHint = '',
    this.failureReason,
    this.technicalError,
  });

  factory DockerDiagnostics.fromJson(Map<String, dynamic> json) {
    return DockerDiagnostics(
      state: DockerState.fromString(json['state'] as String?),
      cliInstalled: json['cli_installed'] as bool? ?? false,
      desktopInstalled: json['desktop_installed'] as bool? ?? false,
      engineRunning: json['engine_running'] as bool? ?? false,
      statusText: json['status_text'] as String? ?? '',
      actionHint: json['action_hint'] as String? ?? '',
      failureReason: json['failure_reason'] as String?,
      technicalError: json['technical_error'] as String?,
    );
  }
}

/// Release version information.
class NodeVersion {
  final String version;
  final bool isRecommended;
  final bool isCurrent;
  final bool isCustom;
  final String? releaseNotesUrl;

  const NodeVersion({
    required this.version,
    this.isRecommended = false,
    this.isCurrent = false,
    this.isCustom = false,
    this.releaseNotesUrl,
  });

  factory NodeVersion.fromJson(Map<String, dynamic> json) {
    return NodeVersion(
      version: json['version'] as String? ?? '',
      isRecommended: json['is_recommended'] as bool? ?? false,
      isCurrent: json['is_current'] as bool? ?? false,
      isCustom: json['is_custom'] as bool? ?? false,
      releaseNotesUrl: json['release_notes_url'] as String?,
    );
  }
}

/// Comprehensive Node Status model representing the live operational state.
class NodeStatus {
  final String installDir;
  final String targetVersion;
  final String? activeVersion;
  final String? recommendedVersion;
  final NodeState nodeState;
  final DockerDiagnostics dockerDiag;
  final int port;
  final String webUrl;
  final bool healthy;
  final List<String> technicalIssues;

  const NodeStatus({
    required this.installDir,
    this.targetVersion = '',
    this.activeVersion,
    this.recommendedVersion,
    this.nodeState = NodeState.unknown,
    this.dockerDiag = const DockerDiagnostics(state: DockerState.unknown),
    this.port = 8000,
    this.webUrl = 'http://localhost:8000',
    this.healthy = false,
    this.technicalIssues = const [],
  });

  bool get isRunning => nodeState == NodeState.running;
  bool get isPaused => nodeState == NodeState.paused;
  bool get isInstalled => activeVersion != null && activeVersion!.isNotEmpty;
  bool get hasUpdate =>
      isInstalled &&
      recommendedVersion != null &&
      recommendedVersion!.isNotEmpty &&
      recommendedVersion != activeVersion;

  factory NodeStatus.fromJson(Map<String, dynamic> json) {
    final diagMap = json['docker_diag'] as Map<String, dynamic>? ?? {};
    final issuesRaw = json['technical_issues'] as List<dynamic>? ?? [];

    return NodeStatus(
      installDir: json['install_dir'] as String? ?? '',
      targetVersion: json['target_version'] as String? ?? '',
      activeVersion: json['active_version'] as String?,
      recommendedVersion: json['recommended_version'] as String?,
      nodeState: NodeState.fromString(json['container_state'] as String?),
      dockerDiag: DockerDiagnostics.fromJson(diagMap),
      port: json['port'] as int? ?? 8000,
      webUrl: json['web_url'] as String? ?? 'http://localhost:8000',
      healthy: json['healthy'] as bool? ?? false,
      technicalIssues: issuesRaw.map((e) => e.toString()).toList(),
    );
  }
}
