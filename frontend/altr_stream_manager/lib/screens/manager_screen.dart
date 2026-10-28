import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart' hide TableRow;
import 'package:flutter/services.dart';
import 'package:hugeicons_pro/hugeicons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/constants.dart';
import '../dialogs/diagnose_and_fix_dialog.dart';
import '../dialogs/technical_logs_dialog.dart';
import '../models/install_progress.dart';
import '../models/node_title_status.dart';
import '../services/backend_init.dart';
import '../services/directory_picker_service.dart';
import '../services/engine_backend_service.dart';
import '../services/mock_backend_service.dart';
import '../widgets/altr_button.dart';
import '../widgets/table_row.dart';

// Helper aliases to maintain exact function signatures for build helpers
final _buildAltrNodeTitleStatusIcon = buildAltrNodeTitleStatusIcon;
final _buildAltrNodeTitleStatusText = buildAltrNodeTitleStatusText;
final _buildAltrNodeSubtitleStatusText = buildAltrNodeSubtitleStatusText;
final _buildDockerStatusText = buildDockerStatusText;
final _buildAltrNodeStatusText = buildAltrNodeStatusText;
final _buildAltrNodeTitleStatusColor = buildAltrNodeTitleStatusColor;
final _buildDockerStatusColor = buildDockerStatusColor;
final _buildAltrNodeStatusColor = buildAltrNodeStatusColor;

/// Main management dashboard screen for Altr Stream node lifecycle and configuration.
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
                const SizedBox(width: 16),
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
                const Spacer(),
                IconButton(
                  tooltip: "Refresh Status",
                  onPressed: _manualRefresh,
                  icon: const Icon(HugeIconsStroke.refresh, size: 22),
                ),
                const SizedBox(width: 4),
                IconButton(
                  tooltip: "Quit Manager",
                  onPressed: _confirmQuitApp,
                  icon: const Icon(HugeIconsStroke.shutDown, size: 24),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              width: MediaQuery.of(context).size.width - 48, // Padding of 24 on each side
              padding: const EdgeInsets.all(16),
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
                  const TableDivider(height: 8),
                  TableRow(
                    icon: HugeIconsSolid.circle,
                    iconColor: _buildAltrNodeStatusColor(nodeState, context),
                    rowLabel: "Altr Stream Node Status",
                    rowValue: _buildAltrNodeStatusText(nodeState, context),
                    rowValueColor: _buildAltrNodeStatusColor(nodeState, context),
                  ),
                  const TableDivider(height: 8),
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
                  const TableDivider(height: 8),
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
                          icon: const Icon(HugeIconsStroke.folder02, size: 18),
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
            const SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  _buildAltrNodeTitleStatusIcon(nodeTitleStatus),
                  size: 36,
                  color: _buildAltrNodeTitleStatusColor(nodeTitleStatus, context),
                ),
                const SizedBox(width: 12),
                Text(
                  _buildAltrNodeTitleStatusText(nodeTitleStatus, context),
                  style: Theme.of(context).textTheme.headlineMedium
                      ?.copyWith(color: _buildAltrNodeTitleStatusColor(nodeTitleStatus, context)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _buildAltrNodeSubtitleStatusText(nodeTitleStatus, dashboardAddress, context),
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
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
            const Spacer(),
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
