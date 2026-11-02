import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import '../services/workspace_service.dart';

/// Dialog to create a new Altr Mesh Workspace.
class CreateWorkspaceDialog extends StatefulWidget {
  final String ownerUid;
  final String ownerEmail;
  final String ownerDisplayName;

  const CreateWorkspaceDialog({
    super.key,
    required this.ownerUid,
    required this.ownerEmail,
    required this.ownerDisplayName,
  });

  @override
  State<CreateWorkspaceDialog> createState() => _CreateWorkspaceDialogState();
}

class _CreateWorkspaceDialogState extends State<CreateWorkspaceDialog> {
  final WorkspaceService _workspaceService = WorkspaceService();
  final TextEditingController _nameController = TextEditingController();

  bool _enableChat = false;
  bool _isCreating = false;
  String? _errorMessage;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _errorMessage = 'Please enter a workspace name.');
      return;
    }

    setState(() {
      _isCreating = true;
      _errorMessage = null;
    });

    final enabledServices = <String>['altr_stream'];
    if (_enableChat) enabledServices.add('altr_chat');

    final ws = await _workspaceService.createWorkspace(
      name: name,
      ownerUid: widget.ownerUid,
      ownerEmail: widget.ownerEmail,
      ownerDisplayName: widget.ownerDisplayName,
      enabledServices: enabledServices,
    );

    if (!mounted) return;

    if (ws != null) {
      Navigator.of(context).pop(ws);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Workspace "${ws.name}" created!'),
          backgroundColor: Theme.of(context).colorScheme.primary,
        ),
      );
    } else {
      setState(() {
        _isCreating = false;
        _errorMessage = 'Failed to create workspace. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: colorScheme.surface,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: HugeIcon(
                      icon: HugeIcons.strokeRoundedGrid,
                      color: colorScheme.onPrimaryContainer,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Create New Workspace',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Shared across Altr Mesh products',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _nameController,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Workspace Name',
                  hintText: 'e.g. Production Data Mesh',
                  prefixIcon: HugeIcon(
                    icon: HugeIcons.strokeRoundedBuilding03,
                    color: colorScheme.outline,
                    size: 18,
                  ),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Enabled Altr Mesh Services:',
                style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                ),
                child: Column(
                  children: [
                    CheckboxListTile(
                      value: true,
                      onChanged: null, // Always enabled
                      title: const Text('Altr Stream (Core CDC & Metadata)'),
                      subtitle: const Text('Always enabled for stream nodes'),
                      secondary: HugeIcon(
                        icon: HugeIcons.strokeRoundedDatabaseSync01,
                        color: colorScheme.primary,
                        size: 20,
                      ),
                    ),
                    const Divider(height: 1),
                    CheckboxListTile(
                      value: _enableChat,
                      onChanged: (val) => setState(() => _enableChat = val ?? false),
                      title: const Text('Altr Chat (Collaborative AI & Mesh)'),
                      subtitle: const Text('Optional AI chat integration'),
                      secondary: HugeIcon(
                        icon: HugeIcons.strokeRoundedBubbleChat,
                        color: _enableChat ? colorScheme.primary : colorScheme.outline,
                        size: 20,
                      ),
                    ),
                  ],
                ),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 10),
                Text(_errorMessage!, style: TextStyle(color: colorScheme.error, fontSize: 12)),
              ],
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _isCreating ? null : _submit,
                    child: _isCreating
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Create Workspace'),
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
