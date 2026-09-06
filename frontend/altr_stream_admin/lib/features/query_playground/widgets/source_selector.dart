import 'package:flutter/material.dart';
import '../../../core/api/models.dart';
import '../../../core/theme/app_theme.dart';

class SourceSelector extends StatelessWidget {
  final List<SourceModel> sources;
  final SourceModel? selectedSource;
  final ValueChanged<SourceModel?> onSourceSelected;
  final bool isExecuting;

  const SourceSelector({
    super.key,
    required this.sources,
    required this.selectedSource,
    required this.onSourceSelected,
    this.isExecuting = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (sources.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
        ),
        child: Row(
          children: [
            Icon(Icons.info_outline, color: colorScheme.error, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'No data sources registered. Please add a data source in the Data Sources page before executing queries.',
                style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Icon(Icons.dns_outlined, size: 20, color: colorScheme.primary),
          const SizedBox(width: 12),
          Text(
            'Target Source:',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                isExpanded: true,
                value: selectedSource?.id,
                hint: Text(
                  'Select a data source to query...',
                  style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13),
                ),
                dropdownColor: colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(12),
                icon: Icon(Icons.keyboard_arrow_down, color: colorScheme.onSurfaceVariant),
                onChanged: isExecuting
                    ? null
                    : (id) {
                        if (id == null) {
                          onSourceSelected(null);
                        } else {
                          final src = sources.firstWhere((s) => s.id == id);
                          onSourceSelected(src);
                        }
                      },
                items: sources.map((source) {
                  final statusColor = AppTheme.getStatusColor(source.status, context);
                  return DropdownMenuItem<String>(
                    value: source.id,
                    child: Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: statusColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          source.name,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            source.type,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '(${source.host}:${source.port}/${source.databaseName})',
                          style: TextStyle(
                            fontSize: 11,
                            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
