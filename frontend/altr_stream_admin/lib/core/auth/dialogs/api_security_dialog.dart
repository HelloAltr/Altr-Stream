import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:material_3_expressive/material_3_expressive.dart';

import '../../api/models.dart';
import '../../config/app_config.dart';
import '../../../shared/dialogs/altr_alert_dialog.dart';
import '../models/altr_api_key.dart';
import '../services/api_key_service.dart';
import 'sudo_verification_dialog.dart';

/// Modal dialog providing full API key security management, key generation, and revocation.
class ApiSecurityDialog extends StatefulWidget {
  final UserProfile? userProfile;

  const ApiSecurityDialog({
    super.key,
    required this.userProfile,
  });

  @override
  State<ApiSecurityDialog> createState() => _ApiSecurityDialogState();
}

class _ApiSecurityDialogState extends State<ApiSecurityDialog> {
  final ApiKeyService _apiKeyService = ApiKeyService();

  bool _isLoading = true;
  AltrApiKey? _justCreatedKey;

  @override
  void initState() {
    super.initState();
    _loadKeys();
  }

  Future<void> _loadKeys() async {
    setState(() => _isLoading = true);
    await _apiKeyService.fetchKeys();
    if (mounted) setState(() => _isLoading = false);
  }

  void _copy(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label copied to clipboard'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _openGenerateKeyModal() async {
    final sudoOk = await SudoVerificationDialog.ensureSudoActive(
      context,
      profile: widget.userProfile,
      actionDescription: 'generate new API keys',
    );
    if (!sudoOk || !mounted) return;

    final nameController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final List<String> selectedScopes = ['read', 'write'];
    int? expiresInDays = 30;
    bool isCustomExpiration = false;
    DateTime? customExpiresAt;

    final created = await showDialog<AltrApiKey?>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          final theme = Theme.of(context);

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('Generate New API Key'),
            content: SizedBox(
              width: 400,
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextFormField(
                      controller: nameController,
                      autofocus: true,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Key label is required';
                        }
                        return null;
                      },
                      decoration: InputDecoration(
                        labelText: 'Key Label / Integration Name',
                        hintText: 'e.g. CLI Sync Pipeline',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        errorBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: theme.colorScheme.error, width: 1.5),
                        ),
                        focusedErrorBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: theme.colorScheme.error, width: 2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text('Permission Scopes:', style: theme.textTheme.labelMedium),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      children: ['read', 'write', 'admin'].map((scope) {
                        final isSelected = selectedScopes.contains(scope);
                        return FilterChip(
                          label: Text(scope.toUpperCase()),
                          selected: isSelected,
                          onSelected: (selected) {
                            setModalState(() {
                              if (selected) {
                                selectedScopes.add(scope);
                              } else {
                                selectedScopes.remove(scope);
                              }
                            });
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                    Text('Expiration:', style: theme.textTheme.labelMedium),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      initialValue: isCustomExpiration
                          ? 'custom'
                          : (expiresInDays == null ? 'never' : expiresInDays.toString()),
                      decoration: InputDecoration(
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      items: const [
                        DropdownMenuItem(value: '7', child: Text('7 Days')),
                        DropdownMenuItem(value: '30', child: Text('30 Days')),
                        DropdownMenuItem(value: '90', child: Text('90 Days')),
                        DropdownMenuItem(value: 'never', child: Text('Never (Permanent)')),
                        DropdownMenuItem(value: 'custom', child: Text('Custom Date & Time...')),
                      ],
                      onChanged: (val) {
                        setModalState(() {
                          if (val == 'custom') {
                            isCustomExpiration = true;
                            expiresInDays = null;
                            customExpiresAt ??= DateTime.now().add(const Duration(days: 14));
                          } else if (val == 'never') {
                            isCustomExpiration = false;
                            expiresInDays = null;
                          } else {
                            isCustomExpiration = false;
                            expiresInDays = int.tryParse(val ?? '30');
                          }
                        });
                      },
                    ),
                    if (isCustomExpiration) ...[
                      const SizedBox(height: 10),
                      InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () async {
                          final now = DateTime.now();
                          final pickedDate = await showDatePicker(
                            context: context,
                            initialDate: customExpiresAt ?? now.add(const Duration(days: 7)),
                            firstDate: now,
                            lastDate: now.add(const Duration(days: 3650)),
                          );
                          if (pickedDate == null || !context.mounted) return;
                          final pickedTime = await showTimePicker(
                            context: context,
                            initialTime: TimeOfDay.fromDateTime(customExpiresAt ?? now),
                          );
                          final finalTime = pickedTime ?? const TimeOfDay(hour: 23, minute: 59);
                          setModalState(() {
                            customExpiresAt = DateTime(
                              pickedDate.year,
                              pickedDate.month,
                              pickedDate.day,
                              finalTime.hour,
                              finalTime.minute,
                            );
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            border: Border.all(color: theme.colorScheme.outlineVariant),
                            borderRadius: BorderRadius.circular(8),
                            color: theme.colorScheme.surfaceContainerLow,
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.calendar_month_outlined, size: 18, color: theme.colorScheme.primary),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  customExpiresAt != null
                                      ? '${customExpiresAt!.toLocal().year}-${customExpiresAt!.toLocal().month.toString().padLeft(2, '0')}-${customExpiresAt!.toLocal().day.toString().padLeft(2, '0')} ${customExpiresAt!.toLocal().hour.toString().padLeft(2, '0')}:${customExpiresAt!.toLocal().minute.toString().padLeft(2, '0')}'
                                      : 'Select Expiration Date & Time',
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                                ),
                              ),
                              Icon(Icons.edit_calendar_outlined, size: 16, color: theme.colorScheme.onSurfaceVariant),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              M3EButton(
                style: M3EButtonStyle.text,
                onPressed: () => Navigator.of(ctx).pop(null),
                child: const Text('Cancel'),
              ),
              M3EButton(
                style: M3EButtonStyle.filled,
                onPressed: () async {
                  if (!formKey.currentState!.validate()) {
                    return;
                  }
                  final name = nameController.text.trim();

                  final key = await _apiKeyService.createKey(
                    name: name,
                    scopes: selectedScopes,
                    expiresInDays: isCustomExpiration ? null : expiresInDays,
                    expiresAt: isCustomExpiration ? customExpiresAt : null,
                  );
                  if (ctx.mounted) Navigator.of(ctx).pop(key);
                },
                child: const Text('Generate Key'),
              ),
            ],
          );
        },
      ),
    );

    if (created != null && mounted) {
      setState(() {
        _justCreatedKey = created;
      });
    }
  }

  Future<void> _revokeKey(AltrApiKey key) async {
    final sudoOk = await SudoVerificationDialog.ensureSudoActive(
      context,
      profile: widget.userProfile,
      actionDescription: 'revoke API key "${key.name}"',
    );
    if (!sudoOk || !mounted) return;

    final colorScheme = Theme.of(context).colorScheme;
    final confirmed = await AltrAlert.show(
      context,
      icon: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: colorScheme.errorContainer.withValues(alpha: 0.5),
          shape: BoxShape.circle,
        ),
        child: HugeIcon(
          icon: HugeIcons.strokeRoundedAlert02,
          color: colorScheme.error,
          size: 26,
        ),
      ),
      title: 'Revoke API Key?',
      message:
          'Are you sure you want to permanently revoke "${key.name}" (${key.keyPrefix}...)? Any clients using this key will immediately lose access.',
      cancelLabel: 'Cancel',
      confirmLabel: 'Revoke',
      isDestructive: true,
    );

    if (confirmed == true) {
      await _apiKeyService.revokeKey(key.id);
      await _loadKeys();
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('API Key "${key.name}" revoked.'),
            backgroundColor: colorScheme.error,
          ),
        );
      }
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
        constraints: const BoxConstraints(maxWidth: 700, maxHeight: 680),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: HugeIcon(
                      icon: HugeIcons.strokeRoundedShieldCheck,
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
                          'API & Security Settings',
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'Manage authentication tokens for programmatic access to Altr Stream',
                          style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Just Created One-Time Key Banner
              if (_justCreatedKey != null && _justCreatedKey!.fullKey != null) ...[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: colorScheme.primary),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            'Copy your new API Key now. It will never be shown again!',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              color: colorScheme.onSurface,
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            icon: const Icon(Icons.close, size: 16),
                            onPressed: () => setState(() => _justCreatedKey = null),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: colorScheme.surface,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: SelectableText(
                                _justCreatedKey!.fullKey!,
                                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.copy, size: 16),
                              onPressed: () => _copy(_justCreatedKey!.fullKey!, 'API Key'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Controls row
              Builder(
                builder: (context) {
                  final activeKeys = _apiKeyService.keys.where((k) => k.isActive).toList();
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Active API Keys (${activeKeys.length})',
                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      FilledButton.icon(
                        onPressed: _openGenerateKeyModal,
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('Generate New Key'),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 12),

              // Keys List
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : Builder(
                        builder: (context) {
                          final activeKeys = _apiKeyService.keys.where((k) => k.isActive).toList();
                          if (activeKeys.isEmpty) {
                            return Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  HugeIcon(
                                    icon: HugeIcons.strokeRoundedKey01,
                                    color: colorScheme.outline,
                                    size: 40,
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    'No API keys generated yet',
                                    style: TextStyle(color: colorScheme.onSurfaceVariant),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Generate a key to securely query or ingest data via external clients.',
                                    style: TextStyle(fontSize: 12, color: colorScheme.outline),
                                  ),
                                ],
                              ),
                            );
                          }
                          return ListView.separated(
                            itemCount: activeKeys.length,
                            separatorBuilder: (_, _) => const Divider(height: 1),
                            itemBuilder: (ctx, index) {
                              final key = activeKeys[index];
                              return ListTile(
                                leading: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: colorScheme.surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: HugeIcon(
                                    icon: HugeIcons.strokeRoundedKey01,
                                    color: colorScheme.primary,
                                    size: 18,
                                  ),
                                ),
                                title: Row(
                                  children: [
                                    Text(key.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: colorScheme.surfaceContainerHighest,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        '${key.keyPrefix}••••',
                                        style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                                      ),
                                    ),
                                  ],
                                ),
                                subtitle: Text(
                                  'Scopes: ${key.scopes.join(', ')} · Created: ${key.createdAt.toLocal().toString().substring(0, 10)}',
                                  style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                                ),
                                trailing: IconButton(
                                  tooltip: 'Revoke Key',
                                  icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                                  onPressed: () => _revokeKey(key),
                                ),
                              );
                            },
                          );
                        },
                      ),
              ),

              const SizedBox(height: 12),
              // Node Authentication Header Note
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                ),
                child: Row(
                  children: [
                    HugeIcon(icon: HugeIcons.strokeRoundedInformationCircle, color: colorScheme.primary, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Include header "X-Altr-API-Key: <key>" or "Authorization: Bearer <key>" in your HTTP requests to ${AppConfig.apiBaseUrl}.',
                        style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
