import 'package:flutter/material.dart';

const List<String> kDestructiveKeywords = [
  'DROP',
  'TRUNCATE',
  'DELETE',
  'ALTER',
];

/// Strips leading single-line (--) and multi-line (/* */) comments to identify root verb.
String extractLeadingKeyword(String sql) {
  final clean = sql.trim();
  int pos = 0;
  final length = clean.length;

  while (pos < length) {
    // Skip whitespace
    if (clean[pos] == ' ' || clean[pos] == '\t' || clean[pos] == '\n' || clean[pos] == '\r') {
      pos++;
      continue;
    }

    // Skip single-line comment: -- ...
    if (pos + 1 < length && clean[pos] == '-' && clean[pos + 1] == '-') {
      pos += 2;
      while (pos < length && clean[pos] != '\n') {
        pos++;
      }
      continue;
    }

    // Skip multi-line comment: /* ... */
    if (pos + 1 < length && clean[pos] == '/' && clean[pos + 1] == '*') {
      pos += 2;
      while (pos + 1 < length && !(clean[pos] == '*' && clean[pos + 1] == '/')) {
        pos++;
      }
      pos += 2;
      continue;
    }

    // First non-comment, non-whitespace character encountered
    break;
  }

  if (pos >= length) return '';

  final remaining = clean.substring(pos);
  final firstWord = remaining.split(RegExp(r'\s+')).first.toUpperCase();
  return firstWord;
}

bool isDestructiveQuery(String sql) {
  final verb = extractLeadingKeyword(sql);
  return kDestructiveKeywords.contains(verb);
}

class DestructiveQueryDialog extends StatelessWidget {
  final String query;

  const DestructiveQueryDialog({
    super.key,
    required this.query,
  });

  static Future<bool> show(BuildContext context, String query) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => DestructiveQueryDialog(query: query),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final keyword = extractLeadingKeyword(query);

    return AlertDialog(
      backgroundColor: colorScheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: colorScheme.errorContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.warning_amber_rounded, size: 20, color: colorScheme.error),
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
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'You are about to execute a database modification command containing "$keyword". This operation may alter or permanently remove data or schemas.',
              style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
              ),
              child: Text(
                query.length > 200 ? '${query.substring(0, 200)}...' : query,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: colorScheme.error,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Are you sure you want to proceed with execution against the live database?',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: colorScheme.onSurface),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text('Cancel', style: TextStyle(color: colorScheme.onSurfaceVariant)),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: colorScheme.error,
            foregroundColor: colorScheme.onError,
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Confirm & Execute'),
        ),
      ],
    );
  }
}
