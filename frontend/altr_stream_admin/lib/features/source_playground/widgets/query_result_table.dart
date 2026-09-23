import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

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
          borderRadius: BorderRadius.circular(28),
        ),
        child: Column(
          children: [
            HugeIcon(icon: HugeIcons.strokeRoundedInbox, size: 36, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
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

    final Map<String, double> colWidths = {};
    for (final col in columns) {
      double maxW = (col.length * 10.0) + 32.0;
      for (final row in rows.take(100)) {
        final val = row[col];
        final str = val == null ? 'NULL' : val.toString();
        final w = (str.length * 8.5) + 32.0;
        if (w > maxW) maxW = w;
      }
      colWidths[col] = maxW.clamp(100.0, 450.0);
    }

    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxHeight: 540),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(28),
      ),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Pinned Sticky Header Row
            Container(
              color: colorScheme.surfaceContainer,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 44,
                    child: Text(
                      '#',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                  ...columns.map(
                    (col) => SizedBox(
                      width: colWidths[col],
                      child: Text(
                        col,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface,
                          fontFamily: 'monospace',
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Divider(
              height: 1,
              thickness: 1,
              color: colorScheme.outlineVariant.withValues(alpha: 0.4),
            ),
            // Scrollable Data Rows
            Flexible(
              child: SingleChildScrollView(
                scrollDirection: Axis.vertical,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: rows.asMap().entries.map((entry) {
                    final idx = entry.key + 1;
                    final row = entry.value;

                    return Container(
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: colorScheme.outlineVariant.withValues(alpha: 0.2),
                          ),
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 44,
                            child: Text(
                              '$idx',
                              style: TextStyle(
                                fontSize: 11,
                                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                                fontFamily: 'monospace',
                              ),
                            ),
                          ),
                          ...columns.map((col) {
                            final val = row[col];
                            final strVal = val == null ? 'NULL' : val.toString();
                            final isNull = val == null;

                            return SizedBox(
                              width: colWidths[col],
                              child: SelectableText(
                                strVal,
                                style: TextStyle(
                                  color: isNull
                                      ? colorScheme.onSurfaceVariant.withValues(alpha: 0.5)
                                      : colorScheme.onSurface,
                                  fontStyle: isNull ? FontStyle.italic : FontStyle.normal,
                                  fontSize: 12,
                                  fontFamily: 'monospace',
                                ),
                                maxLines: 1,
                              ),
                            );
                          }),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
