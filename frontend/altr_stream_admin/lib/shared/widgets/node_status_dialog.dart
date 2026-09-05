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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final successColor = isDark ? AppTheme.successDark : AppTheme.successLight;

    return Dialog(
      backgroundColor: colorScheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
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
                        color: AppTheme.successBg(context),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.bolt, color: successColor, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Node Status & Telemetry',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        Text(
                          'Altr Stream Local Infrastructure Node',
                          style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => Navigator.of(context).pop(),
                  color: colorScheme.onSurfaceVariant,
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Telemetry Rows
            Container(
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainer,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
              ),
              child: Column(
                children: [
                  _buildRow(context, 'Node Identifier', 'altr-stream-node-01', isMonospace: true),
                  _buildDivider(context),
                  _buildRow(
                    context,
                    'Node Health',
                    _error != null ? 'Unreachable' : (_healthInfo?['status'] ?? 'Healthy').toString(),
                    customWidget: StatusBadge(
                      status: _error != null ? 'UNREACHABLE' : (_healthInfo?['status'] ?? 'ACTIVE').toString(),
                    ),
                  ),
                  _buildDivider(context),
                  _buildRow(context, 'Service Name', _healthInfo?['service'] ?? 'Altr Stream Service'),
                  _buildDivider(context),
                  _buildRow(context, 'Version', _healthInfo?['version'] ?? '0.1.0', isMonospace: true),
                  _buildDivider(context),
                  _buildRow(context, 'API Base URL', AppConfig.apiBaseUrl, isMonospace: true),
                  _buildDivider(context),
                  _buildRow(
                    context,
                    'Connected Sources',
                    '${widget.activeSourcesCount} Active / ${widget.connectedSourcesCount} Total',
                  ),
                  if (_latencyMs != null) ...[
                    _buildDivider(context),
                    _buildRow(
                      context,
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
                      ? SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 2, color: colorScheme.primary),
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

  Widget _buildRow(BuildContext context, String label, String value, {bool isMonospace = false, Widget? customWidget}) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
          ),
          customWidget ??
              Text(
                value,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  fontFamily: isMonospace ? 'monospace' : null,
                  color: colorScheme.onSurface,
                ),
              ),
        ],
      ),
    );
  }

  Widget _buildDivider(BuildContext context) {
    return Divider(
      height: 1,
      thickness: 1,
      color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5),
    );
  }
}
