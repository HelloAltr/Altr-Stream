import 'package:flutter/material.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/models.dart';

class CreateLogicalModelDialog extends StatefulWidget {
  final ApiClient apiClient;
  final ValueChanged<LogicalModelModel> onModelCreated;

  const CreateLogicalModelDialog({
    super.key,
    required this.apiClient,
    required this.onModelCreated,
  });

  @override
  State<CreateLogicalModelDialog> createState() => _CreateLogicalModelDialogState();
}

class _CreateLogicalModelDialogState extends State<CreateLogicalModelDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _versionController = TextEditingController(text: '1.0.0');
  final _descriptionController = TextEditingController();
  final _initialEntityController = TextEditingController();

  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _nameController.dispose();
    _versionController.dispose();
    _descriptionController.dispose();
    _initialEntityController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final entities = <Map<String, dynamic>>[];
      if (_initialEntityController.text.trim().isNotEmpty) {
        entities.add({
          'name': _initialEntityController.text.trim(),
          'description': 'Primary entity for ${_nameController.text.trim()}',
          'fields': [
            {
              'name': 'id',
              'data_type': 'INTEGER',
              'is_primary_key': true,
              'nullable': false,
            },
            {
              'name': 'name',
              'data_type': 'STRING',
              'is_primary_key': false,
              'nullable': false,
            },
          ],
        });
      }

      final created = await widget.apiClient.createLogicalModel(
        name: _nameController.text.trim(),
        version: _versionController.text.trim().isEmpty ? '1.0.0' : _versionController.text.trim(),
        description: _descriptionController.text.trim().isEmpty ? null : _descriptionController.text.trim(),
        entities: entities,
      );

      if (mounted) {
        Navigator.of(context).pop();
        widget.onModelCreated(created);
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
        constraints: const BoxConstraints(maxWidth: 520),
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
                    child: Icon(Icons.schema_outlined, color: colorScheme.primary, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'New Logical Data Model',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        Text(
                          'Define a source-agnostic domain schema and entity contract.',
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
              const SizedBox(height: 20),
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
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: TextFormField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'Model Name *',
                        hintText: 'e.g. CoreCommerce, UnifiedSchool',
                        prefixIcon: Icon(Icons.label_outline, size: 18),
                      ),
                      validator: (val) {
                        if (val == null || val.trim().isEmpty) return 'Model name is required';
                        if (!RegExp(r'^[a-zA-Z0-9_\-]+$').hasMatch(val.trim())) {
                          return 'Alphanumeric, dashes, and underscores only';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: _versionController,
                      decoration: const InputDecoration(
                        labelText: 'Version',
                        hintText: '1.0.0',
                        prefixIcon: Icon(Icons.tag, size: 18),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _descriptionController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Description (Optional)',
                  hintText: 'Brief summary of what this logical domain represents...',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _initialEntityController,
                decoration: const InputDecoration(
                  labelText: 'Initial Entity (Optional)',
                  hintText: 'e.g. Customer, Order, Product',
                  helperText: 'Creates starter entity with id (INTEGER PK) and name (STRING)',
                  prefixIcon: Icon(Icons.table_chart_outlined, size: 18),
                ),
              ),
              const SizedBox(height: 24),
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
                    label: Text(_isSubmitting ? 'Creating...' : 'Create Model'),
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
