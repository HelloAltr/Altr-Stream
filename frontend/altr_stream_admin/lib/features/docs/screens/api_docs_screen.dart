import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/models.dart';
import '../../../core/config/app_config.dart';
import '../../../shared/widgets/page_header.dart';
import '../models/api_endpoint_model.dart';
import '../services/openapi_parser.dart';
import '../widgets/api_endpoint_detail_panel.dart';
import '../widgets/api_endpoint_list.dart';
import '../widgets/api_search_filter_bar.dart';

class ApiDocsScreen extends StatefulWidget {
  final ApiClient apiClient;
  final List<SourceModel> sources;
  final String nodeStatus;
  final VoidCallback? onNodeStatusTap;

  ApiDocsScreen({
    super.key,
    ApiClient? apiClient,
    this.sources = const [],
    this.nodeStatus = 'ACTIVE',
    this.onNodeStatusTap,
  }) : apiClient = apiClient ?? ApiClient();

  @override
  State<ApiDocsScreen> createState() => _ApiDocsScreenState();
}

class _ApiDocsScreenState extends State<ApiDocsScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  OpenApiSpecData _specData = OpenApiSpecData.empty;
  List<SourceModel> _sources = [];
  List<LogicalModelModel> _logicalModels = [];
  List<SourceMappingModel> _sourceMappings = [];

  String _searchQuery = '';
  String? _selectedMethod;
  String? _selectedTag;
  ApiEndpoint? _selectedEndpoint;

  @override
  void initState() {
    super.initState();
    _sources = List.from(widget.sources);
    _loadOpenApiSpec();
    _loadSources();
    _loadLogicalModels();
    _loadSourceMappings();
  }

  Future<void> _loadSources() async {
    try {
      final sources = await widget.apiClient.listSources();
      if (mounted && sources.isNotEmpty) {
        setState(() {
          _sources = sources;
        });
      }
    } catch (_) {
      // Non-blocking: sources are for convenience dropdowns
    }
  }

  Future<void> _loadOpenApiSpec() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final specMap = await widget.apiClient.getOpenApiSpec();
      final parsed = OpenApiParser.parse(specMap);
      setState(() {
        _specData = parsed;
        _isLoading = false;
        if (parsed.endpoints.isNotEmpty) {
          _selectedEndpoint = parsed.endpoints.first;
        }
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _loadLogicalModels() async {
    try {
      final models = await widget.apiClient.listLogicalModels();
      if (mounted) {
        setState(() {
          _logicalModels = models;
        });
      }
    } catch (_) {
      // Non-blocking: models are for convenience dropdowns
    }
  }

  Future<void> _loadSourceMappings() async {
    try {
      final mappings = await widget.apiClient.listSourceMappings();
      if (mounted) {
        setState(() {
          _sourceMappings = mappings;
        });
      }
    } catch (_) {
      // Non-blocking: mappings are for convenience dropdowns
    }
  }

  List<ApiEndpoint> get _filteredEndpoints {
    return _specData.endpoints.where((ep) {
      // Method filter
      if (_selectedMethod != null && ep.method.toUpperCase() != _selectedMethod!.toUpperCase()) {
        return false;
      }
      // Tag filter
      if (_selectedTag != null && !ep.tags.contains(_selectedTag)) {
        return false;
      }
      // Search query
      if (_searchQuery.trim().isNotEmpty && !ep.matchesSearch(_searchQuery)) {
        return false;
      }
      return true;
    }).toList();
  }

  void _clearFilters() {
    setState(() {
      _searchQuery = '';
      _selectedMethod = null;
      _selectedTag = null;
    });
  }

  Future<void> _openUrl(BuildContext context, String url) async {
    final uri = Uri.parse(url);
    try {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not open $url'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to open URL: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  void _copyToClipboard(BuildContext context, String text, String label) {
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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final filtered = _filteredEndpoints;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 960;

        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              PageHeader(
                title: 'API Explorer',
                description: 'Live FastAPI OpenAPI discovery, real-time search, parameter inspection, and native request execution.',
                nodeStatus: widget.nodeStatus,
                onNodeStatusTap: widget.onNodeStatusTap,
                primaryAction: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.refresh, size: 18),
                      tooltip: 'Reload OpenAPI Specification',
                      onPressed: _isLoading ? null : _loadOpenApiSpec,
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.open_in_new, size: 16),
                      label: const Text('Open Swagger UI'),
                      onPressed: () => _openUrl(context, AppConfig.apiDocsUrl),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Loading state
              if (_isLoading) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(48),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                  ),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 16),
                        Text(
                          'Discovering API schema from OpenAPI 3.1...',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          AppConfig.openApiJsonUrl,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ] else if (_errorMessage != null) ...[
                // Error state with retry
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: colorScheme.errorContainer.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: colorScheme.error.withValues(alpha: 0.5)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.error_outline, color: colorScheme.error, size: 22),
                          const SizedBox(width: 10),
                          Text(
                            'Failed to Load OpenAPI Specification',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.error,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _errorMessage!,
                        style: TextStyle(fontSize: 13, color: colorScheme.onSurface),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: colorScheme.error,
                          foregroundColor: colorScheme.onError,
                        ),
                        icon: const Icon(Icons.refresh, size: 16),
                        label: const Text('Retry Loading OpenAPI'),
                        onPressed: _loadOpenApiSpec,
                      ),
                    ],
                  ),
                ),
              ] else ...[
                // Search & Filter Bar
                ApiSearchFilterBar(
                  searchQuery: _searchQuery,
                  onSearchChanged: (q) => setState(() => _searchQuery = q),
                  selectedMethod: _selectedMethod,
                  onMethodChanged: (m) => setState(() => _selectedMethod = m),
                  selectedTag: _selectedTag,
                  onTagChanged: (t) => setState(() => _selectedTag = t),
                  availableMethods: _specData.discoveredMethods,
                  availableTags: _specData.discoveredTags,
                  totalCount: _specData.endpoints.length,
                  filteredCount: filtered.length,
                  onClearAll: _clearFilters,
                ),
                const SizedBox(height: 20),

                // Main Explorer Area: Split View on Desktop, Stacked on Mobile
                if (isDesktop) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Left Column: Endpoint List
                      Expanded(
                        flex: 4,
                        child: ApiEndpointList(
                          endpoints: filtered,
                          selectedEndpoint: _selectedEndpoint,
                          onSelectEndpoint: (ep) => setState(() => _selectedEndpoint = ep),
                          onClearFilters: _clearFilters,
                        ),
                      ),
                      const SizedBox(width: 24),

                      // Right Column: Endpoint Detail & Execution Panel
                      Expanded(
                        flex: 6,
                        child: _selectedEndpoint != null
                            ? ApiEndpointDetailPanel(
                                key: ValueKey('${_selectedEndpoint!.method}_${_selectedEndpoint!.path}'),
                                endpoint: _selectedEndpoint!,
                                apiClient: widget.apiClient,
                                sources: _sources,
                                logicalModels: _logicalModels,
                                sourceMappings: _sourceMappings,
                                onOpenSwagger: () => _openUrl(context, AppConfig.apiDocsUrl),
                              )
                            : Container(
                                padding: const EdgeInsets.all(48),
                                decoration: BoxDecoration(
                                  color: colorScheme.surfaceContainerLow,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                                ),
                                child: Center(
                                  child: Text(
                                    'Select an endpoint from the left to view details and execute requests.',
                                    style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
                                  ),
                                ),
                              ),
                      ),
                    ],
                  ),
                ] else ...[
                  // Mobile Layout: Stacked
                  ApiEndpointList(
                    endpoints: filtered,
                    selectedEndpoint: _selectedEndpoint,
                    onSelectEndpoint: (ep) {
                      setState(() => _selectedEndpoint = ep);
                      // Scroll down or open modal in mobile
                      _showMobileDetailModal(context, ep);
                    },
                    onClearFilters: _clearFilters,
                  ),
                ],
              ],

              const SizedBox(height: 36),

              // Secondary Section: External Documentation & Swagger Fallback
              _buildExternalDocsSection(context),
              const SizedBox(height: 24),

              // Quick cURL Reference
              _buildCurlReferenceCard(context),
            ],
          ),
        );
      },
    );
  }

  void _showMobileDetailModal(BuildContext context, ApiEndpoint ep) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.88,
          minChildSize: 0.5,
          maxChildSize: 0.96,
          expand: false,
          builder: (_, scrollController) {
            return SingleChildScrollView(
              controller: scrollController,
              padding: const EdgeInsets.all(16),
              child: ApiEndpointDetailPanel(
                endpoint: ep,
                apiClient: widget.apiClient,
                sources: _sources,
                logicalModels: _logicalModels,
                sourceMappings: _sourceMappings,
                onOpenSwagger: () => _openUrl(context, AppConfig.apiDocsUrl),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildExternalDocsSection(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.library_books_outlined, size: 18, color: colorScheme.primary),
              const SizedBox(width: 10),
              Text(
                'OpenAPI / Swagger Documentation',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'FastAPI serves the authoritative OpenAPI 3.1 specification. Access external Swagger UI or ReDoc below.',
            style: TextStyle(
              fontSize: 13,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 10,
            children: [
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: const Icon(Icons.rocket_launch, size: 16),
                label: const Text('Launch Swagger UI (/docs)'),
                onPressed: () => _openUrl(context, AppConfig.apiDocsUrl),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: const Icon(Icons.article_outlined, size: 16),
                label: const Text('Open ReDoc (/redoc)'),
                onPressed: () => _openUrl(context, AppConfig.redocDocsUrl),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: const Icon(Icons.code, size: 16),
                label: const Text('OpenAPI JSON (/openapi.json)'),
                onPressed: () => _openUrl(context, AppConfig.openApiJsonUrl),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCurlReferenceCard(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Quick cURL Request Reference',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.copy, size: 16),
                tooltip: 'Copy cURL command',
                onPressed: () => _copyToClipboard(
                  context,
                  'curl -X POST "${AppConfig.apiBaseUrl}/execute" \\\n  -H "Content-Type: application/json" \\\n  -d \'{"query": "SELECT u.id, u.name FROM users u"}\'',
                  'cURL command',
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(8),
            ),
            child: SelectableText(
              'curl -X POST "${AppConfig.apiBaseUrl}/execute" \\\n'
              '  -H "Content-Type: application/json" \\\n'
              '  -d \'{"query": "SELECT u.id, u.name FROM users u"}\'',
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: Color(0xFF68D391),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
