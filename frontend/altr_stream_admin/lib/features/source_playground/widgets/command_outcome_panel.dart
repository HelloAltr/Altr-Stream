import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import '../../../core/api/models.dart';

class CommandOutcomePanel extends StatelessWidget {
  final QueryMetadataModel metadata;
  final String sourceName;
  final VoidCallback? onCopy;

  const CommandOutcomePanel({
    super.key,
    required this.metadata,
    required this.sourceName,
    this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final message = metadata.message ?? 'Command executed successfully';
    final affectedRows = metadata.affectedRows;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: HugeIcon(icon: HugeIcons.strokeRoundedCheckmarkBadge01, size: 20, color: colorScheme.primary),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Command Executed Successfully',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Executed against $sourceName in ${metadata.executionTimeMs.toStringAsFixed(1)} ms',
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (onCopy != null) ...[
                OutlinedButton.icon(
                  onPressed: onCopy,
                  icon: const HugeIcon(icon: HugeIcons.strokeRoundedCopy01, size: 12),
                  label: const Text(
                    'Copy Details',
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
          const SizedBox(height: 16),
          Divider(color: colorScheme.outlineVariant.withValues(alpha: 0.4), height: 1),
          const SizedBox(height: 16),
          Row(
            children: [
              if (affectedRows != null) ...[
                _buildMetricCard(
                  context,
                  label: 'Affected Rows',
                  value: affectedRows.toString(),
                  icon: HugeIcons.strokeRoundedSheet,
                ),
                const SizedBox(width: 16),
              ],
              _buildMetricCard(
                context,
                label: 'Execution Status',
                value: message,
                icon: HugeIcons.strokeRoundedTag01,
                isMonospace: true,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricCard(
    BuildContext context, {
    required String label,
    required String value,
    required icon,
    bool isMonospace = false,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            HugeIcon(icon: icon, size: 16, color: colorScheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      fontFamily: isMonospace ? 'monospace' : null,
                      color: colorScheme.onSurface,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
