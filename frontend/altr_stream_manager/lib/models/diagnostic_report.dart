import 'package:flutter/material.dart';

enum DiagnosticStatus {
  passed,
  failed,
  warning,
  info,
  skipped,
}

extension DiagnosticStatusX on DiagnosticStatus {
  String get displayName {
    switch (this) {
      case DiagnosticStatus.passed:
        return 'PASSED';
      case DiagnosticStatus.failed:
        return 'FAILED';
      case DiagnosticStatus.warning:
        return 'WARNING';
      case DiagnosticStatus.info:
        return 'INFO';
      case DiagnosticStatus.skipped:
        return 'SKIPPED';
    }
  }

  Color getColor(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    switch (this) {
      case DiagnosticStatus.passed:
        return isLight ? Colors.green.shade700 : Colors.lightGreen;
      case DiagnosticStatus.failed:
        return isLight ? Colors.red.shade700 : Colors.redAccent;
      case DiagnosticStatus.warning:
        return isLight ? Colors.orange.shade800 : Colors.orangeAccent;
      case DiagnosticStatus.info:
        return isLight ? Colors.blue.shade700 : Colors.lightBlue;
      case DiagnosticStatus.skipped:
        return isLight ? Colors.grey.shade600 : Colors.grey.shade400;
    }
  }

  IconData get icon {
    switch (this) {
      case DiagnosticStatus.passed:
        return Icons.check_circle_outline;
      case DiagnosticStatus.failed:
        return Icons.error_outline;
      case DiagnosticStatus.warning:
        return Icons.warning_amber_outlined;
      case DiagnosticStatus.info:
        return Icons.info_outline;
      case DiagnosticStatus.skipped:
        return Icons.remove_circle_outline;
    }
  }
}

class DiagnosticCheck {
  final String title;
  final String description;
  final DiagnosticStatus status;
  final String details;

  const DiagnosticCheck({
    required this.title,
    required this.description,
    required this.status,
    required this.details,
  });
}

enum RecommendedActionType {
  none,
  startDocker,
  installDocker,
  resumeDocker,
  startNode,
  repairNode,
}

class DiagnosticReport {
  final List<DiagnosticCheck> checks;
  final String primaryFinding;
  final String summaryExplanation;
  final RecommendedActionType recommendedAction;
  final String recommendedActionLabel;
  final DateTime timestamp;

  const DiagnosticReport({
    required this.checks,
    required this.primaryFinding,
    required this.summaryExplanation,
    required this.recommendedAction,
    required this.recommendedActionLabel,
    required this.timestamp,
  });

  bool get hasIssues =>
      checks.any((c) => c.status == DiagnosticStatus.failed || c.status == DiagnosticStatus.warning);
}
