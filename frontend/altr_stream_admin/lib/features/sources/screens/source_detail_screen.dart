import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/models.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/status_badge.dart';
import '../../overview/screens/overview_screen.dart';
import '../../overview/services/overview_layout_service.dart';
import '../../overview/widgets/bento_grid_engine.dart';
import '../../source_playground/screens/source_playground_view.dart';
import '../../../shared/widgets/schema_explorer_card.dart';
import '../services/source_detail_layout_service.dart';

class SourceDetailScreen extends StatefulWidget {
  final SourceModel source;
  final ApiClient apiClient;
  final VoidCallback onBack;
  final VoidCallback onDelete;
  final VoidCallback onNodeStatusTap;
  final ValueChanged<SourceModel>? onSourceUpdated;
  final String nodeStatus;

  const SourceDetailScreen({
    super.key,
    required this.source,
    required this.apiClient,
    required this.onBack,
    required this.onDelete,
    required this.onNodeStatusTap,
    this.onSourceUpdated,
    this.nodeStatus = 'ACTIVE',
  });

  @override
  State<SourceDetailScreen> createState() => SourceDetailScreenState();
}

class SourceDetailScreenState extends State<SourceDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late final M3ERefreshIndicatorController _refreshController;
  late SourceModel _currentSource;
  SourceSchemaModel? _schema;

  Future<void> triggerRefresh() async {
    if (mounted) setState(() => _isRefreshing = true);
    await Future.wait([_testConnection(), _discoverSchema()]);
    if (mounted) setState(() => _isRefreshing = false);
  }
  SourceCapabilitiesModel? _capabilities;
  List<BentoCardConfig> _cardConfigs =
      SourceDetailLayoutService.getLayoutSync();

  bool _isLoading = true;
  bool _isTesting = false;
  bool _isDiscovering = false;
  bool _isRefreshing = false;
  bool _isEditMode = false;
  bool _isPasswordVisible = false;

  ConnectionTestResultModel? _lastTestResult;
  DateTime? _lastHealthCheckTime;
  Timer? _liveUsageTimer;
  Timer? _resetTestResultTimer;
  UsageMetricsModel? _sourceUsageMetrics;
  String _selectedUsageTimeWindow = '30m';
  Offset? _sourceChartHoverOffset;
  String? _selectedSchemaNamespace;
  String? _selectedTableName;
  @override
  void initState() {
    super.initState();
    _currentSource = widget.source;
    _tabController = TabController(length: 3, vsync: this);
    _refreshController = M3ERefreshIndicatorController();
    _loadDetails();
    _fetchSourceUsageMetrics();
    _startLiveUsageTimer();
  }

  void _startLiveUsageTimer() {
    _liveUsageTimer?.cancel();
    _liveUsageTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted) {
        _fetchSourceUsageMetrics();
      }
    });
  }

  Future<void> _fetchSourceUsageMetrics() async {
    try {
      final metrics = await widget.apiClient.getUsageMetrics(
        timeWindow: _selectedUsageTimeWindow,
        sourceId: _currentSource.id,
      );
      if (mounted) {
        setState(() {
          _sourceUsageMetrics = metrics;
        });
      }
    } catch (_) {}
  }

  String _formatCount(int count) {
    if (count >= 1000000) {
      return '${(count / 1000000.0).toStringAsFixed(1)}M';
    }
    if (count >= 1000) {
      return '${(count / 1000.0).toStringAsFixed(1)}k';
    }
    return '$count';
  }

  @override
  void didUpdateWidget(covariant SourceDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.source != oldWidget.source) {
      _currentSource = widget.source;
    }
  }

  @override
  void dispose() {
    _liveUsageTimer?.cancel();
    _resetTestResultTimer?.cancel();
    _tabController.dispose();
    _refreshController.dispose();
    super.dispose();
  }

  Future<void> _loadDetails() async {
    setState(() => _isLoading = true);
    try {
      final caps = await widget.apiClient.getSourceCapabilities(
        _currentSource.id,
      );
      final schema = await widget.apiClient.getLatestSchema(_currentSource.id);
      if (mounted) {
        setState(() {
          _capabilities = caps;
          _schema = schema;
          if (schema != null && schema.entities.isNotEmpty) {
            _selectedSchemaNamespace = schema.entities.first.namespace;
            _selectedTableName = schema.entities.first.name;
          }
        });
      }
    } catch (_) {
      // Schema may not be discovered yet
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _testConnection() async {
    setState(() {
      _isTesting = true;
      _lastTestResult = null;
    });

    try {
      final result = await widget.apiClient.testSavedConnection(
        _currentSource.id,
      );
      SourceModel updatedSource = _currentSource;
      try {
        updatedSource = await widget.apiClient.getSource(_currentSource.id);
      } catch (_) {}

      if (mounted) {
        setState(() {
          _currentSource = updatedSource;
          _lastTestResult = result;
          _lastHealthCheckTime = DateTime.now();
        });
        widget.onSourceUpdated?.call(updatedSource);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _lastTestResult = ConnectionTestResultModel(
            success: false,
            message: 'Connection check failed',
            errorDetails: e.toString(),
          );
          _lastHealthCheckTime = DateTime.now();
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isTesting = false);
        _resetTestResultTimer?.cancel();
        _resetTestResultTimer = Timer(const Duration(seconds: 3), () {
          if (mounted) {
            setState(() {
              _lastTestResult = null;
            });
          }
        });
      }
    }
  }

  Future<void> _discoverSchema() async {
    setState(() => _isDiscovering = true);

    try {
      final schema = await widget.apiClient.discoverSchema(_currentSource.id);
      if (mounted) {
        setState(() {
          _schema = schema;
          if (schema.entities.isNotEmpty) {
            _selectedSchemaNamespace = schema.entities.first.namespace;
            _selectedTableName = schema.entities.first.name;
          }
        });
        final isMongo = _currentSource.type.toUpperCase() == 'MONGODB';
        final count = schema.entityCount;
        final entityTerm = isMongo
            ? (count == 1 ? 'collection' : 'collections')
            : (count == 1 ? 'table' : 'tables');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Schema discovered: $count $entityTerm found!'),
            backgroundColor: AppTheme.getStatusColor('ACTIVE', context),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        final colorScheme = Theme.of(context).colorScheme;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Schema discovery failed: $e'),
            backgroundColor: colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isDiscovering = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('yyyy-MM-dd HH:mm:ss');
    final colorScheme = Theme.of(context).colorScheme;

    final Widget content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Source Title Bar
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    _currentSource.name,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                      letterSpacing: -0.4,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 12),
                StatusBadge(status: _currentSource.type, isTypeBadge: true),
                const SizedBox(width: 8),
                StatusBadge(
                  status:
                      (_isRefreshing ||
                          _isTesting ||
                          _isDiscovering ||
                          (_isLoading && _currentSource.isUnreachable))
                      ? 'PINGING'
                      : _currentSource.status,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              _currentSource.type == 'SQLITE'
                  ? 'File: ${_currentSource.filePath ?? "Local Database"}'
                  : '${_currentSource.host ?? "localhost"}:${_currentSource.port ?? 5432} • Database: ${_currentSource.databaseName ?? ""}',
              style: TextStyle(
                fontSize: 13,
                fontFamily: 'monospace',
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // Combined Tabs Bar (Overview, Discovered Schemas, Playground)
        Container(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
          ),
          child: TabBar(
            controller: _tabController,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: colorScheme.primary,
            unselectedLabelColor: colorScheme.onSurfaceVariant,
            indicatorColor: colorScheme.primary,
            indicatorSize: TabBarIndicatorSize.tab,
            tabs: [
              const Tab(text: 'Overview'),
              const Tab(text: 'Discovered Schemas'),
              Tab(text: '${widget.source.type} Query Playground'),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Tab Views
        if (_isLoading && _schema == null && _capabilities == null)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(60),
              child: CircularProgressIndicator(color: colorScheme.primary),
            ),
          )
        else
          AnimatedBuilder(
            animation: _tabController,
            builder: (context, _) {
              if (_tabController.index == 0) {
                return _buildOverviewBentoTab(context, dateFormat);
              }
              final screenHeight = MediaQuery.of(context).size.height;
              final dynamicTabHeight = (screenHeight - 270.0).clamp(400.0, 1000.0);
              return SizedBox(
                height: dynamicTabHeight,
                child: IndexedStack(
                  index: _tabController.index,
                  children: [
                    const SizedBox.shrink(),
                    _buildSchemasTab(context),
                    _buildPlaygroundTab(context),
                  ],
                ),
              );
            },
          ),
      ],
    );

    return M3ERefreshIndicator.contained(
      controller: _refreshController,
      onRefresh: () async {
        if (mounted) setState(() => _isRefreshing = true);
        await Future.wait([_testConnection(), _discoverSchema()]);
        if (mounted) setState(() => _isRefreshing = false);
      },
      triggerMode: M3ERefreshTriggerMode.onEdge,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: ClampingScrollPhysics(),
        ),
        child: content,
      ),
    );
  }

  // --- TAB 1: OVERVIEW BENTO GRID ---
  Widget _buildOverviewBentoTab(BuildContext context, DateFormat dateFormat) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BentoGridEngine(
          configs: _cardConfigs,
          isEditMode: _isEditMode,
          rowUnitHeight: 220.0,
          onLayoutChanged: (updated) {
            setState(() {
              _cardConfigs = updated;
            });
            SourceDetailLayoutService.saveLayout(updated);
          },
          cardBuilder: (context, config) =>
              _buildBentoCardContent(context, config, dateFormat),
        ),
        const SizedBox(height: 12),
        _buildBottomEditToolbar(context),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildBottomEditToolbar(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (!_isEditMode) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: OutlinedButton.icon(
            onPressed: () => setState(() => _isEditMode = true),
            icon: HugeIcon(
              icon: HugeIcons.strokeRoundedDashboardSquare02,
              size: 16,
              color: colorScheme.onSurfaceVariant,
            ),
            label: const Text('Customize Bento Layout'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              side: BorderSide(
                color: colorScheme.outlineVariant.withValues(alpha: 0.6),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),
        ),
      );
    }

    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: colorScheme.primary.withValues(alpha: 0.6),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          alignment: WrapAlignment.center,
          spacing: 12,
          runSpacing: 8,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: HugeIcon(
                    icon: HugeIcons.strokeRoundedEdit02,
                    size: 15,
                    color: colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Customizing Bento Layout',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    Text(
                      'Drag = to rearrange • Drag corner to resize',
                      style: TextStyle(
                        fontSize: 11,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(width: 4),
            TextButton.icon(
              onPressed: () async {
                final reset = await SourceDetailLayoutService.resetLayout();
                if (mounted) {
                  setState(() {
                    _cardConfigs = reset;
                  });
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('Bento layout reset to default'),
                      backgroundColor: colorScheme.primary,
                    ),
                  );
                }
              },
              icon: HugeIcon(
                icon: HugeIcons.strokeRoundedRotateLeft01,
                size: 14,
                color: colorScheme.error,
              ),
              label: Text(
                'Reset to Default',
                style: TextStyle(fontSize: 12, color: colorScheme.error),
              ),
            ),
            ElevatedButton.icon(
              onPressed: () async {
                await SourceDetailLayoutService.saveLayout(_cardConfigs);
                if (mounted) {
                  setState(() => _isEditMode = false);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text(
                        'Bento layout saved persistently across all data sources!',
                      ),
                      backgroundColor: AppTheme.getStatusColor(
                        'ACTIVE',
                        context,
                      ),
                    ),
                  );
                }
              },
              icon: HugeIcon(
                icon: HugeIcons.strokeRoundedTick01,
                size: 14,
                color: colorScheme.onPrimary,
              ),
              label: const Text('Save Layout'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBentoCardContent(
    BuildContext context,
    BentoCardConfig config,
    DateFormat dateFormat,
  ) {
    Widget cardInner;
    switch (config.id) {
      case 'source_summary':
        cardInner = _buildSummaryBentoCard(context, dateFormat);
        break;
      case 'quick_actions':
        cardInner = _buildQuickActionsBentoCard(context);
        break;
      case 'health_diagnostics':
        cardInner = _buildHealthBentoCard(context, dateFormat);
        break;
      case 'source_capabilities':
        cardInner = _buildCapabilitiesBentoCard(context);
        break;
      case 'schema_summary':
        cardInner = _buildSchemaSummaryBentoCard(context);
        break;
      case 'source_usage':
        cardInner = _buildUsageBentoCard(context);
        break;
      default:
        cardInner = _buildSummaryBentoCard(context, dateFormat);
        break;
    }
    return Card(child: cardInner);
  }

  Widget _buildSummaryBentoCard(BuildContext context, DateFormat dateFormat) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              HugeIcon(
                icon: HugeIcons.strokeRoundedInformationCircle,
                size: 18,
                color: colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Source & Connection Details',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  _buildInfoRow(
                    context,
                    'Source Display Name',
                    _currentSource.name,
                  ),
                  _buildDivider(context),
                  if (_currentSource.type == 'SQLITE') ...[
                    _buildInfoRow(
                      context,
                      'Database Engine',
                      'SQLite (File Database)',
                      isCopyable: false,
                    ),
                    _buildDivider(context),
                    _buildInfoRow(
                      context,
                      'Storage Mode',
                      'Local / Embedded File',
                      isCopyable: false,
                    ),
                    _buildDivider(context),
                    _buildInfoRow(
                      context,
                      'Database File Path',
                      _currentSource.filePath ?? '',
                      isMonospace: true,
                      isCopyable: true,
                    ),
                  ] else ...[
                    _buildInfoRow(
                      context,
                      'Database Engine',
                      _currentSource.type,
                      isCopyable: false,
                    ),
                    _buildDivider(context),
                    _buildInfoRow(
                      context,
                      'Host / IP Address',
                      _currentSource.host ?? 'localhost',
                      isMonospace: true,
                      isCopyable: true,
                    ),
                    _buildDivider(context),
                    _buildInfoRow(
                      context,
                      'Listening Port',
                      (_currentSource.port ?? 5432).toString(),
                      isMonospace: true,
                      isCopyable: true,
                    ),
                    _buildDivider(context),
                    _buildInfoRow(
                      context,
                      'Database Name',
                      _currentSource.databaseName ?? '',
                      isMonospace: true,
                      isCopyable: true,
                    ),
                    _buildDivider(context),
                    _buildInfoRow(
                      context,
                      'Database User',
                      _currentSource.username ?? '',
                      isMonospace: true,
                      isCopyable: true,
                    ),
                    _buildDivider(context),
                    _buildInfoRow(
                      context,
                      'Database Password',
                      _currentSource.passwordMasked,
                      isMonospace: true,
                      isCopyable: true,
                      customWidget: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _isPasswordVisible
                                ? '••••••••'
                                : _currentSource.passwordMasked,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              fontFamily: 'monospace',
                              color: colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(width: 4),
                          IconButton(
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            icon: HugeIcon(
                              icon: _isPasswordVisible
                                  ? HugeIcons.strokeRoundedView
                                  : HugeIcons.strokeRoundedViewOffSlash,
                              size: 15,
                              color: colorScheme.onSurfaceVariant,
                            ),
                            onPressed: () {
                              setState(() {
                                _isPasswordVisible = !_isPasswordVisible;
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                  _buildDivider(context),
                  _buildInfoRow(
                    context,
                    'Connection Status',
                    _currentSource.isActive
                        ? 'Active & Reachable'
                        : 'Unreachable',
                  ),
                  _buildDivider(context),
                  _buildInfoRow(
                    context,
                    _currentSource.type.toUpperCase() == 'MONGODB'
                        ? 'Discovered Collections'
                        : 'Discovered Tables',
                    _schema != null
                        ? '${_schema!.entityCount} ${_currentSource.type.toUpperCase() == "MONGODB" ? (_schema!.entityCount == 1 ? "collection" : "collections") : (_schema!.entityCount == 1 ? "table" : "tables")} (${_schema!.totalFieldCount} fields)'
                        : 'No schema discovered yet',
                  ),
                  _buildDivider(context),
                  _buildInfoRow(
                    context,
                    'Registered Date',
                    dateFormat.format(_currentSource.createdAt),
                  ),
                  _buildDivider(context),
                  _buildInfoRow(
                    context,
                    'Last Updated',
                    dateFormat.format(_currentSource.updatedAt),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionsBentoCard(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              HugeIcon(
                icon: HugeIcons.strokeRoundedFlash,
                size: 18,
                color: colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Quick Actions',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Modify parameters, update credentials, or remove source.',
            style: TextStyle(
              fontSize: 12,
              height: 1.4,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const Spacer(),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _showEditSourceDialog(context),
                  icon: HugeIcon(
                    icon: HugeIcons.strokeRoundedEdit02,
                    size: 15,
                    color: colorScheme.primary,
                  ),
                  label: const Text(
                    'Edit Source Details',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: colorScheme.error,
                    side: BorderSide(
                      color: colorScheme.error.withValues(alpha: 0.5),
                    ),
                  ),
                  onPressed: () =>
                      _showDeleteConfirmationDialog(context),
                  icon: HugeIcon(
                    icon: HugeIcons.strokeRoundedDelete02,
                    size: 15,
                    color: colorScheme.error,
                  ),
                  label: const Text(
                    'Delete Data Source',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirmationDialog(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    M3EDialog.show<void>(
      context,
      barrierDismissible: true,
      dialog: M3EDialog(
        icon: HugeIcon(
          icon: HugeIcons.strokeRoundedAlert02,
          color: colorScheme.error,
          size: 28,
        ),
        title: 'Delete Data Source?',
        content: Text(
          'Are you sure you want to delete database "${_currentSource.name}" (${_currentSource.type})? This action will remove all configuration and mappings and cannot be undone.',
          style: TextStyle(
            color: colorScheme.onSurfaceVariant,
            fontSize: 13,
            height: 1.5,
          ),
        ),
        actions: [
          M3EButton(
            style: M3EButtonStyle.text,
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          M3EButton(
            style: M3EButtonStyle.filled,
            onPressed: () {
              Navigator.of(context).pop();
              widget.onDelete();
            },
            child: const Text('Delete Data Source'),
          ),
        ],
      ),
    );
  }

  void _showEditSourceDialog(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final nameController = TextEditingController(text: _currentSource.name);
    final hostController = TextEditingController(
      text: _currentSource.host ?? '',
    );
    final portController = TextEditingController(
      text: (_currentSource.port ?? 5432).toString(),
    );
    final dbNameController = TextEditingController(
      text: _currentSource.databaseName ?? '',
    );
    final usernameController = TextEditingController(
      text: _currentSource.username ?? '',
    );
    final filePathController = TextEditingController(
      text: _currentSource.filePath ?? '',
    );

    final isSqlite = _currentSource.type.toUpperCase() == 'SQLITE';

    M3EDialog.show<void>(
      context,
      barrierDismissible: true,
      dialog: M3EDialog(
        icon: HugeIcon(
          icon: HugeIcons.strokeRoundedEdit02,
          color: colorScheme.primary,
          size: 28,
        ),
        title: 'Edit Source Details',
        content: Material(
          color: Colors.transparent,
          child: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'DB Display Name',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (isSqlite) ...[
                    TextField(
                      controller: filePathController,
                      decoration: const InputDecoration(
                        labelText: 'Database File Path',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ] else ...[
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: TextField(
                            controller: hostController,
                            decoration: const InputDecoration(
                              labelText: 'Host IP Add.',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 1,
                          child: TextField(
                            controller: portController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Port No',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: dbNameController,
                      decoration: const InputDecoration(
                        labelText: 'Table / DB Name',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: usernameController,
                      decoration: const InputDecoration(
                        labelText: 'DB User Name',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        actions: [
          M3EButton(
            style: M3EButtonStyle.text,
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          M3EButton(
            style: M3EButtonStyle.filled,
            onPressed: () {
              Navigator.of(context).pop();
              final updated = SourceModel(
                id: _currentSource.id,
                name: nameController.text.trim().isNotEmpty
                    ? nameController.text.trim()
                    : _currentSource.name,
                type: _currentSource.type,
                host: isSqlite ? null : hostController.text.trim(),
                port: isSqlite
                    ? null
                    : int.tryParse(portController.text.trim()) ??
                          _currentSource.port,
                databaseName: isSqlite ? null : dbNameController.text.trim(),
                username: isSqlite ? null : usernameController.text.trim(),
                filePath: isSqlite ? filePathController.text.trim() : null,
                status: _currentSource.status,
                createdAt: _currentSource.createdAt,
                updatedAt: DateTime.now(),
              );
              setState(() {
                _currentSource = updated;
              });
              widget.onSourceUpdated?.call(updated);
            },
            child: const Text('Save Changes'),
          ),
        ],
      ),
    );
  }

  Widget _buildCapabilitiesBentoCard(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              HugeIcon(
                icon: HugeIcons.strokeRoundedShieldKey,
                size: 18,
                color: colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Capabilities & Security',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildCapabilityItem(
                    context,
                    'Schema Introspection',
                    _capabilities?.schemaDiscovery ?? true,
                  ),
                  _buildCapabilityItem(
                    context,
                    'Physical Query Reads',
                    _capabilities?.read ?? true,
                  ),
                  _buildCapabilityItem(
                    context,
                    'Native Writes',
                    _capabilities?.write ?? true,
                  ),
                  _buildCapabilityItem(context, 'Connection Pooling', true),
                  _buildCapabilityItem(context, 'Query Optimisation', true),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHealthBentoCard(BuildContext context, DateFormat dateFormat) {
    final colorScheme = Theme.of(context).colorScheme;

    final statusStr =
        (_isRefreshing ||
            _isTesting ||
            (_isLoading && _currentSource.isUnreachable))
        ? 'PINGING'
        : _currentSource.status;

    final isSuccess = _lastTestResult?.success == true;
    final isFailure = _lastTestResult?.success == false;

    Color buttonBg = Colors.transparent;
    Color buttonFg = colorScheme.primary;
    Color buttonBorder = colorScheme.outlineVariant;
    String buttonText = 'Test Connection';
    Widget? buttonIcon;

    if (_isTesting) {
      buttonText = 'Testing Connection...';
      buttonIcon = SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: colorScheme.primary,
        ),
      );
    } else if (isSuccess) {
      buttonBg = AppTheme.successBg(context);
      buttonFg = AppTheme.getStatusColor('ACTIVE', context);
      buttonBorder = AppTheme.getStatusColor('ACTIVE', context);
      buttonText = 'Connection Successful';
      buttonIcon = HugeIcon(
        icon: HugeIcons.strokeRoundedTick01,
        size: 15,
        color: buttonFg,
      );
    } else if (isFailure) {
      buttonBg = AppTheme.errorBg(context);
      buttonFg = colorScheme.error;
      buttonBorder = colorScheme.error;
      buttonText = 'Connection Failed';
      buttonIcon = HugeIcon(
        icon: HugeIcons.strokeRoundedCancel01,
        size: 15,
        color: buttonFg,
      );
    } else {
      buttonIcon = HugeIcon(
        icon: HugeIcons.strokeRoundedFlash,
        size: 15,
        color: colorScheme.primary,
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              HugeIcon(
                icon: HugeIcons.strokeRoundedTimelineList,
                size: 18,
                color: colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Health & Diagnostics',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  children: [
                    _buildInfoRow(
                      context,
                      'Health',
                      _currentSource.isActive ? 'Healthy' : 'Failing',
                      isCopyable: false,
                      customWidget: Text(
                        _currentSource.isActive ? 'Healthy' : 'Failing',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: _currentSource.isActive
                              ? AppTheme.getStatusColor('ACTIVE', context)
                              : colorScheme.error,
                        ),
                      ),
                    ),
                    _buildDivider(context),
                    _buildInfoRow(
                      context,
                      'Status',
                      statusStr,
                      isCopyable: false,
                      customWidget: StatusBadge(status: statusStr),
                    ),
                    _buildDivider(context),
                    _buildInfoRow(
                      context,
                      'Last Check',
                      _lastHealthCheckTime != null
                          ? dateFormat.format(_lastHealthCheckTime!)
                          : 'Never / Not checked yet',
                      isCopyable: false,
                    ),
                  ],
                ),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: (_isTesting || _lastTestResult != null)
                        ? null
                        : _testConnection,
                    style: OutlinedButton.styleFrom(
                      backgroundColor: buttonBg,
                      foregroundColor: buttonFg,
                      side: BorderSide(color: buttonBorder),
                      disabledBackgroundColor: buttonBg,
                      disabledForegroundColor: buttonFg,
                    ),
                    icon: buttonIcon,
                    label: Text(
                      buttonText,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSchemaSummaryBentoCard(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isMongo = _currentSource.type.toUpperCase() == 'MONGODB';
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    HugeIcon(
                      icon: HugeIcons.strokeRoundedHierarchySquare01,
                      size: 18,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Schema Summary',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              M3EButton(
                style: M3EButtonStyle.tonal,
                size: M3EButtonSize.sm,
                onPressed: () {
                  _tabController.animateTo(1);
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Explore Schemas'),
                    const SizedBox(width: 4),
                    HugeIcon(
                      icon: HugeIcons.strokeRoundedArrowRight01,
                      size: 14,
                      color: colorScheme.primary,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _schema != null && _schema!.entities.isNotEmpty
                ? Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                '${_schema!.entityCount}',
                                style: TextStyle(
                                  fontSize: 48,
                                  fontWeight: FontWeight.bold,
                                  color: colorScheme.primary,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                isMongo ? 'Collections' : 'Tables',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      VerticalDivider(),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                '${_schema!.totalFieldCount}',
                                style: TextStyle(
                                  fontSize: 48,
                                  fontWeight: FontWeight.bold,
                                  color: colorScheme.primary,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Fields in total',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  )
                : Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'No schema discovered yet',
                          style: TextStyle(
                            fontSize: 13,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ElevatedButton.icon(
                          onPressed: _isDiscovering ? null : _discoverSchema,
                          icon: HugeIcon(
                            icon: HugeIcons.strokeRoundedSearch01,
                            size: 14,
                            color: colorScheme.onPrimary,
                          ),
                          label: const Text('Discover Schema'),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildUsageBentoCard(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final metrics = _sourceUsageMetrics;
    final opsText = metrics?.formattedOpsPerMinute ?? '0.0 ops/m';
    final readsCountText = metrics != null
        ? _formatCount(metrics.totalReads)
        : '0';
    final writesCountText = metrics != null
        ? _formatCount(metrics.totalWrites)
        : '0';

    final readPoints = (metrics != null && metrics.readHistory.isNotEmpty)
        ? metrics.readHistory
        : const [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0];
    final writePoints = (metrics != null && metrics.writeHistory.isNotEmpty)
        ? metrics.writeHistory
        : const [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0];
    final timestamps = metrics?.timestamps ?? const [];
    final rawReads = metrics?.rawReads ?? const [];
    final rawWrites = metrics?.rawWrites ?? const [];
    final yMax = metrics?.yMax ?? 10;

    return GestureDetector(
      onSecondaryTapUp: (details) {
        final overlay =
            Overlay.of(context).context.findRenderObject() as RenderBox?;
        if (overlay == null) return;
        showMenu<String>(
          context: context,
          position: RelativeRect.fromRect(
            details.globalPosition & const Size(1, 1),
            Offset.zero & overlay.size,
          ),
          items: [
            PopupMenuItem<String>(
              value: 'clear',
              onTap: () async {
                try {
                  await widget.apiClient.clearUsageMetrics();
                  await _fetchSourceUsageMetrics();
                } catch (_) {}
              },
              child: Row(
                children: [
                  HugeIcon(
                    icon: HugeIcons.strokeRoundedDelete02,
                    size: 16,
                    color: colorScheme.error,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Clear Monitored Source Usage',
                    style: TextStyle(
                      fontSize: 13,
                      color: colorScheme.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Data Source Usage & Operations',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Read / Write Operations • Right-click to clear',
                        style: TextStyle(
                          fontSize: 11,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    M3EMenu(
                      position: M3EMenuAnchorPosition.bottomStart,
                      colorStyle: M3EMenuColorStyle.standard,
                      closeOnSelect: true,
                      selectedValue: _selectedUsageTimeWindow,
                      onSelected: (Object? val) {
                        if (val is String) {
                          setState(() => _selectedUsageTimeWindow = val);
                          _fetchSourceUsageMetrics();
                        }
                      },
                      anchorBuilder: (context, open) {
                        return M3EButton.icon(
                          style: M3EButtonStyle.tonal,
                          size: M3EButtonSize.sm,
                          icon: HugeIcon(
                            icon: HugeIcons.strokeRoundedArrowDown01,
                            size: 14,
                            color: colorScheme.primary,
                          ),
                          label: Text(_selectedUsageTimeWindow),
                          onPressed: open,
                        );
                      },
                      children: <M3EMenuNode>[
                        M3EMenuSelectable(
                          label: '30m',
                          value: '30m',
                          selected: _selectedUsageTimeWindow == '30m',
                        ),
                        M3EMenuSelectable(
                          label: '1h',
                          value: '1h',
                          selected: _selectedUsageTimeWindow == '1h',
                        ),
                        M3EMenuSelectable(
                          label: '1d',
                          value: '1d',
                          selected: _selectedUsageTimeWindow == '1d',
                        ),
                        M3EMenuSelectable(
                          label: '1w',
                          value: '1w',
                          selected: _selectedUsageTimeWindow == '1w',
                        ),
                      ],
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          HugeIcon(
                            icon: HugeIcons.strokeRoundedChartLineData01,
                            size: 14,
                            color: colorScheme.primary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            opsText,
                            style: textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: SizedBox(
                width: double.infinity,
                child: MouseRegion(
                  onHover: (evt) => setState(
                    () => _sourceChartHoverOffset = evt.localPosition,
                  ),
                  onExit: (_) => setState(() => _sourceChartHoverOffset = null),
                  child: CustomPaint(
                    painter: UsageLineChartPainter(
                      readColor: colorScheme.primary,
                      writeColor: colorScheme.tertiary,
                      gridColor: colorScheme.outlineVariant.withValues(
                        alpha: 0.3,
                      ),
                      textColor: colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.8,
                      ),
                      readPoints: readPoints,
                      writePoints: writePoints,
                      timestamps: timestamps,
                      rawReads: rawReads,
                      rawWrites: rawWrites,
                      yMax: yMax,
                      hoverOffset: _sourceChartHoverOffset,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 16,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Reads ($readsCountText)',
                      style: textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: colorScheme.tertiary,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Writes ($writesCountText)',
                      style: textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // --- TAB 2: DISCOVERED SCHEMAS ---
  Widget _buildSchemasTab(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (_isDiscovering) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Introspecting database catalog and schemas...'),
          ],
        ),
      );
    }

    if (_schema == null || _schema!.entities.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            HugeIcon(
              icon: HugeIcons.strokeRoundedHierarchySquare01,
              size: 48,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              'No Schema Snapshot Discovered Yet',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _currentSource.type.toUpperCase() == 'MONGODB'
                  ? 'Run schema discovery to introspect collections and fields from this database.'
                  : 'Run schema discovery to introspect tables and fields from this database.',
              style: TextStyle(
                fontSize: 13,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _isDiscovering ? null : _discoverSchema,
              icon: HugeIcon(
                icon: HugeIcons.strokeRoundedSearch01,
                size: 14,
                color: colorScheme.onPrimary,
              ),
              label: const Text('Discover Schema Now'),
            ),
          ],
        ),
      );
    }

    final Map<String, List<EntitySchemaModel>> namespaceMap = {};
    for (final entity in _schema!.entities) {
      namespaceMap.putIfAbsent(entity.namespace, () => []).add(entity);
    }

    final currentEntities = namespaceMap[_selectedSchemaNamespace] ?? [];
    final currentEntity = currentEntities.firstWhere(
      (e) => e.name == _selectedTableName,
      orElse: () => currentEntities.isNotEmpty
          ? currentEntities.first
          : _schema!.entities.first,
    );
    final isMongo = widget.source.type.toUpperCase() == 'MONGODB';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left Column: Namespaces & Tables/Collections Tree
        SizedBox(
          width: 280,
          child: SchemaExplorerCard(
            selectedSource: _currentSource,
            schema: _schema,
            isLoading: _isLoading,
            isExpandable: false,
            selectedNamespace: _selectedSchemaNamespace,
            selectedEntityName: _selectedTableName,
            onSelectEntity: (entity, ns) {
              setState(() {
                _selectedSchemaNamespace = ns;
                _selectedTableName = entity.name;
              });
            },
          ),
        ),
        const SizedBox(width: 16),





        const SizedBox(width: 16),

        // Right Column: Table/Collection Column Details
        Expanded(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          HugeIcon(
                            icon: isMongo
                                ? HugeIcons.strokeRoundedFolder02
                                : HugeIcons.strokeRoundedSheet,
                            color: colorScheme.primary,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${currentEntity.namespace}.${currentEntity.name}',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        '${currentEntity.fieldCount} ${currentEntity.fieldCount == 1 ? "field" : "fields"}',
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        return SingleChildScrollView(
                          scrollDirection: Axis.vertical,
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: ConstrainedBox(
                              constraints: BoxConstraints(minWidth: constraints.maxWidth),
                              child: DataTable(
                                columnSpacing: 24,
                                headingRowHeight: 40,
                                dataRowMinHeight: 44,
                                dataRowMaxHeight: 52,
                                columns: const [
                                  DataColumn(
                                    label: Text(
                                      'Field Name',
                                      style: TextStyle(fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  DataColumn(
                                    label: Text(
                                      'Data Type',
                                      style: TextStyle(fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  DataColumn(
                                    label: Text(
                                      'Nullable',
                                      style: TextStyle(fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  DataColumn(
                                    label: Text(
                                      'Key Type',
                                      style: TextStyle(fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ],
                                rows: currentEntity.fields.map((field) {
                                  return DataRow(
                                    cells: [
                                      DataCell(
                                        Text(
                                          field.name,
                                          style: TextStyle(
                                            fontFamily: 'monospace',
                                            fontWeight: field.isPrimaryKey
                                                ? FontWeight.bold
                                                : FontWeight.normal,
                                          ),
                                        ),
                                      ),
                                      DataCell(
                                        Text(
                                          field.dataType.toUpperCase(),
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontFamily: 'monospace',
                                            color: colorScheme.secondary,
                                          ),
                                        ),
                                      ),
                                      DataCell(
                                        Text(
                                          field.nullable ? 'YES' : 'NO',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: field.nullable
                                                ? colorScheme.onSurfaceVariant
                                                : colorScheme.primary,
                                          ),
                                        ),
                                      ),
                                      DataCell(
                                        field.isPrimaryKey
                                            ? StatusBadge(
                                                status: 'PK:${field.position}',
                                                isPkBadge: true,
                                              )
                                            : Text(
                                                '-',
                                                style: TextStyle(
                                                  color: colorScheme.onSurfaceVariant,
                                                ),
                                              ),
                                      ),
                                    ],
                                  );
                                }).toList(),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(
    BuildContext context,
    String label,
    String value, {
    bool isMonospace = false,
    bool isCopyable = false,
    Widget? customWidget,
    CrossAxisAlignment crossAxisAlignment = CrossAxisAlignment.center,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    Widget valChild =
        customWidget ??
        Text(
          value,
          textAlign: TextAlign.right,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            fontFamily: isMonospace ? 'monospace' : null,
            color: colorScheme.onSurface,
          ),
          overflow: TextOverflow.ellipsis,
        );

    if (isCopyable && value.isNotEmpty) {
      valChild = InkWell(
        onTap: () {
          Clipboard.setData(ClipboardData(text: value));
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  HugeIcon(
                    icon: HugeIcons.strokeRoundedCopy01,
                    size: 14,
                    color: colorScheme.onPrimary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text('Copied $label ($value) to clipboard!')),
                ],
              ),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 2),
              width: 340,
            ),
          );
        },
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(child: valChild),
              const SizedBox(width: 4),
              HugeIcon(
                icon: HugeIcons.strokeRoundedCopy01,
                size: 13,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: crossAxisAlignment,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(width: 12),
          Flexible(child: valChild),
        ],
      ),
    );
  }

  Widget _buildCapabilityItem(
    BuildContext context,
    String label,
    bool isSupported, {
    bool isRoadmap = false,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 13, color: colorScheme.onSurface),
          ),
          if (isRoadmap)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.getStatusColor(
                  'DISCOVERING',
                  context,
                ).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'Future Milestone',
                style: TextStyle(
                  fontSize: 10,
                  color: AppTheme.getStatusColor('DISCOVERING', context),
                ),
              ),
            )
          else if (isSupported)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.getStatusColor(
                  'ACTIVE',
                  context,
                ).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '✓ Supported',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.getStatusColor('ACTIVE', context),
                ),
              ),
            )
          else
            Text(
              'Not Supported',
              style: TextStyle(
                fontSize: 11,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPlaygroundTab(BuildContext context) {
    return SourcePlaygroundView(
      source: _currentSource,
      apiClient: widget.apiClient,
      schema: _schema,
      onRefreshSchema: _discoverSchema,
    );
  }

  Widget _buildDivider(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Divider(
      height: 1,
      thickness: 1,
      color: colorScheme.outlineVariant.withValues(alpha: 0.5),
    );
  }
}
