import 'package:flutter/material.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/models.dart';
import '../../../shared/widgets/page_header.dart';
import '../widgets/command_outcome_panel.dart';
import '../widgets/destructive_query_dialog.dart';
import '../widgets/query_editor.dart';
import '../widgets/query_error_panel.dart';
import '../widgets/query_metadata_banner.dart';
import '../widgets/query_result_table.dart';
import '../widgets/schema_explorer.dart';
import '../widgets/source_selector.dart';

class QueryPlaygroundScreen extends StatefulWidget {
  final List<SourceModel> sources;
  final ApiClient apiClient;
  final String nodeStatus;
  final VoidCallback? onNodeStatusTap;
  final VoidCallback onBack;
  final SourceModel? initialSelectedSource;

  const QueryPlaygroundScreen({
    super.key,
    required this.sources,
    required this.apiClient,
    required this.nodeStatus,
    this.onNodeStatusTap,
    required this.onBack,
    this.initialSelectedSource,
  });

  @override
  State<QueryPlaygroundScreen> createState() => _QueryPlaygroundScreenState();
}

class _QueryPlaygroundScreenState extends State<QueryPlaygroundScreen> {
  late TextEditingController _queryController;
  late FocusNode _focusNode;
  SourceModel? _selectedSource;
  SourceSchemaModel? _schema;
  bool _isLoadingSchema = false;
  String? _schemaErrorMessage;
  bool _isExecuting = false;
  QueryExecuteResponseModel? _response;
  String? _errorMessage;
  bool _isTabletSchemaOpen = false;

  @override
  void initState() {
    super.initState();
    _selectedSource = widget.initialSelectedSource ??
        (widget.sources.isNotEmpty ? widget.sources.first : null);
    _queryController = TextEditingController(text: 'SELECT * FROM users LIMIT 10;');
    _focusNode = FocusNode();

    _queryController.addListener(_onQueryChanged);

    if (_selectedSource != null) {
      _loadSchema(_selectedSource!.id);
    }
  }

  void _onQueryChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _queryController.removeListener(_onQueryChanged);
    _queryController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _loadSchema(String sourceId, {bool forceDiscover = false}) async {
    setState(() {
      _isLoadingSchema = true;
      _schemaErrorMessage = null;
    });

    try {
      SourceSchemaModel? loadedSchema;
      if (forceDiscover) {
        loadedSchema = await widget.apiClient.discoverSchema(sourceId);
      } else {
        loadedSchema = await widget.apiClient.getLatestSchema(sourceId);
        loadedSchema ??= await widget.apiClient.discoverSchema(sourceId);
      }

      if (mounted) {
        setState(() {
          _schema = loadedSchema;
          _isLoadingSchema = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _schemaErrorMessage = e is ApiException ? e.message : e.toString();
          _isLoadingSchema = false;
        });
      }
    }
  }

  void _onSourceChanged(SourceModel? src) {
    setState(() {
      _selectedSource = src;
      _schema = null;
      _response = null;
      _errorMessage = null;
    });
    if (src != null) {
      _loadSchema(src.id);
    }
  }

  void _insertTableTemplate(EntitySchemaModel entity) {
    final template = 'SELECT * FROM ${entity.name} LIMIT 100;\n';
    setState(() {
      _queryController.text = template;
      _response = null;
      _errorMessage = null;
    });
    _focusNode.requestFocus();
  }

  void _insertColumnName(FieldSchemaModel field, EntitySchemaModel entity) {
    final currentText = _queryController.text;
    final selection = _queryController.selection;

    if (selection.isValid && selection.start >= 0) {
      final newText = currentText.replaceRange(selection.start, selection.end, field.name);
      _queryController.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: selection.start + field.name.length),
      );
    } else {
      _queryController.text = '$currentText ${field.name}';
    }
    _focusNode.requestFocus();
  }

  Future<void> _executeQuery() async {
    if (_isExecuting || _selectedSource == null || _queryController.text.trim().isEmpty) return;

    final queryText = _queryController.text.trim();

    // UX Safety Guardrail: Confirm destructive operations
    if (isDestructiveQuery(queryText)) {
      final confirmed = await DestructiveQueryDialog.show(context, queryText);
      if (!confirmed) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _focusNode.requestFocus();
          }
        });
        return;
      }
    }

    setState(() {
      _isExecuting = true;
      _errorMessage = null;
      _response = null;
    });

    try {
      final res = await widget.apiClient.executeQuery(
        sourceId: _selectedSource!.id,
        query: queryText,
      );
      if (mounted) {
        setState(() {
          _response = res;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          if (e is ApiException) {
            _errorMessage = e.message;
          } else {
            _errorMessage = e.toString();
          }
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isExecuting = false;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _focusNode.requestFocus();
          }
        });
      }
    }
  }

  void _clearEditor() {
    setState(() {
      _queryController.clear();
      _response = null;
      _errorMessage = null;
    });
    _focusNode.requestFocus();
  }

  void _showMobileSchemaBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.4,
        maxChildSize: 0.92,
        builder: (_, scrollController) => Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Expanded(
                child: SchemaExplorer(
                  selectedSource: _selectedSource,
                  schema: _schema,
                  isLoading: _isLoadingSchema,
                  errorMessage: _schemaErrorMessage,
                  onRefreshSchema: () {
                    if (_selectedSource != null) {
                      _loadSchema(_selectedSource!.id, forceDiscover: true);
                    }
                  },
                  onSelectTable: (entity) {
                    Navigator.pop(ctx);
                    _insertTableTemplate(entity);
                  },
                  onSelectColumn: (field, entity) {
                    _insertColumnName(field, entity);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final canExecute = _selectedSource != null && _queryController.text.trim().isNotEmpty;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 1024;
        final isTablet = constraints.maxWidth >= 640 && constraints.maxWidth < 1024;
        final isMobile = constraints.maxWidth < 640;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Page Header
            PageHeader(
              title: 'Query Playground',
              description: 'Execute native database queries directly against connected data sources and explore discovered schemas.',
              nodeStatus: widget.nodeStatus,
              onNodeStatusTap: widget.onNodeStatusTap,
              primaryAction: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isMobile)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilledButton.tonalIcon(
                        onPressed: () => _showMobileSchemaBottomSheet(context),
                        icon: const Icon(Icons.account_tree_outlined, size: 16),
                        label: const Text('Schema'),
                        style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
                      ),
                    ),
                  if (isTablet)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: OutlinedButton.icon(
                        onPressed: () => setState(() => _isTabletSchemaOpen = !_isTabletSchemaOpen),
                        icon: Icon(_isTabletSchemaOpen ? Icons.visibility_off_outlined : Icons.account_tree_outlined, size: 16),
                        label: Text(_isTabletSchemaOpen ? 'Hide Schema' : 'Show Schema'),
                        style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                      ),
                    ),
                  OutlinedButton.icon(
                    onPressed: widget.onBack,
                    icon: const Icon(Icons.arrow_back, size: 16),
                    label: const Text('Back to Dashboard'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // 1. Source Selector
            SourceSelector(
              sources: widget.sources,
              selectedSource: _selectedSource,
              onSourceSelected: _onSourceChanged,
              isExecuting: _isExecuting,
            ),
            const SizedBox(height: 16),

            // 2. Main Workspace Layout (Desktop Two-Panel vs Tablet/Mobile Stacked)
            if (isDesktop)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Left: Schema Explorer (Width: 320px)
                  SizedBox(
                    width: 320,
                    height: 640,
                    child: SchemaExplorer(
                      selectedSource: _selectedSource,
                      schema: _schema,
                      isLoading: _isLoadingSchema,
                      errorMessage: _schemaErrorMessage,
                      onRefreshSchema: () {
                        if (_selectedSource != null) {
                          _loadSchema(_selectedSource!.id, forceDiscover: true);
                        }
                      },
                      onSelectTable: _insertTableTemplate,
                      onSelectColumn: _insertColumnName,
                    ),
                  ),
                  const SizedBox(width: 16),

                  // Right: Query Workspace
                  Expanded(
                    child: _buildQueryWorkspace(context, colorScheme, canExecute),
                  ),
                ],
              )
            else ...[
              // Tablet Collapsible Schema Explorer
              if (isTablet && _isTabletSchemaOpen) ...[
                SizedBox(
                  height: 320,
                  child: SchemaExplorer(
                    selectedSource: _selectedSource,
                    schema: _schema,
                    isLoading: _isLoadingSchema,
                    errorMessage: _schemaErrorMessage,
                    onRefreshSchema: () {
                      if (_selectedSource != null) {
                        _loadSchema(_selectedSource!.id, forceDiscover: true);
                      }
                    },
                    onSelectTable: _insertTableTemplate,
                    onSelectColumn: _insertColumnName,
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Query Workspace for Tablet & Mobile
              _buildQueryWorkspace(context, colorScheme, canExecute),
            ],
          ],
        );
      },
    );
  }

  Widget _buildQueryWorkspace(BuildContext context, ColorScheme colorScheme, bool canExecute) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Query Editor
        QueryEditor(
          controller: _queryController,
          focusNode: _focusNode,
          onExecute: _executeQuery,
          onClear: _clearEditor,
          isExecuting: _isExecuting,
          canExecute: canExecute,
          selectedSource: _selectedSource,
        ),
        const SizedBox(height: 24),

        // Error Panel
        if (_errorMessage != null) ...[
          QueryErrorPanel(
            errorMessage: _errorMessage!,
            onDismiss: () => setState(() => _errorMessage = null),
          ),
          const SizedBox(height: 24),
        ],

        // Query Results or Command Outcome
        if (_response != null) ...[
          if (_response!.isResultSet) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Query Results',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
                QueryMetadataBanner(
                  rowCount: _response!.metadata.rowCount,
                  executionTimeMs: _response!.metadata.executionTimeMs,
                  sourceName: _selectedSource?.name ?? 'Database',
                ),
              ],
            ),
            const SizedBox(height: 12),
            QueryResultTable(
              columns: _response!.columns,
              rows: _response!.rows,
            ),
          ] else ...[
            CommandOutcomePanel(
              metadata: _response!.metadata,
              sourceName: _selectedSource?.name ?? 'Database',
            ),
          ],
        ] else if (_errorMessage == null) ...[
          // Initial Guidance Card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainer,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.terminal, color: colorScheme.primary.withValues(alpha: 0.7), size: 36),
                const SizedBox(height: 12),
                Text(
                  'Ready to Execute Physical Queries',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Text(
                    'Select a data source, explore its schema on the left, write your native query in the editor, and click Run Query or press ⌘+Enter to execute.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
