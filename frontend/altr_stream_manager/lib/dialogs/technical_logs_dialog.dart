import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons_pro/hugeicons.dart';

import '../config/constants.dart';
import '../services/backend_service.dart';

/// Responsive technical logs dialog providing non-blocking asynchronous log retrieval,
/// copy to clipboard, and log buffer clearing.
class TechnicalLogsDialog extends StatefulWidget {
  final BackendService backendService;

  const TechnicalLogsDialog({super.key, required this.backendService});

  @override
  State<TechnicalLogsDialog> createState() => _TechnicalLogsDialogState();
}

class _TechnicalLogsDialogState extends State<TechnicalLogsDialog> {
  String _logs = '';
  bool _isLoading = true;
  String? _error;
  bool _showRawLogs = false;

  @override
  void initState() {
    super.initState();
    _fetchLogs();
  }

  Future<void> _fetchLogs({bool force = false}) async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final logs = await widget.backendService.getInstallationLogs(forceRefresh: force, raw: _showRawLogs);
      if (!mounted) return;
      setState(() {
        _logs = logs;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load logs: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _copyLogs() async {
    if (_logs.isEmpty) return;
    try {
      await Clipboard.setData(ClipboardData(text: _logs));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Logs copied to clipboard'),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to copy logs: $e'),
          backgroundColor: Colors.red.shade800,
        ),
      );
    }
  }

  Future<void> _clearLogs() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear Displayed Logs?'),
        content: const SizedBox(
          width: kDialogStandardWidth,
          child: Text(
            'This will clear Manager diagnostics and application session history. '
            'Docker container logs are managed externally by the Docker engine and are filtered by timestamp rather than deleted. '
            'It will not affect your running containers, volumes, settings, or application data.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Clear Logs'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await widget.backendService.clearLogs();
      await _fetchLogs(force: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Log buffer cleared'),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to clear logs: $e'),
          backgroundColor: Colors.red.shade800,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('Technical Logs'),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Copy Logs',
                icon: const Icon(HugeIconsStroke.copy01, size: 18),
                onPressed: _logs.isNotEmpty ? _copyLogs : null,
              ),
              IconButton(
                tooltip: 'Clear Logs',
                icon: const Icon(HugeIconsStroke.delete02, size: 18),
                onPressed: _logs.isNotEmpty ? _clearLogs : null,
              ),
              IconButton(
                tooltip: 'Refresh',
                icon: const Icon(HugeIconsStroke.refresh, size: 18),
                onPressed: _isLoading ? null : () => _fetchLogs(force: true),
              ),
            ],
          ),
        ],
      ),
      content: SizedBox(
        width: 580,
        height: 440,
        child: Column(
          children: [
            Row(
              children: [
                SegmentedButton<bool>(
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  segments: const [
                    ButtonSegment(
                      value: false,
                      label: Text('Decluttered', style: TextStyle(fontSize: 11)),
                      icon: Icon(HugeIconsStroke.filter, size: 12),
                    ),
                    ButtonSegment(
                      value: true,
                      label: Text('Raw Logs', style: TextStyle(fontSize: 11)),
                      icon: Icon(HugeIconsStroke.database01, size: 12),
                    ),
                  ],
                  selected: {_showRawLogs},
                  onSelectionChanged: (set) {
                    setState(() {
                      _showRawLogs = set.first;
                    });
                    _fetchLogs(force: true);
                  },
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _showRawLogs ? 'Full container logs' : 'Health checks collapsed',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                          fontSize: 11,
                        ),
                    textAlign: TextAlign.end,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: _isLoading
                    ? const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 12),
                            Text('Retrieving technical logs...'),
                          ],
                        ),
                      )
                    : _error != null
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.error_outline, color: Colors.red.shade400, size: 36),
                                const SizedBox(height: 8),
                                Text(_error!),
                                const SizedBox(height: 12),
                                OutlinedButton(
                                  onPressed: () => _fetchLogs(force: true),
                                  child: const Text('Retry'),
                                ),
                              ],
                            ),
                          )
                        : SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: SingleChildScrollView(
                              scrollDirection: Axis.vertical,
                              child: SelectableText(
                                _logs.isEmpty ? 'No logs available.' : _logs,
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
