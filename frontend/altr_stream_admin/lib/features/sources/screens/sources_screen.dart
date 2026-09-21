import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import '../../../core/api/models.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/status_badge.dart';

class SourcesScreen extends StatefulWidget {
  final List<SourceModel> sources;
  final bool isLoading;
  final VoidCallback onRefresh;
  final VoidCallback onAddSource;
  final Function(SourceModel source) onSelectSource;
  final VoidCallback onNodeStatusTap;
  final String nodeStatus;

  const SourcesScreen({
    super.key,
    required this.sources,
    required this.isLoading,
    required this.onRefresh,
    required this.onAddSource,
    required this.onSelectSource,
    required this.onNodeStatusTap,
    this.nodeStatus = 'ACTIVE',
  });

  @override
  State<SourcesScreen> createState() => _SourcesScreenState();
}

class _SourcesScreenState extends State<SourcesScreen> {
  String _searchQuery = '';
  String _filterStatus = 'ALL';

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    // Filter sources
    final filteredSources = widget.sources.where((s) {
      final matchesQuery = _searchQuery.isEmpty ||
          s.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          (s.host?.toLowerCase().contains(_searchQuery.toLowerCase()) ?? false) ||
          (s.databaseName?.toLowerCase().contains(_searchQuery.toLowerCase()) ?? false) ||
          (s.filePath?.toLowerCase().contains(_searchQuery.toLowerCase()) ?? false) ||
          s.type.toLowerCase().contains(_searchQuery.toLowerCase());

      final matchesStatus = _filterStatus == 'ALL' ||
          (_filterStatus == 'ACTIVE' && s.isActive) ||
          (_filterStatus == 'UNREACHABLE' && s.isUnreachable);

      return matchesQuery && matchesStatus;
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Search & Filter Toolbar
        Row(
          children: [
            Expanded(
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'Search sources by name, host, or database...',
                  prefixIcon: HugeIcon(icon: HugeIcons.strokeRoundedSearch01, size: 18, color: colorScheme.onSurfaceVariant),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: HugeIcon(icon: HugeIcons.strokeRoundedCancel01, size: 16, color: colorScheme.onSurfaceVariant),
                          onPressed: () => setState(() => _searchQuery = ''),
                        )
                      : null,
                ),
                onChanged: (val) => setState(() => _searchQuery = val),
              ),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _filterStatus,
                  dropdownColor: colorScheme.surfaceContainerHigh,
                  style: TextStyle(fontSize: 13, color: colorScheme.onSurface),
                  items: const [
                    DropdownMenuItem(value: 'ALL', child: Text('All Statuses')),
                    DropdownMenuItem(value: 'ACTIVE', child: Text('Active Only')),
                    DropdownMenuItem(value: 'UNREACHABLE', child: Text('Unreachable Only')),
                  ],
                  onChanged: (val) {
                    if (val != null) setState(() => _filterStatus = val);
                  },
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // Sources List / States
        if (widget.isLoading)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(60),
              child: CircularProgressIndicator(color: colorScheme.primary),
            ),
          )
        else if (widget.sources.isEmpty)
          _buildEmptyState(context)
        else if (filteredSources.isEmpty)
          _buildNoSearchResults(context)
        else
          _buildSourcesList(filteredSources),
      ],
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
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
            child: HugeIcon(icon: HugeIcons.strokeRoundedDatabase, color: colorScheme.primary, size: 36),
          ),
          const SizedBox(height: 16),
          Text(
            'No data sources registered',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Connect your physical database to begin schema discovery and data federation.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: widget.onAddSource,
            icon: HugeIcon(icon: HugeIcons.strokeRoundedPlusSign, size: 16, color: colorScheme.onPrimary),
            label: const Text('Add Data Source'),
          ),
        ],
      ),
    );
  }

  Widget _buildNoSearchResults(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        children: [
          HugeIcon(icon: HugeIcons.strokeRoundedSearchRemove, size: 32, color: colorScheme.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(
            'No matching data sources',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
          ),
          const SizedBox(height: 4),
          Text(
            'Try adjusting your search terms or filter criteria.',
            style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: () => setState(() {
              _searchQuery = '';
              _filterStatus = 'ALL';
            }),
            child: const Text('Reset Filters'),
          ),
        ],
      ),
    );
  }

  Widget _buildSourcesList(List<SourceModel> sources) {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: sources.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final source = sources[index];
        return _buildSourceCard(context, source);
      },
    );
  }

  Widget _buildSourceCard(BuildContext context, SourceModel source) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      color: colorScheme.surfaceContainerHighest,
      child: InkWell(
        onTap: () => widget.onSelectSource(source),
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              // Icon
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                ),
                child: HugeIcon(
                  icon: AppTheme.getSourceTypeIcon(source.type),
                  color: colorScheme.primary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 16),

              // Main Info (Left)
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            source.name,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onSurface,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        StatusBadge(status: source.type, isTypeBadge: true),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      source.type == 'SQLITE'
                          ? (source.filePath ?? 'Local File')
                          : '${source.host ?? "localhost"}:${source.port ?? 5432} • ${source.databaseName ?? ""}',
                      style: TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),

              // Status Summary (Middle)
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      source.isActive ? 'Connection Healthy' : 'Connection Unavailable',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: source.isActive ? colorScheme.onSurface : colorScheme.error,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Introspected local store',
                      style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),

              // Status Pill & Chevron (Right)
              StatusBadge(status: source.status),
              const SizedBox(width: 16),
              HugeIcon(icon: HugeIcons.strokeRoundedArrowRight01, color: colorScheme.onSurfaceVariant, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
