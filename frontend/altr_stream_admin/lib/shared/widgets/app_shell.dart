import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

class AppShell extends StatelessWidget {
  final Widget child;
  final String activeRoute;
  final Function(String route) onNavigate;
  final VoidCallback? onNodeStatusTap;
  final String nodeStatus;

  const AppShell({
    super.key,
    required this.child,
    required this.activeRoute,
    required this.onNavigate,
    this.onNodeStatusTap,
    this.nodeStatus = 'ACTIVE',
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
    return Scaffold(
      backgroundColor: AppTheme.bgPrimary,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Persistent Sidebar
          Container(
            width: 240,
            decoration: const BoxDecoration(
              color: AppTheme.bgSidebar,
              border: Border(right: BorderSide(color: AppTheme.borderColor)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Branding Header
                _buildSidebarHeader(),
                const SizedBox(height: 16),

                // Navigation Items
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildNavItem(
                          title: 'Overview',
                          route: '/',
                          icon: Icons.dashboard_outlined,
                          activeIcon: Icons.dashboard,
                        ),
                        const SizedBox(height: 4),
                        _buildNavItem(
                          title: 'Data Sources',
                          route: '/sources',
                          icon: Icons.dns_outlined,
                          activeIcon: Icons.dns,
                        ),
                        const SizedBox(height: 4),
                        _buildNavItem(
                          title: 'Activity',
                          route: '/activity',
                          icon: Icons.history_outlined,
                          activeIcon: Icons.history,
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                          child: Divider(height: 1, thickness: 1, color: AppTheme.borderColor),
                        ),
                        _buildNavItem(
                          title: 'Settings',
                          route: '/settings',
                          icon: Icons.settings_outlined,
                          activeIcon: Icons.settings,
                        ),
                      ],
                    ),
                  ),
                ),

                // Sidebar Footer (Node Status)
                _buildSidebarFooter(),
              ],
            ),
          ),

          // Main Workspace
          Expanded(
            child: Container(
              color: AppTheme.bgPrimary,
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
    final navRoutes = ['/', '/sources', '/activity', '/settings'];
    int selectedIndex = 0;
    if (activeRoute == '/sources' || activeRoute.startsWith('/sources/')) {
      selectedIndex = 1;
    } else if (activeRoute == '/activity') {
      selectedIndex = 2;
    } else if (activeRoute == '/settings') {
      selectedIndex = 3;
    }

    return Scaffold(
      backgroundColor: AppTheme.bgPrimary,
      body: Row(
        children: [
          NavigationRail(
            backgroundColor: AppTheme.bgSidebar,
            selectedIndex: selectedIndex,
            onDestinationSelected: (index) => onNavigate(navRoutes[index]),
            labelType: NavigationRailLabelType.all,
            leading: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: _buildCompactLogo(),
            ),
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.dashboard_outlined),
                selectedIcon: Icon(Icons.dashboard, color: AppTheme.accentCyan),
                label: Text('Overview', style: TextStyle(fontSize: 11)),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.dns_outlined),
                selectedIcon: Icon(Icons.dns, color: AppTheme.accentCyan),
                label: Text('Sources', style: TextStyle(fontSize: 11)),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.history_outlined),
                selectedIcon: Icon(Icons.history, color: AppTheme.accentCyan),
                label: Text('Activity', style: TextStyle(fontSize: 11)),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings, color: AppTheme.accentCyan),
                label: Text('Settings', style: TextStyle(fontSize: 11)),
              ),
            ],
          ),
          const VerticalDivider(width: 1, thickness: 1, color: AppTheme.borderColor),
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
    return Scaffold(
      backgroundColor: AppTheme.bgPrimary,
      appBar: AppBar(
        backgroundColor: AppTheme.bgSidebar,
        elevation: 0,
        title: Row(
          children: [
            _buildCompactLogo(),
            const SizedBox(width: 10),
            const Text(
              'Altr Stream',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
            ),
          ],
        ),
      ),
      drawer: Drawer(
        backgroundColor: AppTheme.bgSidebar,
        child: Column(
          children: [
            DrawerHeader(
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: AppTheme.borderColor)),
              ),
              child: Row(
                children: [
                  _buildCompactLogo(),
                  const SizedBox(width: 12),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Altr Stream',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                      ),
                      Text(
                        'Admin Node',
                        style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
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
              leading: const Icon(Icons.history_outlined),
              title: const Text('Activity'),
              selected: activeRoute == '/activity',
              onTap: () {
                Navigator.of(context).pop();
                onNavigate('/activity');
              },
            ),
            const Divider(color: AppTheme.borderColor),
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

  Widget _buildSidebarHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
      child: InkWell(
        onTap: () => onNavigate('/'),
        borderRadius: BorderRadius.circular(8),
        child: Row(
          children: [
            _buildCompactLogo(),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Altr Stream',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary,
                      letterSpacing: -0.3,
                    ),
                  ),
                  Text(
                    'Node Administration',
                    style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompactLogo() {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppTheme.accentBlue, AppTheme.accentCyan],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: AppTheme.accentCyan.withValues(alpha: 0.25),
            blurRadius: 8,
          ),
        ],
      ),
      child: const Center(
        child: Icon(Icons.bolt, color: Colors.white, size: 18),
      ),
    );
  }

  Widget _buildNavItem({
    required String title,
    required String route,
    required IconData icon,
    required IconData activeIcon,
  }) {
    final bool isActive = (route == '/' && activeRoute == '/') ||
        (route != '/' && (activeRoute == route || (route == '/sources' && activeRoute.startsWith('/sources/'))));

    return InkWell(
      onTap: () => onNavigate(route),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isActive ? AppTheme.accentCyanSubtle : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isActive ? AppTheme.accentCyan.withValues(alpha: 0.25) : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            Icon(
              isActive ? activeIcon : icon,
              size: 18,
              color: isActive ? AppTheme.accentCyan : AppTheme.textSecondary,
            ),
            const SizedBox(width: 12),
            Text(
              title,
              style: TextStyle(
                color: isActive ? AppTheme.textPrimary : AppTheme.textSecondary,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebarFooter() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppTheme.borderColor)),
      ),
      child: InkWell(
        onTap: onNodeStatusTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: AppTheme.bgPrimary,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTheme.borderColor),
          ),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: AppTheme.success,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Node Online',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
              const Icon(Icons.info_outline, size: 14, color: AppTheme.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}
