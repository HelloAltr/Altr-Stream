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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.message),
            backgroundColor: result.success ? AppTheme.success : AppTheme.error,
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
            backgroundColor: AppTheme.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Schema discovery failed: $e'),
            backgroundColor: AppTheme.error,
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Top Context Breadcrumb & Header
        Row(
          children: [
            InkWell(
              onTap: widget.onBack,
              borderRadius: BorderRadius.circular(6),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.arrow_back, size: 16, color: AppTheme.accentCyan),
                    SizedBox(width: 4),
                    Text('Data Sources', style: TextStyle(color: AppTheme.accentCyan, fontSize: 13)),
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
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
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
                  style: const TextStyle(
                    fontSize: 13,
                    fontFamily: 'monospace',
                    color: AppTheme.textSecondary,
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
                      ? const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.accentCyan),
                        )
                      : const Icon(Icons.bolt, size: 14),
                  label: Text(_isTesting ? 'Testing...' : 'Test Connection'),
                ),
                ElevatedButton.icon(
                  onPressed: _isDiscovering ? null : _discoverSchema,
                  icon: _isDiscovering
                      ? const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
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
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppTheme.borderColor)),
          ),
          child: TabBar(
            controller: _tabController,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: AppTheme.accentCyan,
            unselectedLabelColor: AppTheme.textSecondary,
            indicatorColor: AppTheme.accentCyan,
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
          const Center(
            child: Padding(
              padding: EdgeInsets.all(60),
              child: CircularProgressIndicator(color: AppTheme.accentCyan),
            ),
          )
        else
          SizedBox(
            height: 620,
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildOverviewTab(dateFormat),
                _buildConnectionTab(dateFormat),
                _buildSchemasTab(),
                _buildHealthTab(dateFormat),
              ],
            ),
          ),
      ],
    );
  }

  // --- TAB 1: OVERVIEW ---
  Widget _buildOverviewTab(DateFormat dateFormat) {
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
                  const Text(
                    'Source Summary',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                  ),
                  const SizedBox(height: 16),
                  _buildInfoRow('Database Engine', widget.source.type),
                  _buildDivider(),
                  _buildInfoRow('Database Name', widget.source.databaseName, isMonospace: true),
                  _buildDivider(),
                  _buildInfoRow('Connection Status', widget.source.isActive ? 'Active & Reachable' : 'Unreachable'),
                  _buildDivider(),
                  _buildInfoRow(
                    'Discovered Tables',
                    _schema != null ? '${_schema!.entityCount} tables (${_schema!.totalFieldCount} fields)' : 'No schema discovered yet',
                  ),
                  _buildDivider(),
                  _buildInfoRow('Registered Date', dateFormat.format(widget.source.createdAt)),
                  _buildDivider(),
                  _buildInfoRow('Last Updated', dateFormat.format(widget.source.updatedAt)),
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
                      const Text(
                        'Introspection Actions',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Run introspection to discover tables, columns, data types, and primary keys from this database.',
                        style: TextStyle(fontSize: 12, color: AppTheme.textSecondary, height: 1.4),
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
                color: AppTheme.errorBg.withValues(alpha: 0.2),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Danger Zone',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.error),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Deleting this data source removes all introspection snapshots and local connection configuration.',
                        style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: widget.onDelete,
                        icon: const Icon(Icons.delete_outline, size: 14, color: AppTheme.error),
                        label: const Text('Delete Data Source', style: TextStyle(color: AppTheme.error, fontSize: 12)),
                        style: OutlinedButton.styleFrom(side: const BorderSide(color: AppTheme.error)),
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
  Widget _buildConnectionTab(DateFormat dateFormat) {
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
                  const Text(
                    'Connection Parameters',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                  ),
                  const SizedBox(height: 16),
                  _buildInfoRow('Host / IP Address', widget.source.host, isMonospace: true),
                  _buildDivider(),
                  _buildInfoRow('Listening Port', widget.source.port.toString(), isMonospace: true),
                  _buildDivider(),
                  _buildInfoRow('Database Name', widget.source.databaseName, isMonospace: true),
                  _buildDivider(),
                  _buildInfoRow('Database User', widget.source.username, isMonospace: true),
                  _buildDivider(),
                  _buildInfoRow('Password', '•••••••• (Securely Stored in Local Metadata)', isMonospace: true),
                  _buildDivider(),
                  _buildInfoRow('Source ID (UUID)', widget.source.id, isMonospace: true),
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
                  const Text(
                    'Connector Capabilities',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                  ),
                  const SizedBox(height: 14),
                  _buildCapabilityItem('Schema Discovery', _capabilities?.schemaDiscovery ?? true),
                  _buildCapabilityItem('Physical Query Reads', _capabilities?.read ?? true),
                  _buildCapabilityItem('Native Writes', _capabilities?.write ?? true),
                  _buildCapabilityItem('Change Data Capture (CDC)', _capabilities?.cdc ?? false, isRoadmap: true),
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
  Widget _buildSchemasTab() {
    if (_schema == null || _schema!.entities.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.schema_outlined, size: 48, color: AppTheme.textMuted),
            const SizedBox(height: 16),
            const Text(
              'No Schema Snapshot Discovered Yet',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
            ),
            const SizedBox(height: 8),
            const Text(
              'Run schema discovery to introspect tables and fields from this database.',
              style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
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
                  const Text(
                    'SCHEMAS & TABLES',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textMuted, letterSpacing: 0.5),
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
                                const Icon(Icons.folder_outlined, size: 16, color: AppTheme.accentCyan),
                                const SizedBox(width: 6),
                                Text(
                                  ns,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textPrimary),
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
                                      ? AppTheme.accentCyanSubtle
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.table_chart_outlined, size: 14, color: AppTheme.textSecondary),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        table.name,
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontFamily: 'monospace',
                                          color: (_selectedTableName == table.name && _selectedSchemaNamespace == ns)
                                              ? AppTheme.accentCyan
                                              : AppTheme.textPrimary,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Text(
                                      '${table.fieldCount}',
                                      style: const TextStyle(fontSize: 10, color: AppTheme.textMuted),
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
                          const Icon(Icons.table_rows, color: AppTheme.accentCyan, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            '${currentEntity.namespace}.${currentEntity.name}',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
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
                          border: Border.all(color: AppTheme.borderColor),
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
                            const TableRow(
                              decoration: BoxDecoration(
                                color: AppTheme.bgPrimary,
                                border: Border(bottom: BorderSide(color: AppTheme.borderColor)),
                              ),
                              children: [
                                Padding(padding: EdgeInsets.all(10), child: Text('#', style: TextStyle(fontSize: 11, color: AppTheme.textMuted, fontWeight: FontWeight.bold))),
                                Padding(padding: EdgeInsets.all(10), child: Text('FIELD', style: TextStyle(fontSize: 11, color: AppTheme.textMuted, fontWeight: FontWeight.bold))),
                                Padding(padding: EdgeInsets.all(10), child: Text('STANDARD TYPE', style: TextStyle(fontSize: 11, color: AppTheme.textMuted, fontWeight: FontWeight.bold))),
                                Padding(padding: EdgeInsets.all(10), child: Text('NATIVE TYPE', style: TextStyle(fontSize: 11, color: AppTheme.textMuted, fontWeight: FontWeight.bold))),
                                Padding(padding: EdgeInsets.all(10), child: Text('NULLABLE', style: TextStyle(fontSize: 11, color: AppTheme.textMuted, fontWeight: FontWeight.bold))),
                                Padding(padding: EdgeInsets.all(10), child: Text('KEY', style: TextStyle(fontSize: 11, color: AppTheme.textMuted, fontWeight: FontWeight.bold))),
                              ],
                            ),
                            for (final field in currentEntity.fields)
                              TableRow(
                                decoration: const BoxDecoration(
                                  border: Border(bottom: BorderSide(color: AppTheme.borderColor)),
                                ),
                                children: [
                                  Padding(padding: const EdgeInsets.all(10), child: Text('${field.position}', style: const TextStyle(fontSize: 11, color: AppTheme.textMuted))),
                                  Padding(
                                    padding: const EdgeInsets.all(10),
                                    child: Text(
                                      field.name,
                                      style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 12, color: AppTheme.textPrimary),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.all(10),
                                    child: Text(
                                      field.dataType,
                                      style: const TextStyle(color: AppTheme.accentCyan, fontWeight: FontWeight.w600, fontFamily: 'monospace', fontSize: 11),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.all(10),
                                    child: Text(
                                      field.nativeDataType,
                                      style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: AppTheme.textSecondary),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.all(10),
                                    child: Text(
                                      field.nullable ? 'YES' : 'NO',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: field.nullable ? FontWeight.normal : FontWeight.bold,
                                        color: field.nullable ? AppTheme.textMuted : AppTheme.textPrimary,
                                      ),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.all(10),
                                    child: field.isPrimaryKey
                                        ? const Align(alignment: Alignment.centerLeft, child: StatusBadge(status: 'PK', isPkBadge: true))
                                        : const Text('—', style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
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
  Widget _buildHealthTab(DateFormat dateFormat) {
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
                      const Text(
                        'Connection Health & Telemetry',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
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
                    'Current Health State',
                    widget.source.isActive ? 'Healthy & Online' : 'Unreachable',
                    customWidget: StatusBadge(status: widget.source.status),
                  ),
                  _buildDivider(),
                  _buildInfoRow(
                    'Last Health Check',
                    _lastHealthCheckTime != null ? dateFormat.format(_lastHealthCheckTime!) : 'Checked upon page load',
                  ),
                  _buildDivider(),
                  if (_lastTestResult?.latencyMs != null) ...[
                    _buildInfoRow(
                      'Roundtrip Latency',
                      '${_lastTestResult!.latencyMs!.toStringAsFixed(1)} ms',
                      isMonospace: true,
                    ),
                    _buildDivider(),
                  ],
                  if (_lastTestResult?.serverVersion != null) ...[
                    _buildInfoRow(
                      'Remote Server Version',
                      _lastTestResult!.serverVersion!,
                      isMonospace: true,
                    ),
                    _buildDivider(),
                  ],
                  _buildInfoRow('Connection Protocol', 'Direct TCP Socket / PostgreSQL wire'),
                ],
              ),
            ),
          ),
          if (_lastTestResult?.errorDetails != null) ...[
            const SizedBox(height: 20),
            Card(
              color: AppTheme.errorBg.withValues(alpha: 0.3),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Diagnostic Error Trace', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.error)),
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.bgPrimary,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        _lastTestResult!.errorDetails!,
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: AppTheme.error),
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

  Widget _buildInfoRow(String label, String value, {bool isMonospace = false, Widget? customWidget}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
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
                    color: AppTheme.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
        ],
      ),
    );
  }

  Widget _buildCapabilityItem(String label, bool isSupported, {bool isRoadmap = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 13, color: AppTheme.textPrimary)),
          if (isRoadmap)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.warningBg,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text('Future Milestone', style: TextStyle(fontSize: 10, color: AppTheme.warning)),
            )
          else if (isSupported)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.successBg,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text('✓ Supported', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.success)),
            )
          else
            const Text('Not Supported', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
        ],
      ),
    );
  }

  Widget _buildDivider() {
    return const Divider(height: 1, thickness: 1, color: AppTheme.borderColor);
  }
}
