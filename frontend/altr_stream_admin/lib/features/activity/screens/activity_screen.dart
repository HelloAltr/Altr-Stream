import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/api/models.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/page_header.dart';

class ActivityScreen extends StatelessWidget {
  final List<ActivityLogModel> activities;
  final VoidCallback onClear;
  final VoidCallback onNodeStatusTap;
  final String nodeStatus;

  const ActivityScreen({
    super.key,
    required this.activities,
    required this.onClear,
    required this.onNodeStatusTap,
    this.nodeStatus = 'ACTIVE',
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Context Header
        PageHeader(
          title: 'Activity',
          description: 'Operational timeline of connection, discovery, and lifecycle events on this node.',
          nodeStatus: nodeStatus,
          onNodeStatusTap: onNodeStatusTap,
          secondaryAction: activities.isNotEmpty
              ? OutlinedButton.icon(
                  onPressed: onClear,
                  icon: const Icon(Icons.clear_all, size: 14),
                  label: const Text('Clear Timeline'),
                )
              : null,
        ),

        if (activities.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 48),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainer,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
            ),
            child: Column(
              children: [
                Icon(Icons.history_toggle_off, size: 40, color: colorScheme.onSurfaceVariant),
                const SizedBox(height: 16),
                Text(
                  'No Activity Recorded Yet',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
                ),
                const SizedBox(height: 6),
                Text(
                  'Operational events like connection tests and schema discoveries will appear here.',
                  style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          )
        else
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: activities.length,
                separatorBuilder: (_, _) => const SizedBox(height: 18),
                itemBuilder: (context, index) {
                  final act = activities[index];
                  return _buildTimelineItem(context, act);
                },
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildTimelineItem(BuildContext context, ActivityLogModel act) {
    final dateFormat = DateFormat('yyyy-MM-dd • hh:mm a');
    final colorScheme = Theme.of(context).colorScheme;
    final statusActiveColor = AppTheme.getStatusColor('ACTIVE', context);

    IconData icon;
    Color iconColor;

    switch (act.type) {
      case ActivityType.nodeStart:
        icon = Icons.bolt;
        iconColor = colorScheme.primary;
        break;
      case ActivityType.sourceRegistered:
        icon = Icons.add_circle_outline;
        iconColor = statusActiveColor;
        break;
      case ActivityType.sourceUpdated:
        icon = Icons.edit_outlined;
        iconColor = colorScheme.tertiary;
        break;
      case ActivityType.sourceDeleted:
        icon = Icons.delete_outline;
        iconColor = colorScheme.error;
        break;
      case ActivityType.connectionTested:
        icon = Icons.wifi_tethering;
        iconColor = act.isSuccess ? statusActiveColor : colorScheme.error;
        break;
      case ActivityType.schemaDiscovered:
        icon = Icons.search;
        iconColor = colorScheme.primary;
        break;
      case ActivityType.healthCheck:
        icon = Icons.health_and_safety_outlined;
        iconColor = act.isSuccess ? statusActiveColor : colorScheme.error;
        break;
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: iconColor, size: 16),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    act.title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  Text(
                    dateFormat.format(act.timestamp),
                    style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                act.description,
                style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant, height: 1.4),
              ),
              if (act.sourceName != null) ...[
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'Source: ${act.sourceName}',
                    style: TextStyle(fontSize: 10, fontFamily: 'monospace', color: colorScheme.onSurfaceVariant),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
