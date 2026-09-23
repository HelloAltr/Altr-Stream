import 'package:flutter/material.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import '../../core/theme/app_theme.dart';

class StatusBadge extends StatelessWidget {
  final String status;
  final bool isTypeBadge;
  final bool isPkBadge;
  final bool isCompact;

  const StatusBadge({
    super.key,
    required this.status,
    this.isTypeBadge = false,
    this.isPkBadge = false,
    this.isCompact = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    if (isPkBadge) {
      final pkColor = isDark ? AppTheme.warningDark : AppTheme.warningLight;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: pkColor.withValues(alpha: isDark ? 0.2 : 0.12),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: pkColor.withValues(alpha: 0.4)),
        ),
        child: Text(
          status.startsWith('PK:') ? status : 'PK',
          style: TextStyle(
            color: pkColor,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            fontFamily: 'monospace',
          ),
        ),
      );
    }

    if (isTypeBadge) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: colorScheme.secondaryContainer.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: colorScheme.secondary.withValues(alpha: 0.3)),
        ),
        child: Text(
          status.toUpperCase(),
          style: TextStyle(
            color: colorScheme.onSecondaryContainer,
            fontSize: 11,
            fontFamily: 'monospace',
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
          ),
        ),
      );
    }

    Color dotColor;
    Color bgColor;
    Color textColor;
    String label;
    bool isPinging = false;

    switch (status.toUpperCase()) {
      case 'PINGING':
      case 'CONNECTING':
      case 'REFRESHING':
        dotColor = isDark ? Colors.orangeAccent : Colors.orange.shade800;
        bgColor = isDark ? Colors.orange.withValues(alpha: 0.2) : Colors.orange.shade50;
        textColor = dotColor;
        label = 'Pinging';
        isPinging = true;
        break;
      case 'ACTIVE':
      case 'HEALTHY':
        dotColor = isDark ? AppTheme.successDark : AppTheme.successLight;
        bgColor = AppTheme.successBg(context);
        textColor = dotColor;
        label = 'Active';
        break;
      case 'VALIDATED':
        dotColor = isDark ? Colors.tealAccent : Colors.teal.shade700;
        bgColor = isDark ? Colors.teal.withValues(alpha: 0.2) : Colors.teal.shade50;
        textColor = dotColor;
        label = 'Validated';
        break;
      case 'DRAFT':
        dotColor = isDark ? Colors.amberAccent : Colors.amber.shade800;
        bgColor = isDark ? Colors.amber.withValues(alpha: 0.15) : Colors.amber.shade50;
        textColor = dotColor;
        label = 'Draft';
        break;
      case 'UNREACHABLE':
        dotColor = isDark ? AppTheme.errorDark : AppTheme.errorLight;
        bgColor = AppTheme.errorBg(context);
        textColor = dotColor;
        label = 'Unreachable';
        break;
      case 'DEGRADED':
      case 'WARNING':
        dotColor = isDark ? AppTheme.warningDark : AppTheme.warningLight;
        bgColor = AppTheme.warningBg(context);
        textColor = dotColor;
        label = 'Degraded';
        break;
      case 'ERROR':
        dotColor = isDark ? AppTheme.errorDark : AppTheme.errorLight;
        bgColor = AppTheme.errorBg(context);
        textColor = dotColor;
        label = 'Error';
        break;
      default:
        dotColor = colorScheme.onSurfaceVariant;
        bgColor = colorScheme.surfaceContainerHighest;
        textColor = colorScheme.onSurfaceVariant;
        label = status;
    }

    final Widget dotWidget = isPinging
        ? SizedBox(
            width: 12,
            height: 12,
            child: M3EProgressIndicator.circular(
              value: null,
              strokeWidth: 2.5,
              trackStrokeWidth: 2.5,
              color: dotColor,
            ),
          )
        : Container(
            width: isCompact ? 7 : 6,
            height: isCompact ? 7 : 6,
            decoration: BoxDecoration(
              color: dotColor,
              shape: BoxShape.circle,
            ),
          );

    if (isCompact) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          dotWidget,
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: textColor,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: dotColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          dotWidget,
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: textColor,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

