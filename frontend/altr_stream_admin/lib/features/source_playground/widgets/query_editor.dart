import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hugeicons/hugeicons.dart';
import '../../../core/api/models.dart';

class QueryEditor extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onExecute;
  final VoidCallback onClear;
  final bool isExecuting;
  final bool canExecute;
  final FocusNode focusNode;
  final SourceModel? selectedSource;
  final String? mongoQueryMode;
  final ValueChanged<String>? onMongoQueryModeChanged;

  const QueryEditor({
    super.key,
    required this.controller,
    required this.onExecute,
    required this.onClear,
    required this.isExecuting,
    required this.canExecute,
    required this.focusNode,
    this.selectedSource,
    this.mongoQueryMode,
    this.onMongoQueryModeChanged,
  });

  String _getHintText(SourceModel? source, String? mode) {
    final type = source?.type.toUpperCase() ?? '';
    switch (type) {
      case 'POSTGRESQL':
        return 'Type in a PostgreSQL query to execute it';
      case 'MYSQL':
        return 'Type in a MySQL query to execute it';
      case 'SQLITE':
        return 'Type in a SQLite query to execute it';
      case 'MONGODB':
        if (mode == 'physical') {
          return 'Type a physical JSON command, e.g. {"collection": "users", "filter": {}}';
        }
        return 'Type a MongoDB query, e.g. db.users.find().pretty()';
      default:
        return 'Type in a physical query to execute it';
    }
  }

  Map<String, String> _getTemplates(SourceModel? source, String? mode) {
    final type = source?.type.toUpperCase() ?? '';
    if (type == 'MONGODB') {
      if (mode == 'physical') {
        return {
          'Find Documents (limit 10)': '''{
  "collection": "collection_name",
  "filter": {},
  "limit": 10
}''',
          'Find with Projection & Sort': '''{
  "collection": "collection_name",
  "filter": {},
  "projection": {"_id": 1},
  "sort": [["_id", -1]],
  "limit": 10
}''',
          'Insert Documents': '''{
  "collection": "collection_name",
  "documents": [
    {"name": "Item 1", "status": "active"}
  ]
}''',
          'Update Documents': '''{
  "collection": "collection_name",
  "filter": {"status": "active"},
  "update": {"\$set": {"status": "updated"}}
}''',
          'Delete Documents': '''{
  "collection": "collection_name",
  "filter": {"status": "archived"}
}''',
        };
      } else {
        return {
          'Basic Find': 'db.collection_name.find().pretty()',
          'Find with Filter': 'db.collection_name.find({ status: "active" })',
          'Find with Projection': 'db.collection_name.find({}, { username: 1, age: 1, _id: 0 })',
          'Sort & Limit': 'db.collection_name.find().sort({ age: -1 }).limit(10)',
          'Chained Find': 'db.collection_name.find({ status: "active" }).sort({ age: -1 }).skip(10).limit(20)',
          'Insert Documents': '''db.collection_name.insertMany([
  { name: "alice", age: 25 },
  { name: "bob", age: 30 }
])''',
          'Update Documents': '''db.collection_name.updateMany(
  { status: "active" },
  { \$set: { status: "updated" } }
)''',
          'Delete Documents': '''db.collection_name.deleteMany({
  status: "inactive"
})''',
        };
      }
    } else {
      return {
        'Select Top 10': 'SELECT * FROM table_name LIMIT 10;',
        'Count Records': 'SELECT COUNT(*) AS count FROM table_name;',
        'Filter by Condition': 'SELECT * FROM table_name WHERE id = 1;',
        'Aggregate Group By': 'SELECT category, COUNT(*) AS count FROM table_name GROUP BY category;',
      };
    }
  }

  void _handleTabKey() {
    final text = controller.text;
    final selection = controller.selection;
    if (selection.start >= 0) {
      final newText = text.replaceRange(
        selection.start,
        selection.end,
        '  ',
      );
      controller.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(
          offset: selection.start + 2,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isMongo = selectedSource?.type.toUpperCase() == 'MONGODB';
    final sourceTypeName = selectedSource?.type.toUpperCase() ?? 'NATIVE';
    final currentMode = mongoQueryMode ?? 'shell';
    final templates = _getTemplates(selectedSource, currentMode);

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header with DB info, Mode Selector (for MongoDB) & Clear Button
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainer,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
              border: Border(
                bottom: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
              ),
            ),
            child: Row(
              children: [
                HugeIcon(icon: HugeIcons.strokeRoundedCommandLine, size: 16, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Query Editor',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
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
                if (isMongo) ...[
                  const SizedBox(width: 12),
                  Container(
                    height: 26,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.7)),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: currentMode,
                        isDense: true,
                        icon: HugeIcon(icon: HugeIcons.strokeRoundedArrowDown01, size: 16, color: colorScheme.onSurfaceVariant),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurface,
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'shell',
                            child: Text('MongoDB Shell'),
                          ),
                          DropdownMenuItem(
                            value: 'physical',
                            child: Text('Physical Command'),
                          ),
                        ],
                        onChanged: isExecuting
                            ? null
                            : (val) {
                                if (val != null && onMongoQueryModeChanged != null) {
                                  onMongoQueryModeChanged!(val);
                                }
                              },
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                OutlinedButton.icon(
                  icon: const HugeIcon(icon: HugeIcons.strokeRoundedRefresh, size: 14),
                  label: const Text(
                    'Clear',
                    style: TextStyle(fontSize: 12),
                  ),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                  ),
                  onPressed: isExecuting
                      ? null
                      : () {
                          onClear();
                          focusNode.requestFocus();
                        },
                ),
              ],
            ),
          ),

          // Text Field with Top Alignment, Tab Support, Monospace Code Font, and Generous Padding
          Expanded(
            child: CallbackShortcuts(
              bindings: <ShortcutActivator, VoidCallback>{
                const SingleActivator(LogicalKeyboardKey.tab): _handleTabKey,
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
                textAlignVertical: TextAlignVertical.top,
                style: GoogleFonts.robotoMono(
                  fontWeight: FontWeight.normal,
                  fontSize: 13,
                  color: colorScheme.onSurface,
                  height: 1.5,
                  letterSpacing: 0.2,
                ),
                cursorColor: colorScheme.primary,
                decoration: InputDecoration(
                  hintText: _getHintText(selectedSource, currentMode),
                  hintStyle: GoogleFonts.robotoMono(
                    fontWeight: FontWeight.normal,
                    fontSize: 13,
                    height: 1.5,
                    letterSpacing: 0.2,
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.45),
                  ),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: const EdgeInsets.all(16),
                ),
              ),
            ),
          ),

          // Footer Action Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainer,
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(11)),
              border: Border(
                top: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
              ),
            ),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: [
                Text(
                  'Shortcuts: ⌘/Ctrl + Enter to Execute · Tab to Indent',
                  style: TextStyle(
                    fontSize: 11,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    PopupMenuButton<String>(
                      tooltip: 'Insert Template',
                      onSelected: (templateValue) {
                        controller.text = templateValue;
                        focusNode.requestFocus();
                      },
                      itemBuilder: (context) => templates.entries.map((entry) {
                        return PopupMenuItem<String>(
                          value: entry.value,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Row(
                            children: [
                              HugeIcon(
                                icon: HugeIcons.strokeRoundedCode,
                                size: 14,
                                color: colorScheme.primary,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  entry.key,
                                  style: const TextStyle(fontSize: 12),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: colorScheme.outlineVariant.withValues(alpha: 0.8),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            HugeIcon(
                              icon: HugeIcons.strokeRoundedCode,
                              size: 14,
                              color: colorScheme.primary,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Templates',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(width: 2),
                            HugeIcon(
                              icon: HugeIcons.strokeRoundedArrowDown01,
                              size: 16,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ],
                        ),
                      ),
                    ),
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
                          : const HugeIcon(icon: HugeIcons.strokeRoundedPlay, size: 18),
                      label: Text(isExecuting ? 'Running...' : 'Run Query'),
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
