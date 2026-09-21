import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
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
      final name = _nameController.text.trim();
      final version = _versionController.text.trim().isEmpty ? '1.0.0' : _versionController.text.trim();
      final description = _descriptionController.text.trim().isEmpty ? null : _descriptionController.text.trim();

      // 1. Create Logical Model
      final model = await widget.apiClient.createLogicalModel(
        name: name,
        version: version,
        description: description,
      );

      // 2. Optionally create initial entity if specified
      final initialEntityName = _initialEntityController.text.trim();
      if (initialEntityName.isNotEmpty) {
        try {
          final entity = await widget.apiClient.createLogicalEntity(
            modelId: model.id,
            name: initialEntityName,
            description: 'Starter entity for $name',
          );

          // Add standard default fields: id (INTEGER, PK), name (STRING)
          await widget.apiClient.createLogicalField(
            entityId: entity.id,
            name: 'id',
            dataType: 'INTEGER',
            nullable: false,
            isPrimaryKey: true,
            description: 'Primary identifier',
          );
          await widget.apiClient.createLogicalField(
            entityId: entity.id,
            name: 'name',
            dataType: 'STRING',
            nullable: true,
            isPrimaryKey: false,
            description: 'Display name',
          );
        } catch (_) {
          // Non-critical: model was created, initial entity creation best-effort
        }
      }

      if (mounted) {
        Navigator.of(context).pop();
        widget.onModelCreated(model);
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
                    child: HugeIcon(icon: HugeIcons.strokeRoundedStructure01, color: colorScheme.primary, size: 20),
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
                    icon: const HugeIcon(icon: HugeIcons.strokeRoundedCancel01, size: 18),
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
                      HugeIcon(icon: HugeIcons.strokeRoundedAlertCircle, color: colorScheme.error, size: 18),
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
                        prefixIcon: HugeIcon(icon: HugeIcons.strokeRoundedTag01, size: 18),
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
                        prefixIcon: HugeIcon(icon: HugeIcons.strokeRoundedTag01, size: 18),
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
                  prefixIcon: HugeIcon(icon: HugeIcons.strokeRoundedTable01, size: 18),
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
                        : const HugeIcon(icon: HugeIcons.strokeRoundedCheckmarkBadge01, size: 16),
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
