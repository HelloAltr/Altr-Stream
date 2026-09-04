import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
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

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 16,
          runSpacing: 12,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                        letterSpacing: -0.4,
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
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (secondaryAction != null) secondaryAction!,
                if (primaryAction != null) primaryAction!,
              ],
            ),
          ],
        ),
        const SizedBox(height: 20),
        const Divider(height: 1, thickness: 1, color: AppTheme.borderColor),
        const SizedBox(height: 20),
      ],
    );
  }
}
