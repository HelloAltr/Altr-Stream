import 'package:flutter/material.dart';
import '../../core/api/api_client.dart';
import '../../core/config/app_config.dart';
import '../../core/theme/app_theme.dart';
import 'status_badge.dart';

class NodeStatusDialog extends StatefulWidget {
  final ApiClient apiClient;
  final int connectedSourcesCount;
  final int activeSourcesCount;

  const NodeStatusDialog({
    super.key,
    required this.apiClient,
    required this.connectedSourcesCount,
    required this.activeSourcesCount,
  });

  @override
  State<NodeStatusDialog> createState() => _NodeStatusDialogState();
}

class _NodeStatusDialogState extends State<NodeStatusDialog> {
  Map<String, dynamic>? _healthInfo;
  bool _isChecking = false;
  String? _error;
  double? _latencyMs;

  @override
  void initState() {
    super.initState();
    _checkHealth();
  }

  Future<void> _checkHealth() async {
    setState(() {
      _isChecking = true;
      _error = null;
    });

    final stopwatch = Stopwatch()..start();
    try {
      final health = await widget.apiClient.getHealth();
      stopwatch.stop();
      if (mounted) {
        setState(() {
          _healthInfo = health;
          _latencyMs = stopwatch.elapsedMicroseconds / 1000.0;
        });
      }
    } catch (e) {
      stopwatch.stop();
      if (mounted) {
        setState(() {
          _error = e.toString();
          _latencyMs = stopwatch.elapsedMicroseconds / 1000.0;
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isChecking = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppTheme.bgSecondary,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppTheme.borderColor),
      ),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 480),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppTheme.successBg,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.bolt, color: AppTheme.success, size: 20),
                    ),
                    const SizedBox(width: 12),
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Node Status & Telemetry',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        Text(
                          'Altr Stream Local Infrastructure Node',
                          style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                        ),
                      ],
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => Navigator.of(context).pop(),
                  color: AppTheme.textMuted,
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Telemetry Rows
            Container(
              decoration: BoxDecoration(
                color: AppTheme.bgPrimary,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.borderColor),
              ),
              child: Column(
                children: [
                  _buildRow('Node Identifier', 'altr-stream-node-01', isMonospace: true),
                  _buildDivider(),
                  _buildRow(
                    'Node Health',
                    _error != null ? 'Unreachable' : (_healthInfo?['status'] ?? 'Healthy').toString(),
                    customWidget: StatusBadge(
                      status: _error != null ? 'UNREACHABLE' : (_healthInfo?['status'] ?? 'ACTIVE').toString(),
                    ),
                  ),
                  _buildDivider(),
                  _buildRow('Service Name', _healthInfo?['service'] ?? 'Altr Stream Service'),
                  _buildDivider(),
                  _buildRow('Version', _healthInfo?['version'] ?? '0.1.0', isMonospace: true),
                  _buildDivider(),
                  _buildRow('API Base URL', AppConfig.apiBaseUrl, isMonospace: true),
                  _buildDivider(),
                  _buildRow(
                    'Connected Sources',
                    '${widget.activeSourcesCount} Active / ${widget.connectedSourcesCount} Total',
                  ),
                  if (_latencyMs != null) ...[
                    _buildDivider(),
                    _buildRow(
                      'API Latency',
                      '${_latencyMs!.toStringAsFixed(1)} ms',
                      isMonospace: true,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Actions
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                OutlinedButton.icon(
                  onPressed: _isChecking ? null : _checkHealth,
                  icon: _isChecking
                      ? const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.accentCyan),
                        )
                      : const Icon(Icons.refresh, size: 14),
                  label: Text(_isChecking ? 'Checking...' : 'Probe Node'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRow(String label, String value, {bool isMonospace = false, Widget? customWidget}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
          ),
          customWidget ??
              Text(
                value,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  fontFamily: isMonospace ? 'monospace' : null,
                  color: AppTheme.textPrimary,
                ),
              ),
        ],
      ),
    );
  }

  Widget _buildDivider() {
    return const Divider(height: 1, thickness: 1, color: AppTheme.borderColor);
  }
}
