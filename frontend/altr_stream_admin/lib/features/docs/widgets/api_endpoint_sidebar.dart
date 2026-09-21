import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import '../models/api_endpoint_model.dart';

/// Left-region navigation sidebar displaying tag-grouped API endpoints,
/// method filters, tag filters, and active selection state.
class ApiEndpointSidebar extends StatefulWidget {
  final List<ApiEndpoint> endpoints;
  final ApiEndpoint? selectedEndpoint;
  final ValueChanged<ApiEndpoint> onSelectEndpoint;
  final String? selectedMethod;
  final ValueChanged<String?> onMethodChanged;
  final String? selectedTag;
  final ValueChanged<String?> onTagChanged;
  final List<String> availableMethods;
  final List<String> availableTags;
  final int? totalCount;
  final int? filteredCount;
  final VoidCallback onClearFilters;

  const ApiEndpointSidebar({
    super.key,
    required this.endpoints,
    required this.selectedEndpoint,
    required this.onSelectEndpoint,
    required this.selectedMethod,
    required this.onMethodChanged,
    required this.selectedTag,
    required this.onTagChanged,
    required this.availableMethods,
    required this.availableTags,
    this.totalCount,
    this.filteredCount,
    required this.onClearFilters,
  });

  @override
  State<ApiEndpointSidebar> createState() => _ApiEndpointSidebarState();
}

class _ApiEndpointSidebarState extends State<ApiEndpointSidebar> {
  final Set<String> _collapsedTags = {};

  void _toggleTagCollapse(String tag) {
    setState(() {
      if (_collapsedTags.contains(tag)) {
        _collapsedTags.remove(tag);
      } else {
        _collapsedTags.add(tag);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Group endpoints by primary tag
    final Map<String, List<ApiEndpoint>> grouped = {};
    for (final ep in widget.endpoints) {
      grouped.putIfAbsent(ep.primaryTag, () => []).add(ep);
    }

    final tags = grouped.keys.toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final hasBoundedHeight = constraints.hasBoundedHeight;

        final listWidget = widget.endpoints.isEmpty
            ? _buildEmptyState(context)
            : ListView.builder(
                shrinkWrap: !hasBoundedHeight,
                physics: !hasBoundedHeight
                    ? const NeverScrollableScrollPhysics()
                    : null,
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: tags.length,
                itemBuilder: (context, index) {
                  final tag = tags[index];
                  final groupEndpoints = grouped[tag]!;
                  final isCollapsed = _collapsedTags.contains(tag);

                  return _buildTagGroup(
                    context,
                    tag: tag,
                    endpoints: groupEndpoints,
                    isCollapsed: isCollapsed,
                  );
                },
              );

        return Container(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            border: Border(
              right: BorderSide(
                color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                width: 1,
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: hasBoundedHeight
                ? MainAxisSize.max
                : MainAxisSize.min,
            children: [
              // 1. Sidebar Header: Quick Filter Dropdowns & Stats
              _buildFilterHeader(context),
              Divider(
                height: 1,
                thickness: 1,
                color: colorScheme.outlineVariant.withValues(alpha: 0.4),
              ),

              // 2. Scrollable Endpoint Navigation Groups
              if (hasBoundedHeight) Expanded(child: listWidget) else listWidget,
            ],
          ),
        );
      },
    );
  }

  Widget _buildFilterHeader(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasActiveFilter =
        widget.selectedMethod != null ||
        widget.selectedTag != null ||
        (widget.totalCount != null &&
            widget.filteredCount != null &&
            widget.filteredCount! < widget.totalCount!);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  widget.totalCount != null
                      ? (widget.filteredCount == widget.totalCount
                            ? '${widget.totalCount} endpoints'
                            : '${widget.filteredCount} of ${widget.totalCount} endpoints')
                      : '${widget.endpoints.length} endpoints',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.3,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (hasActiveFilter)
                InkWell(
                  onTap: widget.onClearFilters,
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 2,
                    ),
                    child: Text(
                      'Reset Filters',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.primary,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),

          // Method & Tag Filter Selectors
          Row(
            children: [
              // Method Dropdown
              Expanded(
                flex: 4,
                child: Container(
                  height: 32,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: colorScheme.surface,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      key: const Key('api_method_filter_dropdown'),
                      value: widget.selectedMethod,
                      hint: Text(
                        'Method',
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      isExpanded: true,
                      icon: HugeIcon(
                        icon: HugeIcons.strokeRoundedArrowDown01,
                        size: 18,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurface,
                      ),
                      items: [
                        DropdownMenuItem<String>(
                          value: null,
                          child: Text(
                            'All Methods',
                            style: TextStyle(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        for (final m in widget.availableMethods)
                          DropdownMenuItem<String>(
                            value: m,
                            child: Row(
                              children: [
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: _getMethodColor(m, context),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  m,
                                  style: TextStyle(
                                    fontFamily: 'monospace',
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11,
                                    color: _getMethodColor(m, context),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                      onChanged: widget.onMethodChanged,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),

              // Tag Dropdown
              Expanded(
                flex: 5,
                child: Container(
                  height: 32,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: colorScheme.surface,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      key: const Key('api_tag_filter_dropdown'),
                      value: widget.selectedTag,
                      hint: Text(
                        'Tag',
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      isExpanded: true,
                      icon: HugeIcon(
                        icon: HugeIcons.strokeRoundedArrowDown01,
                        size: 18,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurface,
                      ),
                      items: [
                        DropdownMenuItem<String>(
                          value: null,
                          child: Text(
                            'All Tags',
                            style: TextStyle(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        for (final t in widget.availableTags)
                          DropdownMenuItem<String>(
                            value: t,
                            child: Text(
                              t,
                              style: const TextStyle(fontSize: 12),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: widget.onTagChanged,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTagGroup(
    BuildContext context, {
    required String tag,
    required List<ApiEndpoint> endpoints,
    required bool isCollapsed,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Tag Header
        InkWell(
          onTap: () => _toggleTagCollapse(tag),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              children: [
                HugeIcon(
                  icon: isCollapsed ? HugeIcons.strokeRoundedArrowRight01 : HugeIcons.strokeRoundedArrowDown01,
                  size: 16,
                  color: colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    tag,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1.5,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${endpoints.length}',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // Endpoints List under this tag
        if (!isCollapsed)
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: endpoints.length,
            itemBuilder: (ctx, idx) =>
                _buildEndpointTile(context, endpoints[idx]),
          ),

        const SizedBox(height: 4),
      ],
    );
  }

  Widget _buildEndpointTile(BuildContext context, ApiEndpoint ep) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isSelected =
        widget.selectedEndpoint?.path == ep.path &&
        widget.selectedEndpoint?.method == ep.method;
    final methodColor = _getMethodColor(ep.method, context);

    return InkWell(
      key: Key('api_endpoint_${ep.method}_${ep.path}'),
      onTap: () => widget.onSelectEndpoint(ep),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? colorScheme.primaryContainer.withValues(alpha: 0.4)
              : Colors.transparent,
          border: Border(
            left: BorderSide(
              color: isSelected ? colorScheme.primary : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        child: Row(
          children: [
            // HTTP Method Badge
            Container(
              width: 48,
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: methodColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: methodColor.withValues(alpha: 0.4),
                  width: 0.8,
                ),
              ),
              child: Center(
                child: Text(
                  ep.method,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 9.5,
                    fontWeight: FontWeight.bold,
                    color: methodColor,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),

            // Endpoint Path
            Expanded(
              child: Text(
                ep.path,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11.5,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  color: isSelected
                      ? colorScheme.primary
                      : colorScheme.onSurface,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            HugeIcon(
              icon: HugeIcons.strokeRoundedSearchRemove,
              size: 36,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 10),
            Text(
              'No endpoints match',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Try changing search or filters',
              style: TextStyle(
                fontSize: 11,
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: widget.onClearFilters,
              child: const Text(
                'Clear Filters',
                style: TextStyle(fontSize: 11),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Color _getMethodColor(String method, BuildContext context) {
    switch (method.toUpperCase()) {
      case 'GET':
        return const Color(0xFF38A169);
      case 'POST':
        return const Color(0xFF3182CE);
      case 'PUT':
        return const Color(0xFFDD6B20);
      case 'DELETE':
        return const Color(0xFFE53E3E);
      case 'PATCH':
        return const Color(0xFF805AD5);
      case 'HEAD':
        return const Color(0xFF319795);
      default:
        return Theme.of(context).colorScheme.primary;
    }
  }
}
