import 'package:flutter/material.dart';

class QueryMetadataBanner extends StatelessWidget {
  final int rowCount;
  final double executionTimeMs;
  final String sourceName;

  const QueryMetadataBanner({
    super.key,
    required this.rowCount,
    required this.executionTimeMs,
    required this.sourceName,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle, size: 14, color: colorScheme.primary),
          const SizedBox(width: 8),
          Text(
            'Success',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: colorScheme.primary,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '·',
            style: TextStyle(color: colorScheme.onSurfaceVariant, fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 8),
          Text(
            '$rowCount ${rowCount == 1 ? "row" : "rows"}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '·',
            style: TextStyle(color: colorScheme.onSurfaceVariant, fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 8),
          Text(
            '${executionTimeMs.toStringAsFixed(1)} ms',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurfaceVariant,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '·',
            style: TextStyle(color: colorScheme.onSurfaceVariant, fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 8),
          Text(
            sourceName,
            style: TextStyle(
              fontSize: 11,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
