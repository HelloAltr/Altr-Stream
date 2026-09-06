import 'package:flutter/material.dart';

class QueryResultTable extends StatelessWidget {
  final List<String> columns;
  final List<Map<String, dynamic>> rows;

  const QueryResultTable({
    super.key,
    required this.columns,
    required this.rows,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (rows.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
        ),
        child: Column(
          children: [
            Icon(Icons.inbox_outlined, size: 36, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
            const SizedBox(height: 8),
            Text(
              'No records returned',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SingleChildScrollView(
          scrollDirection: Axis.vertical,
          child: DataTable(
            headingRowColor: WidgetStateProperty.all(colorScheme.surfaceContainer),
            dataRowColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.hovered)) {
                return colorScheme.surfaceContainerHighest.withValues(alpha: 0.5);
              }
              return Colors.transparent;
            }),
            columnSpacing: 24,
            horizontalMargin: 16,
            headingTextStyle: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurface,
              fontFamily: 'monospace',
            ),
            dataTextStyle: TextStyle(
              fontSize: 12,
              color: colorScheme.onSurface,
              fontFamily: 'monospace',
            ),
            columns: [
              const DataColumn(
                label: Text('#', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
              ),
              ...columns.map(
                (col) => DataColumn(
                  label: Text(col),
                ),
              ),
            ],
            rows: rows.asMap().entries.map((entry) {
              final idx = entry.key + 1;
              final row = entry.value;

              return DataRow(
                cells: [
                  DataCell(
                    Text(
                      idx.toString(),
                      style: TextStyle(color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6), fontSize: 11),
                    ),
                  ),
                  ...columns.map((col) {
                    final val = row[col];
                    final strVal = val == null ? 'NULL' : val.toString();
                    final isNull = val == null;

                    return DataCell(
                      SelectableText(
                        strVal,
                        style: TextStyle(
                          color: isNull ? colorScheme.onSurfaceVariant.withValues(alpha: 0.5) : colorScheme.onSurface,
                          fontStyle: isNull ? FontStyle.italic : FontStyle.normal,
                          fontSize: 12,
                        ),
                      ),
                    );
                  }),
                ],
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}
