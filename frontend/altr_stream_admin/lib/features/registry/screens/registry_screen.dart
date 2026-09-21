import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:hugeicons/hugeicons.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/models.dart';
import '../widgets/create_logical_model_dialog.dart';
import '../widgets/edit_logical_model_dialog.dart';

class RegistryScreen extends StatefulWidget {
  final ApiClient apiClient;
  final List<SourceModel> sources;
  final Function(LogicalModelModel model) onSelectModel;
  final String nodeStatus;
  final VoidCallback onNodeStatusTap;

  const RegistryScreen({
    super.key,
    required this.apiClient,
    required this.sources,
    required this.onSelectModel,
    this.nodeStatus = 'ACTIVE',
    required this.onNodeStatusTap,
  });

  @override
  State<RegistryScreen> createState() => RegistryScreenState();
}

class RegistryScreenState extends State<RegistryScreen> {
  List<LogicalModelModel> _models = [];
  RegistrySummaryModel? _summary;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    fetchRegistry();
  }

  Future<void> fetchRegistry() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final summary = await widget.apiClient.getRegistrySummary();
      final models = await widget.apiClient.listLogicalModels();
      setState(() {
        _summary = summary;
        _models = models;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _showCreateModelDialog() {
    showDialog(
      context: context,
      builder: (ctx) => CreateLogicalModelDialog(
        apiClient: widget.apiClient,
        onModelCreated: (newModel) {
          fetchRegistry();
          widget.onSelectModel(newModel);
        },
      ),
    );
  }

  void _showEditModelDialog(LogicalModelModel model) {
    showDialog(
      context: context,
      builder: (ctx) => EditLogicalModelDialog(
        apiClient: widget.apiClient,
        model: model,
        onModelUpdated: (_) {
          fetchRegistry();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Logical model updated successfully.')),
          );
        },
      ),
    );
  }

  Future<void> _deleteModel(LogicalModelModel model) async {
    final colorScheme = Theme.of(context).colorScheme;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colorScheme.surfaceContainerHigh,
        title: const Text('Delete Logical Model?'),
        content: Text(
          'Are you sure you want to delete "${model.name}" and all its entities and source mappings? This action cannot be undone.',
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
        await widget.apiClient.deleteLogicalModel(model.id);
        fetchRegistry();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Model "${model.name}" deleted.')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to delete model: $e'), backgroundColor: colorScheme.error),
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
        if (_isLoading)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(60),
              child: CircularProgressIndicator(color: colorScheme.primary),
            ),
          )
        else if (_error != null)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: colorScheme.errorContainer.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: colorScheme.error.withValues(alpha: 0.5)),
            ),
            child: Row(
              children: [
                HugeIcon(icon: HugeIcons.strokeRoundedAlertCircle, color: colorScheme.error, size: 24),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Error loading registry', style: TextStyle(fontWeight: FontWeight.bold, color: colorScheme.error)),
                      const SizedBox(height: 2),
                      Text(_error!, style: TextStyle(fontSize: 12, color: colorScheme.error)),
                    ],
                  ),
                ),
                ElevatedButton(onPressed: fetchRegistry, child: const Text('Retry')),
              ],
            ),
          )
        else ...[
          // Metrics Summary Cards
          if (_summary != null) ...[
            LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 768;
                return GridView.count(
                  crossAxisCount: isWide ? 4 : 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: isWide ? 2.2 : 1.8,
                  children: [
                    _buildMetricCard(
                      context,
                      title: 'Logical Models',
                      value: '${_summary!.totalModels}',
                      subtitle: 'Domain schemas',
                      icon: HugeIcons.strokeRoundedStructure01,
                    ),
                    _buildMetricCard(
                      context,
                      title: 'Logical Entities',
                      value: '${_summary!.totalEntities}',
                      subtitle: '${_summary!.totalLogicalFields} standard fields',
                      icon: HugeIcons.strokeRoundedTable01,
                    ),
                    _buildMetricCard(
                      context,
                      title: 'Source Mappings',
                      value: '${_summary!.totalSourceMappings}',
                      subtitle: '${_summary!.activeSourceMappings} active',
                      icon: HugeIcons.strokeRoundedLink01,
                    ),
                    _buildMetricCard(
                      context,
                      title: 'Mapping Status',
                      value: '${_summary!.draftSourceMappings + _summary!.validatedSourceMappings}',
                      subtitle: '${_summary!.errorSourceMappings} with errors',
                      icon: HugeIcons.strokeRoundedCheckmarkBadge01,
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 24),
          ],

          // Models List Header
          Row(
            children: [
              Text(
                'Logical Models',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${_models.length}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Models List / Empty State
          if (_models.isEmpty)
            _buildEmptyState(context)
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _models.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final model = _models[index];
                return Card(
                  elevation: 0,
                  color: colorScheme.surfaceContainer,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                  ),
                  child: InkWell(
                    onTap: () => widget.onSelectModel(model),
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: colorScheme.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: HugeIcon(icon: HugeIcons.strokeRoundedStructure01, color: colorScheme.primary, size: 22),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      model.name,
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: colorScheme.onSurface,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: colorScheme.surfaceContainerHighest,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        'v${model.version}',
                                        style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  model.description ?? '${model.entityCount} entities, ${model.totalFieldCount} fields defined',
                                  style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Updated ${DateFormat.yMMMd().format(model.updatedAt)}',
                                  style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8)),
                                ),
                              ],
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => widget.onSelectModel(model),
                            icon: const HugeIcon(icon: HugeIcons.strokeRoundedArrowRight01, size: 14),
                            label: const Text('Inspect'),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            onPressed: () => _showEditModelDialog(model),
                            icon: const HugeIcon(icon: HugeIcons.strokeRoundedEdit02, size: 18),
                            tooltip: 'Edit Model',
                          ),
                          const SizedBox(width: 4),
                          IconButton(
                            onPressed: () => _deleteModel(model),
                            icon: const HugeIcon(icon: HugeIcons.strokeRoundedDelete02, size: 18),
                            color: colorScheme.error,
                            tooltip: 'Delete Model',
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
        ],
      ],
    );
  }

  Widget _buildMetricCard(
    BuildContext context, {
    required String title,
    required String value,
    required String subtitle,
    required icon,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: colorScheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: HugeIcon(icon: icon, color: colorScheme.primary, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
                Text(
                  title,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: colorScheme.onSurface),
                ),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 10, color: colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(48),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Center(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: HugeIcon(icon: HugeIcons.strokeRoundedStructure01, size: 36, color: colorScheme.primary),
            ),
            const SizedBox(height: 16),
            Text(
              'No Logical Models Defined',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
            ),
            const SizedBox(height: 8),
            Text(
              'Create a logical model to define your source-agnostic domain entities\nand map them to your PostgreSQL or SQLite data sources.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant, height: 1.5),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _showCreateModelDialog,
              icon: const HugeIcon(icon: HugeIcons.strokeRoundedAdd01, size: 16),
              label: const Text('Create Your First Logical Model'),
            ),
          ],
        ),
      ),
    );
  }
}
