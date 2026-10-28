import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons_pro/hugeicons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/constants.dart';
import '../models/diagnostic_report.dart';
import '../services/backend_service.dart';

/// Comprehensive Diagnose & Fix modal displaying bounded diagnostic checks,
/// plain-language findings, safe actionable remediation, and post-action verification.
class DiagnoseAndFixDialog extends StatefulWidget {
  final BackendService backendService;
  final VoidCallback? onStatusChanged;

  const DiagnoseAndFixDialog({
    super.key,
    required this.backendService,
    this.onStatusChanged,
  });

  @override
  State<DiagnoseAndFixDialog> createState() => _DiagnoseAndFixDialogState();
}

class _DiagnoseAndFixDialogState extends State<DiagnoseAndFixDialog> {
  DiagnosticReport? _report;
  bool _isLoading = true;
  bool _isExecutingAction = false;
  String? _actionResultMessage;
  bool? _actionResultSuccess;

  @override
  void initState() {
    super.initState();
    _runDiagnostics();
  }

  Future<void> _runDiagnostics() async {
    setState(() {
      _isLoading = true;
    });
    try {
      final report = await widget.backendService.runDiagnostics();
      if (!mounted) return;
      setState(() {
        _report = report;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _executeRecommendedAction(RecommendedActionType action) async {
    setState(() {
      _isExecutingAction = true;
      _actionResultMessage = null;
      _actionResultSuccess = null;
    });

    try {
      switch (action) {
        case RecommendedActionType.startDocker:
          await widget.backendService.startDockerDesktop();
          break;
        case RecommendedActionType.installDocker:
          final uri = Uri.parse('https://www.docker.com/products/docker-desktop/');
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri);
          } else {
            await Clipboard.setData(const ClipboardData(text: 'https://www.docker.com/products/docker-desktop/'));
          }
          break;
        case RecommendedActionType.resumeDocker:
          await widget.backendService.resumeDockerDesktop();
          break;
        case RecommendedActionType.startNode:
          await widget.backendService.startNode();
          break;
        case RecommendedActionType.repairNode:
          await for (final _ in widget.backendService.repairNode()) {}
          break;
        case RecommendedActionType.none:
          break;
      }

      // Post-action bounded verification check
      final postReport = await widget.backendService.runDiagnostics();
      if (!mounted) return;

      final allChecksPassed = postReport.checks.every(
        (c) => c.status == DiagnosticStatus.passed || c.status == DiagnosticStatus.info || c.status == DiagnosticStatus.skipped,
      );

      setState(() {
        _report = postReport;
        _actionResultSuccess = allChecksPassed;
        _actionResultMessage = allChecksPassed
            ? 'Verified: Issue resolved successfully! All diagnostic checks passed.'
            : 'Action performed, but issue persists: ${postReport.primaryFinding}.';
      });

      widget.onStatusChanged?.call();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _actionResultSuccess = false;
        _actionResultMessage = 'Error during repair action: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isExecutingAction = false;
        });
      }
    }
  }

  Widget _buildStatusBadge(DiagnosticStatus status) {
    Color bg;
    Color fg;
    String label;
    IconData icon;

    switch (status) {
      case DiagnosticStatus.passed:
        bg = Colors.green.withValues(alpha: 0.15);
        fg = Colors.green.shade400;
        label = 'PASSED';
        icon = Icons.check_circle_outline;
        break;
      case DiagnosticStatus.failed:
        bg = Colors.red.withValues(alpha: 0.15);
        fg = Colors.red.shade400;
        label = 'FAILED';
        icon = Icons.error_outline;
        break;
      case DiagnosticStatus.warning:
        bg = Colors.amber.withValues(alpha: 0.15);
        fg = Colors.amber.shade400;
        label = 'WARNING';
        icon = Icons.warning_amber_outlined;
        break;
      case DiagnosticStatus.info:
        bg = Colors.blue.withValues(alpha: 0.15);
        fg = Colors.blue.shade400;
        label = 'INFO';
        icon = Icons.info_outline;
        break;
      case DiagnosticStatus.skipped:
        bg = Colors.grey.withValues(alpha: 0.15);
        fg = Colors.grey.shade400;
        label = 'SKIPPED';
        icon = Icons.remove_circle_outline;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: fg),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: fg,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final report = _report;

    return AlertDialog(
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('Diagnose & Fix'),
          IconButton(
            tooltip: 'Re-run Diagnostics',
            icon: const Icon(HugeIconsStroke.refresh, size: 18),
            onPressed: (_isLoading || _isExecutingAction) ? null : _runDiagnostics,
          ),
        ],
      ),
      content: SizedBox(
        width: kDialogStandardWidth,
        height: 520,
        child: _isLoading
            ? const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 12),
                    Text('Running diagnostic checks...'),
                  ],
                ),
              )
            : report == null
                ? const Center(child: Text('Unable to load diagnostic report.'))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Primary finding banner
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: report.recommendedAction != RecommendedActionType.none
                                ? Colors.amber.shade700
                                : Colors.green.shade700,
                            width: 1.5,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  report.recommendedAction != RecommendedActionType.none
                                      ? Icons.warning_amber_rounded
                                      : Icons.check_circle_rounded,
                                  color: report.recommendedAction != RecommendedActionType.none
                                      ? Colors.amber.shade400
                                      : Colors.green.shade400,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    report.primaryFinding,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              report.summaryExplanation,
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_actionResultMessage != null) ...[
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: _actionResultSuccess == true
                                ? Colors.green.withValues(alpha: 0.15)
                                : Colors.amber.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: _actionResultSuccess == true ? Colors.green : Colors.amber,
                            ),
                          ),
                          child: Text(
                            _actionResultMessage!,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: _actionResultSuccess == true ? Colors.green.shade300 : Colors.amber.shade300,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      const Text(
                        'Diagnostic Checks',
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                      const SizedBox(height: 6),
                      // Checks list
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surfaceContainerLowest,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(8),
                            child: Column(
                              children: [
                                for (int i = 0; i < report.checks.length; i++) ...[
                                  if (i > 0) const Divider(height: 1),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Expanded(
                                              child: Text(
                                                report.checks[i].title,
                                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            _buildStatusBadge(report.checks[i].status),
                                          ],
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          report.checks[i].details,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
      ),
      actions: [
        if (_report != null &&
            _report!.recommendedAction != RecommendedActionType.none &&
            _actionResultSuccess != true)
          FilledButton(
            onPressed: _isExecutingAction
                ? null
                : () => _executeRecommendedAction(_report!.recommendedAction),
            child: _isExecutingAction
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : Text(_report!.recommendedActionLabel),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
