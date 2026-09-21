import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import '../services/overview_layout_service.dart';
import 'dashboard_card_wrapper.dart';

typedef BentoCardWidgetBuilder = Widget Function(
  BuildContext context,
  BentoCardConfig config,
);

/// A high-performance 2D Bento Grid Engine for Flutter supporting:
/// - Collision & gravity auto-packing (no components ever overlap)
/// - Background grid slot drop targets (drop into any empty cell or occupied cell)
/// - Exact multi-column / multi-row Bento tile coordinates
/// - Animated layout repositioning
/// - Physical drag-and-drop reordering via DragTarget & Draggable
/// - Physical corner drag-resizing with grid snapping
/// - Responsive adaptation for mobile and tablet
class BentoGridEngine extends StatefulWidget {
  final List<BentoCardConfig> configs;
  final bool isEditMode;
  final BentoCardWidgetBuilder cardBuilder;
  final ValueChanged<List<BentoCardConfig>> onLayoutChanged;
  final double rowUnitHeight;

  const BentoGridEngine({
    super.key,
    required this.configs,
    required this.isEditMode,
    required this.cardBuilder,
    required this.onLayoutChanged,
    this.rowUnitHeight = 240.0,
  });

  @override
  State<BentoGridEngine> createState() => _BentoGridEngineState();
}

class _BentoGridEngineState extends State<BentoGridEngine> {
  String? _draggedCardId;
  String? _hoveredCardId;
  int? _hoveredCol;
  int? _hoveredRow;

  // Track in-progress live resizing
  String? _resizingCardId;
  double _resizeDeltaWidth = 0.0;
  double _resizeDeltaHeight = 0.0;

  BentoCardConfig? _getCardConfig(String? id) {
    if (id == null) return null;
    final idx = widget.configs.indexWhere((c) => c.id == id);
    return idx != -1 ? widget.configs[idx] : null;
  }

  void _onSlotDropped(String draggedId, int targetCol, int targetRow) {
    final list = List<BentoCardConfig>.from(widget.configs);
    final fromIdx = list.indexWhere((c) => c.id == draggedId);
    if (fromIdx == -1) return;

    final fromCard = list[fromIdx];

    // Ensure the card fits horizontally within 3 columns
    int newCol = targetCol;
    if (newCol + fromCard.colSpan > 3) {
      newCol = (3 - fromCard.colSpan).clamp(0, 2);
    }
    int newRow = targetRow.clamp(0, 50);

    // Place the dragged card into the target grid coordinates
    list[fromIdx] = fromCard.copyWith(
      col: newCol,
      row: newRow,
    );

    // Resolve any collisions by pushing down only the overlapping components
    final resolved = BentoCollisionResolver.resolve(list, fixedId: draggedId);
    widget.onLayoutChanged(resolved);
  }

  void _cycleCardSpan(BentoCardConfig config) {
    if (!config.isResizable) return;

    final list = List<BentoCardConfig>.from(widget.configs);
    final idx = list.indexWhere((c) => c.id == config.id);
    if (idx == -1) return;

    // Available spans ordered by increasing footprint within this card's constraints:
    final List<(int, int)> candidateSpans = [
      (1, 1),
      (2, 1),
      (3, 1),
      (2, 2),
      (3, 2),
      (3, 3),
    ].where((s) => s.$1 <= config.maxColSpan && s.$2 <= config.maxRowSpan).toList();

    if (candidateSpans.isEmpty) return;

    final currentSpan = (config.colSpan, config.rowSpan);
    final currentIdx = candidateSpans.indexOf(currentSpan);
    final nextIdx = (currentIdx + 1) % candidateSpans.length;
    final nextSpan = candidateSpans[nextIdx];

    final nextColSpan = nextSpan.$1;
    final nextRowSpan = nextSpan.$2;

    int newCol = config.col;
    if (newCol + nextColSpan > 3) {
      newCol = (3 - nextColSpan).clamp(0, 2);
    }

    list[idx] = config.copyWith(
      col: newCol,
      colSpan: nextColSpan,
      rowSpan: nextRowSpan,
    );

    // Automatically cascade down any items overlapped by the new span
    final resolved = BentoCollisionResolver.resolve(list, fixedId: config.id);
    widget.onLayoutChanged(resolved);
  }

  void _onResizeUpdate(
    BentoCardConfig config,
    DragUpdateDetails details,
    double colWidth,
    double rowUnitHeight,
    double spacing,
  ) {
    if (!config.isResizable) return;

    _resizingCardId = config.id;
    _resizeDeltaWidth += details.delta.dx;
    _resizeDeltaHeight += details.delta.dy;

    final double colStep = colWidth + spacing;
    final double rowStep = rowUnitHeight + spacing;

    final int colsDelta = (_resizeDeltaWidth / colStep).round();
    final int rowsDelta = (_resizeDeltaHeight / rowStep).round();

    final int newColSpan = (config.colSpan + colsDelta).clamp(
      config.minColSpan,
      config.maxColSpan,
    );
    final int newRowSpan = (config.rowSpan + rowsDelta).clamp(
      config.minRowSpan,
      config.maxRowSpan,
    );

    int newCol = config.col;
    if (newCol + newColSpan > 3) {
      newCol = (3 - newColSpan).clamp(0, 2);
    }

    if (newColSpan != config.colSpan ||
        newRowSpan != config.rowSpan ||
        newCol != config.col) {
      final list = List<BentoCardConfig>.from(widget.configs);
      final idx = list.indexWhere((c) => c.id == config.id);
      if (idx != -1) {
        list[idx] = config.copyWith(
          col: newCol,
          colSpan: newColSpan,
          rowSpan: newRowSpan,
        );

        _resizeDeltaWidth -= colsDelta * colStep;
        _resizeDeltaHeight -= rowsDelta * rowStep;

        // Resolve collisions in real-time so surrounding components immediately yield space
        final resolved = BentoCollisionResolver.resolve(list, fixedId: config.id);
        widget.onLayoutChanged(resolved);
      }
    } else {
      setState(() {});
    }
  }

  void _onResizeEnd(
    BentoCardConfig config,
    DragEndDetails details,
    double colWidth,
    double rowUnitHeight,
    double spacing,
  ) {
    setState(() {
      _resizingCardId = null;
      _resizeDeltaWidth = 0.0;
      _resizeDeltaHeight = 0.0;
    });
    OverviewLayoutService.saveLayout(widget.configs);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth;
        const double spacing = 16.0;
        final double rowUnitHeight = widget.rowUnitHeight;

        // On mobile / narrow screens (< 860px), stack cards in a clean column
        if (totalWidth < 860) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final config in widget.configs)
                Padding(
                  padding: const EdgeInsets.only(bottom: spacing),
                  child: DashboardCardWrapper(
                    config: config,
                    isEditMode: widget.isEditMode,
                    onCycleSpan: () => _cycleCardSpan(config),
                    child: widget.cardBuilder(context, config),
                  ),
                ),
            ],
          );
        }

        // Desktop Bento 3-Column Grid Layout:
        final double colWidth = (totalWidth - 2 * spacing) / 3;

        // Calculate max row index
        int maxGridRow = 0;
        for (final c in widget.configs) {
          final bottomRow = c.row + c.rowSpan;
          if (bottomRow > maxGridRow) {
            maxGridRow = bottomRow;
          }
        }
        // Always fit totalRows strictly to maxGridRow to eliminate any empty bento space below cards
        final int totalRows = maxGridRow;
        final double totalGridHeight = totalRows > 0
            ? (totalRows * rowUnitHeight + (totalRows - 1) * spacing)
            : 0;

        return SizedBox(
          width: totalWidth,
          height: totalGridHeight,
          child: Stack(
            children: [
              // Background Grid Slot Drop Targets (allows dropping into ANY empty slot in the grid)
              if (widget.isEditMode) ...[
                for (int r = 0; r < totalRows; r++)
                  for (int c = 0; c < 3; c++)
                    _buildBackgroundGridSlot(
                      col: c,
                      row: r,
                      colWidth: colWidth,
                      rowUnitHeight: rowUnitHeight,
                      spacing: spacing,
                      colorScheme: colorScheme,
                    ),
              ],

              // Positioned Bento Cards
              for (final config in widget.configs)
                _buildPositionedBentoTile(
                  context,
                  config,
                  colWidth,
                  rowUnitHeight,
                  spacing,
                  colorScheme,
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBackgroundGridSlot({
    required int col,
    required int row,
    required double colWidth,
    required double rowUnitHeight,
    required double spacing,
    required ColorScheme colorScheme,
  }) {
    final double left = col * (colWidth + spacing);
    final double top = row * (rowUnitHeight + spacing);

    final draggedCard = _getCardConfig(_draggedCardId);
    final int draggedColSpan = draggedCard?.colSpan ?? 1;
    final int draggedRowSpan = draggedCard?.rowSpan ?? 1;

    int placeCol = _hoveredCol ?? 0;
    if (placeCol + draggedColSpan > 3) {
      placeCol = (3 - draggedColSpan).clamp(0, 2);
    }
    int placeRow = _hoveredRow ?? 0;

    final bool isInDropFootprint = _hoveredCol != null &&
        _hoveredRow != null &&
        col >= placeCol &&
        col < (placeCol + draggedColSpan) &&
        row >= placeRow &&
        row < (placeRow + draggedRowSpan);

    final bool isPrimaryAnchor = isInDropFootprint && col == placeCol && row == placeRow;

    return Positioned(
      left: left,
      top: top,
      width: colWidth,
      height: rowUnitHeight,
      child: DragTarget<String>(
        hitTestBehavior: HitTestBehavior.opaque,
        onWillAcceptWithDetails: (details) {
          setState(() {
            _hoveredCol = col;
            _hoveredRow = row;
            _draggedCardId = details.data;
          });
          return true;
        },
        onLeave: (_) {
          setState(() {
            if (_hoveredCol == col && _hoveredRow == row) {
              _hoveredCol = null;
              _hoveredRow = null;
            }
          });
        },
        onAcceptWithDetails: (details) {
          setState(() {
            _hoveredCol = null;
            _hoveredRow = null;
            _hoveredCardId = null;
            _draggedCardId = null;
          });
          _onSlotDropped(details.data, col, row);
        },
        builder: (context, candidateData, rejectedData) {
          return AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: isInDropFootprint
                    ? colorScheme.primary
                    : colorScheme.outlineVariant.withValues(alpha: 0.15),
                width: isInDropFootprint ? 2.0 : 1.0,
              ),
              color: isInDropFootprint
                  ? colorScheme.primaryContainer.withValues(alpha: 0.25)
                  : Colors.transparent,
            ),
            child: isPrimaryAnchor
                ? Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          HugeIcon(
                            icon: HugeIcons.strokeRoundedMove,
                            size: 14,
                            color: colorScheme.onPrimary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Drop here',
                            style: TextStyle(
                              color: colorScheme.onPrimary,
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : null,
          );
        },
      ),
    );
  }

  Widget _buildPositionedBentoTile(
    BuildContext context,
    BentoCardConfig config,
    double colWidth,
    double rowUnitHeight,
    double spacing,
    ColorScheme colorScheme,
  ) {
    final double left = config.col * (colWidth + spacing);
    final double top = config.row * (rowUnitHeight + spacing);

    final double width = config.colSpan * colWidth + (config.colSpan - 1) * spacing;
    final double height = config.rowSpan * rowUnitHeight + (config.rowSpan - 1) * spacing;

    final isBeingHovered = _hoveredCardId == config.id && _draggedCardId != config.id;
    final isBeingDragged = _draggedCardId == config.id;
    final isBeingResized = _resizingCardId == config.id;

    return AnimatedPositioned(
      key: ValueKey(config.id),
      duration: widget.isEditMode ? const Duration(milliseconds: 200) : Duration.zero,
      curve: Curves.easeOutCubic,
      left: left,
      top: top,
      width: width,
      height: height,
      child: IgnorePointer(
        ignoring: isBeingDragged,
        child: DragTarget<String>(
          hitTestBehavior: widget.isEditMode ? HitTestBehavior.opaque : HitTestBehavior.deferToChild,
          onWillAcceptWithDetails: (details) {
            setState(() {
              _hoveredCardId = config.id;
              _draggedCardId = details.data;
            });
            return details.data != config.id;
          },
          onLeave: (_) {
            setState(() {
              if (_hoveredCardId == config.id) {
                _hoveredCardId = null;
              }
            });
          },
          onAcceptWithDetails: (details) {
            setState(() {
              _hoveredCardId = null;
              _draggedCardId = null;
            });
            _onSlotDropped(details.data, config.col, config.row);
          },
          builder: (context, candidateData, rejectedData) {
            return AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                border: isBeingHovered
                    ? Border.all(color: colorScheme.primary, width: 2.5)
                    : isBeingResized
                        ? Border.all(color: colorScheme.secondary, width: 2.0)
                        : null,
              ),
              child: DashboardCardWrapper(
                config: config,
                isEditMode: widget.isEditMode,
                isDragging: isBeingDragged || isBeingResized,
                onCycleSpan: () => _cycleCardSpan(config),
                onDragStarted: () {
                  setState(() {
                    _draggedCardId = config.id;
                  });
                },
                onDragEnd: (_) {
                  setState(() {
                    _draggedCardId = null;
                    _hoveredCardId = null;
                    _hoveredCol = null;
                    _hoveredRow = null;
                  });
                },
                onResizeUpdate: (details) => _onResizeUpdate(config, details, colWidth, rowUnitHeight, spacing),
                onResizeEnd: (details) => _onResizeEnd(config, details, colWidth, rowUnitHeight, spacing),
                child: RepaintBoundary(
                  child: widget.cardBuilder(context, config),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
