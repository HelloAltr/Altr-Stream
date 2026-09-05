import 'package:flutter/material.dart';
import '../../../core/api/api_client.dart';
import '../../../core/config/app_config.dart';
import '../../../shared/widgets/page_header.dart';
import '../../../shared/widgets/status_badge.dart';

class SettingsScreen extends StatefulWidget {
  final ApiClient apiClient;
  final VoidCallback onNodeStatusTap;
  final String nodeStatus;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode>? onThemeModeChanged;

  const SettingsScreen({
    super.key,
    required this.apiClient,
    required this.onNodeStatusTap,
    this.nodeStatus = 'ACTIVE',
    this.themeMode = ThemeMode.system,
    this.onThemeModeChanged,
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
    final colorScheme = Theme.of(context).colorScheme;

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
                ? SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 2, color: colorScheme.primary),
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
                      Row(
                        children: [
                          Icon(Icons.info_outline, color: colorScheme.primary, size: 18),
                          const SizedBox(width: 8),
                          Text('Node Identity & Role', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: colorScheme.onSurface)),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _buildRow(context, 'Node Name', 'altr-stream-node-01', isMonospace: true),
                      _buildDivider(context),
                      _buildRow(context, 'Service Role', 'Physical Source Abstraction & CDC Node'),
                      _buildDivider(context),
                      _buildRow(context, 'Service Version', _healthInfo?['version'] ?? '0.1.0', isMonospace: true),
                      _buildDivider(context),
                      _buildRow(context, 'Ecosystem', 'HelloAltr / Altr Mesh Federated Architecture'),
                      _buildDivider(context),
                      _buildRow(
                        context,
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
                      Row(
                        children: [
                          Icon(Icons.network_check, color: colorScheme.primary, size: 18),
                          const SizedBox(width: 8),
                          Text('Networking & Runtime', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: colorScheme.onSurface)),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _buildRow(context, 'API Base URL', AppConfig.apiBaseUrl, isMonospace: true),
                      _buildDivider(context),
                      _buildRow(context, 'API Protocol', 'REST / JSON (FastAPI v1)', isMonospace: true),
                      _buildDivider(context),
                      _buildRow(context, 'Reverse Proxy', 'Nginx 1.27 Static Host & Proxy'),
                      _buildDivider(context),
                      _buildRow(context, 'Backend Status', _healthInfo != null ? 'Connected' : 'Checking...'),
                      if (_probeLatencyMs != null) ...[
                        _buildDivider(context),
                        _buildRow(context, 'Probe Latency', '${_probeLatencyMs!.toStringAsFixed(1)} ms', isMonospace: true),
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
        const SizedBox(height: 16),

        // Theme & Appearance Card
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.palette_outlined, color: colorScheme.primary, size: 18),
                    const SizedBox(width: 8),
                    Text('Theme & Appearance', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: colorScheme.onSurface)),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Color Theme Mode', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: colorScheme.onSurface)),
                        const SizedBox(height: 2),
                        Text('Select system preference, light mode, or dark mode', style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
                      ],
                    ),
                    SegmentedButton<ThemeMode>(
                      segments: const [
                        ButtonSegment(
                          value: ThemeMode.system,
                          label: Text('System'),
                          icon: Icon(Icons.brightness_auto, size: 16),
                        ),
                        ButtonSegment(
                          value: ThemeMode.light,
                          label: Text('Light'),
                          icon: Icon(Icons.light_mode, size: 16),
                        ),
                        ButtonSegment(
                          value: ThemeMode.dark,
                          label: Text('Dark'),
                          icon: Icon(Icons.dark_mode, size: 16),
                        ),
                      ],
                      selected: {widget.themeMode},
                      onSelectionChanged: (Set<ThemeMode> newSelection) {
                        if (widget.onThemeModeChanged != null && newSelection.isNotEmpty) {
                          widget.onThemeModeChanged!(newSelection.first);
                        }
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRow(BuildContext context, String label, String value, {bool isMonospace = false, Widget? customWidget}) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant)),
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
                    color: colorScheme.onSurface,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
        ],
      ),
    );
  }

  Widget _buildDivider(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Divider(height: 1, thickness: 1, color: colorScheme.outlineVariant.withValues(alpha: 0.5));
  }
}
