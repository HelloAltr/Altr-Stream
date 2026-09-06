import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/api/models.dart';

class QueryEditor extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onExecute;
  final VoidCallback onClear;
  final bool isExecuting;
  final bool canExecute;
  final FocusNode focusNode;
  final SourceModel? selectedSource;

  const QueryEditor({
    super.key,
    required this.controller,
    required this.onExecute,
    required this.onClear,
    required this.isExecuting,
    required this.canExecute,
    required this.focusNode,
    this.selectedSource,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final sourceTypeName = selectedSource?.type.toUpperCase() ?? 'NATIVE';

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Editor Top Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainer,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
              border: Border(
                bottom: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.terminal, size: 16, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Query Editor',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '$sourceTypeName QUERY',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.primary,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  '⌘ + Enter to execute',
                  style: TextStyle(
                    fontSize: 11,
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),

          // Text Field with CallbackShortcuts for ⌘+Enter / Ctrl+Enter
          Expanded(
            child: CallbackShortcuts(
              bindings: <ShortcutActivator, VoidCallback>{
                const SingleActivator(LogicalKeyboardKey.enter, meta: true): () {
                  if (canExecute && !isExecuting) {
                    onExecute();
                  }
                },
                const SingleActivator(LogicalKeyboardKey.enter, control: true): () {
                  if (canExecute && !isExecuting) {
                    onExecute();
                  }
                },
              },
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                maxLines: null,
                expands: true,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  height: 1.5,
                  color: colorScheme.onSurface,
                ),
                cursorColor: colorScheme.primary,
                decoration: InputDecoration(
                  hintText: '-- Write a native physical query\nSELECT * FROM users LIMIT 10;',
                  hintStyle: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.all(14),
                ),
              ),
            ),
          ),

          // Editor Bottom Actions
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainer,
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(11)),
              border: Border(
                top: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
              ),
            ),
            child: Row(
              children: [
                TextButton.icon(
                  onPressed: isExecuting ? null : onClear,
                  icon: const Icon(Icons.clear_all, size: 16),
                  label: const Text('Clear'),
                  style: TextButton.styleFrom(
                    foregroundColor: colorScheme.onSurfaceVariant,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: (canExecute && !isExecuting) ? onExecute : null,
                  icon: isExecuting
                      ? SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: colorScheme.onPrimary,
                          ),
                        )
                      : const Icon(Icons.play_arrow_rounded, size: 18),
                  label: Text(isExecuting ? 'Running...' : 'Run Query'),
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
