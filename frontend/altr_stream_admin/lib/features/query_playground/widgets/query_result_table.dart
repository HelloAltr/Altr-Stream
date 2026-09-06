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

    if (columns.isEmpty && rows.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_outline, color: colorScheme.primary, size: 32),
            const SizedBox(height: 12),
            Text(
              'Query executed successfully',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '0 rows returned by the database engine.',
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(11),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SingleChildScrollView(
            scrollDirection: Axis.vertical,
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(colorScheme.surfaceContainer),
              headingTextStyle: TextStyle(
                fontFamily: 'monospace',
                fontWeight: FontWeight.bold,
                fontSize: 12,
                color: colorScheme.onSurface,
              ),
              dataTextStyle: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: colorScheme.onSurfaceVariant,
              ),
              horizontalMargin: 16,
              columnSpacing: 24,
              border: TableBorder(
                horizontalInside: BorderSide(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                  width: 1,
                ),
              ),
              columns: [
                const DataColumn(
                  label: Text('#', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                ...columns.map(
                  (col) => DataColumn(
                    label: Text(col),
                  ),
                ),
              ],
              rows: rows.asMap().entries.map((entry) {
                final rowIndex = entry.key + 1;
                final row = entry.value;

                return DataRow(
                  cells: [
                    DataCell(
                      Text(
                        '$rowIndex',
                        style: TextStyle(
                          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                          fontSize: 11,
                        ),
                      ),
                    ),
                    ...columns.map((col) {
                      final val = row[col];
                      if (val == null) {
                        return DataCell(
                          Text(
                            'null',
                            style: TextStyle(
                              fontStyle: FontStyle.italic,
                              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                            ),
                          ),
                        );
                      }
                      return DataCell(
                        SelectableText(
                          val.toString(),
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            color: colorScheme.onSurface,
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
      ),
    );
  }
}
