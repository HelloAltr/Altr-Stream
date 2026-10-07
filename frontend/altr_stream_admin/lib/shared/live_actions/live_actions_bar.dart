import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'live_action_model.dart';
import 'live_actions_controller.dart';

/// Reusable Live Actions Zone component for the application app bar.
///
/// Dynamically renders contextual Live Actions (Update, Reload, Feedback)
/// adaptively based on available space and action priority.
class LiveActionsBar extends StatefulWidget {
  final LiveActionsController controller;

  /// Optional override to force compact icon-only presentation.
  final bool? compact;

  const LiveActionsBar({super.key, required this.controller, this.compact});

  @override
  State<LiveActionsBar> createState() => _LiveActionsBarState();
}

class _LiveActionsBarState extends State<LiveActionsBar> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        widget.controller.updateController?.init();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final actions = widget.controller.activeActions;
        if (actions.isEmpty) {
          return const SizedBox.shrink();
        }

        return LayoutBuilder(
          builder: (context, constraints) {
            // Determine compact mode:
            // Explicit flag, or constrained width (< 460), or narrow screens (< 900) with 3+ actions
            final screenWidth =
                MediaQuery.maybeOf(context)?.size.width ?? 1200.0;
            final isNarrow = screenWidth < 900.0;
            final isConstrained = constraints.maxWidth < 460.0;
            final isCompact =
                widget.compact ??
                (isConstrained ||
                    (isNarrow && actions.length >= 3) ||
                    (screenWidth < 600.0));

            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (int i = 0; i < actions.length; i++) ...[
                  if (i > 0) const SizedBox(width: 6),
                  _LiveActionItem(action: actions[i], compact: isCompact),
                ],
              ],
            );
          },
        );
      },
    );
  }
}

class _LiveActionItem extends StatelessWidget {
  final LiveAction action;
  final bool compact;

  const _LiveActionItem({required this.action, required this.compact});

  Widget _buildIcon(BuildContext context, Color color) {
    if (action.customLeading != null) {
      return action.customLeading!;
    }
    if (action.icon is Widget) {
      return action.icon as Widget;
    }
    if (action.icon is IconData) {
      return Icon(action.icon as IconData, size: 14, color: color);
    }
    // HugeIcon descriptor
    return HugeIcon(icon: action.icon, color: color, size: 14);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Resolve color styling based on action ID/priority or custom overrides
    Color bg;
    Color fg;
    Color border;

    if (action.backgroundColor != null && action.foregroundColor != null) {
      bg = action.backgroundColor!;
      fg = action.foregroundColor!;
      border = action.borderColor ?? Colors.transparent;
    } else {
      switch (action.id) {
        case 'reload':
          bg = colorScheme.tertiaryContainer;
          fg = colorScheme.onTertiaryContainer;
          border = colorScheme.tertiary.withValues(alpha: 0.4);
          break;

        case 'update':
          if (action.label.contains('failed')) {
            bg = colorScheme.errorContainer;
            fg = colorScheme.onErrorContainer;
            border = colorScheme.error.withValues(alpha: 0.4);
          } else if (action.label.contains('Updating') ||
              action.label.contains('Starting') ||
              action.label.contains('Rolling')) {
            bg = colorScheme.surfaceContainerHigh;
            fg = colorScheme.onSurface;
            border = colorScheme.primary.withValues(alpha: 0.4);
          } else {
            bg = colorScheme.primaryContainer;
            fg = colorScheme.onPrimaryContainer;
            border = colorScheme.primary.withValues(alpha: 0.3);
          }
          break;

        case 'feedback':
          bg = colorScheme.surfaceContainerHigh;
          fg = colorScheme.onSurfaceVariant;
          border = colorScheme.outlineVariant.withValues(alpha: 0.6);
          break;

        default:
          bg = colorScheme.surfaceContainerHigh;
          fg = colorScheme.onSurface;
          border = colorScheme.outlineVariant.withValues(alpha: 0.4);
      }
    }

    final tooltipMessage = action.tooltip ?? action.label;

    return Tooltip(
      message: tooltipMessage,
      child: Material(
        key: action.key ?? ValueKey('live_action_${action.id}'),
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: action.isEnabled ? action.onTap : null,
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 8 : 10,
              vertical: 6,
            ),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildIcon(context, fg),
                if (!compact) ...[
                  const SizedBox(width: 6),
                  Text(
                    action.label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: fg,
                    ),
                  ),
                ],
                if (action.customTrailing != null) ...[
                  const SizedBox(width: 4),
                  action.customTrailing!,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
