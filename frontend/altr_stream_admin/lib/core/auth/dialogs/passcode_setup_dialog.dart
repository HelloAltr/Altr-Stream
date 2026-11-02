import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../api/models.dart';
import '../services/auth_service.dart';
import '../services/passcode_service.dart';

/// Modal dialog allowing the user to configure or change their Altr Passcode (PIN or Password).
/// When modifying an existing passcode, it strictly verifies the current passcode first.
class PasscodeSetupDialog extends StatefulWidget {
  final String userId;
  final UserProfile? userProfile;
  final String initialType;
  final VoidCallback? onConfigured;

  const PasscodeSetupDialog({
    super.key,
    required this.userId,
    this.userProfile,
    this.initialType = 'pin',
    this.onConfigured,
  });

  @override
  State<PasscodeSetupDialog> createState() => _PasscodeSetupDialogState();
}

class _PasscodeSetupDialogState extends State<PasscodeSetupDialog> {
  final PasscodeService _passcodeService = PasscodeService();

  late String _selectedType;
  late bool _isChangeMode;
  late String _existingType;

  final TextEditingController _currentPasscodeController = TextEditingController();
  final TextEditingController _passcodeController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();

  bool _obscureCurrent = true;
  bool _obscurePasscode = true;
  bool _obscureConfirm = true;
  bool _isSaving = false;
  String? _errorMessage;

  UserProfile get _effectiveProfile =>
      widget.userProfile ??
      AuthService().currentProfile ??
      UserProfile(id: widget.userId, displayName: '', email: '');

  @override
  void initState() {
    super.initState();
    final profile = _effectiveProfile;
    _isChangeMode = _passcodeService.hasConfiguredPasscode(profile);
    _existingType = profile.passcodeType.isNotEmpty
        ? profile.passcodeType
        : (_passcodeService.getCredentialType(profile.id) ?? 'pin');
    _selectedType = _isChangeMode ? _existingType : widget.initialType;
  }

  @override
  void dispose() {
    _currentPasscodeController.dispose();
    _passcodeController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final passcode = _passcodeController.text.trim();
    final confirm = _confirmController.text.trim();

    setState(() {
      _errorMessage = null;
    });

    if (_isChangeMode) {
      final current = _currentPasscodeController.text.trim();
      if (current.isEmpty) {
        setState(() {
          _errorMessage = 'Please enter your current ${_existingType == 'pin' ? 'PIN' : 'password'}.';
        });
        return;
      }
      final matches = _passcodeService.checkPasscodeMatch(
        profile: _effectiveProfile,
        enteredPasscode: current,
      );
      if (!matches) {
        setState(() {
          _errorMessage = 'Incorrect current ${_existingType == 'pin' ? 'PIN' : 'password'}.';
        });
        return;
      }
    }

    if (_selectedType == 'pin') {
      if (passcode.length != 6 || int.tryParse(passcode) == null) {
        setState(() {
          _errorMessage = 'New PIN must be exactly 6 numeric digits.';
        });
        return;
      }
    } else {
      if (passcode.length < 8) {
        setState(() {
          _errorMessage = 'New password must be at least 8 characters.';
        });
        return;
      }
    }

    if (passcode != confirm) {
      setState(() {
        _errorMessage = 'Passcodes do not match.';
      });
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      await _passcodeService.setupPasscode(
        userId: widget.userId,
        passcode: passcode,
        passcodeType: _selectedType,
      );

      widget.onConfigured?.call();
      if (mounted) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${_selectedType == 'pin' ? 'PIN' : 'Password'} ${_isChangeMode ? 'changed' : 'configured'} successfully. Sudo mode activated for 5 minutes.',
            ),
            backgroundColor: Theme.of(context).colorScheme.primary,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to configure passcode: $e';
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isPin = _selectedType == 'pin';

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
                      icon: HugeIcons.strokeRoundedSecurityLock,
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
                          _isChangeMode ? 'Change Altr Passcode' : 'Configure Altr Passcode',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          _isChangeMode
                              ? 'Verify current passcode before saving updates'
                              : 'Secure access to API keys & sensitive settings',
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

              // Current Passcode verification section if changing
              if (_isChangeMode) ...[
                Text(
                  'Verify Current ${_existingType == 'pin' ? 'PIN' : 'Password'}:',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _currentPasscodeController,
                  obscureText: _obscureCurrent,
                  keyboardType: _existingType == 'pin' ? TextInputType.number : TextInputType.text,
                  maxLength: _existingType == 'pin' ? 6 : 32,
                  decoration: InputDecoration(
                    labelText: _existingType == 'pin' ? 'Current 6-Digit PIN' : 'Current Password',
                    counterText: '',
                    prefixIcon: HugeIcon(
                      icon: _existingType == 'pin' ? HugeIcons.strokeRoundedKey01 : HugeIcons.strokeRoundedLockPassword,
                      color: colorScheme.outline,
                      size: 18,
                    ),
                    suffixIcon: IconButton(
                      icon: Icon(_obscureCurrent ? Icons.visibility_off : Icons.visibility, size: 18),
                      onPressed: () => setState(() => _obscureCurrent = !_obscureCurrent),
                    ),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 12),
              ],

              Text(
                _isChangeMode ? 'Choose new passcode type:' : 'Choose your passcode type:',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () {
                        setState(() {
                          _selectedType = 'pin';
                          _passcodeController.clear();
                          _confirmController.clear();
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
                        decoration: BoxDecoration(
                          color: isPin
                              ? colorScheme.primaryContainer
                              : colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isPin
                                ? colorScheme.primary
                                : colorScheme.outlineVariant.withValues(alpha: 0.5),
                            width: 1.5,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            HugeIcon(
                              icon: HugeIcons.strokeRoundedKey01,
                              color: isPin ? colorScheme.onPrimaryContainer : colorScheme.onSurface,
                              size: 16,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '6-Digit PIN',
                              style: TextStyle(
                                fontWeight: isPin ? FontWeight.bold : FontWeight.normal,
                                color: isPin ? colorScheme.onPrimaryContainer : colorScheme.onSurface,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () {
                        setState(() {
                          _selectedType = 'password';
                          _passcodeController.clear();
                          _confirmController.clear();
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
                        decoration: BoxDecoration(
                          color: !isPin
                              ? colorScheme.primaryContainer
                              : colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: !isPin
                                ? colorScheme.primary
                                : colorScheme.outlineVariant.withValues(alpha: 0.5),
                            width: 1.5,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            HugeIcon(
                              icon: HugeIcons.strokeRoundedLockPassword,
                              color: !isPin ? colorScheme.onPrimaryContainer : colorScheme.onSurface,
                              size: 16,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Password',
                              style: TextStyle(
                                fontWeight: !isPin ? FontWeight.bold : FontWeight.normal,
                                color: !isPin ? colorScheme.onPrimaryContainer : colorScheme.onSurface,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              TextField(
                controller: _passcodeController,
                obscureText: _obscurePasscode,
                keyboardType: isPin ? TextInputType.number : TextInputType.text,
                maxLength: isPin ? 6 : 32,
                decoration: InputDecoration(
                  labelText: isPin
                      ? (_isChangeMode ? 'Enter New 6-Digit PIN' : 'Enter 6-Digit PIN')
                      : (_isChangeMode ? 'Enter New Password (min 8 chars)' : 'Enter Password (min 8 chars)'),
                  counterText: '',
                  prefixIcon: HugeIcon(
                    icon: isPin ? HugeIcons.strokeRoundedKey01 : HugeIcons.strokeRoundedLockPassword,
                    color: colorScheme.outline,
                    size: 18,
                  ),
                  suffixIcon: IconButton(
                    icon: Icon(_obscurePasscode ? Icons.visibility_off : Icons.visibility, size: 18),
                    onPressed: () => setState(() => _obscurePasscode = !_obscurePasscode),
                  ),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _confirmController,
                obscureText: _obscureConfirm,
                keyboardType: isPin ? TextInputType.number : TextInputType.text,
                maxLength: isPin ? 6 : 32,
                decoration: InputDecoration(
                  labelText: isPin
                      ? (_isChangeMode ? 'Confirm New 6-Digit PIN' : 'Confirm 6-Digit PIN')
                      : (_isChangeMode ? 'Confirm New Password' : 'Confirm Password'),
                  counterText: '',
                  prefixIcon: const Icon(Icons.check_circle_outline, size: 18),
                  suffixIcon: IconButton(
                    icon: Icon(_obscureConfirm ? Icons.visibility_off : Icons.visibility, size: 18),
                    onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
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
                    onPressed: _isSaving ? null : _submit,
                    child: _isSaving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(_isChangeMode ? 'Update Passcode' : 'Save & Activate Sudo'),
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
