import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/models.dart';
import '../models/api_endpoint_model.dart';
import 'api_parameter_card.dart';
import 'api_request_body_card.dart';
import 'api_response_viewer.dart';

/// Right-region interactive "Try It Out" execution panel.
/// Combines structured parameter inputs, code-styled request body editor,
/// execute action button, and rich response inspection.
class ApiTryItOutPanel extends StatefulWidget {
  final ApiEndpoint endpoint;
  final ApiClient apiClient;
  final List<SourceModel> sources;
  final List<LogicalModelModel> logicalModels;
  final List<SourceMappingModel> sourceMappings;

  const ApiTryItOutPanel({
    super.key,
    required this.endpoint,
    required this.apiClient,
    this.sources = const [],
    this.logicalModels = const [],
    this.sourceMappings = const [],
  });

  @override
  State<ApiTryItOutPanel> createState() => _ApiTryItOutPanelState();
}

class _ApiTryItOutPanelState extends State<ApiTryItOutPanel> {
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
  void didUpdateWidget(covariant ApiTryItOutPanel oldWidget) {
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
        final source = widget.sources
            .where((s) => s.id == sourceId)
            .firstOrNull;
        setState(() {
          _alignDiscoveredSchema = schema;
          _isLoadingDiscoveredSchema = false;
          if (schema != null && schema.entities.isNotEmpty) {
            _selectedAlignPhysicalEntityName = schema.entities.first.name;
            _alignNamespaceController.text =
                schema.entities.first.namespace.isNotEmpty
                ? schema.entities.first.namespace
                : (source?.databaseName ?? 'public');
            if (schema.entities.first.fields.isNotEmpty) {
              _selectedAlignPhysicalFieldName =
                  schema.entities.first.fields.first.name;
            }
          }
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _alignDiscoveredSchema = null;
          _isLoadingDiscoveredSchema = false;
        });
      }
    }
  }

  void _formatJson() {
    final text = _bodyController.text.trim();
    if (text.isEmpty) return;
    try {
      final decoded = jsonDecode(text);
      final pretty = const JsonEncoder.withIndent('  ').convert(decoded);
      setState(() {
        _bodyController.text = pretty;
        _jsonFormatError = null;
      });
    } catch (e) {
      setState(() {
        _jsonFormatError = e.toString();
      });
    }
  }

  void _resetTemplate() {
    final sample = widget.endpoint.requestBody?.sampleJson ?? '';
    setState(() {
      _bodyController.text = sample;
      _jsonFormatError = null;
    });
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
        if (targetKeys.contains('logical_model_id') ||
            targetKeys.contains('model_id')) {
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

  void _applyAlignSuggestionToBody() {
    final modelId =
        _selectedAlignModelId ??
        (widget.logicalModels.isNotEmpty ? widget.logicalModels.first.id : '');
    final sourceId =
        _selectedAlignSourceId ??
        (widget.sources.isNotEmpty ? widget.sources.first.id : '');

    final model = widget.logicalModels
        .where((m) => m.id == modelId)
        .firstOrNull;
    final entity =
        model?.entities
            .where((e) => e.id == _selectedAlignEntityId)
            .firstOrNull ??
        model?.entities.firstOrNull;
    final field =
        entity?.fields
            .where((f) => f.id == _selectedAlignFieldId)
            .firstOrNull ??
        entity?.fields.firstOrNull;

    final physicalEntityName =
        _selectedAlignPhysicalEntityName?.trim().isNotEmpty == true
        ? _selectedAlignPhysicalEntityName!.trim()
        : (_alignPhysicalEntityInputController.text.trim().isNotEmpty
              ? _alignPhysicalEntityInputController.text.trim()
              : (entity?.name ?? ''));

    final physicalFieldName =
        _selectedAlignPhysicalFieldName?.trim().isNotEmpty == true
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
        },
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
        content: Text('Align suggestion template applied into request body.'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _executeRequest() async {
    // 1. Gather Path and Query Parameters
    final pathParams = <String, String>{};
    final queryParams = <String, dynamic>{};

    for (final p in widget.endpoint.parameters) {
      final val = _paramControllers[p.name]?.text.trim() ?? '';
      if (val.isNotEmpty) {
        if (p.isPath) {
          pathParams[p.name] = val;
        } else if (p.isQuery) {
          queryParams[p.name] = val;
        }
      }
    }

    // 2. Parse Request Body
    dynamic bodyPayload;
    if (widget.endpoint.hasRequestBody &&
        _bodyController.text.trim().isNotEmpty) {
      final rawBody = _bodyController.text.trim();
      try {
        bodyPayload = jsonDecode(rawBody);
      } catch (e) {
        setState(() {
          _isExecuting = false;
          _jsonFormatError = 'Malformed JSON body: $e';
        });
        return;
      }
    }

    // Required fields validation for AltrQL endpoints
    if (widget.endpoint.path.contains('/altrql/')) {
      if (bodyPayload is Map) {
        final q = bodyPayload['query']?.toString().trim() ?? '';
        final sid = bodyPayload['source_id']?.toString().trim() ?? '';
        if (q.isEmpty && widget.endpoint.path.contains('/bind')) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'Please enter an AltrQL query in the request body.',
              ),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
          return;
        }
        if (sid.isEmpty && widget.endpoint.path.contains('/bind')) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'Please select or enter a valid source_id in the request body.',
              ),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
          return;
        }
      }
    }

    setState(() {
      _isExecuting = true;
      _lastResult = null;
      _jsonFormatError = null;
    });

    // 3. Execute via ApiClient
    final result = await widget.apiClient.executeRawRequest(
      method: widget.endpoint.method,
      path: widget.endpoint.path,
      pathParams: pathParams.isEmpty ? null : pathParams,
      queryParams: queryParams.isEmpty ? null : queryParams,
      body: bodyPayload,
    );

    if (mounted) {
      setState(() {
        _isExecuting = false;
        _lastResult = result;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isAlignEndpoint =
        widget.endpoint.path.contains('/align/suggestions') &&
        widget.endpoint.method == 'POST';

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Panel Header & Execute Action Bar
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  HugeIcon(
                    icon: HugeIcons.strokeRoundedPlay,
                    size: 18,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Try It Out',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ],
              ),

              // Prominent Send Request Button
              ElevatedButton.icon(
                key: const Key('api_execute_button'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: colorScheme.primary,
                  foregroundColor: colorScheme.onPrimary,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  elevation: 1,
                ),
                icon: _isExecuting
                    ? SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colorScheme.onPrimary,
                        ),
                      )
                    : const HugeIcon(icon: HugeIcons.strokeRoundedSent, size: 14),
                label: Text(
                  _isExecuting ? 'Executing...' : 'Execute Request',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                onPressed: _isExecuting ? null : _executeRequest,
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 2. Parameters Card
          ApiParameterCard(
            endpoint: widget.endpoint,
            paramControllers: _paramControllers,
            selectedParamValues: _selectedParamValues,
            sources: widget.sources,
            logicalModels: widget.logicalModels,
            sourceMappings: widget.sourceMappings,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),

          // 3. Request Body Card (if applicable)
          if (widget.endpoint.hasRequestBody) ...[
            ApiRequestBodyCard(
              endpoint: widget.endpoint,
              bodyController: _bodyController,
              jsonFormatError: _jsonFormatError,
              onFormatJson: _formatJson,
              onResetTemplate: _resetTemplate,
              onBodyChanged: (_) => setState(() => _jsonFormatError = null),
              sources: widget.sources,
              logicalModels: widget.logicalModels,
              sourceMappings: widget.sourceMappings,
              selectedBodyModelId: _selectedBodyModelId,
              selectedBodySourceId: _selectedBodySourceId,
              selectedBodyMappingId: _selectedBodyMappingId,
              onSelectBodyModel: (id) {
                if (id != null) {
                  _selectedBodyModelId = id;
                  _updateBodyJsonField([
                    'logical_model_id',
                    'model_id',
                    'modelId',
                  ], id);
                }
              },
              onSelectBodySource: (id) {
                if (id != null) {
                  _selectedBodySourceId = id;
                  _updateBodyJsonField(['source_id', 'sourceId'], id);
                }
              },
              onSelectBodyMapping: (id) {
                if (id != null) {
                  _selectedBodyMappingId = id;
                  _updateBodyJsonField([
                    'mapping_id',
                    'source_mapping_id',
                    'mappingId',
                  ], id);
                }
              },
              isAlignEndpoint: isAlignEndpoint,
              selectedAlignModelId: _selectedAlignModelId,
              selectedAlignEntityId: _selectedAlignEntityId,
              selectedAlignFieldId: _selectedAlignFieldId,
              selectedAlignSourceId: _selectedAlignSourceId,
              selectedAlignPhysicalEntityName: _selectedAlignPhysicalEntityName,
              selectedAlignPhysicalFieldName: _selectedAlignPhysicalFieldName,
              alignNamespaceController: _alignNamespaceController,
              alignConfidenceController: _alignConfidenceController,
              alignPhysicalEntityInputController:
                  _alignPhysicalEntityInputController,
              alignPhysicalFieldInputController:
                  _alignPhysicalFieldInputController,
              alignDiscoveredSchema: _alignDiscoveredSchema,
              isLoadingDiscoveredSchema: _isLoadingDiscoveredSchema,
              onSelectAlignModel: (id) {
                if (id != null) {
                  setState(() {
                    _selectedAlignModelId = id;
                    final m = widget.logicalModels
                        .where((m) => m.id == id)
                        .firstOrNull;
                    if (m != null && m.entities.isNotEmpty) {
                      _selectedAlignEntityId = m.entities.first.id;
                      if (m.entities.first.fields.isNotEmpty) {
                        _selectedAlignFieldId =
                            m.entities.first.fields.first.id;
                      }
                    }
                  });
                }
              },
              onSelectAlignEntity: (id) {
                if (id != null) {
                  setState(() {
                    _selectedAlignEntityId = id;
                    final m = widget.logicalModels
                        .where((m) => m.id == _selectedAlignModelId)
                        .firstOrNull;
                    final e = m?.entities.where((e) => e.id == id).firstOrNull;
                    if (e != null && e.fields.isNotEmpty) {
                      _selectedAlignFieldId = e.fields.first.id;
                    }
                  });
                }
              },
              onSelectAlignField: (id) =>
                  setState(() => _selectedAlignFieldId = id),
              onSelectAlignSource: (id) {
                if (id != null) {
                  setState(() => _selectedAlignSourceId = id);
                  _loadDiscoveredSchemaForSource(id);
                }
              },
              onSelectAlignPhysicalEntity: (name) {
                if (name != null) {
                  setState(() {
                    _selectedAlignPhysicalEntityName = name;
                    final e = _alignDiscoveredSchema?.entities
                        .where((e) => e.name == name)
                        .firstOrNull;
                    if (e != null && e.fields.isNotEmpty) {
                      _selectedAlignPhysicalFieldName = e.fields.first.name;
                    }
                  });
                }
              },
              onSelectAlignPhysicalField: (name) =>
                  setState(() => _selectedAlignPhysicalFieldName = name),
              onApplyAlignSuggestion: _applyAlignSuggestionToBody,
            ),
            const SizedBox(height: 16),
          ],

          // 4. Response Viewer
          if (_lastResult != null) ...[
            ApiResponseViewer(
              result: _lastResult!,
              onClear: () => setState(() => _lastResult = null),
            ),
          ] else
            Container(
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                ),
              ),
              child: Center(
                child: Column(
                  children: [
                    HugeIcon(
                      icon: HugeIcons.strokeRoundedCommandLine,
                      size: 28,
                      color: colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.4,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Ready to execute request',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Configure parameters or body above and click "Send Request".',
                      style: TextStyle(
                        fontSize: 11,
                        color: colorScheme.onSurfaceVariant.withValues(
                          alpha: 0.7,
                        ),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
