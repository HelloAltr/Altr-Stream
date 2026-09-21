import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/hugeicons.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/models.dart';
import '../widgets/command_outcome_panel.dart';
import '../widgets/destructive_query_dialog.dart';
import '../widgets/query_editor.dart';
import '../widgets/query_error_panel.dart';
import '../widgets/query_metadata_banner.dart';
import '../widgets/query_result_table.dart';
import '../widgets/schema_explorer.dart';

class SourcePlaygroundView extends StatefulWidget {
  final SourceModel source;
  final ApiClient apiClient;
  final SourceSchemaModel? schema;
  final VoidCallback? onRefreshSchema;

  const SourcePlaygroundView({
    super.key,
    required this.source,
    required this.apiClient,
    this.schema,
    this.onRefreshSchema,
  });

  @override
  State<SourcePlaygroundView> createState() => _SourcePlaygroundViewState();
}

class _SourcePlaygroundViewState extends State<SourcePlaygroundView> {
  late TextEditingController _queryController;
  late FocusNode _focusNode;
  SourceSchemaModel? _schema;
  bool _isLoadingSchema = false;
  String? _schemaErrorMessage;
  bool _isExecuting = false;
  QueryExecuteResponseModel? _response;
  String? _errorMessage;
  bool _isTabletSchemaOpen = false;
  String _mongoQueryMode = 'shell'; // 'shell' (default) or 'physical'

  @override
  void initState() {
    super.initState();
    _schema = widget.schema;

    _queryController = TextEditingController();
    _focusNode = FocusNode();
    _queryController.addListener(_onQueryChanged);

    if (_schema == null) {
      _loadSchema();
    }
  }

  @override
  void didUpdateWidget(covariant SourcePlaygroundView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.schema != null && widget.schema != _schema) {
      setState(() {
        _schema = widget.schema;
      });
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

  Future<void> _loadSchema({bool forceDiscover = false}) async {
    setState(() {
      _isLoadingSchema = true;
      _schemaErrorMessage = null;
    });

    try {
      SourceSchemaModel? loadedSchema;
      if (forceDiscover) {
        loadedSchema = await widget.apiClient.discoverSchema(widget.source.id);
      } else {
        loadedSchema = await widget.apiClient.getLatestSchema(widget.source.id);
        loadedSchema ??= await widget.apiClient.discoverSchema(widget.source.id);
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

  Future<void> _handleMongoQueryModeChanged(String newMode) async {
    if (newMode == _mongoQueryMode) return;

    final currentText = _queryController.text.trim();
    if (currentText.isEmpty) {
      setState(() {
        _mongoQueryMode = newMode;
      });
      _focusNode.requestFocus();
      return;
    }

    final currentModeName = _mongoQueryMode == 'shell' ? 'MongoDB Shell' : 'Physical Command';
    final newModeName = newMode == 'shell' ? 'MongoDB Shell' : 'Physical Command';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Switch Query Mode?'),
        content: Text(
          'The current query uses $currentModeName syntax.\nSwitching modes will clear the query editor for $newModeName mode.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Switch'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      setState(() {
        _mongoQueryMode = newMode;
        _queryController.clear();
        _response = null;
        _errorMessage = null;
      });
      _focusNode.requestFocus();
    }
  }

  void _insertTableTemplate(EntitySchemaModel entity) {
    final isMongo = widget.source.type.toUpperCase() == 'MONGODB';
    String template;
    if (isMongo) {
      if (_mongoQueryMode == 'physical') {
        template = '{\n  "collection": "${entity.name}",\n  "filter": {}\n}\n';
      } else {
        template = 'db.${entity.name}.find().pretty();\n';
      }
    } else {
      template = 'SELECT * FROM ${entity.name} LIMIT 100;\n';
    }

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
    if (_isExecuting || _queryController.text.trim().isEmpty) return;

    final queryText = _queryController.text.trim();
    final isMongo = widget.source.type.toUpperCase() == 'MONGODB';

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
        sourceId: widget.source.id,
        query: queryText,
        mode: isMongo ? _mongoQueryMode : null,
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

  void _copyQueryResults() {
    if (_response == null) return;
    if (_response!.isCommandOutcome) {
      final details = {
        'source': widget.source.name,
        'status': _response!.metadata.message ?? 'Command executed successfully',
        'affectedRows': _response!.metadata.affectedRows,
        'executionTimeMs': _response!.metadata.executionTimeMs,
      };
      final jsonString = const JsonEncoder.withIndent('  ').convert(details);
      _copyToClipboard(jsonString, 'Command outcome details');
    } else {
      final jsonString = const JsonEncoder.withIndent('  ').convert(_response!.rows);
      _copyToClipboard(jsonString, 'Query results JSON');
    }
  }

  void _copyQueryError() {
    if (_errorMessage == null) return;
    _copyToClipboard(_errorMessage!, 'Error message');
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
                  selectedSource: widget.source,
                  schema: _schema,
                  isLoading: _isLoadingSchema,
                  errorMessage: _schemaErrorMessage,
                  onRefreshSchema: () => _loadSchema(forceDiscover: true),
                  onSelectTable: (entity) {
                    Navigator.of(ctx).pop();
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 1024;
        final isTablet = constraints.maxWidth >= 700 && constraints.maxWidth < 1024;

        if (isDesktop) {
          return _buildDesktopLayout(context);
        } else if (isTablet) {
          return _buildTabletLayout(context);
        } else {
          return _buildMobileLayout(context);
        }
      },
    );
  }

  Widget _buildDesktopLayout(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final canExecute = _queryController.text.trim().isNotEmpty && !_isExecuting;
    final isMongo = widget.source.type.toUpperCase() == 'MONGODB';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Left Column: Schema Explorer (width 280)
        SizedBox(
          width: 280,
          child: SchemaExplorer(
            selectedSource: widget.source,
            schema: _schema,
            isLoading: _isLoadingSchema,
            errorMessage: _schemaErrorMessage,
            onRefreshSchema: () => _loadSchema(forceDiscover: true),
            onSelectTable: _insertTableTemplate,
            onSelectColumn: _insertColumnName,
          ),
        ),
        const SizedBox(width: 16),

        // Right Column: Editor & Results
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Query Editor Panel
              SizedBox(
                height: 280,
                child: QueryEditor(
                  controller: _queryController,
                  focusNode: _focusNode,
                  selectedSource: widget.source,
                  mongoQueryMode: isMongo ? _mongoQueryMode : null,
                  onMongoQueryModeChanged: _handleMongoQueryModeChanged,
                  isExecuting: _isExecuting,
                  canExecute: canExecute,
                  onExecute: _executeQuery,
                  onClear: _clearEditor,
                ),
              ),
              const SizedBox(height: 14),

              // Execution Feedback & Results
              Expanded(
                child: _buildResultsSection(context, colorScheme),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTabletLayout(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final canExecute = _queryController.text.trim().isNotEmpty && !_isExecuting;
    final isMongo = widget.source.type.toUpperCase() == 'MONGODB';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Schema Toggle Row
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            OutlinedButton.icon(
              onPressed: () {
                setState(() {
                  _isTabletSchemaOpen = !_isTabletSchemaOpen;
                });
              },
              icon: HugeIcon(
                icon: _isTabletSchemaOpen ? HugeIcons.strokeRoundedArrowUp01 : HugeIcons.strokeRoundedStructure01,
                size: 14,
              ),
              label: Text(_isTabletSchemaOpen ? 'Hide Schema Explorer' : 'Show Schema Explorer'),
              style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
            ),
            if (_schema != null) ...[
              Builder(
                builder: (context) {
                  final isMongoSource = widget.source.type.toUpperCase() == 'MONGODB';
                  final count = _schema!.entityCount;
                  final entityTerm = isMongoSource
                      ? (count == 1 ? 'collection' : 'collections')
                      : (count == 1 ? 'table' : 'tables');
                  return Text(
                    '$count $entityTerm available',
                    style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                  );
                },
              ),
            ],
          ],
        ),
        const SizedBox(height: 10),

        if (_isTabletSchemaOpen) ...[
          SizedBox(
            height: 220,
            child: SchemaExplorer(
              selectedSource: widget.source,
              schema: _schema,
              isLoading: _isLoadingSchema,
              errorMessage: _schemaErrorMessage,
              onRefreshSchema: () => _loadSchema(forceDiscover: true),
              onSelectTable: _insertTableTemplate,
              onSelectColumn: _insertColumnName,
            ),
          ),
          const SizedBox(height: 12),
        ],

        // Editor
        SizedBox(
          height: 240,
          child: QueryEditor(
            controller: _queryController,
            focusNode: _focusNode,
            selectedSource: widget.source,
            mongoQueryMode: isMongo ? _mongoQueryMode : null,
            onMongoQueryModeChanged: _handleMongoQueryModeChanged,
            isExecuting: _isExecuting,
            canExecute: canExecute,
            onExecute: _executeQuery,
            onClear: _clearEditor,
          ),
        ),
        const SizedBox(height: 14),

        // Results
        Expanded(
          child: _buildResultsSection(context, colorScheme),
        ),
      ],
    );
  }

  Widget _buildMobileLayout(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final canExecute = _queryController.text.trim().isNotEmpty && !_isExecuting;
    final isMongo = widget.source.type.toUpperCase() == 'MONGODB';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Quick Schema Sheet Trigger
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            OutlinedButton.icon(
              onPressed: () => _showMobileSchemaBottomSheet(context),
              icon: const HugeIcon(icon: HugeIcons.strokeRoundedStructure01, size: 14),
              label: Text(isMongo ? 'Browse Collections' : 'Browse Schema Tables'),
              style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
            ),
            if (_schema != null) ...[
              Builder(
                builder: (context) {
                  final count = _schema!.entityCount;
                  final entityTerm = isMongo
                      ? (count == 1 ? 'collection' : 'collections')
                      : (count == 1 ? 'table' : 'tables');
                  return Text(
                    '$count $entityTerm',
                    style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                  );
                },
              ),
            ],
          ],
        ),
        const SizedBox(height: 10),

        SizedBox(
          height: 200,
          child: QueryEditor(
            controller: _queryController,
            focusNode: _focusNode,
            selectedSource: widget.source,
            mongoQueryMode: isMongo ? _mongoQueryMode : null,
            onMongoQueryModeChanged: _handleMongoQueryModeChanged,
            isExecuting: _isExecuting,
            canExecute: canExecute,
            onExecute: _executeQuery,
            onClear: _clearEditor,
          ),
        ),
        const SizedBox(height: 12),

        Expanded(
          child: _buildResultsSection(context, colorScheme),
        ),
      ],
    );
  }

  Widget _buildResultsSection(BuildContext context, ColorScheme colorScheme) {
    if (_isExecuting) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: colorScheme.primary),
            const SizedBox(height: 16),
            Text(
              'Executing query against ${widget.source.name}...',
              style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return SingleChildScrollView(
        child: QueryErrorPanel(
          errorMessage: _errorMessage!,
          onDismiss: () => setState(() => _errorMessage = null),
          onCopy: _copyQueryError,
        ),
      );
    }

    if (_response != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          QueryMetadataBanner(
            rowCount: _response!.metadata.rowCount,
            executionTimeMs: _response!.metadata.executionTimeMs,
            sourceName: widget.source.name,
            onCopyResults: _copyQueryResults,
          ),
          const SizedBox(height: 10),
          Expanded(
            child: _response!.isCommandOutcome
                ? SingleChildScrollView(
                    child: CommandOutcomePanel(
                      metadata: _response!.metadata,
                      sourceName: widget.source.name,
                      onCopy: _copyQueryResults,
                    ),
                  )
                : QueryResultTable(
                    columns: _response!.columns,
                    rows: _response!.rows,
                  ),
          ),
        ],
      );
    }

    // Idle Placeholder
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              HugeIcon(
                icon: HugeIcons.strokeRoundedCommandLine,
                size: 36,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
              ),
              const SizedBox(height: 12),
              Text(
                'Ready to Execute',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Press ⌘+Enter or click Run Query to test queries against ${widget.source.name}.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
