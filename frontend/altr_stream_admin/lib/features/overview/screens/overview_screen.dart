import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'package:intl/intl.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:hugeicons/hugeicons.dart';
import '../../../core/api/models.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/status_badge.dart';
import '../services/overview_layout_service.dart';
import '../widgets/bento_grid_engine.dart';

class OverviewScreen extends StatefulWidget {
  final List<SourceModel> sources;
  final List<ActivityLogModel> activities;
  final bool isLoading;
  final UsageMetricsModel? usageMetrics;
  final VoidCallback onRefresh;
  final VoidCallback onAddSource;
  final Function(SourceModel source) onSelectSource;
  final VoidCallback onViewAllSources;
  final VoidCallback? onNavigateToRegistry;
  final VoidCallback onNodeStatusTap;
  final String nodeStatus;
  final String selectedTimeWindow;
  final Function(String window)? onTimeWindowChanged;
  final VoidCallback? onClearUsageData;

  const OverviewScreen({
    super.key,
    required this.sources,
    required this.activities,
    required this.isLoading,
    this.usageMetrics,
    required this.onRefresh,
    required this.onAddSource,
    required this.onSelectSource,
    required this.onViewAllSources,
    this.onNavigateToRegistry,
    required this.onNodeStatusTap,
    this.nodeStatus = 'ACTIVE',
    this.selectedTimeWindow = '30m',
    this.onTimeWindowChanged,
    this.onClearUsageData,
  });


  @override
  State<OverviewScreen> createState() => OverviewScreenState();
}

class OverviewScreenState extends State<OverviewScreen> {
  List<BentoCardConfig> _cardConfigs = OverviewLayoutService.getLayoutSync();
  bool _isEditMode = false;
  bool _isRefreshing = false;
  late final M3ERefreshIndicatorController _refreshController;
  Offset? _chartHoverOffset;

  Future<void> triggerRefresh() async {
    if (mounted) setState(() => _isRefreshing = true);
    widget.onRefresh();
    await Future.delayed(const Duration(milliseconds: 600));
    if (mounted) setState(() => _isRefreshing = false);
  }

  @override
  void initState() {
    super.initState();
    _refreshController = M3ERefreshIndicatorController();
  }

  @override
  void dispose() {
    _refreshController.dispose();
    super.dispose();
  }

  void _onLayoutChanged(List<BentoCardConfig> updated) {
    setState(() {
      _cardConfigs = updated;
    });
    OverviewLayoutService.saveLayout(_cardConfigs);
  }

  Future<void> _resetLayout() async {
    final reset = await OverviewLayoutService.resetLayout();
    if (mounted) {
      setState(() {
        _cardConfigs = reset;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeCount = widget.sources.where((s) => s.isActive).length;
    final colorScheme = Theme.of(context).colorScheme;

    final Widget scrollContent = SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: ClampingScrollPhysics(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.isLoading && widget.sources.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(60),
                child: CircularProgressIndicator(color: colorScheme.primary),
              ),
            )
          else if (widget.sources.isEmpty)
            _buildEmptyState(context)
          else ...[
            BentoGridEngine(
              configs: _cardConfigs,
              isEditMode: _isEditMode,
              onLayoutChanged: _onLayoutChanged,
              cardBuilder: (context, config) => _buildCardContent(
                context,
                config,
                activeCount,
              ),
            ),
            const SizedBox(height: 12),
            _buildBottomEditToolbar(context),
            const SizedBox(height: 16),
          ],
        ],
      ),
    );

    if (_isEditMode) {
      return scrollContent;
    }

    return M3ERefreshIndicator.contained(
      controller: _refreshController,
      onRefresh: () async {
        if (mounted) setState(() => _isRefreshing = true);
        widget.onRefresh();
        await Future.delayed(const Duration(milliseconds: 1000));
        if (mounted) setState(() => _isRefreshing = false);
      },
      triggerMode: M3ERefreshTriggerMode.onEdge,
      child: scrollContent,
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 56, horizontal: 28),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
              child: HugeIcon(
                icon: HugeIcons.strokeRoundedDatabase,
                color: colorScheme.primary,
                size: 36,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'No data sources connected',
              style: textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Connect your first database to begin discovering\nand exposing data through this Altr Stream node.',
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            M3EButton.icon(
              onPressed: widget.onAddSource,
              icon: HugeIcon(
                icon: HugeIcons.strokeRoundedPlusSign,
                size: 16,
                color: colorScheme.onPrimary,
              ),
              label: const Text('Add Data Source'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCardContent(
    BuildContext context,
    BentoCardConfig config,
    int activeCount,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final statusActiveColor = AppTheme.getStatusColor('ACTIVE', context);

    switch (config.id) {
      case 'kpi':
        return _buildKpiCard(
          context,
          colorScheme,
          textTheme,
          widget.sources.length,
          activeCount,
          statusActiveColor,
          config,
        );
      case 'usage':
        return _buildUsageCard(context, colorScheme, textTheme);
      case 'sources':
        return _buildSourcesListCard(context, colorScheme, textTheme, config);
      case 'registry':
        return _buildRegistryCard(context, colorScheme, textTheme, config);
      case 'activity':
        return _buildActivityCard(context, colorScheme, textTheme, config);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildBottomEditToolbar(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (!_isEditMode) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: OutlinedButton.icon(
            onPressed: () => setState(() => _isEditMode = true),
            icon: HugeIcon(
              icon: HugeIcons.strokeRoundedDashboardSquare02,
              size: 16,
              color: colorScheme.onSurfaceVariant,
            ),
            label: const Text('Edit Overview Layout'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              side: BorderSide(
                color: colorScheme.outlineVariant.withValues(alpha: 0.6),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),
        ),
      );
    }

    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: colorScheme.primary.withValues(alpha: 0.6),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          alignment: WrapAlignment.center,
          spacing: 12,
          runSpacing: 8,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: HugeIcon(
                    icon: HugeIcons.strokeRoundedEdit02,
                    size: 15,
                    color: colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Editing Overview Layout',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    Text(
                      'Drag = to rearrange • Drag corner to resize',
                      style: TextStyle(
                        fontSize: 11,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(width: 4),
            TextButton.icon(
              onPressed: _resetLayout,
              icon: HugeIcon(
                icon: HugeIcons.strokeRoundedRotateLeft01,
                size: 14,
                color: colorScheme.error,
              ),
              label: Text(
                'Reset to Default',
                style: TextStyle(fontSize: 12, color: colorScheme.error),
              ),
            ),
            ElevatedButton.icon(
              onPressed: () => setState(() => _isEditMode = false),
              icon: HugeIcon(
                icon: HugeIcons.strokeRoundedTick01,
                size: 14,
                color: colorScheme.onPrimary,
              ),
              label: const Text('Done'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKpiCard(
    BuildContext context,
    ColorScheme colorScheme,
    TextTheme textTheme,
    int totalSources,
    int activeCount,
    Color statusActiveColor,
    BentoCardConfig config,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    'Connected Sources',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: HugeIcon(
                    icon: HugeIcons.strokeRoundedDatabase,
                    color: colorScheme.primary,
                    size: 18,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$totalSources',
                  style: textTheme.displayLarge?.copyWith(
                    fontSize: 64,
                    fontWeight: FontWeight.w800,
                    color: colorScheme.onSurface,
                    letterSpacing: -1.0,
                    height: 1.0,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: statusActiveColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '$activeCount/$totalSources Healthy',
                          style: textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: statusActiveColor,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      '• Active node',
                      style: textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUsageCard(
    BuildContext context,
    ColorScheme colorScheme,
    TextTheme textTheme,
  ) {
    final metrics = widget.usageMetrics;
    final opsText = metrics?.formattedOpsPerMinute ?? '0.0 ops/m';
    final readsCountText = metrics != null ? _formatCount(metrics.totalReads) : '0';
    final writesCountText = metrics != null ? _formatCount(metrics.totalWrites) : '0';
    final currentWindow = widget.selectedTimeWindow;

    final readPoints = (metrics != null && metrics.readHistory.isNotEmpty)
        ? metrics.readHistory
        : const [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0];
    final writePoints = (metrics != null && metrics.writeHistory.isNotEmpty)
        ? metrics.writeHistory
        : const [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0];
    final timestamps = metrics?.timestamps ?? const [];
    final rawReads = metrics?.rawReads ?? const [];
    final rawWrites = metrics?.rawWrites ?? const [];
    final yMax = metrics?.yMax ?? 10;

    return GestureDetector(
      onSecondaryTapUp: (details) => _showUsageCardContextMenu(context, details.globalPosition),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Altr Stream Usage',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Read / Write Operations • Right-click to clear',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.bodySmall?.copyWith(
                            fontSize: 11,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Time Window Menu Button (Material 3 Expressive M3EMenu)
                      M3EMenu(
                        position: M3EMenuAnchorPosition.bottomStart,
                        colorStyle: M3EMenuColorStyle.standard,
                        closeOnSelect: true,
                        selectedValue: currentWindow,
                        onSelected: (Object? value) {
                          if (value != null && widget.onTimeWindowChanged != null) {
                            widget.onTimeWindowChanged!(value.toString());
                          }
                        },
                        anchorBuilder: (BuildContext context, VoidCallback open) {
                          return M3EButton.icon(
                            style: M3EButtonStyle.tonal,
                            icon: HugeIcon(
                              icon: HugeIcons.strokeRoundedArrowDown01,
                              size: 14,
                              color: colorScheme.primary,
                            ),
                            label: Text(currentWindow),
                            onPressed: open,
                          );
                        },
                        children: <M3EMenuNode>[
                          M3EMenuSelectable(
                            label: '30m',
                            value: '30m',
                            selected: currentWindow == '30m',
                          ),
                          M3EMenuSelectable(
                            label: '1h',
                            value: '1h',
                            selected: currentWindow == '1h',
                          ),
                          M3EMenuSelectable(
                            label: '1d',
                            value: '1d',
                            selected: currentWindow == '1d',
                          ),
                          M3EMenuSelectable(
                            label: '1w',
                            value: '1w',
                            selected: currentWindow == '1w',
                          ),
                        ],
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            HugeIcon(
                              icon: HugeIcons.strokeRoundedChartLineData01,
                              size: 14,
                              color: colorScheme.primary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              opsText,
                              style: textTheme.labelSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Flexible Line Chart with X & Y Axis Labels and Hover Indicator
              Expanded(
                child: SizedBox(
                  width: double.infinity,
                  child: MouseRegion(
                    onHover: (event) {
                      setState(() {
                        _chartHoverOffset = event.localPosition;
                      });
                    },
                    onExit: (_) {
                      setState(() {
                        _chartHoverOffset = null;
                      });
                    },
                    child: CustomPaint(
                      painter: UsageLineChartPainter(
                        readColor: colorScheme.primary,
                        writeColor: colorScheme.tertiary,
                        gridColor: colorScheme.outlineVariant.withValues(alpha: 0.3),
                        textColor: colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                        readPoints: readPoints,
                        writePoints: writePoints,
                        timestamps: timestamps,
                        rawReads: rawReads,
                        rawWrites: rawWrites,
                        yMax: yMax,
                        hoverOffset: _chartHoverOffset,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Legend with numerical counts
              Wrap(
                spacing: 16,
                runSpacing: 4,
                children: [
                  _buildLegendItem(context, 'Reads ($readsCountText)', colorScheme.primary),
                  _buildLegendItem(context, 'Writes ($writesCountText)', colorScheme.tertiary),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showUsageCardContextMenu(BuildContext context, Offset globalPosition) {
    final colorScheme = Theme.of(context).colorScheme;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;

    showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        globalPosition & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem<String>(
          value: 'clear',
          child: Row(
            children: [
              HugeIcon(
                icon: HugeIcons.strokeRoundedDelete02,
                size: 16,
                color: colorScheme.error,
              ),
              const SizedBox(width: 8),
              Text(
                'Clear Monitored Usage Data',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.error,
                ),
              ),
            ],
          ),
        ),
      ],
    ).then((selected) {
      if (selected == 'clear') {
        _showClearUsageConfirmationDialog(context);
      }
    });
  }

  void _showClearUsageConfirmationDialog(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    M3EDialog.show<void>(
      context,
      barrierDismissible: true,
      dialog: M3EDialog(
        icon: HugeIcon(
          icon: HugeIcons.strokeRoundedAlert02,
          color: colorScheme.error,
          size: 28,
        ),
        title: 'Clear Monitored Usage Data?',
        content: Text(
          'Are you sure you want to clear all monitored read/write operation logs and reset cumulative counters to 0? This action cannot be undone.',
          style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13, height: 1.5),
        ),
        actions: [
          M3EButton(
            style: M3EButtonStyle.text,
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          M3EButton(
            style: M3EButtonStyle.filled,
            onPressed: () {
              Navigator.of(context).pop();
              widget.onClearUsageData?.call();
            },
            child: const Text('Clear All Monitored Data'),
          ),
        ],
      ),
    );
  }


  String _formatCount(int count) {
    if (count >= 1000000) {
      return '${(count / 1000000).toStringAsFixed(1)}M';
    }
    if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}k';
    }
    return '$count';
  }

  Widget _buildSourcesListCard(
    BuildContext context,
    ColorScheme colorScheme,
    TextTheme textTheme,
    BentoCardConfig config,
  ) {
    final int maxCount = config.rowSpan == 1
        ? 2
        : (config.rowSpan == 2 ? 6 : 10);
    final topSources = widget.sources.take(maxCount).toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Sources List',
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Top connected sources in this node',
                      style: textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                M3EButton(
                  style: M3EButtonStyle.tonal,
                  size: M3EButtonSize.sm,
                  onPressed: widget.onViewAllSources,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Manage Sources'),
                      const SizedBox(width: 4),
                      HugeIcon(
                        icon: HugeIcons.strokeRoundedArrowRight01,
                        size: 14,
                        color: colorScheme.onSecondaryContainer,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Connected items
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    for (int i = 0; i < topSources.length; i++) ...[
                      if (i > 0) const SizedBox(height: 4),
                      _buildM3EConnectedListItem(
                        context: context,
                        source: topSources[i],
                        index: i,
                        totalCount: topSources.length,
                        colorScheme: colorScheme,
                        textTheme: textTheme,
                        onTap: () => widget.onSelectSource(topSources[i]),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRegistryCard(
    BuildContext context,
    ColorScheme colorScheme,
    TextTheme textTheme,
    BentoCardConfig config,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: HugeIcon(
                icon: HugeIcons.strokeRoundedHierarchySquare01,
                color: colorScheme.primary,
                size: 24,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Schema & Mapping Registry',
                    style: textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Manage source-agnostic logical models and map physical PostgreSQL / SQLite databases to expose unified AltrQL queries.',
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            M3EButton.icon(
              onPressed: widget.onNavigateToRegistry,
              icon: HugeIcon(
                icon: HugeIcons.strokeRoundedArrowRight01,
                size: 14,
                color: colorScheme.onPrimary,
              ),
              label: const Text('Open Registry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActivityCard(
    BuildContext context,
    ColorScheme colorScheme,
    TextTheme textTheme,
    BentoCardConfig config,
  ) {
    if (widget.activities.isEmpty) {
      return const SizedBox.shrink();
    }

    final int maxItems = config.rowSpan == 1 ? 2 : 4;
    final displayActivities = widget.activities.take(maxItems).toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Recent Node Activity',
                  style: textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: colorScheme.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Live Stream',
                        style: textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Expanded(
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: displayActivities.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final act = displayActivities[index];
                  final dotColor = act.isSuccess
                      ? colorScheme.primary
                      : colorScheme.error;
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
                              style: textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              act.description,
                              style: textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        DateFormat('hh:mm a').format(act.timestamp),
                        style: textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildM3EConnectedListItem({
    required BuildContext context,
    required SourceModel source,
    required int index,
    required int totalCount,
    required ColorScheme colorScheme,
    required TextTheme textTheme,
    required VoidCallback onTap,
  }) {
    final BorderRadius borderRadius;
    if (totalCount <= 1) {
      borderRadius = BorderRadius.circular(18);
    } else if (index == 0) {
      borderRadius = const BorderRadius.vertical(
        top: Radius.circular(18),
        bottom: Radius.circular(4),
      );
    } else if (index == totalCount - 1) {
      borderRadius = const BorderRadius.vertical(
        top: Radius.circular(4),
        bottom: Radius.circular(18),
      );
    } else {
      borderRadius = BorderRadius.circular(4);
    }

    final subtext = source.type == 'SQLITE'
        ? '${source.type} • ${source.filePath ?? "Local File"}'
        : '${source.type} • ${source.host ?? ""}:${source.port ?? ""}/${source.databaseName ?? ""}';

    return Material(
      color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.6),
      borderRadius: borderRadius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: borderRadius,
        hoverColor: colorScheme.primary.withValues(alpha: 0.06),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: HugeIcon(
                  icon: AppTheme.getSourceTypeIcon(source.type),
                  color: colorScheme.primary,
                  size: 18,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      source.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodyMedium?.copyWith(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                        letterSpacing: -0.1,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtext,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodySmall?.copyWith(
                        fontSize: 11,
                        fontWeight: FontWeight.normal,
                        color: colorScheme.onSurfaceVariant.withValues(
                          alpha: 0.8,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              StatusBadge(
                status: (_isRefreshing || (widget.isLoading && source.isUnreachable))
                    ? 'PINGING'
                    : source.status,
              ),
              const SizedBox(width: 8),
              HugeIcon(
                icon: HugeIcons.strokeRoundedArrowRight01,
                size: 18,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLegendItem(BuildContext context, String label, Color color) {
    final textTheme = Theme.of(context).textTheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: textTheme.bodySmall?.copyWith(
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class UsageLineChartPainter extends CustomPainter {
  final Color readColor;
  final Color writeColor;
  final Color gridColor;
  final Color textColor;
  final List<double> readPoints;
  final List<double> writePoints;
  final List<String> timestamps;
  final List<int> rawReads;
  final List<int> rawWrites;
  final int yMax;
  final Offset? hoverOffset;

  const UsageLineChartPainter({
    required this.readColor,
    required this.writeColor,
    required this.gridColor,
    required this.textColor,
    this.readPoints = const [0.05, 0.05, 0.05],
    this.writePoints = const [0.02, 0.02, 0.02],
    this.timestamps = const [],
    this.rawReads = const [],
    this.rawWrites = const [],
    this.yMax = 10,
    this.hoverOffset,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const leftMargin = 28.0;
    const bottomMargin = 18.0;
    final chartWidth = size.width - leftMargin;
    final chartHeight = size.height - bottomMargin;

    if (chartWidth <= 0 || chartHeight <= 0) return;

    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    // Draw horizontal grid lines & Y-axis labels
    final yTicks = [
      (yMax).toString(),
      (yMax / 2).round().toString(),
      '0',
    ];

    final yPositions = [
      4.0,
      chartHeight / 2,
      chartHeight - 4.0,
    ];

    for (int i = 0; i < yTicks.length; i++) {
      final y = yPositions[i];
      canvas.drawLine(
        Offset(leftMargin, y),
        Offset(size.width, y),
        gridPaint,
      );

      final tp = TextPainter(
        text: TextSpan(
          text: yTicks[i],
          style: TextStyle(
            color: textColor,
            fontSize: 9.5,
            fontWeight: FontWeight.w500,
          ),
        ),
        textDirection: ui.TextDirection.ltr,
      );
      tp.layout();
      tp.paint(canvas, Offset(leftMargin - tp.width - 4, y - (tp.height / 2)));
    }

    // Draw X-axis timestamps
    if (timestamps.isNotEmpty) {
      final sampleCount = 5;
      final step = (timestamps.length - 1) / (sampleCount - 1);
      for (int i = 0; i < sampleCount; i++) {
        final index = (i * step).round().clamp(0, timestamps.length - 1);
        final label = timestamps[index];
        final xRatio = timestamps.length > 1 ? index / (timestamps.length - 1) : 0.5;
        final x = leftMargin + (xRatio * chartWidth);

        final tp = TextPainter(
          text: TextSpan(
            text: label,
            style: TextStyle(
              color: textColor,
              fontSize: 9.5,
              fontWeight: FontWeight.w500,
            ),
          ),
          textDirection: ui.TextDirection.ltr,
        );
        tp.layout();

        double drawX = x - (tp.width / 2);
        if (drawX < leftMargin) drawX = leftMargin;
        if (drawX + tp.width > size.width) drawX = size.width - tp.width;

        tp.paint(canvas, Offset(drawX, chartHeight + 2));
      }
    }

    // Draw read and write smooth curves within inner chart bounds
    final innerSize = Size(chartWidth, chartHeight);
    canvas.save();
    canvas.translate(leftMargin, 0);
    _drawSmoothCurve(canvas, innerSize, readPoints, readColor, true);
    _drawSmoothCurve(canvas, innerSize, writePoints, writeColor, false);

    // Draw hover guide line & peak activity tooltip
    if (hoverOffset != null && timestamps.isNotEmpty && hoverOffset!.dx >= leftMargin) {
      final xInChart = (hoverOffset!.dx - leftMargin).clamp(0.0, chartWidth);
      final index = timestamps.length > 1
          ? ((xInChart / chartWidth) * (timestamps.length - 1)).round().clamp(0, timestamps.length - 1)
          : 0;

      final xPos = timestamps.length > 1 ? (index / (timestamps.length - 1)) * chartWidth : (chartWidth / 2);
      final paddingY = chartHeight * 0.08;
      final usableHeight = chartHeight - (paddingY * 2);

      final rVal = index < readPoints.length ? readPoints[index].clamp(0.0, 1.0) : 0.0;
      final wVal = index < writePoints.length ? writePoints[index].clamp(0.0, 1.0) : 0.0;

      final rY = chartHeight - paddingY - (rVal * usableHeight);
      final wY = chartHeight - paddingY - (wVal * usableHeight);

      final rCount = index < rawReads.length ? rawReads[index] : 0;
      final wCount = index < rawWrites.length ? rawWrites[index] : 0;
      final timestampStr = index < timestamps.length ? timestamps[index] : '';

      // Vertical guideline
      final linePaint = Paint()
        ..color = textColor.withValues(alpha: 0.45)
        ..strokeWidth = 1.2
        ..style = PaintingStyle.stroke;
      canvas.drawLine(Offset(xPos, 0), Offset(xPos, chartHeight), linePaint);

      // Highlighted dots on curves
      final dotPaintR = Paint()..color = readColor;
      final dotPaintW = Paint()..color = writeColor;
      final whiteBorderPaint = Paint()
        ..color = Colors.white
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke;

      canvas.drawCircle(Offset(xPos, rY), 4.5, dotPaintR);
      canvas.drawCircle(Offset(xPos, rY), 4.5, whiteBorderPaint);

      canvas.drawCircle(Offset(xPos, wY), 4.5, dotPaintW);
      canvas.drawCircle(Offset(xPos, wY), 4.5, whiteBorderPaint);

      // Floating peak activity tooltip card (Bigger Read & Write text, smaller timestamp)
      final tooltipSpan = TextSpan(
        children: [
          TextSpan(
            text: 'Reads: $rCount   Writes: $wCount\n',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          TextSpan(
            text: '$timestampStr (1m step)',
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w500,
              color: Colors.white.withValues(alpha: 0.7),
            ),
          ),
        ],
      );

      final tp = TextPainter(
        text: tooltipSpan,
        textDirection: ui.TextDirection.ltr,
      );
      tp.layout();

      const tooltipPadding = EdgeInsets.symmetric(horizontal: 8, vertical: 5);
      final boxWidth = tp.width + tooltipPadding.horizontal;
      final boxHeight = tp.height + tooltipPadding.vertical;

      double tooltipX = xPos - (boxWidth / 2);
      if (tooltipX < 0) tooltipX = 0;
      if (tooltipX + boxWidth > chartWidth) tooltipX = chartWidth - boxWidth;

      double tooltipY = (rY < wY ? rY : wY) - boxHeight - 8;
      if (tooltipY < 0) tooltipY = (rY > wY ? rY : wY) + 8;

      final tooltipRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(tooltipX, tooltipY, boxWidth, boxHeight),
        const Radius.circular(6),
      );

      final bgPaint = Paint()..color = const Color(0xFF1E1E2E).withValues(alpha: 0.94);
      final borderPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.25)
        ..strokeWidth = 1
        ..style = PaintingStyle.stroke;

      canvas.drawRRect(tooltipRect, bgPaint);
      canvas.drawRRect(tooltipRect, borderPaint);
      tp.paint(canvas, Offset(tooltipX + tooltipPadding.left, tooltipY + tooltipPadding.top));
    }

    canvas.restore();
  }

  void _drawSmoothCurve(
    Canvas canvas,
    Size size,
    List<double> values,
    Color color,
    bool fillGradient,
  ) {
    if (values.length < 2) return;

    final stepX = size.width / (values.length - 1);
    final path = Path();
    final fillPath = Path();

    final points = <Offset>[];
    final paddingY = size.height * 0.08;
    final usableHeight = size.height - (paddingY * 2);
    for (int i = 0; i < values.length; i++) {
      final x = i * stepX;
      final clampedVal = values[i].clamp(0.0, 1.0);
      final y = size.height - paddingY - (clampedVal * usableHeight);
      points.add(Offset(x, y));
    }

    path.moveTo(points[0].dx, points[0].dy);
    fillPath.moveTo(points[0].dx, size.height);
    fillPath.lineTo(points[0].dx, points[0].dy);

    for (int i = 0; i < points.length - 1; i++) {
      final p0 = points[i];
      final p1 = points[i + 1];
      final controlX = (p0.dx + p1.dx) / 2;

      path.cubicTo(controlX, p0.dy, controlX, p1.dy, p1.dx, p1.dy);
      fillPath.cubicTo(controlX, p0.dy, controlX, p1.dy, p1.dx, p1.dy);
    }

    fillPath.lineTo(points.last.dx, size.height);
    fillPath.close();

    if (fillGradient) {
      final gradientPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.25), color.withValues(alpha: 0.0)],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
        ..style = PaintingStyle.fill;
      canvas.drawPath(fillPath, gradientPaint);
    }

    final strokePaint = Paint()
      ..color = color
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(path, strokePaint);
  }

  @override
  bool shouldRepaint(covariant UsageLineChartPainter oldDelegate) =>
      oldDelegate.readColor != readColor ||
      oldDelegate.writeColor != writeColor ||
      oldDelegate.gridColor != gridColor ||
      oldDelegate.textColor != textColor ||
      oldDelegate.yMax != yMax ||
      oldDelegate.readPoints != readPoints ||
      oldDelegate.writePoints != writePoints ||
      oldDelegate.timestamps != timestamps ||
      oldDelegate.rawReads != rawReads ||
      oldDelegate.rawWrites != rawWrites ||
      oldDelegate.hoverOffset != hoverOffset;
}

