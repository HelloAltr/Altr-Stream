import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

class AppShell extends StatelessWidget {
  final Widget child;
  final String activeRoute;
  final Function(String route) onNavigate;
  final VoidCallback? onNodeStatusTap;
  final String nodeStatus;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode>? onThemeModeChanged;

  const AppShell({
    super.key,
    required this.child,
    required this.activeRoute,
    required this.onNavigate,
    this.onNodeStatusTap,
    this.nodeStatus = 'ACTIVE',
    this.themeMode = ThemeMode.system,
    this.onThemeModeChanged,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 1024;
        final isTablet = constraints.maxWidth >= 640 && constraints.maxWidth < 1024;

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

  // --- DESKTOP LAYOUT (Persistent Sidebar) ---
  Widget _buildDesktopLayout(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      floatingActionButton: (activeRoute == '/altrql' || activeRoute == '/playground') ? null : _buildDesktopFab(context),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Persistent Sidebar
          Container(
            width: 240,
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow,
              border: Border(
                right: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Branding Header with Theme Mode Toggle
                _buildSidebarHeader(context),
                const SizedBox(height: 16),

                // Navigation Items
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildNavItem(
                          context: context,
                          title: 'Overview',
                          route: '/',
                          icon: Icons.dashboard_outlined,
                          activeIcon: Icons.dashboard,
                        ),
                        const SizedBox(height: 4),
                        _buildNavItem(
                          context: context,
                          title: 'Data Sources',
                          route: '/sources',
                          icon: Icons.dns_outlined,
                          activeIcon: Icons.dns,
                        ),
                        const SizedBox(height: 4),
                        _buildNavItem(
                          context: context,
                          title: 'Mapping Registry',
                          route: '/registry',
                          icon: Icons.schema_outlined,
                          activeIcon: Icons.schema,
                        ),
                        const SizedBox(height: 4),
                        _buildNavItem(
                          context: context,
                          title: 'Activity',
                          route: '/activity',
                          icon: Icons.history_outlined,
                          activeIcon: Icons.history,
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                          child: Divider(
                            height: 1,
                            thickness: 1,
                            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                          ),
                        ),
                        _buildNavItem(
                          context: context,
                          title: 'Settings',
                          route: '/settings',
                          icon: Icons.settings_outlined,
                          activeIcon: Icons.settings,
                        ),
                      ],
                    ),
                  ),
                ),

                // Sidebar Footer (Node Status & Theme Toggle)
                _buildSidebarFooter(context),
              ],
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
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
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
    final navRoutes = ['/', '/sources', '/registry', '/activity', '/settings'];
    int selectedIndex = 0;
    if (activeRoute == '/sources' || activeRoute.startsWith('/sources/')) {
      selectedIndex = 1;
    } else if (activeRoute == '/registry' || activeRoute.startsWith('/registry/')) {
      selectedIndex = 2;
    } else if (activeRoute == '/activity') {
      selectedIndex = 3;
    } else if (activeRoute == '/settings') {
      selectedIndex = 4;
    }

    return Scaffold(
      backgroundColor: colorScheme.surface,
      floatingActionButton: (activeRoute == '/altrql' || activeRoute == '/playground') ? null : _buildCompactFab(context),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NavigationRail(
            backgroundColor: colorScheme.surfaceContainerLow,
            selectedIndex: selectedIndex,
            onDestinationSelected: (index) => onNavigate(navRoutes[index]),
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
                  child: _buildThemeToggleButton(context),
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
            ],
          ),
          VerticalDivider(width: 1, thickness: 1, color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
          Expanded(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                child: child,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- MOBILE LAYOUT (Drawer + App Bar) ---
  Widget _buildMobileLayout(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      floatingActionButton: (activeRoute == '/altrql' || activeRoute == '/playground') ? null : _buildCompactFab(context),
      appBar: AppBar(
        backgroundColor: colorScheme.surfaceContainerLow,
        elevation: 0,
        title: Row(
          children: [
            _buildCompactLogo(context),
            const SizedBox(width: 10),
            Text(
              'Altr Stream',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),
          ],
        ),
        actions: [
          _buildThemeToggleButton(context),
          const SizedBox(width: 8),
        ],
      ),
      drawer: Drawer(
        backgroundColor: colorScheme.surfaceContainerLow,
        child: Column(
          children: [
            DrawerHeader(
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5))),
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
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      Text(
                        'Admin Node',
                        style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.dashboard_outlined),
              title: const Text('Overview'),
              selected: activeRoute == '/',
              onTap: () {
                Navigator.of(context).pop();
                onNavigate('/');
              },
            ),
            ListTile(
              leading: const Icon(Icons.dns_outlined),
              title: const Text('Data Sources'),
              selected: activeRoute == '/sources' || activeRoute.startsWith('/sources/'),
              onTap: () {
                Navigator.of(context).pop();
                onNavigate('/sources');
              },
            ),
            ListTile(
              leading: const Icon(Icons.schema_outlined),
              title: const Text('Mapping Registry'),
              selected: activeRoute == '/registry' || activeRoute.startsWith('/registry/'),
              onTap: () {
                Navigator.of(context).pop();
                onNavigate('/registry');
              },
            ),
            ListTile(
              leading: const Icon(Icons.history_outlined),
              title: const Text('Activity'),
              selected: activeRoute == '/activity',
              onTap: () {
                Navigator.of(context).pop();
                onNavigate('/activity');
              },
            ),
            Divider(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
            ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: const Text('Settings'),
              selected: activeRoute == '/settings',
              onTap: () {
                Navigator.of(context).pop();
                onNavigate('/settings');
              },
            ),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        child: child,
      ),
    );
  }

  // --- HELPER WIDGETS ---

  Widget _buildSidebarHeader(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: () => onNavigate('/'),
              borderRadius: BorderRadius.circular(8),
              child: Row(
                children: [
                  _buildCompactLogo(context),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Altr Stream',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                            letterSpacing: -0.3,
                          ),
                        ),
                        Text(
                          'Node Administration',
                          style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          _buildThemeToggleButton(context),
        ],
      ),
    );
  }

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

  Widget _buildCompactLogo(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
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
    );
  }

  Widget _buildNavItem({
    required BuildContext context,
    required String title,
    required String route,
    required IconData icon,
    required IconData activeIcon,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final bool isActive = (route == '/' && activeRoute == '/') ||
        (route != '/' && (activeRoute == route || (route == '/sources' && activeRoute.startsWith('/sources/'))));

    return InkWell(
      onTap: () => onNavigate(route),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isActive ? colorScheme.primaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isActive ? colorScheme.primary.withValues(alpha: 0.25) : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            Icon(
              isActive ? activeIcon : icon,
              size: 18,
              color: isActive ? colorScheme.primary : colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isActive ? colorScheme.onPrimaryContainer : colorScheme.onSurfaceVariant,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebarFooter(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final statusColor = AppTheme.getStatusColor(nodeStatus, context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
        ),
      ),
      child: InkWell(
        onTap: onNodeStatusTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainer,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
          ),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: statusColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Node Online',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
              ),
              Icon(Icons.info_outline, size: 14, color: colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
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

