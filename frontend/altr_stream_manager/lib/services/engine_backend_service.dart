import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/constants.dart';
import '../models/diagnostic_report.dart';
import '../models/install_progress.dart';
import '../models/node_status.dart';
import 'backend_service.dart';

/// Production backend service executing the compiled Go installer engine.
typedef CommandRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments,
);

/// Production backend service executing the compiled Go installer engine.
class EngineBackendService implements BackendService {
  final String? customEnginePath;
  String? _cachedEnginePath;
  String _effectiveInstallDir = '';
  String? _lastEngineError;
  final CommandRunner _commandRunner;
  final List<String> _sessionLogs = [];
  String? _cachedLogs;
  DateTime? _lastLogsFetchTime;
  DateTime? _lastLogsClearedTime;
  String? _lastLoggedStatusState;
  DateTime? _lastLoggedStatusTime;

  /// Sanitizes sensitive values (tokens, credentials, API keys) from log messages.
  static String sanitizeLogMessage(String message) {
    var sanitized = message;
    sanitized = sanitized.replaceAll(
      RegExp(r'(Bearer\s+)[A-Za-z0-9_\-\.]{8,}', caseSensitive: false),
      r'$1[REDACTED]',
    );
    sanitized = sanitized.replaceAll(
      RegExp(r'(token[=:\s]+)[A-Za-z0-9_\-\.]{8,}', caseSensitive: false),
      r'$1[REDACTED]',
    );
    sanitized = sanitized.replaceAll(
      RegExp(r'(password[=:\s]+)[^\s,;&]+', caseSensitive: false),
      r'$1[REDACTED]',
    );
    sanitized = sanitized.replaceAll(
      RegExp(r'(secret[=:\s]+)[^\s,;&]+', caseSensitive: false),
      r'$1[REDACTED]',
    );
    sanitized = sanitized.replaceAll(
      RegExp(r'ghp_[A-Za-z0-9]{20,}'),
      '[REDACTED_GITHUB_TOKEN]',
    );
    return sanitized;
  }

  /// Records a structured, chronological session log event with sanitized message.
  @override
  void logEvent(String category, String message, {String level = 'INFO'}) {
    final now = DateTime.now().toIso8601String().replaceFirst('T', ' ').substring(0, 19);
    final sanitized = sanitizeLogMessage(message);
    final entry = '[$now] [$level] [$category] $sanitized';
    _sessionLogs.add(entry);
    debugPrint('[EngineBackendService] $entry');
  }

  EngineBackendService({
    this.customEnginePath,
    CommandRunner? commandRunner,
  }) : _commandRunner = commandRunner ?? _defaultProcessRunner {
    logEvent(
      'Startup',
      'Altr Stream Manager initialized (Backend: EngineBackendService, Platform: ${Platform.operatingSystem} ${Platform.operatingSystemVersion})',
      level: 'INFO',
    );
  }

  /// Default process runner with enhanced environment variables (PATH, HOME, DOCKER_HOST).
  static Future<ProcessResult> _defaultProcessRunner(
    String executable,
    List<String> arguments,
  ) {
    final env = Map<String, String>.from(Platform.environment);
    final home = env['HOME'] ?? Platform.environment['HOME'] ?? '';

    // Augment PATH so system commands, docker, and brew tools are always discoverable
    final currentPath = env['PATH'] ?? '';
    final additionalPaths = <String>[
      if (home.isNotEmpty) '$home/.docker/bin',
      '/usr/local/bin',
      '/opt/homebrew/bin',
      '/opt/homebrew/sbin',
      '/usr/bin',
      '/bin',
      '/usr/sbin',
      '/sbin',
    ];

    final pathSet = currentPath.split(':').where((p) => p.isNotEmpty).toList();
    for (final p in additionalPaths) {
      if (!pathSet.contains(p)) {
        pathSet.add(p);
      }
    }
    env['PATH'] = pathSet.join(':');

    if (home.isNotEmpty && !env.containsKey('HOME')) {
      env['HOME'] = home;
    }

    // Set DOCKER_HOST fallback if macOS Docker Desktop socket exists and DOCKER_HOST not explicitly provided
    if (!env.containsKey('DOCKER_HOST') && home.isNotEmpty) {
      final defaultMacSocket = File('$home/.docker/run/docker.sock');
      if (defaultMacSocket.existsSync()) {
        env['DOCKER_HOST'] = 'unix://${defaultMacSocket.path}';
      }
    }

    return Process.run(
      executable,
      arguments,
      environment: env,
      includeParentEnvironment: true,
    );
  }

  /// Returns the most recent error encountered by the engine, if any.
  String? get lastEngineError => _lastEngineError;

  /// Verifies that [path] points to an existing regular file that is executable.
  bool _isExecutableFile(String path) {
    try {
      final file = File(path);
      if (!file.existsSync()) return false;

      final stat = file.statSync();
      if (stat.type != FileSystemEntityType.file) return false;

      if (!Platform.isWindows) {
        // POSIX: Ensure at least one execute bit is set (user, group, or other)
        return (stat.mode & 0x49) != 0;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Locates the native installer engine executable across macOS, Windows, and dev environments.
  ///
  /// Deterministic Strategy:
  /// - Tier 0: Explicit Override:
  ///   - Programmatic [customEnginePath] (strictly verified, no fallthrough)
  ///   - Environment variable [ALTR_INSTALLER_ENGINE] (strictly verified, no fallthrough)
  /// - Tier 1: Packaged Application Bundle / Installation Directory:
  ///   - macOS: `<App>.app/Contents/Resources/altr-installer-engine` (primary packaging location)
  ///   - macOS/Windows/Linux: Beside executable (`<execDir>/altr-installer-engine[.exe]`)
  /// - Tier 2: Development / Source Tree Discovery (local `flutter run` / tests / IDE debug):
  ///   - `<cwd>/packaging/engine/$binaryName`
  ///   - `<cwd>/../packaging/engine/$binaryName`
  ///   - `<cwd>/dist/$binaryName`
  ///   - `<cwd>/../dist/$binaryName`
  ///   - Flutter build tree ancestor search (up to 8 levels strictly for packaging/engine or dist)
  ///
  /// Arbitrary `/tmp` fallbacks and unbounded filesystem walks are strictly prohibited.
  String? resolveEngineBinary({String? overrideExecutable}) {
    // Tier 0a: Programmatic override
    final customPath = customEnginePath;
    if (customPath != null) {
      if (_isExecutableFile(customPath)) {
        return customPath;
      }
      debugPrint('[EngineBackendService] Custom engine path not found or not executable: $customPath');
      return null;
    }

    if (_cachedEnginePath != null && _isExecutableFile(_cachedEnginePath!)) {
      return _cachedEnginePath;
    }

    final binaryName = Platform.isWindows ? 'altr-installer-engine.exe' : 'altr-installer-engine';

    // Tier 0b: Environment variable override
    // If specified, it must be valid; an invalid or stale override fails clearly without falling through.
    final envPath = Platform.environment['ALTR_INSTALLER_ENGINE'];
    if (envPath != null && envPath.isNotEmpty) {
      if (_isExecutableFile(envPath)) {
        _cachedEnginePath = envPath;
        debugPrint('[EngineBackendService] Resolved binary from ALTR_INSTALLER_ENGINE: $envPath');
        return envPath;
      }
      debugPrint('[EngineBackendService] ALTR_INSTALLER_ENGINE override specified but invalid or not executable: $envPath');
      return null;
    }

    // Tier 1: Packaged Application Bundle / Installation Directory
    final execFile = File(overrideExecutable ?? Platform.resolvedExecutable);
    final execDir = execFile.parent;

    // 1a. macOS App Bundle: Contents/Resources/altr-installer-engine (scripts/build_macos_app.py output)
    if (!Platform.isWindows) {
      final inResourcesPath = '${execDir.parent.path}/Resources/$binaryName';
      if (_isExecutableFile(inResourcesPath)) {
        _cachedEnginePath = File(inResourcesPath).absolute.path;
        debugPrint('[EngineBackendService] Resolved binary in Resources: $_cachedEnginePath');
        return _cachedEnginePath;
      }
    }

    // 1b. Adjacent to executable (Windows {app}\altr-installer-engine.exe or macOS Contents/MacOS)
    final inSameDirPath = '${execDir.path}/$binaryName';
    if (_isExecutableFile(inSameDirPath)) {
      _cachedEnginePath = File(inSameDirPath).absolute.path;
      debugPrint('[EngineBackendService] Resolved binary beside executable: $_cachedEnginePath');
      return _cachedEnginePath;
    }

    // Tier 2: Development / Source Tree Discovery
    // Checks deterministic candidate directories relative to current working directory:
    // - cwd (when running from repository root)
    // - cwd.parent (when running from frontend/)
    // - cwd.parent.parent (when running from frontend/altr_stream_manager/)
    final cwd = Directory.current;
    final candidateBaseDirs = <Directory>[
      cwd,
      cwd.parent,
      cwd.parent.parent,
    ];

    for (final baseDir in candidateBaseDirs) {
      final inPackaging = '${baseDir.path}/packaging/engine/$binaryName';
      if (_isExecutableFile(inPackaging)) {
        _cachedEnginePath = File(inPackaging).absolute.path;
        debugPrint('[EngineBackendService] Resolved binary in packaging/engine: $_cachedEnginePath');
        return _cachedEnginePath;
      }

      final inDist = '${baseDir.path}/dist/$binaryName';
      if (_isExecutableFile(inDist)) {
        _cachedEnginePath = File(inDist).absolute.path;
        debugPrint('[EngineBackendService] Resolved binary in dist: $_cachedEnginePath');
        return _cachedEnginePath;
      }
    }

    // Tier 2b: If launched from a Flutter build output bundle (e.g. build/macos/Build/Products/Debug/...),
    // ascend up to 8 levels strictly looking for the repo's packaging/engine or dist directory.
    if (execDir.path.contains('build')) {
      Directory dir = execDir;
      for (int i = 0; i < 8; i++) {
        final inPackaging = '${dir.path}/packaging/engine/$binaryName';
        if (_isExecutableFile(inPackaging)) {
          _cachedEnginePath = File(inPackaging).absolute.path;
          debugPrint('[EngineBackendService] Resolved binary from build ancestor: $_cachedEnginePath');
          return _cachedEnginePath;
        }
        final inDist = '${dir.path}/dist/$binaryName';
        if (_isExecutableFile(inDist)) {
          _cachedEnginePath = File(inDist).absolute.path;
          debugPrint('[EngineBackendService] Resolved binary from build ancestor dist: $_cachedEnginePath');
          return _cachedEnginePath;
        }
        final parent = dir.parent;
        if (parent.path == dir.path) break;
        dir = parent;
      }
    }

    debugPrint('[EngineBackendService] WARNING: Could not resolve native installer engine executable on host.');
    return null;
  }

  Future<Map<String, dynamic>> _runEngineJson(List<String> args) async {
    final binary = resolveEngineBinary();
    if (binary == null) {
      const msg = 'altr-installer-engine executable not found on host.';
      _lastEngineError = msg;
      throw Exception(msg);
    }

    try {
      final result = await _commandRunner(binary, args).timeout(const Duration(seconds: 15));
      if (result.exitCode != 0) {
        final err = result.stderr.toString().trim();
        final msg = 'Engine command failed (code ${result.exitCode}): $err';
        _lastEngineError = msg;
        throw Exception(msg);
      }

      final out = result.stdout.toString().trim();
      if (out.isEmpty) {
        return <String, dynamic>{};
      }

      try {
        return jsonDecode(out) as Map<String, dynamic>;
      } catch (e) {
        final msg = 'Failed to decode engine output as JSON: $e\nOutput was: $out';
        _lastEngineError = msg;
        throw Exception(msg);
      }
    } catch (e) {
      _lastEngineError = e.toString();
      rethrow;
    }
  }

  @override
  Future<NodeStatus> getStatus() async {
    final sw = Stopwatch()..start();
    try {
      final args = ['status'];
      if (_effectiveInstallDir.isNotEmpty) {
        args.addAll(['--target-dir', _effectiveInstallDir]);
      }
      final json = await _runEngineJson(args);
      final status = NodeStatus.fromJson(json);
      _effectiveInstallDir = status.installDir;
      _lastEngineError = null;
      sw.stop();

      // Rate-limited status check logging (logs transitions, errors, or 60s heartbeat)
      final currentState = '${status.dockerDiag.state.name}_${status.nodeState.name}_${status.healthy}';
      final now = DateTime.now();
      final shouldLog = _lastLoggedStatusState != currentState ||
          _lastLoggedStatusTime == null ||
          now.difference(_lastLoggedStatusTime!).inSeconds >= 60;

      if (shouldLog) {
        _lastLoggedStatusState = currentState;
        _lastLoggedStatusTime = now;
        logEvent(
          'Status',
          'Status probe completed in ${sw.elapsedMilliseconds}ms: '
          'Docker=${status.dockerDiag.state.displayName} (${status.dockerDiag.statusText}), '
          'Node=${status.nodeState.displayName}, Healthy=${status.healthy}',
          level: status.dockerDiag.state == DockerState.error ? 'WARN' : 'INFO',
        );
      }

      return status;
    } catch (e) {
      sw.stop();
      debugPrint('[EngineBackendService] getStatus error: $e');
      final home = Platform.environment['HOME'] ?? '';
      _lastEngineError = e.toString();
      logEvent(
        'Status',
        'Status probe failed in ${sw.elapsedMilliseconds}ms: ${sanitizeLogMessage(e.toString())}',
        level: 'ERROR',
      );
      return NodeStatus(
        installDir: _effectiveInstallDir.isNotEmpty ? _effectiveInstallDir : '$home/.altr-stream',
        nodeState: NodeState.error,
        dockerDiag: DockerDiagnostics(
          state: DockerState.error,
          statusText: 'Engine Error',
          technicalError: e.toString(),
        ),
        technicalIssues: [e.toString()],
      );
    }
  }

  @override
  Future<NodeStatus> refreshStatus() async {
    return getStatus();
  }

  @override
  Future<DiagnosticReport> runDiagnostics() async {
    logEvent('Diagnostics', 'Diagnose and Fix diagnostic sweep initiated...', level: 'INFO');
    final sw = Stopwatch()..start();
    final checks = <DiagnosticCheck>[];

    // Check 1: Docker Desktop Installation
    bool desktopFound = false;
    String desktopPathEvidence = '';
    try {
      if (Platform.isMacOS) {
        final candidates = [
          '/Applications/Docker.app',
          '/Applications/Docker Desktop.app',
          '${Platform.environment['HOME'] ?? ''}/Applications/Docker.app',
          '${Platform.environment['HOME'] ?? ''}/Applications/Docker Desktop.app',
        ];
        for (final p in candidates) {
          if (Directory(p).existsSync()) {
            desktopFound = true;
            desktopPathEvidence = p;
            break;
          }
        }
      } else if (Platform.isWindows) {
        final progFiles = Platform.environment['ProgramFiles'] ?? r'C:\Program Files';
        final winPath = '$progFiles\\Docker\\Docker\\Docker Desktop.exe';
        if (File(winPath).existsSync()) {
          desktopFound = true;
          desktopPathEvidence = winPath;
        }
      }
    } catch (_) {}

    checks.add(DiagnosticCheck(
      title: 'Docker Desktop Installation',
      description: 'Verify Docker Desktop application is installed on system',
      status: desktopFound ? DiagnosticStatus.passed : DiagnosticStatus.failed,
      details: desktopFound
          ? 'Docker Desktop application bundle located at: $desktopPathEvidence'
          : 'Docker Desktop application was not found in standard application locations.',
    ));
    logEvent(
      'Diagnostics',
      'Check 1 [Docker Desktop Installation]: ${desktopFound ? "PASSED ($desktopPathEvidence)" : "FAILED"}',
      level: desktopFound ? 'INFO' : 'WARN',
    );

    // Check 2: Docker CLI Discovery
    bool cliFound = false;
    String cliEvidence = '';
    try {
      final cliName = Platform.isWindows ? 'docker.exe' : 'docker';
      final res = await _commandRunner(cliName, ['--version']).timeout(const Duration(seconds: 3));
      if (res.exitCode == 0) {
        cliFound = true;
        cliEvidence = res.stdout.toString().trim();
      }
    } catch (_) {}

    checks.add(DiagnosticCheck(
      title: 'Docker CLI Discovery',
      description: 'Verify Docker command-line tool availability',
      status: cliFound ? DiagnosticStatus.passed : DiagnosticStatus.warning,
      details: cliFound
          ? 'Docker CLI available: $cliEvidence'
          : 'Docker CLI not found in system PATH or did not respond.',
    ));
    logEvent(
      'Diagnostics',
      'Check 2 [Docker CLI Discovery]: ${cliFound ? "PASSED ($cliEvidence)" : "WARNING"}',
      level: cliFound ? 'INFO' : 'WARN',
    );

    // Check 3: Docker Daemon Connectivity
    bool daemonReady = false;
    bool daemonPaused = false;
    String daemonError = '';
    try {
      final cliName = Platform.isWindows ? 'docker.exe' : 'docker';
      final res = await _commandRunner(cliName, ['info']).timeout(const Duration(seconds: 3));
      if (res.exitCode == 0) {
        daemonReady = true;
      } else {
        final err = res.stderr.toString().trim();
        final lower = err.toLowerCase();
        if (lower.contains('paused')) {
          daemonPaused = true;
        }
        daemonError = sanitizeLogMessage(err.isNotEmpty ? err : res.stdout.toString().trim());
      }
    } catch (e) {
      daemonError = sanitizeLogMessage(e.toString());
    }

    if (!desktopFound && !cliFound) {
      checks.add(const DiagnosticCheck(
        title: 'Docker Daemon Readiness',
        description: 'Verify Docker daemon connection',
        status: DiagnosticStatus.skipped,
        details: 'Skipped because Docker Desktop is not installed on this system.',
      ));
      logEvent('Diagnostics', 'Check 3 [Docker Daemon Readiness]: SKIPPED (Docker not installed)', level: 'INFO');
    } else if (daemonReady) {
      checks.add(const DiagnosticCheck(
        title: 'Docker Daemon Readiness',
        description: 'Verify Docker daemon connection',
        status: DiagnosticStatus.passed,
        details: 'Docker daemon is active and responding normally.',
      ));
      logEvent('Diagnostics', 'Check 3 [Docker Daemon Readiness]: PASSED (Daemon active)', level: 'INFO');
    } else if (daemonPaused) {
      checks.add(const DiagnosticCheck(
        title: 'Docker Daemon Readiness',
        description: 'Verify Docker daemon connection',
        status: DiagnosticStatus.warning,
        details: 'Docker Desktop is currently in a paused state.',
      ));
      logEvent('Diagnostics', 'Check 3 [Docker Daemon Readiness]: WARNING (Docker Desktop paused)', level: 'WARN');
    } else {
      checks.add(DiagnosticCheck(
        title: 'Docker Daemon Readiness',
        description: 'Verify Docker daemon connection',
        status: DiagnosticStatus.failed,
        details: 'Docker daemon is not running ($daemonError).',
      ));
      logEvent('Diagnostics', 'Check 3 [Docker Daemon Readiness]: FAILED ($daemonError)', level: 'WARN');
    }

    // Check 4: Runtime Configuration & Target Directory
    final home = Platform.environment['HOME'] ?? '';
    final dir = _effectiveInstallDir.isNotEmpty ? _effectiveInstallDir : '$home/.altr-stream';
    final composeFile = File('$dir/docker-compose.yml');
    final envFile = File('$dir/.env');
    final hasConfig = composeFile.existsSync() && envFile.existsSync();

    checks.add(DiagnosticCheck(
      title: 'Altr Stream Configuration',
      description: 'Verify configuration directory and runtime files',
      status: hasConfig ? DiagnosticStatus.passed : DiagnosticStatus.info,
      details: hasConfig
          ? 'Configuration files verified in $dir.'
          : 'Installation configuration not found in $dir (will be generated upon installation).',
    ));
    logEvent(
      'Diagnostics',
      'Check 4 [Altr Stream Configuration]: ${hasConfig ? "PASSED" : "INFO (Uninstalled/default)"}',
      level: 'INFO',
    );

    // Check 5: Port 8000 Availability
    bool portAvailable = true;
    String portDetails = 'Port 8000 is available for web dashboard binding.';
    try {
      final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 8000);
      await socket.close();
    } catch (_) {
      // Port in use: is it our running container?
      if (daemonReady) {
        portDetails = 'Port 8000 is in use (bound to active container or process).';
      } else {
        portAvailable = false;
        portDetails = 'Port 8000 is occupied by an external host process while Docker is offline.';
      }
    }

    checks.add(DiagnosticCheck(
      title: 'Port 8000 Availability',
      description: 'Check host port 8000 accessibility',
      status: portAvailable ? DiagnosticStatus.passed : DiagnosticStatus.warning,
      details: portDetails,
    ));
    logEvent('Diagnostics', 'Check 5 [Port 8000 Availability]: $portDetails', level: portAvailable ? 'INFO' : 'WARN');

    // Check 6: Container Runtime State
    if (!daemonReady) {
      checks.add(const DiagnosticCheck(
        title: 'Altr Stream Container State',
        description: 'Check container status and health endpoint',
        status: DiagnosticStatus.skipped,
        details: 'Skipped (requires running Docker daemon).',
      ));
      logEvent('Diagnostics', 'Check 6 [Container State]: SKIPPED (Docker daemon offline)', level: 'INFO');
    } else {
      bool containerRunning = false;
      bool containerHealthy = false;
      try {
        final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
        final req = await client.getUrl(Uri.parse('http://localhost:8000/api/v1/health'));
        final resp = await req.close();
        if (resp.statusCode == 200) {
          containerRunning = true;
          containerHealthy = true;
        }
      } catch (_) {}

      if (containerRunning && containerHealthy) {
        checks.add(const DiagnosticCheck(
          title: 'Altr Stream Container State',
          description: 'Check container status and health endpoint',
          status: DiagnosticStatus.passed,
          details: 'Altr Stream container is running and healthy on http://localhost:8000.',
        ));
        logEvent('Diagnostics', 'Check 6 [Container State]: PASSED (Healthy)', level: 'INFO');
      } else if (hasConfig) {
        checks.add(const DiagnosticCheck(
          title: 'Altr Stream Container State',
          description: 'Check container status and health endpoint',
          status: DiagnosticStatus.warning,
          details: 'Altr Stream container is not running or healthcheck did not respond.',
        ));
        logEvent('Diagnostics', 'Check 6 [Container State]: WARNING (Container stopped or unhealthy)', level: 'WARN');
      } else {
        checks.add(const DiagnosticCheck(
          title: 'Altr Stream Container State',
          description: 'Check container status and health endpoint',
          status: DiagnosticStatus.info,
          details: 'Altr Stream is not yet installed.',
        ));
        logEvent('Diagnostics', 'Check 6 [Container State]: INFO (Not installed)', level: 'INFO');
      }
    }

    // Determine primary finding and safe action
    String primaryFinding = 'All checks passed successfully.';
    String summary = 'Docker Desktop and Altr Stream runtime are operating normally.';
    RecommendedActionType action = RecommendedActionType.none;
    String actionLabel = '';

    if (!desktopFound && !cliFound) {
      primaryFinding = 'Docker Desktop Not Installed';
      summary = 'Docker Desktop was not found on this computer. Altr Stream requires Docker Desktop to execute its containerized local node.';
      action = RecommendedActionType.installDocker;
      actionLabel = 'Install Docker Desktop';
    } else if (!daemonReady && daemonPaused) {
      primaryFinding = 'Docker Desktop Paused';
      summary = 'Docker Desktop is currently paused. Resume Docker Desktop to restore container services.';
      action = RecommendedActionType.resumeDocker;
      actionLabel = 'Resume Docker Desktop';
    } else if (!daemonReady) {
      primaryFinding = 'Docker Desktop Stopped';
      summary = 'Docker Desktop is installed but the Docker daemon is not running. Start Docker Desktop to allow Altr Stream to run.';
      action = RecommendedActionType.startDocker;
      actionLabel = 'Start Docker Desktop';
    } else if (!portAvailable) {
      primaryFinding = 'Port 8000 Conflict';
      summary = 'Port 8000 is occupied by an external application on your system. Free port 8000 to enable Altr Stream.';
      action = RecommendedActionType.none;
      actionLabel = '';
    } else if (hasConfig && !checks.any((c) => c.title == 'Altr Stream Container State' && c.status == DiagnosticStatus.passed)) {
      primaryFinding = 'Altr Stream Container Stopped';
      summary = 'Docker daemon is ready, but the Altr Stream container is not currently active.';
      action = RecommendedActionType.startNode;
      actionLabel = 'Start Altr Stream';
    }

    sw.stop();
    logEvent(
      'Diagnostics',
      'Diagnostic sweep completed in ${sw.elapsedMilliseconds}ms. Primary finding: $primaryFinding (Action: $actionLabel)',
      level: 'INFO',
    );

    return DiagnosticReport(
      checks: checks,
      primaryFinding: primaryFinding,
      summaryExplanation: summary,
      recommendedAction: action,
      recommendedActionLabel: actionLabel,
      timestamp: DateTime.now(),
    );
  }

  @override
  Future<List<NodeVersion>> getAvailableVersions() async {
    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
      final request = await client.getUrl(
        Uri.parse('https://api.github.com/repos/HelloAltr/Altr-Stream/releases'),
      );
      request.headers.set('User-Agent', 'Altr-Stream-Manager');
      final response = await request.close();
      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        final list = jsonDecode(body) as List<dynamic>;
        final versions = <NodeVersion>[];
        for (final item in list) {
          if (item is Map<String, dynamic>) {
            // Strictly exclude unreleased drafts
            if (item['draft'] == true) continue;
            final tag = (item['tag_name'] as String? ?? '').replaceFirst('v', '').trim();
            if (tag.isNotEmpty) {
              versions.add(NodeVersion(
                version: tag,
                isRecommended: versions.isEmpty,
                isCurrent: versions.isEmpty,
              ));
            }
          }
        }
        if (versions.isNotEmpty) return versions;
      }
    } catch (_) {
      // Offline fallback
    }

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
    final status = await getStatus();
    return status.activeVersion;
  }

  @override
  Future<bool> startDockerDesktop() async {
    logEvent('Docker', 'Initiating Docker Desktop launch...');
    try {
      final binary = resolveEngineBinary();
      if (binary == null) {
        _lastEngineError = 'Native engine binary not found on host.';
        logEvent('Docker', 'Engine binary not found', level: 'ERROR');
        return false;
      }
      final launchRes = await _commandRunner(binary, ['launch-docker']);
      if (launchRes.exitCode != 0) {
        final err = launchRes.stderr.toString().trim();
        _lastEngineError = 'Failed to dispatch launch-docker: $err';
        logEvent('Docker', 'Failed to dispatch launch-docker: $err', level: 'ERROR');
        return false;
      }

      // Wait for Docker daemon readiness (bounded timeout with diagnostic recording)
      final waitRes = await _commandRunner(binary, ['wait-docker', '--timeout', '60', '--json']);
      if (waitRes.exitCode == 0) {
        _lastEngineError = null;
        logEvent('Docker', 'Docker daemon is ready', level: 'SUCCESS');
        return true;
      } else {
        final err = waitRes.stderr.toString().trim().isNotEmpty
            ? waitRes.stderr.toString().trim()
            : waitRes.stdout.toString().trim();
        _lastEngineError = 'Docker Desktop was launched, but the Docker daemon did not become ready within 60s: $err';
        logEvent('Docker', 'Docker daemon did not become ready within 60s: $err', level: 'ERROR');
        return false;
      }
    } catch (e) {
      _lastEngineError = 'Error starting Docker Desktop: $e';
      logEvent('Docker', 'Exception during Docker Desktop launch: $e', level: 'ERROR');
      debugPrint('[EngineBackendService] startDockerDesktop error: $e');
      return false;
    }
  }

  @override
  Future<bool> resumeDockerDesktop() async {
    logEvent('Docker', 'Initiating Docker Desktop resume (unpause)...');
    try {
      final binary = resolveEngineBinary();
      if (binary == null) {
        _lastEngineError = 'Native engine binary not found on host.';
        logEvent('Docker', 'Engine binary not found', level: 'ERROR');
        return false;
      }
      final unpauseRes = await _commandRunner(binary, ['unpause-docker-desktop']);
      if (unpauseRes.exitCode != 0) {
        final err = unpauseRes.stderr.toString().trim();
        _lastEngineError = 'Failed to dispatch unpause-docker-desktop: $err';
        logEvent('Docker', 'Failed to dispatch unpause-docker-desktop: $err', level: 'ERROR');
        return false;
      }

      final waitRes = await _commandRunner(binary, ['wait-docker', '--timeout', '30', '--json']);
      if (waitRes.exitCode == 0) {
        _lastEngineError = null;
        logEvent('Docker', 'Docker daemon resumed and ready', level: 'SUCCESS');
        return true;
      } else {
        final err = waitRes.stderr.toString().trim().isNotEmpty
            ? waitRes.stderr.toString().trim()
            : waitRes.stdout.toString().trim();
        _lastEngineError = 'Docker Desktop unpause sent, but the Docker daemon did not become ready within 30s: $err';
        logEvent('Docker', 'Docker daemon did not become ready after resume: $err', level: 'ERROR');
        return false;
      }
    } catch (e) {
      _lastEngineError = 'Error resuming Docker Desktop: $e';
      logEvent('Docker', 'Exception during Docker Desktop resume: $e', level: 'ERROR');
      debugPrint('[EngineBackendService] resumeDockerDesktop error: $e');
      return false;
    }
  }

  @override
  Future<bool> startNode() async {
    logEvent('Node', 'Starting Altr Stream container...');
    try {
      final binary = resolveEngineBinary();
      if (binary == null) {
        logEvent('Node', 'Engine binary not found', level: 'ERROR');
        return false;
      }
      final res = await _commandRunner(binary, ['start-container']);
      if (res.exitCode == 0) {
        logEvent('Node', 'Altr Stream container started successfully', level: 'SUCCESS');
        return true;
      } else {
        final err = res.stderr.toString().trim();
        logEvent('Node', 'Failed to start container: $err', level: 'ERROR');
        return false;
      }
    } catch (e) {
      logEvent('Node', 'Exception starting container: $e', level: 'ERROR');
      debugPrint('[EngineBackendService] startNode error: $e');
      return false;
    }
  }

  @override
  Future<bool> stopNode() async {
    logEvent('Node', 'Stopping Altr Stream container...');
    try {
      final binary = resolveEngineBinary();
      if (binary == null) {
        logEvent('Node', 'Engine binary not found', level: 'ERROR');
        return false;
      }
      final res = await _commandRunner(binary, ['stop-container', '--name', 'altr-stream']);
      if (res.exitCode == 0) {
        logEvent('Node', 'Altr Stream container stopped successfully', level: 'SUCCESS');
        return true;
      } else {
        final err = res.stderr.toString().trim();
        logEvent('Node', 'Failed to stop container: $err', level: 'ERROR');
        return false;
      }
    } catch (e) {
      logEvent('Node', 'Exception stopping container: $e', level: 'ERROR');
      debugPrint('[EngineBackendService] stopNode error: $e');
      return false;
    }
  }

  @override
  Future<bool> pauseNode() async {
    logEvent('Node', 'Pausing Altr Stream container...');
    try {
      final binary = resolveEngineBinary();
      if (binary == null) {
        logEvent('Node', 'Engine binary not found', level: 'ERROR');
        return false;
      }
      final res = await _commandRunner(binary, ['pause-container', '--name', 'altr-stream']);
      if (res.exitCode == 0) {
        logEvent('Node', 'Altr Stream container paused successfully', level: 'SUCCESS');
        return true;
      } else {
        final err = res.stderr.toString().trim();
        logEvent('Node', 'Failed to pause container: $err', level: 'ERROR');
        return false;
      }
    } catch (e) {
      logEvent('Node', 'Exception pausing container: $e', level: 'ERROR');
      debugPrint('[EngineBackendService] pauseNode error: $e');
      return false;
    }
  }

  @override
  Future<bool> resumeNode() async {
    logEvent('Node', 'Resuming Altr Stream container...');
    try {
      final binary = resolveEngineBinary();
      if (binary == null) {
        logEvent('Node', 'Engine binary not found', level: 'ERROR');
        return false;
      }
      final res = await _commandRunner(binary, ['unpause-container', '--name', 'altr-stream']);
      if (res.exitCode == 0) {
        logEvent('Node', 'Altr Stream container resumed successfully', level: 'SUCCESS');
        return true;
      } else {
        final err = res.stderr.toString().trim();
        logEvent('Node', 'Failed to resume container: $err', level: 'ERROR');
        return false;
      }
    } catch (e) {
      logEvent('Node', 'Exception resuming container: $e', level: 'ERROR');
      debugPrint('[EngineBackendService] resumeNode error: $e');
      return false;
    }
  }

  @override
  Stream<InstallProgress> installNode(String version, {String? customImage}) async* {
    yield* _streamOperation([
      'install',
      '--version',
      version,
      '--replace-existing',
      if (customImage != null) ...['--image', customImage],
    ]);
  }

  @override
  Stream<InstallProgress> updateNodeVersion(String version) async* {
    yield* _streamOperation(['switch-version', '--version', version]);
  }

  @override
  Stream<InstallProgress> repairNode() async* {
    yield* _streamOperation(['repair']);
  }

  Stream<InstallProgress> _streamOperation(List<String> baseArgs) async* {
    final binary = resolveEngineBinary();
    if (binary == null) {
      final err = 'altr-installer-engine executable not found.';
      logEvent('Lifecycle', err, level: 'ERROR');
      yield InstallProgress.failed(err);
      return;
    }

    final args = List<String>.from(baseArgs);
    if (_effectiveInstallDir.isNotEmpty) {
      args.addAll(['--target-dir', _effectiveInstallDir]);
    }
    args.add('--json');

    logEvent('Lifecycle', 'Executing command: ${args.join(" ")}');
    final initial = InstallProgress.initial();
    logEvent('Lifecycle', '${initial.stage}: ${initial.message}');
    yield initial;

    final process = await Process.start(binary, args);
    final lines = process.stdout.transform(utf8.decoder).transform(const LineSplitter());

    await for (final line in lines) {
      final parsed = InstallProgress.tryParseLine(line);
      if (parsed != null) {
        logEvent('Lifecycle', '${parsed.stage}: ${parsed.message} (${parsed.percent}%)');
        yield parsed;
      } else {
        try {
          final json = jsonDecode(line) as Map<String, dynamic>;
          final prog = InstallProgress.fromJson(json);
          logEvent('Lifecycle', '${prog.stage}: ${prog.message} (${prog.percent}%)');
          yield prog;
        } catch (_) {
          final fallback = InstallProgress(
            stage: 'Processing',
            stageIndex: 1,
            totalStages: 5,
            percent: 50,
            message: line,
          );
          logEvent('Lifecycle', line);
          yield fallback;
        }
      }
    }

    final exitCode = await process.exitCode;
    if (exitCode != 0) {
      final err = await process.stderr.transform(utf8.decoder).join();
      final errSummary = 'Operation failed with code $exitCode: ${err.trim().isNotEmpty ? err.trim() : "Unknown error"}';
      logEvent('Lifecycle', errSummary, level: 'ERROR');
      yield InstallProgress.failed(errSummary);
    } else {
      logEvent('Lifecycle', 'Operation completed successfully.', level: 'SUCCESS');
      yield InstallProgress.completed();
    }
  }

  @override
  Future<bool> uninstallNode({bool deleteData = false}) async {
    logEvent('Lifecycle', 'Uninstall requested (deleteData: $deleteData)');
    final args = ['uninstall'];
    if (_effectiveInstallDir.isNotEmpty) {
      args.addAll(['--target-dir', _effectiveInstallDir]);
    }
    if (deleteData) {
      args.add('--delete-data');
    }
    final res = await _runEngineJson(args);
    final success = res['success'] as bool? ?? true;
    if (success) {
      logEvent('Lifecycle', 'Altr Stream node uninstalled successfully', level: 'SUCCESS');
    } else {
      logEvent('Lifecycle', 'Uninstall failed: ${res["error"] ?? "unknown error"}', level: 'ERROR');
    }
    return success;
  }

  @override
  Future<String> changeInstallationPath(String newPath) async {
    String resolvedPath = newPath.trim();
    if (resolvedPath.startsWith('~/')) {
      final home = Platform.environment['HOME'] ?? '';
      resolvedPath = '$home/${resolvedPath.substring(2)}';
    }
    _effectiveInstallDir = resolvedPath;
    logEvent('Config', 'Changed target installation path to $resolvedPath');
    try {
      await _runEngineJson(['provision-config', '--target-dir', resolvedPath]);
    } catch (e) {
      logEvent('Config', 'provision-config error: $e', level: 'ERROR');
      debugPrint('[EngineBackendService] provision-config error: $e');
    }
    return _effectiveInstallDir;
  }

  @override
  Future<void> openWebInterface() async {
    final uri = Uri.parse(AppConstants.defaultLocalWebUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  @override
  Future<void> openInstallationDirectory() async {
    final home = Platform.environment['HOME'] ?? '';
    final dir = _effectiveInstallDir.isNotEmpty ? _effectiveInstallDir : '$home/.altr-stream';
    final target = Directory(dir);
    if (!target.existsSync()) {
      target.createSync(recursive: true);
    }
    if (Platform.isMacOS) {
      await Process.run('open', [dir]);
    } else if (Platform.isWindows) {
      await Process.run('explorer.exe', [dir]);
    }
  }

  /// Filters repetitive successful health check lines from container logs.
  /// Any errors, failures, non-200 responses, or lifecycle transitions are strictly preserved.
  static String filterContainerLogs(String logs) {
    if (logs.isEmpty) return logs;
    final lines = logs.split('\n');
    final result = <String>[];
    int consecutiveHealthChecks = 0;
    String? sampleHealthCheck;

    void flushHealthChecks() {
      if (consecutiveHealthChecks > 0) {
        if (consecutiveHealthChecks == 1 && sampleHealthCheck != null) {
          result.add(sampleHealthCheck!);
        } else {
          result.add('... [$consecutiveHealthChecks successful GET /api/v1/health (200 OK) checks collapsed - switch to Raw Logs to view all] ...');
        }
        consecutiveHealthChecks = 0;
        sampleHealthCheck = null;
      }
    }

    final healthRegex = RegExp(r'GET\s+.*\/health.*200(\s+OK)?', caseSensitive: false);

    for (final line in lines) {
      final isHealthCheck200 = healthRegex.hasMatch(line) &&
          !line.toLowerCase().contains('error') &&
          !line.toLowerCase().contains('fail') &&
          !line.contains(' 500') &&
          !line.contains(' 502') &&
          !line.contains(' 503');
      if (isHealthCheck200) {
        consecutiveHealthChecks++;
        sampleHealthCheck = line;
      } else {
        flushHealthChecks();
        result.add(line);
      }
    }
    flushHealthChecks();
    return result.join('\n');
  }

  @override
  Future<String> getInstallationLogs({bool forceRefresh = false, bool raw = false}) async {
    final now = DateTime.now();
    if (!forceRefresh && _cachedLogs != null && _lastLogsFetchTime != null) {
      if (now.difference(_lastLogsFetchTime!).inSeconds < 3) {
        return _cachedLogs!;
      }
    }

    final home = Platform.environment['HOME'] ?? '';
    final dir = _effectiveInstallDir.isNotEmpty ? _effectiveInstallDir : '$home/.altr-stream';
    final StringBuffer logBuffer = StringBuffer();

    // 1. Manager Diagnostics & Operational Events (Application Owned, Clearable)
    logBuffer.writeln('=== Manager Diagnostics & Operation Events (Session Activity & Installation Events) ===');
    if (_sessionLogs.isNotEmpty) {
      for (final entry in _sessionLogs) {
        logBuffer.writeln(entry);
      }
    } else {
      logBuffer.writeln('No operations logged in current session.');
    }
    logBuffer.writeln();

    // 2. Persistent file logs (Application Owned, Clearable, bounded to recent lines)
    final candidates = [
      '$dir/install.log',
      '$dir/supervisor.log',
      '$dir/altr-stream.log',
      '$dir/.docker_pull.log',
      '/tmp/altr-installer.log',
    ];

    bool hasPersistentLogs = false;
    for (final path in candidates) {
      final file = File(path);
      if (file.existsSync()) {
        try {
          final content = await file.readAsString();
          final trimmed = content.trim();
          if (trimmed.isNotEmpty) {
            hasPersistentLogs = true;
            final lines = trimmed.split('\n');
            final bounded = lines.length > 100 ? lines.sublist(lines.length - 100).join('\n') : trimmed;
            logBuffer.writeln('=== Persistent Installation Log: $path (Application Owned) ===\n$bounded\n');
          }
        } catch (_) {}
      }
    }
    if (!hasPersistentLogs) {
      logBuffer.writeln('=== Persistent Installation Logs (Application Owned) ===\nNo persistent log files found.\n');
    }

    // 3. Container Logs with strict 2.5-second timeout (Docker Engine Managed - Not cleared by app Clear Logs)
    logBuffer.writeln('=== Container Logs (Docker Engine Managed - External) ===');
    logBuffer.writeln('# Note: Container logs are managed externally by Docker Engine.');
    logBuffer.writeln('# Application "Clear Logs" filters prior entries using timestamps and does not wipe host docker daemon logs.');
    try {
      final dockerCli = Platform.isWindows ? 'docker.exe' : 'docker';
      final logArgs = ['logs', '--tail', '50'];
      if (_lastLogsClearedTime != null) {
        logArgs.addAll(['--since', _lastLogsClearedTime!.toUtc().toIso8601String()]);
      }
      logArgs.add('altr-stream');

      final res = await _commandRunner(
        dockerCli,
        logArgs,
      ).timeout(const Duration(milliseconds: 2500));

      if (res.exitCode == 0) {
        final out = res.stdout.toString().trim();
        final err = res.stderr.toString().trim();
        final combined = '$out\n$err'.trim();
        if (combined.isNotEmpty) {
          final output = raw ? combined : filterContainerLogs(combined);
          logBuffer.writeln(output);
        } else {
          logBuffer.writeln('No recent container logs since last clear.');
        }
      } else {
        logBuffer.writeln('Container altr-stream is not running or has no logs available.');
      }
    } catch (_) {
      logBuffer.writeln('Could not retrieve container logs (Docker daemon connection timed out or offline).');
    }
    logBuffer.writeln();

    // 4. Diagnostics & Last Engine Errors
    if (_lastEngineError != null && _lastEngineError!.isNotEmpty) {
      logBuffer.writeln('=== Native Engine Diagnostics ===');
      logBuffer.writeln('Binary: ${resolveEngineBinary() ?? "NOT FOUND"}');
      logBuffer.writeln('Error: $_lastEngineError\n');
    }

    _cachedLogs = logBuffer.toString().trim();
    _lastLogsFetchTime = now;
    return _cachedLogs!;
  }

  @override
  Future<void> clearLogs() async {
    // Clear application-owned in-memory session logs and caches
    _sessionLogs.clear();
    _cachedLogs = null;
    _lastLogsFetchTime = null;
    _lastEngineError = null;
    // Set timestamp cutoff so external Docker container logs before this moment are filtered out
    _lastLogsClearedTime = DateTime.now();

    final home = Platform.environment['HOME'] ?? '';
    final dir = _effectiveInstallDir.isNotEmpty ? _effectiveInstallDir : '$home/.altr-stream';
    final candidates = [
      '$dir/install.log',
      '$dir/supervisor.log',
      '$dir/altr-stream.log',
      '$dir/.docker_pull.log',
      '/tmp/altr-installer.log',
    ];
    for (final path in candidates) {
      try {
        final file = File(path);
        if (file.existsSync()) {
          await file.writeAsString('');
        }
      } catch (_) {}
    }
  }
}
