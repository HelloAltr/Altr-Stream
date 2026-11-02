import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/api/models.dart';
import '../../core/api/api_client.dart';
import '../../core/config/app_config.dart';
import '../../core/theme/app_theme.dart';
import '../../core/updates/update_controller.dart';
import '../live_actions/live_actions_controller.dart';
import '../live_actions/live_actions_bar.dart';
import '../feedback/feedback_dialog.dart';

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
  final Widget? floatingActionButton;
  final int sourcesCount;
  final int modelsCount;
  final ApiClient? apiClient;
  final UpdateController? updateController;
  final LiveActionsController? liveActionsController;
  final VoidCallback? onPasscodeTap;
  final VoidCallback? onApiSecurityTap;
  final VoidCallback? onWorkspacesTap;
  final String? activeWorkspaceName;
  final void Function(String category)? onNavigateToSettingsCategory;

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
    this.floatingActionButton,
    this.sourcesCount = 0,
    this.modelsCount = 0,
    this.apiClient,
    this.updateController,
    this.liveActionsController,
    this.onPasscodeTap,
    this.onApiSecurityTap,
    this.onWorkspacesTap,
    this.activeWorkspaceName,
    this.onNavigateToSettingsCategory,
  });

  UpdateController get _effectiveUpdateController =>
      updateController ?? UpdateController.instanceFor(apiClient);

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
    '/altrql',
    '/sources',
    '/registry',
    '/activity',
  ];

  int _getNavIndex(String route) {
    if (route == '/altrql' || route == '/playground') {
      return 1;
    } else if (route == '/sources' || route.startsWith('/sources/')) {
      return 2;
    } else if (route == '/registry' || route.startsWith('/registry/')) {
      return 3;
    } else if (route == '/activity') {
      return 4;
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

  // --- DESKTOP LAYOUT (Full-row Navigation Sidebar + Top App Bar) ---
  Widget _buildDesktopLayout(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surfaceContainer,
      appBar: _buildTopAppBar(context),
      floatingActionButton: floatingActionButton != null
          ? UnconstrainedBox(
              alignment: Alignment.bottomRight,
              child: floatingActionButton,
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: _desktopDrawerWidth,
            color: colorScheme.surfaceContainer,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildDesktopNavList(context),
                const Spacer(),
                _buildDesktopFooterItem(
                  context,
                  icon: HugeIcons.strokeRoundedApi,
                  label: 'API Explorer',
                  isActive:
                      activeRoute == '/api-explorer' ||
                      activeRoute == '/docs' ||
                      activeRoute == '/api-docs',
                  onTap: () => onNavigate('/api-explorer'),
                ),
                _buildDesktopFooterItem(
                  context,
                  icon: HugeIcons.strokeRoundedBook02,
                  label: 'Documentation',
                  onTap: () => onLaunchDocs != null
                      ? onLaunchDocs!()
                      : _launchDocs(context),
                ),
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Divider(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
                const SizedBox(height: 4),
                _buildDesktopFooterItem(
                  context,
                  icon: HugeIcons.strokeRoundedSettings01,
                  label: 'Settings',
                  isActive: activeRoute == '/settings',
                  onTap: () => onNavigate('/settings'),
                ),
                _buildDrawerProfileTile(context),
              ],
            ),
          ),
          // Main Workspace Canvas with Top-Left Concave Fillet Transition
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerLowest,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(24),
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: SafeArea(
                child: activeRoute == '/settings'
                    ? child
                    : Align(
                        alignment: Alignment.topLeft,
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: 1600),
                          padding: const EdgeInsets.only(
                            left: 32,
                            right: 32,
                            top: 24,
                            bottom: 28,
                          ),
                          child: child,
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static const double _navItemHeight = 40.0;
  static const double _navItemSpacing = 4.0;
  static const double _navTopPadding = 12.0;

  int _getDesktopNavIndex(String route) {
    if (route == '/') return 0;
    if (route == '/altrql' || route == '/playground') return 1;
    if (route == '/sources' || route.startsWith('/sources/')) return 2;
    if (route == '/registry' || route.startsWith('/registry/')) return 3;
    if (route == '/activity' || route.startsWith('/activity/')) return 4;
    return -1;
  }

  Widget _buildDesktopNavList(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final selectedIndex = _getDesktopNavIndex(activeRoute);

    final items = [
      (
        label: 'Overview',
        icon: HugeIcons.strokeRoundedDashboardSquare01,
        route: '/',
        badgeCount: null,
      ),
      (
        label: 'AltrQL Console',
        icon: HugeIcons.strokeRoundedCommandLine,
        route: '/altrql',
        badgeCount: null,
      ),
      (
        label: 'Data Sources',
        icon: HugeIcons.strokeRoundedDatabase,
        route: '/sources',
        badgeCount: sourcesCount,
      ),
      (
        label: 'Logical Models',
        icon: HugeIcons.strokeRoundedHierarchySquare01,
        route: '/registry',
        badgeCount: modelsCount,
      ),
      (
        label: 'Activity',
        icon: HugeIcons.strokeRoundedActivity01,
        route: '/activity',
        badgeCount: null,
      ),
    ];

    final totalHeight =
        _navTopPadding +
        items.length * _navItemHeight +
        (items.length - 1) * _navItemSpacing;

    return SizedBox(
      height: totalHeight,
      child: Stack(
        children: [
          // Animated Moving Pill Highlight
          AnimatedPositioned(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOutCubicEmphasized,
            top: selectedIndex >= 0
                ? _navTopPadding +
                      selectedIndex * (_navItemHeight + _navItemSpacing)
                : -100.0,
            left: 12.0,
            width: _desktopDrawerWidth - 24.0,
            height: _navItemHeight,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: selectedIndex >= 0 ? 1.0 : 0.0,
              child: Container(
                decoration: BoxDecoration(
                  color: colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          // Nav Items on top of moving highlight
          Padding(
            padding: const EdgeInsets.only(top: _navTopPadding),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (int i = 0; i < items.length; i++) ...[
                  SizedBox(
                    height: _navItemHeight,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12.0),
                      child: Material(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          hoverColor: colorScheme.surfaceContainerHighest
                              .withValues(alpha: 0.6),
                          splashColor: colorScheme.primary.withValues(alpha: 0.08),
                          highlightColor: colorScheme.primary.withValues(alpha: 0.05),
                          onTap: () => onNavigate(items[i].route),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12.0),
                            child: Row(
                              children: [
                                HugeIcon(
                                  icon: items[i].icon,
                                  color: selectedIndex == i
                                      ? colorScheme.onSecondaryContainer
                                      : colorScheme.onSurfaceVariant,
                                  size: 20,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: AnimatedDefaultTextStyle(
                                    duration: const Duration(milliseconds: 200),
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontFamily:
                                          theme.textTheme.bodyMedium?.fontFamily,
                                      fontWeight: selectedIndex == i
                                          ? FontWeight.w600
                                          : FontWeight.w500,
                                      color: selectedIndex == i
                                          ? colorScheme.onSecondaryContainer
                                          : colorScheme.onSurfaceVariant,
                                    ),
                                    child: Text(
                                      items[i].label,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                                if (items[i].badgeCount != null) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 7,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: selectedIndex == i
                                          ? colorScheme.primary
                                          : colorScheme.surfaceContainerHighest,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      '${items[i].badgeCount}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: selectedIndex == i
                                            ? colorScheme.onPrimary
                                            : colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (i < items.length - 1)
                    const SizedBox(height: _navItemSpacing),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopFooterItem(
    BuildContext context, {
    required dynamic icon,
    required String label,
    required VoidCallback onTap,
    bool isActive = false,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          hoverColor: colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.6,
          ),
          splashColor: colorScheme.primary.withValues(alpha: 0.08),
          highlightColor: colorScheme.primary.withValues(alpha: 0.05),
          onTap: onTap,
          child: Container(
            decoration: isActive
                ? BoxDecoration(
                    color: colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  )
                : null,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                HugeIcon(
                  icon: icon,
                  color: isActive
                      ? colorScheme.onSecondaryContainer
                      : colorScheme.primary,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                      color: isActive
                          ? colorScheme.onSecondaryContainer
                          : colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --- TABLET LAYOUT (Compact Navigation Rail) ---
  Widget _buildTabletLayout(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final selectedIndex = _getNavIndex(activeRoute);

    return Scaffold(
      backgroundColor: colorScheme.surfaceContainerLowest,
      floatingActionButton: floatingActionButton != null
          ? UnconstrainedBox(
              alignment: Alignment.bottomRight,
              child: floatingActionButton,
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NavigationRail(
            backgroundColor: colorScheme.surfaceContainer,
            selectedIndex: selectedIndex >= 0 ? selectedIndex : null,
            onDestinationSelected: (index) => onNavigate(_navRoutes[index]),
            labelType: NavigationRailLabelType.all,
            leading: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => onNavigate('/'),
                  child: _buildCompactLogo(context),
                ),
              ),
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
                        icon: HugeIcon(
                          icon: HugeIcons.strokeRoundedApi,
                          color:
                              activeRoute == '/api-explorer' ||
                                  activeRoute == '/docs' ||
                                  activeRoute == '/api-docs'
                              ? colorScheme.primary
                              : colorScheme.primary.withValues(alpha: 0.7),
                          size: 18,
                        ),
                        tooltip: 'API Explorer',
                        onPressed: () => onNavigate('/api-explorer'),
                        style: IconButton.styleFrom(
                          hoverColor: colorScheme.surfaceContainerHighest
                              .withValues(alpha: 0.6),
                        ),
                      ),
                      const SizedBox(height: 4),
                      IconButton(
                        icon: HugeIcon(
                          icon: HugeIcons.strokeRoundedBook02,
                          color: colorScheme.primary.withValues(alpha: 0.7),
                          size: 18,
                        ),
                        tooltip: 'Documentation',
                        onPressed: () => _launchDocs(context),
                        style: IconButton.styleFrom(
                          hoverColor: colorScheme.surfaceContainerHighest
                              .withValues(alpha: 0.6),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        child: Divider(
                          color: colorScheme.outlineVariant.withValues(
                            alpha: 0.5,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      IconButton(
                        icon: HugeIcon(
                          icon: HugeIcons.strokeRoundedSettings01,
                          color: activeRoute == '/settings'
                              ? colorScheme.primary
                              : colorScheme.primary.withValues(alpha: 0.7),
                          size: 18,
                        ),
                        tooltip: 'Settings',
                        onPressed: () => onNavigate('/settings'),
                        style: IconButton.styleFrom(
                          hoverColor: colorScheme.surfaceContainerHighest
                              .withValues(alpha: 0.6),
                        ),
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
            destinations: [
              NavigationRailDestination(
                icon: HugeIcon(
                  icon: HugeIcons.strokeRoundedDashboardSquare01,
                  color: colorScheme.primary,
                  size: 20,
                ),
                selectedIcon: HugeIcon(
                  icon: HugeIcons.strokeRoundedDashboardSquare01,
                  color: colorScheme.primary,
                  size: 20,
                ),
                label: const Text('Overview', style: TextStyle(fontSize: 11)),
              ),
              NavigationRailDestination(
                icon: HugeIcon(
                  icon: HugeIcons.strokeRoundedCommandLine,
                  color: colorScheme.primary,
                  size: 20,
                ),
                selectedIcon: HugeIcon(
                  icon: HugeIcons.strokeRoundedCommandLine,
                  color: colorScheme.primary,
                  size: 20,
                ),
                label: const Text('AltrQL', style: TextStyle(fontSize: 11)),
              ),
              NavigationRailDestination(
                icon: Badge.count(
                  count: sourcesCount,
                  isLabelVisible: true,
                  backgroundColor: colorScheme.primary,
                  textColor: colorScheme.onPrimary,
                  child: HugeIcon(
                    icon: HugeIcons.strokeRoundedDatabase,
                    color: colorScheme.primary,
                    size: 20,
                  ),
                ),
                selectedIcon: Badge.count(
                  count: sourcesCount,
                  isLabelVisible: true,
                  backgroundColor: colorScheme.primary,
                  textColor: colorScheme.onPrimary,
                  child: HugeIcon(
                    icon: HugeIcons.strokeRoundedDatabase,
                    color: colorScheme.primary,
                    size: 20,
                  ),
                ),
                label: const Text(
                  'Data Sources',
                  style: TextStyle(fontSize: 11),
                ),
              ),
              NavigationRailDestination(
                icon: Badge.count(
                  count: modelsCount,
                  isLabelVisible: true,
                  backgroundColor: colorScheme.primary,
                  textColor: colorScheme.onPrimary,
                  child: HugeIcon(
                    icon: HugeIcons.strokeRoundedHierarchySquare01,
                    color: colorScheme.primary,
                    size: 20,
                  ),
                ),
                selectedIcon: Badge.count(
                  count: modelsCount,
                  isLabelVisible: true,
                  backgroundColor: colorScheme.primary,
                  textColor: colorScheme.onPrimary,
                  child: HugeIcon(
                    icon: HugeIcons.strokeRoundedHierarchySquare01,
                    color: colorScheme.primary,
                    size: 20,
                  ),
                ),
                label: const Text('Models', style: TextStyle(fontSize: 11)),
              ),
              NavigationRailDestination(
                icon: HugeIcon(
                  icon: HugeIcons.strokeRoundedActivity01,
                  color: colorScheme.primary,
                  size: 20,
                ),
                selectedIcon: HugeIcon(
                  icon: HugeIcons.strokeRoundedActivity01,
                  color: colorScheme.primary,
                  size: 20,
                ),
                label: const Text('Activity', style: TextStyle(fontSize: 11)),
              ),
            ],
          ),
          VerticalDivider(
            width: 1,
            thickness: 1,
            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
          Expanded(
            child: activeRoute == '/settings'
                ? child
                : Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                    child: child,
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
      backgroundColor: colorScheme.surfaceContainerLowest,
      floatingActionButton: floatingActionButton != null
          ? UnconstrainedBox(
              alignment: Alignment.bottomRight,
              child: floatingActionButton,
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      appBar: AppBar(
        backgroundColor: colorScheme.surfaceContainer,
        elevation: 0,
        titleSpacing: 0,
        title: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => onNavigate('/'),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildCompactLogo(context),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'Altr Stream',
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.anta(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          _buildLiveActions(context, compact: true),
          _buildThemeToggleButton(context),
          const SizedBox(width: 8),
        ],
      ),
      drawer: Drawer(
        backgroundColor: colorScheme.surfaceContainer,
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
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () {
                    Navigator.of(context).pop();
                    onNavigate('/');
                  },
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
              ),
            ),
            ListTile(
              leading: HugeIcon(
                icon: HugeIcons.strokeRoundedDashboardSquare01,
                color: colorScheme.primary,
                size: 20,
              ),
              title: const Text('Overview'),
              selected: activeRoute == '/',
              onTap: () {
                Navigator.of(context).pop();
                onNavigate('/');
              },
            ),
            ListTile(
              leading: HugeIcon(
                icon: HugeIcons.strokeRoundedCommandLine,
                color: colorScheme.primary,
                size: 20,
              ),
              title: const Text('AltrQL Console'),
              selected:
                  activeRoute == '/altrql' || activeRoute == '/playground',
              onTap: () {
                Navigator.of(context).pop();
                onNavigate('/altrql');
              },
            ),
            ListTile(
              leading: HugeIcon(
                icon: HugeIcons.strokeRoundedDatabase,
                color: colorScheme.primary,
                size: 20,
              ),
              title: const Text('Data Sources'),
              trailing: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color:
                      activeRoute == '/sources' ||
                          activeRoute.startsWith('/sources/')
                      ? colorScheme.primary
                      : colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$sourcesCount',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color:
                        activeRoute == '/sources' ||
                            activeRoute.startsWith('/sources/')
                        ? colorScheme.onPrimary
                        : colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              selected:
                  activeRoute == '/sources' ||
                  activeRoute.startsWith('/sources/'),
              onTap: () {
                Navigator.of(context).pop();
                onNavigate('/sources');
              },
            ),
            ListTile(
              leading: HugeIcon(
                icon: HugeIcons.strokeRoundedHierarchySquare01,
                color: colorScheme.primary,
                size: 20,
              ),
              title: const Text('Logical Models'),
              trailing: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color:
                      activeRoute == '/registry' ||
                          activeRoute.startsWith('/registry/')
                      ? colorScheme.primary
                      : colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$modelsCount',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color:
                        activeRoute == '/registry' ||
                            activeRoute.startsWith('/registry/')
                        ? colorScheme.onPrimary
                        : colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              selected:
                  activeRoute == '/registry' ||
                  activeRoute.startsWith('/registry/'),
              onTap: () {
                Navigator.of(context).pop();
                onNavigate('/registry');
              },
            ),
            ListTile(
              leading: HugeIcon(
                icon: HugeIcons.strokeRoundedActivity01,
                color: colorScheme.primary,
                size: 20,
              ),
              title: const Text('Activity'),
              selected: activeRoute == '/activity',
              onTap: () {
                Navigator.of(context).pop();
                onNavigate('/activity');
              },
            ),
            Divider(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
            ListTile(
              leading: HugeIcon(
                icon: HugeIcons.strokeRoundedApi,
                color: colorScheme.primary,
                size: 20,
              ),
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
              leading: HugeIcon(
                icon: HugeIcons.strokeRoundedBook02,
                color: colorScheme.primary,
                size: 20,
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
            Divider(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
            ListTile(
              leading: HugeIcon(
                icon: HugeIcons.strokeRoundedSettings01,
                color: colorScheme.primary,
                size: 20,
              ),
              title: const Text('Settings'),
              selected: activeRoute == '/settings',
              onTap: () {
                Navigator.of(context).pop();
                onNavigate('/settings');
              },
            ),
            const Spacer(),
            Divider(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
            _buildDrawerProfileTile(context),
          ],
        ),
      ),
      body: Padding(
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
      return 'Logical Models';
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
      backgroundColor: colorScheme.surfaceContainer,
      title: Row(
        children: [
          SizedBox(
            width: _desktopDrawerWidth - 8,
            child: Padding(
              padding: const EdgeInsets.only(left: 8, right: 16),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => onNavigate('/'),
                  borderRadius: BorderRadius.circular(8),
                  hoverColor: colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.5,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildCompactLogo(context),
                        const SizedBox(width: 8),
                        Flexible(child: _buildBrandMenuButton(context)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          Container(
            height: 22,
            width: 1,
            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
          const SizedBox(width: 16),
          // Permanent back button slot with disabled appearance when onBack is null
          IconButton(
            icon: HugeIcon(
              icon: HugeIcons.strokeRoundedArrowLeft01,
              color: onBack != null
                  ? colorScheme.onSurface
                  : colorScheme.onSurface.withValues(alpha: 0.25),
              size: 18,
            ),
            onPressed: onBack,
            tooltip: onBack != null ? 'Back' : null,
            style: IconButton.styleFrom(
              minimumSize: const Size(28, 28),
              maximumSize: const Size(28, 28),
              padding: EdgeInsets.zero,
              hoverColor: colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.5,
              ),
              disabledForegroundColor: colorScheme.onSurface.withValues(
                alpha: 0.25,
              ),
            ),
          ),
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
        _buildLiveActions(context),
        const SizedBox(width: 16),
      ],
    );
  }

  Widget _buildBrandMenuButton(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
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
          hoverColor: colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.5,
          ),
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
                HugeIcon(
                  icon: HugeIcons.strokeRoundedUserCircle,
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

    return Padding(
      padding: const EdgeInsets.only(left: 12, right: 12, top: 4, bottom: 16),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          hoverColor: colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.5,
          ),
          onTap: () {
            if (onNavigateToSettingsCategory != null) {
              onNavigateToSettingsCategory!('profile');
            } else {
              onNavigate('/settings');
            }
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                _buildInitialsAvatar(currentUser!, colorScheme, size: 28),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        currentUser!.displayName.isNotEmpty
                            ? currentUser!.displayName
                            : 'Altr User',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      Text(
                        currentUser!.email.isNotEmpty
                            ? currentUser!.email
                            : 'Personal Account',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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
          ),
        ),
      ),
    );
  }

  Widget _buildRailProfileIcon(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isSignedIn = currentUser != null;

    if (!isSignedIn) {
      return IconButton(
        icon: HugeIcon(
          icon: HugeIcons.strokeRoundedUserCircle,
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
      icon: _buildInitialsAvatar(currentUser!, colorScheme, size: 28),
      tooltip: 'Profile Settings',
      onPressed: () {
        if (onNavigateToSettingsCategory != null) {
          onNavigateToSettingsCategory!('profile');
        } else {
          onNavigate('/settings');
        }
      },
    );
  }

  Widget _buildInitialsAvatar(
    UserProfile user,
    ColorScheme colorScheme, {
    double size = 24,
  }) {
    final initial = user.displayName.isNotEmpty
        ? user.displayName.substring(0, 1).toUpperCase()
        : (user.email.isNotEmpty
              ? user.email.substring(0, 1).toUpperCase()
              : 'U');
    final fallback = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colorScheme.primary,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: TextStyle(
          color: colorScheme.onPrimary,
          fontSize: size * 0.45,
          fontWeight: FontWeight.bold,
        ),
      ),
    );

    final url = user.photoUrl?.trim();
    if (url == null || url.isEmpty) {
      return fallback;
    }

    final resolvedUrl = url.startsWith('http://')
        ? 'https://${url.substring(7)}'
        : url;

    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: Image.network(
          resolvedUrl,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => fallback,
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return fallback;
          },
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
            HugeIcon(
              icon: HugeIcons.strokeRoundedUserCircle,
              color: colorScheme.primary,
              size: 24,
            ),
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

  void _showUpdateDialog(BuildContext context) {
    M3EDialog.show<void>(
      context,
      barrierDismissible: true,
      dialog: const _VersionInfoDialog(),
    );
  }

  void _showFeedbackDialog(BuildContext context) {
    FeedbackDialog.show(context, apiClient: apiClient);
  }

  LiveActionsController _createEffectiveLiveActionsController(
    BuildContext context,
  ) {
    if (liveActionsController != null) {
      return liveActionsController!;
    }
    return LiveActionsController(
      updateController: _effectiveUpdateController,
      onOpenUpdateDialog: () => _showUpdateDialog(context),
      onOpenFeedback: () => _showFeedbackDialog(context),
    );
  }

  Widget _buildLiveActions(BuildContext context, {bool? compact}) {
    return LiveActionsBar(
      controller: _createEffectiveLiveActionsController(context),
      compact: compact,
    );
  }

  // --- HELPER WIDGETS ---

  Widget _buildThemeToggleButton(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    dynamic icon;
    String tooltip;

    switch (themeMode) {
      case ThemeMode.light:
        icon = HugeIcons.strokeRoundedSun01;
        tooltip = 'Theme: Light (Click to switch)';
        break;
      case ThemeMode.dark:
        icon = HugeIcons.strokeRoundedMoon02;
        tooltip = 'Theme: Dark (Click to switch)';
        break;
      case ThemeMode.system:
        icon = HugeIcons.strokeRoundedComputer;
        tooltip = 'Theme: System (Click to switch)';
        break;
    }

    return IconButton(
      icon: HugeIcon(icon: icon, size: 18, color: colorScheme.onSurfaceVariant),
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
    final borderCutout = cutoutColor ?? colorScheme.surfaceContainer;

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
            child: HugeIcon(
              icon: HugeIcons.strokeRoundedFlash,
              color: colorScheme.onPrimary,
              size: 18,
            ),
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
}

class _VersionInfoDialog extends StatelessWidget {
  const _VersionInfoDialog();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return M3EDialog(
      title: 'Altr Stream Version Info',
      icon: HugeIcon(
        icon: HugeIcons.strokeRoundedInformationCircle,
        color: colorScheme.primary,
        size: 24,
      ),
      topDivider: false,
      bottomDivider: false,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Current Version: ${AppConfig.formattedAppVersion}',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'AltrQL Federation Engine: ${AppConfig.formattedAppVersion}',
            style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13),
          ),
          Text(
            'Protocol: Binary & Stream Gateway v1',
            style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainer,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                HugeIcon(
                  icon: HugeIcons.strokeRoundedInformationCircle,
                  color: colorScheme.primary,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Updates Managed by Stream Manager',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Node updates, binary installs, and release channels are managed via the Altr Stream Manager desktop app.',
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: <Widget>[
        M3EButton(
          key: const ValueKey('dialog_version_close'),
          style: M3EButtonStyle.filled,
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
