import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/api/models.dart';
import 'api_curl_generator.dart';

class HumanReadableValidationError {
  final String fieldName;
  final String locationContext;
  final String userMessage;
  final String? rawType;

  HumanReadableValidationError({
    required this.fieldName,
    required this.locationContext,
    required this.userMessage,
    this.rawType,
  });
}

class ApiResponseViewer extends StatefulWidget {
  final ApiExecutionResult result;
  final VoidCallback? onClear;

  const ApiResponseViewer({
    super.key,
    required this.result,
    this.onClear,
  });

  @override
  State<ApiResponseViewer> createState() => _ApiResponseViewerState();
}

class _ApiResponseViewerState extends State<ApiResponseViewer> {
  bool _showRawResponse = false;

  void _copyToClipboard(BuildContext context, String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label copied to clipboard'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  String _formatResponseBody(dynamic body) {
    if (body == null) return '(empty response body)';
    if (body is String) {
      try {
        final decoded = jsonDecode(body);
        return const JsonEncoder.withIndent('  ').convert(decoded);
      } catch (_) {
        return body;
      }
    }
    try {
      return const JsonEncoder.withIndent('  ').convert(body);
    } catch (_) {
      return body.toString();
    }
  }

  List<HumanReadableValidationError> _extractValidationErrors() {
    final body = widget.result.responseBody;
    dynamic detail;

    if (body is Map && body.containsKey('detail')) {
      detail = body['detail'];
    } else if (body is String) {
      try {
        final decoded = jsonDecode(body);
        if (decoded is Map && decoded.containsKey('detail')) {
          detail = decoded['detail'];
        }
      } catch (_) {}
    }

    if (detail is! List) return [];

    final List<HumanReadableValidationError> errors = [];
    for (final item in detail) {
      if (item is Map) {
        final loc = item['loc'] as List<dynamic>? ?? [];
        final msg = item['msg']?.toString() ?? 'Validation failed';
        final type = item['type']?.toString() ?? '';

        String fieldName = loc.isNotEmpty ? loc.last.toString() : 'request';
        List<String> contextParts = [];

        for (int i = 0; i < loc.length - 1; i++) {
          final part = loc[i].toString();
          if (part == 'body') {
            continue;
          } else if (part == 'entity_mappings') {
            if (i + 1 < loc.length && loc[i + 1] is int) {
              final idx = loc[i + 1] as int;
              contextParts.add('Entity mapping #${idx + 1}');
              i++;
            } else {
              contextParts.add('Entity mappings');
            }
          } else if (part == 'field_mappings') {
            if (i + 1 < loc.length && loc[i + 1] is int) {
              final idx = loc[i + 1] as int;
              contextParts.add('Field mapping #${idx + 1}');
              i++;
            } else {
              contextParts.add('Field mappings');
            }
          } else {
            contextParts.add(part);
          }
        }

        String locationContext = contextParts.isNotEmpty ? contextParts.join(' > ') : 'Request Body';

        String userMessage = msg;
        if (type == 'string_too_short' || msg.contains('at least 1 character')) {
          userMessage = 'This field cannot be empty.';
        } else if (type == 'missing' || msg.contains('Field required')) {
          userMessage = 'This field is required.';
        } else if (type == 'string_type') {
          userMessage = 'Expected a valid string value.';
        } else if (type == 'number_type' || type == 'float_type' || type == 'int_type') {
          userMessage = 'Expected a valid numeric value.';
        }

        errors.add(
          HumanReadableValidationError(
            fieldName: fieldName,
            locationContext: locationContext,
            userMessage: userMessage,
            rawType: type,
          ),
        );
      }
    }
    return errors;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isSuccess = widget.result.isSuccess;
    final statusColor = isSuccess ? const Color(0xFF38A169) : const Color(0xFFE53E3E);
    final formattedBody = _formatResponseBody(widget.result.responseBody);
    final curlCommand = ApiCurlGenerator.generate(
      method: widget.result.requestMethod,
      url: widget.result.requestUrl,
      headers: widget.result.requestHeaders,
      body: widget.result.requestBody,
    );

    final validationErrors = _extractValidationErrors();
    final hasValidationErrors = validationErrors.isNotEmpty;

    return Container(
      key: const Key('api_response_viewer_container'),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSuccess
              ? colorScheme.outlineVariant.withValues(alpha: 0.5)
              : statusColor.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Bar with Status Code, Duration, and Actions
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isSuccess
                  ? colorScheme.surfaceContainer
                  : statusColor.withValues(alpha: 0.08),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              border: Border(
                bottom: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
              ),
            ),
            child: Row(
              children: [
                // Status Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: statusColor.withValues(alpha: 0.5)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isSuccess ? Icons.check_circle : Icons.error_outline,
                        size: 14,
                        color: statusColor,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        widget.result.statusText,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: statusColor,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),

                // Duration Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.timer_outlined, size: 13, color: colorScheme.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Text(
                        widget.result.formattedDuration,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),

                // Copy actions
                IconButton(
                  icon: const Icon(Icons.code, size: 16),
                  tooltip: 'Copy cURL Command',
                  onPressed: () => _copyToClipboard(context, curlCommand, 'cURL command'),
                ),
                IconButton(
                  icon: const Icon(Icons.link, size: 16),
                  tooltip: 'Copy Request URL',
                  onPressed: () => _copyToClipboard(context, widget.result.requestUrl, 'Request URL'),
                ),
                IconButton(
                  icon: const Icon(Icons.copy, size: 16),
                  tooltip: 'Copy Response Body',
                  onPressed: () => _copyToClipboard(context, formattedBody, 'Response body'),
                ),
                if (widget.onClear != null)
                  IconButton(
                    icon: const Icon(Icons.close, size: 16),
                    tooltip: 'Clear Response',
                    onPressed: widget.onClear,
                  ),
              ],
            ),
          ),

          // Error banner if any generic error message
          if (!isSuccess && widget.result.errorMessage != null && widget.result.errorMessage!.isNotEmpty && !hasValidationErrors)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              color: statusColor.withValues(alpha: 0.1),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warning_amber_rounded, size: 16, color: statusColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.result.errorMessage!,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: statusColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Human-Readable Validation Error Card
          if (hasValidationErrors) ...[
            Container(
              key: const Key('api_validation_summary_card'),
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colorScheme.errorContainer.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: colorScheme.error.withValues(alpha: 0.4)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.gpp_maybe, size: 18, color: colorScheme.error),
                      const SizedBox(width: 8),
                      Text(
                        'Request validation failed',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.error,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: colorScheme.error.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '${validationErrors.length} issue${validationErrors.length > 1 ? 's' : ''}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.error,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ...validationErrors.asMap().entries.map((entry) {
                    final idx = entry.key;
                    final err = entry.value;
                    return Container(
                      key: Key('api_validation_error_item_$idx'),
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: colorScheme.surface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: colorScheme.error.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  err.fieldName,
                                  style: TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: colorScheme.error,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  err.locationContext,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '→ ${err.userMessage}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ],

          // Request URL Bar & View Toggle
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: Row(
              children: [
                Text(
                  '${widget.result.requestMethod} ',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.primary,
                  ),
                ),
                Expanded(
                  child: SelectableText(
                    widget.result.requestUrl,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                if (hasValidationErrors)
                  TextButton.icon(
                    key: const Key('api_toggle_raw_response_button'),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    ),
                    icon: Icon(_showRawResponse ? Icons.visibility_off : Icons.visibility, size: 14),
                    label: Text(
                      _showRawResponse ? 'Hide Raw Response' : 'View Raw Response',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                    onPressed: () {
                      setState(() {
                        _showRawResponse = !_showRawResponse;
                      });
                    },
                  ),
              ],
            ),
          ),

          // Response Body Box (shown if not validation error or if raw response is toggled on)
          if (!hasValidationErrors || _showRawResponse) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: Container(
                key: const Key('api_raw_response_container'),
                width: double.infinity,
                constraints: const BoxConstraints(minHeight: 100, maxHeight: 380),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(
                    formattedBody,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      height: 1.4,
                      color: Color(0xFF68D391),
                    ),
                  ),
                ),
              ),
            ),
          ] else ...[
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}
