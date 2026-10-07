import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import '../../../core/api/models.dart';

class SchemaExplorer extends StatefulWidget {
  final SourceModel? selectedSource;
  final SourceSchemaModel? schema;
  final bool isLoading;
  final String? errorMessage;
  final VoidCallback onRefreshSchema;
  final ValueChanged<EntitySchemaModel> onSelectTable;
  final void Function(FieldSchemaModel field, EntitySchemaModel entity)
  onSelectColumn;

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
      final matchesNamespace = entity.namespace.toLowerCase().contains(
        _searchQuery,
      );
      final matchesColumn = entity.fields.any(
        (f) =>
            f.name.toLowerCase().contains(_searchQuery) ||
            f.dataType.toLowerCase().contains(_searchQuery),
      );
      return matchesTableName || matchesNamespace || matchesColumn;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isMongo = widget.selectedSource?.type.toUpperCase() == 'MONGODB';
    final filteredEntities = _getFilteredEntities();

    // Group entities by namespace
    final Map<String, List<EntitySchemaModel>> namespaceMap = {};
    for (final entity in filteredEntities) {
      namespaceMap.putIfAbsent(entity.namespace, () => []).add(entity);
    }
    final filteredNamespaces = namespaceMap.keys.toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Card Title (Matches Discovered Schemas card)
            Text(
              isMongo ? 'SCHEMAS & COLLECTIONS' : 'SCHEMAS & TABLES',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurfaceVariant,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 10),

            // Anchored Top Search Bar
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: isMongo
                    ? 'Search collections...'
                    : 'Search tables...',
                hintStyle: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurfaceVariant,
                ),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                prefixIcon: Padding(
                  padding: const EdgeInsets.only(left: 8, right: 6),
                  child: HugeIcon(
                    icon: HugeIcons.strokeRoundedSearch01,
                    size: 14,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                prefixIconConstraints: const BoxConstraints(
                  minWidth: 28,
                  minHeight: 28,
                ),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: HugeIcon(
                          icon: HugeIcons.strokeRoundedCancel01,
                          size: 14,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        onPressed: () => _searchController.clear(),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 28,
                          minHeight: 28,
                        ),
                      )
                    : null,
                filled: true,
                fillColor: colorScheme.surfaceContainerLow,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(
                    color: colorScheme.primary,
                    width: 1.5,
                  ),
                ),
              ),
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 10),

            // Content Area
            Expanded(
              child: _buildBody(
                context,
                colorScheme,
                isMongo,
                filteredNamespaces,
                namespaceMap,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    ColorScheme colorScheme,
    bool isMongo,
    List<String> filteredNamespaces,
    Map<String, List<EntitySchemaModel>> namespaceMap,
  ) {
    if (widget.selectedSource == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              HugeIcon(
                icon: HugeIcons.strokeRoundedDatabase,
                size: 28,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
              ),
              const SizedBox(height: 8),
              Text(
                'No Source Selected',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Select a data source to explore its schema.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  color: colorScheme.onSurfaceVariant,
                ),
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
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Loading schema snapshot...',
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurfaceVariant,
              ),
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
              HugeIcon(
                icon: HugeIcons.strokeRoundedAlertCircle,
                size: 24,
                color: colorScheme.error,
              ),
              const SizedBox(height: 8),
              Text(
                'Failed to Load Schema',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.error,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                widget.errorMessage!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: widget.onRefreshSchema,
                icon: const HugeIcon(
                  icon: HugeIcons.strokeRoundedRefresh,
                  size: 14,
                ),
                label: const Text(
                  'Retry Discovery',
                  style: TextStyle(fontSize: 11),
                ),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
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
              HugeIcon(
                icon: HugeIcons.strokeRoundedPackage,
                size: 28,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
              ),
              const SizedBox(height: 8),
              Text(
                'No Schema Discovered',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'No schema snapshot found for this source.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: widget.onRefreshSchema,
                icon: const HugeIcon(
                  icon: HugeIcons.strokeRoundedSparkles,
                  size: 14,
                ),
                label: const Text(
                  'Discover Schema',
                  style: TextStyle(fontSize: 11),
                ),
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (filteredNamespaces.isEmpty && _searchQuery.isNotEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            isMongo ? 'No collections found' : 'No tables found',
            style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
          ),
        ),
      );
    }

    return ListView(
      children: [
        for (final ns in filteredNamespaces) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                HugeIcon(
                  icon: HugeIcons.strokeRoundedFolder01,
                  size: 16,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 6),
                Text(
                  ns,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          ...() {
            final tables = namespaceMap[ns]!;
            final totalCount = tables.length;
            return tables.asMap().entries.map((entry) {
              final index = entry.key;
              final entity = entry.value;

              final BorderRadius borderRadius;
              if (totalCount <= 1) {
                borderRadius = BorderRadius.circular(16);
              } else if (index == 0) {
                borderRadius = const BorderRadius.vertical(
                  top: Radius.circular(16),
                  bottom: Radius.circular(6),
                );
              } else if (index == totalCount - 1) {
                borderRadius = const BorderRadius.vertical(
                  top: Radius.circular(6),
                  bottom: Radius.circular(16),
                );
              } else {
                borderRadius = BorderRadius.circular(6);
              }

              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Material(
                  color: Colors.transparent,
                  borderRadius: borderRadius,
                  clipBehavior: Clip.antiAlias,
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 52),
                    decoration: BoxDecoration(
                      borderRadius: borderRadius,
                      border: Border.all(
                        color: colorScheme.outline.withAlpha(50),
                        width: 1,
                      ),
                    ),
                    child: Theme(
                      data: Theme.of(
                        context,
                      ).copyWith(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        dense: true,
                        tilePadding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 2,
                        ),
                        childrenPadding: const EdgeInsets.only(bottom: 6),
                        leading: Container(
                          padding: const EdgeInsets.all(7),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHigh.withValues(
                              alpha: 0.6,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: HugeIcon(
                            icon:
                                entity.entityType.toUpperCase() == 'COLLECTION'
                                ? HugeIcons.strokeRoundedFolderLibrary
                                : (entity.entityType.toUpperCase() == 'VIEW'
                                      ? HugeIcons.strokeRoundedView
                                      : HugeIcons.strokeRoundedSheet),
                            size: 16,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        title: Text(
                          entity.name,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w500,
                            color: colorScheme.onSurface,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${entity.fields.length} ${entity.fields.length == 1 ? "field" : "fields"}',
                          style: TextStyle(
                            fontSize: 11,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const HugeIcon(
                                icon: HugeIcons.strokeRoundedCode,
                                size: 15,
                              ),
                              tooltip: isMongo
                                  ? 'Query Collection (Insert Template)'
                                  : 'Query Table (Insert Template)',
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 26,
                                minHeight: 26,
                              ),
                              color: colorScheme.primary,
                              onPressed: () => widget.onSelectTable(entity),
                            ),
                            const HugeIcon(
                              icon: HugeIcons.strokeRoundedArrowDown01,
                              size: 16,
                            ),
                          ],
                        ),
                        children: entity.fields
                            .map(
                              (field) => _buildFieldRow(
                                context,
                                colorScheme,
                                field,
                                entity,
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  ),
                ),
              );
            });
          }(),
          const SizedBox(height: 8),
        ],
      ],
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
                child: HugeIcon(
                  icon: HugeIcons.strokeRoundedKey01,
                  size: 12,
                  color: Colors.amber.shade700,
                ),
              )
            else
              const SizedBox(width: 18),
            Expanded(
              child: Text(
                field.name,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: field.isPrimaryKey
                      ? FontWeight.bold
                      : FontWeight.normal,
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
                field.nativeDataType.isNotEmpty
                    ? field.nativeDataType
                    : field.dataType,
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
