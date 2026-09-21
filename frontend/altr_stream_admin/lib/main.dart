import 'package:flutter/material.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:hugeicons/hugeicons.dart';
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

import 'core/theme/material_theme.dart';

void main() {
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
  final List<ActivityLogModel> _activities = [];
  bool _isLoadingSources = true;
  String _activeRoute = '/';
  String? _previousRoute;
  SourceModel? _selectedSource;
  LogicalModelModel? _selectedLogicalModel;
  String _nodeStatus = 'ACTIVE';
  UserProfile? _currentUser;
  final GlobalKey<RegistryScreenState> _registryKey = GlobalKey<RegistryScreenState>();

  @override
  void initState() {
    super.initState();
    _logActivity(
      type: ActivityType.nodeStart,
      title: 'Altr Stream Node Initialized',
      description: 'Connected to local runtime metadata and PostgreSQL connector ready.',
    );
    _probeNodeHealth();
    _fetchSources();
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

  Future<void> _fetchSources() async {
    setState(() => _isLoadingSources = true);
    try {
      final list = await _apiClient.listSources();
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

  void _showAddSourceWizard() {
    showDialog(
      context: context,
      builder: (ctx) => AddSourceWizardDialog(
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
    if (_activeRoute == '/registry') return 'Mapping Registry';
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
    if (_activeRoute == '/altrql' || _activeRoute == '/playground') {
      return () => setState(() => _activeRoute = _previousRoute ?? '/');
    }
    return null;
  }

  List<Widget>? _getPageActions() {
    if (_activeRoute == '/') {
      return [
        Focus(
          canRequestFocus: false,
          skipTraversal: true,
          child: M3EIconButton(
            icon: HugeIcon(
              icon: HugeIcons.strokeRoundedRefresh,
              color: Theme.of(context).colorScheme.onSurface,
              size: 18,
            ),
            onPressed: () {
              FocusManager.instance.primaryFocus?.unfocus();
              _probeNodeHealth();
              _fetchSources();
            },
            variant: M3EIconButtonVariant.standard,
            size: M3EIconButtonSize.xs,
            tooltip: 'Refresh',
          ),
        ),
      ];
    }
    if (_activeRoute == '/sources') {
      return [
        M3EButton.icon(
          onPressed: _showAddSourceWizard,
          icon: HugeIcon(
            icon: HugeIcons.strokeRoundedPlusSign,
            color: Theme.of(context).colorScheme.onPrimary,
            size: 16,
          ),
          label: const Text('Add Data Source'),
          style: M3EButtonStyle.filled,
          size: M3EButtonSize.xs,
        ),
        const SizedBox(width: 8),
        Focus(
          canRequestFocus: false,
          skipTraversal: true,
          child: M3EIconButton(
            icon: HugeIcon(
              icon: HugeIcons.strokeRoundedRefresh,
              color: Theme.of(context).colorScheme.onSurface,
              size: 18,
            ),
            onPressed: () {
              FocusManager.instance.primaryFocus?.unfocus();
              _probeNodeHealth();
              _fetchSources();
            },
            variant: M3EIconButtonVariant.standard,
            size: M3EIconButtonSize.xs,
            tooltip: 'Refresh',
          ),
        ),
      ];
    }
    if (_activeRoute == '/registry') {
      return [
        M3EButton.icon(
          onPressed: _showCreateLogicalModelDialog,
          icon: HugeIcon(
            icon: HugeIcons.strokeRoundedPlusSign,
            color: Theme.of(context).colorScheme.onPrimary,
            size: 16,
          ),
          label: const Text('New Logical Model'),
          style: M3EButtonStyle.filled,
          size: M3EButtonSize.xs,
        ),
        const SizedBox(width: 8),
        Focus(
          canRequestFocus: false,
          skipTraversal: true,
          child: M3EIconButton(
            icon: HugeIcon(
              icon: HugeIcons.strokeRoundedRefresh,
              color: Theme.of(context).colorScheme.onSurface,
              size: 18,
            ),
            onPressed: () {
              FocusManager.instance.primaryFocus?.unfocus();
              _registryKey.currentState?.fetchRegistry();
            },
            variant: M3EIconButtonVariant.standard,
            size: M3EIconButtonSize.xs,
            tooltip: 'Refresh',
          ),
        ),
      ];
    }
    if (_activeRoute == '/activity') {
      if (_activities.isNotEmpty) {
        return [
          M3EButton.icon(
            onPressed: () => setState(() => _activities.clear()),
            icon: HugeIcon(
              icon: HugeIcons.strokeRoundedClean,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              size: 16,
            ),
            label: const Text('Clear Timeline'),
            style: M3EButtonStyle.outlined,
            size: M3EButtonSize.xs,
          ),
        ];
      }
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colorScheme.surfaceContainerHigh,
        title: const Text('Delete Data Source?'),
        content: Text(
          'Are you sure you want to delete "${source.name}" and all associated physical schema snapshots? This action cannot be undone.',
          style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Cancel', style: TextStyle(color: colorScheme.onSurfaceVariant)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: colorScheme.error, foregroundColor: colorScheme.onError),
            onPressed: () => Navigator.of(ctx).pop(true),
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
        source: _selectedSource!,
        apiClient: _apiClient,
        nodeStatus: _nodeStatus,
        onNodeStatusTap: _showNodeStatusDialog,
        onBack: () => setState(() => _activeRoute = '/sources'),
        onDelete: () => _deleteSource(_selectedSource!),
      );
    }

    if (_activeRoute == '/sources' || (_activeRoute == '/sources/detail' && _selectedSource == null)) {
      return SourcesScreen(
        sources: _sources,
        isLoading: _isLoadingSources,
        nodeStatus: _nodeStatus,
        onNodeStatusTap: _showNodeStatusDialog,
        onRefresh: () {
          _probeNodeHealth();
          _fetchSources();
        },
        onAddSource: _showAddSourceWizard,
        onSelectSource: (s) {
          setState(() {
            _selectedSource = s;
            _activeRoute = '/sources/detail';
          });
        },
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
        model: _selectedLogicalModel!,
        sources: _sources,
        apiClient: _apiClient,
        nodeStatus: _nodeStatus,
        onNodeStatusTap: _showNodeStatusDialog,
        onBack: () => setState(() => _activeRoute = '/registry'),
        onModelDeleted: () => setState(() {
          _selectedLogicalModel = null;
          _activeRoute = '/registry';
        }),
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
      sources: _sources,
      activities: _activities,
      isLoading: _isLoadingSources,
      nodeStatus: _nodeStatus,
      onNodeStatusTap: _showNodeStatusDialog,
      onRefresh: () {
        _probeNodeHealth();
        _fetchSources();
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
      nodeStatus: _nodeStatus,
      currentUser: _currentUser,
      onSignIn: _showSignInDialog,
      onSignOut: _handleSignOut,
      onNodeStatusTap: _showNodeStatusDialog,
      themeMode: widget.themeMode,
      onThemeModeChanged: widget.onThemeModeChanged,
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
