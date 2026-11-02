import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../api/models.dart';
import '../../../../shared/dialogs/altr_alert_dialog.dart';
import '../services/passcode_service.dart';
import 'passcode_setup_dialog.dart';

/// Modal dialog requiring the user to verify their passcode to enter Sudo mode.
class SudoVerificationDialog extends StatefulWidget {
  final UserProfile profile;
  final String actionDescription;

  const SudoVerificationDialog({
    super.key,
    required this.profile,
    this.actionDescription = 'perform this sensitive action',
  });

  /// Check whether Sudo mode is active. If not, prompts for verification.
  static Future<bool> ensureSudoActive(
    BuildContext context, {
    required UserProfile? profile,
    String actionDescription = 'perform this sensitive action',
  }) async {
    final passcodeService = PasscodeService();
    if (passcodeService.isSudoActive) {
      return true; // Already elevated in 5-minute grace period
    }

    final effectiveProfile = profile ?? const UserProfile(
      id: 'local_admin',
      displayName: 'Local Admin',
      email: 'admin@localhost',
    );

    if (!passcodeService.hasConfiguredPasscode(effectiveProfile)) {
      // Prompt user to configure passcode first
      final shouldConfigure = await AltrAlert.show(
        context,
        icon: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.5),
            shape: BoxShape.circle,
          ),
          child: HugeIcon(
            icon: HugeIcons.strokeRoundedLockPassword,
            color: Theme.of(context).colorScheme.primary,
            size: 26,
          ),
        ),
        title: 'Configure Security Passcode',
        message:
            'To $actionDescription, please configure an Altr Account passcode (PIN or Password).',
        cancelLabel: 'Cancel',
        confirmLabel: 'Configure Passcode',
        isDestructive: false,
      );

      if (shouldConfigure == true && context.mounted) {
        final configured = await showDialog<bool>(
          context: context,
          builder: (ctx) => PasscodeSetupDialog(
            userId: effectiveProfile.id,
            userProfile: effectiveProfile,
          ),
        );
        return configured == true;
      }
      return false;
    }

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => SudoVerificationDialog(
        profile: effectiveProfile,
        actionDescription: actionDescription,
      ),
    );

    return result == true;
  }

  @override
  State<SudoVerificationDialog> createState() => _SudoVerificationDialogState();
}

class _SudoVerificationDialogState extends State<SudoVerificationDialog> {
  final PasscodeService _passcodeService = PasscodeService();
  final TextEditingController _passcodeController = TextEditingController();

  bool _obscureText = true;
  bool _isVerifying = false;
  String? _errorMessage;

  @override
  void dispose() {
    _passcodeController.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final entered = _passcodeController.text.trim();
    if (entered.isEmpty) return;

    setState(() {
      _isVerifying = true;
      _errorMessage = null;
    });

    final success = await _passcodeService.verifyPasscode(
      profile: widget.profile,
      enteredPasscode: entered,
    );

    if (!mounted) return;

    if (success) {
      Navigator.of(context).pop(true);
    } else {
      final isConfigured = _passcodeService.hasConfiguredPasscode(widget.profile);
      setState(() {
        _isVerifying = false;
        _errorMessage = isConfigured
            ? 'Incorrect passcode. Please try again.'
            : 'No passcode configured yet. Please configure a PIN or Password first.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isPin = widget.profile.passcodeType == 'pin';

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: colorScheme.surface,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
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
                      color: Colors.amber.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const HugeIcon(
                      icon: HugeIcons.strokeRoundedSecurityLock,
                      color: Colors.amber,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Sudo Authentication',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '5-minute elevated session',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                'Please enter your Altr ${isPin ? '6-digit PIN' : 'password'} to ${widget.actionDescription}.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passcodeController,
                obscureText: _obscureText,
                autofocus: true,
                keyboardType: isPin ? TextInputType.number : TextInputType.text,
                maxLength: isPin ? 6 : 32,
                onSubmitted: (_) => _verify(),
                decoration: InputDecoration(
                  labelText: isPin ? 'PIN' : 'Password',
                  counterText: '',
                  prefixIcon: HugeIcon(
                    icon: isPin ? HugeIcons.strokeRoundedKey01 : HugeIcons.strokeRoundedLockPassword,
                    color: colorScheme.outline,
                    size: 18,
                  ),
                  suffixIcon: IconButton(
                    icon: Icon(_obscureText ? Icons.visibility_off : Icons.visibility, size: 18),
                    onPressed: () => setState(() => _obscureText = !_obscureText),
                  ),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 10),
                Text(
                  _errorMessage!,
                  style: TextStyle(color: colorScheme.error, fontSize: 12),
                ),
              ],
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _isVerifying ? null : _verify,
                    child: _isVerifying
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Unlock Sudo'),
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
