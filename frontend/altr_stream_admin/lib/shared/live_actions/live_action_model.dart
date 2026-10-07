import 'package:flutter/material.dart';

/// Contextual priority levels for Live Actions in the app bar.
/// Lower integer value indicates higher priority (remaining visible when constrained).
enum LiveActionPriority {
  critical(0),
  update(1),
  reload(2),
  feedback(3),
  normal(4);

  final int rank;
  const LiveActionPriority(this.rank);

  bool operator <(LiveActionPriority other) => rank < other.rank;
  bool operator <=(LiveActionPriority other) => rank <= other.rank;
  bool operator >(LiveActionPriority other) => rank > other.rank;
  bool operator >=(LiveActionPriority other) => rank >= other.rank;
}

/// Represents a single contextual live action presented in the App Bar.
class LiveAction {
  /// Unique and stable identifier (e.g. 'update', 'reload', 'feedback').
  final String id;

  /// User-facing label displayed when space permits.
  final String label;

  /// Icon descriptor or Widget (supports [HugeIcon], [IconData], or custom [Widget]).
  final dynamic icon;

  /// Priority rank governing ordering and responsive collapse behavior.
  final LiveActionPriority priority;

  /// Whether the action is currently relevant and eligible for display.
  final bool isVisible;

  /// Whether user interaction is currently permitted.
  final bool isEnabled;

  /// Callback executed upon user activation.
  final VoidCallback? onTap;

  /// Descriptive tooltip displayed on hover or in compact/icon-only presentation mode.
  final String? tooltip;

  /// Unique widget key for widget testing and accessibility identification.
  final Key? key;

  /// Optional contextual visual styling tokens.
  final Color? backgroundColor;
  final Color? foregroundColor;
  final Color? borderColor;

  /// Optional custom leading widget (such as animated spinner).
  final Widget? customLeading;

  /// Optional custom trailing widget (such as status badge).
  final Widget? customTrailing;

  const LiveAction({
    required this.id,
    required this.label,
    required this.icon,
    this.priority = LiveActionPriority.normal,
    this.isVisible = true,
    this.isEnabled = true,
    this.onTap,
    this.tooltip,
    this.key,
    this.backgroundColor,
    this.foregroundColor,
    this.borderColor,
    this.customLeading,
    this.customTrailing,
  });

  LiveAction copyWith({
    String? id,
    String? label,
    dynamic icon,
    LiveActionPriority? priority,
    bool? isVisible,
    bool? isEnabled,
    VoidCallback? onTap,
    String? tooltip,
    Key? key,
    Color? backgroundColor,
    Color? foregroundColor,
    Color? borderColor,
    Widget? customLeading,
    Widget? customTrailing,
  }) {
    return LiveAction(
      id: id ?? this.id,
      label: label ?? this.label,
      icon: icon ?? this.icon,
      priority: priority ?? this.priority,
      isVisible: isVisible ?? this.isVisible,
      isEnabled: isEnabled ?? this.isEnabled,
      onTap: onTap ?? this.onTap,
      tooltip: tooltip ?? this.tooltip,
      key: key ?? this.key,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      foregroundColor: foregroundColor ?? this.foregroundColor,
      borderColor: borderColor ?? this.borderColor,
      customLeading: customLeading ?? this.customLeading,
      customTrailing: customTrailing ?? this.customTrailing,
    );
  }
}
