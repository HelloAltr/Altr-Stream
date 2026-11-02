import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:material_3_expressive/material_3_expressive.dart';

/// Unified alert and confirmation dialog with constrained width and M3EButton actions.
/// Designed for confirmation popups (e.g. Revoke Key, Delete Source, Sign Out, Clear Data).
/// Note: Complex multi-step modals (Add Data Source, Manage API Keys) should NOT use this.
class AltrAlert extends StatelessWidget {
  final Widget? icon;
  final String title;
  final String? message;
  final Widget? content;
  final String cancelLabel;
  final String confirmLabel;
  final bool isDestructive;
  final VoidCallback? onConfirm;
  final VoidCallback? onCancel;
  final List<Widget>? customActions;
  final double maxWidth;

  const AltrAlert({
    super.key,
    this.icon,
    required this.title,
    this.message,
    this.content,
    this.cancelLabel = 'Cancel',
    this.confirmLabel = 'Confirm',
    this.isDestructive = false,
    this.onConfirm,
    this.onCancel,
    this.customActions,
    this.maxWidth = 420.0,
  });

  /// Static helper to display the unified alert confirmation dialog and return bool.
  static Future<bool?> show(
    BuildContext context, {
    Widget? icon,
    required String title,
    String? message,
    Widget? content,
    String cancelLabel = 'Cancel',
    String confirmLabel = 'Confirm',
    bool isDestructive = false,
    VoidCallback? onConfirm,
    VoidCallback? onCancel,
    double maxWidth = 420.0,
    bool barrierDismissible = true,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (ctx) => AltrAlert(
        icon: icon,
        title: title,
        message: message,
        content: content,
        cancelLabel: cancelLabel,
        confirmLabel: confirmLabel,
        isDestructive: isDestructive,
        onConfirm: onConfirm,
        onCancel: onCancel,
        maxWidth: maxWidth,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final Widget effectiveIcon = icon ??
        (isDestructive
            ? Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: colorScheme.errorContainer.withValues(alpha: 0.5),
                  shape: BoxShape.circle,
                ),
                child: HugeIcon(
                  icon: HugeIcons.strokeRoundedAlert02,
                  color: colorScheme.error,
                  size: 26,
                ),
              )
            : Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withValues(alpha: 0.5),
                  shape: BoxShape.circle,
                ),
                child: HugeIcon(
                  icon: HugeIcons.strokeRoundedInformationCircle,
                  color: colorScheme.primary,
                  size: 26,
                ),
              ));

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: colorScheme.surfaceContainerHigh,
      surfaceTintColor: Colors.transparent,
      elevation: 6,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxWidth,
          minWidth: 320,
        ),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  effectiveIcon,
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        if (message != null || content != null) ...[
                          const SizedBox(height: 8),
                          content ??
                              Text(
                                message!,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                  height: 1.45,
                                ),
                              ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: customActions ??
                    [
                      M3EButton(
                        style: M3EButtonStyle.text,
                        onPressed: () {
                          Navigator.of(context).pop(false);
                          onCancel?.call();
                        },
                        child: Text(cancelLabel),
                      ),
                      const SizedBox(width: 8),
                      M3EButton(
                        style: M3EButtonStyle.filled,
                        decoration: isDestructive
                            ? M3EButtonDecoration(
                                backgroundColor: WidgetStatePropertyAll(colorScheme.error),
                                foregroundColor: WidgetStatePropertyAll(colorScheme.onError),
                              )
                            : null,
                        onPressed: () {
                          Navigator.of(context).pop(true);
                          onConfirm?.call();
                        },
                        child: Text(confirmLabel),
                      ),
                    ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Alias for developers preferring [AltrAlertDialog]
typedef AltrAlertDialog = AltrAlert;
