import 'package:flutter/material.dart';
import '../../../core/api/api_client.dart';
import '../../../core/config/app_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/page_header.dart';
import '../../../shared/widgets/status_badge.dart';

class SettingsScreen extends StatefulWidget {
  final ApiClient apiClient;
  final VoidCallback onNodeStatusTap;
  final String nodeStatus;

  const SettingsScreen({
    super.key,
    required this.apiClient,
    required this.onNodeStatusTap,
    this.nodeStatus = 'ACTIVE',
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Map<String, dynamic>? _healthInfo;
  bool _isProbing = false;
  double? _probeLatencyMs;

  @override
  void initState() {
    super.initState();
    _probeBackend();
  }

  Future<void> _probeBackend() async {
    setState(() => _isProbing = true);
    final sw = Stopwatch()..start();
    try {
      final res = await widget.apiClient.getHealth();
      sw.stop();
      if (mounted) {
        setState(() {
          _healthInfo = res;
          _probeLatencyMs = sw.elapsedMicroseconds / 1000.0;
        });
      }
    } catch (_) {
      sw.stop();
      if (mounted) {
        setState(() {
          _probeLatencyMs = sw.elapsedMicroseconds / 1000.0;
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isProbing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        PageHeader(
          title: 'Settings',
          description: 'Node configuration, networking metadata, and runtime diagnostics.',
          nodeStatus: widget.nodeStatus,
          onNodeStatusTap: widget.onNodeStatusTap,
          primaryAction: OutlinedButton.icon(
            onPressed: _isProbing ? null : _probeBackend,
            icon: _isProbing
                ? const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.accentCyan),
                  )
                : const Icon(Icons.refresh, size: 14),
            label: const Text('Probe Node Health'),
          ),
        ),

        // Settings Cards
        LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < 768;
            final children = [
              // Left: General & Node Identity
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.info_outline, color: AppTheme.accentCyan, size: 18),
                          SizedBox(width: 8),
                          Text('Node Identity & Role', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _buildRow('Node Name', 'altr-stream-node-01', isMonospace: true),
                      _buildDivider(),
                      _buildRow('Service Role', 'Physical Source Abstraction & CDC Node'),
                      _buildDivider(),
                      _buildRow('Service Version', _healthInfo?['version'] ?? '0.1.0', isMonospace: true),
                      _buildDivider(),
                      _buildRow('Ecosystem', 'HelloAltr / Altr Mesh Federated Architecture'),
                      _buildDivider(),
                      _buildRow(
                        'Operational State',
                        _healthInfo?['status'] ?? 'Healthy',
                        customWidget: StatusBadge(status: _healthInfo?['status'] ?? 'ACTIVE'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16, width: 20),

              // Right: Networking & Diagnostics
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.network_check, color: AppTheme.accentCyan, size: 18),
                          SizedBox(width: 8),
                          Text('Networking & Runtime', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _buildRow('API Base URL', AppConfig.apiBaseUrl, isMonospace: true),
                      _buildDivider(),
                      _buildRow('API Protocol', 'REST / JSON (FastAPI v1)', isMonospace: true),
                      _buildDivider(),
                      _buildRow('Reverse Proxy', 'Nginx 1.27 Static Host & Proxy'),
                      _buildDivider(),
                      _buildRow('Backend Status', _healthInfo != null ? 'Connected' : 'Checking...'),
                      if (_probeLatencyMs != null) ...[
                        _buildDivider(),
                        _buildRow('Probe Latency', '${_probeLatencyMs!.toStringAsFixed(1)} ms', isMonospace: true),
                      ],
                    ],
                  ),
                ),
              ),
            ];

            if (isNarrow) {
              return Column(children: children);
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: children[0]),
                const SizedBox(width: 20),
                Expanded(child: children[2]),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildRow(String label, String value, {bool isMonospace = false, Widget? customWidget}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
          const SizedBox(width: 12),
          customWidget ??
              Flexible(
                child: Text(
                  value,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    fontFamily: isMonospace ? 'monospace' : null,
                    color: AppTheme.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
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
