import 'package:flutter/material.dart';
import 'status_badge.dart';

class PageHeader extends StatelessWidget {
  final String title;
  final String description;
  final Widget? primaryAction;
  final Widget? secondaryAction;
  final String nodeStatus;
  final VoidCallback? onNodeStatusTap;

  const PageHeader({
    super.key,
    required this.title,
    required this.description,
    this.primaryAction,
    this.secondaryAction,
    this.nodeStatus = 'ACTIVE',
    this.onNodeStatusTap,
  });

  Widget _buildTitleSection(BuildContext context, ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                  letterSpacing: -0.4,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 12),
            if (onNodeStatusTap != null)
              InkWell(
                onTap: onNodeStatusTap,
                borderRadius: BorderRadius.circular(12),
                child: Tooltip(
                  message: 'Click to inspect node status & telemetry',
                  child: StatusBadge(status: nodeStatus),
                ),
              )
            else
              StatusBadge(status: nodeStatus),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          description,
          style: TextStyle(
            fontSize: 13,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final hasActions = primaryAction != null || secondaryAction != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < 640;
            if (isNarrow) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildTitleSection(context, colorScheme),
                  if (hasActions) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        ?secondaryAction,
                        ?primaryAction,
                      ],
                    ),
                  ],
                ],
              );
            }

            return Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: _buildTitleSection(context, colorScheme),
                ),
                if (hasActions) ...[
                  const SizedBox(width: 16),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      ?secondaryAction,
                      ?primaryAction,
                    ],
                  ),
                ],
              ],
            );
          },
        ),
        const SizedBox(height: 20),
        Divider(
          height: 1,
          thickness: 1,
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
        const SizedBox(height: 20),
      ],
    );
  }
}
