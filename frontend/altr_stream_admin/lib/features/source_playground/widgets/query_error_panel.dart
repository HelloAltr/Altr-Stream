import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

class QueryErrorPanel extends StatelessWidget {
  final String errorMessage;
  final VoidCallback? onDismiss;
  final VoidCallback? onCopy;

  const QueryErrorPanel({
    super.key,
    required this.errorMessage,
    this.onDismiss,
    this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HugeIcon(icon: HugeIcons.strokeRoundedAlertCircle, size: 20, color: colorScheme.error),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Query Execution Failed',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.error,
                      ),
                    ),
                    const Spacer(),
                    if (onCopy != null) ...[
                      OutlinedButton.icon(
                        onPressed: onCopy,
                        icon: const HugeIcon(icon: HugeIcons.strokeRoundedCopy01, size: 12),
                        label: const Text(
                          'Copy Error',
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
                      const SizedBox(width: 8),
                    ],
                    if (onDismiss != null)
                      IconButton(
                        icon: HugeIcon(icon: HugeIcons.strokeRoundedCancel01, size: 16, color: colorScheme.onSurfaceVariant),
                        onPressed: onDismiss,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                SelectableText(
                  errorMessage,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    color: colorScheme.onErrorContainer,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
