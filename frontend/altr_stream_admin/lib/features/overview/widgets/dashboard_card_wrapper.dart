import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import '../services/overview_layout_service.dart';

/// A polished Bento card wrapper providing:
/// - Top-Right '=' physical drag handle (initiating a Flutter Draggable)
/// - Bottom-Right interactive resize grip handle (capturing onPan gestures)
/// - Edit Mode border glow & dimensions badge
class DashboardCardWrapper extends StatelessWidget {
  final BentoCardConfig config;
  final Widget child;
  final bool isEditMode;
  final bool isDragging;
  final VoidCallback? onCycleSpan;
  final VoidCallback? onDragStarted;
  final void Function(DraggableDetails details)? onDragEnd;
  final void Function(DragUpdateDetails details)? onResizeUpdate;
  final void Function(DragEndDetails details)? onResizeEnd;

  const DashboardCardWrapper({
    super.key,
    required this.config,
    required this.child,
    required this.isEditMode,
    this.isDragging = false,
    this.onCycleSpan,
    this.onDragStarted,
    this.onDragEnd,
    this.onResizeUpdate,
    this.onResizeEnd,
  });

  String _getDimensionsLabel() {
    return '${config.colSpan}x${config.rowSpan}';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (!isEditMode) {
      return child;
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: isDragging
              ? colorScheme.primary
              : colorScheme.primary.withValues(alpha: 0.6),
          width: isDragging ? 2.5 : 1.5,
        ),
        boxShadow: isDragging
            ? [
                BoxShadow(
                  color: colorScheme.primary.withValues(alpha: 0.2),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Wrapped Card Content
          child,

          // Edit Mode Top Bar: Dimensions Badge & '=' Physical Drag Handle
          Positioned(
            top: 10,
            left: 14,
            right: 14,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Dimensions Badge (clickable to cycle dimensions)
                InkWell(
                  onTap: onCycleSpan,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: colorScheme.secondary.withValues(alpha: 0.4),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        HugeIcon(
                          icon: HugeIcons.strokeRoundedDashboardSquare01,
                          size: 13,
                          color: colorScheme.onSecondaryContainer,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _getDimensionsLabel(),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSecondaryContainer,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Top-Right '=' Drag Handle
                Draggable<String>(
                  data: config.id,
                  onDragStarted: onDragStarted,
                  onDragEnd: onDragEnd,
                  feedback: Material(
                    color: Colors.transparent,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: colorScheme.secondary,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.3),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          HugeIcon(
                            icon: HugeIcons.strokeRoundedEqualSign,
                            color: colorScheme.onSecondary,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            config.title,
                            style: TextStyle(
                              color: colorScheme.onSecondary,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  childWhenDragging: Opacity(
                    opacity: 0.3,
                    child: _buildDragHandleWidget(context),
                  ),
                  child: _buildDragHandleWidget(context),
                ),
              ],
            ),
          ),

          // Bottom-Right Corner Resize Grip Handle
          if (config.isResizable)
            Positioned(
              bottom: 8,
              right: 8,
              child: Tooltip(
                message: 'Drag corner to resize (${_getDimensionsLabel()})',
                child: GestureDetector(
                  onTap: onCycleSpan,
                  onPanUpdate: onResizeUpdate,
                  onPanEnd: onResizeEnd,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.resizeDownRight,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: colorScheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: colorScheme.secondary.withValues(alpha: 0.6),
                          width: 1.2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: HugeIcon(
                        icon: HugeIcons.strokeRoundedDiagonalScrollPoint02,
                        size: 16,
                        color: colorScheme.onSecondaryContainer,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDragHandleWidget(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: 'Drag = to reorder',
      child: MouseRegion(
        cursor: SystemMouseCursors.grab,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: colorScheme.secondary,
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: colorScheme.secondary.withValues(alpha: 0.3),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              HugeIcon(
                icon: HugeIcons.strokeRoundedEqualSign,
                color: colorScheme.onSecondary,
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
