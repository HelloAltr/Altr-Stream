import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import '../../../core/api/models.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/status_badge.dart';

class SourcesScreen extends StatefulWidget {
  final List<SourceModel> sources;
  final bool isLoading;
  final VoidCallback onRefresh;
  final VoidCallback onAddSource;
  final Function(SourceModel source) onSelectSource;
  final Function(SourceModel source)? onDeleteSource;
  final VoidCallback onNodeStatusTap;
  final String nodeStatus;
  final bool isEditMode;
  final bool isDeleteMode;

  const SourcesScreen({
    super.key,
    required this.sources,
    required this.isLoading,
    required this.onRefresh,
    required this.onAddSource,
    required this.onSelectSource,
    this.onDeleteSource,
    required this.onNodeStatusTap,
    this.nodeStatus = 'ACTIVE',
    this.isEditMode = false,
    this.isDeleteMode = false,
  });

  @override
  State<SourcesScreen> createState() => SourcesScreenState();
}

class SourcesScreenState extends State<SourcesScreen> {
  late final M3ESearchController _searchController;
  late final M3ERefreshIndicatorController _refreshController;
  String _searchQuery = '';
  String _filterStatus = 'ALL';
  bool _isRefreshing = false;

  Future<void> triggerRefresh() async {
    if (mounted) setState(() => _isRefreshing = true);
    widget.onRefresh();
    await Future.delayed(const Duration(milliseconds: 600));
    if (mounted) setState(() => _isRefreshing = false);
  }

  @override
  void initState() {
    super.initState();
    _searchController = M3ESearchController();
    _searchController.addListener(_onSearchChanged);
    _refreshController = M3ERefreshIndicatorController();
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

  void _showContextMenu(BuildContext context, Offset position, SourceModel source) async {
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
              const Text('Edit Source'),
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
              Text('Delete Source', style: TextStyle(color: colorScheme.error)),
            ],
          ),
        ),
      ],
    );

    if (selected == 'edit') {
      widget.onSelectSource(source);
    } else if (selected == 'delete') {
      widget.onDeleteSource?.call(source);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    // Filter sources
    final filteredSources = widget.sources.where((s) {
      final matchesQuery = _searchQuery.isEmpty ||
          s.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          (s.host?.toLowerCase().contains(_searchQuery.toLowerCase()) ?? false) ||
          (s.databaseName?.toLowerCase().contains(_searchQuery.toLowerCase()) ?? false) ||
          (s.filePath?.toLowerCase().contains(_searchQuery.toLowerCase()) ?? false) ||
          s.type.toLowerCase().contains(_searchQuery.toLowerCase());

      final matchesStatus = _filterStatus == 'ALL' ||
          (_filterStatus == 'ACTIVE' && s.isActive) ||
          (_filterStatus == 'UNREACHABLE' && s.isUnreachable);

      return matchesQuery && matchesStatus;
    }).toList();

    final Widget scrollContent = SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: ClampingScrollPhysics(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Search & Filter Toolbar with M3E Components
          Row(
            children: [
              Expanded(
                child: M3ESearchBar(
                  controller: _searchController,
                  hintText: 'Search sources by name, host, or database...',
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
              const SizedBox(width: 2),
              // M3EMenu replacement for dropdown menu
              M3EMenu(
                position: M3EMenuAnchorPosition.bottomStart,
                colorStyle: M3EMenuColorStyle.standard,
                closeOnSelect: true,
                selectedValue: _filterStatus,
                onSelected: (Object? value) {
                  if (value is String) {
                    setState(() => _filterStatus = value);
                  }
                },
                anchorBuilder: (BuildContext context, VoidCallback open) {
                  final labelText = _filterStatus == 'ALL'
                      ? 'All Statuses'
                      : _filterStatus == 'ACTIVE'
                          ? 'Active Only'
                          : 'Unreachable Only';
                  return SizedBox(
                    height: 56,
                    child: M3EButton.icon(
                      style: M3EButtonStyle.tonal,
                      icon: const Icon(M3EIcons.filter_list, size: 18),
                      label: Text(labelText),
                      onPressed: open,
                    ),
                  );
                },
                children: <M3EMenuNode>[
                  M3EMenuSelectable(
                    label: 'All Statuses',
                    value: 'ALL',
                    selected: _filterStatus == 'ALL',
                  ),
                  M3EMenuSelectable(
                    label: 'Active Only',
                    value: 'ACTIVE',
                    selected: _filterStatus == 'ACTIVE',
                  ),
                  M3EMenuSelectable(
                    label: 'Unreachable Only',
                    value: 'UNREACHABLE',
                    selected: _filterStatus == 'UNREACHABLE',
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Sources List / States
          if (widget.isLoading && widget.sources.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(60),
                child: CircularProgressIndicator(color: colorScheme.primary),
              ),
            )
          else if (widget.sources.isEmpty)
            _buildEmptyState(context)
          else if (filteredSources.isEmpty)
            _buildNoSearchResults(context)
          else
            _buildSourcesList(filteredSources),
        ],
      ),
    );

    return M3ERefreshIndicator.contained(
      controller: _refreshController,
      onRefresh: () async {
        if (mounted) setState(() => _isRefreshing = true);
        widget.onRefresh();
        await Future.delayed(const Duration(milliseconds: 1000));
        if (mounted) setState(() => _isRefreshing = false);
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
            child: HugeIcon(icon: HugeIcons.strokeRoundedDatabase, color: colorScheme.primary, size: 36),
          ),
          const SizedBox(height: 16),
          Text(
            'No data sources registered',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Connect your physical database to begin schema discovery and data federation.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: widget.onAddSource,
            icon: HugeIcon(icon: HugeIcons.strokeRoundedPlusSign, size: 16, color: colorScheme.onPrimary),
            label: const Text('Add Data Source'),
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
            'No matching data sources',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
          ),
          const SizedBox(height: 4),
          Text(
            'Try adjusting your search terms or filter criteria.',
            style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: () => setState(() {
              _searchQuery = '';
              _filterStatus = 'ALL';
            }),
            child: const Text('Reset Filters'),
          ),
        ],
      ),
    );
  }

  Widget _buildSourcesList(List<SourceModel> sources) {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: sources.length,
      separatorBuilder: (_, _) => const SizedBox(height: 6),
      itemBuilder: (context, index) {
        final source = sources[index];
        return _buildM3ESourceListItem(
          context: context,
          source: source,
          index: index,
          totalCount: sources.length,
        );
      },
    );
  }

  Widget _buildM3ESourceListItem({
    required BuildContext context,
    required SourceModel source,
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

    final subtext = source.type == 'SQLITE'
        ? '${source.type} • ${source.filePath ?? "Local File"}'
        : '${source.type} • ${source.host ?? "localhost"}:${source.port ?? 5432}/${source.databaseName ?? ""}';

    return Material(
      color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.6),
      borderRadius: borderRadius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: borderRadius,
        hoverColor: colorScheme.primary.withValues(alpha: 0.06),
        onTap: () {
          if (widget.isDeleteMode) {
            widget.onDeleteSource?.call(source);
          } else {
            widget.onSelectSource(source);
          }
        },
        onSecondaryTapDown: (details) {
          _showContextMenu(context, details.globalPosition, source);
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
                  icon: AppTheme.getSourceTypeIcon(source.type),
                  color: colorScheme.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 14),

              // Main Info (DB Name, DB Type, DB URL/URI)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            source.name,
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
                        StatusBadge(status: source.type, isTypeBadge: true),
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

              // Right side action/status
              if (widget.isDeleteMode) ...[
                IconButton.filledTonal(
                  style: IconButton.styleFrom(
                    backgroundColor: colorScheme.errorContainer,
                    foregroundColor: colorScheme.onErrorContainer,
                  ),
                  icon: const Icon(M3EIcons.delete, size: 20),
                  tooltip: 'Delete "${source.name}"',
                  onPressed: () => widget.onDeleteSource?.call(source),
                ),
              ] else if (widget.isEditMode) ...[
                IconButton.filledTonal(
                  style: IconButton.styleFrom(
                    backgroundColor: colorScheme.secondaryContainer,
                    foregroundColor: colorScheme.onSecondaryContainer,
                  ),
                  icon: const Icon(M3EIcons.edit, size: 20),
                  tooltip: 'Edit "${source.name}"',
                  onPressed: () => widget.onSelectSource(source),
                ),
              ] else ...[
                // Status Chip & Right Arrow (Right)
                StatusBadge(
                  status: (_isRefreshing || (widget.isLoading && source.isUnreachable))
                      ? 'PINGING'
                      : source.status,
                ),
                const SizedBox(width: 12),
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