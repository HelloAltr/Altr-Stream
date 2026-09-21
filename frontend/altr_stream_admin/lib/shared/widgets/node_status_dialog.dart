import 'package:flutter/material.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:hugeicons/hugeicons.dart';
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

    return M3EDialog(
      title: 'Node Status & Telemetry',
      icon: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: AppTheme.successBg(context),
          borderRadius: BorderRadius.circular(8),
        ),
        child: HugeIcon(icon: HugeIcons.strokeRoundedFlash, color: successColor, size: 20),
      ),
      topDivider: false,
      bottomDivider: false,
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            const SizedBox(height: 12),

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
          ],
        ),
      ),
      actions: <Widget>[
        M3EButton.icon(
          style: M3EButtonStyle.tonal,
          onPressed: _isChecking ? null : _checkHealth,
          icon: _isChecking
              ? SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 2, color: colorScheme.primary),
                )
              : HugeIcon(icon: HugeIcons.strokeRoundedRefresh, color: colorScheme.onSecondaryContainer, size: 14),
          label: Text(_isChecking ? 'Checking...' : 'Probe Node'),
        ),
        M3EButton(
          style: M3EButtonStyle.filled,
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
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
