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
  Map<String, dynamic>? _ir;
  AltrQLParseErrorModel? _error;

  static const String _defaultAltrQL = '''// AltrQL Query Definition
GET users (
    id,
    name,
    email,
    created_at
) WHERE {
    status = "ACTIVE"
};''';

  static const Map<String, String> _templates = {
    'Simple Read': '''// Logical read with field projection & filter
GET users (
    id,
    name,
    email
) WHERE {
    status = "ACTIVE"
};''',
    'Range & Sets': '''// Filter with range and value set expressions
GET users (
    id,
    name,
    age
) WHERE {
    id = {1, 2, 6..10},
    age = {>=18 & <=50}
};''',
    'Logical Conditions': '''// Filter with logical OR and implicit AND
GET users (
    id,
    name,
    role,
    status
) WHERE {
    age = {>18} OR role = "ADMIN",
    status = "ACTIVE"
};''',
    'Ranking & Pagination': '''// Ranking TOP n BY field with OFFSET
GET users (
    id,
    name,
    age
) WHERE {
    status = "ACTIVE"
} TOP 10 BY age OFFSET 20;''',
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

  Future<void> _handleParse() async {
    final queryText = _queryController.text.trim();
    if (queryText.isEmpty || _isParsing) return;

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
          _error = null;
        } else {
          _ir = null;
          _error = response.error ??
              AltrQLParseErrorModel(
                type: 'AltrQueryParseError',
                message: 'Failed to parse query.',
              );
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isParsing = false;
        _ir = null;
        _error = AltrQLParseErrorModel(
          type: 'RequestError',
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
                'The unified AltrQL parser, compiler, and query execution engine are currently scheduled for subsequent implementation phases (Phases B–E).',
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
                    _buildRoadmapItem('Phase B', 'Lock AltrQL Language Specification & Parser Core', true),
                    _buildRoadmapItem('Phase B.5', 'Interactive Parser Playground Integration', true),
                    _buildRoadmapItem('Phase C', 'Semantic Validation & Intermediate Representation (IR)', false),
                    _buildRoadmapItem('Phase D', 'PostgreSQL / Engine Lowering Compiler', false),
                    _buildRoadmapItem('Phase E', 'End-to-End AltrQL Query Execution Engine', false),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'To execute native SQL queries against connected databases, visit the Playground tab inside any Data Source detail page.',
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
              label: Text('Open ${_selectedSource!.name} Playground'),
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
        const SingleActivator(LogicalKeyboardKey.enter, meta: true): _handleParse,
        const SingleActivator(LogicalKeyboardKey.enter, control: true): _handleParse,
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageHeader(
            title: 'AltrQL Console',
            description: 'Unified, readable, vendor-neutral query interface for logical entity retrieval and filtering.',
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
                    'AltrQL provides a human-readable, vendor-neutral query language. Click "Parse Query" (⌘+Enter) to tokenize and parse queries into a typed AltrQueryIR AST.',
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
                  height: 200,
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
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Shortcuts: ⌘/Ctrl + Enter to Parse',
                        style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                      ),
                      FilledButton.icon(
                        onPressed: _isParsing ? null : _handleParse,
                        icon: _isParsing
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.account_tree_outlined, size: 16),
                        label: Text(
                          _isParsing ? 'Parsing...' : 'Parse Query',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Output Panel: Success (IR Viewer) OR Error (Diagnostics) OR Initial Placeholder
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
                    'AltrQL provides a readable, logical query model for entity retrieval, projection, and expressive filtering without vendor lock-in. In Phase B & B.5, the parser and intermediate representation (IR) are fully integrated for interactive inspection.',
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

    if (_ir != null) {
      final prettyJson = const JsonEncoder.withIndent('  ').convert(_ir);
      return Container(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.green.withValues(alpha: 0.4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Success Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.1),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
                border: Border(
                  bottom: BorderSide(color: Colors.green.withValues(alpha: 0.2)),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_outline, color: Colors.green, size: 18),
                  const SizedBox(width: 8),
                  const Text(
                    'Query Parsed Successfully',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.green),
                  ),
                  const Spacer(),
                  OutlinedButton.icon(
                    onPressed: () => _copyToClipboard(prettyJson, 'AltrQueryIR JSON'),
                    icon: const Icon(Icons.copy, size: 13),
                    label: const Text('Copy IR', style: TextStyle(fontSize: 11)),
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                  ),
                ],
              ),
            ),

            // IR Title & Monospace Viewer
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'AltrQueryIR (Typed Abstract Syntax Tree):',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurfaceVariant,
                    ),
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
              ),
            ),
          ],
        ),
      );
    }

    if (_error != null) {
      final errorText = '${_error!.type}: ${_error!.message}\n${_error!.locationDescription}'.trim();
      return Container(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colorScheme.error.withValues(alpha: 0.5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Error Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: colorScheme.errorContainer.withValues(alpha: 0.3),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
                border: Border(
                  bottom: BorderSide(color: colorScheme.error.withValues(alpha: 0.2)),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline, color: colorScheme.error, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'AltrQL Parse Error',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: colorScheme.error),
                  ),
                  const Spacer(),
                  OutlinedButton.icon(
                    onPressed: () => _copyToClipboard(errorText, 'Error Diagnostics'),
                    icon: const Icon(Icons.copy, size: 13),
                    label: const Text('Copy Error', style: TextStyle(fontSize: 11)),
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                  ),
                ],
              ),
            ),

            // Error Diagnostics Content
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: colorScheme.errorContainer,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          _error!.type,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onErrorContainer,
                          ),
                        ),
                      ),
                      if (_error!.locationDescription.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            _error!.locationDescription,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
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
                      _error!.message,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: colorScheme.error,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
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
            child: Icon(Icons.data_object, size: 22, color: colorScheme.primary),
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
                  'Click "Parse Query" or press ⌘+Enter to tokenize and parse the query into a deterministic AltrQueryIR AST.',
                  style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
