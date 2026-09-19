import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/models.dart';
import '../../../core/config/app_config.dart';
import '../models/api_endpoint_model.dart';
import '../services/openapi_parser.dart';
import '../widgets/api_console_header.dart';
import '../widgets/api_endpoint_documentation.dart';
import '../widgets/api_endpoint_sidebar.dart';
import '../widgets/api_try_it_out_panel.dart';

/// Altr Stream Dedicated API Console screen.
///
/// Features a dedicated global top header (`ApiConsoleHeader`) sitting above
/// a three-region workspace:
///   - Left: Tag-grouped Endpoint Navigation & Filters (`ApiEndpointSidebar`)
///   - Center: Authoritative Documentation & Schemas (`ApiEndpointDocumentation`)
///   - Right: Interactive "Try It Out" Execution Console (`ApiTryItOutPanel`)
class ApiDocsScreen extends StatefulWidget {
  final ApiClient apiClient;
  final List<SourceModel> sources;
  final String nodeStatus;
  final VoidCallback? onNodeStatusTap;
  final VoidCallback? onBackToAdmin;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode>? onThemeModeChanged;

  ApiDocsScreen({
    super.key,
    ApiClient? apiClient,
    this.sources = const [],
    this.nodeStatus = 'ACTIVE',
    this.onNodeStatusTap,
    this.onBackToAdmin,
    this.themeMode = ThemeMode.system,
    this.onThemeModeChanged,
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final filtered = _filteredEndpoints;

    // Ensure active endpoint selection is valid within filtered results
    final effectiveEndpoint = (_selectedEndpoint != null && filtered.contains(_selectedEndpoint))
        ? _selectedEndpoint
        : (filtered.isNotEmpty ? filtered.first : _selectedEndpoint);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktopWide = constraints.maxWidth >= 1100;
        final isTablet = constraints.maxWidth >= 720 && constraints.maxWidth < 1100;
        final hasBoundedHeight = constraints.hasBoundedHeight;

        Widget content;
        if (_isLoading) {
          content = _buildLoadingState(context);
        } else if (_errorMessage != null) {
          content = _buildErrorState(context);
        } else if (isDesktopWide) {
          content = _buildDesktopThreeRegionWorkspace(
            context,
            filtered: filtered,
            endpoint: effectiveEndpoint,
            hasBoundedHeight: hasBoundedHeight,
          );
        } else if (isTablet) {
          content = _buildTabletWorkspace(
            context,
            filtered: filtered,
            endpoint: effectiveEndpoint,
            hasBoundedHeight: hasBoundedHeight,
          );
        } else {
          content = _buildMobileWorkspace(
            context,
            filtered: filtered,
            endpoint: effectiveEndpoint,
            hasBoundedHeight: hasBoundedHeight,
          );
        }

        final header = ApiConsoleHeader(
          searchQuery: _searchQuery,
          onSearchChanged: (q) => setState(() => _searchQuery = q),
          onBackToAdmin: widget.onBackToAdmin ?? () => Navigator.of(context).maybePop(),
          onRefreshSpec: _loadOpenApiSpec,
          isLoading: _isLoading,
          nodeStatus: widget.nodeStatus,
          onNodeStatusTap: widget.onNodeStatusTap,
          themeMode: widget.themeMode,
          onThemeModeChanged: widget.onThemeModeChanged,
          onOpenExternalUrl: (url) => _openUrl(context, url),
        );

        if (hasBoundedHeight) {
          return Scaffold(
            backgroundColor: colorScheme.surface,
            body: SafeArea(
              child: Column(
                children: [
                  header,
                  Expanded(child: content),
                ],
              ),
            ),
          );
        } else {
          return Container(
            color: colorScheme.surface,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                header,
                content,
              ],
            ),
          );
        }
      },
    );
  }

  // --- 1. DESKTOP THREE-REGION WORKSPACE ---
  Widget _buildDesktopThreeRegionWorkspace(
    BuildContext context, {
    required List<ApiEndpoint> filtered,
    required ApiEndpoint? endpoint,
    bool hasBoundedHeight = true,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      crossAxisAlignment: hasBoundedHeight ? CrossAxisAlignment.stretch : CrossAxisAlignment.start,
      children: [
        // Region 1 (Left): Endpoint Navigation Sidebar (tag grouped + filters)
        SizedBox(
          width: 290,
          child: ApiEndpointSidebar(
            endpoints: filtered,
            selectedEndpoint: endpoint,
            onSelectEndpoint: (ep) => setState(() => _selectedEndpoint = ep),
            selectedMethod: _selectedMethod,
            onMethodChanged: (m) => setState(() => _selectedMethod = m),
            selectedTag: _selectedTag,
            onTagChanged: (t) => setState(() => _selectedTag = t),
            availableMethods: _specData.discoveredMethods,
            availableTags: _specData.discoveredTags,
            totalCount: _specData.endpoints.length,
            filteredCount: filtered.length,
            onClearFilters: _clearFilters,
          ),
        ),

        // Vertical Divider 1
        VerticalDivider(
          width: 1,
          thickness: 1,
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),

        // Region 2 (Center): Documentation & Schema Details (Major Focus - flex 6)
        Expanded(
          flex: 6,
          child: endpoint != null
              ? ApiEndpointDocumentation(
                  key: ValueKey('doc_${endpoint.method}_${endpoint.path}'),
                  endpoint: endpoint,
                  onOpenSwagger: (url) => _openUrl(context, url),
                )
              : _buildEmptyCenterSelection(context),
        ),

        // Vertical Divider 2
        VerticalDivider(
          width: 1,
          thickness: 1,
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),

        // Region 3 (Right): Interactive "Try It Out" Execution Console (Compact - flex 4)
        Expanded(
          flex: 4,
          child: endpoint != null
              ? ApiTryItOutPanel(
                  key: ValueKey('try_${endpoint.method}_${endpoint.path}'),
                  endpoint: endpoint,
                  apiClient: widget.apiClient,
                  sources: _sources,
                  logicalModels: _logicalModels,
                  sourceMappings: _sourceMappings,
                )
              : _buildEmptyRightSelection(context),
        ),
      ],
    );
  }

  // --- 2. TABLET WORKSPACE (Sidebar + Tabbed Doc / Try) ---
  Widget _buildTabletWorkspace(
    BuildContext context, {
    required List<ApiEndpoint> filtered,
    required ApiEndpoint? endpoint,
    bool hasBoundedHeight = true,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    final tabViews = [
      ApiEndpointDocumentation(
        key: ValueKey('tab_doc_${endpoint?.method}_${endpoint?.path}'),
        endpoint: endpoint ?? filtered.first,
        onOpenSwagger: (url) => _openUrl(context, url),
      ),
      ApiTryItOutPanel(
        key: ValueKey('tab_try_${endpoint?.method}_${endpoint?.path}'),
        endpoint: endpoint ?? filtered.first,
        apiClient: widget.apiClient,
        sources: _sources,
        logicalModels: _logicalModels,
        sourceMappings: _sourceMappings,
      ),
    ];

    return Row(
      crossAxisAlignment: hasBoundedHeight ? CrossAxisAlignment.stretch : CrossAxisAlignment.start,
      children: [
        // Left: Endpoint Navigation Sidebar
        SizedBox(
          width: 260,
          child: ApiEndpointSidebar(
            endpoints: filtered,
            selectedEndpoint: endpoint,
            onSelectEndpoint: (ep) => setState(() => _selectedEndpoint = ep),
            selectedMethod: _selectedMethod,
            onMethodChanged: (m) => setState(() => _selectedMethod = m),
            selectedTag: _selectedTag,
            onTagChanged: (t) => setState(() => _selectedTag = t),
            availableMethods: _specData.discoveredMethods,
            availableTags: _specData.discoveredTags,
            totalCount: _specData.endpoints.length,
            filteredCount: filtered.length,
            onClearFilters: _clearFilters,
          ),
        ),

        VerticalDivider(
          width: 1,
          thickness: 1,
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),

        // Right: Tabbed Documentation & Try It Out
        Expanded(
          child: endpoint != null
              ? DefaultTabController(
                  length: 2,
                  child: Column(
                    mainAxisSize: hasBoundedHeight ? MainAxisSize.max : MainAxisSize.min,
                    children: [
                      TabBar(
                        tabs: const [
                          Tab(icon: Icon(Icons.description_outlined, size: 16), text: 'Documentation'),
                          Tab(icon: Icon(Icons.play_circle_outline, size: 16), text: 'Try It Out'),
                        ],
                      ),
                      if (hasBoundedHeight)
                        Expanded(child: TabBarView(children: tabViews))
                      else
                        SizedBox(height: 700, child: TabBarView(children: tabViews)),
                    ],
                  ),
                )
              : _buildEmptyCenterSelection(context),
        ),
      ],
    );
  }

  // --- 3. MOBILE WORKSPACE (Full Tabbed View) ---
  Widget _buildMobileWorkspace(
    BuildContext context, {
    required List<ApiEndpoint> filtered,
    required ApiEndpoint? endpoint,
    bool hasBoundedHeight = true,
  }) {
    final tabViews = [
      // Tab 1: Endpoints
      ApiEndpointSidebar(
        endpoints: filtered,
        selectedEndpoint: endpoint,
        onSelectEndpoint: (ep) => setState(() => _selectedEndpoint = ep),
        selectedMethod: _selectedMethod,
        onMethodChanged: (m) => setState(() => _selectedMethod = m),
        selectedTag: _selectedTag,
        onTagChanged: (t) => setState(() => _selectedTag = t),
        availableMethods: _specData.discoveredMethods,
        availableTags: _specData.discoveredTags,
        totalCount: _specData.endpoints.length,
        filteredCount: filtered.length,
        onClearFilters: _clearFilters,
      ),
      // Tab 2: Documentation
      endpoint != null
          ? ApiEndpointDocumentation(
              key: ValueKey('mob_doc_${endpoint.method}_${endpoint.path}'),
              endpoint: endpoint,
              onOpenSwagger: (url) => _openUrl(context, url),
            )
          : _buildEmptyCenterSelection(context),
      // Tab 3: Try It Out
      endpoint != null
          ? ApiTryItOutPanel(
              key: ValueKey('mob_try_${endpoint.method}_${endpoint.path}'),
              endpoint: endpoint,
              apiClient: widget.apiClient,
              sources: _sources,
              logicalModels: _logicalModels,
              sourceMappings: _sourceMappings,
            )
          : _buildEmptyRightSelection(context),
    ];

    return DefaultTabController(
      length: 3,
      child: Column(
        mainAxisSize: hasBoundedHeight ? MainAxisSize.max : MainAxisSize.min,
        children: [
          const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.list_alt, size: 16), text: 'Endpoints'),
              Tab(icon: Icon(Icons.description_outlined, size: 16), text: 'Docs'),
              Tab(icon: Icon(Icons.play_circle_outline, size: 16), text: 'Try It'),
            ],
          ),
          if (hasBoundedHeight)
            Expanded(child: TabBarView(children: tabViews))
          else
            SizedBox(height: 700, child: TabBarView(children: tabViews)),
        ],
      ),
    );
  }

  // --- LOADING STATE ---
  Widget _buildLoadingState(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Container(
        padding: const EdgeInsets.all(36),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 18),
            Text(
              'Discovering API schema from OpenAPI 3.1...',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 6),
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
    );
  }

  // --- ERROR STATE ---
  Widget _buildErrorState(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 560),
        padding: const EdgeInsets.all(28),
        margin: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: colorScheme.errorContainer.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colorScheme.error.withValues(alpha: 0.5)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.error_outline, color: colorScheme.error, size: 24),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Failed to Load OpenAPI Specification',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.error,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              _errorMessage ?? 'Unknown error occurred while parsing OpenAPI specification.',
              style: TextStyle(fontSize: 13, color: colorScheme.onSurface),
            ),
            const SizedBox(height: 18),
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
    );
  }

  // --- EMPTY STATES ---
  Widget _buildEmptyCenterSelection(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.api_outlined, size: 48, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4)),
            const SizedBox(height: 12),
            Text(
              'No Endpoint Selected',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
            ),
            const SizedBox(height: 4),
            Text(
              'Select an endpoint from the left navigation panel to view its documentation.',
              style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyRightSelection(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.play_circle_outline, size: 48, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4)),
            const SizedBox(height: 12),
            Text(
              'Try It Out Console',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
            ),
            const SizedBox(height: 4),
            Text(
              'Select an endpoint from the left to test execution with interactive parameters and live responses.',
              style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
