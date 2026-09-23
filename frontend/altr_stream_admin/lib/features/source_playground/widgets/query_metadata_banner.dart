import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

class QueryMetadataBanner extends StatelessWidget {
  final int rowCount;
  final double executionTimeMs;
  final String sourceName;
  final VoidCallback? onCopyResults;

  const QueryMetadataBanner({
    super.key,
    required this.rowCount,
    required this.executionTimeMs,
    required this.sourceName,
    this.onCopyResults,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  HugeIcon(icon: HugeIcons.strokeRoundedCheckmarkCircle02, size: 14, color: colorScheme.primary),
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
            ),
          ),
          if (onCopyResults != null) ...[
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: onCopyResults,
              icon: const HugeIcon(icon: HugeIcons.strokeRoundedCopy01, size: 12),
              label: const Text(
                'Copy Results',
                style: TextStyle(fontSize: 11),
              ),
              style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
