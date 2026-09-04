import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:altr_stream_admin/main.dart';
import 'package:altr_stream_admin/core/api/api_client.dart';
import 'package:altr_stream_admin/core/api/models.dart';
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

  testWidgets('App navigation switches between pages', (WidgetTester tester) async {
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

  testWidgets('SourceDetailScreen renders with canonical Discovered Schemas tab', (WidgetTester tester) async {
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

    await tester.pumpWidget(
      MaterialApp(
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

    // Verify TabBar with canonical Discovered Schemas tab
    expect(find.text('Overview'), findsOneWidget);
    expect(find.text('Connection Parameters'), findsOneWidget);
    expect(find.text('Discovered Schemas'), findsOneWidget);
    expect(find.text('Health & Diagnostics'), findsOneWidget);

    // Switch to Discovered Schemas tab
    await tester.tap(find.text('Discovered Schemas'));
    await tester.pumpAndSettle();
    expect(find.text('Discover Schema Now'), findsOneWidget);
  });

  testWidgets('App renders on tablet viewport with NavigationRail', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(768, 1024);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const AltrStreamAdminApp());
    await tester.pump();

    expect(find.byType(NavigationRail), findsOneWidget);
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
}
