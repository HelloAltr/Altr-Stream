import 'package:flutter/material.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/models.dart';

class AddMappingDialog extends StatefulWidget {
  final ApiClient apiClient;
  final LogicalModelModel logicalModel;
  final List<SourceModel> sources;
  final ValueChanged<SourceMappingModel> onMappingCreated;
  final SourceMappingModel? existingMapping;

  const AddMappingDialog({
    super.key,
    required this.apiClient,
    required this.logicalModel,
    required this.sources,
    required this.onMappingCreated,
    this.existingMapping,
  });

  @override
  State<AddMappingDialog> createState() => _AddMappingDialogState();
}

class _EntityMappingDraft {
  final LogicalEntityModel logicalEntity;
  String? physicalEntityName;
  String physicalNamespace = 'public';
  final Map<String, String> fieldMappings = {}; // logical_field_name -> physical_field_name

  _EntityMappingDraft({required this.logicalEntity});
}

class _AddMappingDialogState extends State<AddMappingDialog> {
  String? _selectedSourceId;
  SourceSchemaModel? _sourceSchema;
  bool _isLoadingSchema = false;
  bool _isSubmitting = false;
  String? _errorMessage;

  final List<_EntityMappingDraft> _entityDrafts = [];

  bool get _isEditMode => widget.existingMapping != null;

  @override
  void initState() {
    super.initState();
    for (var entity in widget.logicalModel.entities) {
      final draft = _EntityMappingDraft(logicalEntity: entity);
      if (_isEditMode) {
        final em = widget.existingMapping!.entityMappings.where(
          (m) => m.logicalEntityId == entity.id || m.logicalEntityName == entity.name,
        ).firstOrNull;
        if (em != null) {
          draft.physicalEntityName = em.physicalEntityName;
          draft.physicalNamespace = em.physicalNamespace;
          for (var fm in em.fieldMappings) {
            draft.fieldMappings[fm.logicalFieldName] = fm.physicalFieldName;
          }
        }
      }
      _entityDrafts.add(draft);
    }

    if (_isEditMode) {
      _selectedSourceId = widget.existingMapping!.sourceId;
      _loadSourceSchema(_selectedSourceId!, preserveExistingMappings: true);
    } else if (widget.sources.isNotEmpty) {
      _selectedSourceId = widget.sources.first.id;
      _loadSourceSchema(_selectedSourceId!);
    }
  }

  Future<void> _loadSourceSchema(String sourceId, {bool preserveExistingMappings = false}) async {
    setState(() {
      _isLoadingSchema = true;
      _sourceSchema = null;
      _errorMessage = null;
    });

    try {
      SourceSchemaModel? schema = await widget.apiClient.getLatestSchema(sourceId);
      if (schema == null || schema.entities.isEmpty) {
        schema = await widget.apiClient.discoverSchema(sourceId);
      }

      setState(() {
        _sourceSchema = schema;
        _isLoadingSchema = false;
        if (!preserveExistingMappings) {
          _autoMatchEntities();
        }
      });
    } catch (e) {
      setState(() {
        _isLoadingSchema = false;
        _errorMessage = 'Failed to load source physical schema: $e';
      });
    }
  }

  void _autoMatchEntities() {
    if (_sourceSchema == null) return;

    for (var draft in _entityDrafts) {
      final logicalName = draft.logicalEntity.name.toLowerCase();
      // Try exact or plural or strip underscores
      final matched = _sourceSchema!.entities.where((pe) {
        final pn = pe.name.toLowerCase();
        return pn == logicalName ||
            pn == '${logicalName}s' ||
            pn == 'tbl_$logicalName' ||
            pn == '${logicalName}_tbl' ||
            pn.replaceAll('_', '') == logicalName.replaceAll('_', '');
      }).toList();

      if (matched.isNotEmpty) {
        draft.physicalEntityName = matched.first.name;
        draft.physicalNamespace = matched.first.namespace;
        _autoMatchFields(draft);
      }
    }
  }

  void _autoMatchFields(_EntityMappingDraft draft) {
    if (_sourceSchema == null || draft.physicalEntityName == null) return;

    final physEntity = _sourceSchema!.entities.firstWhere(
      (pe) => pe.name == draft.physicalEntityName,
      orElse: () => _sourceSchema!.entities.first,
    );

    for (var lf in draft.logicalEntity.fields) {
      final lfn = lf.name.toLowerCase().replaceAll('_', '');
      for (var pf in physEntity.fields) {
        final pfn = pf.name.toLowerCase().replaceAll('_', '');
        if (pfn == lfn || pf.name.toLowerCase() == lf.name.toLowerCase()) {
          draft.fieldMappings[lf.name] = pf.name;
          break;
        }
      }
    }
  }

  Future<void> _submit() async {
    if (_selectedSourceId == null) {
      setState(() => _errorMessage = 'Please select a data source');
      return;
    }

    // Build entity mappings payload
    final entityPayloads = <Map<String, dynamic>>[];
    for (var draft in _entityDrafts) {
      if (draft.physicalEntityName == null || draft.physicalEntityName!.isEmpty) {
        continue;
      }

      final fieldPayloads = <Map<String, dynamic>>[];
      for (var lf in draft.logicalEntity.fields) {
        final physField = draft.fieldMappings[lf.name];
        if (physField != null && physField.isNotEmpty) {
          fieldPayloads.add({
            'logical_field_id': lf.id,
            'logical_field_name': lf.name,
            'physical_field_name': physField,
          });
        }
      }

      if (fieldPayloads.isEmpty) {
        setState(() => _errorMessage = 'Entity "${draft.logicalEntity.name}" has no mapped fields');
        return;
      }

      entityPayloads.add({
        'logical_entity_id': draft.logicalEntity.id,
        'logical_entity_name': draft.logicalEntity.name,
        'physical_entity_name': draft.physicalEntityName,
        'physical_namespace': draft.physicalNamespace,
        'field_mappings': fieldPayloads,
      });
    }

    if (entityPayloads.isEmpty) {
      setState(() => _errorMessage = 'At least one entity must be mapped to a physical table');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      SourceMappingModel resultMapping;
      if (_isEditMode) {
        resultMapping = await widget.apiClient.updateSourceMapping(
          widget.existingMapping!.id,
          version: widget.logicalModel.version,
          entityMappings: entityPayloads,
        );
      } else {
        resultMapping = await widget.apiClient.createSourceMapping(
          logicalModelId: widget.logicalModel.id,
          sourceId: _selectedSourceId!,
          version: widget.logicalModel.version,
          provenance: 'USER',
          entityMappings: entityPayloads,
        );
      }

      // Trigger automatic validation
      final validated = await widget.apiClient.validateSourceMapping(resultMapping.id);

      if (mounted) {
        Navigator.of(context).pop();
        widget.onMappingCreated(validated);
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isSubmitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Dialog(
      backgroundColor: colorScheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 800, maxHeight: 780),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.compare_arrows, color: colorScheme.primary, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _isEditMode
                            ? 'Edit Mapping for "${widget.logicalModel.name}"'
                            : 'Map Physical Source to "${widget.logicalModel.name}"',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      Text(
                        _isEditMode
                            ? 'Update physical database table and column mappings for standard logical entities.'
                            : 'Map physical database tables and columns to standard logical entities.',
                        style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close, size: 18),
                  color: colorScheme.onSurfaceVariant,
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_errorMessage != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.errorContainer.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: colorScheme.error.withValues(alpha: 0.5)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: colorScheme.error, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(_errorMessage!, style: TextStyle(color: colorScheme.error, fontSize: 12)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            // Source Selector
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _selectedSourceId,
                    decoration: const InputDecoration(
                      labelText: 'Target Physical Data Source',
                      prefixIcon: Icon(Icons.storage, size: 18),
                    ),
                    items: widget.sources.map((s) {
                      return DropdownMenuItem(
                        value: s.id,
                        child: Text('${s.name} (${s.type})', style: const TextStyle(fontSize: 13)),
                      );
                    }).toList(),
                    onChanged: _isEditMode
                        ? null // Source cannot be changed when editing an existing source mapping
                        : (val) {
                            if (val != null) {
                              setState(() => _selectedSourceId = val);
                              _loadSourceSchema(val);
                            }
                          },
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: _sourceSchema != null
                      ? () {
                          setState(() {
                            _autoMatchEntities();
                          });
                        }
                      : null,
                  icon: const Icon(Icons.auto_fix_high, size: 16),
                  label: const Text('Auto-Match All'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_isLoadingSchema)
              Padding(
                padding: const EdgeInsets.all(40),
                child: Center(
                  child: Column(
                    children: [
                      CircularProgressIndicator(color: colorScheme.primary),
                      const SizedBox(height: 12),
                      const Text('Inspecting physical schema...', style: TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
              )
            else if (_sourceSchema == null)
              Container(
                padding: const EdgeInsets.all(24),
                child: const Center(
                  child: Text('Select a connected data source to inspect its tables and columns.'),
                ),
              )
            else
              Expanded(
                child: ListView.separated(
                  itemCount: _entityDrafts.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 16),
                  itemBuilder: (context, eIdx) {
                    final draft = _entityDrafts[eIdx];
                    final physEntities = _sourceSchema!.entities;
                    final selectedPhysEntity = physEntities.where((pe) => pe.name == draft.physicalEntityName).firstOrNull;

                    return Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainer,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: colorScheme.primary.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'Logical Entity: ${draft.logicalEntity.name}',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: colorScheme.primary,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              const Icon(Icons.arrow_forward, size: 16),
                              const SizedBox(width: 12),
                                Expanded(
                                child: DropdownButtonFormField<String?>(
                                  initialValue: draft.physicalEntityName,
                                  hint: const Text('Select Physical Table', style: TextStyle(fontSize: 13)),
                                  isDense: false,
                                  isExpanded: true,
                                  decoration: InputDecoration(
                                    labelText: 'Physical Table',
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.8)),
                                    ),
                                  ),
                                  items: [
                                    const DropdownMenuItem<String?>(
                                      value: null,
                                      child: Text('(Not Mapped)', style: TextStyle(fontSize: 13, color: Colors.grey)),
                                    ),
                                    ...physEntities.map(
                                      (pe) => DropdownMenuItem<String?>(
                                        value: pe.name,
                                        child: Text('${pe.namespace}.${pe.name}', style: const TextStyle(fontSize: 13)),
                                      ),
                                    ),
                                  ],
                                  onChanged: (val) {
                                    setState(() {
                                      draft.physicalEntityName = val;
                                      if (val != null) {
                                        final pe = physEntities.firstWhere((e) => e.name == val);
                                        draft.physicalNamespace = pe.namespace;
                                        _autoMatchFields(draft);
                                      } else {
                                        draft.fieldMappings.clear();
                                      }
                                    });
                                  },
                                ),
                              ),
                            ],
                          ),
                          if (draft.physicalEntityName != null && selectedPhysEntity != null) ...[
                            const SizedBox(height: 14),
                            Divider(height: 1, color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
                            const SizedBox(height: 12),
                            Text(
                              'Field Mappings (${draft.logicalEntity.fields.length} logical fields):',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: colorScheme.onSurfaceVariant),
                            ),
                            const SizedBox(height: 10),
                            ...draft.logicalEntity.fields.map((lf) {
                              final currentPhysField = draft.fieldMappings[lf.name];
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 6),
                                child: Row(
                                  children: [
                                    SizedBox(
                                      width: 200,
                                      child: Row(
                                        children: [
                                          Icon(
                                            lf.isPrimaryKey ? Icons.key : Icons.tag,
                                            size: 14,
                                            color: lf.isPrimaryKey ? Colors.amber : colorScheme.onSurfaceVariant,
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              lf.name,
                                              style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600,
                                                color: colorScheme.onSurface,
                                              ),
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: colorScheme.primary.withValues(alpha: 0.1),
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              lf.dataType,
                                              style: TextStyle(fontSize: 11, color: colorScheme.primary, fontFamily: 'monospace', fontWeight: FontWeight.w600),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    const Icon(Icons.arrow_right_alt, size: 18),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: DropdownButtonFormField<String?>(
                                        initialValue: selectedPhysEntity.fields.any((pf) => pf.name == currentPhysField) ? currentPhysField : null,
                                        isDense: false,
                                        isExpanded: true,
                                        hint: const Text('Select physical column', style: TextStyle(fontSize: 13)),
                                        decoration: InputDecoration(
                                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                          enabledBorder: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(8),
                                            borderSide: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.8)),
                                          ),
                                        ),
                                        items: [
                                          const DropdownMenuItem<String?>(
                                            value: null,
                                            child: Text('(Unmapped)', style: TextStyle(fontSize: 13, color: Colors.grey)),
                                          ),
                                          ...selectedPhysEntity.fields.map(
                                            (pf) => DropdownMenuItem<String?>(
                                              value: pf.name,
                                              child: Text(
                                                '${pf.name} (${pf.dataType})',
                                                style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
                                              ),
                                            ),
                                          ),
                                        ],
                                        onChanged: (val) {
                                          setState(() {
                                            if (val == null) {
                                              draft.fieldMappings.remove(lf.name);
                                            } else {
                                              draft.fieldMappings[lf.name] = val;
                                            }
                                          });
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }),
                          ],
                        ],
                      ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
                  child: Text('Cancel', style: TextStyle(color: colorScheme.onSurfaceVariant)),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _isSubmitting || _isLoadingSchema || _sourceSchema == null ? null : _submit,
                  icon: _isSubmitting
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save, size: 16),
                  label: Text(_isSubmitting
                      ? 'Validating & Saving...'
                      : (_isEditMode ? 'Update & Validate Mapping' : 'Save & Validate Mapping')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
