import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/api/models.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/page_header.dart';
import '../../../shared/widgets/status_badge.dart';

class OverviewScreen extends StatelessWidget {
  final List<SourceModel> sources;
  final List<ActivityLogModel> activities;
  final bool isLoading;
  final VoidCallback onRefresh;
  final VoidCallback onAddSource;
  final Function(SourceModel source) onSelectSource;
  final VoidCallback onViewAllSources;
  final VoidCallback onNodeStatusTap;
  final String nodeStatus;

  const OverviewScreen({
    super.key,
    required this.sources,
    required this.activities,
    required this.isLoading,
    required this.onRefresh,
    required this.onAddSource,
    required this.onSelectSource,
    required this.onViewAllSources,
    required this.onNodeStatusTap,
    this.nodeStatus = 'ACTIVE',
  });

  @override
  Widget build(BuildContext context) {
    final activeCount = sources.where((s) => s.isActive).length;
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Page Context Header
        PageHeader(
          title: 'Overview',
          description: 'Your local data federation node.',
          nodeStatus: nodeStatus,
          onNodeStatusTap: onNodeStatusTap,
          secondaryAction: OutlinedButton.icon(
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh, size: 14),
            label: const Text('Refresh'),
          ),
          primaryAction: ElevatedButton.icon(
            onPressed: onAddSource,
            icon: const Icon(Icons.add, size: 14),
            label: const Text('Add Data Source'),
          ),
        ),

        if (isLoading)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(60),
              child: CircularProgressIndicator(color: colorScheme.primary),
            ),
          )
        else if (sources.isEmpty)
          _buildEmptyState(context)
        else
          _buildOverviewContent(context, activeCount),
      ],
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer.withValues(alpha: 0.5),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.dns_outlined, color: colorScheme.primary, size: 36),
          ),
          const SizedBox(height: 16),
          Text(
            'No data sources connected',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Connect your first database to begin discovering\nand exposing data through this Altr Stream node.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant, height: 1.5),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: onAddSource,
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Add Data Source'),
          ),
        ],
      ),
    );
  }

  Widget _buildOverviewContent(BuildContext context, int activeCount) {
    final colorScheme = Theme.of(context).colorScheme;
    final statusActiveColor = AppTheme.getStatusColor('ACTIVE', context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Merged Connected Sources & Health Status Card
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header: Title, Health Count Badge & Manage Sources Action
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Connected Sources',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: colorScheme.onSurface,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: statusActiveColor.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: statusActiveColor.withValues(alpha: 0.3)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 6,
                                      height: 6,
                                      decoration: BoxDecoration(
                                        color: statusActiveColor,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      '$activeCount/${sources.length} Healthy',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: statusActiveColor,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${sources.length} ${sources.length == 1 ? "source" : "sources"} connected • PostgreSQL connector active',
                            style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: onViewAllSources,
                      child: Text('Manage Sources →', style: TextStyle(color: colorScheme.primary, fontSize: 13)),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Divider(height: 1, color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
                const SizedBox(height: 6),

                // Sources List
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: sources.length > 5 ? 5 : sources.length,
                  separatorBuilder: (_, _) => Divider(height: 1, color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
                  itemBuilder: (context, index) {
                    final source = sources[index];
                    return InkWell(
                      onTap: () => onSelectSource(source),
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: colorScheme.surfaceContainerHigh,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                              ),
                              child: Icon(Icons.storage, color: colorScheme.primary, size: 16),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    source.name,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: colorScheme.onSurface,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${source.type} • ${source.host}:${source.port}/${source.databaseName}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontFamily: 'monospace',
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            StatusBadge(status: source.status),
                            const SizedBox(width: 12),
                            Icon(Icons.chevron_right, color: colorScheme.onSurfaceVariant, size: 18),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),

        // Recent Activity Card
        if (activities.isNotEmpty) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Recent Node Activity',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 14),
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: activities.length > 4 ? 4 : activities.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final act = activities[index];
                      final dotColor = act.isSuccess ? colorScheme.primary : colorScheme.error;
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            margin: const EdgeInsets.only(top: 4),
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: dotColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  act.title,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: colorScheme.onSurface,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  act.description,
                                  style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            DateFormat('hh:mm a').format(act.timestamp),
                            style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}
