import 'package:flutter/material.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/models.dart';

class AddEntityDialog extends StatefulWidget {
  final ApiClient apiClient;
  final String modelId;
  final ValueChanged<LogicalEntityModel> onEntityCreated;

  const AddEntityDialog({
    super.key,
    required this.apiClient,
    required this.modelId,
    required this.onEntityCreated,
  });

  @override
  State<AddEntityDialog> createState() => _AddEntityDialogState();
}

class _FieldDraft {
  final TextEditingController nameController = TextEditingController();
  String dataType = 'STRING';
  bool isPrimaryKey = false;
  bool nullable = true;

  _FieldDraft({String name = '', this.dataType = 'STRING', this.isPrimaryKey = false, this.nullable = true}) {
    nameController.text = name;
  }

  void dispose() {
    nameController.dispose();
  }
}

class _AddEntityDialogState extends State<AddEntityDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final List<_FieldDraft> _fields = [
    _FieldDraft(name: 'id', dataType: 'INTEGER', isPrimaryKey: true, nullable: false),
    _FieldDraft(name: 'name', dataType: 'STRING', isPrimaryKey: false, nullable: false),
  ];

  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    for (var f in _fields) {
      f.dispose();
    }
    super.dispose();
  }

  void _addField() {
    setState(() {
      _fields.add(_FieldDraft(name: '', dataType: 'STRING', isPrimaryKey: false, nullable: true));
    });
  }

  void _removeField(int index) {
    if (_fields.length <= 1) return;
    setState(() {
      final removed = _fields.removeAt(index);
      removed.dispose();
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final fieldPayloads = <Map<String, dynamic>>[];
    for (var f in _fields) {
      final name = f.nameController.text.trim();
      if (name.isEmpty) continue;
      fieldPayloads.add({
        'name': name,
        'data_type': f.dataType,
        'is_primary_key': f.isPrimaryKey,
        'nullable': f.nullable,
      });
    }

    if (fieldPayloads.isEmpty) {
      setState(() => _errorMessage = 'At least one field is required');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final created = await widget.apiClient.createLogicalEntity(
        modelId: widget.modelId,
        name: _nameController.text.trim(),
        description: _descriptionController.text.trim().isEmpty ? null : _descriptionController.text.trim(),
        fields: fieldPayloads,
      );

      if (mounted) {
        Navigator.of(context).pop();
        widget.onEntityCreated(created);
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
    const dataTypes = ['STRING', 'INTEGER', 'FLOAT', 'BOOLEAN', 'DATE', 'TIMESTAMP', 'JSON', 'BINARY'];

    return Dialog(
      backgroundColor: colorScheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 720),
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
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
                    child: Icon(Icons.table_chart_outlined, color: colorScheme.primary, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Add Logical Entity',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        Text(
                          'Define a domain entity and its standard fields.',
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
                        child: Text(
                          _errorMessage!,
                          style: TextStyle(color: colorScheme.error, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Entity Name *',
                  hintText: 'e.g. Student, Course, OrderItem',
                  prefixIcon: Icon(Icons.table_rows_outlined, size: 18),
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) return 'Entity name is required';
                  if (!RegExp(r'^[a-zA-Z0-9_\-]+$').hasMatch(val.trim())) {
                    return 'Alphanumeric and underscores only';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Description (Optional)',
                  hintText: 'Purpose of this logical entity...',
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Logical Fields',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _addField,
                    icon: const Icon(Icons.add, size: 14),
                    label: const Text('Add Field', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.separated(
                  itemCount: _fields.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, idx) {
                    final f = _fields[idx];
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainer,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: TextFormField(
                              controller: f.nameController,
                              style: const TextStyle(fontSize: 13),
                              decoration: const InputDecoration(
                                isDense: true,
                                labelText: 'Field Name',
                                contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              ),
                              validator: (val) {
                                if (val == null || val.trim().isEmpty) return 'Required';
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 2,
                            child: DropdownButtonFormField<String>(
                              initialValue: f.dataType,
                              style: TextStyle(fontSize: 13, color: colorScheme.onSurface),
                              decoration: const InputDecoration(
                                isDense: true,
                                labelText: 'Type',
                                contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              ),
                              items: dataTypes.map((t) => DropdownMenuItem(value: t, child: Text(t, style: const TextStyle(fontSize: 12)))).toList(),
                              onChanged: (val) {
                                if (val != null) setState(() => f.dataType = val);
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Tooltip(
                            message: 'Primary Key',
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Checkbox(
                                  value: f.isPrimaryKey,
                                  onChanged: (val) => setState(() => f.isPrimaryKey = val ?? false),
                                ),
                                const Text('PK', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                          const SizedBox(width: 4),
                          Tooltip(
                            message: 'Nullable',
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Checkbox(
                                  value: f.nullable,
                                  onChanged: (val) => setState(() => f.nullable = val ?? true),
                                ),
                                const Text('Null', style: TextStyle(fontSize: 11)),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: _fields.length > 1 ? () => _removeField(idx) : null,
                            icon: const Icon(Icons.delete_outline, size: 18),
                            color: colorScheme.error,
                          ),
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
                    onPressed: _isSubmitting ? null : _submit,
                    icon: _isSubmitting
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check, size: 16),
                    label: Text(_isSubmitting ? 'Saving...' : 'Add Entity'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
