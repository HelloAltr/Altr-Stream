import 'package:flutter/material.dart';
import '../../../core/api/models.dart';

class SchemaExplorer extends StatefulWidget {
  final SourceModel? selectedSource;
  final SourceSchemaModel? schema;
  final bool isLoading;
  final String? errorMessage;
  final VoidCallback onRefreshSchema;
  final ValueChanged<EntitySchemaModel> onSelectTable;
  final void Function(FieldSchemaModel field, EntitySchemaModel entity) onSelectColumn;

  const SchemaExplorer({
    super.key,
    required this.selectedSource,
    required this.schema,
    required this.isLoading,
    this.errorMessage,
    required this.onRefreshSchema,
    required this.onSelectTable,
    required this.onSelectColumn,
  });

  @override
  State<SchemaExplorer> createState() => _SchemaExplorerState();
}

class _SchemaExplorerState extends State<SchemaExplorer> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<EntitySchemaModel> _getFilteredEntities() {
    if (widget.schema == null) return [];
    if (_searchQuery.isEmpty) return widget.schema!.entities;

    return widget.schema!.entities.where((entity) {
      final matchesTableName = entity.name.toLowerCase().contains(_searchQuery);
      final matchesColumn = entity.fields.any(
        (f) => f.name.toLowerCase().contains(_searchQuery) || f.dataType.toLowerCase().contains(_searchQuery),
      );
      return matchesTableName || matchesColumn;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final filteredEntities = _getFilteredEntities();

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainer,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
              border: Border(
                bottom: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.account_tree_outlined, size: 16, color: colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Schema Explorer',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      if (widget.schema != null)
                        Text(
                          '${widget.schema!.entityCount} tables • ${widget.schema!.totalFieldCount} columns',
                          style: TextStyle(
                            fontSize: 10,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                if (widget.selectedSource != null)
                  IconButton(
                    icon: widget.isLoading
                        ? SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: colorScheme.primary,
                            ),
                          )
                        : const Icon(Icons.refresh, size: 16),
                    tooltip: 'Refresh / Discover Schema',
                    onPressed: widget.isLoading ? null : widget.onRefreshSchema,
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          ),

          // 2. Search Box
          if (widget.schema != null && widget.schema!.entities.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(10),
              child: TextField(
                controller: _searchController,
                style: const TextStyle(fontSize: 12),
                decoration: InputDecoration(
                  hintText: 'Filter tables & columns...',
                  hintStyle: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7)),
                  prefixIcon: Icon(Icons.search, size: 16, color: colorScheme.onSurfaceVariant),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 14),
                          onPressed: () => _searchController.clear(),
                          visualDensity: VisualDensity.compact,
                        )
                      : null,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  filled: true,
                  fillColor: colorScheme.surfaceContainer,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                  ),
                ),
              ),
            ),

          // 3. Tree Content / State
          Expanded(
            child: _buildBody(context, colorScheme, filteredEntities),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context, ColorScheme colorScheme, List<EntitySchemaModel> entities) {
    if (widget.selectedSource == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.dns_outlined, size: 28, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
              const SizedBox(height: 8),
              Text(
                'No Source Selected',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: colorScheme.onSurface),
              ),
              const SizedBox(height: 4),
              Text(
                'Select a data source to explore its schema.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );
    }

    if (widget.isLoading && widget.schema == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2, color: colorScheme.primary),
            ),
            const SizedBox(height: 12),
            Text(
              'Loading schema snapshot...',
              style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    if (widget.errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 24, color: colorScheme.error),
              const SizedBox(height: 8),
              Text(
                'Failed to Load Schema',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: colorScheme.error),
              ),
              const SizedBox(height: 4),
              Text(
                widget.errorMessage!,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: widget.onRefreshSchema,
                icon: const Icon(Icons.refresh, size: 14),
                label: const Text('Retry Discovery', style: TextStyle(fontSize: 11)),
                style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
              ),
            ],
          ),
        ),
      );
    }

    if (widget.schema == null || widget.schema!.entities.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.inventory_2_outlined, size: 28, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
              const SizedBox(height: 8),
              Text(
                'No Schema Discovered',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: colorScheme.onSurface),
              ),
              const SizedBox(height: 4),
              Text(
                'No schema snapshot found for this source.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: widget.onRefreshSchema,
                icon: const Icon(Icons.auto_awesome, size: 14),
                label: const Text('Discover Schema', style: TextStyle(fontSize: 11)),
                style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
              ),
            ],
          ),
        ),
      );
    }

    if (entities.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'No matching tables or columns found.',
            style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      itemCount: entities.length,
      itemBuilder: (context, index) {
        final entity = entities[index];
        return _buildEntityTile(context, colorScheme, entity);
      },
    );
  }

  Widget _buildEntityTile(BuildContext context, ColorScheme colorScheme, EntitySchemaModel entity) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Material(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            dense: true,
            tilePadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
            childrenPadding: const EdgeInsets.only(bottom: 6),
          leading: Icon(
            entity.entityType.toUpperCase() == 'VIEW' ? Icons.visibility_outlined : Icons.table_chart_outlined,
            size: 16,
            color: colorScheme.primary,
          ),
          title: Text(
            entity.name,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
            ),
          ),
          subtitle: Text(
            '${entity.fields.length} columns',
            style: TextStyle(
              fontSize: 10,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.code_rounded, size: 15),
                tooltip: 'Query Table (Insert Template)',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                color: colorScheme.primary,
                onPressed: () => widget.onSelectTable(entity),
              ),
              const Icon(Icons.expand_more, size: 16),
            ],
          ),
          children: entity.fields.map((field) => _buildFieldRow(context, colorScheme, field, entity)).toList(),
        ),
      ),
    ),
  );
}

  Widget _buildFieldRow(
    BuildContext context,
    ColorScheme colorScheme,
    FieldSchemaModel field,
    EntitySchemaModel entity,
  ) {
    return InkWell(
      onTap: () {
        widget.onSelectColumn(field, entity);
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Inserted "${field.name}" into editor'),
            duration: const Duration(milliseconds: 1200),
            behavior: SnackBarBehavior.floating,
          ),
        );
      },
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          children: [
            if (field.isPrimaryKey)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Icon(Icons.vpn_key_rounded, size: 12, color: Colors.amber.shade700),
              )
            else
              const SizedBox(width: 18),
            Expanded(
              child: Text(
                field.name,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: field.isPrimaryKey ? FontWeight.bold : FontWeight.normal,
                  fontFamily: 'monospace',
                  color: colorScheme.onSurface,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                field.nativeDataType.isNotEmpty ? field.nativeDataType : field.dataType,
                style: TextStyle(
                  fontSize: 9,
                  fontFamily: 'monospace',
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            if (!field.nullable) ...[
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                decoration: BoxDecoration(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  'NOT NULL',
                  style: TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
