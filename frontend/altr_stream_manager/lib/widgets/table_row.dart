import 'package:flutter/material.dart' hide TableRow;
import 'middle_truncated_path_text.dart';

/// Uniform row for Altr Stream Manager status and configuration table.
class TableRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String rowLabel;
  final Color rowValueColor;
  final String rowValue;
  final Widget? trailingAction;
  final Widget? controls;

  const TableRow({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.rowLabel,
    required this.rowValueColor,
    required this.rowValue,
    this.trailingAction,
    this.controls,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: iconColor),
        const SizedBox(width: 16),
        Text(rowLabel, style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Flexible(
                    child: MiddleTruncatedPathText(
                      rowValue,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: rowValueColor),
                      textAlign: TextAlign.end,
                    ),
                  ),
                  if (trailingAction != null) ...[
                    const SizedBox(width: 8),
                    trailingAction!,
                  ],
                ],
              ),
              if (controls != null) ...[const SizedBox(height: 12), controls!],
            ],
          ),
        ),
      ],
    );
  }
}

/// Subtle horizontal divider between table rows.
class TableDivider extends StatelessWidget {
  final double height;

  const TableDivider({super.key, required this.height});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: height),
      child: Divider(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3)),
    );
  }
}
