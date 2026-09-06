import 'package:flutter/material.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/models.dart';
import '../../../shared/widgets/page_header.dart';
import '../widgets/query_editor.dart';
import '../widgets/query_error_panel.dart';
import '../widgets/query_metadata_banner.dart';
import '../widgets/query_result_table.dart';
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
  bool _isExecuting = false;
  QueryExecuteResponseModel? _response;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _selectedSource = widget.initialSelectedSource ??
        (widget.sources.isNotEmpty ? widget.sources.first : null);
    _queryController = TextEditingController(text: 'SELECT * FROM users LIMIT 10;');
    _focusNode = FocusNode();
  }

  @override
  void dispose() {
    _queryController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _executeQuery() async {
    if (_selectedSource == null || _queryController.text.trim().isEmpty) return;

    setState(() {
      _isExecuting = true;
      _errorMessage = null;
      _response = null;
    });

    try {
      final res = await widget.apiClient.executeQuery(
        sourceId: _selectedSource!.id,
        query: _queryController.text.trim(),
      );
      setState(() {
        _response = res;
      });
    } catch (e) {
      setState(() {
        if (e is ApiException) {
          _errorMessage = e.message;
        } else {
          _errorMessage = e.toString();
        }
      });
    } finally {
      if (mounted) {
        setState(() {
          _isExecuting = false;
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final canExecute = _selectedSource != null && _queryController.text.trim().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Page Header
        PageHeader(
          title: 'Query Playground',
          description: 'Execute native database read queries directly against connected data sources and inspect results.',
          nodeStatus: widget.nodeStatus,
          onNodeStatusTap: widget.onNodeStatusTap,
          primaryAction: OutlinedButton.icon(
            onPressed: widget.onBack,
            icon: const Icon(Icons.arrow_back, size: 16),
            label: const Text('Back to Dashboard'),
          ),
        ),
        const SizedBox(height: 24),

        // 1. Source Selector
        SourceSelector(
          sources: widget.sources,
          selectedSource: _selectedSource,
          onSourceSelected: (src) {
            setState(() {
              _selectedSource = src;
              _response = null;
              _errorMessage = null;
            });
          },
          isExecuting: _isExecuting,
        ),
        const SizedBox(height: 16),

        // 2. Query Editor
        QueryEditor(
          controller: _queryController,
          focusNode: _focusNode,
          onExecute: _executeQuery,
          onClear: _clearEditor,
          isExecuting: _isExecuting,
          canExecute: canExecute,
        ),
        const SizedBox(height: 24),

        // 3. Error Panel (if error)
        if (_errorMessage != null) ...[
          QueryErrorPanel(
            errorMessage: _errorMessage!,
            onDismiss: () => setState(() => _errorMessage = null),
          ),
          const SizedBox(height: 24),
        ],

        // 4. Query Results (if executed)
        if (_response != null) ...[
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
        ] else if (_errorMessage == null) ...[
          // Initial Empty State Guidance Card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
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
                    'Select a target data source, write your native SQL read query (e.g. SELECT, WITH, EXPLAIN) in the editor above, and click Run Query or press ⌘+Enter to view results.',
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
