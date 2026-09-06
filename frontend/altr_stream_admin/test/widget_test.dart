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
import 'package:altr_stream_admin/features/query_playground/screens/query_playground_screen.dart';
import 'package:altr_stream_admin/features/query_playground/widgets/schema_explorer.dart';
import 'package:altr_stream_admin/features/query_playground/widgets/command_outcome_panel.dart';
import 'package:altr_stream_admin/features/query_playground/widgets/destructive_query_dialog.dart';
import 'package:altr_stream_admin/features/query_playground/widgets/query_editor.dart';
import 'package:altr_stream_admin/features/settings/screens/settings_screen.dart';
import 'package:altr_stream_admin/features/sources/widgets/add_source_wizard_dialog.dart';

class MockTestApiClient extends ApiClient {
  final SourceSchemaModel? schemaToReturn;
  final QueryExecuteResponseModel? queryResponseToReturn;

  MockTestApiClient({
    this.schemaToReturn,
    this.queryResponseToReturn,
  });

  @override
  Future<SourceSchemaModel?> getLatestSchema(String id) async => schemaToReturn;

  @override
  Future<SourceSchemaModel> discoverSchema(String id) async =>
      schemaToReturn ??
      SourceSchemaModel(
        sourceId: id,
        sourceName: 'Mock Source',
        version: '1.0.0',
        discoveredAt: DateTime.now(),
        entities: [],
        metadata: {},
      );

  @override
  Future<QueryExecuteResponseModel> executeQuery({
    required String sourceId,
    required String query,
  }) async {
    return queryResponseToReturn ??
        QueryExecuteResponseModel(
          success: true,
          columns: ['id', 'name'],
          rows: [
            {'id': 1, 'name': 'Alice'},
            {'id': 2, 'name': 'Bob'},
          ],
          metadata: QueryMetadataModel(
            rowCount: 2,
            executionTimeMs: 12.5,
          ),
        );
  }
}

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

    expect(find.text('Source Summary'), findsOneWidget);
    expect(find.text('Host / IP Address'), findsNothing);

    await tester.drag(find.text('Source Summary'), const Offset(-400, 0));
    await tester.pumpAndSettle();

    expect(find.text('Source Summary'), findsOneWidget);
    expect(find.text('Host / IP Address'), findsNothing);

    await tester.tap(find.text('Connection Parameters'));
    await tester.pumpAndSettle();

    expect(find.text('Host / IP Address'), findsOneWidget);
  });

  testWidgets('PageHeader action buttons are positioned on the right-hand side on desktop', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const AltrStreamAdminApp());
    await tester.pump();

    final overviewTitleX = tester.getTopLeft(find.text('Overview').first).dx;
    final addSourceX = tester.getTopLeft(find.text('Add Data Source').first).dx;
    final refreshX = tester.getTopLeft(find.text('Refresh').first).dx;
    expect(addSourceX, greaterThan(overviewTitleX + 500));
    expect(refreshX, greaterThan(overviewTitleX + 500));

    await tester.tap(find.text('Data Sources').first);
    await tester.pumpAndSettle();
    final sourcesTitleX = tester.getTopLeft(find.text('Data Sources').first).dx;
    final sourcesAddSourceX = tester.getTopLeft(find.text('Add Data Source').first).dx;
    expect(sourcesAddSourceX, greaterThan(sourcesTitleX + 500));

    await tester.tap(find.text('Activity').first);
    await tester.pumpAndSettle();
    expect(find.byType(ActivityScreen), findsOneWidget);

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

    expect(find.text('Connected Sources'), findsOneWidget);
    expect(find.text('2/2 Healthy'), findsOneWidget);
    expect(find.text('2 sources connected • PostgreSQL connector active'), findsOneWidget);
    expect(find.text('Manage Sources →'), findsOneWidget);
    expect(find.text('Primary PostgreSQL'), findsOneWidget);
    expect(find.text('Analytics Warehouse'), findsOneWidget);
  });

  testWidgets('Console FAB is visible and opens Query Playground screen', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const AltrStreamAdminApp());
    await tester.pump();

    final fabFinder = find.text('Open Console');
    expect(fabFinder, findsOneWidget);

    await tester.tap(fabFinder);
    await tester.pumpAndSettle();

    expect(find.byType(QueryPlaygroundScreen), findsOneWidget);
    expect(find.text('Query Playground'), findsOneWidget);
    expect(find.text('Run Query'), findsOneWidget);

    expect(find.text('Open Console'), findsNothing);

    await tester.tap(find.text('Back to Dashboard'));
    await tester.pumpAndSettle();

    expect(find.byType(OverviewScreen), findsOneWidget);
    expect(find.text('Open Console'), findsOneWidget);
  });

  testWidgets('SchemaExplorer widget renders tables, columns, and inserts query template', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final mockSource = SourceModel(
      id: 'src_pg_1',
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

    final mockSchema = SourceSchemaModel(
      sourceId: 'src_pg_1',
      sourceName: 'Primary PostgreSQL',
      version: '1.0.0',
      discoveredAt: DateTime.now(),
      entities: [
        EntitySchemaModel(
          name: 'users',
          namespace: 'public',
          entityType: 'TABLE',
          fields: [
            FieldSchemaModel(
              name: 'id',
              dataType: 'integer',
              nativeDataType: 'int4',
              nullable: false,
              isPrimaryKey: true,
              position: 1,
            ),
            FieldSchemaModel(
              name: 'email',
              dataType: 'varchar',
              nativeDataType: 'varchar(255)',
              nullable: true,
              isPrimaryKey: false,
              position: 2,
            ),
          ],
          primaryKey: ['id'],
          constraints: [],
        ),
      ],
      metadata: {},
    );

    EntitySchemaModel? selectedEntity;
    FieldSchemaModel? selectedField;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: SizedBox(
            width: 320,
            height: 600,
            child: SchemaExplorer(
              selectedSource: mockSource,
              schema: mockSchema,
              isLoading: false,
              onRefreshSchema: () {},
              onSelectTable: (e) => selectedEntity = e,
              onSelectColumn: (f, e) => selectedField = f,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Schema Explorer'), findsOneWidget);
    expect(find.text('1 tables • 2 columns'), findsOneWidget);
    expect(find.text('users'), findsOneWidget);

    // Click "Query Table" template icon button
    final queryTableFinder = find.byTooltip('Query Table (Insert Template)');
    expect(queryTableFinder, findsOneWidget);
    await tester.tap(queryTableFinder);
    await tester.pump();
    expect(selectedEntity?.name, 'users');

    // Expand table to inspect columns
    await tester.tap(find.text('users'));
    await tester.pumpAndSettle();

    expect(find.text('id'), findsOneWidget);
    expect(find.text('email'), findsOneWidget);
    expect(find.text('int4'), findsOneWidget);
    expect(find.text('NOT NULL'), findsOneWidget);
    expect(find.byIcon(Icons.vpn_key_rounded), findsOneWidget);

    // Tap column to trigger onSelectColumn
    await tester.tap(find.text('email'));
    await tester.pump();
    expect(selectedField?.name, 'email');
  });

  testWidgets('QueryPlaygroundScreen executes query and renders QueryResultTable and CommandOutcomePanel', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final mockSource = SourceModel(
      id: 'src_pg_1',
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

    final mockSchema = SourceSchemaModel(
      sourceId: 'src_pg_1',
      sourceName: 'Primary PostgreSQL',
      version: '1.0.0',
      discoveredAt: DateTime.now(),
      entities: [
        EntitySchemaModel(
          name: 'users',
          namespace: 'public',
          entityType: 'TABLE',
          fields: [
            FieldSchemaModel(
              name: 'id',
              dataType: 'integer',
              nativeDataType: 'int4',
              nullable: false,
              isPrimaryKey: true,
              position: 1,
            ),
          ],
          primaryKey: ['id'],
          constraints: [],
        ),
      ],
      metadata: {},
    );

    final mockClient = MockTestApiClient(
      schemaToReturn: mockSchema,
      queryResponseToReturn: QueryExecuteResponseModel(
        success: true,
        columns: ['id', 'username'],
        rows: [
          {'id': 1, 'username': 'Alice'},
          {'id': 2, 'username': 'Bob'},
        ],
        metadata: QueryMetadataModel(
          rowCount: 2,
          executionTimeMs: 14.2,
        ),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: QueryPlaygroundScreen(
            sources: [mockSource],
            apiClient: mockClient,
            nodeStatus: 'ACTIVE',
            onBack: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Query Playground'), findsOneWidget);
    expect(find.text('POSTGRESQL QUERY'), findsOneWidget);
    expect(find.text('Schema Explorer'), findsOneWidget);
    expect(find.text('users'), findsOneWidget);

    // Tap Run Query
    await tester.tap(find.text('Run Query'));
    await tester.pumpAndSettle();

    // Verify result table rendered
    expect(find.text('Query Results'), findsOneWidget);
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Bob'), findsOneWidget);
  });

  testWidgets('Destructive query detection triggers DestructiveQueryDialog confirmation', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // Verify comment-aware destructive detection helper
    expect(isDestructiveQuery('DROP TABLE users;'), isTrue);
    expect(isDestructiveQuery('-- cleanup\nTRUNCATE TABLE logs;'), isTrue);
    expect(isDestructiveQuery('/* multi-line comment */ DELETE FROM users;'), isTrue);
    expect(isDestructiveQuery('ALTER TABLE users ADD COLUMN age INT;'), isTrue);
    expect(isDestructiveQuery('SELECT * FROM users;'), isFalse);
    expect(isDestructiveQuery('INSERT INTO users VALUES (1);'), isFalse);

    final mockSource = SourceModel(
      id: 'src_pg_1',
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

    final mockClient = MockTestApiClient(
      queryResponseToReturn: QueryExecuteResponseModel(
        success: true,
        columns: [],
        rows: [],
        metadata: QueryMetadataModel(
          rowCount: 0,
          affectedRows: 1,
          message: 'DROP TABLE',
          executionTimeMs: 8.5,
        ),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: QueryPlaygroundScreen(
            sources: [mockSource],
            apiClient: mockClient,
            nodeStatus: 'ACTIVE',
            onBack: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Enter a DROP query
    final textField = find.byType(TextField).last;
    await tester.enterText(textField, 'DROP TABLE test_temp;');
    await tester.pump();

    // Click Run Query
    await tester.tap(find.text('Run Query'));
    await tester.pumpAndSettle();

    // Verify DestructiveQueryDialog appears
    expect(find.byType(DestructiveQueryDialog), findsOneWidget);
    expect(find.text('Potentially Destructive Operation'), findsOneWidget);
    expect(find.text('Execute Anyway'), findsOneWidget);

    // Confirm execution
    await tester.tap(find.text('Execute Anyway'));
    await tester.pumpAndSettle();

    // Verify CommandOutcomePanel rendered
    expect(find.byType(CommandOutcomePanel), findsOneWidget);
    expect(find.text('Command Executed Successfully'), findsOneWidget);
    expect(find.text('DROP TABLE'), findsOneWidget);
  });

  testWidgets('Query editor remains fully editable and focused after execution failure, cancellation, and clear', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final mockSource = SourceModel(
      id: 'src_pg_1',
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

    final mockClient = MockTestApiClient(
      queryResponseToReturn: QueryExecuteResponseModel(
        success: true,
        columns: ['val'],
        rows: [{'val': 1}],
        metadata: QueryMetadataModel(rowCount: 1, executionTimeMs: 5.0),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: QueryPlaygroundScreen(
            sources: [mockSource],
            apiClient: mockClient,
            nodeStatus: 'ACTIVE',
            onBack: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final editorField = find.descendant(of: find.byType(QueryEditor), matching: find.byType(TextField));

    // 1. Enter query and trigger execution
    await tester.enterText(editorField, 'SELECT invalid_syntax;');
    await tester.pump();

    // Tap Run Query
    await tester.tap(find.text('Run Query'));
    await tester.pumpAndSettle();

    // 2. Verify editor is still editable after execution
    await tester.enterText(editorField, 'SELECT 1;');
    await tester.pump();
    expect(find.text('SELECT 1;'), findsOneWidget);

    // 3. Click Clear and verify editor is emptied and editable
    await tester.tap(find.text('Clear'));
    await tester.pump();
    expect(find.text('SELECT 1;'), findsNothing);

    await tester.enterText(editorField, 'SELECT 2;');
    await tester.pump();
    expect(find.text('SELECT 2;'), findsOneWidget);

    // 4. Trigger destructive query dialog and cancel
    await tester.enterText(editorField, 'DROP TABLE test_tbl;');
    await tester.pump();
    await tester.tap(find.text('Run Query'));
    await tester.pumpAndSettle();

    expect(find.byType(DestructiveQueryDialog), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    // 5. Verify editor is STILL editable after dialog cancellation
    await tester.enterText(editorField, 'SELECT 3;');
    await tester.pump();
    expect(find.text('SELECT 3;'), findsOneWidget);
  });

  testWidgets('Query editor supports consecutive query executions without losing focus or editability', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final mockSource = SourceModel(
      id: 'src_pg_1',
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

    final mockClient = MockTestApiClient(
      queryResponseToReturn: QueryExecuteResponseModel(
        success: true,
        columns: ['val'],
        rows: [{'val': 1}],
        metadata: QueryMetadataModel(rowCount: 1, executionTimeMs: 4.2),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: QueryPlaygroundScreen(
            sources: [mockSource],
            apiClient: mockClient,
            nodeStatus: 'ACTIVE',
            onBack: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final editorField = find.descendant(of: find.byType(QueryEditor), matching: find.byType(TextField));

    // Iteration 1: SELECT 1
    await tester.enterText(editorField, 'SELECT 1;');
    await tester.pump();
    await tester.tap(find.text('Run Query'));
    await tester.pumpAndSettle();
    expect(find.text('Query Results'), findsOneWidget);

    // Iteration 2: SELECT 2
    await tester.enterText(editorField, 'SELECT 2;');
    await tester.pump();
    expect(find.text('SELECT 2;'), findsOneWidget);
    await tester.tap(find.text('Run Query'));
    await tester.pumpAndSettle();

    // Iteration 3: SELECT 3
    await tester.enterText(editorField, 'SELECT 3;');
    await tester.pump();
    expect(find.text('SELECT 3;'), findsOneWidget);
    await tester.tap(find.text('Run Query'));
    await tester.pumpAndSettle();

    // Iteration 4: Command Query CREATE TABLE
    await tester.enterText(editorField, 'CREATE TABLE focus_probe (id INT);');
    await tester.pump();
    expect(find.text('CREATE TABLE focus_probe (id INT);'), findsOneWidget);
  });
}
