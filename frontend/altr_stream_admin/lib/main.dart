import 'package:flutter/material.dart';
import 'core/api/api_client.dart';
import 'core/api/models.dart';
import 'core/theme/app_theme.dart';
import 'features/activity/screens/activity_screen.dart';
import 'features/altrql_playground/screens/altrql_playground_screen.dart';
import 'features/overview/screens/overview_screen.dart';
import 'features/settings/screens/settings_screen.dart';
import 'features/sources/screens/source_detail_screen.dart';
import 'features/sources/screens/sources_screen.dart';
import 'features/sources/widgets/add_source_wizard_dialog.dart';
import 'shared/widgets/app_shell.dart';
import 'shared/widgets/node_status_dialog.dart';

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
  String _nodeStatus = 'ACTIVE';

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
          _logActivity(
            type: ActivityType.sourceRegistered,
            title: 'Source Registered',
            description: 'Registered "${newSource.name}" (${newSource.type} on ${newSource.host}:${newSource.port})',
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

  void _showNodeStatusDialog() {
    final activeCount = _sources.where((s) => s.isActive).length;
    showDialog(
      context: context,
      builder: (ctx) => NodeStatusDialog(
        apiClient: _apiClient,
        connectedSourcesCount: _sources.length,
        activeSourcesCount: activeCount,
      ),
    );
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

    if (_activeRoute == '/altrql' || _activeRoute == '/playground') {
      return AltrQLPlaygroundScreen(
        sources: _sources,
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
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      activeRoute: _activeRoute,
      nodeStatus: _nodeStatus,
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
