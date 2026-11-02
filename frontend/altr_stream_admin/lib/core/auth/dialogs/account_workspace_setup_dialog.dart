import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../api/models.dart';
import '../models/workspace.dart';
import '../services/auth_service.dart';
import '../services/passcode_service.dart';
import '../services/workspace_service.dart';

/// Modal dialog presented upon initial login if no account or workspace data exists in Firestore.
/// It collects profile details, creates a primary workspace, and persists both records to Firestore.
class AccountWorkspaceSetupDialog extends StatefulWidget {
  final String userId;
  final String initialEmail;
  final String initialDisplayName;
  final String? initialPhotoUrl;
  final Future<void> Function(UserProfile profile, Workspace workspace)? onSetupComplete;

  const AccountWorkspaceSetupDialog({
    super.key,
    required this.userId,
    required this.initialEmail,
    required this.initialDisplayName,
    this.initialPhotoUrl,
    this.onSetupComplete,
  });

  @override
  State<AccountWorkspaceSetupDialog> createState() => _AccountWorkspaceSetupDialogState();
}

class _AccountWorkspaceSetupDialogState extends State<AccountWorkspaceSetupDialog> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;
  late final TextEditingController _emailController;
  late final TextEditingController _roleController;
  late final TextEditingController _workspaceNameController;
  late final TextEditingController _workspaceSlugController;

  bool _enableChat = false;
  bool _isSaving = false;
  String? _errorMessage;

  final List<String> _commonRoles = [
    'Workspace Owner & Administrator',
    'Lead Data Engineer',
    'Software Engineer',
    'Data Architect',
    'DevOps / SRE',
    'Business / Data Analyst',
  ];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.initialDisplayName.isNotEmpty ? widget.initialDisplayName : 'Altr Developer',
    );
    _emailController = TextEditingController(text: widget.initialEmail);
    _roleController = TextEditingController(text: _commonRoles.first);
    _workspaceNameController = TextEditingController(text: 'Primary Workspace');
    _workspaceSlugController = TextEditingController(text: 'primary-workspace');

    _workspaceNameController.addListener(_autoUpdateSlug);
  }

  void _autoUpdateSlug() {
    final name = _workspaceNameController.text.trim();
    if (name.isNotEmpty) {
      final slug = name
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
          .replaceAll(RegExp(r'^-+|-+$'), '');
      _workspaceSlugController.text = slug;
    }
  }

  @override
  void dispose() {
    _workspaceNameController.removeListener(_autoUpdateSlug);
    _nameController.dispose();
    _emailController.dispose();
    _roleController.dispose();
    _workspaceNameController.dispose();
    _workspaceSlugController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final role = _roleController.text.trim();
    final wsName = _workspaceNameController.text.trim();
    var wsSlug = _workspaceSlugController.text.trim();
    if (wsSlug.isEmpty) {
      wsSlug = 'workspace-${DateTime.now().millisecondsSinceEpoch % 10000}';
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final fs = FirebaseFirestore.instance;

      // Ensure Firebase Auth session exists so Firestore rules allow the write
      try {
        if (FirebaseAuth.instance.currentUser == null) {
          await FirebaseAuth.instance.signInAnonymously();
        }
      } catch (authErr) {
        debugPrint('[AccountSetupDialog] Anonymous auth fallback notice: $authErr');
      }

      // 1. Generate and persist Workspace document
      final wsRef = fs.collection('workspaces').doc();
      final wsId = wsRef.id;
      final now = DateTime.now();
      final enabledServices = <String>['altr_stream'];
      if (_enableChat) enabledServices.add('altr_chat');

      final wsData = <String, dynamic>{
        'name': wsName,
        'slug': wsSlug,
        'owner_id': widget.userId,
        'member_uids': [widget.userId],
        'admin_uids': [widget.userId],
        'enabled_services': enabledServices,
        'created_at': FieldValue.serverTimestamp(),
        'members': {
          widget.userId: {
            'email': email,
            'display_name': name,
            'role': 'owner',
            'title': role,
            'joined_at': FieldValue.serverTimestamp(),
          },
        },
      };

      await wsRef.set(wsData);
      debugPrint('[AccountSetupDialog] Created workspace in Firestore: $wsId');

      // 2. Persist User document
      final userRef = fs.collection('users').doc(widget.userId);
      final existingPasscodeType = PasscodeService().getCredentialType(widget.userId, email) ?? 'pin';

      final userData = <String, dynamic>{
        'email': email,
        'display_name': name,
        'role': role,
        'photo_url': widget.initialPhotoUrl,
        'default_workspace_id': wsId,
        'workspace_ids': [wsId],
        'passcode_type': existingPasscodeType,
        'created_at': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
      };

      await userRef.set(userData, SetOptions(merge: true));
      debugPrint('[AccountSetupDialog] Created user in Firestore: ${widget.userId}');

      final workspace = Workspace(
        id: wsId,
        name: wsName,
        ownerId: widget.userId,
        memberUids: [widget.userId],
        adminUids: [widget.userId],
        enabledServices: enabledServices,
        members: {
          widget.userId: WorkspaceMember(
            email: email,
            displayName: name,
            role: 'owner',
            joinedAt: now,
          ),
        },
        createdAt: now,
      );

      final userProfile = UserProfile(
        id: widget.userId,
        email: email,
        displayName: name,
        photoUrl: widget.initialPhotoUrl,
        defaultWorkspaceId: wsId,
        workspaceIds: [wsId],
        passcodeType: existingPasscodeType,
      );

      AuthService().setProfileDirect(userProfile);
      await WorkspaceService().fetchUserWorkspaces(widget.userId, workspaceIds: [wsId]);

      if (widget.onSetupComplete != null) {
        await widget.onSetupComplete!(userProfile, workspace);
      }

      if (mounted) {
        Navigator.of(context).pop(userProfile);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Account & Workspace "$wsName" saved to Firebase!'),
            backgroundColor: Theme.of(context).colorScheme.primary,
          ),
        );
      }
    } catch (e) {
      debugPrint('[AccountSetupDialog] Error saving account and workspace: $e');
      if (mounted) {
        setState(() {
          _isSaving = false;
          _errorMessage = 'Failed to save to Firebase: $e';
        });
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
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
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
                        icon: HugeIcons.strokeRoundedUserSharing,
                        color: colorScheme.onPrimaryContainer,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Account & Workspace Setup',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Initialize your Altr profile and cloud workspace in Firebase',
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

                // Form Scrollable Body
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // SECTION 1: Account Information
                        Row(
                          children: [
                            HugeIcon(icon: HugeIcons.strokeRoundedUser, size: 16, color: colorScheme.primary),
                            const SizedBox(width: 8),
                            Text(
                              'Profile Details',
                              style: theme.textTheme.labelLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _nameController,
                          decoration: InputDecoration(
                            labelText: 'Full Name *',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            prefixIcon: const Icon(Icons.badge_outlined, size: 20),
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter your name.' : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _emailController,
                          readOnly: true,
                          decoration: InputDecoration(
                            labelText: 'Email Address',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            prefixIcon: const Icon(Icons.email_outlined, size: 20),
                            filled: true,
                            fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                          ),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: _roleController.text,
                          decoration: InputDecoration(
                            labelText: 'Role / Title',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            prefixIcon: const Icon(Icons.work_outline, size: 20),
                          ),
                          items: _commonRoles.map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
                          onChanged: (val) {
                            if (val != null) _roleController.text = val;
                          },
                        ),
                        const SizedBox(height: 24),
                        const Divider(),
                        const SizedBox(height: 16),

                        // SECTION 2: Workspace Information
                        Row(
                          children: [
                            HugeIcon(icon: HugeIcons.strokeRoundedFolder01, size: 16, color: colorScheme.secondary),
                            const SizedBox(width: 8),
                            Text(
                              'Primary Workspace',
                              style: theme.textTheme.labelLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: colorScheme.secondary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _workspaceNameController,
                          decoration: InputDecoration(
                            labelText: 'Workspace Name *',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            prefixIcon: const Icon(Icons.business_outlined, size: 20),
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter a workspace name.' : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _workspaceSlugController,
                          decoration: InputDecoration(
                            labelText: 'Workspace Slug / Identifier',
                            helperText: 'Unique identifier used for routing and federation',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            prefixIcon: const Icon(Icons.tag, size: 20),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Services
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Enabled Services',
                                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: colorScheme.onSurface),
                              ),
                              const SizedBox(height: 8),
                              CheckboxListTile(
                                value: true,
                                onChanged: null, // Always enabled
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                title: const Text('Altr Stream (Core Data Engine)', style: TextStyle(fontWeight: FontWeight.w500)),
                                subtitle: const Text('Streaming federation, physical query execution & schema mapping', style: TextStyle(fontSize: 11)),
                              ),
                              CheckboxListTile(
                                value: _enableChat,
                                onChanged: (val) => setState(() => _enableChat = val ?? false),
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                title: const Text('Altr Chat (Mesh Integration)', style: TextStyle(fontWeight: FontWeight.w500)),
                                subtitle: const Text('Real-time team collaboration and bot query channels', style: TextStyle(fontSize: 11)),
                              ),
                            ],
                          ),
                        ),

                        if (_errorMessage != null) ...[
                          const SizedBox(height: 14),
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: colorScheme.errorContainer.withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.error_outline, color: colorScheme.error, size: 18),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _errorMessage!,
                                    style: TextStyle(color: colorScheme.error, fontSize: 12),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 20),
                // Footer
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      onPressed: _isSaving ? null : _submit,
                      icon: _isSaving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.cloud_done_outlined, size: 18),
                      label: Text(_isSaving ? 'Saving to Firebase...' : 'Save & Complete Setup'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
