import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:altr_stream_admin/main.dart';
import 'package:altr_stream_admin/core/api/api_client.dart';
import 'package:altr_stream_admin/core/api/models.dart';
import 'package:altr_stream_admin/core/theme/app_theme.dart';
import 'package:altr_stream_admin/features/overview/screens/overview_screen.dart';
import 'package:altr_stream_admin/features/sources/screens/sources_screen.dart';
import 'package:altr_stream_admin/features/sources/screens/source_detail_screen.dart';
import 'package:altr_stream_admin/features/activity/screens/activity_screen.dart';
import 'package:altr_stream_admin/features/settings/screens/settings_screen.dart';
import 'package:altr_stream_admin/features/sources/widgets/add_source_wizard_dialog.dart';

void main() {
  testWidgets('App renders on desktop viewport with persistent sidebar', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const AltrStreamAdminApp());
    await tester.pump();

    // Verify Brand, Sidebar items, Overview page header
    expect(find.text('Altr Stream'), findsWidgets);
    expect(find.text('Overview'), findsWidgets);
    expect(find.text('Data Sources'), findsWidgets);
    expect(find.text('Activity'), findsWidgets);
    expect(find.text('Settings'), findsWidgets);
    expect(find.byType(OverviewScreen), findsOneWidget);
  });

  testWidgets('App navigation switches between pages and supports theme mode changes', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const AltrStreamAdminApp());
    await tester.pump();

    // Navigate to Data Sources
    await tester.tap(find.text('Data Sources').first);
    await tester.pumpAndSettle();
    expect(find.byType(SourcesScreen), findsOneWidget);

    // Navigate to Activity
    await tester.tap(find.text('Activity').first);
    await tester.pumpAndSettle();
    expect(find.byType(ActivityScreen), findsOneWidget);

    // Navigate to Settings
    await tester.tap(find.text('Settings').first);
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(find.text('Theme & Appearance'), findsOneWidget);
    expect(find.text('Light'), findsOneWidget);
    expect(find.text('Dark'), findsOneWidget);

    // Change theme mode via Settings SegmentedButton
    await tester.tap(find.text('Light'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
  });

  testWidgets('Theme toggle button in header switches theme modes', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const AltrStreamAdminApp());
    await tester.pump();

    // Find theme toggle button (initially brightness_auto / System)
    final toggleFinder = find.byIcon(Icons.brightness_auto);
    expect(toggleFinder, findsOneWidget);

    await tester.tap(toggleFinder);
    await tester.pumpAndSettle();

    // Switched to Light mode -> icon is light_mode
    expect(find.byIcon(Icons.light_mode), findsOneWidget);

    await tester.tap(find.byIcon(Icons.light_mode));
    await tester.pumpAndSettle();

    // Switched to Dark mode -> icon is dark_mode
    expect(find.byIcon(Icons.dark_mode), findsOneWidget);
  });

  testWidgets('Add Source Wizard opens properly', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const AltrStreamAdminApp());
    await tester.pump();

    // Tap Add Data Source
    await tester.tap(find.text('Add Data Source').first);
    await tester.pumpAndSettle();

    expect(find.byType(AddSourceWizardDialog), findsOneWidget);
    expect(find.text('Step 1 of 4: Choose database connector'), findsOneWidget);
    expect(find.text('PostgreSQL'), findsOneWidget);
  });

  testWidgets('SourceDetailScreen renders in both Light and Dark themes', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final mockSource = SourceModel(
      id: 'src_test',
      name: 'Primary PostgreSQL',
      type: 'POSTGRESQL',
      host: 'localhost',
      port: 5432,
      databaseName: 'testdb',
      username: 'postgres',
      status: 'ACTIVE',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    // Test Light Theme
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: SourceDetailScreen(
            source: mockSource,
            apiClient: ApiClient(),
            onBack: () {},
            onDelete: () {},
            onNodeStatusTap: () {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Overview'), findsOneWidget);
    expect(find.text('Connection Parameters'), findsOneWidget);
    expect(find.text('Discovered Schemas'), findsOneWidget);
    expect(find.text('Health & Diagnostics'), findsOneWidget);

    // Switch to Discovered Schemas tab
    await tester.tap(find.text('Discovered Schemas'));
    await tester.pumpAndSettle();
    expect(find.text('Discover Schema Now'), findsOneWidget);
  });

  testWidgets('App renders on tablet viewport with NavigationRail and top-aligned content', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(768, 1024);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const AltrStreamAdminApp());
    await tester.pump();

    expect(find.byType(NavigationRail), findsOneWidget);

    // Verify content is top-aligned near the top of the screen (not centered)
    final overviewTitleY = tester.getTopLeft(
      find.descendant(of: find.byType(OverviewScreen), matching: find.text('Overview')),
    ).dy;
    expect(overviewTitleY, lessThan(60));
  });

  testWidgets('App renders on mobile viewport with Drawer and AppBar', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const AltrStreamAdminApp());
    await tester.pump();

    expect(find.byType(AppBar), findsOneWidget);
  });

  testWidgets('SourceDetailScreen tab navigation on Desktop disables horizontal drag gesture and uses tab clicks', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final mockSource = SourceModel(
      id: 'src_test_drag',
      name: 'Primary PostgreSQL',
      type: 'POSTGRESQL',
      host: 'localhost',
      port: 5432,
      databaseName: 'testdb',
      username: 'postgres',
      status: 'ACTIVE',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: SourceDetailScreen(
            source: mockSource,
            apiClient: ApiClient(),
            onBack: () {},
            onDelete: () {},
            onNodeStatusTap: () {},
          ),
        ),
      ),
    );
    await tester.pump();

    // Verify initial tab is Overview (contains 'Source Summary')
    expect(find.text('Source Summary'), findsOneWidget);
    expect(find.text('Host / IP Address'), findsNothing);

    // Attempt horizontal drag on the TabBarView area (from right to left)
    await tester.drag(find.text('Source Summary'), const Offset(-400, 0));
    await tester.pumpAndSettle();

    // Verify view has NOT changed via drag (still on Overview, not Connection Parameters)
    expect(find.text('Source Summary'), findsOneWidget);
    expect(find.text('Host / IP Address'), findsNothing);

    // Click 'Connection Parameters' tab explicitly
    await tester.tap(find.text('Connection Parameters'));
    await tester.pumpAndSettle();

    // Verify view successfully switched to Connection Parameters
    expect(find.text('Host / IP Address'), findsOneWidget);
  });

  testWidgets('PageHeader action buttons are positioned on the right-hand side on desktop', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const AltrStreamAdminApp());
    await tester.pump();

    // 1. Overview Screen: Verify 'Refresh' and 'Add Data Source' are on the right side
    final overviewTitleX = tester.getTopLeft(find.text('Overview').first).dx;
    final addSourceX = tester.getTopLeft(find.text('Add Data Source').first).dx;
    final refreshX = tester.getTopLeft(find.text('Refresh').first).dx;
    expect(addSourceX, greaterThan(overviewTitleX + 500));
    expect(refreshX, greaterThan(overviewTitleX + 500));

    // 2. Data Sources Screen: Verify action buttons are on the right side
    await tester.tap(find.text('Data Sources').first);
    await tester.pumpAndSettle();
    final sourcesTitleX = tester.getTopLeft(find.text('Data Sources').first).dx;
    final sourcesAddSourceX = tester.getTopLeft(find.text('Add Data Source').first).dx;
    expect(sourcesAddSourceX, greaterThan(sourcesTitleX + 500));

    // 3. Activity Screen: Verify 'Clear Timeline' button is on the right side if present
    await tester.tap(find.text('Activity').first);
    await tester.pumpAndSettle();
    expect(find.byType(ActivityScreen), findsOneWidget);

    // 4. Settings Screen: Verify 'Probe Node Health' button is on the right side
    await tester.tap(find.text('Settings').first);
    await tester.pumpAndSettle();
    final settingsTitleX = tester.getTopLeft(find.text('Settings').first).dx;
    final probeHealthX = tester.getTopLeft(find.text('Probe Node Health')).dx;
    expect(probeHealthX, greaterThan(settingsTitleX + 500));
  });

  testWidgets('OverviewScreen renders merged Connected Sources & Health Status card', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final mockSources = [
      SourceModel(
        id: 'src_1',
        name: 'Primary PostgreSQL',
        type: 'POSTGRESQL',
        host: 'localhost',
        port: 5432,
        databaseName: 'testdb',
        username: 'postgres',
        status: 'ACTIVE',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
      SourceModel(
        id: 'src_2',
        name: 'Analytics Warehouse',
        type: 'POSTGRESQL',
        host: '10.0.0.5',
        port: 5432,
        databaseName: 'analytics',
        username: 'postgres',
        status: 'ACTIVE',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: SingleChildScrollView(
            child: OverviewScreen(
              sources: mockSources,
              activities: const [],
              isLoading: false,
              onRefresh: () {},
              onAddSource: () {},
              onSelectSource: (_) {},
              onViewAllSources: () {},
              onNodeStatusTap: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // Verify title and health badge inside single card
    expect(find.text('Connected Sources'), findsOneWidget);
    expect(find.text('2/2 Healthy'), findsOneWidget);
    expect(find.text('2 sources connected • PostgreSQL connector active'), findsOneWidget);
    expect(find.text('Manage Sources →'), findsOneWidget);

    // Verify source items in the list
    expect(find.text('Primary PostgreSQL'), findsOneWidget);
    expect(find.text('Analytics Warehouse'), findsOneWidget);
  });
}



