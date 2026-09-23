import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
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

  final bool isDeleteMode;

  const RegistryScreen({
    super.key,
    required this.apiClient,
    required this.sources,
    required this.onSelectModel,
    this.nodeStatus = 'ACTIVE',
    required this.onNodeStatusTap,
    this.isDeleteMode = false,
  });

  @override
  State<RegistryScreen> createState() => RegistryScreenState();
}

class RegistryScreenState extends State<RegistryScreen> {
  late final M3ESearchController _searchController;
  late final M3ERefreshIndicatorController _refreshController;
  List<LogicalModelModel> _models = [];
  String _searchQuery = '';
  bool _isLoading = true;
  String? _error;

  Future<void> triggerRefresh() async {
    await fetchRegistry();
  }

  @override
  void initState() {
    super.initState();
    _searchController = M3ESearchController();
    _searchController.addListener(_onSearchChanged);
    _refreshController = M3ERefreshIndicatorController();
    fetchRegistry();
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _refreshController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    if (_searchQuery != _searchController.text) {
      setState(() {
        _searchQuery = _searchController.text;
      });
    }
  }

  Future<void> fetchRegistry() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final models = await widget.apiClient.listLogicalModels();
      if (mounted) {
        setState(() {
          _models = models;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
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
    final confirmed = await M3EDialog.show<bool>(
      context,
      barrierDismissible: true,
      dialog: M3EDialog(
        icon: HugeIcon(
          icon: HugeIcons.strokeRoundedDelete02,
          color: colorScheme.error,
          size: 28,
        ),
        title: 'Delete Logical Model?',
        content: Text(
          'Are you sure you want to delete "${model.name}" and all its entities and source mappings? This action cannot be undone.',
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

  void _showContextMenu(BuildContext context, Offset position, LogicalModelModel model) async {
    final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final colorScheme = Theme.of(context).colorScheme;

    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        position & const Size(40, 40),
        Offset.zero & overlay.size,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: colorScheme.surfaceContainerHigh,
      elevation: 4,
      items: [
        PopupMenuItem<String>(
          value: 'edit',
          child: Row(
            children: [
              HugeIcon(
                icon: HugeIcons.strokeRoundedEdit02,
                color: colorScheme.onSurface,
                size: 18,
              ),
              const SizedBox(width: 12),
              const Text('Edit Model'),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'delete',
          child: Row(
            children: [
              HugeIcon(
                icon: HugeIcons.strokeRoundedDelete02,
                color: colorScheme.error,
                size: 18,
              ),
              const SizedBox(width: 12),
              Text('Delete Model', style: TextStyle(color: colorScheme.error)),
            ],
          ),
        ),
      ],
    );

    if (selected == 'edit') {
      _showEditModelDialog(model);
    } else if (selected == 'delete') {
      _deleteModel(model);
    }
  }

  List<LogicalModelModel> get models => _models;

  void promptDeleteModelPicker() {
    if (_models.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No logical models available to delete.')),
      );
      return;
    }
    final colorScheme = Theme.of(context).colorScheme;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colorScheme.surfaceContainerHigh,
        title: const Text('Select Logical Model to Delete'),
        content: SizedBox(
          width: 400,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: _models.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final model = _models[index];
              return ListTile(
                leading: HugeIcon(
                  icon: HugeIcons.strokeRoundedHierarchySquare01,
                  color: colorScheme.primary,
                  size: 20,
                ),
                title: Text(model.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text('v${model.version} • ${model.entityCount} entities'),
                trailing: HugeIcon(
                  icon: HugeIcons.strokeRoundedDelete02,
                  color: colorScheme.error,
                  size: 18,
                ),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _deleteModel(model);
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final filteredModels = _models.where((m) {
      if (_searchQuery.isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      final nameMatches = m.name.toLowerCase().contains(q);
      final descMatches = m.description?.toLowerCase().contains(q) ?? false;
      final versionMatches = m.version.toLowerCase().contains(q);
      final entityMatches = m.entities.any((e) => e.name.toLowerCase().contains(q));
      return nameMatches || descMatches || versionMatches || entityMatches;
    }).toList();

    final scrollContent = SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: ClampingScrollPhysics(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Search Toolbar with M3E Search Bar
          Row(
            children: [
              Expanded(
                child: M3ESearchBar(
                  controller: _searchController,
                  hintText: 'Search logical models by name, entity, or description...',
                  enabled: true,
                  leading: HugeIcon(
                    icon: HugeIcons.strokeRoundedSearch01,
                    size: 18,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  trailing: _searchQuery.isNotEmpty
                      ? [
                          IconButton(
                            icon: HugeIcon(
                              icon: HugeIcons.strokeRoundedCancel01,
                              size: 16,
                              color: colorScheme.onSurfaceVariant,
                            ),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          ),
                        ]
                      : null,
                  onChanged: (val) {
                    setState(() => _searchQuery = val);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

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
          else if (_models.isEmpty)
            _buildEmptyState(context)
          else if (filteredModels.isEmpty)
            _buildNoSearchResults(context)
          else
            _buildModelsList(filteredModels),
        ],
      ),
    );

    return M3ERefreshIndicator.contained(
      controller: _refreshController,
      onRefresh: () async {
        await fetchRegistry();
      },
      triggerMode: M3ERefreshTriggerMode.onEdge,
      child: scrollContent,
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer.withValues(alpha: 0.5),
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
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: _showCreateModelDialog,
            icon: HugeIcon(icon: HugeIcons.strokeRoundedPlusSign, size: 16, color: colorScheme.onPrimary),
            label: const Text('Create Logical Model'),
          ),
        ],
      ),
    );
  }

  Widget _buildNoSearchResults(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        children: [
          HugeIcon(icon: HugeIcons.strokeRoundedSearchRemove, size: 32, color: colorScheme.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(
            'No matching logical models',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
          ),
          const SizedBox(height: 4),
          Text(
            'Try adjusting your search terms or keywords.',
            style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: () => setState(() {
              _searchQuery = '';
              _searchController.clear();
            }),
            child: const Text('Reset Search'),
          ),
        ],
      ),
    );
  }

  Widget _buildModelsList(List<LogicalModelModel> models) {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: models.length,
      separatorBuilder: (_, _) => const SizedBox(height: 6),
      itemBuilder: (context, index) {
        final model = models[index];
        return _buildM3EModelListItem(
          context: context,
          model: model,
          index: index,
          totalCount: models.length,
        );
      },
    );
  }

  Widget _buildM3EModelListItem({
    required BuildContext context,
    required LogicalModelModel model,
    required int index,
    required int totalCount,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final BorderRadius borderRadius;
    if (totalCount <= 1) {
      borderRadius = BorderRadius.circular(16);
    } else if (index == 0) {
      borderRadius = const BorderRadius.vertical(
        top: Radius.circular(16),
        bottom: Radius.circular(6),
      );
    } else if (index == totalCount - 1) {
      borderRadius = const BorderRadius.vertical(
        top: Radius.circular(6),
        bottom: Radius.circular(16),
      );
    } else {
      borderRadius = BorderRadius.circular(6);
    }

    final subtext = model.description != null && model.description!.trim().isNotEmpty
        ? '${model.entityCount} Entities • ${model.totalFieldCount} Fields • ${model.description}'
        : '${model.entityCount} Entities • ${model.totalFieldCount} Fields • Updated ${DateFormat.yMMMd().format(model.updatedAt)}';

    return Material(
      color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.6),
      borderRadius: borderRadius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: borderRadius,
        hoverColor: colorScheme.primary.withValues(alpha: 0.06),
        onTap: () {
          if (widget.isDeleteMode) {
            _deleteModel(model);
          } else {
            widget.onSelectModel(model);
          }
        },
        onSecondaryTapDown: (details) {
          _showContextMenu(context, details.globalPosition, model);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
          child: Row(
            children: [
              // Icon Badge
              Container(
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: HugeIcon(
                  icon: HugeIcons.strokeRoundedStructure01,
                  color: colorScheme.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 14),

              // Main Info (Model Name, Version, Entities/Fields/Description)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            model.name,
                            style: textTheme.bodyMedium?.copyWith(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.onSurface,
                              letterSpacing: -0.1,
                            ),
                            overflow: TextOverflow.ellipsis,
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
                      subtext,
                      style: textTheme.bodySmall?.copyWith(
                        fontSize: 12.5,
                        color: colorScheme.onSurfaceVariant.withValues(alpha: 0.85),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),

              // Right side action (Delete button in delete mode or arrow only)
              if (widget.isDeleteMode) ...[
                IconButton.filledTonal(
                  style: IconButton.styleFrom(
                    backgroundColor: colorScheme.errorContainer,
                    foregroundColor: colorScheme.onErrorContainer,
                  ),
                  icon: const Icon(M3EIcons.delete, size: 20),
                  tooltip: 'Delete "${model.name}"',
                  onPressed: () => _deleteModel(model),
                ),
              ] else ...[
                HugeIcon(
                  icon: HugeIcons.strokeRoundedArrowRight01,
                  size: 18,
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
