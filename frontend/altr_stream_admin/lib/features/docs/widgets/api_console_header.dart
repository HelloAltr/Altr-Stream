import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import '../../../core/config/app_config.dart';

/// Top header bar for the dedicated Altr Stream API Console.
/// Sits globally above the three-region workspace.
class ApiConsoleHeader extends StatelessWidget {
  final String searchQuery;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onBackToAdmin;
  final VoidCallback onRefreshSpec;
  final bool isLoading;
  final String nodeStatus;
  final VoidCallback? onNodeStatusTap;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode>? onThemeModeChanged;
  final Function(String url) onOpenExternalUrl;

  const ApiConsoleHeader({
    super.key,
    required this.searchQuery,
    required this.onSearchChanged,
    required this.onBackToAdmin,
    required this.onRefreshSpec,
    this.isLoading = false,
    this.nodeStatus = 'ACTIVE',
    this.onNodeStatusTap,
    this.themeMode = ThemeMode.system,
    this.onThemeModeChanged,
    required this.onOpenExternalUrl,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 950;
        final isVeryCompact = constraints.maxWidth < 750;

        return Container(
          height: 60,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            border: Border(
              bottom: BorderSide(
                color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                width: 1,
              ),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 1. Left: Back to Admin Button + Branding
              OutlinedButton.icon(
                key: const Key('api_console_back_button'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  side: BorderSide(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                icon: const HugeIcon(icon: HugeIcons.strokeRoundedArrowLeft01, size: 14),
                label: const Text(
                  'Back to Admin',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                ),
                onPressed: onBackToAdmin,
              ),
              const SizedBox(width: 10),

              // Vertical separator
              Container(
                height: 20,
                width: 1,
                color: colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
              const SizedBox(width: 10),

              // Branding Icon + Title
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer.withValues(
                        alpha: 0.5,
                      ),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: HugeIcon(
                      icon: HugeIcons.strokeRoundedCommandLine,
                      size: 16,
                      color: colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'API Explorer',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1.5,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: colorScheme.primary.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Text(
                      'Console',
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.primary,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(width: 12),

              // 2. Center: Global Endpoint Search Bar
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: TextField(
                      key: const Key('api_search_input'),
                      decoration: InputDecoration(
                        hintText: isVeryCompact
                            ? 'Search endpoints...'
                            : 'Search endpoints, paths, tags, parameters...',
                        hintStyle: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onSurfaceVariant.withValues(
                            alpha: 0.7,
                          ),
                        ),
                        prefixIcon: HugeIcon(
                          icon: HugeIcons.strokeRoundedSearch01,
                          size: 16,
                          color: colorScheme.primary,
                        ),
                        suffixIcon: searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const HugeIcon(icon: HugeIcons.strokeRoundedCancel01, size: 15),
                                tooltip: 'Clear search',
                                onPressed: () => onSearchChanged(''),
                              )
                            : null,
                        filled: true,
                        fillColor: colorScheme.surface,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(
                            color: colorScheme.outlineVariant.withValues(
                              alpha: 0.5,
                            ),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(
                            color: colorScheme.outlineVariant.withValues(
                              alpha: 0.5,
                            ),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(
                            color: colorScheme.primary,
                            width: 1.5,
                          ),
                        ),
                      ),
                      controller: TextEditingController.fromValue(
                        TextEditingValue(
                          text: searchQuery,
                          selection: TextSelection.collapsed(
                            offset: searchQuery.length,
                          ),
                        ),
                      ),
                      onChanged: onSearchChanged,
                    ),
                  ),
                ),
              ),

              const SizedBox(width: 12),

              // 3. Right: Server Info, External Docs Menu, Theme Toggle, Refresh
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Server / Endpoint Base URL Chip
                  if (!isCompact) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.surface,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: colorScheme.outlineVariant.withValues(
                            alpha: 0.5,
                          ),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: Color(0xFF38A169),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            AppConfig.apiBaseUrl,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 10.5,
                              fontWeight: FontWeight.w500,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],

                  // Reload OpenAPI Spec Button
                  IconButton(
                    icon: isLoading
                        ? SizedBox(
                            width: 15,
                            height: 15,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: colorScheme.primary,
                            ),
                          )
                        : const HugeIcon(icon: HugeIcons.strokeRoundedRefresh, size: 17),
                    tooltip: 'Reload OpenAPI Specification',
                    padding: const EdgeInsets.all(6),
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                    onPressed: isLoading ? null : onRefreshSpec,
                  ),

                  // External Documentation Links Menu
                  PopupMenuButton<String>(
                    icon: const HugeIcon(icon: HugeIcons.strokeRoundedBook02, size: 17),
                    tooltip: 'External API Documentation',
                    padding: const EdgeInsets.all(6),
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                    offset: const Offset(0, 38),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    onSelected: onOpenExternalUrl,
                    itemBuilder: (ctx) => [
                      PopupMenuItem(
                        value: AppConfig.apiDocsUrl,
                        child: const Row(
                          children: [
                            HugeIcon(icon: HugeIcons.strokeRoundedRocket, size: 15),
                            SizedBox(width: 8),
                            Text(
                              'FastAPI Swagger UI (/docs)',
                              style: TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: AppConfig.redocDocsUrl,
                        child: const Row(
                          children: [
                            HugeIcon(icon: HugeIcons.strokeRoundedDocumentCode, size: 15),
                            SizedBox(width: 8),
                            Text(
                              'FastAPI ReDoc (/redoc)',
                              style: TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: AppConfig.openApiJsonUrl,
                        child: const Row(
                          children: [
                            HugeIcon(icon: HugeIcons.strokeRoundedCode, size: 15),
                            SizedBox(width: 8),
                            Text(
                              'OpenAPI Specification (/openapi.json)',
                              style: TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  // Theme Mode Toggle
                  if (onThemeModeChanged != null)
                    IconButton(
                      icon: HugeIcon(
                        icon: isDark
                            ? HugeIcons.strokeRoundedSun01
                            : HugeIcons.strokeRoundedMoon02,
                        size: 17,
                      ),
                      tooltip: isDark
                          ? 'Switch to Light Mode'
                          : 'Switch to Dark Mode',
                      padding: const EdgeInsets.all(6),
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                      onPressed: () {
                        final nextMode = isDark
                            ? ThemeMode.light
                            : ThemeMode.dark;
                        onThemeModeChanged!(nextMode);
                      },
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
