import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/models.dart';
import '../../../shared/widgets/page_header.dart';

class AltrQLPlaygroundScreen extends StatefulWidget {
  final List<SourceModel> sources;
  final String nodeStatus;
  final VoidCallback? onNodeStatusTap;
  final VoidCallback onBack;
  final ValueChanged<SourceModel>? onNavigateToSource;
  final ApiClient? apiClient;

  const AltrQLPlaygroundScreen({
    super.key,
    required this.sources,
    required this.nodeStatus,
    this.onNodeStatusTap,
    required this.onBack,
    this.onNavigateToSource,
    this.apiClient,
  });

  @override
  State<AltrQLPlaygroundScreen> createState() => _AltrQLPlaygroundScreenState();
}

class _AltrQLPlaygroundScreenState extends State<AltrQLPlaygroundScreen> {
  late TextEditingController _queryController;
  late FocusNode _focusNode;
  SourceModel? _selectedSource;
  late final ApiClient _apiClient;

  bool _isParsing = false;
  bool _isBinding = false;
  bool _isExecuting = false;

  Map<String, dynamic>? _ir;
  Map<String, dynamic>? _boundIr;
  PhysicalQueryModel? _physicalQuery;
  List<String> _columns = [];
  List<Map<String, dynamic>> _rows = [];
  QueryMetadataModel? _metadata;
  AltrQLErrorDetailModel? _error;

  int _activeResultTab = 0; // 0: Results, 1: Physical Query, 2: Bound IR, 3: Canonical IR

  static const String _defaultAltrQL = '''// AltrQL Query Definition
GET users (
    id,
    username,
    email,
    age
) WHERE {
    age >= 18
} SORT {
    age DESC
};''';

  static const Map<String, String> _templates = {
    'Simple Read': '''// Logical read with field projection & filter
GET users (
    id,
    username,
    email
) WHERE {
    age >= 18
};''',
    'Range & Sets': '''// Filter with range and value set expressions
GET users (
    id,
    username,
    age
) WHERE {
    id = {1, 2, 6..10},
    age = {>=18 & <=50}
};''',
    'String Patterns': '''// String matchers (STARTS, ENDS, HAS, NOT HAS)
GET users (
    id,
    username,
    email
) WHERE {
    username STARTS "San",
    email ENDS "@test.com"
};''',
    'Ranking & Pagination': '''// Ranking TOP n BY field with OFFSET
GET users (
    id,
    username,
    age
) TOP 10 BY age OFFSET 20;''',
  };

  @override
  void initState() {
    super.initState();
    _apiClient = widget.apiClient ?? ApiClient();
    _queryController = TextEditingController(text: _defaultAltrQL);
    _focusNode = FocusNode();
    if (widget.sources.isNotEmpty) {
      _selectedSource = widget.sources.first;
    }
  }

  @override
  void dispose() {
    _queryController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  bool get _isBusy => _isParsing || _isBinding || _isExecuting;

  Future<void> _handleParse() async {
    final queryText = _queryController.text.trim();
    if (queryText.isEmpty || _isBusy) return;

    setState(() {
      _isParsing = true;
      _error = null;
    });

    try {
      final response = await _apiClient.parseAltrQL(queryText);
      if (!mounted) return;

      setState(() {
        _isParsing = false;
        if (response.success) {
          _ir = response.ir;
          _boundIr = null;
          _physicalQuery = null;
          _columns = [];
          _rows = [];
          _metadata = null;
          _error = null;
          _activeResultTab = 3; // Canonical IR tab
        } else {
          _ir = null;
          _boundIr = null;
          _physicalQuery = null;
          _columns = [];
          _rows = [];
          _metadata = null;
          _error = response.error ??
              AltrQLErrorDetailModel(
                type: 'AltrQueryParseError',
                message: 'Failed to parse query',
              );
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isParsing = false;
        _ir = null;
        _boundIr = null;
        _physicalQuery = null;
        _columns = [];
        _rows = [];
        _metadata = null;
        _error = AltrQLErrorDetailModel(
          type: 'AltrQueryParseError',
          message: e.toString(),
        );
      });
    }
  }

  Future<void> _handleBind() async {
    final queryText = _queryController.text.trim();
    if (queryText.isEmpty || _isBusy || _selectedSource == null) return;

    setState(() {
      _isBinding = true;
      _error = null;
    });

    try {
      final response = await _apiClient.bindAltrQL(
        query: queryText,
        sourceId: _selectedSource!.id,
      );
      if (!mounted) return;

      setState(() {
        _isBinding = false;
        if (response.success) {
          _ir = response.ir;
          _boundIr = response.boundIr;
          _physicalQuery = null;
          _columns = [];
          _rows = [];
          _metadata = null;
          _error = null;
          _activeResultTab = 2; // Bound IR tab
        } else {
          _ir = response.ir;
          _boundIr = null;
          _physicalQuery = null;
          _columns = [];
          _rows = [];
          _metadata = null;
          _error = response.error ??
              AltrQLErrorDetailModel(
                type: 'AltrQuerySchemaError',
                message: 'Failed to bind query against schema',
              );
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isBinding = false;
        _boundIr = null;
        _physicalQuery = null;
        _columns = [];
        _rows = [];
        _metadata = null;
        _error = AltrQLErrorDetailModel(
          type: 'AltrQuerySchemaError',
          message: e.toString(),
        );
      });
    }
  }

  Future<void> _handleExecute() async {
    final queryText = _queryController.text.trim();
    if (queryText.isEmpty || _isBusy || _selectedSource == null) return;

    setState(() {
      _isExecuting = true;
      _error = null;
    });

    try {
      final response = await _apiClient.executeAltrQL(
        query: queryText,
        sourceId: _selectedSource!.id,
      );
      if (!mounted) return;

      setState(() {
        _isExecuting = false;
        _ir = response.ir;
        _boundIr = response.boundIr;
        _physicalQuery = response.physicalQuery;

        if (response.success) {
          _columns = response.columns;
          _rows = response.rows;
          _metadata = response.metadata;
          _error = null;
          _activeResultTab = 0; // Results tab
        } else {
          _columns = [];
          _rows = [];
          _metadata = null;
          _error = response.error ??
              AltrQLErrorDetailModel(
                type: 'AltrQueryExecutionError',
                message: 'Query execution failed',
              );
          // If we have a physical query even on error, default to physical query tab
          if (_physicalQuery != null) {
            _activeResultTab = 1;
          }
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isExecuting = false;
        _columns = [];
        _rows = [];
        _metadata = null;
        _error = AltrQLErrorDetailModel(
          type: 'AltrQueryExecutionError',
          message: e.toString(),
        );
      });
    }
  }

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label copied to clipboard'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        width: 320,
      ),
    );
  }

  void _showEngineRoadmapDialog() {
    final colorScheme = Theme.of(context).colorScheme;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.code_rounded, color: colorScheme.primary, size: 20),
            ),
            const SizedBox(width: 12),
            const Text('AltrQL Execution Engine', style: TextStyle(fontSize: 16)),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'AltrQL provides a unified, vendor-neutral query interface with pure compilation and controlled database execution.',
                style: TextStyle(fontSize: 13, color: colorScheme.onSurface),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainer,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Implementation Roadmap:',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
                    ),
                    const SizedBox(height: 8),
                    _buildRoadmapItem('Phase B', 'Language Specification & Parser Core', true),
                    _buildRoadmapItem('Phase B.5', 'Interactive Parser Playground', true),
                    _buildRoadmapItem('Phase C', 'Semantic Validation & Normalization IR', true),
                    _buildRoadmapItem('Phase D', 'Schema Binding & Type Validation', true),
                    _buildRoadmapItem('Phase E', 'Physical Query Lowering & Controlled Execution', true),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'AltrQL compiles queries deterministically into parameterized SQL, executing them securely against connected data sources.',
                style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        actions: [
          if (_selectedSource != null && widget.onNavigateToSource != null)
            TextButton.icon(
              onPressed: () {
                Navigator.of(ctx).pop();
                widget.onNavigateToSource!(_selectedSource!);
              },
              icon: const Icon(Icons.arrow_forward, size: 14),
              label: Text('Open ${_selectedSource!.name} Detail'),
            ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  Widget _buildRoadmapItem(String phase, String label, bool isDoneOrNext) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: isDoneOrNext ? colorScheme.primary : colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              phase,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: isDoneOrNext ? colorScheme.onPrimary : colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: isDoneOrNext ? colorScheme.primary : colorScheme.onSurfaceVariant,
                fontWeight: isDoneOrNext ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter, meta: true): _handleExecute,
        const SingleActivator(LogicalKeyboardKey.enter, control: true): _handleExecute,
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageHeader(
            title: 'AltrQL Console',
            description: 'Unified, vendor-neutral query interface for logical entity retrieval, schema binding, and controlled execution.',
            nodeStatus: widget.nodeStatus,
            onNodeStatusTap: widget.onNodeStatusTap,
            primaryAction: OutlinedButton.icon(
              onPressed: widget.onBack,
              icon: const Icon(Icons.arrow_back, size: 14),
              label: const Text('Back to Dashboard'),
            ),
          ),
          const SizedBox(height: 16),

          // Info Banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: colorScheme.primary.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 18, color: colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'AltrQL provides a human-readable, vendor-neutral query language. Click "Execute Query" (⌘+Enter) to compile and run against the target source.',
                    style: TextStyle(fontSize: 12, color: colorScheme.onSurface),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: _showEngineRoadmapDialog,
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                  child: const Text('View Roadmap', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Controls Bar: Target Source Selector & Template Chips
          Container(
            padding: const EdgeInsets.all(14),
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
                    Icon(Icons.tune, size: 16, color: colorScheme.primary),
                    const SizedBox(width: 8),
                    Text(
                      'Query Context',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
                    ),
                    const Spacer(),
                    if (widget.sources.isNotEmpty) ...[
                      Text('Target Source:', style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
                      const SizedBox(width: 8),
                      DropdownButtonHideUnderline(
                        child: DropdownButton<SourceModel>(
                          value: _selectedSource,
                          isDense: true,
                          borderRadius: BorderRadius.circular(8),
                          items: widget.sources.map((src) {
                            return DropdownMenuItem<SourceModel>(
                              value: src,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(src.name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: colorScheme.surfaceContainerHighest,
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                    child: Text(src.type, style: const TextStyle(fontSize: 9)),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) {
                              setState(() => _selectedSource = val);
                            }
                          },
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 12),

                // Query Templates Chips
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text('Templates:', style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant)),
                    ..._templates.entries.map((entry) {
                      return ActionChip(
                        label: Text(entry.key, style: const TextStyle(fontSize: 11)),
                        avatar: const Icon(Icons.code, size: 12),
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        onPressed: () {
                          setState(() {
                            _queryController.text = entry.value;
                          });
                          _focusNode.requestFocus();
                        },
                      );
                    }),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // AltrQL Editor Card
          Container(
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainer,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
                    border: Border(
                      bottom: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.terminal_outlined, size: 16, color: colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        'AltrQL Editor',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.clear_all, size: 16),
                        tooltip: 'Reset Query',
                        visualDensity: VisualDensity.compact,
                        onPressed: () {
                          setState(() => _queryController.text = _defaultAltrQL);
                          _focusNode.requestFocus();
                        },
                      ),
                    ],
                  ),
                ),

                // Text Field
                Container(
                  height: 180,
                  padding: const EdgeInsets.all(14),
                  child: TextField(
                    controller: _queryController,
                    focusNode: _focusNode,
                    maxLines: null,
                    expands: true,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                      color: colorScheme.onSurface,
                      height: 1.4,
                    ),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),

                // Footer Action Bar
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainer,
                    borderRadius: const BorderRadius.vertical(bottom: Radius.circular(11)),
                    border: Border(
                      top: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                    ),
                  ),
                  child: Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      Text(
                        'Shortcuts: ⌘/Ctrl + Enter to Execute',
                        style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                      ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          OutlinedButton.icon(
                            onPressed: _isBusy ? null : _handleParse,
                            icon: _isParsing
                                ? const SizedBox(
                                    width: 12,
                                    height: 12,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.account_tree_outlined, size: 14),
                            label: Text(
                              _isParsing ? 'Parsing...' : 'Parse Query',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: (_isBusy || _selectedSource == null) ? null : _handleBind,
                            icon: _isBinding
                                ? const SizedBox(
                                    width: 12,
                                    height: 12,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.fact_check_outlined, size: 14),
                            label: Text(
                              _isBinding ? 'Binding...' : 'Bind Against Source',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                          FilledButton.icon(
                            onPressed: (_isBusy || _selectedSource == null) ? null : _handleExecute,
                            icon: _isExecuting
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.play_arrow_rounded, size: 16),
                            label: Text(
                              _isExecuting ? 'Executing...' : 'Execute Query',
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Output Panel: Multi-view switcher [Results, Physical Query, Bound IR, Canonical IR]
          _buildOutputPanel(context),
          const SizedBox(height: 16),

          // Status / Architecture Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.architecture, size: 18, color: colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        'AltrQL Architecture Overview',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'AltrQL provides a strongly-typed compiler pipeline: Lexer -> Parser (AltrQueryIR) -> Semantic Validator -> Schema Binder (BoundAltrQueryIR) -> Physical Lowerer (PhysicalQuery) -> Controlled Database Execution.',
                    style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant, height: 1.4),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed: _showEngineRoadmapDialog,
                        icon: const Icon(Icons.info_outline, size: 14),
                        label: const Text('Engine Roadmap Details', style: TextStyle(fontSize: 12)),
                        style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOutputPanel(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final hasResults = _columns.isNotEmpty || _rows.isNotEmpty || _metadata != null;
    final hasPhysicalQuery = _physicalQuery != null;
    final hasBoundIr = _boundIr != null;
    final hasCanonicalIr = _ir != null;

    if (hasResults || hasPhysicalQuery || hasBoundIr || hasCanonicalIr || _error != null) {
      final isSuccess = _error == null;

      // Available tabs
      final availableSegments = <ButtonSegment<int>>[];
      if (hasResults) {
        availableSegments.add(const ButtonSegment(value: 0, label: Text('Results', style: TextStyle(fontSize: 11))));
      }
      if (hasPhysicalQuery) {
        availableSegments.add(const ButtonSegment(value: 1, label: Text('Physical Query', style: TextStyle(fontSize: 11))));
      }
      if (hasBoundIr) {
        availableSegments.add(const ButtonSegment(value: 2, label: Text('Bound IR', style: TextStyle(fontSize: 11))));
      }
      if (hasCanonicalIr) {
        availableSegments.add(const ButtonSegment(value: 3, label: Text('Canonical IR', style: TextStyle(fontSize: 11))));
      }

      // Ensure active tab is valid
      if (availableSegments.isNotEmpty && !availableSegments.any((s) => s.value == _activeResultTab)) {
        _activeResultTab = availableSegments.first.value;
      }

      return Container(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSuccess ? Colors.green.withValues(alpha: 0.4) : colorScheme.error.withValues(alpha: 0.5),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Status Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: isSuccess ? Colors.green.withValues(alpha: 0.1) : colorScheme.errorContainer.withValues(alpha: 0.3),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
                border: Border(
                  bottom: BorderSide(
                    color: isSuccess ? Colors.green.withValues(alpha: 0.2) : colorScheme.error.withValues(alpha: 0.2),
                  ),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    isSuccess ? Icons.check_circle_outline : Icons.error_outline,
                    color: isSuccess ? Colors.green : colorScheme.error,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            isSuccess
                                ? (hasResults ? 'Query Executed Successfully' : (hasBoundIr ? 'Query Bound & Type Validated' : 'Query Parsed & Semantically Valid'))
                                : _getErrorTitle(_error?.type),
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: isSuccess ? Colors.green : colorScheme.error,
                            ),
                          ),
                        ),
                        if (_metadata != null) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.green.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '${_metadata!.executionTimeMs} ms · ${_metadata!.rowCount} rows',
                              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.green),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (availableSegments.length > 1) ...[
                    SegmentedButton<int>(
                      segments: availableSegments,
                      selected: {_activeResultTab},
                      onSelectionChanged: (set) {
                        setState(() => _activeResultTab = set.first);
                      },
                      style: const ButtonStyle(
                        visualDensity: VisualDensity.compact,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  if (isSuccess) _buildCopyButton(),
                ],
              ),
            ),

            // Error Diagnostics Banner if present
            if (_error != null) ...[
              Padding(
                padding: const EdgeInsets.all(14),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorScheme.errorContainer.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: colorScheme.error.withValues(alpha: 0.4)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: colorScheme.error,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              _error!.type,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onError,
                              ),
                            ),
                          ),
                          if (_error!.locationDescription.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Text(
                              _error!.locationDescription,
                              style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                            ),
                          ],
                          const Spacer(),
                          OutlinedButton.icon(
                            onPressed: () {
                              final errText = _error!.locationDescription.isNotEmpty
                                  ? '${_error!.type} at ${_error!.locationDescription}: ${_error!.message}'
                                  : '${_error!.type}: ${_error!.message}';
                              _copyToClipboard(errText, 'Error Diagnostics');
                            },
                            icon: const Icon(Icons.copy, size: 12),
                            label: const Text('Copy Error', style: TextStyle(fontSize: 11)),
                            style: OutlinedButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SelectableText(
                        _error!.message,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          color: colorScheme.error,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],

            // Active Tab Content View
            Padding(
              padding: const EdgeInsets.all(14),
              child: _buildActiveTabContent(context),
            ),
          ],
        ),
      );
    }

    // Default / Initial Placeholder
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.play_circle_outline, size: 22, color: colorScheme.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Interactive AST / IR Inspector',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
                ),
                const SizedBox(height: 2),
                Text(
                  'Click "Execute Query" or press ⌘+Enter to compile and run queries with tabular results and physical SQL inspection.',
                  style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _getErrorTitle(String? errorType) {
    if (errorType == null) return 'AltrQL Error';
    if (errorType == 'AltrQueryLexError') return 'AltrQL Lexer Error';
    if (errorType == 'AltrQueryParseError') return 'AltrQL Parse Error';
    if (errorType == 'AltrQuerySemanticError') return 'AltrQL Semantic Error';
    if (errorType == 'UnknownEntityError' ||
        errorType == 'UnknownFieldError' ||
        errorType == 'TypeCompatibilityError' ||
        errorType == 'AltrQuerySchemaError') {
      return 'AltrQL Schema Error';
    }
    if (errorType == 'UnsupportedDialectError' || errorType == 'QueryLoweringError') {
      return 'AltrQL Lowering Error';
    }
    return 'AltrQL Execution Error';
  }

  Widget _buildCopyButton() {
    String label = 'Copy';
    if (_activeResultTab == 0) {
      label = 'Copy Results';
    } else if (_activeResultTab == 1) {
      label = 'Copy SQL';
    } else if (_activeResultTab == 2) {
      label = 'Copy Bound IR';
    } else if (_activeResultTab == 3) {
      label = 'Copy IR';
    }

    return OutlinedButton.icon(
      onPressed: () {
        if (_activeResultTab == 0 && _rows.isNotEmpty) {
          final jsonString = const JsonEncoder.withIndent('  ').convert(_rows);
          _copyToClipboard(jsonString, 'Query Results JSON');
        } else if (_activeResultTab == 1 && _physicalQuery != null) {
          _copyToClipboard(_physicalQuery!.query, 'Physical SQL Query');
        } else if (_activeResultTab == 2 && _boundIr != null) {
          final jsonString = const JsonEncoder.withIndent('  ').convert(_boundIr);
          _copyToClipboard(jsonString, 'BoundAltrQueryIR JSON');
        } else if (_activeResultTab == 3 && _ir != null) {
          final jsonString = const JsonEncoder.withIndent('  ').convert(_ir);
          _copyToClipboard(jsonString, 'AltrQueryIR JSON');
        }
      },
      icon: const Icon(Icons.copy, size: 13),
      label: Text(label, style: const TextStyle(fontSize: 11)),
      style: OutlinedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 8),
      ),
    );
  }

  Widget _buildActiveTabContent(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    // 0: Results
    if (_activeResultTab == 0) {
      if (_columns.isEmpty && _rows.isEmpty) {
        return Container(
          padding: const EdgeInsets.all(24),
          alignment: Alignment.center,
          child: Text('No rows returned.', style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
        );
      }

      return Container(
        width: double.infinity,
        constraints: const BoxConstraints(maxHeight: 320),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.vertical,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(colorScheme.surfaceContainerHighest.withValues(alpha: 0.6)),
              dataRowColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.hovered)) {
                  return colorScheme.surfaceContainerHighest.withValues(alpha: 0.3);
                }
                return null;
              }),
              columns: _columns.map((col) {
                return DataColumn(
                  label: Text(
                    col,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                );
              }).toList(),
              rows: _rows.map((row) {
                return DataRow(
                  cells: _columns.map((col) {
                    final val = row[col];
                    return DataCell(
                      Text(
                        val == null ? 'NULL' : val.toString(),
                        style: TextStyle(
                          fontFamily: val == null ? 'sans-serif' : 'monospace',
                          fontSize: 12,
                          color: val == null ? colorScheme.outline : colorScheme.onSurface,
                        ),
                      ),
                    );
                  }).toList(),
                );
              }).toList(),
            ),
          ),
        ),
      );
    }

    // 1: Physical Query
    if (_activeResultTab == 1 && _physicalQuery != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${_physicalQuery!.dialect.toUpperCase()} Dialect',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: colorScheme.primary),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Source: ${_physicalQuery!.sourceName}',
                style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
            ),
            child: SelectableText(
              _physicalQuery!.query,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: colorScheme.onSurface,
                height: 1.4,
              ),
            ),
          ),
          if (_physicalQuery!.parameters.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              'Query Parameters:',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: List.generate(_physicalQuery!.parameters.length, (idx) {
                final param = _physicalQuery!.parameters[idx];
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                  ),
                  child: Text(
                    '\$${idx + 1} = ${jsonEncode(param)}',
                    style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: colorScheme.primary),
                  ),
                );
              }),
            ),
          ],
        ],
      );
    }

    // 2: Bound IR
    if (_activeResultTab == 2 && _boundIr != null) {
      final prettyJson = const JsonEncoder.withIndent('  ').convert(_boundIr);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'BoundAltrQueryIR (Schema-Resolved & Type-Validated AST):',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxHeight: 280),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
            ),
            child: SingleChildScrollView(
              child: SelectableText(
                prettyJson,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: colorScheme.onSurface,
                  height: 1.4,
                ),
              ),
            ),
          ),
        ],
      );
    }

    // 3: Canonical IR
    if (_activeResultTab == 3 && _ir != null) {
      final prettyJson = const JsonEncoder.withIndent('  ').convert(_ir);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'AltrQueryIR (Typed Abstract Syntax Tree):',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxHeight: 280),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
            ),
            child: SingleChildScrollView(
              child: SelectableText(
                prettyJson,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: colorScheme.onSurface,
                  height: 1.4,
                ),
              ),
            ),
          ),
        ],
      );
    }

    return const SizedBox.shrink();
  }
}
