import 'package:flutter/material.dart';

class ApiSearchFilterBar extends StatelessWidget {
  final String searchQuery;
  final ValueChanged<String> onSearchChanged;
  final String? selectedMethod;
  final ValueChanged<String?> onMethodChanged;
  final String? selectedTag;
  final ValueChanged<String?> onTagChanged;
  final List<String> availableMethods;
  final List<String> availableTags;
  final int totalCount;
  final int filteredCount;
  final VoidCallback onClearAll;

  const ApiSearchFilterBar({
    super.key,
    required this.searchQuery,
    required this.onSearchChanged,
    required this.selectedMethod,
    required this.onMethodChanged,
    required this.selectedTag,
    required this.onTagChanged,
    required this.availableMethods,
    required this.availableTags,
    required this.totalCount,
    required this.filteredCount,
    required this.onClearAll,
  });

  bool get _hasActiveFilters =>
      searchQuery.trim().isNotEmpty || selectedMethod != null || selectedTag != null;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: Search Bar
          TextField(
            key: const Key('api_search_input'),
            decoration: InputDecoration(
              hintText: 'Search APIs (path, method, summary, tags, parameters)...',
              hintStyle: TextStyle(color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7), fontSize: 13),
              prefixIcon: Icon(Icons.search, size: 20, color: colorScheme.primary),
              suffixIcon: searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      tooltip: 'Clear search',
                      onPressed: () => onSearchChanged(''),
                    )
                  : null,
              filled: true,
              fillColor: colorScheme.surface,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
              ),
            ),
            controller: TextEditingController.fromValue(
              TextEditingValue(
                text: searchQuery,
                selection: TextSelection.collapsed(offset: searchQuery.length),
              ),
            ),
            onChanged: onSearchChanged,
          ),
          const SizedBox(height: 12),

          // Row 2: Method Filter, Tag Filter, Results Count, Reset
          Wrap(
            spacing: 12,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              // Method Dropdown
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String?>(
                    key: const Key('api_method_filter_dropdown'),
                    value: selectedMethod,
                    isDense: true,
                    icon: const Icon(Icons.arrow_drop_down, size: 18),
                    hint: Text(
                      'All Methods',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: colorScheme.onSurface),
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('All Methods', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      ),
                      ...availableMethods.map((m) {
                        return DropdownMenuItem<String?>(
                          value: m,
                          child: Text(
                            m,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: _getMethodColor(m, context),
                            ),
                          ),
                        );
                      }),
                    ],
                    onChanged: onMethodChanged,
                  ),
                ),
              ),

              // Tag Dropdown
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String?>(
                    key: const Key('api_tag_filter_dropdown'),
                    value: selectedTag,
                    isDense: true,
                    icon: const Icon(Icons.arrow_drop_down, size: 18),
                    hint: Text(
                      'All Tags',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: colorScheme.onSurface),
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('All Tags', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      ),
                      ...availableTags.map((t) {
                        return DropdownMenuItem<String?>(
                          value: t,
                          child: Text(
                            t,
                            style: TextStyle(fontSize: 12, color: colorScheme.onSurface),
                          ),
                        );
                      }),
                    ],
                    onChanged: onTagChanged,
                  ),
                ),
              ),

              // Endpoints Count Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  filteredCount == totalCount
                      ? '$totalCount endpoints'
                      : '$filteredCount of $totalCount endpoints',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
              ),

              // Clear All Filters action
              if (_hasActiveFilters)
                TextButton.icon(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    visualDensity: VisualDensity.compact,
                  ),
                  icon: const Icon(Icons.filter_alt_off, size: 14),
                  label: const Text('Reset Filters', style: TextStyle(fontSize: 12)),
                  onPressed: onClearAll,
                ),
            ],
          ),
        ],
      ),
    );
  }

  static Color _getMethodColor(String method, BuildContext context) {
    switch (method.toUpperCase()) {
      case 'GET':
        return const Color(0xFF38A169);
      case 'POST':
        return const Color(0xFF3182CE);
      case 'PUT':
        return const Color(0xFFDD6B20);
      case 'DELETE':
        return const Color(0xFFE53E3E);
      case 'PATCH':
        return const Color(0xFF805AD5);
      case 'HEAD':
        return const Color(0xFF319795);
      default:
        return Theme.of(context).colorScheme.primary;
    }
  }
}
