import 'dart:async';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'core/api/api_client.dart';
import 'core/api/models.dart';
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

import 'package:flutter/services.dart';
import 'core/theme/material_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    BrowserContextMenu.disableContextMenu();
  } catch (_) {}
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
              tertiaryContainer: materialTheme.colorScheme.surfaceContainerHighest,
              onTertiaryContainer: materialTheme.colorScheme.onSurface,
              secondaryContainer: materialTheme.colorScheme.surfaceContainerHigh,
              onSecondaryContainer: materialTheme.colorScheme.onSurface,
            ),
            menuTheme: M3EMenuTheme(
              backgroundColor: materialTheme.colorScheme.surfaceContainerHigh,
            ),
            navigationDrawerTheme: const M3ENavigationDrawerTheme(
              width: 320,
            ),
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

  List<SourceModel> _sources = [];
  int _modelsCount = 0;
  final List<ActivityLogModel> _activities = [];
  bool _isLoadingSources = true;
  String _activeRoute = '/';
  String? _previousRoute;
  SourceModel? _selectedSource;
  LogicalModelModel? _selectedLogicalModel;
  String _nodeStatus = 'ACTIVE';
  UserProfile? _currentUser;
  final GlobalKey<OverviewScreenState> _overviewKey = GlobalKey<OverviewScreenState>();
  final GlobalKey<RegistryScreenState> _registryKey = GlobalKey<RegistryScreenState>();
  final GlobalKey<SourcesScreenState> _sourcesKey = GlobalKey<SourcesScreenState>();
  final GlobalKey<SourceDetailScreenState> _sourceDetailKey = GlobalKey<SourceDetailScreenState>();
  final GlobalKey<LogicalModelDetailScreenState> _logicalModelDetailKey = GlobalKey<LogicalModelDetailScreenState>();

  UsageMetricsModel? _usageMetrics;
  Timer? _usageTimer;
  String _usageTimeWindow = '30m';

  @override
  void initState() {
    super.initState();
    _logActivity(
      type: ActivityType.nodeStart,
      title: 'Altr Stream Node Initialized',
      description: 'Connected to local runtime metadata and PostgreSQL connector ready.',
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
    super.dispose();
  }

  Future<void> _fetchUsageMetrics() async {
    try {
      final metrics = await _apiClient.getUsageMetrics(timeWindow: _usageTimeWindow);
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
            description: 'Registered "${newSource.name}" (${newSource.type} on $endpointDesc)',
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
              content: Text('Data source "${newSource.name}" registered successfully!'),
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
    if (_activeRoute == '/registry') return 'Logical Models';
    if (_activeRoute == '/activity') return 'Activity';
    if (_activeRoute == '/settings') return 'Settings';
    if (_activeRoute == '/altrql' || _activeRoute == '/playground') return 'AltrQL Console';
    return 'Overview';
  }

  String _getPageSubtitle() {
    if (_activeRoute == '/') return 'System overview, status & analytics';
    if (_activeRoute == '/sources/detail') {
      return _selectedSource != null
          ? '${_selectedSource!.type} • ${_selectedSource!.host ?? _selectedSource!.filePath ?? "Connected"}'
          : 'Inspect tables, schema & test connectivity';
    }
    if (_activeRoute == '/sources') return 'Manage connected data sources and connections';
    if (_activeRoute == '/registry/detail') {
      return _selectedLogicalModel != null
          ? 'v${_selectedLogicalModel!.version} • ${_selectedLogicalModel!.entityCount} Entities • ${_selectedLogicalModel!.totalFieldCount} Fields'
          : 'Manage mappings, views & virtual schemas';
    }
    if (_activeRoute == '/registry') return 'Define federated schemas and entity mappings';
    if (_activeRoute == '/activity') return 'Real-time audit log and system events';
    if (_activeRoute == '/settings') return 'Global configurations and engine parameters';
    if (_activeRoute == '/altrql' || _activeRoute == '/playground') return 'Execute federated SQL queries across sources';
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

  void _showSignInDialog() {
    final colorScheme = Theme.of(context).colorScheme;
    final nameController = TextEditingController(text: 'Asher Developer');
    final emailController = TextEditingController(text: 'asher@altrstream.io');
    final photoController = TextEditingController(text: 'https://images.unsplash.com/photo-1535713875002-d1d0cf377fde?auto=format&fit=crop&w=120&q=80');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colorScheme.surfaceContainerHigh,
        title: Row(
          children: [
            HugeIcon(icon: HugeIcons.strokeRoundedUserCircle, color: colorScheme.primary, size: 24),
            const SizedBox(width: 10),
            const Text('Google Sign In'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Sign in with your Google account to manage node configuration, schemas, and queries.',
              style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Display Name *'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: emailController,
              decoration: const InputDecoration(labelText: 'Google Email *'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: photoController,
              decoration: const InputDecoration(labelText: 'Profile Picture URL (Optional)'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Cancel', style: TextStyle(color: colorScheme.onSurfaceVariant)),
          ),
          M3EButton(
            onPressed: () {
              final name = nameController.text.trim();
              final email = emailController.text.trim();
              final photo = photoController.text.trim();
              if (name.isNotEmpty && email.isNotEmpty) {
                final user = UserProfile(
                  id: 'usr_${DateTime.now().millisecondsSinceEpoch}',
                  displayName: name,
                  email: email,
                  photoUrl: photo.isNotEmpty ? photo : null,
                  provider: 'google.com',
                );
                setState(() {
                  _currentUser = user;
                });
                _logActivity(
                  type: ActivityType.nodeStart,
                  title: 'User Authenticated',
                  description: 'Signed in as ${user.displayName} (${user.email})',
                );
                Navigator.of(ctx).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Welcome, ${user.displayName}! Signed in with Google.'),
                    backgroundColor: colorScheme.primary,
                  ),
                );
              }
            },
            style: M3EButtonStyle.filled,
            size: M3EButtonSize.sm,
            child: const Text('Sign In with Google'),
          ),
        ],
      ),
    );
  }

  void _handleSignOut() {
    final prevUser = _currentUser;
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Successfully signed out.')),
      );
    }
  }

  Future<void> _deleteSource(SourceModel source) async {
    final colorScheme = Theme.of(context).colorScheme;
    final confirmed = await M3EDialog.show<bool>(
      context,
      barrierDismissible: true,
      dialog: M3EDialog(
        icon: HugeIcon(
          icon: HugeIcons.strokeRoundedDelete02,
          color: colorScheme.error,
          size: 28,
        ),
        title: 'Delete Data Source?',
        content: Text(
          'Are you sure you want to delete "${source.name}" and all associated physical schema snapshots? This action cannot be undone.',
          style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13, height: 1.5),
        ),
        actions: [
          M3EButton(
            style: M3EButtonStyle.text,
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          M3EButton(
            style: M3EButtonStyle.filled,
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete Source'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _apiClient.deleteSource(source.id);
        _logActivity(
          type: ActivityType.sourceDeleted,
          title: 'Source Deleted',
          description: 'Deleted data source "${source.name}" and its introspection metadata.',
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

    if (_activeRoute == '/sources' || (_activeRoute == '/sources/detail' && _selectedSource == null)) {
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
      );
    }

    if (_activeRoute == '/docs' || _activeRoute == '/api-docs' || _activeRoute == '/api-explorer') {
      return ApiDocsScreen(
        apiClient: _apiClient,
        sources: _sources,
        nodeStatus: _nodeStatus,
        onNodeStatusTap: _showNodeStatusDialog,
        themeMode: widget.themeMode,
        onThemeModeChanged: widget.onThemeModeChanged,
        onBackToAdmin: () => setState(() => _activeRoute = _previousRoute ?? '/'),
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

    if (_activeRoute == '/registry' || (_activeRoute == '/registry/detail' && _selectedLogicalModel == null)) {
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
                content: const Text('All monitored usage data successfully cleared.'),
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
    if (_activeRoute == '/api-explorer' || _activeRoute == '/api-docs' || _activeRoute == '/docs') {
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
      currentUser: _currentUser,
      onSignIn: _showSignInDialog,
      onSignOut: _handleSignOut,
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
          }
        });
      },
      child: _buildCurrentScreen(),
    );
  }
}
