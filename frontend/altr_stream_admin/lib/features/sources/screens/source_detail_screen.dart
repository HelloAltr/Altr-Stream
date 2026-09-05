import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/models.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/status_badge.dart';

class SourceDetailScreen extends StatefulWidget {
  final SourceModel source;
  final ApiClient apiClient;
  final VoidCallback onBack;
  final VoidCallback onDelete;
  final VoidCallback onNodeStatusTap;
  final String nodeStatus;

  const SourceDetailScreen({
    super.key,
    required this.source,
    required this.apiClient,
    required this.onBack,
    required this.onDelete,
    required this.onNodeStatusTap,
    this.nodeStatus = 'ACTIVE',
  });

  @override
  State<SourceDetailScreen> createState() => _SourceDetailScreenState();
}

class _SourceDetailScreenState extends State<SourceDetailScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  SourceSchemaModel? _schema;
  SourceCapabilitiesModel? _capabilities;
  bool _isLoading = true;
  bool _isTesting = false;
  bool _isDiscovering = false;
  ConnectionTestResultModel? _lastTestResult;
  DateTime? _lastHealthCheckTime;
  String? _selectedSchemaNamespace;
  String? _selectedTableName;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadDetails();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadDetails() async {
    setState(() => _isLoading = true);
    try {
      final caps = await widget.apiClient.getSourceCapabilities(widget.source.id);
      final schema = await widget.apiClient.getLatestSchema(widget.source.id);
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
      final result = await widget.apiClient.testSavedConnection(widget.source.id);
      if (mounted) {
        setState(() {
          _lastTestResult = result;
          _lastHealthCheckTime = DateTime.now();
        });
        final colorScheme = Theme.of(context).colorScheme;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.message),
            backgroundColor: result.success ? AppTheme.getStatusColor('ACTIVE', context) : colorScheme.error,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _lastTestResult = ConnectionTestResultModel(
            success: false,
            message: 'Connection check failed',
            errorDetails: e.toString(),
          );
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isTesting = false);
      }
    }
  }

  Future<void> _discoverSchema() async {
    setState(() => _isDiscovering = true);

    try {
      final schema = await widget.apiClient.discoverSchema(widget.source.id);
      if (mounted) {
        setState(() {
          _schema = schema;
          if (schema.entities.isNotEmpty) {
            _selectedSchemaNamespace = schema.entities.first.namespace;
            _selectedTableName = schema.entities.first.name;
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Schema discovered: ${schema.entityCount} tables found!'),
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Top Context Breadcrumb & Header
        Row(
          children: [
            InkWell(
              onTap: widget.onBack,
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.arrow_back, size: 16, color: colorScheme.primary),
                    const SizedBox(width: 4),
                    Text('Data Sources', style: TextStyle(color: colorScheme.primary, fontSize: 13)),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Source Title Bar
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 16,
          runSpacing: 12,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.source.name,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(width: 12),
                    StatusBadge(status: widget.source.type, isTypeBadge: true),
                    const SizedBox(width: 8),
                    StatusBadge(status: widget.source.status),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${widget.source.host}:${widget.source.port} • Database: ${widget.source.databaseName}',
                  style: TextStyle(
                    fontSize: 13,
                    fontFamily: 'monospace',
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _isTesting ? null : _testConnection,
                  icon: _isTesting
                      ? SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 2, color: colorScheme.primary),
                        )
                      : const Icon(Icons.bolt, size: 14),
                  label: Text(_isTesting ? 'Testing...' : 'Test Connection'),
                ),
                ElevatedButton.icon(
                  onPressed: _isDiscovering ? null : _discoverSchema,
                  icon: _isDiscovering
                      ? SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 2, color: colorScheme.onPrimary),
                        )
                      : const Icon(Icons.search, size: 14),
                  label: Text(_isDiscovering ? 'Discovering...' : 'Discover Schema'),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 20),

        // Tabs Bar
        Container(
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5))),
          ),
          child: TabBar(
            controller: _tabController,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: colorScheme.primary,
            unselectedLabelColor: colorScheme.onSurfaceVariant,
            indicatorColor: colorScheme.primary,
            indicatorSize: TabBarIndicatorSize.tab,
            tabs: const [
              Tab(text: 'Overview'),
              Tab(text: 'Connection Parameters'),
              Tab(text: 'Discovered Schemas'),
              Tab(text: 'Health & Diagnostics'),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Tab Views
        if (_isLoading)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(60),
              child: CircularProgressIndicator(color: colorScheme.primary),
            ),
          )
        else
          SizedBox(
            height: 620,
            child: TabBarView(
              controller: _tabController,
              physics: _isDesktopInteraction(context)
                  ? const NeverScrollableScrollPhysics()
                  : const PageScrollPhysics(),
              children: [
                _buildOverviewTab(context, dateFormat),
                _buildConnectionTab(context, dateFormat),
                _buildSchemasTab(context),
                _buildHealthTab(context, dateFormat),
              ],
            ),
          ),
      ],
    );
  }

  bool _isDesktopInteraction(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final platform = Theme.of(context).platform;
    final isDesktopPlatform = platform == TargetPlatform.macOS ||
        platform == TargetPlatform.windows ||
        platform == TargetPlatform.linux;
    return isDesktopPlatform || width >= 1024;
  }

  // --- TAB 1: OVERVIEW ---
  Widget _buildOverviewTab(BuildContext context, DateFormat dateFormat) {
    final colorScheme = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 800;
          final leftCard = Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Source Summary',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
                  ),
                  const SizedBox(height: 16),
                  _buildInfoRow(context, 'Database Engine', widget.source.type),
                  _buildDivider(context),
                  _buildInfoRow(context, 'Database Name', widget.source.databaseName, isMonospace: true),
                  _buildDivider(context),
                  _buildInfoRow(context, 'Connection Status', widget.source.isActive ? 'Active & Reachable' : 'Unreachable'),
                  _buildDivider(context),
                  _buildInfoRow(
                    context,
                    'Discovered Tables',
                    _schema != null ? '${_schema!.entityCount} tables (${_schema!.totalFieldCount} fields)' : 'No schema discovered yet',
                  ),
                  _buildDivider(context),
                  _buildInfoRow(context, 'Registered Date', dateFormat.format(widget.source.createdAt)),
                  _buildDivider(context),
                  _buildInfoRow(context, 'Last Updated', dateFormat.format(widget.source.updatedAt)),
                ],
              ),
            ),
          );

          final rightColumn = Column(
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Introspection Actions',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Run introspection to discover tables, columns, data types, and primary keys from this database.',
                        style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant, height: 1.4),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _isDiscovering ? null : _discoverSchema,
                          icon: const Icon(Icons.search, size: 14),
                          label: const Text('Run Schema Discovery'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _isTesting ? null : _testConnection,
                          icon: const Icon(Icons.bolt, size: 14),
                          label: const Text('Probe Connection'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Danger Zone Card
              Card(
                color: colorScheme.errorContainer.withValues(alpha: 0.2),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Danger Zone',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: colorScheme.error),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Deleting this data source removes all introspection snapshots and local connection configuration.',
                        style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: widget.onDelete,
                        icon: Icon(Icons.delete_outline, size: 14, color: colorScheme.error),
                        label: Text('Delete Data Source', style: TextStyle(color: colorScheme.error, fontSize: 12)),
                        style: OutlinedButton.styleFrom(side: BorderSide(color: colorScheme.error)),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );

          if (isNarrow) {
            return Column(
              children: [
                leftCard,
                const SizedBox(height: 16),
                rightColumn,
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: leftCard),
              const SizedBox(width: 20),
              Expanded(flex: 2, child: rightColumn),
            ],
          );
        },
      ),
    );
  }

  // --- TAB 2: CONNECTION PARAMETERS ---
  Widget _buildConnectionTab(BuildContext context, DateFormat dateFormat) {
    final colorScheme = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 800;
          final leftCard = Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Connection Parameters',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
                  ),
                  const SizedBox(height: 16),
                  _buildInfoRow(context, 'Host / IP Address', widget.source.host, isMonospace: true),
                  _buildDivider(context),
                  _buildInfoRow(context, 'Listening Port', widget.source.port.toString(), isMonospace: true),
                  _buildDivider(context),
                  _buildInfoRow(context, 'Database Name', widget.source.databaseName, isMonospace: true),
                  _buildDivider(context),
                  _buildInfoRow(context, 'Database User', widget.source.username, isMonospace: true),
                  _buildDivider(context),
                  _buildInfoRow(context, 'Password', '•••••••• (Securely Stored in Local Metadata)', isMonospace: true),
                  _buildDivider(context),
                  _buildInfoRow(context, 'Source ID (UUID)', widget.source.id, isMonospace: true),
                ],
              ),
            ),
          );

          final rightCard = Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Connector Capabilities',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
                  ),
                  const SizedBox(height: 14),
                  _buildCapabilityItem(context, 'Schema Discovery', _capabilities?.schemaDiscovery ?? true),
                  _buildCapabilityItem(context, 'Physical Query Reads', _capabilities?.read ?? true),
                  _buildCapabilityItem(context, 'Native Writes', _capabilities?.write ?? true),
                  _buildCapabilityItem(context, 'Change Data Capture (CDC)', _capabilities?.cdc ?? false, isRoadmap: true),
                ],
              ),
            ),
          );

          if (isNarrow) {
            return Column(
              children: [
                leftCard,
                const SizedBox(height: 16),
                rightCard,
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: leftCard),
              const SizedBox(width: 20),
              Expanded(flex: 2, child: rightCard),
            ],
          );
        },
      ),
    );
  }

  // --- TAB 3: DISCOVERED SCHEMAS ---
  Widget _buildSchemasTab(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (_schema == null || _schema!.entities.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.schema_outlined, size: 48, color: colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(
              'No Schema Snapshot Discovered Yet',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
            ),
            const SizedBox(height: 8),
            Text(
              'Run schema discovery to introspect tables and fields from this database.',
              style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _isDiscovering ? null : _discoverSchema,
              icon: const Icon(Icons.search, size: 14),
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

    final namespaces = namespaceMap.keys.toList();
    final currentEntities = namespaceMap[_selectedSchemaNamespace] ?? [];
    final currentEntity = currentEntities.firstWhere(
      (e) => e.name == _selectedTableName,
      orElse: () => currentEntities.isNotEmpty ? currentEntities.first : _schema!.entities.first,
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left Column: Namespaces & Tables Tree
        SizedBox(
          width: 260,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'SCHEMAS & TABLES',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: colorScheme.onSurfaceVariant, letterSpacing: 0.5),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ListView(
                      children: [
                        for (final ns in namespaces) ...[
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                Icon(Icons.folder_outlined, size: 16, color: colorScheme.primary),
                                const SizedBox(width: 6),
                                Text(
                                  ns,
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: colorScheme.onSurface),
                                ),
                              ],
                            ),
                          ),
                          for (final table in namespaceMap[ns]!)
                            InkWell(
                              onTap: () {
                                setState(() {
                                  _selectedSchemaNamespace = ns;
                                  _selectedTableName = table.name;
                                });
                              },
                              borderRadius: BorderRadius.circular(6),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                margin: const EdgeInsets.symmetric(vertical: 2),
                                decoration: BoxDecoration(
                                  color: (_selectedTableName == table.name && _selectedSchemaNamespace == ns)
                                      ? colorScheme.primaryContainer.withValues(alpha: 0.5)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.table_chart_outlined, size: 14, color: colorScheme.onSurfaceVariant),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        table.name,
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontFamily: 'monospace',
                                          color: (_selectedTableName == table.name && _selectedSchemaNamespace == ns)
                                              ? colorScheme.primary
                                              : colorScheme.onSurface,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Text(
                                      '${table.fieldCount}',
                                      style: TextStyle(fontSize: 10, color: colorScheme.onSurfaceVariant),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          const SizedBox(height: 8),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 16),

        // Right Column: Table Column Details
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
                          Icon(Icons.table_rows, color: colorScheme.primary, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            '${currentEntity.namespace}.${currentEntity.name}',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
                          ),
                        ],
                      ),
                      if (currentEntity.primaryKey.isNotEmpty)
                        StatusBadge(status: 'PK: ${currentEntity.primaryKey.join(', ')}', isPkBadge: true),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Fields Table
                  Expanded(
                    child: SingleChildScrollView(
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Table(
                          columnWidths: const {
                            0: FixedColumnWidth(40),
                            1: FlexColumnWidth(2.5),
                            2: FlexColumnWidth(2.0),
                            3: FlexColumnWidth(2.0),
                            4: FlexColumnWidth(1.4),
                            5: FlexColumnWidth(1.2),
                          },
                          children: [
                            TableRow(
                              decoration: BoxDecoration(
                                color: colorScheme.surfaceContainerHigh,
                                border: Border(bottom: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5))),
                              ),
                              children: [
                                Padding(padding: const EdgeInsets.all(10), child: Text('#', style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant, fontWeight: FontWeight.bold))),
                                Padding(padding: const EdgeInsets.all(10), child: Text('FIELD', style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant, fontWeight: FontWeight.bold))),
                                Padding(padding: const EdgeInsets.all(10), child: Text('STANDARD TYPE', style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant, fontWeight: FontWeight.bold))),
                                Padding(padding: const EdgeInsets.all(10), child: Text('NATIVE TYPE', style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant, fontWeight: FontWeight.bold))),
                                Padding(padding: const EdgeInsets.all(10), child: Text('NULLABLE', style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant, fontWeight: FontWeight.bold))),
                                Padding(padding: const EdgeInsets.all(10), child: Text('KEY', style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant, fontWeight: FontWeight.bold))),
                              ],
                            ),
                            for (final field in currentEntity.fields)
                              TableRow(
                                decoration: BoxDecoration(
                                  border: Border(bottom: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.3))),
                                ),
                                children: [
                                  Padding(padding: const EdgeInsets.all(10), child: Text('${field.position}', style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant))),
                                  Padding(
                                    padding: const EdgeInsets.all(10),
                                    child: Text(
                                      field.name,
                                      style: TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 12, color: colorScheme.onSurface),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.all(10),
                                    child: Text(
                                      field.dataType,
                                      style: TextStyle(color: colorScheme.primary, fontWeight: FontWeight.w600, fontFamily: 'monospace', fontSize: 11),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.all(10),
                                    child: Text(
                                      field.nativeDataType,
                                      style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: colorScheme.onSurfaceVariant),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.all(10),
                                    child: Text(
                                      field.nullable ? 'YES' : 'NO',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: field.nullable ? FontWeight.normal : FontWeight.bold,
                                        color: field.nullable ? colorScheme.onSurfaceVariant : colorScheme.onSurface,
                                      ),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.all(10),
                                    child: field.isPrimaryKey
                                        ? const Align(alignment: Alignment.centerLeft, child: StatusBadge(status: 'PK', isPkBadge: true))
                                        : Text('—', style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 11)),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
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

  // --- TAB 4: HEALTH & DIAGNOSTICS ---
  Widget _buildHealthTab(BuildContext context, DateFormat dateFormat) {
    final colorScheme = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Connection Health & Telemetry',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
                      ),
                      OutlinedButton.icon(
                        onPressed: _isTesting ? null : _testConnection,
                        icon: const Icon(Icons.bolt, size: 14),
                        label: Text(_isTesting ? 'Pinging...' : 'Probe Live Connection'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildInfoRow(
                    context,
                    'Current Health State',
                    widget.source.isActive ? 'Healthy & Online' : 'Unreachable',
                    customWidget: StatusBadge(status: widget.source.status),
                  ),
                  _buildDivider(context),
                  _buildInfoRow(
                    context,
                    'Last Health Check',
                    _lastHealthCheckTime != null ? dateFormat.format(_lastHealthCheckTime!) : 'Checked upon page load',
                  ),
                  _buildDivider(context),
                  if (_lastTestResult?.latencyMs != null) ...[
                    _buildInfoRow(
                      context,
                      'Roundtrip Latency',
                      '${_lastTestResult!.latencyMs!.toStringAsFixed(1)} ms',
                      isMonospace: true,
                    ),
                    _buildDivider(context),
                  ],
                  if (_lastTestResult?.serverVersion != null) ...[
                    _buildInfoRow(
                      context,
                      'Remote Server Version',
                      _lastTestResult!.serverVersion!,
                      isMonospace: true,
                    ),
                    _buildDivider(context),
                  ],
                  _buildInfoRow(context, 'Connection Protocol', 'Direct TCP Socket / PostgreSQL wire'),
                ],
              ),
            ),
          ),
          if (_lastTestResult?.errorDetails != null) ...[
            const SizedBox(height: 20),
            Card(
              color: colorScheme.errorContainer.withValues(alpha: 0.3),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Diagnostic Error Trace', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: colorScheme.error)),
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        _lastTestResult!.errorDetails!,
                        style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: colorScheme.error),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoRow(BuildContext context, String label, String value, {bool isMonospace = false, Widget? customWidget}) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant)),
          const SizedBox(width: 12),
          customWidget ??
              Flexible(
                child: Text(
                  value,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    fontFamily: isMonospace ? 'monospace' : null,
                    color: colorScheme.onSurface,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
        ],
      ),
    );
  }

  Widget _buildCapabilityItem(BuildContext context, String label, bool isSupported, {bool isRoadmap = false}) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 13, color: colorScheme.onSurface)),
          if (isRoadmap)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.getStatusColor('DISCOVERING', context).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'Future Milestone',
                style: TextStyle(fontSize: 10, color: AppTheme.getStatusColor('DISCOVERING', context)),
              ),
            )
          else if (isSupported)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.getStatusColor('ACTIVE', context).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '✓ Supported',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.getStatusColor('ACTIVE', context)),
              ),
            )
          else
            Text('Not Supported', style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }

  Widget _buildDivider(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Divider(height: 1, thickness: 1, color: colorScheme.outlineVariant.withValues(alpha: 0.5));
  }
}
