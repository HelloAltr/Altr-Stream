import 'package:flutter/material.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/models.dart';
import '../../../shared/widgets/status_badge.dart';
import '../widgets/add_entity_dialog.dart';
import '../widgets/add_field_dialog.dart';
import '../widgets/add_mapping_dialog.dart';
import '../widgets/edit_entity_dialog.dart';
import '../widgets/edit_field_dialog.dart';
import '../widgets/edit_logical_model_dialog.dart';

class LogicalModelDetailScreen extends StatefulWidget {
  final LogicalModelModel model;
  final List<SourceModel> sources;
  final ApiClient apiClient;
  final VoidCallback onBack;
  final VoidCallback onModelDeleted;
  final String nodeStatus;
  final VoidCallback onNodeStatusTap;

  const LogicalModelDetailScreen({
    super.key,
    required this.model,
    required this.sources,
    required this.apiClient,
    required this.onBack,
    required this.onModelDeleted,
    this.nodeStatus = 'ACTIVE',
    required this.onNodeStatusTap,
  });

  @override
  State<LogicalModelDetailScreen> createState() => _LogicalModelDetailScreenState();
}

class _LogicalModelDetailScreenState extends State<LogicalModelDetailScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late LogicalModelModel _currentModel;
  List<SourceMappingModel> _mappings = [];
  bool _isLoadingMappings = true;

  // Inline mapping editor state
  String? _editingMappingId;
  final Map<String, String?> _editingPhysicalEntityNames = {};
  final Map<String, String> _editingPhysicalNamespaces = {};
  final Map<String, Map<String, String?>> _editingFieldAssignments = {};
  bool _isSavingInlineEdit = false;

  // Cache for source schemas
  final Map<String, SourceSchemaModel> _sourceSchemas = {};
  final Set<String> _loadingSchemaSourceIds = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    _currentModel = widget.model;
    _refreshModel();
    _fetchMappings();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _refreshModel() async {
    try {
      final updated = await widget.apiClient.getLogicalModel(_currentModel.id);
      setState(() => _currentModel = updated);
    } catch (_) {}
  }

  Future<void> _fetchMappings() async {
    setState(() => _isLoadingMappings = true);
    try {
      final list = await widget.apiClient.listSourceMappings(modelId: _currentModel.id);
      setState(() {
        _mappings = list;
        _isLoadingMappings = false;
      });
      for (final m in list) {
        _ensureSourceSchema(m.sourceId);
      }
    } catch (e) {
      setState(() => _isLoadingMappings = false);
    }
  }

  Future<void> _ensureSourceSchema(String sourceId) async {
    if (_sourceSchemas.containsKey(sourceId) || _loadingSchemaSourceIds.contains(sourceId)) {
      return;
    }
    _loadingSchemaSourceIds.add(sourceId);
    try {
      SourceSchemaModel? schema = await widget.apiClient.getLatestSchema(sourceId);
      if (schema == null || schema.entities.isEmpty) {
        schema = await widget.apiClient.discoverSchema(sourceId);
      }
      final SourceSchemaModel loadedSchema = schema;
      if (mounted) {
        setState(() {
          _sourceSchemas[sourceId] = loadedSchema;
        });
      }
    } catch (_) {
    } finally {
      _loadingSchemaSourceIds.remove(sourceId);
    }
  }

  void _startInlineEdit(SourceMappingModel mapping) {
    setState(() {
      _editingMappingId = mapping.id;
      _editingPhysicalEntityNames.clear();
      _editingPhysicalNamespaces.clear();
      _editingFieldAssignments.clear();

      for (final logicalEntity in _currentModel.entities) {
        final em = mapping.entityMappings.where(
          (m) => m.logicalEntityId == logicalEntity.id || m.logicalEntityName == logicalEntity.name,
        ).firstOrNull;

        if (em != null) {
          _editingPhysicalEntityNames[logicalEntity.id] = em.physicalEntityName;
          _editingPhysicalNamespaces[logicalEntity.id] = em.physicalNamespace;
          final fieldMap = <String, String?>{};
          for (final lf in logicalEntity.fields) {
            final fm = em.fieldMappings.where((f) => f.logicalFieldName == lf.name).firstOrNull;
            fieldMap[lf.name] = fm?.physicalFieldName;
          }
          _editingFieldAssignments[logicalEntity.id] = fieldMap;
        } else {
          _editingPhysicalEntityNames[logicalEntity.id] = null;
          _editingPhysicalNamespaces[logicalEntity.id] = 'public';
          final fieldMap = <String, String?>{};
          for (final lf in logicalEntity.fields) {
            fieldMap[lf.name] = null;
          }
          _editingFieldAssignments[logicalEntity.id] = fieldMap;
        }
      }
    });
    _ensureSourceSchema(mapping.sourceId);
  }

  void _cancelInlineEdit() {
    setState(() {
      _editingMappingId = null;
      _editingPhysicalEntityNames.clear();
      _editingPhysicalNamespaces.clear();
      _editingFieldAssignments.clear();
    });
  }

  void _autoMatchCurrentEdit(SourceMappingModel mapping) {
    final schema = _sourceSchemas[mapping.sourceId];
    if (schema == null) return;

    setState(() {
      for (final logicalEntity in _currentModel.entities) {
        final logicalName = logicalEntity.name.toLowerCase();
        var selectedPhysicalName = _editingPhysicalEntityNames[logicalEntity.id];

        if (selectedPhysicalName == null || selectedPhysicalName.isEmpty) {
          final matchedEntity = schema.entities.where((pe) {
            final pn = pe.name.toLowerCase();
            return pn == logicalName ||
                pn == '${logicalName}s' ||
                pn == 'tbl_$logicalName' ||
                pn == '${logicalName}_tbl' ||
                pn.replaceAll('_', '') == logicalName.replaceAll('_', '');
          }).firstOrNull;

          if (matchedEntity != null) {
            selectedPhysicalName = matchedEntity.name;
            _editingPhysicalEntityNames[logicalEntity.id] = matchedEntity.name;
            _editingPhysicalNamespaces[logicalEntity.id] = matchedEntity.namespace;
          }
        }

        if (selectedPhysicalName != null && selectedPhysicalName.isNotEmpty) {
          final physEntity = schema.entities.where((pe) => pe.name == selectedPhysicalName).firstOrNull;
          if (physEntity != null) {
            final fieldMap = _editingFieldAssignments.putIfAbsent(logicalEntity.id, () => {});
            for (final lf in logicalEntity.fields) {
              final lfn = lf.name.toLowerCase().replaceAll('_', '');
              for (final pf in physEntity.fields) {
                final pfn = pf.name.toLowerCase().replaceAll('_', '');
                if ((pfn == lfn || pf.name.toLowerCase() == lf.name.toLowerCase()) &&
                    areDataTypesCompatible(lf.dataType, pf.dataType)) {
                  fieldMap[lf.name] = pf.name;
                  break;
                }
              }
            }
          }
        }
      }
    });
  }

  Future<void> _saveCurrentInlineEdit(SourceMappingModel mapping) async {
    final entityPayloads = <Map<String, dynamic>>[];

    for (final logicalEntity in _currentModel.entities) {
      final physicalName = _editingPhysicalEntityNames[logicalEntity.id];
      if (physicalName == null || physicalName.isEmpty) {
        continue;
      }
      final physicalNs = _editingPhysicalNamespaces[logicalEntity.id] ?? 'public';
      final fieldMap = _editingFieldAssignments[logicalEntity.id] ?? {};
      final fieldPayloads = <Map<String, dynamic>>[];

      for (final lf in logicalEntity.fields) {
        final physField = fieldMap[lf.name];
        if (physField != null && physField.isNotEmpty) {
          fieldPayloads.add({
            'logical_field_id': lf.id,
            'logical_field_name': lf.name,
            'physical_field_name': physField,
          });
        }
      }

      if (fieldPayloads.isNotEmpty) {
        entityPayloads.add({
          'logical_entity_id': logicalEntity.id,
          'logical_entity_name': logicalEntity.name,
          'physical_entity_name': physicalName,
          'physical_namespace': physicalNs,
          'field_mappings': fieldPayloads,
        });
      }
    }

    if (entityPayloads.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('At least one entity with mapped fields is required to save.')),
      );
      return;
    }

    setState(() => _isSavingInlineEdit = true);

    try {
      await widget.apiClient.updateSourceMapping(
        mapping.id,
        version: _currentModel.version,
        entityMappings: entityPayloads,
      );
      _cancelInlineEdit();
      await _fetchMappings();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Source mapping updated! Status reset to DRAFT. Click Validate to test.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update mapping: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSavingInlineEdit = false);
      }
    }
  }

  void _showEditModelDialog() {
    showDialog(
      context: context,
      builder: (ctx) => EditLogicalModelDialog(
        apiClient: widget.apiClient,
        model: _currentModel,
        onModelUpdated: (updated) {
          setState(() => _currentModel = updated);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Logical model updated successfully.')),
          );
        },
      ),
    );
  }

  Future<void> _deleteModel() async {
    final colorScheme = Theme.of(context).colorScheme;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colorScheme.surfaceContainerHigh,
        title: const Text('Delete Logical Model?'),
        content: Text(
          'Are you sure you want to delete "${_currentModel.name}" and all its entities and source mappings? This action cannot be undone.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: colorScheme.error, foregroundColor: colorScheme.onError),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete Model'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await widget.apiClient.deleteLogicalModel(_currentModel.id);
        widget.onModelDeleted();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to delete model: $e'), backgroundColor: colorScheme.error),
          );
        }
      }
    }
  }

  void _showAddEntityDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AddEntityDialog(
        apiClient: widget.apiClient,
        modelId: _currentModel.id,
        onEntityCreated: (_) {
          _refreshModel();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Logical entity added successfully.')),
          );
        },
      ),
    );
  }

  void _showEditEntityDialog(LogicalEntityModel entity) {
    showDialog(
      context: context,
      builder: (ctx) => EditEntityDialog(
        apiClient: widget.apiClient,
        entity: entity,
        onEntityUpdated: (_) {
          _refreshModel();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Logical entity updated successfully.')),
          );
        },
      ),
    );
  }

  void _showAddFieldDialog(LogicalEntityModel entity) {
    showDialog(
      context: context,
      builder: (ctx) => AddFieldDialog(
        apiClient: widget.apiClient,
        entityId: entity.id,
        onFieldCreated: (_) {
          _refreshModel();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Field added successfully.')),
          );
        },
      ),
    );
  }

  void _showEditFieldDialog(LogicalFieldModel field) {
    showDialog(
      context: context,
      builder: (ctx) => EditFieldDialog(
        apiClient: widget.apiClient,
        field: field,
        onFieldUpdated: (_) {
          _refreshModel();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Field updated successfully.')),
          );
        },
      ),
    );
  }

  void _showAddMappingDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AddMappingDialog(
        apiClient: widget.apiClient,
        logicalModel: _currentModel,
        sources: widget.sources,
        onMappingCreated: (_) {
          _fetchMappings();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Source mapping created and validated!')),
          );
        },
      ),
    );
  }

  Future<void> _deleteEntity(LogicalEntityModel entity) async {
    final colorScheme = Theme.of(context).colorScheme;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colorScheme.surfaceContainerHigh,
        title: const Text('Delete Logical Entity?'),
        content: Text('Are you sure you want to delete "${entity.name}" and its fields?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: colorScheme.error, foregroundColor: colorScheme.onError),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete Entity'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await widget.apiClient.deleteLogicalEntity(entity.id);
        _refreshModel();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to delete entity: $e'), backgroundColor: colorScheme.error),
          );
        }
      }
    }
  }

  Future<void> _deleteField(LogicalFieldModel field) async {
    final colorScheme = Theme.of(context).colorScheme;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colorScheme.surfaceContainerHigh,
        title: const Text('Delete Field?'),
        content: Text('Are you sure you want to delete field "${field.name}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: colorScheme.error, foregroundColor: colorScheme.onError),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete Field'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await widget.apiClient.deleteLogicalField(field.id);
        _refreshModel();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to delete field: $e'), backgroundColor: colorScheme.error),
          );
        }
      }
    }
  }

  Future<void> _validateMapping(SourceMappingModel mapping) async {
    try {
      final updated = await widget.apiClient.validateSourceMapping(mapping.id);
      _fetchMappings();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Mapping validated: ${updated.status}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Validation error: $e'), backgroundColor: Theme.of(context).colorScheme.error),
        );
      }
    }
  }

  Future<void> _activateMapping(SourceMappingModel mapping) async {
    try {
      final updated = await widget.apiClient.activateSourceMapping(mapping.id);
      _fetchMappings();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Mapping "${updated.id}" is now ACTIVE!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Activation failed: $e'), backgroundColor: Theme.of(context).colorScheme.error),
        );
      }
    }
  }

  Future<void> _deleteMapping(SourceMappingModel mapping) async {
    final colorScheme = Theme.of(context).colorScheme;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colorScheme.surfaceContainerHigh,
        title: const Text('Delete Source Mapping?'),
        content: const Text('Are you sure you want to delete this source mapping?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: colorScheme.error, foregroundColor: colorScheme.onError),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete Mapping'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await widget.apiClient.deleteSourceMapping(mapping.id);
        _fetchMappings();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Delete failed: $e'), backgroundColor: colorScheme.error),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Top Header
        Row(
          children: [
            IconButton(
              onPressed: widget.onBack,
              icon: const Icon(Icons.arrow_back),
              tooltip: 'Back to Registry',
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        _currentModel.name,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: colorScheme.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: colorScheme.primary.withValues(alpha: 0.3)),
                        ),
                        child: Text(
                          'v${_currentModel.version}',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: colorScheme.primary),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: _showEditModelDialog,
                        icon: const Icon(Icons.edit_outlined, size: 16),
                        tooltip: 'Edit Model Details',
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                  if (_currentModel.description != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      _currentModel.description!,
                      style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ],
              ),
            ),
            OutlinedButton.icon(
              onPressed: _showAddEntityDialog,
              icon: const Icon(Icons.add, size: 14),
              label: const Text('Add Entity'),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: _showAddMappingDialog,
              icon: const Icon(Icons.compare_arrows, size: 14),
              label: const Text('Map Source'),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: _deleteModel,
              icon: const Icon(Icons.delete_outline, size: 18),
              color: colorScheme.error,
              tooltip: 'Delete Model',
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Tab Bar
        TabBar(
          controller: _tabController,
          labelColor: colorScheme.primary,
          unselectedLabelColor: colorScheme.onSurfaceVariant,
          indicatorColor: colorScheme.primary,
          tabs: [
            Tab(
              icon: const Icon(Icons.schema_outlined, size: 16),
              text: 'Logical Schema (${_currentModel.entityCount} entities, ${_currentModel.totalFieldCount} fields)',
            ),
            Tab(
              icon: const Icon(Icons.link, size: 16),
              text: 'Source Mappings (${_mappings.length} sources)',
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Tab Views
        AnimatedBuilder(
          animation: _tabController,
          builder: (context, _) {
            if (_tabController.index == 0) {
              return _buildLogicalSchemaTab(context);
            } else {
              return _buildSourceMappingsTab(context);
            }
          },
        ),
      ],
    );
  }

  Widget _buildLogicalSchemaTab(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (_currentModel.entities.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(40),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
        ),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.table_chart_outlined, size: 40, color: colorScheme.onSurfaceVariant),
              const SizedBox(height: 12),
              const Text('No logical entities defined yet.', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              const Text('Add entities and field definitions to build this domain model.', style: TextStyle(fontSize: 12)),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _showAddEntityDialog,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add Entity'),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _currentModel.entities.length,
      separatorBuilder: (_, _) => const SizedBox(height: 16),
      itemBuilder: (context, idx) {
        final entity = _currentModel.entities[idx];
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: colorScheme.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Icon(Icons.table_rows_outlined, size: 16, color: colorScheme.primary),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          entity.name,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '(${entity.fieldCount} fields)',
                          style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        TextButton.icon(
                          onPressed: () => _showAddFieldDialog(entity),
                          icon: const Icon(Icons.add, size: 14),
                          label: const Text('Add Field', style: TextStyle(fontSize: 12)),
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          onPressed: () => _showEditEntityDialog(entity),
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          tooltip: 'Edit Entity',
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          onPressed: () => _deleteEntity(entity),
                          icon: const Icon(Icons.delete_outline, size: 18),
                          color: colorScheme.error,
                          tooltip: 'Delete Entity',
                        ),
                      ],
                    ),
                  ],
                ),
                if (entity.description != null) ...[
                  const SizedBox(height: 4),
                  Text(entity.description!, style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
                ],
                const SizedBox(height: 12),
                Divider(height: 1, color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
                const SizedBox(height: 8),
                // Fields Table
                Table(
                  columnWidths: const {
                    0: FlexColumnWidth(3),
                    1: FlexColumnWidth(2),
                    2: FlexColumnWidth(2),
                    3: FlexColumnWidth(1.5),
                  },
                  defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                  children: [
                    TableRow(
                      decoration: BoxDecoration(
                        border: Border(bottom: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.2))),
                      ),
                      children: const [
                        Padding(
                          padding: EdgeInsets.symmetric(vertical: 6),
                          child: Text('FIELD NAME', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                        ),
                        Padding(
                          padding: EdgeInsets.symmetric(vertical: 6),
                          child: Text('LOGICAL TYPE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                        ),
                        Padding(
                          padding: EdgeInsets.symmetric(vertical: 6),
                          child: Text('ATTRIBUTES', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                        ),
                        Padding(
                          padding: EdgeInsets.symmetric(vertical: 6),
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: Text('ACTIONS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
                    ),
                    ...entity.fields.map(
                      (f) => TableRow(
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Row(
                              children: [
                                Icon(
                                  f.isPrimaryKey ? Icons.key : Icons.tag,
                                  size: 13,
                                  color: f.isPrimaryKey ? Colors.amber : colorScheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  f.name,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: f.isPrimaryKey ? FontWeight.bold : FontWeight.normal,
                                    fontFamily: 'monospace',
                                    color: colorScheme.onSurface,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Text(
                              f.dataType,
                              style: TextStyle(fontSize: 12, color: colorScheme.primary, fontFamily: 'monospace'),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Row(
                              children: [
                                if (f.isPrimaryKey)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                    margin: const EdgeInsets.only(right: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.amber.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text('PK', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.amber)),
                                  ),
                                if (f.nullable)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: colorScheme.surfaceContainerHighest,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text('NULL', style: TextStyle(fontSize: 10, color: colorScheme.onSurfaceVariant)),
                                  ),
                              ],
                            ),
                          ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  onPressed: () => _showEditFieldDialog(f),
                                  icon: const Icon(Icons.edit_outlined, size: 14),
                                  tooltip: 'Edit field',
                                  visualDensity: VisualDensity.compact,
                                ),
                                IconButton(
                                  onPressed: () => _deleteField(f),
                                  icon: const Icon(Icons.delete_outline, size: 14),
                                  color: colorScheme.error.withValues(alpha: 0.7),
                                  tooltip: 'Delete field',
                                  visualDensity: VisualDensity.compact,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCompatibilityBadge({
    required BuildContext context,
    required String logicalType,
    required String? physicalFieldName,
    required String? physicalDataType,
    required bool isFieldFoundInSchema,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    if (physicalFieldName == null || physicalFieldName.isEmpty || physicalFieldName == '—') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.warning_amber_rounded, size: 13, color: colorScheme.onSurfaceVariant),
            const SizedBox(width: 5),
            Text(
              'Unmapped',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    if (!isFieldFoundInSchema && physicalDataType == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: colorScheme.errorContainer.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: colorScheme.error.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cancel_outlined, size: 13, color: colorScheme.error),
            const SizedBox(width: 5),
            Text(
              'Missing in Schema',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: colorScheme.error),
            ),
          ],
        ),
      );
    }

    final isCompatible = areDataTypesCompatible(logicalType, physicalDataType);
    if (!isCompatible) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: colorScheme.errorContainer.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: colorScheme.error.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.highlight_off, size: 13, color: colorScheme.error),
            const SizedBox(width: 5),
            Text(
              'Type Mismatch',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: colorScheme.error),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.green.withValues(alpha: 0.45)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle_outline, size: 13, color: Colors.green),
          SizedBox(width: 5),
          Text(
            'Valid',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.green),
          ),
        ],
      ),
    );
  }

  Widget _buildMappingTable({
    required BuildContext context,
    required SourceMappingModel mapping,
    required LogicalEntityModel logicalEntity,
    required bool isEditing,
    required SourceSchemaModel? schema,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    String? physicalTableName;
    if (isEditing) {
      physicalTableName = _editingPhysicalEntityNames[logicalEntity.id];
    } else {
      final em = mapping.entityMappings.where(
        (m) => m.logicalEntityId == logicalEntity.id || m.logicalEntityName == logicalEntity.name,
      ).firstOrNull;
      physicalTableName = em?.physicalEntityName;
    }

    final physicalEntitySchema = schema?.entities.where((e) => e.name == physicalTableName).firstOrNull;
    final availableFields = physicalEntitySchema?.fields ?? <FieldSchemaModel>[];

    final em = mapping.entityMappings.where(
      (m) => m.logicalEntityId == logicalEntity.id || m.logicalEntityName == logicalEntity.name,
    ).firstOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
            border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.table_chart, size: 15, color: colorScheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    'Entity: ${logicalEntity.name}',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.arrow_forward, size: 12),
                  const SizedBox(width: 8),
                  Container(
                    height: 34,
                    alignment: Alignment.centerLeft,
                    child: isEditing
                        ? (schema == null
                            ? Text('Loading schema...', style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant))
                            : SizedBox(
                                width: 260,
                                height: 34,
                                child: DropdownButtonFormField<String?>(
                                  isExpanded: true,
                                  initialValue: physicalTableName,
                                  isDense: true,
                                  decoration: InputDecoration(
                                    filled: true,
                                    fillColor: colorScheme.surfaceContainerLowest,
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(6),
                                      borderSide: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.8)),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(6),
                                      borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
                                    ),
                                  ),
                                  hint: const Text('(Select Physical Table)', style: TextStyle(fontSize: 12)),
                                  items: [
                                    const DropdownMenuItem<String?>(
                                      value: null,
                                      child: Text('(None / Unmapped)', style: TextStyle(fontSize: 12)),
                                    ),
                                    ...schema.entities.map(
                                      (pe) => DropdownMenuItem<String?>(
                                        value: pe.name,
                                        child: Text('${pe.namespace}.${pe.name} (${pe.fields.length} cols)', style: const TextStyle(fontSize: 12)),
                                      ),
                                    ),
                                  ],
                                  onChanged: (val) {
                                    setState(() {
                                      _editingPhysicalEntityNames[logicalEntity.id] = val;
                                      if (val != null) {
                                        final matched = schema.entities.where((e) => e.name == val).firstOrNull;
                                        if (matched != null) {
                                          _editingPhysicalNamespaces[logicalEntity.id] = matched.namespace;
                                        }
                                      }
                                    });
                                  },
                                ),
                              ))
                        : Text(
                            physicalTableName != null
                                ? '${em?.physicalNamespace ?? "public"}.$physicalTableName'
                                : '(Unmapped)',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.bold,
                              color: physicalTableName != null ? colorScheme.primary : colorScheme.onSurfaceVariant,
                            ),
                          ),
                  ),
                ],
              ),
              Text(
                '${logicalEntity.fields.length} logical fields',
                style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8)),
          ),
          child: Table(
            columnWidths: const {
              0: FlexColumnWidth(2.6),
              1: FlexColumnWidth(1.6),
              2: FlexColumnWidth(4.0),
              3: FlexColumnWidth(1.6),
              4: FlexColumnWidth(2.2),
            },
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            children: [
              TableRow(
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainer,
                  border: Border(bottom: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.3))),
                ),
                children: [
                  Container(
                    height: 36,
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: const Text('LOGICAL FIELD', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.4)),
                  ),
                  Container(
                    height: 36,
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: const Text('LOGICAL TYPE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.4)),
                  ),
                  Container(
                    height: 36,
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: const Text('PHYSICAL FIELD', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.4)),
                  ),
                  Container(
                    height: 36,
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: const Text('PHYSICAL TYPE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.4)),
                  ),
                  Container(
                    height: 36,
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: const Text('STATUS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.4)),
                  ),
                ],
              ),
              ...logicalEntity.fields.map((lf) {
                String? mappedPhysicalFieldName;
                if (isEditing) {
                  mappedPhysicalFieldName = _editingFieldAssignments[logicalEntity.id]?[lf.name];
                } else {
                  final fm = em?.fieldMappings.where((f) => f.logicalFieldName == lf.name).firstOrNull;
                  mappedPhysicalFieldName = fm?.physicalFieldName;
                }

                final physicalFieldSchema = availableFields.where((f) => f.name == mappedPhysicalFieldName).firstOrNull;
                final physicalDataType = physicalFieldSchema?.dataType;
                final isFieldFoundInSchema = physicalFieldSchema != null || schema == null;

                return TableRow(
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.15))),
                  ),
                  children: [
                    Container(
                      height: 42,
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        children: [
                          Icon(
                            lf.isPrimaryKey ? Icons.key : Icons.tag,
                            size: 13,
                            color: lf.isPrimaryKey ? Colors.amber : colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              lf.name,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: lf.isPrimaryKey ? FontWeight.bold : FontWeight.normal,
                                fontFamily: 'monospace',
                                color: colorScheme.onSurface,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (lf.isPrimaryKey)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                              margin: const EdgeInsets.only(left: 4),
                              decoration: BoxDecoration(
                                color: Colors.amber.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text('PK', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.amber)),
                            ),
                        ],
                      ),
                    ),
                    Container(
                      height: 42,
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Text(
                        lf.dataType,
                        style: TextStyle(fontSize: 12, color: colorScheme.primary, fontFamily: 'monospace', fontWeight: FontWeight.w500),
                      ),
                    ),
                    Container(
                      height: 42,
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: isEditing
                          ? (availableFields.isEmpty
                              ? Text(
                                  physicalTableName == null ? '(Select table first)' : '(No columns found)',
                                  style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: colorScheme.onSurfaceVariant),
                                )
                              : SizedBox(
                                  height: 34,
                                  child: DropdownButtonFormField<String?>(
                                    isExpanded: true,
                                    initialValue: availableFields.any((f) => f.name == mappedPhysicalFieldName)
                                        ? mappedPhysicalFieldName
                                        : null,
                                    isDense: true,
                                    decoration: InputDecoration(
                                      filled: true,
                                      fillColor: colorScheme.surfaceContainerLowest,
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(6),
                                        borderSide: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.8)),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(6),
                                        borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
                                      ),
                                    ),
                                    items: [
                                      const DropdownMenuItem<String?>(
                                        value: null,
                                        child: Text('(Unmapped)', style: TextStyle(fontSize: 12)),
                                      ),
                                      ...availableFields.map((pf) {
                                        final isComp = areDataTypesCompatible(lf.dataType, pf.dataType);
                                        return DropdownMenuItem<String?>(
                                          value: pf.name,
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Flexible(
                                                child: Text(
                                                  pf.name,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    fontFamily: 'monospace',
                                                    fontWeight: FontWeight.w500,
                                                    color: isComp ? null : colorScheme.error,
                                                  ),
                                                ),
                                              ),
                                              if (!isComp) ...[
                                                const SizedBox(width: 4),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                                  decoration: BoxDecoration(
                                                    color: colorScheme.errorContainer.withValues(alpha: 0.4),
                                                    borderRadius: BorderRadius.circular(4),
                                                  ),
                                                  child: Text(
                                                    pf.dataType,
                                                    style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: colorScheme.error),
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        );
                                      }),
                                    ],
                                    onChanged: (val) {
                                      setState(() {
                                        final map = _editingFieldAssignments.putIfAbsent(logicalEntity.id, () => {});
                                        map[lf.name] = val;
                                      });
                                    },
                                  ),
                                ))
                          : Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              child: Text(
                                mappedPhysicalFieldName ?? '—',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontFamily: 'monospace',
                                  color: mappedPhysicalFieldName != null ? colorScheme.onSurface : colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                    ),
                    Container(
                      height: 42,
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Text(
                        physicalDataType ?? (mappedPhysicalFieldName != null && mappedPhysicalFieldName != '—' ? 'UNKNOWN' : '—'),
                        style: TextStyle(
                          fontSize: 12,
                          fontFamily: 'monospace',
                          color: physicalDataType != null ? colorScheme.onSurfaceVariant : colorScheme.outline,
                        ),
                      ),
                    ),
                    Container(
                      height: 42,
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: _buildCompatibilityBadge(
                        context: context,
                        logicalType: lf.dataType,
                        physicalFieldName: mappedPhysicalFieldName,
                        physicalDataType: physicalDataType,
                        isFieldFoundInSchema: isFieldFoundInSchema,
                      ),
                    ),
                  ],
                );
              }),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSourceMappingCard(BuildContext context, SourceMappingModel mapping) {
    final colorScheme = Theme.of(context).colorScheme;
    final source = widget.sources.where((s) => s.id == mapping.sourceId).firstOrNull;
    final isEditing = _editingMappingId == mapping.id;
    final schema = _sourceSchemas[mapping.sourceId];

    return Card(
      elevation: isEditing ? 3 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: isEditing
            ? BorderSide(color: colorScheme.primary, width: 2)
            : BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                      ),
                      child: Icon(
                        source?.type == 'SQLITE' ? Icons.insert_drive_file_outlined : Icons.storage,
                        color: colorScheme.primary,
                        size: 16,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              source?.name ?? mapping.sourceId,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onSurface,
                              ),
                            ),
                            if (isEditing) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: colorScheme.primary.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'EDITING',
                                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: colorScheme.primary),
                                ),
                              ),
                            ],
                          ],
                        ),
                        Text(
                          '${source?.type ?? "SOURCE"} • Provenance: ${mapping.provenance} • Mapping ID: ${mapping.id.length > 8 ? "${mapping.id.substring(0, 8)}..." : mapping.id}',
                          style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ],
                ),
                Row(
                  children: [
                    StatusBadge(status: mapping.status),
                    const SizedBox(width: 12),
                    if (isEditing) ...[
                      OutlinedButton.icon(
                        onPressed: () => _autoMatchCurrentEdit(mapping),
                        icon: const Icon(Icons.auto_fix_high, size: 14),
                        label: const Text('Auto-Match', style: TextStyle(fontSize: 12)),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: _isSavingInlineEdit ? null : _cancelInlineEdit,
                        child: const Text('Cancel', style: TextStyle(fontSize: 12)),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: _isSavingInlineEdit ? null : () => _saveCurrentInlineEdit(mapping),
                        icon: _isSavingInlineEdit
                            ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.save, size: 14),
                        label: const Text('Save Changes', style: TextStyle(fontSize: 12)),
                      ),
                    ] else ...[
                      OutlinedButton.icon(
                        onPressed: () => _startInlineEdit(mapping),
                        icon: const Icon(Icons.edit_outlined, size: 14),
                        label: const Text('Edit', style: TextStyle(fontSize: 12)),
                      ),
                      const SizedBox(width: 8),
                      if (mapping.status != 'ACTIVE') ...[
                        OutlinedButton.icon(
                          onPressed: () => _validateMapping(mapping),
                          icon: const Icon(Icons.check_circle_outline, size: 14),
                          label: const Text('Validate', style: TextStyle(fontSize: 12)),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          onPressed: mapping.status == 'VALIDATED' ? () => _activateMapping(mapping) : null,
                          icon: const Icon(Icons.bolt, size: 14),
                          label: const Text('Activate', style: TextStyle(fontSize: 12)),
                        ),
                        const SizedBox(width: 8),
                      ],
                      IconButton(
                        onPressed: () => _deleteMapping(mapping),
                        icon: const Icon(Icons.delete_outline, size: 18),
                        color: colorScheme.error,
                        tooltip: 'Delete mapping',
                      ),
                    ],
                  ],
                ),
              ],
            ),
            if (mapping.validationErrors.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.errorContainer.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: colorScheme.error.withValues(alpha: 0.5)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.warning_amber_rounded, size: 16, color: colorScheme.error),
                        const SizedBox(width: 8),
                        Text(
                          'Validation Errors:',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: colorScheme.error),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ...mapping.validationErrors.map(
                      (err) => Text('• $err', style: TextStyle(fontSize: 11, color: colorScheme.error)),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            Divider(height: 1, color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
            const SizedBox(height: 12),
            ..._currentModel.entities.map((logicalEntity) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: _buildMappingTable(
                  context: context,
                  mapping: mapping,
                  logicalEntity: logicalEntity,
                  isEditing: isEditing,
                  schema: schema,
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildSourceMappingsTab(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (_isLoadingMappings) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: CircularProgressIndicator(color: colorScheme.primary),
        ),
      );
    }

    if (_mappings.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(40),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
        ),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.link_off, size: 40, color: colorScheme.onSurfaceVariant),
              const SizedBox(height: 12),
              const Text('No source mappings connected to this model.', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              const Text('Map a physical data source (PostgreSQL, SQLite) to resolve logical AltrQL queries.', style: TextStyle(fontSize: 12)),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _showAddMappingDialog,
                icon: const Icon(Icons.compare_arrows, size: 16),
                label: const Text('Map Data Source'),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _mappings.length,
      separatorBuilder: (_, _) => const SizedBox(height: 16),
      itemBuilder: (context, idx) {
        final mapping = _mappings[idx];
        return _buildSourceMappingCard(context, mapping);
      },
    );
  }
}
