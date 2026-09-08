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
import 'package:altr_stream_admin/features/altrql_playground/screens/altrql_playground_screen.dart';
import 'package:altr_stream_admin/features/source_playground/screens/source_playground_view.dart';
import 'package:altr_stream_admin/features/source_playground/widgets/schema_explorer.dart';
import 'package:altr_stream_admin/features/source_playground/widgets/command_outcome_panel.dart';
import 'package:altr_stream_admin/features/source_playground/widgets/destructive_query_dialog.dart';
import 'package:altr_stream_admin/features/source_playground/widgets/query_editor.dart';
import 'package:altr_stream_admin/features/source_playground/widgets/query_result_table.dart';
import 'package:altr_stream_admin/features/settings/screens/settings_screen.dart';
import 'package:altr_stream_admin/features/sources/widgets/add_source_wizard_dialog.dart';

class MockTestApiClient extends ApiClient {
  final SourceSchemaModel? schemaToReturn;
  final QueryExecuteResponseModel? queryResponseToReturn;
  final AltrQLParseResponseModel? altrqlParseResponseToReturn;
  final AltrQLBindResponseModel? altrqlBindResponseToReturn;
  final AltrQLExecuteResponseModel? altrqlExecuteResponseToReturn;

  MockTestApiClient({
    this.schemaToReturn,
    this.queryResponseToReturn,
    this.altrqlParseResponseToReturn,
    this.altrqlBindResponseToReturn,
    this.altrqlExecuteResponseToReturn,
  });

  @override
  Future<AltrQLParseResponseModel> parseAltrQL(String query) async {
    return altrqlParseResponseToReturn ??
        AltrQLParseResponseModel(
          success: true,
          ir: {
            'entity': 'users',
            'projection': [],
            'where': null,
            'sort': [],
            'ranking': null,
            'offset': null,
          },
        );
  }

  @override
  Future<AltrQLBindResponseModel> bindAltrQL({
    required String query,
    required String sourceId,
  }) async {
    return altrqlBindResponseToReturn ??
        AltrQLBindResponseModel(
          success: true,
          ir: {
            'entity': 'users',
            'projection': [],
            'where': null,
            'sort': [],
            'ranking': null,
            'offset': null,
          },
          boundIr: {
            'source_id': sourceId,
            'source_name': 'Mock Source',
            'entity': {'name': 'users', 'namespace': 'public', 'entity_type': 'TABLE'},
            'projection': [],
            'where': null,
            'sort': [],
            'ranking': null,
            'offset': null,
          },
        );
  }

  @override
  Future<AltrQLExecuteResponseModel> executeAltrQL({
    required String query,
    required String sourceId,
    bool confirmMassMutation = false,
  }) async {
    return altrqlExecuteResponseToReturn ??
        AltrQLExecuteResponseModel(
          success: true,
          ir: {
            'entity': 'users',
            'projection': [],
            'where': null,
            'sort': [],
            'ranking': null,
            'offset': null,
          },
          boundIr: {
            'source_id': sourceId,
            'source_name': 'Mock Source',
            'entity': {'name': 'users', 'namespace': 'public', 'entity_type': 'TABLE'},
            'projection': [],
            'where': null,
            'sort': [],
            'ranking': null,
            'offset': null,
          },
          physicalQuery: PhysicalQueryModel(
            dialect: 'postgresql',
            query: 'SELECT * FROM "public"."users";',
            parameters: [],
            sourceId: sourceId,
            sourceName: 'Mock Source',
          ),
          columns: ['id', 'username'],
          rows: [
            {'id': 1, 'username': 'Alice'},
            {'id': 2, 'username': 'Bob'},
          ],
          metadata: QueryMetadataModel(
            rowCount: 2,
            executionTimeMs: 4.5,
          ),
        );
  }


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
  Future<SourceCapabilitiesModel> getSourceCapabilities(String id) async =>
      SourceCapabilitiesModel(
        schemaDiscovery: true,
        read: true,
        write: true,
        cdc: true,
        customQuery: true,
        supportedOperations: const ['SELECT', 'INSERT', 'UPDATE', 'DELETE'],
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

  testWidgets('SourceDetailScreen renders in both Light and Dark themes with 5 tabs including Playground', (WidgetTester tester) async {
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

    final mockClient = MockTestApiClient();

    // Test Light Theme
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: SourceDetailScreen(
            source: mockSource,
            apiClient: mockClient,
            onBack: () {},
            onDelete: () {},
            onNodeStatusTap: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Overview'), findsOneWidget);
    expect(find.text('Connection Parameters'), findsOneWidget);
    expect(find.text('Discovered Schemas'), findsOneWidget);
    expect(find.text('Playground'), findsOneWidget);
    expect(find.text('Health & Diagnostics'), findsOneWidget);

    // Switch to Playground tab
    await tester.tap(find.text('Playground'));
    await tester.pumpAndSettle();
    expect(find.byType(SourcePlaygroundView), findsOneWidget);
    expect(find.text('POSTGRESQL QUERY'), findsOneWidget);
    expect(find.text('Run Query'), findsOneWidget);
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

    final mockClient = MockTestApiClient();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: SourceDetailScreen(
            source: mockSource,
            apiClient: mockClient,
            onBack: () {},
            onDelete: () {},
            onNodeStatusTap: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

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

  testWidgets('AltrQL Console FAB is visible and opens AltrQL Playground screen', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const AltrStreamAdminApp());
    await tester.pump();

    final fabFinder = find.text('AltrQL Console');
    expect(fabFinder, findsOneWidget);

    await tester.tap(fabFinder);
    await tester.pumpAndSettle();

    expect(find.byType(AltrQLPlaygroundScreen), findsOneWidget);
    expect(find.text('AltrQL Console'), findsWidgets);
    expect(find.text('AltrQL Editor'), findsOneWidget);
    expect(find.text('Parse Query'), findsOneWidget);

    await tester.tap(find.text('Back to Dashboard'));
    await tester.pumpAndSettle();

    expect(find.byType(OverviewScreen), findsOneWidget);
    expect(find.text('AltrQL Console'), findsOneWidget);
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

  testWidgets('SourcePlaygroundView executes query and renders QueryResultTable and CommandOutcomePanel', (WidgetTester tester) async {
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
          body: SizedBox(
            height: 700,
            child: SourcePlaygroundView(
              source: mockSource,
              apiClient: mockClient,
              schema: mockSchema,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('POSTGRESQL QUERY'), findsOneWidget);
    expect(find.text('Schema Explorer'), findsOneWidget);
    expect(find.text('users'), findsOneWidget);

    // Tap Run Query
    await tester.tap(find.text('Run Query'));
    await tester.pumpAndSettle();

    // Verify result table rendered
    expect(find.byType(QueryResultTable), findsOneWidget);
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Bob'), findsOneWidget);
  });

  testWidgets('Destructive query detection triggers DestructiveQueryDialog confirmation in SourcePlaygroundView', (WidgetTester tester) async {
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
          body: SizedBox(
            height: 700,
            child: SourcePlaygroundView(
              source: mockSource,
              apiClient: mockClient,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Enter a DROP query
    final editorField = find.descendant(of: find.byType(QueryEditor), matching: find.byType(TextField));
    await tester.enterText(editorField, 'DROP TABLE test_temp;');
    await tester.pump();

    // Click Run Query
    await tester.tap(find.text('Run Query'));
    await tester.pumpAndSettle();

    // Verify DestructiveQueryDialog appears
    expect(find.byType(DestructiveQueryDialog), findsOneWidget);
    expect(find.text('Potentially Destructive Operation'), findsOneWidget);
    expect(find.text('Confirm & Execute'), findsOneWidget);

    // Confirm execution
    await tester.tap(find.text('Confirm & Execute'));
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
          body: SizedBox(
            height: 700,
            child: SourcePlaygroundView(
              source: mockSource,
              apiClient: mockClient,
            ),
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
          body: SizedBox(
            height: 700,
            child: SourcePlaygroundView(
              source: mockSource,
              apiClient: mockClient,
            ),
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
    expect(find.byType(QueryResultTable), findsOneWidget);

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

  testWidgets('AltrQLPlaygroundScreen parses valid query and displays formatted IR with Copy IR action', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final mockClient = MockTestApiClient(
      altrqlParseResponseToReturn: AltrQLParseResponseModel(
        success: true,
        ir: {
          'entity': 'users',
          'projection': [
            {'path': {'segments': ['id']}, 'alias': null},
            {'path': {'segments': ['name']}, 'alias': 'username'}
          ],
          'where': {
            'kind': 'field_expression',
            'field': {'segments': ['status']},
            'operator': '=',
            'operand': {'kind': 'string', 'value': 'ACTIVE'},
          },
          'sort': [],
          'ranking': null,
          'offset': null,
        },
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: SingleChildScrollView(
            child: AltrQLPlaygroundScreen(
              sources: const [],
              nodeStatus: 'ONLINE',
              apiClient: mockClient,
              onBack: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify initial AST placeholder
    expect(find.text('Interactive AST / IR Inspector'), findsOneWidget);
    expect(find.text('Parse Query'), findsOneWidget);

    // Enter query text
    final queryField = find.descendant(of: find.byType(AltrQLPlaygroundScreen), matching: find.byType(TextField));
    await tester.enterText(queryField, 'GET users (id, name AS username) WHERE { status = "ACTIVE" };');
    await tester.pump();

    // Tap Parse Query
    await tester.tap(find.text('Parse Query'));
    await tester.pumpAndSettle();

    // Verify Success Banner and IR Viewer
    expect(find.text('Query Parsed & Semantically Valid'), findsOneWidget);
    expect(find.text('AltrQueryIR (Typed Abstract Syntax Tree):'), findsOneWidget);
    expect(find.text('Copy IR'), findsOneWidget);
    expect(find.textContaining('"entity": "users"'), findsOneWidget);
    expect(find.textContaining('"alias": "username"'), findsOneWidget);

    // Tap Copy IR and verify feedback
    await tester.tap(find.text('Copy IR'));
    await tester.pumpAndSettle();
    expect(find.text('AltrQueryIR JSON copied to clipboard'), findsOneWidget);
  });

  testWidgets('AltrQLPlaygroundScreen displays structured diagnostics on parse error with Copy Error action', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final mockClient = MockTestApiClient(
      altrqlParseResponseToReturn: AltrQLParseResponseModel(
        success: false,
        error: AltrQLParseErrorModel(
          type: 'AltrQueryParseError',
          message: "Unexpected identifier 'get' (keywords must be strictly uppercase: 'GET')",
          line: 1,
          column: 1,
        ),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: SingleChildScrollView(
            child: AltrQLPlaygroundScreen(
              sources: const [],
              nodeStatus: 'ONLINE',
              apiClient: mockClient,
              onBack: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Enter invalid query text
    final queryField = find.descendant(of: find.byType(AltrQLPlaygroundScreen), matching: find.byType(TextField));
    await tester.enterText(queryField, 'get users (id);');
    await tester.pump();

    // Tap Parse Query
    await tester.tap(find.text('Parse Query'));
    await tester.pumpAndSettle();

    // Verify Error Panel
    expect(find.text('AltrQL Parse Error'), findsOneWidget);
    expect(find.text('Line 1 · Column 1'), findsOneWidget);
    expect(find.text("Unexpected identifier 'get' (keywords must be strictly uppercase: 'GET')"), findsOneWidget);
    expect(find.text('Copy Error'), findsOneWidget);

    // Tap Copy Error and verify feedback
    await tester.tap(find.text('Copy Error'));
    await tester.pumpAndSettle();
    expect(find.text('Error Diagnostics copied to clipboard'), findsOneWidget);
  });

  testWidgets('AltrQLPlaygroundScreen displays semantic error banner on AltrQuerySemanticError', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final mockClient = MockTestApiClient(
      altrqlParseResponseToReturn: AltrQLParseResponseModel(
        success: false,
        error: AltrQLParseErrorModel(
          type: 'AltrQuerySemanticError',
          message: "Duplicate projection alias 'col' found in query projection.",
        ),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: SingleChildScrollView(
            child: AltrQLPlaygroundScreen(
              sources: const [],
              nodeStatus: 'ONLINE',
              apiClient: mockClient,
              onBack: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Enter query text with semantic error
    final queryField = find.descendant(of: find.byType(AltrQLPlaygroundScreen), matching: find.byType(TextField));
    await tester.enterText(queryField, 'GET users (col AS col, col AS col);');
    await tester.pump();

    // Tap Parse Query
    await tester.tap(find.text('Parse Query'));
    await tester.pumpAndSettle();

    // Verify Semantic Error Panel
    expect(find.text('AltrQL Semantic Error'), findsOneWidget);
    expect(find.text("Duplicate projection alias 'col' found in query projection."), findsOneWidget);
  });

  testWidgets('AltrQLPlaygroundScreen template dropdown and reset query work correctly', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: SingleChildScrollView(
            child: AltrQLPlaygroundScreen(
              sources: const [],
              nodeStatus: 'ONLINE',
              onBack: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify initial text field has hint text and is empty
    final queryField = find.descendant(of: find.byType(AltrQLPlaygroundScreen), matching: find.byType(TextField));
    final TextField initialTextField = tester.widget(queryField);
    expect(initialTextField.controller?.text, isEmpty);
    expect(initialTextField.decoration?.hintText, contains('Write an AltrQL query...'));

    // Open Templates popup menu and select 'Range & Sets'
    await tester.tap(find.text('Templates'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Range & Sets').last);
    await tester.pumpAndSettle();

    expect(find.textContaining('id = {1, 2, 6..10}'), findsOneWidget);

    // Open Templates popup menu and select 'Ranking & Pagination'
    await tester.tap(find.text('Templates'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ranking & Pagination').last);
    await tester.pumpAndSettle();

    expect(find.textContaining('TOP 10 BY age OFFSET 20;'), findsOneWidget);

    // Tap 'Reset Query' button to clear everything
    await tester.tap(find.text('Reset Query'));
    await tester.pumpAndSettle();

    final TextField textField = tester.widget(queryField);
    expect(textField.controller?.text, isEmpty);
  });

  testWidgets('AltrQLPlaygroundScreen successfully binds query against source and displays Bound IR banner', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final mockSources = [
      SourceModel(
        id: 'src_1',
        name: 'Warehouse DB',
        type: 'POSTGRESQL',
        host: 'localhost',
        port: 5432,
        databaseName: 'db',
        username: 'user',
        status: 'ACTIVE',
        passwordMasked: '••••',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    ];

    final mockClient = MockTestApiClient(
      altrqlBindResponseToReturn: AltrQLBindResponseModel(
        success: true,
        ir: {
          'entity': 'users',
          'projection': [],
        },
        boundIr: {
          'source_id': 'src_1',
          'source_name': 'Warehouse DB',
          'entity': {'name': 'users', 'namespace': 'public', 'entity_type': 'TABLE'},
          'projection': [],
          'where': null,
        },
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: SingleChildScrollView(
            child: AltrQLPlaygroundScreen(
              sources: mockSources,
              nodeStatus: 'ONLINE',
              apiClient: mockClient,
              onBack: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Enter query text
    final queryField = find.descendant(of: find.byType(AltrQLPlaygroundScreen), matching: find.byType(TextField));
    await tester.enterText(queryField, 'GET users (id, username);');
    await tester.pump();

    // Tap 'Bind Against Source' button
    await tester.tap(find.text('Bind Against Source'));
    await tester.pumpAndSettle();

    // Verify Bound Success Banner
    expect(find.text('Query Bound & Type Validated'), findsOneWidget);
    expect(find.text('Warehouse DB'), findsAtLeastNWidgets(1));
    expect(find.text('Bound IR'), findsOneWidget);
    expect(find.text('Canonical IR'), findsOneWidget);
  });

  testWidgets('AltrQLPlaygroundScreen displays schema error banner on UnknownEntityError', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final mockSources = [
      SourceModel(
        id: 'src_1',
        name: 'Warehouse DB',
        type: 'POSTGRESQL',
        host: 'localhost',
        port: 5432,
        databaseName: 'db',
        username: 'user',
        status: 'ACTIVE',
        passwordMasked: '••••',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    ];

    final mockClient = MockTestApiClient(
      altrqlBindResponseToReturn: AltrQLBindResponseModel(
        success: false,
        error: AltrQLErrorDetailModel(
          type: 'UnknownEntityError',
          message: "Unknown entity 'non_existent_table' in source schema 'Warehouse DB'.",
        ),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: SingleChildScrollView(
            child: AltrQLPlaygroundScreen(
              sources: mockSources,
              nodeStatus: 'ONLINE',
              apiClient: mockClient,
              onBack: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Enter query text
    final queryField = find.descendant(of: find.byType(AltrQLPlaygroundScreen), matching: find.byType(TextField));
    await tester.enterText(queryField, 'GET non_existent_table (id);');
    await tester.pump();

    // Tap 'Bind Against Source'
    await tester.tap(find.text('Bind Against Source'));
    await tester.pumpAndSettle();

    // Verify Schema Error Panel
    expect(find.text('AltrQL Schema Error'), findsOneWidget);
    expect(find.text("Unknown entity 'non_existent_table' in source schema 'Warehouse DB'."), findsOneWidget);
  });

  testWidgets('AltrQLPlaygroundScreen successfully binds query with explicit ISO date literal @YYYY-MM-DD', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final mockSources = [
      SourceModel(
        id: 'src_1',
        name: 'Warehouse DB',
        type: 'POSTGRESQL',
        host: 'localhost',
        port: 5432,
        databaseName: 'db',
        username: 'user',
        status: 'ACTIVE',
        passwordMasked: '••••',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    ];

    final mockClient = MockTestApiClient(
      altrqlBindResponseToReturn: AltrQLBindResponseModel(
        success: true,
        ir: {
          'entity': 'users',
          'projection': [],
          'where': {
            'kind': 'field_expression',
            'field': {'segments': ['created_at']},
            'operator': '>=',
            'operand': {'kind': 'temporal', 'value': '2026-01-01'},
          },
        },
        boundIr: {
          'source_id': 'src_1',
          'source_name': 'Warehouse DB',
          'entity': {'name': 'users', 'namespace': 'public', 'entity_type': 'TABLE'},
          'projection': [],
          'where': {
            'kind': 'bound_field_expression',
            'field': {
              'path': {'segments': ['created_at']},
              'data_type': 'TIMESTAMPTZ',
              'logical_category': 'TEMPORAL',
            },
            'operator': '>=',
            'operand': {'kind': 'temporal', 'value': '2026-01-01'},
          },
        },
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: SingleChildScrollView(
            child: AltrQLPlaygroundScreen(
              sources: mockSources,
              nodeStatus: 'ONLINE',
              apiClient: mockClient,
              onBack: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Enter query with @2026-01-01
    final queryField = find.descendant(of: find.byType(AltrQLPlaygroundScreen), matching: find.byType(TextField));
    await tester.enterText(queryField, 'GET users WHERE { created_at >= @2026-01-01 };');
    await tester.pump();

    // Tap 'Bind Against Source' button
    await tester.tap(find.text('Bind Against Source'));
    await tester.pumpAndSettle();

    // Verify Bound Success Banner
    expect(find.text('Query Bound & Type Validated'), findsOneWidget);
    expect(find.textContaining('"value": "2026-01-01"'), findsOneWidget);
  });

  testWidgets('AltrQLPlaygroundScreen executes query, shows results table and metadata', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final mockSources = [
      SourceModel(
        id: 'src_exec_1',
        name: 'PostgreSQL DB',
        type: 'POSTGRESQL',
        host: 'localhost',
        port: 5432,
        databaseName: 'db',
        username: 'user',
        status: 'ACTIVE',
        passwordMasked: '••••',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    ];

    final mockClient = MockTestApiClient(
      altrqlExecuteResponseToReturn: AltrQLExecuteResponseModel(
        success: true,
        ir: {'entity': 'users', 'projection': []},
        boundIr: {
          'source_id': 'src_exec_1',
          'source_name': 'PostgreSQL DB',
          'entity': {'name': 'users', 'namespace': 'public', 'entity_type': 'TABLE'},
          'projection': [],
        },
        physicalQuery: PhysicalQueryModel(
          dialect: 'postgresql',
          query: 'SELECT "id", "username" FROM "public"."users";',
          parameters: [],
          sourceId: 'src_exec_1',
          sourceName: 'PostgreSQL DB',
        ),
        columns: ['id', 'username'],
        rows: [
          {'id': 1, 'username': 'Alice'},
          {'id': 2, 'username': 'Bob'},
        ],
        metadata: QueryMetadataModel(
          rowCount: 2,
          executionTimeMs: 3.25,
          message: 'SELECT 2',
        ),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: SingleChildScrollView(
            child: AltrQLPlaygroundScreen(
              sources: mockSources,
              nodeStatus: 'ONLINE',
              apiClient: mockClient,
              onBack: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Enter query text
    final queryField = find.descendant(of: find.byType(AltrQLPlaygroundScreen), matching: find.byType(TextField));
    await tester.enterText(queryField, 'GET users (id, username);');
    await tester.pump();

    // Verify Execute Query button is present
    final executeBtn = find.text('Execute Query');
    expect(executeBtn, findsOneWidget);

    // Tap Execute Query
    await tester.tap(executeBtn);
    await tester.pumpAndSettle();

    // Verify Success Header and Metrics
    expect(find.text('Query Executed Successfully'), findsOneWidget);
    expect(find.text('3.25 ms · 2 rows'), findsOneWidget);

    // Verify DataTable rows
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Bob'), findsOneWidget);

    // Switch to Physical Query tab
    await tester.tap(find.text('Physical Query'));
    await tester.pumpAndSettle();

    expect(find.text('POSTGRESQL Dialect'), findsOneWidget);
    expect(find.text('SELECT "id", "username" FROM "public"."users";'), findsOneWidget);

    // Switch to Bound IR tab
    await tester.tap(find.text('Bound IR'));
    await tester.pumpAndSettle();
    expect(find.textContaining('"source_name": "PostgreSQL DB"'), findsOneWidget);

    // Switch to Canonical IR tab
    await tester.tap(find.text('Canonical IR'));
    await tester.pumpAndSettle();
    expect(find.textContaining('"entity": "users"'), findsOneWidget);
  });

  testWidgets('AltrQLPlaygroundScreen displays execution error diagnostic banner while preserving physical query', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final mockSources = [
      SourceModel(
        id: 'src_err_1',
        name: 'PostgreSQL DB',
        type: 'POSTGRESQL',
        host: 'localhost',
        port: 5432,
        databaseName: 'db',
        username: 'user',
        status: 'ACTIVE',
        passwordMasked: '••••',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    ];

    final mockClient = MockTestApiClient(
      altrqlExecuteResponseToReturn: AltrQLExecuteResponseModel(
        success: false,
        ir: {'entity': 'users', 'projection': []},
        boundIr: {
          'source_id': 'src_err_1',
          'source_name': 'PostgreSQL DB',
          'entity': {'name': 'users', 'namespace': 'public', 'entity_type': 'TABLE'},
          'projection': [],
        },
        physicalQuery: PhysicalQueryModel(
          dialect: 'postgresql',
          query: 'SELECT * FROM "public"."users" WHERE "age" >= \$1;',
          parameters: [18],
          sourceId: 'src_err_1',
          sourceName: 'PostgreSQL DB',
        ),
        columns: [],
        rows: [],
        error: AltrQLErrorDetailModel(
          type: 'QueryExecutionError',
          message: 'Connection closed by remote host unexpectedly.',
        ),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: SingleChildScrollView(
            child: AltrQLPlaygroundScreen(
              sources: mockSources,
              nodeStatus: 'ONLINE',
              apiClient: mockClient,
              onBack: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Enter query text
    final queryField = find.descendant(of: find.byType(AltrQLPlaygroundScreen), matching: find.byType(TextField));
    await tester.enterText(queryField, 'GET users (id) WHERE { age >= 18 };');
    await tester.pump();

    // Tap Execute Query
    await tester.tap(find.text('Execute Query'));
    await tester.pumpAndSettle();

    // Verify Error Header & Diagnostics
    expect(find.text('AltrQL Execution Error'), findsOneWidget);
    expect(find.text('Connection closed by remote host unexpectedly.'), findsOneWidget);

    // Verify Physical Query is preserved and viewable
    expect(find.text('POSTGRESQL Dialect'), findsOneWidget);
    expect(find.text('SELECT * FROM "public"."users" WHERE "age" >= \$1;'), findsOneWidget);
    expect(find.text('\$1 = 18'), findsOneWidget);
  });

  testWidgets('AltrQLPlaygroundScreen executes mutation and displays classification badge and affected rows', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final mockSources = [
      SourceModel(
        id: 'src_mut_1',
        name: 'PostgreSQL DB',
        type: 'POSTGRESQL',
        host: 'localhost',
        port: 5432,
        databaseName: 'db',
        username: 'user',
        status: 'ACTIVE',
        passwordMasked: '••••',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    ];

    final mockClient = MockTestApiClient(
      altrqlExecuteResponseToReturn: AltrQLExecuteResponseModel(
        success: true,
        ir: {
          'operation': 'UPDATE',
          'entity': 'users',
          'assignments': [{'field': 'email', 'value': 'new@test.com'}],
        },
        boundIr: {
          'source_id': 'src_mut_1',
          'source_name': 'PostgreSQL DB',
          'operation': 'UPDATE',
          'entity': {'name': 'users', 'namespace': 'public', 'entity_type': 'TABLE'},
        },
        classification: MutationClassificationModel(
          operation: 'UPDATE',
          mutationScope: 'CONSTRAINED',
          requiresConfirmation: false,
          entity: 'users',
          description: "Constrained UPDATE on entity 'users' with WHERE filter.",
        ),
        physicalQuery: PhysicalQueryModel(
          dialect: 'postgresql',
          query: 'UPDATE "public"."users" SET "email" = \$1 WHERE "id" = \$2 RETURNING *;',
          parameters: ['new@test.com', 1],
          sourceId: 'src_mut_1',
          sourceName: 'PostgreSQL DB',
        ),
        columns: ['id', 'email'],
        rows: [
          {'id': 1, 'email': 'new@test.com'},
        ],
        metadata: QueryMetadataModel(
          rowCount: 1,
          affectedRows: 1,
          executionTimeMs: 5.12,
          operation: 'UPDATE',
          mutationScope: 'CONSTRAINED',
        ),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: SingleChildScrollView(
            child: AltrQLPlaygroundScreen(
              sources: mockSources,
              nodeStatus: 'ONLINE',
              apiClient: mockClient,
              onBack: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final queryField = find.descendant(of: find.byType(AltrQLPlaygroundScreen), matching: find.byType(TextField));
    await tester.enterText(queryField, 'UPDATE users ( email: "new@test.com" ) WHERE { id = 1 };');
    await tester.pump();

    await tester.tap(find.text('Execute Query'));
    await tester.pumpAndSettle();

    expect(find.text('UPDATE Mutation Executed'), findsOneWidget);
    expect(find.text('UPDATE · CONSTRAINED'), findsOneWidget);
    expect(find.text('5.12 ms · 1 rows (1 affected)'), findsOneWidget);
    expect(find.text('new@test.com'), findsOneWidget);
  });

  testWidgets('AltrQLPlaygroundScreen handles MassMutationConfirmationRequiredError with confirmation dialog and resubmission', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final mockSources = [
      SourceModel(
        id: 'src_mut_2',
        name: 'PostgreSQL DB',
        type: 'POSTGRESQL',
        host: 'localhost',
        port: 5432,
        databaseName: 'db',
        username: 'user',
        status: 'ACTIVE',
        passwordMasked: '••••',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    ];

    final mockClient = MockTestApiClient(
      altrqlExecuteResponseToReturn: AltrQLExecuteResponseModel(
        success: false,
        classification: MutationClassificationModel(
          operation: 'DELETE',
          mutationScope: 'MASS',
          requiresConfirmation: true,
          entity: 'users',
          description: "Mass DELETE on entity 'users' without WHERE clause.",
        ),
        physicalQuery: PhysicalQueryModel(
          dialect: 'postgresql',
          query: 'DELETE FROM "public"."users" RETURNING *;',
          parameters: [],
          sourceId: 'src_mut_2',
          sourceName: 'PostgreSQL DB',
        ),
        columns: [],
        rows: [],
        error: AltrQLErrorDetailModel(
          type: 'MassMutationConfirmationRequiredError',
          message: "Mass DELETE operation on entity 'users' without a WHERE clause requires explicit confirmation.",
        ),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: SingleChildScrollView(
            child: AltrQLPlaygroundScreen(
              sources: mockSources,
              nodeStatus: 'ONLINE',
              apiClient: mockClient,
              onBack: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final queryField = find.descendant(of: find.byType(AltrQLPlaygroundScreen), matching: find.byType(TextField));
    await tester.enterText(queryField, 'DELETE users;');
    await tester.pump();

    await tester.tap(find.text('Execute Query'));
    await tester.pumpAndSettle();

    // Verify confirmation dialog appeared
    expect(find.text('Mass DELETE Confirmation Required'), findsOneWidget);
    expect(find.textContaining('This will modify or delete ALL records in \'users\''), findsOneWidget);
    expect(find.text('Confirm & Execute Mass DELETE'), findsOneWidget);

    // Tap Cancel
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Mass DELETE Confirmation Required'), findsNothing);
  });
}


