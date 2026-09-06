import 'package:flutter/material.dart';

/// Helper function to strip leading SQL comments and extract the root statement verb.
String? extractLeadingKeyword(String sql) {
  var text = sql.trim();
  bool changed = true;

  while (changed) {
    changed = false;
    text = text.trimLeft();

    // Strip leading single-line comments: -- ...
    if (text.startsWith('--')) {
      final newlineIdx = text.indexOf('\n');
      if (newlineIdx != -1) {
        text = text.substring(newlineIdx + 1);
        changed = true;
      } else {
        return null; // Entire text is a comment
      }
    }

    // Strip leading multi-line comments: /* ... */
    if (text.startsWith('/*')) {
      final endIdx = text.indexOf('*/');
      if (endIdx != -1) {
        text = text.substring(endIdx + 2);
        changed = true;
      } else {
        return null; // Unclosed comment block
      }
    }
  }

  text = text.trimLeft();
  if (text.isEmpty) return null;

  final match = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*').firstMatch(text);
  return match?.group(0)?.toUpperCase();
}

/// Checks if a query is potentially destructive (DROP, TRUNCATE, DELETE, ALTER).
bool isDestructiveQuery(String sql) {
  final verb = extractLeadingKeyword(sql);
  if (verb == null) return false;
  return const {'DROP', 'TRUNCATE', 'DELETE', 'ALTER'}.contains(verb);
}

/// Modal dialog providing a UX guardrail before executing potentially destructive queries.
class DestructiveQueryDialog extends StatelessWidget {
  final String query;
  final String operationVerb;

  const DestructiveQueryDialog({
    super.key,
    required this.query,
    required this.operationVerb,
  });

  static Future<bool> show(BuildContext context, String query) async {
    final verb = extractLeadingKeyword(query) ?? 'DESTRUCTIVE';
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => DestructiveQueryDialog(
        query: query,
        operationVerb: verb,
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      backgroundColor: colorScheme.surfaceContainerHigh,
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: colorScheme.errorContainer.withValues(alpha: 0.5),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.warning_amber_rounded, color: colorScheme.error, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Potentially Destructive Operation',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'You are about to execute a "$operationVerb" statement. This operation may permanently alter, delete, or drop database objects and records.',
              style: TextStyle(
                fontSize: 13,
                color: colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Query Preview:',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
              ),
              child: SelectableText(
                query.trim(),
                maxLines: 6,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: colorScheme.error.withValues(alpha: 0.9),
                ),
              ),
            ),
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.of(context).pop(true),
          icon: const Icon(Icons.gavel_rounded, size: 16),
          label: const Text('Execute Anyway'),
          style: FilledButton.styleFrom(
            backgroundColor: colorScheme.error,
            foregroundColor: colorScheme.onError,
          ),
        ),
      ],
    );
  }
}
