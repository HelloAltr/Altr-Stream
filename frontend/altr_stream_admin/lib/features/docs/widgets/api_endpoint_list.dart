import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import '../models/api_endpoint_model.dart';

class ApiEndpointList extends StatelessWidget {
  final List<ApiEndpoint> endpoints;
  final ApiEndpoint? selectedEndpoint;
  final ValueChanged<ApiEndpoint> onSelectEndpoint;
  final VoidCallback onClearFilters;

  const ApiEndpointList({
    super.key,
    required this.endpoints,
    required this.selectedEndpoint,
    required this.onSelectEndpoint,
    required this.onClearFilters,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (endpoints.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              HugeIcon(icon: HugeIcons.strokeRoundedSearchRemove, size: 48, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
              const SizedBox(height: 12),
              Text(
                'No matching API endpoints found',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Try adjusting your search terms, method, or tag filters.',
                style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                icon: const HugeIcon(icon: HugeIcons.strokeRoundedRefresh, size: 16),
                label: const Text('Clear Filters'),
                onPressed: onClearFilters,
              ),
            ],
          ),
        ),
      );
    }

    // Group endpoints by primary tag
    final Map<String, List<ApiEndpoint>> grouped = {};
    for (final ep in endpoints) {
      grouped.putIfAbsent(ep.primaryTag, () => []).add(ep);
    }

    final tags = grouped.keys.toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < tags.length; i++) ...[
          if (i > 0) const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Group Header
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      HugeIcon(icon: HugeIcons.strokeRoundedFolder01, size: 16, color: colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        tags[i],
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${grouped[tags[i]]!.length}',
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
                Divider(height: 1, thickness: 1, color: colorScheme.outlineVariant.withValues(alpha: 0.4)),

                // Endpoint items
                ...grouped[tags[i]]!.map((ep) => _buildEndpointRow(context, ep)),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildEndpointRow(BuildContext context, ApiEndpoint ep) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isSelected = selectedEndpoint?.path == ep.path && selectedEndpoint?.method == ep.method;
    final methodColor = _getMethodColor(ep.method, context);

    return InkWell(
      key: Key('api_endpoint_${ep.method}_${ep.path}'),
      onTap: () => onSelectEndpoint(ep),
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? colorScheme.primaryContainer.withValues(alpha: 0.4) : Colors.transparent,
          border: Border(
            left: BorderSide(
              color: isSelected ? colorScheme.primary : Colors.transparent,
              width: 3.5,
            ),
            bottom: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.2)),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Method Badge
            Container(
              width: 62,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              decoration: BoxDecoration(
                color: methodColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: methodColor.withValues(alpha: 0.5)),
              ),
              child: Center(
                child: Text(
                  ep.method,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: methodColor,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),

            // Path & Summary
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ep.path,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                      color: isSelected ? colorScheme.primary : colorScheme.onSurface,
                    ),
                  ),
                  if (ep.summary.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      ep.summary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // Selection Arrow or chevron
            HugeIcon(
              icon: HugeIcons.strokeRoundedArrowRight01,
              size: 14,
              color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
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
