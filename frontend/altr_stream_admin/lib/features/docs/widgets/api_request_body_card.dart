import 'package:flutter/material.dart';
import '../../../core/api/models.dart';
import '../models/api_endpoint_model.dart';

/// Reusable Request Body Card component featuring monospace JSON editor,
/// format button, template reset button, contextual dropdown auto-fillers, and syntax error banner.
class ApiRequestBodyCard extends StatelessWidget {
  final ApiEndpoint endpoint;
  final TextEditingController bodyController;
  final String? jsonFormatError;
  final VoidCallback onFormatJson;
  final VoidCallback onResetTemplate;
  final ValueChanged<String> onBodyChanged;

  // Contextual helper state
  final List<SourceModel> sources;
  final List<LogicalModelModel> logicalModels;
  final List<SourceMappingModel> sourceMappings;
  final String? selectedBodyModelId;
  final String? selectedBodySourceId;
  final String? selectedBodyMappingId;
  final ValueChanged<String?> onSelectBodyModel;
  final ValueChanged<String?> onSelectBodySource;
  final ValueChanged<String?> onSelectBodyMapping;

  // Align suggestion builder state
  final bool isAlignEndpoint;
  final String? selectedAlignModelId;
  final String? selectedAlignEntityId;
  final String? selectedAlignFieldId;
  final String? selectedAlignSourceId;
  final String? selectedAlignPhysicalEntityName;
  final String? selectedAlignPhysicalFieldName;
  final TextEditingController alignNamespaceController;
  final TextEditingController alignConfidenceController;
  final TextEditingController alignPhysicalEntityInputController;
  final TextEditingController alignPhysicalFieldInputController;
  final SourceSchemaModel? alignDiscoveredSchema;
  final bool isLoadingDiscoveredSchema;
  final ValueChanged<String?> onSelectAlignModel;
  final ValueChanged<String?> onSelectAlignEntity;
  final ValueChanged<String?> onSelectAlignField;
  final ValueChanged<String?> onSelectAlignSource;
  final ValueChanged<String?> onSelectAlignPhysicalEntity;
  final ValueChanged<String?> onSelectAlignPhysicalField;
  final VoidCallback onApplyAlignSuggestion;

  const ApiRequestBodyCard({
    super.key,
    required this.endpoint,
    required this.bodyController,
    required this.jsonFormatError,
    required this.onFormatJson,
    required this.onResetTemplate,
    required this.onBodyChanged,
    this.sources = const [],
    this.logicalModels = const [],
    this.sourceMappings = const [],
    this.selectedBodyModelId,
    this.selectedBodySourceId,
    this.selectedBodyMappingId,
    required this.onSelectBodyModel,
    required this.onSelectBodySource,
    required this.onSelectBodyMapping,
    this.isAlignEndpoint = false,
    this.selectedAlignModelId,
    this.selectedAlignEntityId,
    this.selectedAlignFieldId,
    this.selectedAlignSourceId,
    this.selectedAlignPhysicalEntityName,
    this.selectedAlignPhysicalFieldName,
    required this.alignNamespaceController,
    required this.alignConfidenceController,
    required this.alignPhysicalEntityInputController,
    required this.alignPhysicalFieldInputController,
    this.alignDiscoveredSchema,
    this.isLoadingDiscoveredSchema = false,
    required this.onSelectAlignModel,
    required this.onSelectAlignEntity,
    required this.onSelectAlignField,
    required this.onSelectAlignSource,
    required this.onSelectAlignPhysicalEntity,
    required this.onSelectAlignPhysicalField,
    required this.onApplyAlignSuggestion,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final rb = endpoint.requestBody;
    final isBodyEmpty = bodyController.text.trim().isEmpty;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Header Toolbar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.data_object_outlined,
                      size: 16,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Request Body',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1.5,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        rb?.contentType ?? 'application/json',
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Format JSON Action
                    TextButton.icon(
                      key: const Key('api_format_json_button'),
                      icon: const Icon(Icons.auto_fix_high, size: 13),
                      label: const Text(
                        'Format',
                        style: TextStyle(fontSize: 11),
                      ),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        minimumSize: const Size(0, 28),
                      ),
                      onPressed: isBodyEmpty ? null : onFormatJson,
                    ),
                    const SizedBox(width: 4),

                    // Reset Action
                    TextButton.icon(
                      key: const Key('api_reset_template_button'),
                      icon: const Icon(Icons.restore, size: 13),
                      label: const Text(
                        'Reset',
                        style: TextStyle(fontSize: 11),
                      ),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        minimumSize: const Size(0, 28),
                      ),
                      onPressed: onResetTemplate,
                    ),
                  ],
                ),
              ],
            ),
          ),
          Divider(
            height: 1,
            thickness: 1,
            color: colorScheme.outlineVariant.withValues(alpha: 0.4),
          ),

          // 2. Syntax Error Banner (if any)
          if (jsonFormatError != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              color: colorScheme.errorContainer.withValues(alpha: 0.5),
              child: Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 14,
                    color: colorScheme.error,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Invalid JSON: $jsonFormatError',
                      style: TextStyle(fontSize: 11, color: colorScheme.error),
                    ),
                  ),
                ],
              ),
            ),

          // 3. Contextual Helpers Bar (Smart Auto-Fillers)
          if (_hasContextualHelpers) _buildContextualHelpersBar(context),

          // 4. Align Suggestion Helper Builder (for /align/suggestions endpoint)
          if (isAlignEndpoint) _buildAlignSuggestionHelperCard(context),

          // 5. Code-Styled Monospace Editor
          Container(
            color: Colors.black.withValues(alpha: 0.35),
            padding: const EdgeInsets.all(12),
            child: TextField(
              key: const Key('api_request_body_editor'),
              controller: bodyController,
              maxLines: null,
              minLines: 7,
              keyboardType: TextInputType.multiline,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: Color(0xFFE2E8F0),
                height: 1.45,
              ),
              decoration: const InputDecoration(
                isDense: true,
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                hintText: '{\n  "key": "value"\n}',
                hintStyle: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: Colors.white24,
                ),
              ),
              onChanged: onBodyChanged,
            ),
          ),
        ],
      ),
    );
  }

  bool get _hasContextualHelpers =>
      (endpoint.isModelAware && logicalModels.isNotEmpty) ||
      (endpoint.isSourceAware && sources.isNotEmpty) ||
      (endpoint.isMappingAware && sourceMappings.isNotEmpty);

  Widget _buildContextualHelpersBar(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        border: Border(
          bottom: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, size: 13, color: colorScheme.primary),
              const SizedBox(width: 6),
              Text(
                'Contextual ID Helpers',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              // Model Selector
              if (endpoint.isModelAware && logicalModels.isNotEmpty)
                _buildCompactDropdown(
                  context,
                  key: const Key('api_body_model_selector'),
                  label: 'Logical Model',
                  value: selectedBodyModelId,
                  items: [
                    for (final m in logicalModels)
                      DropdownMenuItem(
                        value: m.id,
                        child: Text(
                          m.name,
                          style: const TextStyle(fontSize: 11),
                        ),
                      ),
                  ],
                  onChanged: onSelectBodyModel,
                ),

              // Source Selector
              if (endpoint.isSourceAware && sources.isNotEmpty)
                _buildCompactDropdown(
                  context,
                  key: const Key('api_body_source_selector'),
                  label: 'Data Source',
                  value: selectedBodySourceId,
                  items: [
                    for (final s in sources)
                      DropdownMenuItem(
                        value: s.id,
                        child: Text(
                          '${s.name} (${s.type})',
                          style: const TextStyle(fontSize: 11),
                        ),
                      ),
                  ],
                  onChanged: onSelectBodySource,
                ),

              // Mapping Selector
              if (endpoint.isMappingAware && sourceMappings.isNotEmpty)
                _buildCompactDropdown(
                  context,
                  key: const Key('api_body_mapping_selector'),
                  label: 'Source Mapping',
                  value: selectedBodyMappingId,
                  items: [
                    for (final m in sourceMappings)
                      DropdownMenuItem(
                        value: m.id,
                        child: Text(
                          'Mapping ${m.id.length > 8 ? m.id.substring(0, 8) : m.id}... (${m.status})',
                          style: const TextStyle(fontSize: 11),
                        ),
                      ),
                  ],
                  onChanged: onSelectBodyMapping,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCompactDropdown(
    BuildContext context, {
    required Key key,
    required String label,
    required String? value,
    required List<DropdownMenuItem<String>> items,
    required ValueChanged<String?> onChanged,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          key: key,
          value: value,
          isDense: true,
          hint: Text(
            label,
            style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
          ),
          icon: Icon(
            Icons.arrow_drop_down,
            size: 16,
            color: colorScheme.onSurfaceVariant,
          ),
          style: TextStyle(fontSize: 11, color: colorScheme.onSurface),
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildAlignSuggestionHelperCard(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    // Selected model's entities and fields
    final selectedModel = logicalModels
        .where((m) => m.id == selectedAlignModelId)
        .firstOrNull;
    final entities = selectedModel?.entities ?? [];
    final selectedEntity = entities
        .where((e) => e.id == selectedAlignEntityId)
        .firstOrNull;
    final fields = selectedEntity?.fields ?? [];

    // Discovered schema physical entities and fields
    final physEntities = alignDiscoveredSchema?.entities ?? [];
    final selectedPhysEntity = physEntities
        .where((e) => e.name == selectedAlignPhysicalEntityName)
        .firstOrNull;
    final physFields = selectedPhysEntity?.fields ?? [];

    return Container(
      key: const Key('api_align_suggestion_builder_card'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        border: Border(
          bottom: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.4),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 6,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.compare_arrows_rounded,
                    size: 14,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Align Suggestion Helper',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.primary,
                    ),
                  ),
                ],
              ),
              ElevatedButton.icon(
                key: const Key('api_apply_align_suggestion_button'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  minimumSize: const Size(0, 26),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                icon: const Icon(Icons.check, size: 12),
                label: const Text(
                  'Apply into Body',
                  style: TextStyle(fontSize: 10.5),
                ),
                onPressed: onApplyAlignSuggestion,
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Pickers Row
          Row(
            children: [
              // Logical Model Picker
              Expanded(
                child: _buildCompactPicker(
                  context,
                  label: 'Model',
                  value: selectedAlignModelId,
                  items: [
                    for (final m in logicalModels)
                      DropdownMenuItem(value: m.id, child: Text(m.name)),
                  ],
                  onChanged: onSelectAlignModel,
                ),
              ),
              const SizedBox(width: 6),

              // Logical Entity Picker
              Expanded(
                child: _buildCompactPicker(
                  context,
                  label: 'Entity',
                  value: selectedAlignEntityId,
                  items: [
                    for (final e in entities)
                      DropdownMenuItem(value: e.id, child: Text(e.name)),
                  ],
                  onChanged: onSelectAlignEntity,
                ),
              ),
              const SizedBox(width: 6),

              // Logical Field Picker
              Expanded(
                child: _buildCompactPicker(
                  context,
                  label: 'Field',
                  value: selectedAlignFieldId,
                  items: [
                    for (final f in fields)
                      DropdownMenuItem(value: f.id, child: Text(f.name)),
                  ],
                  onChanged: onSelectAlignField,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // Source and Physical Schema Row
          Row(
            children: [
              // Source Picker
              Expanded(
                child: _buildCompactPicker(
                  context,
                  label: 'Source',
                  value: selectedAlignSourceId,
                  items: [
                    for (final s in sources)
                      DropdownMenuItem(value: s.id, child: Text(s.name)),
                  ],
                  onChanged: onSelectAlignSource,
                ),
              ),
              const SizedBox(width: 6),

              // Physical Entity Picker
              Expanded(
                child: physEntities.isNotEmpty
                    ? _buildCompactPicker(
                        context,
                        label: 'Phys Entity',
                        value: selectedAlignPhysicalEntityName,
                        items: [
                          for (final e in physEntities)
                            DropdownMenuItem(
                              value: e.name,
                              child: Text(e.name),
                            ),
                        ],
                        onChanged: onSelectAlignPhysicalEntity,
                      )
                    : TextField(
                        controller: alignPhysicalEntityInputController,
                        style: const TextStyle(fontSize: 11),
                        decoration: const InputDecoration(
                          hintText: 'Phys Entity...',
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 6,
                          ),
                        ),
                      ),
              ),
              const SizedBox(width: 6),

              // Physical Field Picker
              Expanded(
                child: physFields.isNotEmpty
                    ? _buildCompactPicker(
                        context,
                        label: 'Phys Field',
                        value: selectedAlignPhysicalFieldName,
                        items: [
                          for (final f in physFields)
                            DropdownMenuItem(
                              value: f.name,
                              child: Text(f.name),
                            ),
                        ],
                        onChanged: onSelectAlignPhysicalField,
                      )
                    : TextField(
                        controller: alignPhysicalFieldInputController,
                        style: const TextStyle(fontSize: 11),
                        decoration: const InputDecoration(
                          hintText: 'Phys Field...',
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 6,
                          ),
                        ),
                      ),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // Namespace and Confidence inputs
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const Key('api_align_namespace_input'),
                  controller: alignNamespaceController,
                  style: const TextStyle(fontSize: 11),
                  decoration: const InputDecoration(
                    hintText: 'Namespace (e.g. public)',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 6,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: TextField(
                  key: const Key('api_align_confidence_input'),
                  controller: alignConfidenceController,
                  style: const TextStyle(fontSize: 11),
                  decoration: const InputDecoration(
                    hintText: 'Confidence (0.0 - 1.0)',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 6,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCompactPicker(
    BuildContext context, {
    required String label,
    required String? value,
    required List<DropdownMenuItem<String>> items,
    required ValueChanged<String?> onChanged,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isDense: true,
          isExpanded: true,
          hint: Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              color: colorScheme.onSurfaceVariant,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          icon: Icon(
            Icons.arrow_drop_down,
            size: 14,
            color: colorScheme.onSurfaceVariant,
          ),
          style: TextStyle(fontSize: 10.5, color: colorScheme.onSurface),
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }
}
