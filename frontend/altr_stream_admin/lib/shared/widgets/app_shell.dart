import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/api/models.dart';
import '../../core/config/app_config.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/material_theme.dart';

class AppShell extends StatelessWidget {
  final Widget child;
  final String activeRoute;
  final Function(String route) onNavigate;
  final VoidCallback? onNodeStatusTap;
  final String nodeStatus;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode>? onThemeModeChanged;
  final UserProfile? currentUser;
  final VoidCallback? onSignIn;
  final VoidCallback? onSignOut;
  final VoidCallback? onProfileTap;
  final String? pageTitle;
  final String? pageSubtitle;
  final VoidCallback? onBack;
  final List<Widget>? pageActions;
  final VoidCallback? onLaunchDocs;

  const AppShell({
    super.key,
    required this.child,
    required this.activeRoute,
    required this.onNavigate,
    this.onNodeStatusTap,
    this.nodeStatus = 'ACTIVE',
    this.themeMode = ThemeMode.system,
    this.onThemeModeChanged,
    this.currentUser,
    this.onSignIn,
    this.onSignOut,
    this.onProfileTap,
    this.pageTitle,
    this.pageSubtitle,
    this.onBack,
    this.pageActions,
    this.onLaunchDocs,
  });

  Future<void> _launchDocs(BuildContext context) async {
    final uri = Uri.parse(AppConfig.apiDocsUrl);
    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched && context.mounted) {
        M3ESnackbar.show(
          context,
          message: 'Could not open documentation at ${AppConfig.apiDocsUrl}',
        );
      }
    } catch (e) {
      if (context.mounted) {
        M3ESnackbar.show(context, message: 'Failed to open documentation: $e');
      }
    }
  }

  static const List<String> _navRoutes = [
    '/',
    '/sources',
    '/registry',
    '/activity',
    '/settings',
    '/api-explorer',
  ];

  int _getNavIndex(String route) {
    if (route == '/sources' || route.startsWith('/sources/')) {
      return 1;
    } else if (route == '/registry' || route.startsWith('/registry/')) {
      return 2;
    } else if (route == '/activity') {
      return 3;
    } else if (route == '/settings') {
      return 4;
    } else if (route == '/api-explorer' ||
        route == '/docs' ||
        route == '/api-docs') {
      return 5;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 1024;
        final isTablet =
            constraints.maxWidth >= 640 && constraints.maxWidth < 1024;

        if (isDesktop) {
          return _buildDesktopLayout(context);
        } else if (isTablet) {
          return _buildTabletLayout(context);
        } else {
          return _buildMobileLayout(context);
        }
      },
    );
  }

  static const double _desktopDrawerWidth = 230.0;

  // --- DESKTOP LAYOUT (M3E Navigation Drawer + M3E Top App Bar) ---
  Widget _buildDesktopLayout(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final selectedIndex = _getNavIndex(activeRoute);

    final m3eThemeData = M3EThemeData(
      colorScheme: colorScheme.toM3EColorScheme(),
      navigationDrawerTheme: const M3ENavigationDrawerTheme(
        width: _desktopDrawerWidth,
      ),
    );

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: _buildTopAppBar(context),
      floatingActionButton:
          (activeRoute == '/altrql' || activeRoute == '/playground')
          ? null
          : _buildDesktopFab(context),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Material 3 Expressive Navigation Drawer with rounded top-right and bottom-right edges
          ClipRRect(
            borderRadius: const BorderRadius.only(
              bottomRight: Radius.circular(28),
            ),
            child: Container(
              width: _desktopDrawerWidth,
              color: colorScheme.surfaceContainerLow,
              child: Column(
                children: [
                  Expanded(
                    child: M3ETheme(
                      data: m3eThemeData,
                      child: M3ENavigationDrawer(
                        selectedIndex: selectedIndex,
                        onDestinationSelected: (int index) {
                          onNavigate(_navRoutes[index]);
                        },
                        destinations: <M3ENavigationDestination>[
                          M3ENavigationDestination(
                            icon: HugeIcon(
                              icon: HugeIcons.strokeRoundedDashboardSquare01,
                              color: colorScheme.primary,
                              size: 20,
                            ),
                            label: 'Overview',
                          ),
                          M3ENavigationDestination(
                            icon: HugeIcon(
                              icon: HugeIcons.strokeRoundedDatabase,
                              color: colorScheme.primary,
                              size: 20,
                            ),
                            label: 'Data Sources',
                          ),
                          M3ENavigationDestination(
                            icon: HugeIcon(
                              icon: HugeIcons.strokeRoundedHierarchySquare01,
                              color: colorScheme.primary,
                              size: 20,
                            ),
                            label: 'Mapping Registry',
                          ),
                          M3ENavigationDestination(
                            icon: HugeIcon(
                              icon: HugeIcons.strokeRoundedActivity01,
                              color: colorScheme.primary,
                              size: 20,
                            ),
                            label: 'Activity',
                          ),
                          M3ENavigationDestination(
                            icon: HugeIcon(
                              icon: HugeIcons.strokeRoundedSettings01,
                              color: colorScheme.primary,
                              size: 20,
                            ),
                            label: 'Settings',
                          ),
                          M3ENavigationDestination(
                            icon: HugeIcon(
                              icon: HugeIcons.strokeRoundedApi,
                              color: colorScheme.primary,
                              size: 20,
                            ),
                            label: 'API Explorer',
                          ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      hoverColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                      onTap: () => onLaunchDocs != null
                          ? onLaunchDocs!()
                          : _launchDocs(context),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        child: Row(
                          children: [
                            HugeIcon(
                              icon: HugeIcons.strokeRoundedBook02,
                              color: colorScheme.primary,
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Documentation',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  _buildDrawerProfileTile(context),
                ],
              ),
            ),
          ),

          // Main Workspace
          Expanded(
            child: Container(
              color: colorScheme.surface,
              child: SafeArea(
                child: SingleChildScrollView(
                  child: Center(
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 1360),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 28,
                      ),
                      child: child,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- TABLET LAYOUT (Compact Navigation Rail) ---
  Widget _buildTabletLayout(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final selectedIndex = _getNavIndex(activeRoute);

    return Scaffold(
      backgroundColor: colorScheme.surface,
      floatingActionButton:
          (activeRoute == '/altrql' || activeRoute == '/playground')
          ? null
          : _buildCompactFab(context),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NavigationRail(
            backgroundColor: colorScheme.surfaceContainerLow,
            selectedIndex: selectedIndex,
            onDestinationSelected: (index) => onNavigate(_navRoutes[index]),
            labelType: NavigationRailLabelType.all,
            leading: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: _buildCompactLogo(context),
            ),
            trailing: Expanded(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.menu_book_outlined, size: 18),
                        tooltip: 'API Documentation (Swagger UI)',
                        onPressed: () => _launchDocs(context),
                      ),
                      const SizedBox(height: 4),
                      _buildRailProfileIcon(context),
                      const SizedBox(height: 4),
                      _buildThemeToggleButton(context),
                    ],
                  ),
                ),
              ),
            ),
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.dashboard_outlined),
                selectedIcon: Icon(Icons.dashboard),
                label: Text('Overview', style: TextStyle(fontSize: 11)),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.dns_outlined),
                selectedIcon: Icon(Icons.dns),
                label: Text('Sources', style: TextStyle(fontSize: 11)),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.schema_outlined),
                selectedIcon: Icon(Icons.schema),
                label: Text('Registry', style: TextStyle(fontSize: 11)),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.history_outlined),
                selectedIcon: Icon(Icons.history),
                label: Text('Activity', style: TextStyle(fontSize: 11)),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings),
                label: Text('Settings', style: TextStyle(fontSize: 11)),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.api_outlined),
                selectedIcon: Icon(Icons.api),
                label: Text('API Explorer', style: TextStyle(fontSize: 11)),
              ),
            ],
          ),
          VerticalDivider(
            width: 1,
            thickness: 1,
            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
          Expanded(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 24,
                ),
                child: child,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- MOBILE LAYOUT (AppBar + Drawer) ---
  Widget _buildMobileLayout(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      floatingActionButton:
          (activeRoute == '/altrql' || activeRoute == '/playground')
          ? null
          : _buildCompactFab(context),
      appBar: AppBar(
        backgroundColor: colorScheme.surfaceContainerLow,
        elevation: 0,
        titleSpacing: 0,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildCompactLogo(context),
            const SizedBox(width: 8),
            Text(
              'Altr Stream',
              style: GoogleFonts.anta(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),
          ],
        ),
        actions: [_buildThemeToggleButton(context), const SizedBox(width: 8)],
      ),
      drawer: Drawer(
        backgroundColor: colorScheme.surfaceContainerLow,
        child: Column(
          children: [
            DrawerHeader(
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
              ),
              child: Row(
                children: [
                  _buildCompactLogo(context),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Altr Stream',
                        style: GoogleFonts.anta(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      Text(
                        'Admin Node',
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            ListTile(
              leading: Icon(
                Icons.dashboard_outlined,
                color: colorScheme.primary,
              ),
              title: const Text('Overview'),
              selected: activeRoute == '/',
              onTap: () {
                Navigator.of(context).pop();
                onNavigate('/');
              },
            ),
            ListTile(
              leading: Icon(Icons.dns_outlined, color: colorScheme.primary),
              title: const Text('Data Sources'),
              selected:
                  activeRoute == '/sources' ||
                  activeRoute.startsWith('/sources/'),
              onTap: () {
                Navigator.of(context).pop();
                onNavigate('/sources');
              },
            ),
            ListTile(
              leading: Icon(Icons.schema_outlined, color: colorScheme.primary),
              title: const Text('Mapping Registry'),
              selected:
                  activeRoute == '/registry' ||
                  activeRoute.startsWith('/registry/'),
              onTap: () {
                Navigator.of(context).pop();
                onNavigate('/registry');
              },
            ),
            ListTile(
              leading: Icon(Icons.history_outlined, color: colorScheme.primary),
              title: const Text('Activity'),
              selected: activeRoute == '/activity',
              onTap: () {
                Navigator.of(context).pop();
                onNavigate('/activity');
              },
            ),
            Divider(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
            ListTile(
              leading: Icon(
                Icons.settings_outlined,
                color: colorScheme.primary,
              ),
              title: const Text('Settings'),
              selected: activeRoute == '/settings',
              onTap: () {
                Navigator.of(context).pop();
                onNavigate('/settings');
              },
            ),
            ListTile(
              leading: Icon(Icons.api_outlined, color: colorScheme.primary),
              title: const Text('API Explorer'),
              subtitle: const Text(
                'OpenAPI / Swagger',
                style: TextStyle(fontSize: 11),
              ),
              selected:
                  activeRoute == '/api-explorer' ||
                  activeRoute == '/docs' ||
                  activeRoute == '/api-docs',
              onTap: () {
                Navigator.of(context).pop();
                onNavigate('/api-explorer');
              },
            ),
            ListTile(
              leading: Icon(
                Icons.menu_book_outlined,
                color: colorScheme.primary,
              ),
              title: const Text('Documentation'),
              subtitle: const Text(
                'OpenAPI / Swagger UI',
                style: TextStyle(fontSize: 11),
              ),
              onTap: () {
                Navigator.of(context).pop();
                if (onLaunchDocs != null) {
                  onLaunchDocs!();
                } else {
                  _launchDocs(context);
                }
              },
            ),
            const Spacer(),
            Divider(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
            _buildDrawerProfileTile(context),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        child: child,
      ),
    );
  }

  String _getPageTitle(String route) {
    if (route == '/') {
      return 'Overview';
    }
    if (route == '/sources/detail' || route.startsWith('/sources/detail')) {
      return 'Data Source Details';
    }
    if (route == '/sources/playground') {
      return 'Source Playground';
    }
    if (route == '/sources' || route.startsWith('/sources')) {
      return 'Data Sources';
    }
    if (route == '/registry/detail' || route.startsWith('/registry/detail')) {
      return 'Logical Model Details';
    }
    if (route == '/registry' || route.startsWith('/registry')) {
      return 'Mapping Registry';
    }
    if (route == '/activity') {
      return 'Activity';
    }
    if (route == '/settings') {
      return 'Settings';
    }
    if (route == '/api-explorer' || route == '/docs' || route == '/api-docs') {
      return 'API Explorer';
    }
    if (route == '/altrql' || route == '/playground') {
      return 'AltrQL Console';
    }
    return 'Overview';
  }

  String _getPageSubtitle(String route) {
    if (route == '/') {
      return 'System overview, status & analytics';
    }
    if (route == '/sources/detail' || route.startsWith('/sources/detail')) {
      return 'Inspect tables, schema & test connectivity';
    }
    if (route == '/sources/playground') {
      return 'Explore and test data source queries';
    }
    if (route == '/sources' || route.startsWith('/sources')) {
      return 'Manage connected data sources and connections';
    }
    if (route == '/registry/detail' || route.startsWith('/registry/detail')) {
      return 'Manage mappings, views & virtual schemas';
    }
    if (route == '/registry' || route.startsWith('/registry')) {
      return 'Define federated schemas and entity mappings';
    }
    if (route == '/activity') {
      return 'Real-time audit log and system events';
    }
    if (route == '/settings') {
      return 'Global configurations and engine parameters';
    }
    if (route == '/api-explorer' || route == '/docs' || route == '/api-docs') {
      return 'Interactive OpenAPI / Swagger documentation';
    }
    if (route == '/altrql' || route == '/playground') {
      return 'Execute federated SQL queries across sources';
    }
    return 'System overview, status & analytics';
  }

  // --- M3E TOP APP BAR & VERSION DROPDOWN ---

  PreferredSizeWidget _buildTopAppBar(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final displayTitle = pageTitle ?? _getPageTitle(activeRoute);
    final displaySubtitle = pageSubtitle ?? _getPageSubtitle(activeRoute);

    return M3EAppBar.top(
      backgroundColor: colorScheme.surfaceContainerLow,
      title: Row(
        children: [
          SizedBox(
            width: _desktopDrawerWidth - 8,
            child: Padding(
              padding: const EdgeInsets.only(left: 8, right: 16),
              child: Row(
                children: [
                  _buildCompactLogo(context),
                  const SizedBox(width: 8),
                  Flexible(
                    child: _buildBrandMenuButton(context),
                  ),
                ],
              ),
            ),
          ),
          Container(
            height: 22,
            width: 1,
            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
          const SizedBox(width: 16),
          // Fixed slot for back button so the title & subtitle NEVER shift horizontally
          if (onBack != null)
            IconButton(
              icon: HugeIcon(
                icon: HugeIcons.strokeRoundedArrowLeft01,
                color: colorScheme.onSurface,
                size: 18,
              ),
              onPressed: onBack,
              tooltip: 'Back',
              style: IconButton.styleFrom(
                minimumSize: const Size(28, 28),
                maximumSize: const Size(28, 28),
                padding: EdgeInsets.zero,
              ),
            )
          else
            const SizedBox(width: 28, height: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                    letterSpacing: -0.2,
                    height: 1.2,
                  ),
                ),
                Text(
                  displaySubtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 11,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      centerTitle: false,
      density: M3EAppBarDensity.regular,
      shapeFamily: M3EAppBarShapeFamily.square,
      safeArea: true,
      actions: [
        ...?pageActions,
        const SizedBox(width: 16),
      ],
    );
  }

  Widget _buildBrandMenuButton(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final customTheme = Theme.of(context).copyWith(
      colorScheme: colorScheme.copyWith(
        secondaryContainer: colorScheme.surfaceContainerHigh,
        onSecondaryContainer: colorScheme.onSurface,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: colorScheme.surfaceContainerHigh,
          foregroundColor: colorScheme.onSurface,
        ),
      ),
    );

    final menuThemeData = M3EThemeData(
      colorScheme: colorScheme.toM3EColorScheme().copyWith(
        secondaryContainer: colorScheme.surfaceContainerHigh,
        onSecondaryContainer: colorScheme.onSurface,
        tertiaryContainer: colorScheme.surfaceContainerHighest,
        onTertiaryContainer: colorScheme.onSurface,
      ),
      menuTheme: M3EMenuTheme(
        backgroundColor: colorScheme.surfaceContainerHigh,
      ),
    );

    return Theme(
      data: customTheme,
      child: M3ETheme(
        data: menuThemeData,
        child: M3EMenu(
          position: M3EMenuAnchorPosition.bottomStart,
          colorStyle: M3EMenuColorStyle.standard,
          closeOnSelect: true,
          onSelected: (Object? value) {
            if (value == 'check_updates' || value == 'version_info') {
              _showUpdateDialog(context);
            } else if (value == 'telemetry') {
              onNodeStatusTap?.call();
            }
          },
          anchorBuilder: (BuildContext context, VoidCallback open) {
            return Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: open,
                borderRadius: BorderRadius.circular(8),
                hoverColor: colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.5,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 4,
                  ),
                  child: Text(
                    'Altr Stream',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.anta(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: colorScheme.onSurface,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
              ),
            );
          },
          children: <M3EMenuNode>[
            M3EMenuGroup(
              children: [
                M3EMenuEntry(
                  label: 'Node Telemetry',
                  value: 'telemetry',
                  leading: const Icon(Icons.monitor_heart_outlined, size: 18),
                ),
              ],
            ),
            const M3EMenuGroup(
              children: [
                M3EMenuEntry(
                  enabled: false,
                  label: 'Version: v1.0.0',
                  value: 'version_info',
                  leading: Icon(Icons.info_outline, size: 18),
                ),
                M3EMenuEntry(
                  label: 'Check for updates',
                  value: 'check_updates',
                  leading: Icon(Icons.system_update_alt, size: 18),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawerProfileTile(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isSignedIn = currentUser != null;

    if (!isSignedIn) {
      return Padding(
        padding: const EdgeInsets.only(left: 12, right: 12, top: 4, bottom: 16),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          hoverColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          onTap: () {
            if (onSignIn != null) {
              onSignIn!();
            } else {
              _showDefaultSignInDialog(context);
            }
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(
                  Icons.account_circle_outlined,
                  size: 20,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Sign In',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return _DrawerProfilePopup(
      currentUser: currentUser!,
      colorScheme: colorScheme,
      onSignOut: onSignOut,
      buildInitialsAvatar: _buildInitialsAvatar,
    );
  }

  Widget _buildRailProfileIcon(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isSignedIn = currentUser != null;

    if (!isSignedIn) {
      return IconButton(
        icon: Icon(
          Icons.account_circle_outlined,
          size: 22,
          color: colorScheme.onSurfaceVariant,
        ),
        tooltip: 'Sign In',
        onPressed: () {
          if (onSignIn != null) {
            onSignIn!();
          } else {
            _showDefaultSignInDialog(context);
          }
        },
      );
    }

    return IconButton(
      icon: SizedBox(
        width: 22,
        height: 22,
        child: ClipOval(
          child: currentUser!.photoUrl != null &&
                  currentUser!.photoUrl!.trim().isNotEmpty
              ? Image.network(
                  currentUser!.photoUrl!,
                  width: 22,
                  height: 22,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) =>
                      _buildInitialsAvatar(currentUser!, colorScheme),
                )
              : _buildInitialsAvatar(currentUser!, colorScheme),
        ),
      ),
      tooltip: currentUser!.displayName.isNotEmpty
          ? currentUser!.displayName
          : 'Profile',
      onPressed: () {
        if (onProfileTap != null) {
          onProfileTap!();
        } else {
          _showProfileDialog(context, currentUser!);
        }
      },
    );
  }

  Widget _buildUserAvatar(UserProfile user, ColorScheme colorScheme) {
    if (user.photoUrl != null && user.photoUrl!.trim().isNotEmpty) {
      return ClipOval(
        child: Image.network(
          user.photoUrl!,
          width: 20,
          height: 20,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) =>
              _buildInitialsAvatar(user, colorScheme),
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return _buildInitialsAvatar(user, colorScheme);
          },
        ),
      );
    }
    return _buildInitialsAvatar(user, colorScheme);
  }

  Widget _buildInitialsAvatar(UserProfile user, ColorScheme colorScheme) {
    final initial = user.displayName.isNotEmpty
        ? user.displayName.substring(0, 1).toUpperCase()
        : (user.email.isNotEmpty
              ? user.email.substring(0, 1).toUpperCase()
              : 'U');
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        color: colorScheme.primary,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: TextStyle(
          color: colorScheme.onPrimary,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  void _showDefaultSignInDialog(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final emailController = TextEditingController(text: 'admin@altrstream.io');
    final nameController = TextEditingController(text: 'Altr Administrator');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colorScheme.surfaceContainerHigh,
        title: Row(
          children: [
            Icon(Icons.account_circle, color: colorScheme.primary, size: 24),
            const SizedBox(width: 10),
            const Text('Sign In'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Sign in to manage node connections, logical models, and API keys.',
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Display Name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: emailController,
              decoration: const InputDecoration(
                labelText: 'Google Account / Email',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'Cancel',
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
          ),
          M3EButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              M3ESnackbar.show(
                context,
                message:
                    'Signed in as ${nameController.text.trim()} (${emailController.text.trim()})',
              );
            },
            style: M3EButtonStyle.filled,
            size: M3EButtonSize.sm,
            child: const Text('Sign In'),
          ),
        ],
      ),
    );
  }

  void _showProfileDialog(BuildContext context, UserProfile user) {
    final colorScheme = Theme.of(context).colorScheme;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colorScheme.surfaceContainerHigh,
        title: Row(
          children: [
            _buildUserAvatar(user, colorScheme),
            const SizedBox(width: 12),
            const Text('User Profile'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              user.displayName,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              user.email,
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainer,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.verified_user,
                    color: colorScheme.primary,
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Provider: ${user.provider ?? "Google"}',
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showUpdateDialog(BuildContext context) {
    M3EDialog.show<void>(
      context,
      barrierDismissible: true,
      dialog: const _VersionInfoDialog(),
    );
  }

  // --- HELPER WIDGETS ---

  Widget _buildThemeToggleButton(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    IconData icon;
    String tooltip;

    switch (themeMode) {
      case ThemeMode.light:
        icon = Icons.light_mode;
        tooltip = 'Theme: Light (Click to switch)';
        break;
      case ThemeMode.dark:
        icon = Icons.dark_mode;
        tooltip = 'Theme: Dark (Click to switch)';
        break;
      case ThemeMode.system:
        icon = Icons.brightness_auto;
        tooltip = 'Theme: System (Click to switch)';
        break;
    }

    return IconButton(
      icon: Icon(icon, size: 18, color: colorScheme.onSurfaceVariant),
      tooltip: tooltip,
      onPressed: () {
        if (onThemeModeChanged == null) return;
        if (themeMode == ThemeMode.system) {
          onThemeModeChanged!(ThemeMode.light);
        } else if (themeMode == ThemeMode.light) {
          onThemeModeChanged!(ThemeMode.dark);
        } else {
          onThemeModeChanged!(ThemeMode.system);
        }
      },
    );
  }

  Widget _buildCompactLogo(BuildContext context, {Color? cutoutColor}) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final statusColor = AppTheme.getStatusColor(nodeStatus, context);
    final borderCutout = cutoutColor ?? colorScheme.surfaceContainerLow;

    final logoWidget = Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [colorScheme.primary, colorScheme.tertiary],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: colorScheme.primary.withValues(alpha: 0.25),
                blurRadius: 8,
              ),
            ],
          ),
          child: Center(
            child: Icon(Icons.bolt, color: colorScheme.onPrimary, size: 18),
          ),
        ),
        Positioned(
          right: -2,
          bottom: -2,
          child: Container(
            width: 11,
            height: 11,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: borderCutout,
            ),
            child: Center(
              child: Container(
                width: 7.5,
                height: 7.5,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: statusColor,
                  boxShadow: [
                    BoxShadow(
                      color: statusColor.withValues(alpha: isDark ? 0.8 : 0.6),
                      blurRadius: 4,
                      spreadRadius: 0.5,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );

    return Tooltip(message: 'Node: $nodeStatus', child: logoWidget);
  }

  Widget _buildDesktopFab(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return FloatingActionButton.extended(
      onPressed: () => onNavigate('/altrql'),
      icon: const Icon(Icons.terminal, size: 18),
      tooltip: 'Open AltrQL Playground',
      label: const Text(
        'AltrQL Console',
        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
      ),
      backgroundColor: colorScheme.primary,
      foregroundColor: colorScheme.onPrimary,
      elevation: 4,
    );
  }

  Widget _buildCompactFab(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return FloatingActionButton(
      onPressed: () => onNavigate('/altrql'),
      tooltip: 'Open AltrQL Playground',
      backgroundColor: colorScheme.primary,
      foregroundColor: colorScheme.onPrimary,
      elevation: 4,
      child: const Icon(Icons.terminal, size: 20),
    );
  }
}


class _VersionInfoDialog extends StatefulWidget {
  const _VersionInfoDialog();

  @override
  State<_VersionInfoDialog> createState() => _VersionInfoDialogState();
}

class _VersionInfoDialogState extends State<_VersionInfoDialog> {
  bool _isChecking = false;
  bool _updateAvailable = false;
  bool _isUpdating = false;
  bool _updateComplete = false;
  double _updateProgress = 0.0;
  Timer? _updateTimer;

  @override
  void dispose() {
    _updateTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkUpdates() async {
    setState(() {
      _isChecking = true;
      _updateAvailable = false;
      _updateComplete = false;
    });
    await Future.delayed(const Duration(milliseconds: 3500));
    if (mounted) {
      setState(() {
        _isChecking = false;
        _updateAvailable = true;
      });
      M3ESnackbar.show(
        context,
        message: 'New update available: v1.1.0',
        actionLabel: 'Update Now',
        onAction: _startUpdate,
      );
    }
  }

  void _startUpdate() {
    setState(() {
      _isUpdating = true;
      _updateProgress = 0.0;
    });

    _updateTimer?.cancel();
    _updateTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _updateProgress += 0.035;
        if (_updateProgress >= 1.0) {
          _updateProgress = 1.0;
          _isUpdating = false;
          _updateAvailable = false;
          _updateComplete = true;
          timer.cancel();
          M3ESnackbar.show(
            context,
            message: 'Altr Stream successfully updated to v1.1.0!',
          );
        }
      });
    });
  }

  Widget _buildStatusCard(ColorScheme colorScheme) {
    if (_isUpdating) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 28,
              height: 28,
              child: M3EProgressIndicator.circularWavy(
                value: _updateProgress,
                strokeWidth: 3,
                trackStrokeWidth: 2,
                wavelength: 12,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Installing Update v1.1.0 (${(_updateProgress * 100).clamp(0, 100).toInt()}%)',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Applying AltrQL binaries and schemas...',
                    style: TextStyle(
                      fontSize: 11,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    if (_updateComplete) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(Icons.check_circle, color: colorScheme.primary, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Your local node has been updated to v1.1.0.',
                style: TextStyle(fontSize: 12, color: colorScheme.onSurface),
              ),
            ),
          ],
        ),
      );
    }

    if (_updateAvailable) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colorScheme.primary.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            Icon(
              Icons.system_update_rounded,
              color: colorScheme.primary,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Update Available (v1.1.0)',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  Text(
                    'Includes engine improvements',
                    style: TextStyle(
                      fontSize: 11,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            M3EButton(
              onPressed: _startUpdate,
              size: M3EButtonSize.sm,
              style: M3EButtonStyle.filled,
              shape: M3EButtonShape.round,
              child: const Text('Update Now'),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle, color: colorScheme.primary, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Your local node is running the latest version.',
              style: TextStyle(fontSize: 12, color: colorScheme.onSurface),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return M3EDialog(
      title: 'Altr Stream Version Info',
      icon: Icon(Icons.system_update_alt, color: colorScheme.primary, size: 24),
      topDivider: false,
      bottomDivider: false,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _updateComplete
                ? 'Current Version: v1.1.0 (Latest)'
                : 'Current Version: v1.0.0',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _updateComplete
                ? 'AltrQL Federation Engine: v1.1.0'
                : 'AltrQL Federation Engine: v1.0.0',
            style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13),
          ),
          Text(
            'Protocol: Binary & Stream Gateway v1',
            style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13),
          ),
          const SizedBox(height: 16),
          _buildStatusCard(colorScheme),
        ],
      ),
      actions: <Widget>[
        M3EButton(
          style: M3EButtonStyle.text,
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
        M3EButton.icon(
          onPressed: (_isChecking || _isUpdating) ? null : _checkUpdates,
          icon: _isChecking
              ? SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colorScheme.onPrimary,
                  ),
                )
              : const Icon(Icons.refresh, size: 16),
          label: Text(_isChecking ? 'Checking...' : 'Check for Updates'),
        ),
      ],
    );
  }
}

// --- Drawer Profile Popup (authenticated users) ---
class _DrawerProfilePopup extends StatelessWidget {
  final UserProfile currentUser;
  final ColorScheme colorScheme;
  final VoidCallback? onSignOut;
  final Widget Function(UserProfile user, ColorScheme colorScheme)
      buildInitialsAvatar;

  const _DrawerProfilePopup({
    required this.currentUser,
    required this.colorScheme,
    this.onSignOut,
    required this.buildInitialsAvatar,
  });

  Widget _buildAvatar(double size) {
    if (currentUser.photoUrl != null &&
        currentUser.photoUrl!.trim().isNotEmpty) {
      return ClipOval(
        child: Image.network(
          currentUser.photoUrl!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) =>
              buildInitialsAvatar(currentUser, colorScheme),
        ),
      );
    }
    return buildInitialsAvatar(currentUser, colorScheme);
  }

  @override
  Widget build(BuildContext context) {
    final cs = colorScheme;
    final displayName =
        currentUser.displayName.isNotEmpty ? currentUser.displayName : 'User';

    final customTheme = Theme.of(context).copyWith(
      colorScheme: cs.copyWith(
        secondaryContainer: cs.surfaceContainerHigh,
        onSecondaryContainer: cs.onSurface,
      ),
    );

    final menuThemeData = M3EThemeData(
      colorScheme: cs.toM3EColorScheme().copyWith(
        secondaryContainer: cs.surfaceContainerHigh,
        onSecondaryContainer: cs.onSurface,
        tertiaryContainer: cs.surfaceContainerHighest,
        onTertiaryContainer: cs.onSurface,
      ),
      menuTheme: M3EMenuTheme(
        backgroundColor: cs.surfaceContainerHigh,
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(left: 12, right: 12, top: 4, bottom: 16),
      child: Theme(
        data: customTheme,
        child: M3ETheme(
          data: menuThemeData,
          child: M3EMenu(
            position: M3EMenuAnchorPosition.topStart,
            colorStyle: M3EMenuColorStyle.standard,
            closeOnSelect: true,
            onSelected: (Object? value) {
              if (value == 'profile') {
                _showProfileDialog(context);
              } else if (value == 'sign_out') {
                onSignOut?.call();
              } else if (value == 'delete_account') {
                _showDeleteConfirmation(context);
              }
            },
            anchorBuilder: (BuildContext context, VoidCallback open) {
              return InkWell(
                borderRadius: BorderRadius.circular(12),
                hoverColor:
                    cs.surfaceContainerHighest.withValues(alpha: 0.5),
                onTap: open,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: _buildAvatar(20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: cs.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
            children: <M3EMenuNode>[
              // Group 1 — Profile & Actions
              M3EMenuGroup(
                children: [
                  const M3EMenuEntry(
                    label: 'Profile',
                    value: 'profile',
                    leading: Icon(Icons.person_outline_rounded, size: 18),
                  ),
                ],
              ),
              // Group 2 — Account actions
              M3EMenuGroup(
                children: [
                  const M3EMenuEntry(
                    label: 'Log Out',
                    value: 'sign_out',
                    leading: Icon(Icons.logout_rounded, size: 18),
                  ),
                  M3EMenuEntry(
                    label: 'Delete Account',
                    value: 'delete_account',
                    leading: Icon(
                      Icons.delete_outline_rounded,
                      size: 18,
                      color: cs.error,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showProfileDialog(BuildContext context) {
    M3EDialog.show<void>(
      context,
      barrierDismissible: true,
      dialog: M3EDialog(
        icon: SizedBox(
          width: 56,
          height: 56,
          child: _buildAvatar(56),
        ),
        title: currentUser.displayName.isNotEmpty
            ? currentUser.displayName
            : 'User',
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildProfileRow(
              context,
              icon: Icons.alternate_email,
              label: 'Email',
              value: currentUser.email,
            ),
            if (currentUser.displayName.isNotEmpty)
              _buildProfileRow(
                context,
                icon: Icons.badge_outlined,
                label: 'Display Name',
                value: currentUser.displayName,
              ),
          ],
        ),
        actions: <Widget>[
          M3EButton(
            style: M3EButtonStyle.text,
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileRow(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: cs.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: cs.onSurfaceVariant,
                  ),
                ),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: cs.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirmation(BuildContext context) {
    M3EDialog.show<void>(
      context,
      barrierDismissible: true,
      dialog: M3EDialog(
        icon: const Icon(Icons.warning_amber_rounded),
        title: 'Delete Account',
        content: const Text(
          'Are you sure you want to delete your account? This action cannot be undone.',
        ),
        actions: <Widget>[
          M3EButton(
            style: M3EButtonStyle.text,
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          M3EButton(
            onPressed: () {
              Navigator.of(context).pop();
              // TODO: Implement account deletion
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
