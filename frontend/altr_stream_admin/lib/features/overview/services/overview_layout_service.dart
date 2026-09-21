import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'local_storage_adapter.dart';

/// Represents a 2D Bento Grid item with column/row positioning and spans.
class BentoCardConfig {
  final String id;
  final int col; // 0..2 (3-column grid)
  final int row; // 0..N
  final int colSpan; // 1..3
  final int rowSpan; // 1..3
  final String title;

  const BentoCardConfig({
    required this.id,
    required this.col,
    required this.row,
    required this.colSpan,
    required this.rowSpan,
    required this.title,
  });

  int get maxRowSpan {
    switch (id) {
      case 'kpi':
        return 1;
      case 'sources':
        return 3;
      case 'usage':
        return 3;
      case 'activity':
        return 2;
      case 'registry':
        return 1;
      default:
        return 3;
    }
  }

  int get maxColSpan {
    switch (id) {
      case 'kpi':
        return 1;
      case 'sources':
        return 3;
      case 'usage':
        return 3;
      case 'activity':
        return 3;
      case 'registry':
        return 3;
      default:
        return 3;
    }
  }

  int get minRowSpan => 1;
  int get minColSpan => 1;

  bool get isResizable => maxColSpan > 1 || maxRowSpan > 1;

  BentoCardConfig copyWith({
    String? id,
    int? col,
    int? row,
    int? colSpan,
    int? rowSpan,
    String? title,
  }) {
    final effectiveId = id ?? this.id;
    final configForLimits = BentoCardConfig(
      id: effectiveId,
      col: 0,
      row: 0,
      colSpan: 1,
      rowSpan: 1,
      title: '',
    );
    final clampedColSpan = (colSpan ?? this.colSpan).clamp(
      configForLimits.minColSpan,
      configForLimits.maxColSpan,
    );
    final clampedRowSpan = (rowSpan ?? this.rowSpan).clamp(
      configForLimits.minRowSpan,
      configForLimits.maxRowSpan,
    );

    return BentoCardConfig(
      id: effectiveId,
      col: col ?? this.col,
      row: row ?? this.row,
      colSpan: clampedColSpan,
      rowSpan: clampedRowSpan,
      title: title ?? this.title,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'col': col,
    'row': row,
    'colSpan': colSpan,
    'rowSpan': rowSpan,
    'title': title,
  };

  factory BentoCardConfig.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String;
    final dummy = BentoCardConfig(
      id: id,
      col: 0,
      row: 0,
      colSpan: 1,
      rowSpan: 1,
      title: '',
    );
    return BentoCardConfig(
      id: id,
      col: (json['col'] as num?)?.toInt().clamp(0, 2) ?? 0,
      row: (json['row'] as num?)?.toInt().clamp(0, 50) ?? 0,
      colSpan: ((json['colSpan'] as num?)?.toInt() ?? 1).clamp(
        dummy.minColSpan,
        dummy.maxColSpan,
      ),
      rowSpan: ((json['rowSpan'] as num?)?.toInt() ?? 1).clamp(
        dummy.minRowSpan,
        dummy.maxRowSpan,
      ),
      title: (json['title'] as String?) ?? '',
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BentoCardConfig &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          col == other.col &&
          row == other.row &&
          colSpan == other.colSpan &&
          rowSpan == other.rowSpan;

  @override
  int get hashCode =>
      id.hashCode ^
      col.hashCode ^
      row.hashCode ^
      colSpan.hashCode ^
      rowSpan.hashCode;
}

/// Collision & Gravity engine guaranteeing no two Bento cards overlap on the grid.
class BentoCollisionResolver {
  /// Checks if two bounding boxes in 2D grid space overlap.
  static bool itemsOverlap(BentoCardConfig a, BentoCardConfig b) {
    if (a.id == b.id) return false;
    final aRight = a.col + a.colSpan;
    final aBottom = a.row + a.rowSpan;
    final bRight = b.col + b.colSpan;
    final bBottom = b.row + b.rowSpan;

    final noHorizontal = a.col >= bRight || aRight <= b.col;
    final noVertical = a.row >= bBottom || aBottom <= b.row;

    return !(noHorizontal || noVertical);
  }

  /// Compacts the grid upward by removing any entirely empty rows.
  /// If there is an empty row of elements in the grid, all elements below it dynamically shift up.
  static List<BentoCardConfig> compactRows(List<BentoCardConfig> configs) {
    if (configs.isEmpty) return configs;

    int maxRow = 0;
    for (final c in configs) {
      final bottom = c.row + c.rowSpan;
      if (bottom > maxRow) maxRow = bottom;
    }

    if (maxRow == 0) return configs;

    // Check which rows from 0 to maxRow - 1 are occupied by at least one card
    final occupiedRows = List<bool>.filled(maxRow, false);
    for (final c in configs) {
      for (int r = c.row; r < c.row + c.rowSpan; r++) {
        if (r < maxRow) {
          occupiedRows[r] = true;
        }
      }
    }

    // Calculate how many empty rows exist before each row index
    final emptyRowsBefore = List<int>.filled(maxRow + 1, 0);
    int emptyCount = 0;
    for (int r = 0; r < maxRow; r++) {
      if (!occupiedRows[r]) {
        emptyCount++;
      }
      emptyRowsBefore[r + 1] = emptyCount;
    }

    if (emptyCount == 0) return configs;

    // Shift cards upward by the number of empty rows above them
    return configs.map((c) {
      final shift = emptyRowsBefore[c.row.clamp(0, maxRow)];
      if (shift == 0) return c;
      return c.copyWith(row: c.row - shift);
    }).toList();
  }

  /// Resolves all collisions across items, pushing colliding items down the grid,
  /// and dynamically compacts empty rows upward.
  static List<BentoCardConfig> resolve(List<BentoCardConfig> configs, {String? fixedId}) {
    final list = List<BentoCardConfig>.from(configs);

    bool hasCollision = true;
    int iterations = 0;
    const maxIterations = 50;

    while (hasCollision && iterations < maxIterations) {
      hasCollision = false;
      iterations++;

      for (int i = 0; i < list.length; i++) {
        for (int j = 0; j < list.length; j++) {
          if (i == j) continue;
          final cardA = list[i];
          final cardB = list[j];

          if (itemsOverlap(cardA, cardB)) {
            hasCollision = true;
            if (cardA.id == fixedId) {
              list[j] = cardB.copyWith(row: cardA.row + cardA.rowSpan);
            } else if (cardB.id == fixedId) {
              list[i] = cardA.copyWith(row: cardB.row + cardB.rowSpan);
            } else if (cardA.row < cardB.row) {
              list[j] = cardB.copyWith(row: cardA.row + cardA.rowSpan);
            } else if (cardB.row < cardA.row) {
              list[i] = cardA.copyWith(row: cardB.row + cardB.rowSpan);
            } else {
              list[j] = cardB.copyWith(row: cardA.row + cardA.rowSpan);
            }
          }
        }
      }
    }

    return compactRows(list);
  }
}

/// Service managing persistent storage and defaults for the Bento Overview dashboard layout.
class OverviewLayoutService {
  static const String _storageKey = 'altr_stream_overview_bento_v2';

  /// The authentic Bento Grid default layout:
  /// - Left column (col:0, colSpan:1): KPI (row:0, rowSpan:1) + Usage (row:1, rowSpan:1)
  /// - Right column (col:1, colSpan:2): Sources List (row:0, rowSpan:2)
  /// - Full width (col:0, colSpan:3): Registry Banner (row:2, rowSpan:1)
  /// - Full width (col:0, colSpan:3): Activity Log (row:3, rowSpan:1)
  static const List<BentoCardConfig> defaultLayout = [
    BentoCardConfig(
      id: 'kpi',
      col: 0,
      row: 0,
      colSpan: 1,
      rowSpan: 1,
      title: 'Connected Sources',
    ),
    BentoCardConfig(
      id: 'usage',
      col: 0,
      row: 1,
      colSpan: 1,
      rowSpan: 1,
      title: 'Altr Stream Usage',
    ),
    BentoCardConfig(
      id: 'sources',
      col: 1,
      row: 0,
      colSpan: 2,
      rowSpan: 2,
      title: 'Sources List',
    ),
    BentoCardConfig(
      id: 'registry',
      col: 0,
      row: 2,
      colSpan: 3,
      rowSpan: 1,
      title: 'Schema & Mapping Registry',
    ),
    BentoCardConfig(
      id: 'activity',
      col: 0,
      row: 3,
      colSpan: 3,
      rowSpan: 1,
      title: 'Recent Node Activity',
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

  /// Loads saved layout synchronously from cache/storage to eliminate any page-load jump.
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
      debugPrint('[OverviewLayoutService] Error loading saved bento layout: $e');
    }
    _cachedLayout = List.from(defaultLayout);
    return List.from(defaultLayout);
  }

  /// Loads saved layout from local storage or returns pristine Bento defaults.
  static Future<List<BentoCardConfig>> loadLayout() async {
    return getLayoutSync();
  }

  /// Persists layout to local storage and updates in-memory cache.
  static Future<void> saveLayout(List<BentoCardConfig> configs) async {
    try {
      final resolved = _ensureAllCards(configs);
      _cachedLayout = List.from(resolved);
      final jsonStr = jsonEncode(resolved.map((c) => c.toJson()).toList());
      LocalStorageAdapter.write(_storageKey, jsonStr);
    } catch (e) {
      debugPrint('[OverviewLayoutService] Error saving bento layout: $e');
    }
  }

  /// Resets layout to pristine defaults and removes saved preferences.
  static Future<List<BentoCardConfig>> resetLayout() async {
    try {
      _cachedLayout = List.from(defaultLayout);
      LocalStorageAdapter.write(_storageKey, null);
    } catch (e) {
      debugPrint('[OverviewLayoutService] Error resetting bento layout: $e');
    }
    return List.from(defaultLayout);
  }
}
