import 'package:flutter/material.dart';
import '../../../core/api/models.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/page_header.dart';
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
    // Filter sources
    final filteredSources = widget.sources.where((s) {
      final matchesQuery = _searchQuery.isEmpty ||
          s.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          s.host.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          s.databaseName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          s.type.toLowerCase().contains(_searchQuery.toLowerCase());

      final matchesStatus = _filterStatus == 'ALL' ||
          (_filterStatus == 'ACTIVE' && s.isActive) ||
          (_filterStatus == 'UNREACHABLE' && s.isUnreachable);

      return matchesQuery && matchesStatus;
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Page Header
        PageHeader(
          title: 'Data Sources',
          description: 'Manage databases connected to this Altr Stream node.',
          nodeStatus: widget.nodeStatus,
          onNodeStatusTap: widget.onNodeStatusTap,
          secondaryAction: OutlinedButton.icon(
            onPressed: widget.onRefresh,
            icon: const Icon(Icons.refresh, size: 14),
            label: const Text('Refresh'),
          ),
          primaryAction: ElevatedButton.icon(
            onPressed: widget.onAddSource,
            icon: const Icon(Icons.add, size: 14),
            label: const Text('Add Data Source'),
          ),
        ),

        // Search & Filter Toolbar
        Row(
          children: [
            Expanded(
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'Search sources by name, host, or database...',
                  prefixIcon: const Icon(Icons.search, size: 18, color: AppTheme.textMuted),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 16),
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
                color: AppTheme.bgInput,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.borderColor),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _filterStatus,
                  dropdownColor: AppTheme.bgSecondary,
                  style: const TextStyle(fontSize: 13, color: AppTheme.textPrimary),
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
          const Center(
            child: Padding(
              padding: EdgeInsets.all(60),
              child: CircularProgressIndicator(color: AppTheme.accentCyan),
            ),
          )
        else if (widget.sources.isEmpty)
          _buildEmptyState()
        else if (filteredSources.isEmpty)
          _buildNoSearchResults()
        else
          _buildSourcesList(filteredSources),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.borderColor),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.accentCyanSubtle,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.storage, color: AppTheme.accentCyan, size: 36),
          ),
          const SizedBox(height: 16),
          const Text(
            'No data sources registered',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Connect your physical database to begin schema discovery and data federation.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: widget.onAddSource,
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Add Data Source'),
          ),
        ],
      ),
    );
  }

  Widget _buildNoSearchResults() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.borderColor),
      ),
      child: Column(
        children: [
          const Icon(Icons.search_off, size: 32, color: AppTheme.textMuted),
          const SizedBox(height: 12),
          const Text(
            'No matching data sources',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
          ),
          const SizedBox(height: 4),
          const Text(
            'Try adjusting your search terms or filter criteria.',
            style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
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
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final source = sources[index];
        return _buildSourceCard(source);
      },
    );
  }

  Widget _buildSourceCard(SourceModel source) {
    return Card(
      color: AppTheme.bgCard,
      child: InkWell(
        onTap: () => widget.onSelectSource(source),
        borderRadius: BorderRadius.circular(10),
        hoverColor: AppTheme.bgCardHover,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              // Icon
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.bgPrimary,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.borderColor),
                ),
                child: const Icon(Icons.storage_rounded, color: AppTheme.accentCyan, size: 22),
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
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textPrimary,
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
                      '${source.host}:${source.port} • ${source.databaseName}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
                        color: AppTheme.textSecondary,
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
                        color: source.isActive ? AppTheme.textPrimary : AppTheme.error,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Introspected local store',
                      style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                    ),
                  ],
                ),
              ),

              // Status Pill & Chevron (Right)
              StatusBadge(status: source.status),
              const SizedBox(width: 16),
              const Icon(Icons.chevron_right, color: AppTheme.textMuted, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
