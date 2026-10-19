import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons_pro/hugeicons.dart';
import 'package:url_launcher/url_launcher.dart';

import 'models/diagnostic_report.dart';
import 'models/install_progress.dart';
import 'models/node_title_status.dart';

import 'services/backend_service.dart';
import 'services/directory_picker_service.dart';
import 'services/engine_backend_service.dart';
import 'services/mock_backend_service.dart';
import 'themes/theme.dart';
import 'themes/util.dart';

// =============================================================================
// ALTR STREAM MANAGER — FLUTTER DESKTOP UI IMPLEMENTATION CHECKLIST
// =============================================================================
//
// -----------------------------------------------------------------------------
// A. Window and application design
// -----------------------------------------------------------------------------
// [x] Design the Altr Stream Manager desktop interface.
// [x] Support both macOS and Windows.
// [x] Maintain consistent interior layouts, spacing, typography, colors, and
//     component dimensions across platforms.
// [x] Preserve native window controls where practical.
// [x] Establish reusable design constants for colors, typography, spacing,
//     border radii, and button heights (see lib/config/theme.dart).
// [x] Use a dark navy/charcoal theme with blue accents.
// [x] Use subtle borders, restrained shadows, and rounded panels.
// [x] Ensure the layout remains usable when the window is resized.
//
// -----------------------------------------------------------------------------
// B. Application header
// -----------------------------------------------------------------------------
// [x] Display the Altr Stream server-style icon.
// [x] Display the title "Altr Stream".
// [x] Display the subtitle "Local Node Manager".
// [x] Add a refresh button to recheck the application and Docker status.
// [x] Provide appropriate hover, focus, and loading states.
//
// -----------------------------------------------------------------------------
// C. Status and configuration panel
// Build a four-row panel with consistent row heights and subtle horizontal dividers.
// -----------------------------------------------------------------------------
// Row 1: Docker Desktop
// [x] Display a status indicator.
// [x] Display the label "Docker Desktop Status".
// [x] Display a right-aligned status.
// [x] Support "Ready", "Stopped", "Paused", "Starting", and "Unknown" states.
//
// Row 2: Altr Stream Node
// [x] Display a status indicator.
// [x] Display the label "Altr Stream Node Status".
// [x] Display a right-aligned status.
// [x] Support "Running", "Stopped", "Installing...", "Not Installed", and error states.
//
// Row 3: Altr Stream Node Version
// [x] Display the label "Altr Stream Node Version".
// [x] Display the installed version when available.
// [x] Provide a version-selection dropdown.
//
// Row 4: Data & Runtime
// [x] Display the current installation/data directory.
// [x] Add a "Change Installation Path" button.
// [x] Add a platform-appropriate "Reveal in Finder" button.
//
// -----------------------------------------------------------------------------
// D. Main status section
// -----------------------------------------------------------------------------
// [x] Running state, Docker stopped/paused states, Not installed state.
// [x] Linear progress indicator during active installation/updates/repairs.
//
// -----------------------------------------------------------------------------
// E. Main action buttons & F. Footer
// -----------------------------------------------------------------------------
// [x] Wired to live backend actions.
// =============================================================================

/// Global backend service reference.
///
/// Real mode is the strict default. [EngineBackendService] connects to the
/// real Go installer engine and host Docker daemon.
/// [MockBackendService] is ONLY used when explicitly requested via
/// `--dart-define=ALTR_MOCK=true` or the `ALTR_MOCK=true` environment variable.
BackendService backendService = initBackendService();

/// Initializes the backend service.
///
/// Returns [MockBackendService] ONLY when explicitly requested.
/// In all other cases, returns [EngineBackendService].
BackendService initBackendService({bool? forceMock}) {
  final explicitMock = forceMock ?? isMockModeEnabled();
  if (explicitMock) {
    debugPrint('[AltrStreamManager] Explicit mock mode active. Using MockBackendService.');
    return MockBackendService(currentScenario: MockScenario.running);
  }

  final engine = EngineBackendService();
  final path = engine.resolveEngineBinary();
  if (path != null) {
    debugPrint('[AltrStreamManager] Connected to real native engine at: $path');
  } else {
    debugPrint('[AltrStreamManager] Native engine binary not located on host. Real mode active — error states will be surfaced.');
  }
  return engine;
}

/// Returns true only if mock mode was explicitly enabled via compile-time define or env variable.
bool isMockModeEnabled() {
  const dartDefine = String.fromEnvironment('ALTR_MOCK', defaultValue: '');
  if (dartDefine.toLowerCase() == 'true' || dartDefine == '1') {
    return true;
  }
  final env = Platform.environment['ALTR_MOCK']?.toLowerCase();
  if (env == 'true' || env == '1') {
    return true;
  }
  return false;
}

// Helper aliases to maintain exact function signatures for build helpers
final _buildAltrNodeTitleStatusIcon = buildAltrNodeTitleStatusIcon;
final _buildAltrNodeTitleStatusText = buildAltrNodeTitleStatusText;
final _buildAltrNodeSubtitleStatusText = buildAltrNodeSubtitleStatusText;
final _buildDockerStatusText = buildDockerStatusText;
final _buildAltrNodeStatusText = buildAltrNodeStatusText;
final _buildAltrNodeTitleStatusColor = buildAltrNodeTitleStatusColor;
final _buildDockerStatusColor = buildDockerStatusColor;
final _buildAltrNodeStatusColor = buildAltrNodeStatusColor;

/// Standard uniform dialog width across all Altr Stream Manager dialogs,
/// matching the version change confirmation dialog.
const double kDialogStandardWidth = 360.0;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AltrStreamManagerApp());
}

/// Root application shell providing the dark theme foundation.
class AltrStreamManagerApp extends StatelessWidget {
  const AltrStreamManagerApp({super.key});

  @override
  Widget build(BuildContext context) {
    TextTheme textTheme = createTextTheme(context, "Nunito Sans", "Nunito");
    MaterialTheme theme = MaterialTheme(textTheme);

    return MaterialApp(
      title: 'Altr Stream Manager',
      debugShowCheckedModeBanner: false,
      theme: theme.light(),
      darkTheme: theme.dark(),
      home: const AltrStreamManagerPlaceholder(),
    );
  }
}

class AltrStreamManagerPlaceholder extends StatefulWidget {
  const AltrStreamManagerPlaceholder({super.key});

  @override
  State<AltrStreamManagerPlaceholder> createState() => _AltrStreamManagerPlaceholderState();
}

class _AltrStreamManagerPlaceholderState extends State<AltrStreamManagerPlaceholder> {
  // Live state variables wired to backend service
  NodeTitleStatus _titleStatus = NodeTitleStatus.discovering;
  String _altrNodeVersion = "1.0.0-beta";
  List<String> _versionDropdownOptions = [
    "1.0.0-beta",
    "0.13.7-alpha",
  ];
  String _altrNodeInstallationPath = '${Platform.environment['HOME'] ?? ''}/.altr-stream';
  String _dashboardAddress = "http://localhost:8000";
  double? _progressValue;
  int? _progressPercent;
  String _progressMessage = 'Checking System Status...';
  StreamSubscription<InstallProgress>? _progressSub;
  bool _isOperationActive = false;
  int _statusRequestId = 0;
  bool _isRefreshing = false;
  bool _pendingRefresh = false;
  Timer? _statusTimer;
  NodeStatus? _currentStatus;

  @override
  void initState() {
    super.initState();
    _refreshStatus();
    _fetchAvailableVersions();
    _statusTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!_isOperationActive && mounted) {
        _refreshStatus();
      }
    });
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    _progressSub?.cancel();
    super.dispose();
  }

  Future<void> _fetchAvailableVersions() async {
    try {
      final versions = await backendService.getAvailableVersions();
      if (!mounted) return;
      if (versions.isNotEmpty) {
        setState(() {
          // Strictly populate selectable dropdown with eligible published versions
          _versionDropdownOptions = versions.map((v) => v.version).toList();
        });
      }
    } catch (e) {
      debugPrint('[AltrStreamManager] Error fetching available versions: $e');
    }
  }

  Future<void> _manualRefresh() async {
    _fetchAvailableVersions();
    await _refreshStatus();
  }

  Future<void> _refreshStatus() async {
    if (_isRefreshing) {
      _pendingRefresh = true;
      return;
    }
    _isRefreshing = true;
    final currentRequestId = ++_statusRequestId;

    try {
      final status = await backendService.getStatus();
      if (!mounted || currentRequestId != _statusRequestId) return;

      setState(() {
        _currentStatus = status;
        if (!_isOperationActive) {
          _titleStatus = NodeTitleStatus.fromNodeStatus(status);
        }
        if (status.installDir.isNotEmpty) {
          _altrNodeInstallationPath = status.installDir;
        }
        if (status.webUrl.isNotEmpty) {
          _dashboardAddress = status.webUrl;
        }
        if (status.activeVersion != null && status.activeVersion!.isNotEmpty) {
          _altrNodeVersion = status.activeVersion!;
        } else if (status.targetVersion.isNotEmpty) {
          _altrNodeVersion = status.targetVersion;
        }
      });
    } catch (e) {
      debugPrint('[AltrStreamManager] Error fetching status: $e');
      if (mounted && !_isOperationActive && currentRequestId == _statusRequestId) {
        setState(() {
          _titleStatus = NodeTitleStatus.dockerError;
        });
      }
    } finally {
      _isRefreshing = false;
      if (_pendingRefresh && mounted && !_isOperationActive) {
        _pendingRefresh = false;
        _refreshStatus();
      }
    }
  }

  void _listenToProgress(
    Stream<InstallProgress> stream, {
    required NodeTitleStatus failureStatus,
    required VoidCallback onComplete,
  }) {
    _progressSub?.cancel();
    setState(() {
      _isOperationActive = true;
      _progressValue = 0.0;
      _progressPercent = 0;
      _progressMessage = 'Starting operation...';
    });

    _progressSub = stream.listen(
      (progress) {
        if (!mounted) return;
        setState(() {
          _progressPercent = progress.percent > 0 ? progress.percent : null;
          _progressValue = progress.percent > 0 ? (progress.percent / 100.0).clamp(0.0, 1.0) : null;
          _progressMessage = progress.message.isNotEmpty ? progress.message : progress.stage;
        });
      },
      onError: (err) {
        if (!mounted) return;
        setState(() {
          _isOperationActive = false;
          _titleStatus = failureStatus;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Operation failed: $err')),
        );
      },
      onDone: () {
        if (!mounted) return;
        setState(() {
          _isOperationActive = false;
        });
        onComplete();
      },
    );
  }

  void _installNode(String version) {
    setState(() {
      _altrNodeVersion = version;
      _titleStatus = NodeTitleStatus.nodeInstalling;
    });
    _listenToProgress(
      backendService.installNode(version),
      failureStatus: NodeTitleStatus.nodeFailed,
      onComplete: () {
        _refreshStatus();
      },
    );
  }

  void _updateNodeVersion(String version) {
    setState(() {
      _altrNodeVersion = version;
      _titleStatus = NodeTitleStatus.nodeUpdating;
    });
    _listenToProgress(
      backendService.updateNodeVersion(version),
      failureStatus: NodeTitleStatus.nodeUpdateFailed,
      onComplete: () {
        _refreshStatus();
      },
    );
  }

  Future<void> _onVersionSelected(String newVersion) async {
    final isUninstalled = _titleStatus == NodeTitleStatus.nodeNotInstalled;
    if (newVersion == _altrNodeVersion && !isUninstalled) return;

    final dialogTitle = isUninstalled && newVersion == _altrNodeVersion
        ? 'Install Node Version'
        : 'Change Node Version';
    final dialogMessage = isUninstalled && newVersion == _altrNodeVersion
        ? 'Are you sure you want to install Altr Stream Node version $newVersion?'
        : 'Are you sure you want to change the Altr Stream Node version from $_altrNodeVersion to $newVersion?';
    final confirmActionText = isUninstalled && newVersion == _altrNodeVersion
        ? 'Install'
        : 'Change Version';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(dialogTitle),
        content: SizedBox(
          width: kDialogStandardWidth,
          child: Text(dialogMessage),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(confirmActionText),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      if (_titleStatus == NodeTitleStatus.nodeNotInstalled) {
        _installNode(newVersion);
      } else {
        _updateNodeVersion(newVersion);
      }
    }
  }


  Future<void> _uninstallNode() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Uninstall Altr Stream'),
        content: const SizedBox(
          width: kDialogStandardWidth,
          child: Text(
            'Are you sure you want to stop and remove the Altr Stream node container? Persistent storage will be preserved.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            child: const Text('Uninstall'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() {
        _titleStatus = NodeTitleStatus.nodeUninstalling;
        _isOperationActive = true;
        _progressValue = 0.5;
      });
      try {
        await backendService.uninstallNode(deleteData: false);
      } catch (e) {
        debugPrint('[AltrStreamManager] Uninstall error: $e');
      } finally {
        if (mounted) {
          setState(() {
            _isOperationActive = false;
          });
          _refreshStatus();
        }
      }
    }
  }

  Future<void> _changeInstallationPath() async {
    final picked = await DirectoryPickerService.pickDirectory(
      initialDirectory: _altrNodeInstallationPath,
    );
    if (picked == null || picked.isEmpty || picked == _altrNodeInstallationPath) {
      return;
    }

    final validationErr = await DirectoryPickerService.validateDirectory(picked);
    if (validationErr != null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(validationErr),
            backgroundColor: Colors.red.shade800,
            duration: const Duration(seconds: 5),
          ),
        );
      }
      return;
    }

    if (_titleStatus.nodeState == NodeState.running) {
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Change Target Directory?'),
          content: SizedBox(
            width: kDialogStandardWidth,
            child: Text(
              'Altr Stream is currently active. Changing the installation path to "$picked" sets the target configuration directory without deleting or moving existing container data. Continue?',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Change Path'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    try {
      final updated = await backendService.changeInstallationPath(picked);
      if (mounted) {
        setState(() {
          _altrNodeInstallationPath = updated;
        });
        await _refreshStatus();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Installation path updated to: $updated')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update path: $e'),
            backgroundColor: Colors.red.shade800,
          ),
        );
      }
    }
  }

  Future<void> _openInstallationDirectory() async {
    await backendService.openInstallationDirectory();
  }

  Future<void> _openWebInterface() async {
    final uri = Uri.tryParse(_dashboardAddress);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      await backendService.openWebInterface();
    }
  }


  Future<void> _startDocker() async {
    if (_isOperationActive) return;
    setState(() {
      _isOperationActive = true;
      _titleStatus = NodeTitleStatus.dockerStarting;
      _progressValue = null;
      _progressPercent = null;
      _progressMessage = 'Starting Docker Desktop…';
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Starting Docker Desktop, please wait...')),
    );
    bool started = false;
    try {
      started = await backendService.startDockerDesktop();
    } finally {
      if (mounted) {
        setState(() {
          _isOperationActive = false;
        });
        await _refreshStatus();
        if (mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          if (started) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Docker Desktop is ready!'),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 4),
              ),
            );
          } else {
            final errorMsg = backendService is EngineBackendService
                ? (backendService as EngineBackendService).lastEngineError ?? 'Docker Desktop daemon did not become ready within timeout.'
                : 'Docker Desktop daemon did not become ready within timeout.';
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(errorMsg),
                backgroundColor: Colors.red.shade800,
                duration: const Duration(seconds: 6),
              ),
            );
          }
        }
      }
    }
  }

  Future<void> _resumeDocker() async {
    if (_isOperationActive) return;
    setState(() {
      _isOperationActive = true;
      _titleStatus = NodeTitleStatus.dockerStarting;
      _progressValue = null;
      _progressPercent = null;
      _progressMessage = 'Resuming Docker Desktop…';
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Resuming Docker Desktop, please wait...')),
    );
    bool resumed = false;
    try {
      resumed = await backendService.resumeDockerDesktop();
    } finally {
      if (mounted) {
        setState(() {
          _isOperationActive = false;
        });
        await _refreshStatus();
        if (mounted) {
          if (resumed) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Docker Desktop resumed successfully!'),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 4),
              ),
            );
          } else {
            final errorMsg = backendService is EngineBackendService
                ? (backendService as EngineBackendService).lastEngineError ?? 'Docker Desktop could not be resumed.'
                : 'Docker Desktop could not be resumed.';
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(errorMsg),
                backgroundColor: Colors.red.shade800,
                duration: const Duration(seconds: 6),
              ),
            );
          }
        }
      }
    }
  }

  Future<void> _startNode() async {
    if (_isOperationActive) return;
    setState(() {
      _isOperationActive = true;
      _progressValue = null;
      _progressPercent = null;
      _progressMessage = 'Starting Altr Stream container…';
    });
    try {
      final success = await backendService.startNode();
      if (!success) {
        _installNode(_altrNodeVersion);
        return;
      }
    } catch (_) {
      _installNode(_altrNodeVersion);
      return;
    } finally {
      if (mounted) {
        setState(() {
          _isOperationActive = false;
        });
        await _refreshStatus();
      }
    }
  }

  Future<void> _pauseNode() async {
    if (_isOperationActive) return;
    setState(() {
      _isOperationActive = true;
      _progressValue = null;
      _progressPercent = null;
      _progressMessage = 'Pausing Altr Stream container…';
    });
    bool paused = false;
    try {
      paused = await backendService.pauseNode();
    } finally {
      if (mounted) {
        setState(() {
          _isOperationActive = false;
        });
        await _refreshStatus();
        if (mounted) {
          if (paused) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Altr Stream container paused'),
                backgroundColor: Colors.orange,
                duration: Duration(seconds: 3),
              ),
            );
          } else {
            final errorMsg = backendService is EngineBackendService
                ? (backendService as EngineBackendService).lastEngineError ?? 'Failed to pause Altr Stream container.'
                : 'Failed to pause Altr Stream container.';
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(errorMsg),
                backgroundColor: Colors.red.shade800,
                duration: const Duration(seconds: 5),
              ),
            );
          }
        }
      }
    }
  }

  Future<void> _resumeNode() async {
    if (_isOperationActive) return;
    setState(() {
      _isOperationActive = true;
      _progressValue = null;
      _progressPercent = null;
      _progressMessage = 'Resuming Altr Stream container…';
    });
    bool resumed = false;
    try {
      resumed = await backendService.resumeNode();
    } finally {
      if (mounted) {
        setState(() {
          _isOperationActive = false;
        });
        await _refreshStatus();
        if (mounted) {
          if (resumed) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Altr Stream container resumed'),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 3),
              ),
            );
          } else {
            final errorMsg = backendService is EngineBackendService
                ? (backendService as EngineBackendService).lastEngineError ?? 'Failed to resume Altr Stream container.'
                : 'Failed to resume Altr Stream container.';
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(errorMsg),
                backgroundColor: Colors.red.shade800,
                duration: const Duration(seconds: 5),
              ),
            );
          }
        }
      }
    }
  }

  Future<void> _stopNode() async {
    if (_isOperationActive) return;
    setState(() {
      _isOperationActive = true;
      _progressValue = null;
      _progressPercent = null;
      _progressMessage = 'Stopping Altr Stream container…';
    });
    bool stopped = false;
    try {
      stopped = await backendService.stopNode();
    } finally {
      if (mounted) {
        setState(() {
          _isOperationActive = false;
        });
        await _refreshStatus();
        if (mounted) {
          if (stopped) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Altr Stream container stopped'),
                backgroundColor: Colors.blueGrey,
                duration: Duration(seconds: 3),
              ),
            );
          } else {
            final errorMsg = backendService is EngineBackendService
                ? (backendService as EngineBackendService).lastEngineError ?? 'Failed to stop Altr Stream container.'
                : 'Failed to stop Altr Stream container.';
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(errorMsg),
                backgroundColor: Colors.red.shade800,
                duration: const Duration(seconds: 5),
              ),
            );
          }
        }
      }
    }
  }



  Future<void> _installDocker() async {
    final uri = Uri.parse('https://www.docker.com/products/docker-desktop/');
    bool launched = false;
    try {
      if (await canLaunchUrl(uri)) {
        launched = await launchUrl(uri);
      }
    } catch (_) {
      launched = false;
    }

    if (!launched) {
      await Clipboard.setData(const ClipboardData(text: 'https://www.docker.com/products/docker-desktop/'));
      if (mounted) {
        showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Install Docker Desktop'),
            content: SizedBox(
              width: kDialogStandardWidth,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Docker Desktop is required for Altr Stream. The web browser could not be opened automatically.\n\nPlease open the official download link below:',
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: SelectableText(
                      'https://www.docker.com/products/docker-desktop/',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.bold,
                        color: Theme.of(ctx).colorScheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'The link has also been copied to your clipboard.',
                    style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Clipboard.setData(const ClipboardData(text: 'https://www.docker.com/products/docker-desktop/'));
                  Navigator.of(ctx).pop();
                },
                child: const Text('Copy Link Again'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    }
  }

  Future<void> _confirmQuitApp() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Quit Altr Stream Manager?'),
        content: const SizedBox(
          width: kDialogStandardWidth,
          child: Text(
            'Closing the Manager does not stop Docker Desktop or your Altr Stream node. '
            'They will continue running safely in the background.\n\n'
            'Are you sure you want to quit the Manager?',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Quit Manager'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      exit(0);
    }
  }

  void _showTechnicalLogs() {
    showDialog<void>(
      context: context,
      builder: (context) => TechnicalLogsDialog(backendService: backendService),
    );
  }

  void _showDiagnoseAndFix() {
    showDialog<void>(
      context: context,
      builder: (context) => DiagnoseAndFixDialog(
        backendService: backendService,
        onStatusChanged: _refreshStatus,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final brightness = View.of(context).platformDispatcher.platformBrightness;

    // Single master status variable controlling all UI states
    final nodeTitleStatus = _titleStatus;

    // Derived states
    final dockerState = _currentStatus?.dockerDiag.state ?? nodeTitleStatus.dockerState;
    final nodeState = _currentStatus?.nodeState ?? nodeTitleStatus.nodeState;
    final isProgressActive = nodeTitleStatus.isProgressActive || _isOperationActive;

    final altrNodeVersion = _altrNodeVersion;
    final versionDropdownOptions = _versionDropdownOptions;
    final altrNodeInstallationPath = _altrNodeInstallationPath;
    final dashboardAddress = _dashboardAddress;

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Row(
              children: [
                Icon(
                  HugeIconsSolid.database01,
                  size: 56,
                  color: Theme.of(context).colorScheme.primary,
                ),
                SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Altr Stream", style: Theme.of(context).textTheme.headlineSmall),
                    Row(
                      children: [
                        Text(
                          "Local Node Manager",
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: Theme.of(context).colorScheme.outline),
                        ),
                        if (backendService is MockBackendService) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: Colors.amber.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: Colors.amber.withValues(alpha: 0.6),
                                width: 1,
                              ),
                            ),
                            child: const Text(
                              'MOCK',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: Colors.amber,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
                Spacer(),
                IconButton(
                  tooltip: "Refresh Status",
                  onPressed: _manualRefresh,
                  icon: const Icon(HugeIconsStroke.refresh, size: 22,),
                ),
                const SizedBox(width: 4),
                IconButton(
                  tooltip: "Quit Manager",
                  onPressed: _confirmQuitApp,
                  icon: const Icon(HugeIconsStroke.shutDown, size: 24),
                ),
              ],
            ),
            SizedBox(height: 16),
            Container(
              width: MediaQuery.of(context).size.width - 48, // Padding of 24 on each side
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: brightness == Brightness.light
                    ? Theme.of(context).colorScheme.surfaceContainerHighest
                    : Theme.of(context).colorScheme.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  TableRow(
                    icon: HugeIconsSolid.circle,
                    iconColor: _buildDockerStatusColor(dockerState, context),
                    rowLabel: "Docker Desktop Status",
                    rowValueColor: _buildDockerStatusColor(dockerState, context),
                    rowValue: _buildDockerStatusText(dockerState, context),
                  ),
                  TableDivider(height: 8),
                  TableRow(
                    icon: HugeIconsSolid.circle,
                    iconColor: _buildAltrNodeStatusColor(nodeState, context),
                    rowLabel: "Altr Stream Node Status",
                    rowValue: _buildAltrNodeStatusText(nodeState, context),
                    rowValueColor: _buildAltrNodeStatusColor(nodeState, context),
                  ),
                  TableDivider(height: 8),
                  TableRow(
                    icon: HugeIconsStroke.database01,
                    iconColor: Theme.of(context).colorScheme.onSurface,
                    rowLabel: "Altr Stream Node Version",
                    rowValueColor: _buildAltrNodeStatusColor(nodeState, context),
                    rowValue: altrNodeVersion,
                    controls: Container(
                      height: 36,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: brightness == Brightness.light
                            ? Theme.of(context).colorScheme.surfaceContainerLowest
                            : Theme.of(context).colorScheme.surfaceContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: null,
                          hint: Text(
                            "Change version",
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context).colorScheme.onSurface,
                              fontWeight: FontWeight.normal,
                            ),
                          ),
                          icon: Icon(
                            Icons.arrow_drop_down,
                            size: 20,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                          isDense: true,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).colorScheme.onSurface,
                            fontWeight: FontWeight.normal,
                          ),
                          dropdownColor: brightness == Brightness.light
                              ? Theme.of(context).colorScheme.surfaceContainerLowest
                              : Theme.of(context).colorScheme.surfaceContainer,
                          items: versionDropdownOptions.map((option) {
                            final isUninstalled = nodeState == NodeState.notInstalled ||
                                nodeTitleStatus == NodeTitleStatus.nodeNotInstalled;
                            final isCurrent = !isUninstalled && (option == altrNodeVersion);
                            return DropdownMenuItem<String>(
                              value: option,
                              enabled: !isCurrent,
                              child: Text(
                                isCurrent
                                    ? (nodeState == NodeState.running
                                        ? "$option (Running)"
                                        : "$option (Current)")
                                    : option,
                                style: isCurrent
                                    ? TextStyle(color: Theme.of(context).colorScheme.outline)
                                    : null,
                              ),
                            );
                          }).toList(),
                          onChanged: (value) {
                            if (value != null) {
                              _onVersionSelected(value);
                            }
                          },
                        ),
                      ),
                    ),
                  ),
                  TableDivider(height: 8),
                  TableRow(
                    icon: HugeIconsStroke.folder01,
                    iconColor: Theme.of(context).colorScheme.onSurface,
                    rowLabel: "Data & Runtime Path",
                    rowValueColor: Theme.of(context).colorScheme.onSurface,
                    rowValue: altrNodeInstallationPath,
                    controls: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AltrButton(
                          label: "Change Installation Path",
                          icon: Icon(HugeIconsStroke.folder02, size: 18),
                          onPressed: _changeInstallationPath,
                        ),
                        const SizedBox(width: 8),
                        AltrButton(label: "Reveal in Finder", onPressed: _openInstallationDirectory),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  _buildAltrNodeTitleStatusIcon(nodeTitleStatus),
                  size: 36,
                  color: _buildAltrNodeTitleStatusColor(nodeTitleStatus, context),
                ),
                SizedBox(width: 12),
                Text(
                  _buildAltrNodeTitleStatusText(nodeTitleStatus, context),
                  style: Theme.of(context).textTheme.headlineMedium
                      ?.copyWith(color: _buildAltrNodeTitleStatusColor(nodeTitleStatus, context)),
                ),
              ],
            ),
            SizedBox(height: 8),
            Text(
              _buildAltrNodeSubtitleStatusText(nodeTitleStatus, dashboardAddress, context),
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            SizedBox(height: 16),
            if (!isProgressActive)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                spacing: 12,
                children: [
                  if (nodeTitleStatus == NodeTitleStatus.dockerNotInstalled)
                    AltrButton(
                      label: "Install Docker Desktop",
                      onPressed: _installDocker,
                      isOutsideContainer: true,
                    ),
                  if (nodeTitleStatus == NodeTitleStatus.dockerStopped)
                    AltrButton(
                      label: "Start Docker Desktop",
                      onPressed: _startDocker,
                      isOutsideContainer: true,
                    ),
                  if (nodeTitleStatus == NodeTitleStatus.dockerPaused)
                    AltrButton(
                      label: "Resume Docker Desktop",
                      onPressed: _resumeDocker,
                      isOutsideContainer: true,
                    ),
                  if (nodeTitleStatus == NodeTitleStatus.nodeRunning)
                    AltrButton(
                      label: "Open Dashboard",
                      onPressed: _openWebInterface,
                      isOutsideContainer: true,
                    ),
                  if (nodeTitleStatus == NodeTitleStatus.nodeRunning)
                    AltrButton(
                      label: "Pause Node",
                      onPressed: _pauseNode,
                      isOutsideContainer: true,
                    ),
                  if (nodeTitleStatus == NodeTitleStatus.nodeRunning)
                    AltrButton(
                      label: "Stop Node",
                      onPressed: _stopNode,
                      isOutsideContainer: true,
                    ),
                  if (nodeTitleStatus == NodeTitleStatus.nodeFailing ||
                      nodeTitleStatus == NodeTitleStatus.nodeFailed ||
                      nodeTitleStatus == NodeTitleStatus.nodeUpdateFailed ||
                      nodeTitleStatus == NodeTitleStatus.nodeRepairFailed ||
                      nodeTitleStatus == NodeTitleStatus.dockerError)
                    AltrButton(
                      label: "Diagnose & Fix",
                      onPressed: _showDiagnoseAndFix,
                      isOutsideContainer: true,
                    ),
                  if (nodeTitleStatus == NodeTitleStatus.nodeStopped)
                    AltrButton(
                      label: "Start Altr Stream",
                      onPressed: _startNode,
                      isOutsideContainer: true,
                    ),

                  if (nodeTitleStatus == NodeTitleStatus.nodePaused)
                    AltrButton(
                      label: "Resume Node",
                      onPressed: _resumeNode,
                      isOutsideContainer: true,
                    ),
                  if (nodeTitleStatus == NodeTitleStatus.nodePaused)
                    AltrButton(
                      label: "Stop Node",
                      onPressed: _stopNode,
                      isOutsideContainer: true,
                    ),

                  if (nodeTitleStatus == NodeTitleStatus.nodeNotInstalled)
                    AltrButton(
                      label: "Install Altr Stream",
                      onPressed: () => _installNode(altrNodeVersion),
                      isOutsideContainer: true,
                    ),

                  if (nodeTitleStatus == NodeTitleStatus.nodeRunning ||
                      nodeTitleStatus == NodeTitleStatus.nodePaused ||
                      nodeTitleStatus == NodeTitleStatus.nodeFailed ||
                      nodeTitleStatus == NodeTitleStatus.nodeFailing ||
                      nodeTitleStatus == NodeTitleStatus.nodeRepairFailed ||
                      nodeTitleStatus == NodeTitleStatus.nodeUpdateFailed)
                    AltrButton(label: "Uninstall Node", onPressed: _uninstallNode, isOutsideContainer: true),
                ],
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    LinearProgressIndicator(
                      value: _progressValue != null && _progressValue! > 0 ? _progressValue : null,
                      color: Theme.of(context).colorScheme.primary,
                      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                      minHeight: 6,
                      trackGap: 4,
                      // ignore: deprecated_member_use
                      year2023: false,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _progressPercent != null && _progressPercent! > 0
                          ? '$_progressMessage ($_progressPercent%)'
                          : _progressMessage,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w500,
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),

            Spacer(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(
                  onPressed: _showTechnicalLogs,
                  child: const Text("Technical Logs"),
                ),
                TextButton(
                  onPressed: _showDiagnoseAndFix,
                  child: const Text("Diagnose & Fix"),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class AltrButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  final Icon? icon;
  final bool? isOutsideContainer;

  const AltrButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.isOutsideContainer,
  });

  @override
  Widget build(BuildContext context) {
    final brightness = View.of(context).platformDispatcher.platformBrightness;

    return FilledButton.icon(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: brightness == Brightness.light
            ? isOutsideContainer == true
                ? Theme.of(context).colorScheme.surfaceContainerHigh
                : Theme.of(context).colorScheme.surfaceContainerLowest
            : isOutsideContainer == true
                ? Theme.of(context).colorScheme.surfaceContainerHigh
                : Theme.of(context).colorScheme.surfaceContainer,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        fixedSize: const Size.fromHeight(36),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.normal),
        elevation: 0,
      ),
      icon: icon,
      label: Text(label),
    );
  }
}

/// Renders text truncated in the middle on a single line, adhering to macOS-style path truncation.
class MiddleTruncatedPathText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final TextAlign textAlign;

  const MiddleTruncatedPathText(
    this.text, {
    super.key,
    this.style,
    this.textAlign = TextAlign.end,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveStyle = style ?? DefaultTextStyle.of(context).style;
    final textScaler = MediaQuery.textScalerOf(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        if (maxWidth <= 0 || maxWidth == double.infinity) {
          return Text(
            text,
            style: effectiveStyle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          );
        }

        // 1. Measure if the full path fits on a single line
        final painter = TextPainter(
          text: TextSpan(text: text, style: effectiveStyle),
          textDirection: TextDirection.ltr,
          textScaler: textScaler,
          maxLines: 1,
        )..layout();

        if (painter.width <= maxWidth) {
          return Text(
            text,
            style: effectiveStyle,
            maxLines: 1,
            textAlign: textAlign,
          );
        }

        // 2. Perform segment-based middle truncation (macOS style: preserving root & leaf directories)
        final bool isWindows = text.contains('\\') && !text.contains('/');
        final String separator = isWindows ? '\\' : '/';
        final bool hasLeading = text.startsWith(separator);
        final bool hasTrailing = text.endsWith(separator);

        final List<String> segments = text
            .split(separator)
            .where((s) => s.isNotEmpty)
            .toList();

        String bestCandidate = '';

        if (segments.length > 2) {
          int leftCount = 1;
          int rightCount = 1;

          while (leftCount + rightCount < segments.length) {
            bool advanced = false;

            // Try adding left segment if balanced or fewer segments
            if (leftCount <= rightCount && leftCount + rightCount + 1 <= segments.length) {
              final String nextLeft = (hasLeading ? separator : '') + segments.sublist(0, leftCount + 1).join(separator);
              final String currentRight = segments.sublist(segments.length - rightCount).join(separator) + (hasTrailing ? separator : '');
              final String testCandidate = '$nextLeft$separator...$separator$currentRight';

              painter.text = TextSpan(text: testCandidate, style: effectiveStyle);
              painter.layout();

              if (painter.width <= maxWidth) {
                leftCount++;
                advanced = true;
              }
            }

            // Try adding right segment
            if (rightCount < leftCount && leftCount + rightCount + 1 <= segments.length) {
              final String currentLeft = (hasLeading ? separator : '') + segments.sublist(0, leftCount).join(separator);
              final String nextRight = segments.sublist(segments.length - (rightCount + 1)).join(separator) + (hasTrailing ? separator : '');
              final String testCandidate = '$currentLeft$separator...$separator$nextRight';

              painter.text = TextSpan(text: testCandidate, style: effectiveStyle);
              painter.layout();

              if (painter.width <= maxWidth) {
                rightCount++;
                advanced = true;
              }
            }

            if (!advanced) break;
          }

          final String finalLeft = (hasLeading ? separator : '') + segments.sublist(0, leftCount).join(separator);
          final String finalRight = segments.sublist(segments.length - rightCount).join(separator) + (hasTrailing ? separator : '');
          final String candidate = '$finalLeft$separator...$separator$finalRight';

          painter.text = TextSpan(text: candidate, style: effectiveStyle);
          painter.layout();

          if (painter.width <= maxWidth) {
            bestCandidate = candidate;
          }
        }

        // 3. Fallback to character-level middle truncation if segment level still exceeds maxWidth
        if (bestCandidate.isEmpty) {
          int low = 4;
          int high = text.length - 1;
          bestCandidate = '...';

          while (low <= high) {
            final mid = (low + high) ~/ 2;
            final startLen = (mid / 2).ceil();
            final endLen = (mid / 2).floor();

            String cleanStart = text.substring(0, startLen);
            String cleanEnd = text.substring(text.length - endLen);

            if (cleanStart.endsWith(separator)) cleanStart = cleanStart.substring(0, cleanStart.length - 1);
            if (cleanEnd.startsWith(separator)) cleanEnd = cleanEnd.substring(1);

            final candidate = '$cleanStart$separator...$separator$cleanEnd';

            painter.text = TextSpan(text: candidate, style: effectiveStyle);
            painter.layout();

            if (painter.width <= maxWidth) {
              bestCandidate = candidate;
              low = mid + 1;
            } else {
              high = mid - 1;
            }
          }
        }

        return Tooltip(
          message: text,
          waitDuration: const Duration(milliseconds: 400),
          child: Text(
            bestCandidate,
            style: effectiveStyle,
            maxLines: 1,
            textAlign: textAlign,
          ),
        );
      },
    );
  }
}

class TableRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String rowLabel;
  final Color rowValueColor;
  final String rowValue;
  final Widget? trailingAction;
  final Widget? controls;

  const TableRow({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.rowLabel,
    required this.rowValueColor,
    required this.rowValue,
    this.trailingAction,
    this.controls,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: iconColor),
        const SizedBox(width: 16),
        Text(rowLabel, style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Flexible(
                    child: MiddleTruncatedPathText(
                      rowValue,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: rowValueColor),
                      textAlign: TextAlign.end,
                    ),
                  ),
                  if (trailingAction != null) ...[
                    const SizedBox(width: 8),
                    trailingAction!,
                  ],
                ],
              ),
              if (controls != null) ...[const SizedBox(height: 12), controls!],
            ],
          ),
        ),
      ],
    );
  }
}

class TableDivider extends StatelessWidget {
  final double height;

  const TableDivider({super.key, required this.height});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: height),
      child: Divider(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3)),
    );
  }
}

/// Responsive technical logs dialog providing non-blocking asynchronous log retrieval,
/// copy to clipboard, and log buffer clearing.
class TechnicalLogsDialog extends StatefulWidget {
  final BackendService backendService;

  const TechnicalLogsDialog({super.key, required this.backendService});

  @override
  State<TechnicalLogsDialog> createState() => _TechnicalLogsDialogState();
}

class _TechnicalLogsDialogState extends State<TechnicalLogsDialog> {
  String _logs = '';
  bool _isLoading = true;
  String? _error;
  bool _showRawLogs = false;

  @override
  void initState() {
    super.initState();
    _fetchLogs();
  }

  Future<void> _fetchLogs({bool force = false}) async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final logs = await widget.backendService.getInstallationLogs(forceRefresh: force, raw: _showRawLogs);
      if (!mounted) return;
      setState(() {
        _logs = logs;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load logs: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _copyLogs() async {
    if (_logs.isEmpty) return;
    try {
      await Clipboard.setData(ClipboardData(text: _logs));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Logs copied to clipboard'),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to copy logs: $e'),
          backgroundColor: Colors.red.shade800,
        ),
      );
    }
  }

  Future<void> _clearLogs() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear Displayed Logs?'),
        content: const SizedBox(
          width: kDialogStandardWidth,
          child: Text(
            'This will clear Manager diagnostics and application session history. '
            'Docker container logs are managed externally by the Docker engine and are filtered by timestamp rather than deleted. '
            'It will not affect your running containers, volumes, settings, or application data.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Clear Logs'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await widget.backendService.clearLogs();
      await _fetchLogs(force: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Log buffer cleared'),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to clear logs: $e'),
          backgroundColor: Colors.red.shade800,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('Technical Logs'),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Copy Logs',
                icon: const Icon(HugeIconsStroke.copy01, size: 18),
                onPressed: _logs.isNotEmpty ? _copyLogs : null,
              ),
              IconButton(
                tooltip: 'Clear Logs',
                icon: const Icon(HugeIconsStroke.delete02, size: 18),
                onPressed: _logs.isNotEmpty ? _clearLogs : null,
              ),
              IconButton(
                tooltip: 'Refresh',
                icon: const Icon(HugeIconsStroke.refresh, size: 18),
                onPressed: _isLoading ? null : () => _fetchLogs(force: true),
              ),
            ],
          ),
        ],
      ),
      content: SizedBox(
        width: 580,
        height: 440,
        child: Column(
          children: [
            Row(
              children: [
                SegmentedButton<bool>(
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  segments: const [
                    ButtonSegment(
                      value: false,
                      label: Text('Decluttered', style: TextStyle(fontSize: 11)),
                      icon: Icon(HugeIconsStroke.filter, size: 12),
                    ),
                    ButtonSegment(
                      value: true,
                      label: Text('Raw Logs', style: TextStyle(fontSize: 11)),
                      icon: Icon(HugeIconsStroke.database01, size: 12),
                    ),
                  ],
                  selected: {_showRawLogs},
                  onSelectionChanged: (set) {
                    setState(() {
                      _showRawLogs = set.first;
                    });
                    _fetchLogs(force: true);
                  },
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _showRawLogs ? 'Full container logs' : 'Health checks collapsed',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                          fontSize: 11,
                        ),
                    textAlign: TextAlign.end,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: _isLoading
                    ? const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 12),
                            Text('Retrieving technical logs...'),
                          ],
                        ),
                      )
                    : _error != null
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.error_outline, color: Colors.red.shade400, size: 36),
                                const SizedBox(height: 8),
                                Text(_error!),
                                const SizedBox(height: 12),
                                OutlinedButton(
                                  onPressed: () => _fetchLogs(force: true),
                                  child: const Text('Retry'),
                                ),
                              ],
                            ),
                          )
                        : SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: SingleChildScrollView(
                              scrollDirection: Axis.vertical,
                              child: SelectableText(
                                _logs.isEmpty ? 'No logs available.' : _logs,
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

/// Comprehensive Diagnose & Fix modal displaying bounded diagnostic checks,
/// plain-language findings, safe actionable remediation, and post-action verification.
class DiagnoseAndFixDialog extends StatefulWidget {
  final BackendService backendService;
  final VoidCallback? onStatusChanged;

  const DiagnoseAndFixDialog({
    super.key,
    required this.backendService,
    this.onStatusChanged,
  });

  @override
  State<DiagnoseAndFixDialog> createState() => _DiagnoseAndFixDialogState();
}

class _DiagnoseAndFixDialogState extends State<DiagnoseAndFixDialog> {
  DiagnosticReport? _report;
  bool _isLoading = true;
  bool _isExecutingAction = false;
  String? _actionResultMessage;
  bool? _actionResultSuccess;

  @override
  void initState() {
    super.initState();
    _runDiagnostics();
  }

  Future<void> _runDiagnostics() async {
    setState(() {
      _isLoading = true;
    });
    try {
      final report = await widget.backendService.runDiagnostics();
      if (!mounted) return;
      setState(() {
        _report = report;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _executeRecommendedAction(RecommendedActionType action) async {
    setState(() {
      _isExecutingAction = true;
      _actionResultMessage = null;
      _actionResultSuccess = null;
    });

    try {
      switch (action) {
        case RecommendedActionType.startDocker:
          await widget.backendService.startDockerDesktop();
          break;
        case RecommendedActionType.installDocker:
          final uri = Uri.parse('https://www.docker.com/products/docker-desktop/');
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri);
          } else {
            await Clipboard.setData(const ClipboardData(text: 'https://www.docker.com/products/docker-desktop/'));
          }
          break;
        case RecommendedActionType.resumeDocker:
          await widget.backendService.resumeDockerDesktop();
          break;
        case RecommendedActionType.startNode:
          await widget.backendService.startNode();
          break;
        case RecommendedActionType.repairNode:
          await for (final _ in widget.backendService.repairNode()) {}
          break;
        case RecommendedActionType.none:
          break;
      }

      // Post-action bounded verification check
      final postReport = await widget.backendService.runDiagnostics();
      if (!mounted) return;

      final allChecksPassed = postReport.checks.every(
        (c) => c.status == DiagnosticStatus.passed || c.status == DiagnosticStatus.info || c.status == DiagnosticStatus.skipped,
      );

      setState(() {
        _report = postReport;
        _actionResultSuccess = allChecksPassed;
        _actionResultMessage = allChecksPassed
            ? 'Verified: Issue resolved successfully! All diagnostic checks passed.'
            : 'Action performed, but issue persists: ${postReport.primaryFinding}.';
      });

      widget.onStatusChanged?.call();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _actionResultSuccess = false;
        _actionResultMessage = 'Error during repair action: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isExecutingAction = false;
        });
      }
    }
  }

  Widget _buildStatusBadge(DiagnosticStatus status) {
    Color bg;
    Color fg;
    String label;
    IconData icon;

    switch (status) {
      case DiagnosticStatus.passed:
        bg = Colors.green.withValues(alpha: 0.15);
        fg = Colors.green.shade400;
        label = 'PASSED';
        icon = Icons.check_circle_outline;
        break;
      case DiagnosticStatus.failed:
        bg = Colors.red.withValues(alpha: 0.15);
        fg = Colors.red.shade400;
        label = 'FAILED';
        icon = Icons.error_outline;
        break;
      case DiagnosticStatus.warning:
        bg = Colors.amber.withValues(alpha: 0.15);
        fg = Colors.amber.shade400;
        label = 'WARNING';
        icon = Icons.warning_amber_outlined;
        break;
      case DiagnosticStatus.info:
        bg = Colors.blue.withValues(alpha: 0.15);
        fg = Colors.blue.shade400;
        label = 'INFO';
        icon = Icons.info_outline;
        break;
      case DiagnosticStatus.skipped:
        bg = Colors.grey.withValues(alpha: 0.15);
        fg = Colors.grey.shade400;
        label = 'SKIPPED';
        icon = Icons.remove_circle_outline;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: fg),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: fg,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final report = _report;

    return AlertDialog(
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('Diagnose & Fix'),
          IconButton(
            tooltip: 'Re-run Diagnostics',
            icon: const Icon(HugeIconsStroke.refresh, size: 18),
            onPressed: (_isLoading || _isExecutingAction) ? null : _runDiagnostics,
          ),
        ],
      ),
      content: SizedBox(
        width: kDialogStandardWidth,
        height: 520,
        child: _isLoading
            ? const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 12),
                    Text('Running diagnostic checks...'),
                  ],
                ),
              )
            : report == null
                ? const Center(child: Text('Unable to load diagnostic report.'))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Primary finding banner
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: report.recommendedAction != RecommendedActionType.none
                                ? Colors.amber.shade700
                                : Colors.green.shade700,
                            width: 1.5,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  report.recommendedAction != RecommendedActionType.none
                                      ? Icons.warning_amber_rounded
                                      : Icons.check_circle_rounded,
                                  color: report.recommendedAction != RecommendedActionType.none
                                      ? Colors.amber.shade400
                                      : Colors.green.shade400,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    report.primaryFinding,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              report.summaryExplanation,
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_actionResultMessage != null) ...[
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: _actionResultSuccess == true
                                ? Colors.green.withValues(alpha: 0.15)
                                : Colors.amber.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: _actionResultSuccess == true ? Colors.green : Colors.amber,
                            ),
                          ),
                          child: Text(
                            _actionResultMessage!,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: _actionResultSuccess == true ? Colors.green.shade300 : Colors.amber.shade300,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      const Text(
                        'Diagnostic Checks',
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                      const SizedBox(height: 6),
                      // Checks list
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surfaceContainerLowest,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(8),
                            child: Column(
                              children: [
                                for (int i = 0; i < report.checks.length; i++) ...[
                                  if (i > 0) const Divider(height: 1),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Expanded(
                                              child: Text(
                                                report.checks[i].title,
                                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            _buildStatusBadge(report.checks[i].status),
                                          ],
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          report.checks[i].details,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
      ),
      actions: [
        if (_report != null &&
            _report!.recommendedAction != RecommendedActionType.none &&
            _actionResultSuccess != true)
          FilledButton(
            onPressed: _isExecutingAction
                ? null
                : () => _executeRecommendedAction(_report!.recommendedAction),
            child: _isExecutingAction
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : Text(_report!.recommendedActionLabel),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

