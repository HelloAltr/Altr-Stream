import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:hugeicons/hugeicons.dart';
import '../../../core/api/api_client.dart';
import '../../../core/config/app_config.dart';
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
  double? _probeLatencyMs;

  @override
  void initState() {
    super.initState();
    _probeBackend();
  }

  Future<void> _probeBackend() async {
    final sw = Stopwatch()..start();
    try {
      final res = await widget.apiClient.getHealth();
      sw.stop();
      if (res['version'] != null) {
        AppConfig.setRuntimeNodeVersion(res['version'].toString());
      }
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
    }
  }

  Future<void> _launchExternalUrl(String urlString) async {
    final uri = Uri.parse(urlString);
    try {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not open $urlString'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to open documentation: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label copied to clipboard'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: ClampingScrollPhysics(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
                          HugeIcon(icon: HugeIcons.strokeRoundedInformationCircle, color: colorScheme.primary, size: 18),
                          const SizedBox(width: 8),
                          Text('Node Identity & Role', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: colorScheme.onSurface)),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _buildRow(context, 'Node Name', 'altr-stream-node-01', isMonospace: true),
                      _buildDivider(context),
                      _buildRow(context, 'Service Role', 'Physical Source Abstraction & CDC Node'),
                      _buildDivider(context),
                      _buildRow(context, 'Node Version', AppConfig.appVersion, isMonospace: true),
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
                          HugeIcon(icon: HugeIcons.strokeRoundedWifi01, color: colorScheme.primary, size: 18),
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

        // API Documentation Card
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        HugeIcon(icon: HugeIcons.strokeRoundedBook02, color: colorScheme.primary, size: 18),
                        const SizedBox(width: 8),
                        Text('API Documentation', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: colorScheme.onSurface)),
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'OpenAPI / Swagger',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: colorScheme.onPrimaryContainer),
                          ),
                        ),
                      ],
                    ),
                    ElevatedButton.icon(
                      onPressed: () => _launchExternalUrl(AppConfig.apiDocsUrl),
                      icon: const HugeIcon(icon: HugeIcons.strokeRoundedShare01, size: 14),
                      label: const Text('Open Swagger UI'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: colorScheme.primary,
                        foregroundColor: colorScheme.onPrimary,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Access the live, interactive OpenAPI Swagger documentation generated directly by the Altr Stream FastAPI backend service.',
                  style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 16),
                _buildRow(
                  context,
                  'Swagger UI Endpoint',
                  AppConfig.apiDocsUrl,
                  isMonospace: true,
                  customWidget: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SelectableText(
                        AppConfig.apiDocsUrl,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'monospace',
                          color: colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 6),
                      IconButton(
                        icon: const HugeIcon(icon: HugeIcons.strokeRoundedCopy01, size: 14),
                        tooltip: 'Copy Swagger UI URL',
                        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                        padding: EdgeInsets.zero,
                        onPressed: () => _copyToClipboard(AppConfig.apiDocsUrl, 'Swagger UI URL'),
                      ),
                    ],
                  ),
                ),
                _buildDivider(context),
                _buildRow(
                  context,
                  'OpenAPI Specification (JSON)',
                  AppConfig.openApiJsonUrl,
                  isMonospace: true,
                  customWidget: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SelectableText(
                        AppConfig.openApiJsonUrl,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'monospace',
                          color: colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(width: 6),
                      IconButton(
                        icon: const HugeIcon(icon: HugeIcons.strokeRoundedCopy01, size: 14),
                        tooltip: 'Copy OpenAPI JSON URL',
                        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                        padding: EdgeInsets.zero,
                        onPressed: () => _copyToClipboard(AppConfig.openApiJsonUrl, 'OpenAPI JSON URL'),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: () => _launchExternalUrl(AppConfig.openApiJsonUrl),
                        icon: const HugeIcon(icon: HugeIcons.strokeRoundedCode, size: 12),
                        label: const Text('View JSON', style: TextStyle(fontSize: 11)),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
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
                    HugeIcon(icon: HugeIcons.strokeRoundedPaintBoard, color: colorScheme.primary, size: 18),
                    const SizedBox(width: 8),
                    Text('Theme & Appearance', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: colorScheme.onSurface)),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Color Theme Mode', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: colorScheme.onSurface)),
                          const SizedBox(height: 2),
                          Text('Select system preference, light mode, or dark mode', style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    SegmentedButton<ThemeMode>(
                      segments: const [
                        ButtonSegment(
                          value: ThemeMode.system,
                          label: Text('System'),
                          icon: HugeIcon(icon: HugeIcons.strokeRoundedSettings02, size: 16),
                        ),
                        ButtonSegment(
                          value: ThemeMode.light,
                          label: Text('Light'),
                          icon: HugeIcon(icon: HugeIcons.strokeRoundedSun01, size: 16),
                        ),
                        ButtonSegment(
                          value: ThemeMode.dark,
                          label: Text('Dark'),
                          icon: HugeIcon(icon: HugeIcons.strokeRoundedMoon02, size: 16),
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
        const SizedBox(height: 80),
      ],
    ),
  );
  }

  Widget _buildRow(BuildContext context, String label, String value, {bool isMonospace = false, Widget? customWidget}) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(label, style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant)),
          ),
          const SizedBox(width: 12),
          if (customWidget != null)
            Flexible(child: customWidget)
          else
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
