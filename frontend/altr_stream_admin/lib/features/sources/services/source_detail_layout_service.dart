import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../overview/services/local_storage_adapter.dart';
import '../../overview/services/overview_layout_service.dart';

/// Layout service for the Data Source Info / Detail page Bento Grid layout.
class SourceDetailLayoutService {
  static const String _storageKey = 'altr_stream_source_detail_bento_v3';

  /// Default 2D Bento layout for the Data Source Info page:
  /// - Row 0: Source & Connection Details (col:0, colSpan:2, rowSpan:1) + Quick Actions (col:2, colSpan:1, rowSpan:1)
  /// - Row 1: Health & Diagnostics (col:0, colSpan:1, rowSpan:1) + Capabilities & Security (col:1, colSpan:1, rowSpan:1) + Schema Summary (col:2, colSpan:1, rowSpan:1)
  /// - Row 2: DB Specific Usage Monitoring (col:0, colSpan:3, rowSpan:2)
  static const List<BentoCardConfig> defaultLayout = [
    BentoCardConfig(
      id: 'source_summary',
      col: 0,
      row: 0,
      colSpan: 2,
      rowSpan: 1,
      title: 'Source & Connection Details',
    ),
    BentoCardConfig(
      id: 'quick_actions',
      col: 2,
      row: 0,
      colSpan: 1,
      rowSpan: 1,
      title: 'Quick Actions',
    ),
    BentoCardConfig(
      id: 'health_diagnostics',
      col: 0,
      row: 1,
      colSpan: 1,
      rowSpan: 1,
      title: 'Health & Diagnostics',
    ),
    BentoCardConfig(
      id: 'source_capabilities',
      col: 1,
      row: 1,
      colSpan: 1,
      rowSpan: 1,
      title: 'Capabilities & Security',
    ),
    BentoCardConfig(
      id: 'schema_summary',
      col: 2,
      row: 1,
      colSpan: 1,
      rowSpan: 1,
      title: 'Discovered Schema Summary',
    ),
    BentoCardConfig(
      id: 'source_usage',
      col: 0,
      row: 2,
      colSpan: 3,
      rowSpan: 2,
      title: 'Data Source Usage & Operations',
    ),
  ];

  static List<BentoCardConfig>? _cachedLayout;

  static List<BentoCardConfig> _ensureAllCards(List<BentoCardConfig> configs) {
    final list = List<BentoCardConfig>.from(configs);
    final existingIds = list.map((c) => c.id).toSet();
    for (final defCard in defaultLayout) {
      if (!existingIds.contains(defCard.id)) {
        list.add(defCard);
      }
    }
    return BentoCollisionResolver.resolve(list);
  }

  static List<BentoCardConfig> getLayoutSync() {
    if (_cachedLayout != null) {
      return List.from(_cachedLayout!);
    }
    try {
      final jsonStr = LocalStorageAdapter.read(_storageKey);
      if (jsonStr != null && jsonStr.isNotEmpty) {
        final List<dynamic> rawList = jsonDecode(jsonStr);
        final loaded = rawList
            .map((item) => BentoCardConfig.fromJson(item as Map<String, dynamic>))
            .toList();

        _cachedLayout = _ensureAllCards(loaded);
        return List.from(_cachedLayout!);
      }
    } catch (e) {
      debugPrint('[SourceDetailLayoutService] Error loading saved layout: $e');
    }
    _cachedLayout = List.from(defaultLayout);
    return List.from(defaultLayout);
  }

  static Future<void> saveLayout(List<BentoCardConfig> configs) async {
    try {
      final resolved = _ensureAllCards(configs);
      _cachedLayout = List.from(resolved);
      final jsonStr = jsonEncode(resolved.map((c) => c.toJson()).toList());
      LocalStorageAdapter.write(_storageKey, jsonStr);
    } catch (e) {
      debugPrint('[SourceDetailLayoutService] Error saving layout: $e');
    }
  }

  static Future<List<BentoCardConfig>> resetLayout() async {
    try {
      _cachedLayout = List.from(defaultLayout);
      LocalStorageAdapter.write(_storageKey, null);
    } catch (e) {
      debugPrint('[SourceDetailLayoutService] Error resetting layout: $e');
    }
    return List.from(defaultLayout);
  }
}
