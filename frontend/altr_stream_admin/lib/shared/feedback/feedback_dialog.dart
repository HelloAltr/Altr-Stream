import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/api/api_client.dart';
import '../../core/config/app_config.dart';

/// Reusable user feedback dialog that submits structured GitHub issues via backend.
class FeedbackDialog extends StatefulWidget {
  final ApiClient? apiClient;

  const FeedbackDialog({super.key, this.apiClient});

  /// Convenient helper to display the modal dialog.
  static Future<void> show(BuildContext context, {ApiClient? apiClient}) {
    return M3EDialog.show<void>(
      context,
      barrierDismissible: true,
      dialog: FeedbackDialog(apiClient: apiClient),
    );
  }

  @override
  State<FeedbackDialog> createState() => _FeedbackDialogState();
}

class _FeedbackDialogState extends State<FeedbackDialog> {
  final _formKey = GlobalKey<FormState>();
  final _summaryController = TextEditingController();
  final _messageController = TextEditingController();
  final _contactController = TextEditingController();

  String _selectedCategory = 'Bug';
  bool _includeDiagnostics = false;
  bool _isSubmitting = false;
  String? _errorMessage;

  static const List<String> _categories = [
    'Bug',
    'Feature Request',
    'Usability / UX',
    'General',
  ];

  @override
  void dispose() {
    _summaryController.dispose();
    _messageController.dispose();
    _contactController.dispose();
    super.dispose();
  }

  Map<String, dynamic> _collectDiagnostics(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    return {
      'node_version': AppConfig.appVersion,
      'client_mode': kIsWeb ? 'Web SPA' : 'Desktop',
      'screen_size':
          '${mediaQuery.size.width.toInt()}x${mediaQuery.size.height.toInt()}',
      'pixel_ratio': mediaQuery.devicePixelRatio,
      'platform': defaultTargetPlatform.name,
    };
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    final client = widget.apiClient ?? ApiClient();
    final diagnostics = _includeDiagnostics
        ? _collectDiagnostics(context)
        : null;

    final payload = {
      'category': _selectedCategory,
      'summary': _summaryController.text.trim(),
      'message': _messageController.text.trim(),
      'contact': _contactController.text.trim().isNotEmpty
          ? _contactController.text.trim()
          : null,
      'include_diagnostics': _includeDiagnostics,
      'diagnostics': diagnostics,
      'client_platform': kIsWeb ? 'Web' : defaultTargetPlatform.name,
    };

    try {
      final response = await client.submitFeedback(payload);
      if (!mounted) return;

      final issueNum = response['issue_number'];
      final issueUrl = response['issue_url'] ?? response['html_url'];
      final message = issueNum != null
          ? 'Feedback submitted as Issue #$issueNum! Thank you.'
          : 'Feedback submitted successfully! Thank you.';

      Navigator.of(context).pop();
      if (issueUrl != null && issueUrl.toString().startsWith('http')) {
        M3ESnackbar.show(
          context,
          message: message,
          actionLabel: 'View Issue',
          onAction: () async {
            final uri = Uri.parse(issueUrl.toString());
            if (await canLaunchUrl(uri)) {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            }
          },
        );
      } else {
        M3ESnackbar.show(context, message: message);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        if (e is ApiException) {
          _errorMessage = e.message;
        } else {
          _errorMessage =
              'Feedback service is unreachable. Please check your connection and try again.';
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: colorScheme.surfaceContainerHigh,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Dialog Header
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: HugeIcon(
                          icon: HugeIcons.strokeRoundedMessageQuestion,
                          color: colorScheme.onPrimaryContainer,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Send Beta Feedback',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Report bugs, request enhancements, or suggest UX improvements.',
                              style: TextStyle(
                                fontSize: 12,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 20),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Error Banner
                  if (_errorMessage != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: colorScheme.error.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Row(
                        children: [
                          HugeIcon(
                            icon: HugeIcons.strokeRoundedAlertCircle,
                            color: colorScheme.onErrorContainer,
                            size: 18,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: TextStyle(
                                fontSize: 13,
                                color: colorScheme.onErrorContainer,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Category Selector
                  Text(
                    'Category',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _categories.map((cat) {
                      final selected = _selectedCategory == cat;
                      return ChoiceChip(
                        key: ValueKey('feedback_category_$cat'),
                        label: Text(cat),
                        selected: selected,
                        onSelected: (val) {
                          if (val) {
                            setState(() => _selectedCategory = cat);
                          }
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),

                  // Summary Input
                  Text(
                    'Summary',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextFormField(
                    key: const ValueKey('feedback_summary_input'),
                    controller: _summaryController,
                    decoration: InputDecoration(
                      hintText: 'Brief one-line summary',
                      hintStyle: TextStyle(
                        fontSize: 13,
                        color: colorScheme.outline,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) {
                        return 'Please provide a brief summary';
                      }
                      if (val.trim().length < 3) {
                        return 'Summary must be at least 3 characters';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // Message Input
                  Text(
                    'Message',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextFormField(
                    key: const ValueKey('feedback_message_input'),
                    controller: _messageController,
                    minLines: 4,
                    maxLines: 7,
                    decoration: InputDecoration(
                      hintText:
                          'Describe what occurred, steps to reproduce, or desired feature behavior...',
                      hintStyle: TextStyle(
                        fontSize: 13,
                        color: colorScheme.outline,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      contentPadding: const EdgeInsets.all(12),
                    ),
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) {
                        return 'Feedback message cannot be empty';
                      }
                      if (val.trim().length < 3) {
                        return 'Message must be at least 3 characters';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // Optional Contact Input
                  Text(
                    'Contact (Optional)',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextFormField(
                    key: const ValueKey('feedback_contact_input'),
                    controller: _contactController,
                    decoration: InputDecoration(
                      hintText:
                          'Email or GitHub handle if you would like a reply',
                      hintStyle: TextStyle(
                        fontSize: 13,
                        color: colorScheme.outline,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Privacy & Diagnostic Opt-In
                  Material(
                    color: colorScheme.surfaceContainer,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: BorderSide(
                        color: colorScheme.outlineVariant.withValues(
                          alpha: 0.5,
                        ),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: CheckboxListTile(
                        key: const ValueKey('feedback_diagnostics_checkbox'),
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: Text(
                          'Include diagnostic information',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        subtitle: Text(
                          'Safely collects platform, screen dimensions, and node version. Passwords, queries, and credentials are NEVER collected.',
                          style: TextStyle(
                            fontSize: 11,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        value: _includeDiagnostics,
                        onChanged: (val) =>
                            setState(() => _includeDiagnostics = val ?? false),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Action Buttons
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        key: const ValueKey('feedback_cancel_button'),
                        onPressed: _isSubmitting
                            ? null
                            : () => Navigator.of(context).pop(),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton(
                        key: const ValueKey('feedback_submit_button'),
                        onPressed: _isSubmitting ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: colorScheme.primary,
                          foregroundColor: colorScheme.onPrimary,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: _isSubmitting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                'Send Feedback',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
