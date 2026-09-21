import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import '../../../core/api/models.dart';
import '../models/api_endpoint_model.dart';

/// Reusable Parameter Card component for path, query, and header parameters.
/// Displays individual input fields with location chips and contextual helper dropdowns.
class ApiParameterCard extends StatelessWidget {
  final ApiEndpoint endpoint;
  final Map<String, TextEditingController> paramControllers;
  final Map<String, String?> selectedParamValues;
  final ValueChanged<void> onChanged;
  final List<SourceModel> sources;
  final List<LogicalModelModel> logicalModels;
  final List<SourceMappingModel> sourceMappings;

  const ApiParameterCard({
    super.key,
    required this.endpoint,
    required this.paramControllers,
    required this.selectedParamValues,
    required this.onChanged,
    this.sources = const [],
    this.logicalModels = const [],
    this.sourceMappings = const [],
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final params = endpoint.parameters;

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
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                HugeIcon(icon: HugeIcons.strokeRoundedSlidersVertical, size: 16, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Parameters',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1.5,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${params.length}',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Divider(
            height: 1,
            thickness: 1,
            color: colorScheme.outlineVariant.withValues(alpha: 0.4),
          ),

          // Body
          if (params.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Text(
                'No path or query parameters required.',
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. Path Parameters
                  if (params.any(
                    (p) => p.inLocation.toLowerCase() == 'path',
                  )) ...[
                    _buildParamGroupHeader('PATH PARAMETERS', colorScheme),
                    const SizedBox(height: 8),
                    for (final p in params.where(
                      (p) => p.inLocation.toLowerCase() == 'path',
                    )) ...[
                      _buildParameterInput(context, p),
                      const SizedBox(height: 10),
                    ],
                  ],

                  // 2. Query Parameters
                  if (params.any(
                    (p) => p.inLocation.toLowerCase() == 'query',
                  )) ...[
                    if (params.any((p) => p.inLocation.toLowerCase() == 'path'))
                      const SizedBox(height: 6),
                    _buildParamGroupHeader('QUERY PARAMETERS', colorScheme),
                    const SizedBox(height: 8),
                    for (final p in params.where(
                      (p) => p.inLocation.toLowerCase() == 'query',
                    )) ...[
                      _buildParameterInput(context, p),
                      const SizedBox(height: 10),
                    ],
                  ],

                  // 3. Header & Other Parameters
                  if (params.any(
                    (p) =>
                        !['path', 'query'].contains(p.inLocation.toLowerCase()),
                  )) ...[
                    if (params.any(
                      (p) => [
                        'path',
                        'query',
                      ].contains(p.inLocation.toLowerCase()),
                    ))
                      const SizedBox(height: 6),
                    _buildParamGroupHeader('HEADER PARAMETERS', colorScheme),
                    const SizedBox(height: 8),
                    for (final p in params.where(
                      (p) => ![
                        'path',
                        'query',
                      ].contains(p.inLocation.toLowerCase()),
                    )) ...[
                      _buildParameterInput(context, p),
                      const SizedBox(height: 10),
                    ],
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildParamGroupHeader(String title, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 2),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.6,
          color: colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _buildParameterInput(BuildContext context, ApiParameter p) {
    final colorScheme = Theme.of(context).colorScheme;
    final ctrl = paramControllers[p.name];

    // Contextual dropdown helpers for known parameter names
    final isSourceParam = p.name == 'source_id' || p.name == 'sourceId';
    final isModelParam =
        p.name == 'model_id' ||
        p.name == 'modelId' ||
        p.name == 'logical_model_id';
    final isMappingParam = p.name == 'mapping_id' || p.name == 'mappingId';

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: Parameter Name, Location Chip, Type, Required Star
          Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                p.name,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (p.required)
                const Text(
                  '*',
                  style: TextStyle(
                    color: Color(0xFFE53E3E),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              // Location chip
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  p.inLocation,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 9.5,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              // Type chip
              Text(
                '(${p.schemaType})',
                style: TextStyle(
                  fontSize: 10.5,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          if (p.description.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              p.description,
              style: TextStyle(
                fontSize: 11,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 8),

          // Contextual Dropdown quick-selectors
          if (isSourceParam && sources.isNotEmpty) ...[
            _buildSourceSelector(context, p),
            const SizedBox(height: 6),
          ] else if (isModelParam && logicalModels.isNotEmpty) ...[
            _buildModelSelector(context, p),
            const SizedBox(height: 6),
          ] else if (isMappingParam && sourceMappings.isNotEmpty) ...[
            _buildMappingSelector(context, p),
            const SizedBox(height: 6),
          ],

          // Parameter Text Field Input
          TextField(
            key: Key('api_param_input_${p.name}'),
            controller: ctrl,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            decoration: InputDecoration(
              isDense: true,
              hintText: p.defaultValue != null
                  ? 'Default: ${p.defaultValue}'
                  : 'Enter ${p.name}...',
              hintStyle: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
              ),
              filled: true,
              fillColor: colorScheme.surfaceContainerLowest,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 8,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(5),
                borderSide: BorderSide(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(5),
                borderSide: BorderSide(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(5),
                borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
              ),
            ),
            onChanged: (_) => onChanged(null),
          ),
        ],
      ),
    );
  }

  Widget _buildSourceSelector(BuildContext context, ApiParameter p) {
    final colorScheme = Theme.of(context).colorScheme;
    final currentVal = selectedParamValues[p.name];

    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          key: const Key('api_param_source_selector'),
          value: currentVal,
          isExpanded: true,
          hint: Text(
            'Select registered data source...',
            style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
          ),
          icon: HugeIcon(
            icon: HugeIcons.strokeRoundedArrowDown01,
            size: 16,
            color: colorScheme.onSurfaceVariant,
          ),
          style: TextStyle(fontSize: 11, color: colorScheme.onSurface),
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
          onChanged: (val) {
            if (val != null) {
              selectedParamValues[p.name] = val;
              paramControllers[p.name]?.text = val;
              onChanged(null);
            }
          },
        ),
      ),
    );
  }

  Widget _buildModelSelector(BuildContext context, ApiParameter p) {
    final colorScheme = Theme.of(context).colorScheme;
    final currentVal = selectedParamValues[p.name];

    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          key: const Key('api_param_model_selector'),
          value: currentVal,
          isExpanded: true,
          hint: Text(
            'Select logical model...',
            style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
          ),
          icon: HugeIcon(
            icon: HugeIcons.strokeRoundedArrowDown01,
            size: 16,
            color: colorScheme.onSurfaceVariant,
          ),
          style: TextStyle(fontSize: 11, color: colorScheme.onSurface),
          items: [
            for (final m in logicalModels)
              DropdownMenuItem(
                value: m.id,
                child: Text(m.name, style: const TextStyle(fontSize: 11)),
              ),
          ],
          onChanged: (val) {
            if (val != null) {
              selectedParamValues[p.name] = val;
              paramControllers[p.name]?.text = val;
              onChanged(null);
            }
          },
        ),
      ),
    );
  }

  Widget _buildMappingSelector(BuildContext context, ApiParameter p) {
    final colorScheme = Theme.of(context).colorScheme;
    final currentVal = selectedParamValues[p.name];

    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          key: const Key('api_param_mapping_selector'),
          value: currentVal,
          isExpanded: true,
          hint: Text(
            'Select source mapping...',
            style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
          ),
          icon: HugeIcon(
            icon: HugeIcons.strokeRoundedArrowDown01,
            size: 16,
            color: colorScheme.onSurfaceVariant,
          ),
          style: TextStyle(fontSize: 11, color: colorScheme.onSurface),
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
          onChanged: (val) {
            if (val != null) {
              selectedParamValues[p.name] = val;
              paramControllers[p.name]?.text = val;
              onChanged(null);
            }
          },
        ),
      ),
    );
  }
}
