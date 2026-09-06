import 'package:flutter/material.dart';

class QueryErrorPanel extends StatelessWidget {
  final String errorMessage;
  final VoidCallback? onDismiss;

  const QueryErrorPanel({
    super.key,
    required this.errorMessage,
    this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.error.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.error_outline, color: colorScheme.error, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Query Execution Failed',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onErrorContainer,
                  ),
                ),
              ),
              if (onDismiss != null)
                IconButton(
                  icon: Icon(Icons.close, size: 16, color: colorScheme.onErrorContainer),
                  onPressed: onDismiss,
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
            ],
          ),
          const SizedBox(height: 8),
          SelectableText(
            errorMessage,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              height: 1.4,
              color: colorScheme.onErrorContainer,
            ),
          ),
        ],
      ),
    );
  }
}
