import 'dart:async';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'core/api/api_client.dart';
import 'core/api/models.dart';
import 'core/config/app_config.dart';
import 'core/theme/app_theme.dart';
import 'features/activity/screens/activity_screen.dart';
import 'features/altrql_playground/screens/altrql_playground_screen.dart';
import 'features/docs/screens/api_docs_screen.dart';
import 'features/overview/screens/overview_screen.dart';
import 'features/registry/screens/logical_model_detail_screen.dart';
import 'features/registry/screens/registry_screen.dart';
import 'features/registry/widgets/create_logical_model_dialog.dart';
import 'features/settings/screens/settings_screen.dart';
import 'features/sources/screens/source_detail_screen.dart';
import 'features/sources/screens/sources_screen.dart';
import 'features/sources/widgets/add_source_wizard_dialog.dart';
import 'shared/widgets/app_shell.dart';
import 'shared/widgets/node_status_dialog.dart';
import 'shared/widgets/trail_extended_fab.dart';
import 'shared/feedback/feedback_dialog.dart';
import 'shared/dialogs/altr_alert_dialog.dart';
import 'shared/live_actions/live_actions_controller.dart';
import 'core/auth/models/workspace.dart';
import 'core/auth/services/auth_service.dart';
import 'core/auth/services/passcode_service.dart';
import 'core/auth/services/workspace_service.dart';
import 'core/auth/dialogs/passcode_setup_dialog.dart';
import 'core/auth/dialogs/api_security_dialog.dart';
import 'core/auth/dialogs/create_workspace_dialog.dart';
import 'core/auth/dialogs/account_workspace_setup_dialog.dart';

import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'core/theme/material_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    BrowserContextMenu.disableContextMenu();
  } catch (_) {}
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    debugPrint('[Main] Firebase initialization note: $e');
  }
  runApp(const AltrStreamAdminApp());
}

class AltrStreamAdminApp extends StatefulWidget {
  const AltrStreamAdminApp({super.key});

  @override
  State<AltrStreamAdminApp> createState() => _AltrStreamAdminAppState();
}

class _AltrStreamAdminAppState extends State<AltrStreamAdminApp> {
  ThemeMode _themeMode = ThemeMode.system;

  void _handleThemeModeChanged(ThemeMode mode) {
    setState(() {
      _themeMode = mode;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Altr Stream Admin',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: _themeMode,
      debugShowCheckedModeBanner: false,
      builder: (context, child) {
        final materialTheme = Theme.of(context);
        return M3ETheme(
          data: M3EThemeData(
            colorScheme: materialTheme.colorScheme.toM3EColorScheme().copyWith(
              tertiaryContainer:
                  materialTheme.colorScheme.surfaceContainerHighest,
              onTertiaryContainer: materialTheme.colorScheme.onSurface,
              secondaryContainer:
                  materialTheme.colorScheme.surfaceContainerHigh,
              onSecondaryContainer: materialTheme.colorScheme.onSurface,
            ),
            menuTheme: M3EMenuTheme(
              backgroundColor: materialTheme.colorScheme.surfaceContainerHigh,
              maxHeight: 800,
            ),
            navigationDrawerTheme: const M3ENavigationDrawerTheme(width: 320),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: AdminHomeScreen(
        themeMode: _themeMode,
        onThemeModeChanged: _handleThemeModeChanged,
      ),
    );
  }
}

class AdminHomeScreen extends StatefulWidget {
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;

  const AdminHomeScreen({
    super.key,
    required this.themeMode,
    required this.onThemeModeChanged,
  });

  @override
  State<AdminHomeScreen> createState() => _AdminHomeScreenState();
}

class _AdminHomeScreenState extends State<AdminHomeScreen> {
  final ApiClient _apiClient = ApiClient();
  final AuthService _authService = AuthService();
  final PasscodeService _passcodeService = PasscodeService();
  final WorkspaceService _workspaceService = WorkspaceService();
  late final LiveActionsController _liveActionsController;

  List<SourceModel> _sources = [];
  int _modelsCount = 0;
  final List<ActivityLogModel> _activities = [];
  bool _isLoadingSources = true;
  String _activeRoute = '/';
  String? _previousRoute;
  String? _settingsCategory;
  SourceModel? _selectedSource;
  LogicalModelModel? _selectedLogicalModel;
  String _nodeStatus = 'ACTIVE';
  UserProfile? _currentUser;
  final GlobalKey<OverviewScreenState> _overviewKey =
      GlobalKey<OverviewScreenState>();
  final GlobalKey<RegistryScreenState> _registryKey =
      GlobalKey<RegistryScreenState>();
  final GlobalKey<SourcesScreenState> _sourcesKey =
      GlobalKey<SourcesScreenState>();
  final GlobalKey<SourceDetailScreenState> _sourceDetailKey =
      GlobalKey<SourceDetailScreenState>();
  final GlobalKey<LogicalModelDetailScreenState> _logicalModelDetailKey =
      GlobalKey<LogicalModelDetailScreenState>();

  UsageMetricsModel? _usageMetrics;
  Timer? _usageTimer;
  String _usageTimeWindow = '30m';

  @override
  void initState() {
    super.initState();
    _authService.initialize();
    _authService.addListener(_onAuthChanged);
    _passcodeService.addListener(_onPasscodeChanged);
    _workspaceService.addListener(_onWorkspaceChanged);

    _liveActionsController = LiveActionsController(
      onRequestLockSudo: _showExitSudoConfirmation,
      onOpenFeedback: () => FeedbackDialog.show(context, apiClient: _apiClient),
    );

    _logActivity(
      type: ActivityType.nodeStart,
      title: 'Altr Stream Node Initialized',
      description:
          'Connected to local runtime metadata and PostgreSQL connector ready.',
    );
    _probeNodeHealth();
    _fetchSources(probe: true);
    _fetchModels();
    _fetchUsageMetrics();
    _usageTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted) {
        _fetchUsageMetrics();
      }
    });
  }

  @override
  void dispose() {
    _usageTimer?.cancel();
    _authService.removeListener(_onAuthChanged);
    _passcodeService.removeListener(_onPasscodeChanged);
    _workspaceService.removeListener(_onWorkspaceChanged);
    _liveActionsController.dispose();
    super.dispose();
  }

  void _onAuthChanged() {
    if (!mounted) return;
    setState(() {
      _currentUser = _authService.currentProfile;
    });
  }

  void _onPasscodeChanged() {
    if (!mounted) return;
    if (_passcodeService.isSudoActive && !_liveActionsController.isSudoActive) {
      _liveActionsController.activateSudo(
        durationSeconds: _passcodeService.sudoRemainingSeconds,
      );
    } else if (!_passcodeService.isSudoActive && _liveActionsController.isSudoActive) {
      _liveActionsController.lockSudo();
    }
    setState(() {});
  }

  void _onWorkspaceChanged() {
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _fetchUsageMetrics() async {
    try {
      final metrics = await _apiClient.getUsageMetrics(
        timeWindow: _usageTimeWindow,
      );
      if (mounted) {
        setState(() {
          _usageMetrics = metrics;
        });
      }
    } catch (_) {}
  }

  void _logActivity({
    required ActivityType type,
    required String title,
    required String description,
    bool isSuccess = true,
    String? sourceId,
    String? sourceName,
  }) {
    setState(() {
      _activities.insert(
        0,
        ActivityLogModel(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          type: type,
          title: title,
          description: description,
          timestamp: DateTime.now(),
          isSuccess: isSuccess,
          sourceId: sourceId,
          sourceName: sourceName,
        ),
      );
    });
  }

  Future<void> _probeNodeHealth() async {
    try {
      final health = await _apiClient.getHealth();
      if (health['version'] != null) {
        AppConfig.setRuntimeNodeVersion(health['version'].toString());
      }
      setState(() {
        _nodeStatus = health['status'] == 'healthy' ? 'ACTIVE' : 'DEGRADED';
      });
    } catch (_) {
      setState(() {
        _nodeStatus = 'UNREACHABLE';
      });
    }
  }

  Future<void> _fetchSources({bool probe = false}) async {
    setState(() => _isLoadingSources = true);
    try {
      final list = await _apiClient.listSources(probe: probe);
      setState(() {
        _sources = list;
        if (_selectedSource != null) {
          _selectedSource = _sources.firstWhere(
            (s) => s.id == _selectedSource!.id,
            orElse: () => _selectedSource!,
          );
        }
      });
    } catch (e) {
      if (mounted) {
        final colorScheme = Theme.of(context).colorScheme;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load data sources: $e'),
            backgroundColor: colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingSources = false);
      }
    }
  }

  Future<void> _fetchModels() async {
    try {
      final list = await _apiClient.listLogicalModels();
      if (mounted) {
        setState(() {
          _modelsCount = list.length;
        });
      }
    } catch (_) {}
  }

  void _showAddSourceWizard() {
    M3EDialog.show<void>(
      context,
      barrierDismissible: true,
      dialog: AddSourceWizardDialog(
        apiClient: _apiClient,
        onSourceCreated: (newSource) {
          final endpointDesc = newSource.type == 'SQLITE'
              ? (newSource.filePath ?? 'Local File')
              : '${newSource.host ?? ""}:${newSource.port ?? ""}';
          _logActivity(
            type: ActivityType.sourceRegistered,
            title: 'Source Registered',
            description:
                'Registered "${newSource.name}" (${newSource.type} on $endpointDesc)',
            sourceId: newSource.id,
            sourceName: newSource.name,
          );
          _fetchSources();
          setState(() {
            _selectedSource = newSource;
            _activeRoute = '/sources/detail';
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Data source "${newSource.name}" registered successfully!',
              ),
              backgroundColor: AppTheme.getStatusColor('ACTIVE', context),
            ),
          );
        },
      ),
    );
  }

  void _showCreateLogicalModelDialog() {
    showDialog(
      context: context,
      builder: (ctx) => CreateLogicalModelDialog(
        apiClient: _apiClient,
        onModelCreated: (newModel) {
          _fetchModels();
          _registryKey.currentState?.fetchRegistry();
          setState(() {
            _selectedLogicalModel = newModel;
            _activeRoute = '/registry/detail';
          });
        },
      ),
    );
  }

  String _getPageTitle() {
    if (_activeRoute == '/') return 'Overview';
    if (_activeRoute == '/sources/detail') {
      return _selectedSource?.name ?? 'Data Source Details';
    }
    if (_activeRoute == '/sources') return 'Data Sources';
    if (_activeRoute == '/registry/detail') {
      return _selectedLogicalModel?.name ?? 'Logical Model Details';
    }
    if (_activeRoute == '/registry') {
      return 'Logical Models';
    }
    if (_activeRoute == '/activity') {
      return 'Activity';
    }
    if (_activeRoute == '/settings') {
      return 'Settings';
    }
    if (_activeRoute == '/altrql' || _activeRoute == '/playground') {
      return 'AltrQL Console';
    }
    return 'Overview';
  }

  String _getPageSubtitle() {
    if (_activeRoute == '/') {
      return 'System overview, status & analytics';
    }
    if (_activeRoute == '/sources/detail') {
      return _selectedSource != null
          ? '${_selectedSource!.type} • ${_selectedSource!.host ?? _selectedSource!.filePath ?? "Connected"}'
          : 'Inspect tables, schema & test connectivity';
    }
    if (_activeRoute == '/sources') {
      return 'Manage connected data sources and connections';
    }
    if (_activeRoute == '/registry/detail') {
      return _selectedLogicalModel != null
          ? 'v${_selectedLogicalModel!.version} • ${_selectedLogicalModel!.entityCount} Entities • ${_selectedLogicalModel!.totalFieldCount} Fields'
          : 'Manage mappings, views & virtual schemas';
    }
    if (_activeRoute == '/registry') {
      return 'Define federated schemas and entity mappings';
    }
    if (_activeRoute == '/activity') {
      return 'Real-time audit log and system events';
    }
    if (_activeRoute == '/settings') {
      return 'Global configurations and engine parameters';
    }
    if (_activeRoute == '/altrql' || _activeRoute == '/playground') {
      return 'Execute federated SQL queries across sources';
    }
    return 'System overview, status & analytics';
  }

  VoidCallback? _getOnBack() {
    if (_activeRoute == '/sources/detail') {
      return () => setState(() => _activeRoute = '/sources');
    }
    if (_activeRoute == '/registry/detail') {
      return () => setState(() => _activeRoute = '/registry');
    }
    return null;
  }

  List<Widget>? _getPageActions() {
    final colorScheme = Theme.of(context).colorScheme;
    return [
      Focus(
        canRequestFocus: false,
        skipTraversal: true,
        child: M3EIconButton(
          icon: HugeIcon(
            icon: HugeIcons.strokeRoundedRefresh,
            color: colorScheme.onSurface,
            size: 18,
          ),
          onPressed: () {
            FocusManager.instance.primaryFocus?.unfocus();
            _probeNodeHealth();
            _fetchSources(probe: true);
            _fetchModels();

            if (_activeRoute == '/') {
              _overviewKey.currentState?.triggerRefresh();
            } else if (_activeRoute == '/sources') {
              _sourcesKey.currentState?.triggerRefresh();
            } else if (_activeRoute == '/sources/detail') {
              _sourceDetailKey.currentState?.triggerRefresh();
            } else if (_activeRoute == '/registry') {
              _registryKey.currentState?.triggerRefresh();
            } else if (_activeRoute == '/registry/detail') {
              _logicalModelDetailKey.currentState?.triggerRefresh();
            }
          },
          variant: M3EIconButtonVariant.standard,
          size: M3EIconButtonSize.xs,
          tooltip: 'Refresh',
        ),
      ),
    ];
  }

  Widget? _getFloatingActionButton() {
    if (_activeRoute == '/sources') {
      return M3ETrailExtendedFab(
        icon: HugeIcons.strokeRoundedPlusSign,
        label: 'Add Data Source',
        color: M3EFabColor.primary,
        onPressed: _showAddSourceWizard,
      );
    }
    if (_activeRoute == '/registry') {
      return M3ETrailExtendedFab(
        icon: HugeIcons.strokeRoundedPlusSign,
        label: 'New Logical Model',
        color: M3EFabColor.primary,
        onPressed: _showCreateLogicalModelDialog,
      );
    }
    if (_activeRoute == '/activity') {
      return M3ETrailExtendedFab(
        icon: HugeIcons.strokeRoundedTimelineList,
        label: 'Clear Timeline',
        color: M3EFabColor.primary,
        onPressed: () => setState(() => _activities.clear()),
      );
    }
    return null;
  }

  void _showNodeStatusDialog() {
    final activeCount = _sources.where((s) => s.isActive).length;
    M3EDialog.show<void>(
      context,
      barrierDismissible: true,
      dialog: NodeStatusDialog(
        apiClient: _apiClient,
        connectedSourcesCount: _sources.length,
        activeSourcesCount: activeCount,
      ),
    );
  }

  Future<void> _showSignInDialog() async {
    try {
      final credential = await _authService.signInWithGoogle();
      if (credential != null && mounted) {
        final user = credential.user;
        if (user != null) {
          final existing = await _authService.checkProfileExists(user.uid);
          if (existing != null) {
            setState(() => _currentUser = existing);
            _logActivity(
              type: ActivityType.nodeStart,
              title: 'Google Sign-In Success',
              description: 'Signed in as ${existing.displayName} (${existing.email})',
            );
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Welcome back, ${existing.displayName}! Signed in with Google.'),
                backgroundColor: Theme.of(context).colorScheme.primary,
              ),
            );
          } else if (mounted) {
            final setup = await showDialog<UserProfile>(
              context: context,
              barrierDismissible: false,
              builder: (ctx) => AccountWorkspaceSetupDialog(
                userId: user.uid,
                initialEmail: user.email ?? '',
                initialDisplayName: user.displayName ?? '',
                initialPhotoUrl: user.photoURL,
              ),
            );
            if (setup != null && mounted) {
              setState(() => _currentUser = setup);
              _logActivity(
                type: ActivityType.nodeStart,
                title: 'Account & Workspace Configured',
                description: 'Configured profile and workspace for ${setup.displayName} (${setup.email})',
              );
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Account & Workspace configured! Welcome, ${setup.displayName}.'),
                  backgroundColor: Theme.of(context).colorScheme.primary,
                ),
              );
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[AdminHomeScreen] Firebase Google Sign-In note: $e');
      if (mounted) {
        _showManualSignInFallback();
      }
    }
  }

  void _showManualSignInFallback() {
    final colorScheme = Theme.of(context).colorScheme;
    final nameController = TextEditingController(text: 'Asher Developer');
    final emailController = TextEditingController(text: 'asher@helloaltr.com');
    final photoController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colorScheme.surfaceContainerHigh,
        title: Row(
          children: [
            HugeIcon(
              icon: HugeIcons.strokeRoundedUserCircle,
              color: colorScheme.primary,
              size: 24,
            ),
            const SizedBox(width: 10),
            const Text('Altr Account Sign In'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Sign in with your Google account to manage node configuration, schemas, and queries.',
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Display Name *'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: emailController,
              decoration: const InputDecoration(labelText: 'Email *'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: photoController,
              decoration: const InputDecoration(
                labelText: 'Profile Picture URL (Optional)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'Cancel',
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
          ),
          M3EButton(
            onPressed: () async {
              final name = nameController.text.trim();
              final email = emailController.text.trim();
              final photo = photoController.text.trim();
              if (name.isNotEmpty && email.isNotEmpty) {
                final emailSlug = email.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_');
                final stableId = 'usr_$emailSlug';

                Navigator.of(ctx).pop();

                // Check if user already exists in Firestore
                final existing = await _authService.checkProfileExists(stableId);
                if (existing != null && mounted) {
                  await _authService.setManualProfile(existing);
                  setState(() {
                    _currentUser = existing;
                  });
                  _logActivity(
                    type: ActivityType.nodeStart,
                    title: 'User Authenticated',
                    description: 'Signed in as ${existing.displayName} (${existing.email})',
                  );
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Welcome back, ${existing.displayName}! Signed in.'),
                      backgroundColor: colorScheme.primary,
                    ),
                  );
                } else if (mounted) {
                  // First-time setup: prompt user to configure account & workspace details
                  final setup = await showDialog<UserProfile>(
                    context: context,
                    barrierDismissible: false,
                    builder: (dCtx) => AccountWorkspaceSetupDialog(
                      userId: stableId,
                      initialEmail: email,
                      initialDisplayName: name,
                      initialPhotoUrl: photo.isNotEmpty ? photo : null,
                    ),
                  );
                  if (setup != null && mounted) {
                    setState(() {
                      _currentUser = setup;
                    });
                    _logActivity(
                      type: ActivityType.nodeStart,
                      title: 'Account & Workspace Configured',
                      description: 'Configured profile and workspace for ${setup.displayName} (${setup.email})',
                    );
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Account & Workspace configured! Welcome, ${setup.displayName}.'),
                        backgroundColor: colorScheme.primary,
                      ),
                    );
                  }
                }
              }
            },
            style: M3EButtonStyle.filled,
            size: M3EButtonSize.sm,
            child: const Text('Sign In'),
          ),
        ],
      ),
    );
  }

  void _handleSignOut() async {
    final prevUser = _currentUser ?? _authService.currentProfile;
    _passcodeService.lockSudo();
    _liveActionsController.lockSudo();

    await _authService.signOut();
    setState(() {
      _currentUser = null;
    });
    if (prevUser != null) {
      _logActivity(
        type: ActivityType.nodeStart,
        title: 'User Signed Out',
        description: 'Signed out ${prevUser.displayName}',
      );
    }
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Successfully signed out.')));
    }
  }

  Future<void> _showExitSudoConfirmation() async {
    final confirmed = await AltrAlert.show(
      context,
      icon: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.amber.withValues(alpha: 0.18),
          shape: BoxShape.circle,
        ),
        child: const HugeIcon(
          icon: HugeIcons.strokeRoundedSecurityLock,
          color: Colors.amber,
          size: 26,
        ),
      ),
      title: 'Exit Sudo Mode?',
      message:
          'Are you sure you want to exit Sudo mode? Sensitive operations will require entering your passcode again.',
      cancelLabel: 'Cancel',
      confirmLabel: 'Exit Sudo',
      isDestructive: false,
    );

    if (confirmed == true) {
      _passcodeService.lockSudo();
      _liveActionsController.lockSudo();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sudo mode locked. Elevated privileges revoked.'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  void _openPasscodeDialog() {
    final effectiveUser = _currentUser ?? _authService.currentProfile ?? const UserProfile(
      id: 'local_admin',
      displayName: 'Local Admin',
      email: 'admin@localhost',
    );
    showDialog<void>(
      context: context,
      builder: (ctx) => PasscodeSetupDialog(
        userId: effectiveUser.id,
        userProfile: effectiveUser,
        initialType: effectiveUser.passcodeType,
        onConfigured: () async {
          await _authService.refreshProfile();
          if (mounted) {
            setState(() {
              _currentUser = _authService.currentProfile ?? effectiveUser.copyWith(
                passcodeType: _passcodeService.getCredentialType(effectiveUser.id) ?? 'pin',
                passcodeSalt: 'configured',
                passcodeVerifier: 'configured',
              );
            });
          }
        },
      ),
    );
  }

  void _openApiSecurityDialog() {
    final user = _currentUser ?? _authService.currentProfile ?? const UserProfile(
      id: 'local_admin',
      displayName: 'Local Admin',
      email: 'admin@localhost',
    );
    showDialog<void>(
      context: context,
      builder: (ctx) => ApiSecurityDialog(userProfile: user),
    );
  }

  void _openWorkspacesDialog() {
    final user = _currentUser ?? _authService.currentProfile;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in to access workspaces.')),
      );
      return;
    }

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          final theme = Theme.of(context);
          final colorScheme = theme.colorScheme;
          final workspaces = _workspaceService.workspaces;
          final active = _workspaceService.activeWorkspace;

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                HugeIcon(icon: HugeIcons.strokeRoundedGrid, color: colorScheme.primary, size: 20),
                const SizedBox(width: 10),
                const Text('Altr Mesh Workspaces'),
              ],
            ),
            content: SizedBox(
              width: 440,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Workspaces are shared across Altr Stream, Altr Chat, and other Altr Mesh products.',
                    style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 16),
                  if (workspaces.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text('No workspaces yet. Create your first workspace below.'),
                    )
                  else
                    ...workspaces.map((ws) {
                      final isSelected = active?.id == ws.id;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? colorScheme.primaryContainer.withValues(alpha: 0.5)
                              : colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isSelected ? colorScheme.primary : colorScheme.outlineVariant.withValues(alpha: 0.5),
                          ),
                        ),
                        child: ListTile(
                          title: Text(ws.name, style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                          subtitle: Text(
                            'Services: ${ws.enabledServices.join(", ")} · Members: ${ws.memberUids.length}',
                            style: const TextStyle(fontSize: 11),
                          ),
                          trailing: isSelected
                              ? const Icon(Icons.check_circle, color: Colors.green, size: 20)
                              : TextButton(
                                  onPressed: () {
                                    _workspaceService.setActiveWorkspace(ws);
                                    Navigator.of(ctx).pop();
                                  },
                                  child: const Text('Switch'),
                                ),
                        ),
                      );
                    }),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () async {
                      Navigator.of(ctx).pop();
                      await showDialog<Workspace?>(
                        context: context,
                        builder: (_) => CreateWorkspaceDialog(
                          ownerUid: user.id,
                          ownerEmail: user.email,
                          ownerDisplayName: user.displayName,
                        ),
                      );
                    },
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Create New Workspace'),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Close')),
            ],
          );
        },
      ),
    );
  }

  Future<void> _deleteSource(SourceModel source) async {
    final colorScheme = Theme.of(context).colorScheme;
    final confirmed = await AltrAlert.show(
      context,
      icon: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.5),
          shape: BoxShape.circle,
        ),
        child: HugeIcon(
          icon: HugeIcons.strokeRoundedDelete02,
          color: Theme.of(context).colorScheme.error,
          size: 26,
        ),
      ),
      title: 'Delete Data Source?',
      message:
          'Are you sure you want to delete "${source.name}" and all associated physical schema snapshots? This action cannot be undone.',
      cancelLabel: 'Cancel',
      confirmLabel: 'Delete Source',
      isDestructive: true,
    );

    if (confirmed == true) {
      try {
        await _apiClient.deleteSource(source.id);
        _logActivity(
          type: ActivityType.sourceDeleted,
          title: 'Source Deleted',
          description:
              'Deleted data source "${source.name}" and its introspection metadata.',
          sourceId: source.id,
          sourceName: source.name,
        );
        if (_selectedSource?.id == source.id) {
          _selectedSource = null;
          _activeRoute = '/sources';
        }
        await _fetchSources();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Source "${source.name}" deleted.'),
              backgroundColor: AppTheme.getStatusColor('ACTIVE', context),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to delete source: $e'),
              backgroundColor: colorScheme.error,
            ),
          );
        }
      }
    }
  }

  Widget _buildCurrentScreen() {
    if (_activeRoute == '/sources/detail' && _selectedSource != null) {
      return SourceDetailScreen(
        key: _sourceDetailKey,
        source: _selectedSource!,
        apiClient: _apiClient,
        nodeStatus: _nodeStatus,
        onNodeStatusTap: _showNodeStatusDialog,
        onSourceUpdated: (updated) {
          setState(() {
            _selectedSource = updated;
            final idx = _sources.indexWhere((s) => s.id == updated.id);
            if (idx != -1) {
              _sources[idx] = updated;
            }
          });
        },
        onBack: () => setState(() => _activeRoute = '/sources'),
        onDelete: () => _deleteSource(_selectedSource!),
      );
    }

    if (_activeRoute == '/sources' ||
        (_activeRoute == '/sources/detail' && _selectedSource == null)) {
      return SourcesScreen(
        key: _sourcesKey,
        sources: _sources,
        isLoading: _isLoadingSources,
        nodeStatus: _nodeStatus,
        onNodeStatusTap: _showNodeStatusDialog,
        onRefresh: () {
          _probeNodeHealth();
          _fetchSources(probe: true);
        },
        onAddSource: _showAddSourceWizard,
        onSelectSource: (s) {
          setState(() {
            _selectedSource = s;
            _activeRoute = '/sources/detail';
          });
        },
        onDeleteSource: _deleteSource,
      );
    }

    if (_activeRoute == '/activity') {
      return ActivityScreen(
        activities: _activities,
        nodeStatus: _nodeStatus,
        onNodeStatusTap: _showNodeStatusDialog,
        onClear: () => setState(() => _activities.clear()),
      );
    }

    if (_activeRoute == '/settings') {
      return SettingsScreen(
        apiClient: _apiClient,
        nodeStatus: _nodeStatus,
        onNodeStatusTap: _showNodeStatusDialog,
        themeMode: widget.themeMode,
        onThemeModeChanged: widget.onThemeModeChanged,
        onPasscodeTap: _openPasscodeDialog,
        onApiSecurityTap: _openApiSecurityDialog,
        onWorkspacesTap: _openWorkspacesDialog,
        activeWorkspaceName: _workspaceService.activeWorkspace?.name,
        currentUser: _currentUser ?? _authService.currentProfile,
        initialCategoryId: _settingsCategory,
      );
    }

    if (_activeRoute == '/docs' ||
        _activeRoute == '/api-docs' ||
        _activeRoute == '/api-explorer') {
      return ApiDocsScreen(
        apiClient: _apiClient,
        sources: _sources,
        nodeStatus: _nodeStatus,
        onNodeStatusTap: _showNodeStatusDialog,
        themeMode: widget.themeMode,
        onThemeModeChanged: widget.onThemeModeChanged,
        onBackToAdmin: () =>
            setState(() => _activeRoute = _previousRoute ?? '/'),
      );
    }

    if (_activeRoute == '/registry/detail' && _selectedLogicalModel != null) {
      return LogicalModelDetailScreen(
        key: _logicalModelDetailKey,
        model: _selectedLogicalModel!,
        sources: _sources,
        apiClient: _apiClient,
        nodeStatus: _nodeStatus,
        onNodeStatusTap: _showNodeStatusDialog,
        onBack: () => setState(() => _activeRoute = '/registry'),
        onModelDeleted: () {
          _fetchModels();
          setState(() {
            _selectedLogicalModel = null;
            _activeRoute = '/registry';
          });
        },
      );
    }

    if (_activeRoute == '/registry' ||
        (_activeRoute == '/registry/detail' && _selectedLogicalModel == null)) {
      return RegistryScreen(
        key: _registryKey,
        apiClient: _apiClient,
        sources: _sources,
        nodeStatus: _nodeStatus,
        onNodeStatusTap: _showNodeStatusDialog,
        onSelectModel: (m) {
          setState(() {
            _selectedLogicalModel = m;
            _activeRoute = '/registry/detail';
          });
        },
      );
    }

    if (_activeRoute == '/altrql' || _activeRoute == '/playground') {
      return AltrQLPlaygroundScreen(
        sources: _sources,
        apiClient: _apiClient,
        nodeStatus: _nodeStatus,
        onNodeStatusTap: _showNodeStatusDialog,
        onBack: () => setState(() => _activeRoute = _previousRoute ?? '/'),
        onNavigateToSource: (source) {
          setState(() {
            _selectedSource = source;
            _activeRoute = '/sources/detail';
          });
        },
      );
    }

    // Default Overview Screen
    return OverviewScreen(
      key: _overviewKey,
      sources: _sources,
      activities: _activities,
      isLoading: _isLoadingSources,
      usageMetrics: _usageMetrics,
      nodeStatus: _nodeStatus,
      selectedTimeWindow: _usageTimeWindow,
      onNodeStatusTap: _showNodeStatusDialog,
      onRefresh: () {
        _probeNodeHealth();
        _fetchSources(probe: true);
        _fetchUsageMetrics();
      },
      onTimeWindowChanged: (window) {
        setState(() {
          _usageTimeWindow = window;
        });
        _fetchUsageMetrics();
      },
      onClearUsageData: () async {
        try {
          await _apiClient.clearUsageMetrics();
          await _fetchUsageMetrics();
          if (mounted) {
            final colorScheme = Theme.of(context).colorScheme;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text(
                  'All monitored usage data successfully cleared.',
                ),
                backgroundColor: colorScheme.primary,
              ),
            );
          }
        } catch (e) {
          if (mounted) {
            final colorScheme = Theme.of(context).colorScheme;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Failed to clear usage metrics: $e'),
                backgroundColor: colorScheme.error,
              ),
            );
          }
        }
      },
      onAddSource: _showAddSourceWizard,
      onSelectSource: (s) {
        setState(() {
          _selectedSource = s;
          _activeRoute = '/sources/detail';
        });
      },
      onViewAllSources: () => setState(() => _activeRoute = '/sources'),
      onNavigateToRegistry: () => setState(() => _activeRoute = '/registry'),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_activeRoute == '/api-explorer' ||
        _activeRoute == '/api-docs' ||
        _activeRoute == '/docs') {
      return ApiDocsScreen(
        apiClient: _apiClient,
        sources: _sources,
        nodeStatus: _nodeStatus,
        onNodeStatusTap: _showNodeStatusDialog,
        themeMode: widget.themeMode,
        onThemeModeChanged: widget.onThemeModeChanged,
        onBackToAdmin: () {
          setState(() {
            _activeRoute = _previousRoute ?? '/';
          });
        },
      );
    }

    return AppShell(
      activeRoute: _activeRoute,
      pageTitle: _getPageTitle(),
      pageSubtitle: _getPageSubtitle(),
      onBack: _getOnBack(),
      pageActions: _getPageActions(),
      floatingActionButton: _getFloatingActionButton(),
      nodeStatus: _nodeStatus,
      currentUser: _currentUser ?? _authService.currentProfile,
      onSignIn: _showSignInDialog,
      onSignOut: _handleSignOut,
      onPasscodeTap: _openPasscodeDialog,
      onApiSecurityTap: _openApiSecurityDialog,
      onWorkspacesTap: _openWorkspacesDialog,
      activeWorkspaceName: _workspaceService.activeWorkspace?.name,
      onNavigateToSettingsCategory: (category) {
        setState(() {
          _previousRoute = _activeRoute;
          _activeRoute = '/settings';
          _settingsCategory = category;
        });
      },
      liveActionsController: _liveActionsController,
      apiClient: _apiClient,
      onNodeStatusTap: _showNodeStatusDialog,
      themeMode: widget.themeMode,
      onThemeModeChanged: widget.onThemeModeChanged,
      sourcesCount: _sources.length,
      modelsCount: _modelsCount,
      onNavigate: (route) {
        setState(() {
          if (route != _activeRoute) {
            _previousRoute = _activeRoute;
            _activeRoute = route;
            if (route != '/settings') {
              _settingsCategory = null;
            }
          }
        });
      },
      child: _buildCurrentScreen(),
    );
  }
}
