import 'dart:convert';
import 'package:flutter/material.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/models.dart';
import '../models/api_endpoint_model.dart';
import 'api_response_viewer.dart';

class ApiEndpointDetailPanel extends StatefulWidget {
  final ApiEndpoint endpoint;
  final ApiClient apiClient;
  final List<SourceModel> sources;
  final List<LogicalModelModel> logicalModels;
  final List<SourceMappingModel> sourceMappings;
  final VoidCallback? onOpenSwagger;

  const ApiEndpointDetailPanel({
    super.key,
    required this.endpoint,
    required this.apiClient,
    this.sources = const [],
    this.logicalModels = const [],
    this.sourceMappings = const [],
    this.onOpenSwagger,
  });

  @override
  State<ApiEndpointDetailPanel> createState() => _ApiEndpointDetailPanelState();
}

class _ApiEndpointDetailPanelState extends State<ApiEndpointDetailPanel> {
  final Map<String, TextEditingController> _paramControllers = {};
  final Map<String, String?> _selectedParamValues = {};
  late TextEditingController _bodyController;
  bool _isExecuting = false;
  ApiExecutionResult? _lastResult;
  String? _jsonFormatError;

  // Selected values for generic contextual helpers
  String? _selectedBodyModelId;
  String? _selectedBodySourceId;
  String? _selectedBodyMappingId;

  // Align suggestion contextual helper state
  String? _selectedAlignModelId;
  String? _selectedAlignEntityId;
  String? _selectedAlignFieldId;
  String? _selectedAlignSourceId;
  String? _selectedAlignPhysicalEntityName;
  String? _selectedAlignPhysicalFieldName;
  late TextEditingController _alignNamespaceController;
  late TextEditingController _alignConfidenceController;
  late TextEditingController _alignPhysicalEntityInputController;
  late TextEditingController _alignPhysicalFieldInputController;
  SourceSchemaModel? _alignDiscoveredSchema;
  bool _isLoadingDiscoveredSchema = false;

  @override
  void initState() {
    super.initState();
    _alignNamespaceController = TextEditingController();
    _alignConfidenceController = TextEditingController(text: '0.95');
    _alignPhysicalEntityInputController = TextEditingController();
    _alignPhysicalFieldInputController = TextEditingController();
    _initControllers();
  }

  @override
  void didUpdateWidget(covariant ApiEndpointDetailPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.endpoint.path != widget.endpoint.path ||
        oldWidget.endpoint.method != widget.endpoint.method) {
      _disposeParamControllers();
      _initControllers();
      setState(() {
        _lastResult = null;
        _jsonFormatError = null;
      });
    }
  }

  void _initControllers() {
    // Parameters controllers
    for (final p in widget.endpoint.parameters) {
      String initialValue = '';
      if (p.defaultValue != null) {
        initialValue = p.defaultValue.toString();
      }
      _paramControllers[p.name] = TextEditingController(text: initialValue);
      _selectedParamValues[p.name] = null;
    }

    // Request body controller
    final sampleBody = widget.endpoint.requestBody?.sampleJson ?? '';
    _bodyController = TextEditingController(text: sampleBody);

    // Initialize Align helper selections from loaded models & sources
    if (widget.logicalModels.isNotEmpty) {
      _selectedAlignModelId = widget.logicalModels.first.id;
      final firstModel = widget.logicalModels.first;
      if (firstModel.entities.isNotEmpty) {
        _selectedAlignEntityId = firstModel.entities.first.id;
        if (firstModel.entities.first.fields.isNotEmpty) {
          _selectedAlignFieldId = firstModel.entities.first.fields.first.id;
        }
      }
    }

    if (widget.sources.isNotEmpty) {
      _selectedAlignSourceId = widget.sources.first.id;
      _loadDiscoveredSchemaForSource(_selectedAlignSourceId!);
    }
  }

  void _disposeParamControllers() {
    for (final ctrl in _paramControllers.values) {
      ctrl.dispose();
    }
    _paramControllers.clear();
    _selectedParamValues.clear();
    _bodyController.dispose();
  }

  @override
  void dispose() {
    _disposeParamControllers();
    _alignNamespaceController.dispose();
    _alignConfidenceController.dispose();
    _alignPhysicalEntityInputController.dispose();
    _alignPhysicalFieldInputController.dispose();
    super.dispose();
  }

  Future<void> _loadDiscoveredSchemaForSource(String sourceId) async {
    setState(() {
      _isLoadingDiscoveredSchema = true;
    });
    try {
      final schema = await widget.apiClient.getLatestSchema(sourceId);
      if (mounted) {
        final source = widget.sources.where((s) => s.id == sourceId).firstOrNull;
        String defaultNamespace = '';
        if (source != null && source.type.toUpperCase() == 'MONGODB' && source.databaseName != null && source.databaseName!.isNotEmpty) {
          defaultNamespace = source.databaseName!;
        } else if (schema != null && schema.entities.isNotEmpty && schema.entities.first.namespace.isNotEmpty) {
          defaultNamespace = schema.entities.first.namespace;
        } else if (source != null && source.databaseName != null && source.databaseName!.isNotEmpty) {
          defaultNamespace = source.databaseName!;
        }

        setState(() {
          _alignDiscoveredSchema = schema;
          _isLoadingDiscoveredSchema = false;
          if (_alignNamespaceController.text.isEmpty && defaultNamespace.isNotEmpty) {
            _alignNamespaceController.text = defaultNamespace;
          }
          if (schema != null && schema.entities.isNotEmpty) {
            _selectedAlignPhysicalEntityName = schema.entities.first.name;
            _alignPhysicalEntityInputController.text = schema.entities.first.name;
            if (schema.entities.first.fields.isNotEmpty) {
              _selectedAlignPhysicalFieldName = schema.entities.first.fields.first.name;
              _alignPhysicalFieldInputController.text = schema.entities.first.fields.first.name;
            }
          }
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoadingDiscoveredSchema = false;
        });
      }
    }
  }

  void _applyAlignSuggestionToBody() {
    final modelId = _selectedAlignModelId ?? (widget.logicalModels.isNotEmpty ? widget.logicalModels.first.id : '');
    final sourceId = _selectedAlignSourceId ?? (widget.sources.isNotEmpty ? widget.sources.first.id : '');

    final model = widget.logicalModels.where((m) => m.id == modelId).firstOrNull;
    final entity = model?.entities.where((e) => e.id == _selectedAlignEntityId).firstOrNull ?? model?.entities.firstOrNull;
    final field = entity?.fields.where((f) => f.id == _selectedAlignFieldId).firstOrNull ?? entity?.fields.firstOrNull;

    final physicalEntityName = _selectedAlignPhysicalEntityName?.trim().isNotEmpty == true
        ? _selectedAlignPhysicalEntityName!.trim()
        : (_alignPhysicalEntityInputController.text.trim().isNotEmpty
            ? _alignPhysicalEntityInputController.text.trim()
            : (entity?.name ?? ''));

    final physicalFieldName = _selectedAlignPhysicalFieldName?.trim().isNotEmpty == true
        ? _selectedAlignPhysicalFieldName!.trim()
        : (_alignPhysicalFieldInputController.text.trim().isNotEmpty
            ? _alignPhysicalFieldInputController.text.trim()
            : (field?.name ?? ''));

    final namespace = _alignNamespaceController.text.trim();

    double? confidence;
    final confText = _alignConfidenceController.text.trim();
    if (confText.isNotEmpty) {
      confidence = double.tryParse(confText);
    }

    final entityMapping = {
      'logical_entity_id': entity?.id ?? '',
      'logical_entity_name': entity?.name ?? '',
      'physical_entity_name': physicalEntityName,
      'physical_namespace': namespace,
      'field_mappings': [
        {
          'logical_field_id': field?.id ?? '',
          'logical_field_name': field?.name ?? '',
          'physical_field_name': physicalFieldName,
          'transformation_rule': null,
          'confidence': confidence,
        }
      ],
      'confidence': confidence,
    };

    final payload = {
      'source_id': sourceId,
      'version': '1.0.0',
      'entity_mappings': [entityMapping],
      'metadata': {},
    };

    const encoder = JsonEncoder.withIndent('  ');
    setState(() {
      _bodyController.text = encoder.convert(payload);
      _jsonFormatError = null;
      _selectedBodySourceId = sourceId;
      _selectedBodyModelId = modelId;
      if (_paramControllers.containsKey('model_id') && modelId.isNotEmpty) {
        _paramControllers['model_id']!.text = modelId;
        _selectedParamValues['model_id'] = modelId;
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Align suggestion template applied to Request Body.'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _formatJsonBody() {
    final text = _bodyController.text.trim();
    if (text.isEmpty) return;
    try {
      final decoded = jsonDecode(text);
      const encoder = JsonEncoder.withIndent('  ');
      final formatted = encoder.convert(decoded);
      setState(() {
        _bodyController.text = formatted;
        _jsonFormatError = null;
      });
    } catch (e) {
      setState(() {
        _jsonFormatError = 'Invalid JSON: $e';
      });
    }
  }

  void _resetJsonBody() {
    final sample = widget.endpoint.requestBody?.sampleJson ?? '{}';
    setState(() {
      _bodyController.text = sample;
      _jsonFormatError = null;
    });
  }

  Future<void> _executeRequest() async {
    // Collect path parameters
    final Map<String, String> pathParams = {};
    for (final p in widget.endpoint.pathParameters) {
      final val = _paramControllers[p.name]?.text.trim() ?? '';
      if (p.required && val.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Missing required path parameter: ${p.name}'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
        return;
      }
      if (val.isNotEmpty) {
        pathParams[p.name] = val;
      }
    }

    // Collect query parameters
    final Map<String, dynamic> queryParams = {};
    for (final p in widget.endpoint.queryParameters) {
      final val = _paramControllers[p.name]?.text.trim() ?? '';
      if (val.isNotEmpty) {
        queryParams[p.name] = val;
      }
    }

    // Parse request body
    dynamic requestBodyData;
    if (widget.endpoint.hasRequestBody) {
      final bodyText = _bodyController.text.trim();
      if (bodyText.isNotEmpty) {
        try {
          requestBodyData = jsonDecode(bodyText);
        } catch (_) {
          requestBodyData = bodyText;
        }
      }
    }

    // Required fields validation for AltrQL endpoints
    if (widget.endpoint.path.contains('/altrql/')) {
      if (requestBodyData is Map) {
        final q = requestBodyData['query']?.toString().trim() ?? '';
        final sid = requestBodyData['source_id']?.toString().trim() ?? '';
        if (q.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Please enter an AltrQL query in the request body.'),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
          return;
        }
        if (sid.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Please select or enter a valid source_id in the request body.'),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
          return;
        }
      }
    }

    setState(() {
      _isExecuting = true;
      _jsonFormatError = null;
    });

    try {
      final result = await widget.apiClient.executeRawRequest(
        method: widget.endpoint.method,
        path: widget.endpoint.path,
        pathParams: pathParams.isEmpty ? null : pathParams,
        queryParams: queryParams.isEmpty ? null : queryParams,
        body: requestBodyData,
      );

      if (mounted) {
        setState(() {
          _lastResult = result;
          _isExecuting = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _lastResult = ApiExecutionResult(
            statusCode: 0,
            statusText: 'Client Exception',
            duration: Duration.zero,
            requestMethod: widget.endpoint.method,
            requestUrl: widget.endpoint.path,
            requestHeaders: const {},
            requestBody: _bodyController.text,
            responseHeaders: const {},
            responseBody: null,
            errorMessage: e.toString(),
            isSuccess: false,
          );
          _isExecuting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final ep = widget.endpoint;
    final methodColor = _getMethodColor(ep.method, context);

    return Column(
      key: Key('api_endpoint_detail_${ep.method}_${ep.path}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header Card
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Method + Path Row
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: methodColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: methodColor.withValues(alpha: 0.5)),
                    ),
                    child: Text(
                      ep.method,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: methodColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SelectableText(
                      ep.path,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ),
                  if (widget.onOpenSwagger != null)
                    IconButton(
                      icon: const Icon(Icons.open_in_new, size: 18),
                      tooltip: 'View in Swagger UI',
                      onPressed: widget.onOpenSwagger,
                    ),
                ],
              ),
              if (ep.summary.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  ep.summary,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
              ],
              if (ep.description.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  ep.description,
                  style: TextStyle(
                    fontSize: 13,
                    color: colorScheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ],
              const SizedBox(height: 12),

              // Tags Chips
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: ep.tags.map((t) {
                  return Chip(
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                    label: Text(t, style: const TextStyle(fontSize: 11)),
                    backgroundColor: colorScheme.surfaceContainerHighest,
                    side: BorderSide.none,
                  );
                }).toList(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Parameters Section
        if (ep.parameters.isNotEmpty) ...[
          _buildParametersSection(context),
          const SizedBox(height: 20),
        ],

        // Request Body Section
        if (ep.hasRequestBody) ...[
          _buildRequestBodySection(context),
          const SizedBox(height: 20),
        ],

        // Execution Button
        SizedBox(
          width: double.infinity,
          height: 46,
          child: ElevatedButton.icon(
            key: const Key('api_execute_button'),
            style: ElevatedButton.styleFrom(
              backgroundColor: colorScheme.primary,
              foregroundColor: colorScheme.onPrimary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 2,
            ),
            icon: _isExecuting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.play_arrow, size: 20),
            label: Text(
              _isExecuting ? 'Executing Request...' : 'Execute Request',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            onPressed: _isExecuting ? null : _executeRequest,
          ),
        ),
        const SizedBox(height: 24),

        // Response Viewer Section
        if (_lastResult != null) ...[
          Text(
            'Execution Response',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 10),
          ApiResponseViewer(
            result: _lastResult!,
            onClear: () => setState(() => _lastResult = null),
          ),
          const SizedBox(height: 24),
        ],
      ],
    );
  }

  // --- PARAMETERS WIDGET BUILDERS ---

  Widget _buildParametersSection(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final ep = widget.endpoint;

    return Container(
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
            children: [
              Icon(Icons.tune, size: 16, color: colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                'Parameters',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Path Parameters
          if (ep.pathParameters.isNotEmpty) ...[
            Text(
              'PATH PARAMETERS',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(height: 8),
            ...ep.pathParameters.map((p) => _buildParameterInputRow(context, p)),
            const SizedBox(height: 12),
          ],

          // Query Parameters
          if (ep.queryParameters.isNotEmpty) ...[
            Text(
              'QUERY PARAMETERS',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            ...ep.queryParameters.map((p) => _buildParameterInputRow(context, p)),
          ],
        ],
      ),
    );
  }

  Widget _buildParameterInputRow(BuildContext context, ApiParameter param) {
    final colorScheme = Theme.of(context).colorScheme;
    final controller = _paramControllers[param.name];

    // Check if Altr Stream aware helpers apply (model_id, source_id, or mapping_id)
    final isModelIdParam = param.name == 'model_id' || param.name == 'modelId' || param.name == 'logical_model_id';
    final isSourceIdParam = param.name == 'source_id' || param.name == 'sourceId';
    final isMappingIdParam = param.name == 'mapping_id' || param.name == 'mappingId';

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                param.name,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  param.schemaType,
                  style: TextStyle(fontSize: 10, color: colorScheme.onSurfaceVariant),
                ),
              ),
              if (param.required) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: colorScheme.error.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'required',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.error,
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (param.description.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              param.description,
              style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
            ),
          ],
          const SizedBox(height: 6),

          // Altr Stream Contextual Helper Dropdown for Logical Model
          if (isModelIdParam && widget.logicalModels.isNotEmpty) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: colorScheme.primary.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.schema, size: 14, color: colorScheme.primary),
                  const SizedBox(width: 8),
                  Text('Logical Model:', style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        key: const Key('api_param_model_selector'),
                        isDense: true,
                        value: widget.logicalModels.any((m) => m.id == _selectedParamValues[param.name])
                            ? _selectedParamValues[param.name]
                            : (widget.logicalModels.any((m) => m.id == controller?.text) ? controller?.text : null),
                        hint: const Text('Select Logical Model...', style: TextStyle(fontSize: 11)),
                        items: widget.logicalModels.map((m) {
                          return DropdownMenuItem<String>(
                            value: m.id,
                            child: Text(
                              '${m.name} (${m.id.substring(0, m.id.length > 8 ? 8 : m.id.length)}...)',
                              style: const TextStyle(fontSize: 11),
                            ),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null && controller != null) {
                            setState(() {
                              _selectedParamValues[param.name] = val;
                              controller.text = val;
                              _selectedAlignModelId = val;
                            });
                          }
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Altr Stream Contextual Helper Dropdown for Physical Source
          if (isSourceIdParam && widget.sources.isNotEmpty) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: colorScheme.primary.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.dns, size: 14, color: colorScheme.primary),
                  const SizedBox(width: 8),
                  Text('Physical Source:', style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        key: const Key('api_param_source_selector'),
                        isDense: true,
                        value: widget.sources.any((s) => s.id == _selectedParamValues[param.name])
                            ? _selectedParamValues[param.name]
                            : (widget.sources.any((s) => s.id == controller?.text) ? controller?.text : null),
                        hint: const Text('Select Physical Source...', style: TextStyle(fontSize: 11)),
                        items: widget.sources.map((s) {
                          return DropdownMenuItem<String>(
                            value: s.id,
                            child: Text(
                              '${s.name} (${s.type})',
                              style: const TextStyle(fontSize: 11),
                            ),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null && controller != null) {
                            setState(() {
                              _selectedParamValues[param.name] = val;
                              controller.text = val;
                              _selectedAlignSourceId = val;
                            });
                            _loadDiscoveredSchemaForSource(val);
                          }
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Altr Stream Contextual Helper Dropdown for Source Mapping
          if (isMappingIdParam && widget.sourceMappings.isNotEmpty) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: colorScheme.primary.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.compare_arrows, size: 14, color: colorScheme.primary),
                  const SizedBox(width: 8),
                  Text('Source Mapping:', style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        key: const Key('api_param_mapping_selector'),
                        isDense: true,
                        value: widget.sourceMappings.any((m) => m.id == _selectedParamValues[param.name])
                            ? _selectedParamValues[param.name]
                            : (widget.sourceMappings.any((m) => m.id == controller?.text) ? controller?.text : null),
                        hint: const Text('Select Source Mapping...', style: TextStyle(fontSize: 11)),
                        items: widget.sourceMappings.map((m) {
                          final shortId = m.id.substring(0, m.id.length > 8 ? 8 : m.id.length);
                          return DropdownMenuItem<String>(
                            value: m.id,
                            child: Text(
                              'Mapping $shortId... (${m.status})',
                              style: const TextStyle(fontSize: 11),
                            ),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null && controller != null) {
                            setState(() {
                              _selectedParamValues[param.name] = val;
                              controller.text = val;
                            });
                          }
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Text Field for parameter input
          TextField(
            key: Key('api_param_input_${param.name}'),
            controller: controller,
            decoration: InputDecoration(
              hintText: 'Enter ${param.name}...',
              hintStyle: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6)),
              filled: true,
              fillColor: colorScheme.surface,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: colorScheme.primary),
              ),
            ),
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
          ),
        ],
      ),
    );
  }

  void _updateBodyJsonField(List<String> targetKeys, String value) {
    try {
      final text = _bodyController.text.trim();
      Map<String, dynamic> jsonMap;
      if (text.isNotEmpty) {
        final decoded = jsonDecode(text);
        if (decoded is Map) {
          jsonMap = Map<String, dynamic>.from(decoded);
        } else {
          jsonMap = {};
        }
      } else {
        jsonMap = {};
      }

      String keyToUpdate = targetKeys.first;
      for (final k in targetKeys) {
        if (jsonMap.containsKey(k)) {
          keyToUpdate = k;
          break;
        }
      }

      jsonMap[keyToUpdate] = value;
      const encoder = JsonEncoder.withIndent('  ');
      setState(() {
        _bodyController.text = encoder.convert(jsonMap);
        _jsonFormatError = null;
        if (targetKeys.contains('logical_model_id') || targetKeys.contains('model_id')) {
          _selectedBodyModelId = value;
          _selectedAlignModelId = value;
        }
        if (targetKeys.contains('source_id')) {
          _selectedBodySourceId = value;
          _selectedAlignSourceId = value;
          _loadDiscoveredSchemaForSource(value);
        }
        if (targetKeys.contains('mapping_id')) {
          _selectedBodyMappingId = value;
        }
      });
    } catch (_) {
      // Non-blocking fallback
    }
  }

  // --- REQUEST BODY WIDGET BUILDER ---

  Widget _buildRequestBodySection(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final rb = widget.endpoint.requestBody;
    final sampleJson = rb?.sampleJson ?? '';
    final bodyText = _bodyController.text;

    final isAlignEndpoint = widget.endpoint.path.contains('/align/suggestions');

    final hasModelId = sampleJson.contains('"model_id"') ||
        sampleJson.contains('"logical_model_id"') ||
        sampleJson.contains('"modelId"') ||
        bodyText.contains('"model_id"') ||
        bodyText.contains('"logical_model_id"');

    final hasSourceId = sampleJson.contains('"source_id"') ||
        sampleJson.contains('"sourceId"') ||
        bodyText.contains('"source_id"') ||
        bodyText.contains('"sourceId"');

    final hasMappingId = sampleJson.contains('"mapping_id"') ||
        sampleJson.contains('"mappingId"') ||
        bodyText.contains('"mapping_id"') ||
        bodyText.contains('"mappingId"');

    final showContextualHelpers = hasModelId || hasSourceId || hasMappingId || isAlignEndpoint;

    return Container(
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
            children: [
              Icon(Icons.data_object, size: 16, color: colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                'Request Body',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  rb?.contentType ?? 'application/json',
                  style: TextStyle(fontSize: 10, color: colorScheme.onSurfaceVariant),
                ),
              ),
              const Spacer(),

              // Format JSON action
              TextButton.icon(
                key: const Key('api_format_json_button'),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                ),
                icon: const Icon(Icons.auto_fix_high, size: 14),
                label: const Text('Format JSON', style: TextStyle(fontSize: 12)),
                onPressed: _formatJsonBody,
              ),

              // Reset Template action
              TextButton.icon(
                key: const Key('api_reset_template_button'),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                ),
                icon: const Icon(Icons.restart_alt, size: 14),
                label: const Text('Reset Template', style: TextStyle(fontSize: 12)),
                onPressed: _resetJsonBody,
              ),
            ],
          ),

          if (rb?.description != null && rb!.description.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              rb.description,
              style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
            ),
          ],

          // Dedicated Align Suggestion Builder OR Generic Contextual ID Helpers Card
          if (isAlignEndpoint)
            _buildAlignSuggestionBuilderCard(context)
          else if (showContextualHelpers)
            _buildGenericContextualHelpersCard(context, hasModelId: hasModelId, hasSourceId: hasSourceId, hasMappingId: hasMappingId),

          if (_jsonFormatError != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colorScheme.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                _jsonFormatError!,
                style: TextStyle(fontSize: 11, color: colorScheme.error),
              ),
            ),
          ],

          const SizedBox(height: 12),

          // Multi-line JSON Editor
          TextField(
            key: const Key('api_request_body_editor'),
            controller: _bodyController,
            maxLines: 14,
            minLines: 8,
            keyboardType: TextInputType.multiline,
            decoration: InputDecoration(
              filled: true,
              fillColor: colorScheme.surface,
              contentPadding: const EdgeInsets.all(12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: colorScheme.primary),
              ),
            ),
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  // --- ALIGN SUGGESTION BUILDER CARD (Dedicated Contextual Helper) ---

  Widget _buildAlignSuggestionBuilderCard(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final selectedModel = widget.logicalModels.where((m) => m.id == _selectedAlignModelId).firstOrNull ??
        (widget.logicalModels.isNotEmpty ? widget.logicalModels.first : null);
    final availableEntities = selectedModel?.entities ?? [];
    final selectedEntity = availableEntities.where((e) => e.id == _selectedAlignEntityId).firstOrNull ??
        (availableEntities.isNotEmpty ? availableEntities.first : null);
    final availableFields = selectedEntity?.fields ?? [];

    final availablePhysicalEntities = _alignDiscoveredSchema?.entities ?? [];
    final selectedPhysicalEntity = availablePhysicalEntities.where((e) => e.name == _selectedAlignPhysicalEntityName).firstOrNull ??
        (availablePhysicalEntities.isNotEmpty ? availablePhysicalEntities.first : null);
    final availablePhysicalFields = selectedPhysicalEntity?.fields ?? [];

    return Container(
      key: const Key('api_align_suggestion_builder_card'),
      margin: const EdgeInsets.only(top: 12, bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_fix_high, size: 16, color: colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                'Altr Align Suggestion Helper',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  '(Build valid suggestion payload from dynamic registry & source schema)',
                  style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Row 1: Logical Model & Physical Source
          Row(
            children: [
              // Logical Model Selector
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Logical Model:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: colorScheme.onSurfaceVariant)),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          key: const Key('api_body_model_selector'),
                          isDense: true,
                          value: widget.logicalModels.any((m) => m.id == _selectedAlignModelId)
                              ? _selectedAlignModelId
                              : (widget.logicalModels.isNotEmpty ? widget.logicalModels.first.id : null),
                          hint: const Text('Select Logical Model...', style: TextStyle(fontSize: 11)),
                          items: widget.logicalModels.map((m) {
                            return DropdownMenuItem<String>(
                              value: m.id,
                              child: Text('${m.name} (${m.id.substring(0, m.id.length > 8 ? 8 : m.id.length)}...)', style: const TextStyle(fontSize: 11)),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) {
                              setState(() {
                                _selectedAlignModelId = val;
                                _selectedBodyModelId = val;
                                final m = widget.logicalModels.where((x) => x.id == val).firstOrNull;
                                if (m != null && m.entities.isNotEmpty) {
                                  _selectedAlignEntityId = m.entities.first.id;
                                  if (m.entities.first.fields.isNotEmpty) {
                                    _selectedAlignFieldId = m.entities.first.fields.first.id;
                                  }
                                }
                              });
                            }
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),

              // Physical Source Selector
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Physical Source:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: colorScheme.onSurfaceVariant)),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          key: const Key('api_body_source_selector'),
                          isDense: true,
                          value: widget.sources.any((s) => s.id == _selectedAlignSourceId)
                              ? _selectedAlignSourceId
                              : (widget.sources.isNotEmpty ? widget.sources.first.id : null),
                          hint: const Text('Select Physical Source...', style: TextStyle(fontSize: 11)),
                          items: widget.sources.map((s) {
                            return DropdownMenuItem<String>(
                              value: s.id,
                              child: Text('${s.name} (${s.type})', style: const TextStyle(fontSize: 11)),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) {
                              setState(() {
                                _selectedAlignSourceId = val;
                                _selectedBodySourceId = val;
                              });
                              _loadDiscoveredSchemaForSource(val);
                            }
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Row 2: Logical Entity & Physical Entity
          Row(
            children: [
              // Logical Entity Dropdown
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Logical Entity:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: colorScheme.onSurfaceVariant)),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          key: const Key('api_align_entity_selector'),
                          isDense: true,
                          value: availableEntities.any((e) => e.id == _selectedAlignEntityId)
                              ? _selectedAlignEntityId
                              : (availableEntities.isNotEmpty ? availableEntities.first.id : null),
                          hint: const Text('Select Logical Entity...', style: TextStyle(fontSize: 11)),
                          items: availableEntities.map((e) {
                            return DropdownMenuItem<String>(
                              value: e.id,
                              child: Text(e.name, style: const TextStyle(fontSize: 11)),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) {
                              setState(() {
                                _selectedAlignEntityId = val;
                                final ent = availableEntities.where((x) => x.id == val).firstOrNull;
                                if (ent != null && ent.fields.isNotEmpty) {
                                  _selectedAlignFieldId = ent.fields.first.id;
                                }
                              });
                            }
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),

              // Physical Entity (Dropdown if discovered schema available, else TextField)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('Physical Entity:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: colorScheme.onSurfaceVariant)),
                        if (_isLoadingDiscoveredSchema) ...[
                          const SizedBox(width: 6),
                          const SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 2)),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    if (availablePhysicalEntities.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            key: const Key('api_align_physical_entity_selector'),
                            isDense: true,
                            value: availablePhysicalEntities.any((e) => e.name == _selectedAlignPhysicalEntityName)
                                ? _selectedAlignPhysicalEntityName
                                : availablePhysicalEntities.first.name,
                            items: availablePhysicalEntities.map((e) {
                              return DropdownMenuItem<String>(
                                value: e.name,
                                child: Text(e.name, style: const TextStyle(fontSize: 11)),
                              );
                            }).toList(),
                            onChanged: (val) {
                              if (val != null) {
                                setState(() {
                                  _selectedAlignPhysicalEntityName = val;
                                  _alignPhysicalEntityInputController.text = val;
                                  final pEnt = availablePhysicalEntities.where((x) => x.name == val).firstOrNull;
                                  if (pEnt != null && pEnt.fields.isNotEmpty) {
                                    _selectedAlignPhysicalFieldName = pEnt.fields.first.name;
                                    _alignPhysicalFieldInputController.text = pEnt.fields.first.name;
                                  }
                                });
                              }
                            },
                          ),
                        ),
                      )
                    else
                      TextField(
                        key: const Key('api_align_physical_entity_input'),
                        controller: _alignPhysicalEntityInputController,
                        decoration: InputDecoration(
                          hintText: 'Enter physical entity/table/collection...',
                          hintStyle: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6)),
                          filled: true,
                          fillColor: colorScheme.surfaceContainerLow,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5))),
                        ),
                        style: const TextStyle(fontSize: 11),
                        onChanged: (val) => _selectedAlignPhysicalEntityName = val,
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Row 3: Logical Field & Physical Field
          Row(
            children: [
              // Logical Field Dropdown
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Logical Field:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: colorScheme.onSurfaceVariant)),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          key: const Key('api_align_field_selector'),
                          isDense: true,
                          value: availableFields.any((f) => f.id == _selectedAlignFieldId)
                              ? _selectedAlignFieldId
                              : (availableFields.isNotEmpty ? availableFields.first.id : null),
                          hint: const Text('Select Logical Field...', style: TextStyle(fontSize: 11)),
                          items: availableFields.map((f) {
                            return DropdownMenuItem<String>(
                              value: f.id,
                              child: Text('${f.name} (${f.dataType})', style: const TextStyle(fontSize: 11)),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) {
                              setState(() {
                                _selectedAlignFieldId = val;
                              });
                            }
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),

              // Physical Field (Dropdown if discovered schema available, else TextField)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Physical Field:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: colorScheme.onSurfaceVariant)),
                    const SizedBox(height: 4),
                    if (availablePhysicalFields.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            key: const Key('api_align_physical_field_selector'),
                            isDense: true,
                            value: availablePhysicalFields.any((f) => f.name == _selectedAlignPhysicalFieldName)
                                ? _selectedAlignPhysicalFieldName
                                : availablePhysicalFields.first.name,
                            items: availablePhysicalFields.map((f) {
                              return DropdownMenuItem<String>(
                                value: f.name,
                                child: Text('${f.name} (${f.dataType})', style: const TextStyle(fontSize: 11)),
                              );
                            }).toList(),
                            onChanged: (val) {
                              if (val != null) {
                                setState(() {
                                  _selectedAlignPhysicalFieldName = val;
                                  _alignPhysicalFieldInputController.text = val;
                                });
                              }
                            },
                          ),
                        ),
                      )
                    else
                      TextField(
                        key: const Key('api_align_physical_field_input'),
                        controller: _alignPhysicalFieldInputController,
                        decoration: InputDecoration(
                          hintText: 'Enter physical field/column name...',
                          hintStyle: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6)),
                          filled: true,
                          fillColor: colorScheme.surfaceContainerLow,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5))),
                        ),
                        style: const TextStyle(fontSize: 11),
                        onChanged: (val) => _selectedAlignPhysicalFieldName = val,
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Row 4: Physical Namespace & Confidence (Explicit User Inputs)
          Row(
            children: [
              // Physical Namespace / Database
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Physical Namespace / Database:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: colorScheme.onSurfaceVariant)),
                    const SizedBox(height: 4),
                    TextField(
                      key: const Key('api_align_namespace_input'),
                      controller: _alignNamespaceController,
                      decoration: InputDecoration(
                        hintText: 'e.g. public, altr_test_db...',
                        hintStyle: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6)),
                        filled: true,
                        fillColor: colorScheme.surfaceContainerLow,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5))),
                      ),
                      style: const TextStyle(fontSize: 11),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),

              // Confidence Score
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Confidence Score (0.0 - 1.0):', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: colorScheme.onSurfaceVariant)),
                    const SizedBox(height: 4),
                    TextField(
                      key: const Key('api_align_confidence_input'),
                      controller: _alignConfidenceController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        hintText: 'e.g. 0.95',
                        hintStyle: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6)),
                        filled: true,
                        fillColor: colorScheme.surfaceContainerLow,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5))),
                      ),
                      style: const TextStyle(fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Action: Apply Align Suggestion
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton.icon(
              key: const Key('api_apply_align_suggestion_button'),
              style: ElevatedButton.styleFrom(
                backgroundColor: colorScheme.primary,
                foregroundColor: colorScheme.onPrimary,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
              ),
              icon: const Icon(Icons.check_circle_outline, size: 16),
              label: const Text('Apply Align Suggestion to Request Body', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              onPressed: _applyAlignSuggestionToBody,
            ),
          ),
        ],
      ),
    );
  }

  // --- GENERIC CONTEXTUAL ID HELPERS CARD ---

  Widget _buildGenericContextualHelpersCard(
    BuildContext context, {
    required bool hasModelId,
    required bool hasSourceId,
    required bool hasMappingId,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.only(top: 10, bottom: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, size: 14, color: colorScheme.primary),
              const SizedBox(width: 6),
              Text(
                'Contextual ID Helpers',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '(Auto-fills UUIDs into JSON body)',
                style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Logical Model Selector
          if (hasModelId) ...[
            if (widget.logicalModels.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Icon(Icons.schema, size: 13, color: colorScheme.primary),
                    const SizedBox(width: 6),
                    Text('Logical Model:', style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          key: const Key('api_body_model_selector'),
                          isDense: true,
                          value: widget.logicalModels.any((m) => m.id == _selectedBodyModelId)
                              ? _selectedBodyModelId
                              : null,
                          hint: const Text('Select Logical Model...', style: TextStyle(fontSize: 11)),
                          items: widget.logicalModels.map((m) {
                            return DropdownMenuItem<String>(
                              value: m.id,
                              child: Text(
                                '${m.name} (${m.id.substring(0, m.id.length > 8 ? 8 : m.id.length)}...)',
                                style: const TextStyle(fontSize: 11),
                              ),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) {
                              _updateBodyJsonField(['logical_model_id', 'model_id', 'modelId'], val);
                            }
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  'No logical models registered yet. Enter UUID in editor.',
                  style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                ),
              ),
          ],

          // Physical Source Selector
          if (hasSourceId) ...[
            if (widget.sources.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Icon(Icons.dns, size: 13, color: colorScheme.primary),
                    const SizedBox(width: 6),
                    Text('Physical Source:', style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          key: const Key('api_body_source_selector'),
                          isDense: true,
                          value: widget.sources.any((s) => s.id == _selectedBodySourceId)
                              ? _selectedBodySourceId
                              : null,
                          hint: const Text('Select Physical Source...', style: TextStyle(fontSize: 11)),
                          items: widget.sources.map((s) {
                            return DropdownMenuItem<String>(
                              value: s.id,
                              child: Text(
                                '${s.name} (${s.type})',
                                style: const TextStyle(fontSize: 11),
                              ),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) {
                              _updateBodyJsonField(['source_id', 'sourceId'], val);
                            }
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  'No physical data sources registered yet. Enter source_id in editor.',
                  style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                ),
              ),
          ],

          // Source Mapping Selector
          if (hasMappingId) ...[
            if (widget.sourceMappings.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Icon(Icons.compare_arrows, size: 13, color: colorScheme.primary),
                    const SizedBox(width: 6),
                    Text('Source Mapping:', style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          key: const Key('api_body_mapping_selector'),
                          isDense: true,
                          value: widget.sourceMappings.any((m) => m.id == _selectedBodyMappingId)
                              ? _selectedBodyMappingId
                              : null,
                          hint: const Text('Select Source Mapping...', style: TextStyle(fontSize: 11)),
                          items: widget.sourceMappings.map((m) {
                            final shortId = m.id.substring(0, m.id.length > 8 ? 8 : m.id.length);
                            return DropdownMenuItem<String>(
                              value: m.id,
                              child: Text(
                                'Mapping $shortId... (${m.status})',
                                style: const TextStyle(fontSize: 11),
                              ),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) {
                              _updateBodyJsonField(['mapping_id', 'mappingId'], val);
                            }
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  'No source mappings registered yet. Enter mapping_id in editor if needed.',
                  style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                ),
              ),
          ],
        ],
      ),
    );
  }

  static Color _getMethodColor(String method, BuildContext context) {
    switch (method.toUpperCase()) {
      case 'GET':
        return const Color(0xFF38A169);
      case 'POST':
        return const Color(0xFF3182CE);
      case 'PUT':
        return const Color(0xFFDD6B20);
      case 'DELETE':
        return const Color(0xFFE53E3E);
      case 'PATCH':
        return const Color(0xFF805AD5);
      case 'HEAD':
        return const Color(0xFF319795);
      default:
        return Theme.of(context).colorScheme.primary;
    }
  }
}
