import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/hugeicons.dart';
import '../../../core/config/app_config.dart';
import '../models/api_endpoint_model.dart';
import 'api_curl_generator.dart';

/// Center-region documentation panel displaying endpoint details,
/// structured parameters tables, request body schemas, response definitions, and examples.
class ApiEndpointDocumentation extends StatelessWidget {
  final ApiEndpoint endpoint;
  final Function(String url)? onOpenSwagger;

  const ApiEndpointDocumentation({
    super.key,
    required this.endpoint,
    this.onOpenSwagger,
  });

  void _copyToClipboard(BuildContext context, String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label copied to clipboard'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final methodColor = _getMethodColor(endpoint.method, context);

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Breadcrumbs
          Row(
            children: [
              Text(
                endpoint.primaryTag,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(width: 6),
              HugeIcon(
                icon: HugeIcons.strokeRoundedArrowRight01,
                size: 14,
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                endpoint.summary.isNotEmpty ? endpoint.summary : endpoint.path,
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 2. Title & Operation Summary
          Text(
            endpoint.summary.isNotEmpty ? endpoint.summary : endpoint.path,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurface,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 12),

          // 3. Method + Path Banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            child: Row(
              children: [
                // Method Badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: methodColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: methodColor.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Text(
                    endpoint.method,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: methodColor,
                    ),
                  ),
                ),
                const SizedBox(width: 12),

                // Monospace Path
                Expanded(
                  child: SelectableText(
                    endpoint.path,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),

                // Copy Path Action
                IconButton(
                  icon: const HugeIcon(
                    icon: HugeIcons.strokeRoundedCopy01,
                    size: 16,
                  ),
                  tooltip: 'Copy endpoint path',
                  onPressed: () =>
                      _copyToClipboard(context, endpoint.path, 'Endpoint path'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // 4. Description
          if (endpoint.description.isNotEmpty) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                ),
              ),
              child: Text(
                endpoint.description,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],

          // 5. Parameters Section
          _buildSectionHeader(
            context,
            icon: HugeIcons.strokeRoundedSlidersVertical,
            title: 'Parameters',
            count: endpoint.parameters.length,
          ),
          const SizedBox(height: 8),
          if (endpoint.parameters.isEmpty)
            _buildEmptySectionMessage(
              context,
              'No path, query, or header parameters required for this endpoint.',
            )
          else
            _buildParametersTable(context),

          const SizedBox(height: 28),

          // 6. Request Body Schema Section
          if (endpoint.hasRequestBody) ...[
            _buildSectionHeader(
              context,
              icon: HugeIcons.strokeRoundedCode,
              title: 'Request Body Schema',
              badge: endpoint.requestBody?.required == true
                  ? 'Required'
                  : 'Optional',
              badgeColor: endpoint.requestBody?.required == true
                  ? colorScheme.primary
                  : colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 8),
            _buildRequestBodySchema(context),
            const SizedBox(height: 28),
          ],

          // 7. Response Codes & Schema Section
          _buildSectionHeader(
            context,
            icon: HugeIcons.strokeRoundedShare01,
            title: 'Responses',
            count: endpoint.responses.length,
          ),
          const SizedBox(height: 8),
          _buildResponsesTable(context),

          const SizedBox(height: 28),

          // 8. Example cURL Request Snippet
          _buildCurlExampleCard(context),
          const SizedBox(height: 24),

          // 9. External OpenAPI & Swagger Documentation
          _buildExternalDocsSection(context),
          const SizedBox(height: 16),

          // 10. Quick cURL Reference Card
          _buildCurlReferenceCard(context),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(
    BuildContext context, {
    required dynamic icon,
    required String title,
    int? count,
    String? badge,
    Color? badgeColor,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        HugeIcon(icon: icon, size: 18, color: colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: colorScheme.onSurface,
          ),
        ),
        if (count != null) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
        if (badge != null) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: (badgeColor ?? colorScheme.primary).withValues(
                alpha: 0.12,
              ),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: (badgeColor ?? colorScheme.primary).withValues(
                  alpha: 0.4,
                ),
              ),
            ),
            child: Text(
              badge,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: badgeColor ?? colorScheme.primary,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildEmptySectionMessage(BuildContext context, String message) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Text(
        message,
        style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
      ),
    );
  }

  Widget _buildParametersTable(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        children: [
          // Table Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.5),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(7),
              ),
            ),
            child: Row(
              children: [
                Expanded(flex: 3, child: _tableHeaderCell('NAME & LOCATION')),
                Expanded(flex: 2, child: _tableHeaderCell('TYPE')),
                Expanded(
                  flex: 5,
                  child: _tableHeaderCell('DESCRIPTION & DEFAULT'),
                ),
              ],
            ),
          ),
          Divider(
            height: 1,
            thickness: 1,
            color: colorScheme.outlineVariant.withValues(alpha: 0.4),
          ),

          // Rows
          for (int i = 0; i < endpoint.parameters.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                thickness: 1,
                color: colorScheme.outlineVariant.withValues(alpha: 0.2),
              ),
            _buildParameterRow(context, endpoint.parameters[i]),
          ],
        ],
      ),
    );
  }

  Widget _tableHeaderCell(String label) {
    return Text(
      label,
      style: const TextStyle(
        fontSize: 10.5,
        fontWeight: FontWeight.bold,
        letterSpacing: 0.4,
      ),
    );
  }

  Widget _buildParameterRow(BuildContext context, ApiParameter p) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Name & In Location
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RichText(
                  text: TextSpan(
                    text: p.name,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12.5,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                    children: [
                      if (p.required)
                        const TextSpan(
                          text: ' *',
                          style: TextStyle(
                            color: Color(0xFFE53E3E),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 3),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1.5,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    p.inLocation,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 10,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Type
          Expanded(
            flex: 2,
            child: Text(
              p.schemaType,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: colorScheme.primary,
              ),
            ),
          ),

          // Description & Defaults
          Expanded(
            flex: 5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.description.isNotEmpty
                      ? p.description
                      : '(No description provided)',
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                if (p.defaultValue != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Default: ${p.defaultValue}',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: colorScheme.primary,
                    ),
                  ),
                ],
                if (p.enumOptions.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      for (final opt in p.enumOptions)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: colorScheme.surface,
                            borderRadius: BorderRadius.circular(3),
                            border: Border.all(
                              color: colorScheme.outlineVariant.withValues(
                                alpha: 0.5,
                              ),
                            ),
                          ),
                          child: Text(
                            opt,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 10,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRequestBodySchema(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final rb = endpoint.requestBody!;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  rb.contentType,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                rb.required ? 'Body is required' : 'Body is optional',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: rb.required
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          if (rb.description.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              rb.description,
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 12),

          // Sample JSON Schema preview
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(6),
            ),
            child: SelectableText(
              rb.sampleJson,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 11.5,
                color: Color(0xFF68D391),
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResponsesTable(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final entries = endpoint.responses.entries.toList();

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        children: [
          for (int i = 0; i < entries.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                thickness: 1,
                color: colorScheme.outlineVariant.withValues(alpha: 0.2),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Status code badge
                  Container(
                    width: 58,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: _getStatusCodeColor(
                        entries[i].key,
                      ).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: _getStatusCodeColor(
                          entries[i].key,
                        ).withValues(alpha: 0.4),
                      ),
                    ),
                    child: Center(
                      child: Text(
                        entries[i].key,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: _getStatusCodeColor(entries[i].key),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),

                  // Description
                  Expanded(
                    child: Text(
                      entries[i].value.description.isNotEmpty
                          ? entries[i].value.description
                          : '(No description provided)',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCurlExampleCard(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final curlCommand = ApiCurlGenerator.generate(
      method: endpoint.method,
      url: '${AppConfig.apiBaseUrl}${endpoint.path}',
      body: endpoint.requestBody?.sampleJson,
    );

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  HugeIcon(
                    icon: HugeIcons.strokeRoundedCommandLine,
                    size: 16,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Example cURL Command',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
              IconButton(
                icon: const HugeIcon(
                  icon: HugeIcons.strokeRoundedCopy01,
                  size: 15,
                ),
                tooltip: 'Copy cURL command',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                onPressed: () =>
                    _copyToClipboard(context, curlCommand, 'cURL command'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(6),
            ),
            child: SelectableText(
              curlCommand,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                color: Color(0xFF68D391),
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExternalDocsSection(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              HugeIcon(
                icon: HugeIcons.strokeRoundedBook02,
                size: 16,
                color: colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                'OpenAPI / Swagger Documentation',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'FastAPI serves the authoritative OpenAPI 3.1 specification. Access external Swagger UI or ReDoc below.',
            style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                icon: const HugeIcon(
                  icon: HugeIcons.strokeRoundedRocket,
                  size: 15,
                ),
                label: const Text(
                  'Launch Swagger UI (/docs)',
                  style: TextStyle(fontSize: 12),
                ),
                onPressed: () => onOpenSwagger != null
                    ? onOpenSwagger!(AppConfig.apiDocsUrl)
                    : null,
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                icon: const HugeIcon(
                  icon: HugeIcons.strokeRoundedDocumentCode,
                  size: 15,
                ),
                label: const Text(
                  'Open ReDoc (/redoc)',
                  style: TextStyle(fontSize: 12),
                ),
                onPressed: () => onOpenSwagger != null
                    ? onOpenSwagger!(AppConfig.redocDocsUrl)
                    : null,
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                icon: const HugeIcon(
                  icon: HugeIcons.strokeRoundedCode,
                  size: 15,
                ),
                label: const Text(
                  'OpenAPI JSON (/openapi.json)',
                  style: TextStyle(fontSize: 12),
                ),
                onPressed: () => onOpenSwagger != null
                    ? onOpenSwagger!(AppConfig.openApiJsonUrl)
                    : null,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCurlReferenceCard(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Quick cURL Request Reference',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
              IconButton(
                icon: const HugeIcon(
                  icon: HugeIcons.strokeRoundedCopy01,
                  size: 15,
                ),
                tooltip: 'Copy cURL command',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                onPressed: () => _copyToClipboard(
                  context,
                  'curl -X POST "${AppConfig.apiBaseUrl}/execute" \\\n  -H "Content-Type: application/json" \\\n  -d \'{"query": "SELECT u.id, u.name FROM users u"}\'',
                  'cURL command',
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(6),
            ),
            child: SelectableText(
              'curl -X POST "${AppConfig.apiBaseUrl}/execute" \\\n'
              '  -H "Content-Type: application/json" \\\n'
              '  -d \'{"query": "SELECT u.id, u.name FROM users u"}\'',
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                color: Color(0xFF68D391),
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Color _getMethodColor(String method, BuildContext context) {
    switch (method.toUpperCase()) {
      case 'GET':
        return const Color(0xFF38A169);
      case 'POST':
        return const Color(0xFF3182CE);
      case 'PUT':
        return const Color(0xFFDD6B20);
      case 'DELETE':
        return const Color(0xFFE53E3E);
      case 'PATCH':
        return const Color(0xFF805AD5);
      case 'HEAD':
        return const Color(0xFF319795);
      default:
        return Theme.of(context).colorScheme.primary;
    }
  }

  static Color _getStatusCodeColor(String code) {
    if (code.startsWith('2')) return const Color(0xFF38A169);
    if (code.startsWith('3')) return const Color(0xFF3182CE);
    if (code == '422') return const Color(0xFFDD6B20);
    if (code.startsWith('4')) return const Color(0xFFE53E3E);
    if (code.startsWith('5')) return const Color(0xFFE53E3E);
    return Colors.grey;
  }
}
