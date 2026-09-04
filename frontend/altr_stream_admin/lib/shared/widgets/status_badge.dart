import 'package:flutter/material.dart';
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
    if (isPkBadge) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: AppTheme.warningBg,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: AppTheme.warning.withValues(alpha: 0.4)),
        ),
        child: const Text(
          'PK',
          style: TextStyle(
            color: AppTheme.warning,
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
          color: AppTheme.accentCyanSubtle,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: AppTheme.accentCyan.withValues(alpha: 0.3)),
        ),
        child: Text(
          status.toUpperCase(),
          style: const TextStyle(
            color: AppTheme.accentCyan,
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

    switch (status.toUpperCase()) {
      case 'ACTIVE':
      case 'HEALTHY':
        dotColor = AppTheme.success;
        bgColor = AppTheme.successBg;
        textColor = AppTheme.success;
        label = 'Active';
        break;
      case 'UNREACHABLE':
        dotColor = AppTheme.error;
        bgColor = AppTheme.errorBg;
        textColor = AppTheme.error;
        label = 'Unreachable';
        break;
      case 'DEGRADED':
      case 'WARNING':
        dotColor = AppTheme.warning;
        bgColor = AppTheme.warningBg;
        textColor = AppTheme.warning;
        label = 'Degraded';
        break;
      case 'ERROR':
        dotColor = AppTheme.error;
        bgColor = AppTheme.errorBg;
        textColor = AppTheme.error;
        label = 'Error';
        break;
      default:
        dotColor = AppTheme.textMuted;
        bgColor = AppTheme.bgInput;
        textColor = AppTheme.textSecondary;
        label = status;
    }

    if (isCompact) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: dotColor,
              shape: BoxShape.circle,
            ),
          ),
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
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: dotColor,
              shape: BoxShape.circle,
            ),
          ),
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
