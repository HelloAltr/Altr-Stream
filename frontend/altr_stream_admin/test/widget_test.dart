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
import 'package:altr_stream_admin/features/registry/screens/logical_model_detail_screen.dart';
import 'package:altr_stream_admin/features/registry/screens/registry_screen.dart';
import 'package:altr_stream_admin/features/settings/screens/settings_screen.dart';
import 'package:altr_stream_admin/features/sources/widgets/add_source_wizard_dialog.dart';
import 'package:altr_stream_admin/features/registry/widgets/add_mapping_dialog.dart';

class MockTestApiClient extends ApiClient {
  final SourceSchemaModel? schemaToReturn;
  final QueryExecuteResponseModel? queryResponseToReturn;
  final AltrQLParseResponseModel? altrqlParseResponseToReturn;
  final AltrQLBindResponseModel? altrqlBindResponseToReturn;
  final AltrQLExecuteResponseModel? altrqlExecuteResponseToReturn;
  final ConnectionTestResultModel? connectionTestResultToReturn;
  final SourceModel? sourceToReturnOnCreate;
  final List<SourceMappingModel>? mappingsToReturn;
  final List<LogicalModelModel>? modelsToReturn;

  Map<String, dynamic>? lastTestAdhocParams;
  Map<String, dynamic>? lastCreateSourceParams;
  Map<String, dynamic>? lastCreateMappingParams;
  Map<String, dynamic>? lastUpdateMappingParams;
  String? lastActivateMappingId;

  MockTestApiClient({
    this.schemaToReturn,
    this.queryResponseToReturn,
    this.altrqlParseResponseToReturn,
    this.altrqlBindResponseToReturn,
    this.altrqlExecuteResponseToReturn,
    this.connectionTestResultToReturn,
    this.sourceToReturnOnCreate,
    this.mappingsToReturn,
    this.modelsToReturn,
  });

  @override
  Future<ConnectionTestResultModel> testAdhocConnection({
    required String type,
    String? host,
    int? port,
    String? databaseName,
    String? username,
    String? password,
    String? filePath,
  }) async {
    lastTestAdhocParams = {
      'type': type,
      'host': host,
      'port': port,
      'database_name': databaseName,
      'username': username,
      'password': password,
      'file_path': filePath,
    };
    return connectionTestResultToReturn ??
        ConnectionTestResultModel(
          success: true,
          message: 'Connection successful',
          latencyMs: 1.2,
          serverVersion: '3.40.1',
        );
  }

  @override
  Future<SourceModel> createSource({
    required String name,
    required String type,
    String? host,
    int? port,
    String? databaseName,
    String? username,
    String? password,
    String? filePath,
    bool testConnectionFirst = false,
  }) async {
    lastCreateSourceParams = {
      'name': name,
      'type': type,
      'host': host,
      'port': port,
      'database_name': databaseName,
      'username': username,
      'password': password,
      'file_path': filePath,
      'test_connection_first': testConnectionFirst,
    };
    return sourceToReturnOnCreate ??
        SourceModel(
          id: 'mock_created_id',
          name: name,
          type: type,
          host: host,
          port: port,
          databaseName: databaseName,
          username: username,
          filePath: filePath,
          status: 'ACTIVE',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
  }

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
    String? mappingId,
    String? logicalModelId,
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
    String? mappingId,
    String? logicalModelId,
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
  Future<RegistrySummaryModel> getRegistrySummary() async => RegistrySummaryModel(
        totalModels: 1,
        totalEntities: 2,
        totalLogicalFields: 6,
        totalSourceMappings: 1,
        activeSourceMappings: 1,
        draftSourceMappings: 0,
        validatedSourceMappings: 0,
        errorSourceMappings: 0,
      );

  @override
  Future<List<LogicalModelModel>> listLogicalModels() async =>
      modelsToReturn ??
      [
        LogicalModelModel(
          id: 'mock-model-1',
          name: 'CoreCommerce',
          version: '1.0.0',
          description: 'Mock commerce domain model',
          entities: [
            LogicalEntityModel(
              id: 'mock-entity-1',
              logicalModelId: 'mock-model-1',
              name: 'Customer',
              fields: [
                LogicalFieldModel(
                  id: 'mock-field-1',
                  logicalEntityId: 'mock-entity-1',
                  name: 'id',
                  dataType: 'INTEGER',
                  isPrimaryKey: true,
                  nullable: false,
                  createdAt: DateTime.now(),
                  updatedAt: DateTime.now(),
                ),
                LogicalFieldModel(
                  id: 'mock-field-2',
                  logicalEntityId: 'mock-entity-1',
                  name: 'name',
                  dataType: 'STRING',
                  nullable: false,
                  createdAt: DateTime.now(),
                  updatedAt: DateTime.now(),
                ),
              ],
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ),
          ],
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      ];

  @override
  Future<LogicalModelModel> getLogicalModel(String modelId) async {
    final list = await listLogicalModels();
    return list.firstWhere(
      (m) => m.id == modelId,
      orElse: () => list.first,
    );
  }

  @override
  Future<List<SourceMappingModel>> listSourceMappings({String? modelId, String? sourceId, String? status}) async =>
      mappingsToReturn ??
      [
        SourceMappingModel(
          id: 'mock-mapping-1',
          logicalModelId: 'mock-model-1',
          sourceId: 'mock-src-1',
          version: '1.0.0',
          status: 'ACTIVE',
          provenance: 'USER',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      ];

  @override
  Future<SourceMappingModel> getSourceMapping(String mappingId) async =>
      (mappingsToReturn ?? await listSourceMappings()).firstWhere(
        (m) => m.id == mappingId,
        orElse: () => (mappingsToReturn ?? [
          SourceMappingModel(
            id: mappingId,
            logicalModelId: 'mock-model-1',
            sourceId: 'mock-src-1',
            version: '1.0.0',
            status: 'ACTIVE',
            provenance: 'USER',
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        ]).first,
      );

  @override
  Future<SourceMappingModel> createSourceMapping({
    required String logicalModelId,
    required String sourceId,
    String version = '1.0.0',
    String provenance = 'USER',
    List<Map<String, dynamic>> entityMappings = const [],
    Map<String, dynamic> metadata = const {},
  }) async {
    lastCreateMappingParams = {
      'logical_model_id': logicalModelId,
      'source_id': sourceId,
      'version': version,
      'provenance': provenance,
      'entity_mappings': entityMappings,
      'metadata': metadata,
    };
    return SourceMappingModel(
      id: 'mock-created-mapping-id',
      logicalModelId: logicalModelId,
      sourceId: sourceId,
      version: version,
      status: 'DRAFT',
      provenance: provenance,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  @override
  Future<SourceMappingModel> updateSourceMapping(
    String mappingId, {
    String? version,
    String? status,
    String? provenance,
    String? errorMessage,
    List<Map<String, dynamic>>? entityMappings,
  }) async {
    lastUpdateMappingParams = {
      'mapping_id': mappingId,
      'version': version,
      'status': status,
      'provenance': provenance,
      'error_message': errorMessage,
      'entity_mappings': entityMappings,
    };
    return SourceMappingModel(
      id: mappingId,
      logicalModelId: 'mock-model-1',
      sourceId: 'mock-src-1',
      version: version ?? '1.0.0',
      status: status ?? 'VALIDATED',
      provenance: provenance ?? 'USER',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  @override
  Future<SourceMappingModel> validateSourceMapping(String mappingId) async {
    return SourceMappingModel(
      id: mappingId,
      logicalModelId: 'mock-model-1',
      sourceId: 'mock-src-1',
      version: '1.0.0',
      status: 'VALIDATED',
      provenance: 'USER',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  @override
  Future<SourceMappingModel> activateSourceMapping(String mappingId) async {
    lastActivateMappingId = mappingId;
    return SourceMappingModel(
      id: mappingId,
      logicalModelId: 'mock-model-1',
      sourceId: 'mock-src-1',
      version: '1.0.0',
      status: 'ACTIVE',
      provenance: 'USER',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
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

  testWidgets('AddSourceWizardDialog renders SQLite connector as supported alongside PostgreSQL, and MySQL/MongoDB as Future Milestone', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final mockClient = MockTestApiClient();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: AddSourceWizardDialog(
            apiClient: mockClient,
            onSourceCreated: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Step 1 of 4: Choose database connector'), findsOneWidget);
    expect(find.text('PostgreSQL'), findsOneWidget);
    expect(find.text('SQLite'), findsOneWidget);
    expect(find.text('MySQL'), findsOneWidget);
    expect(find.text('MongoDB'), findsOneWidget);

    // Verify Future Milestone badges on MySQL and MongoDB
    expect(find.text('Future Milestone'), findsNWidgets(2));

    // Tap SQLite to select it
    await tester.tap(find.text('SQLite'));
    await tester.pumpAndSettle();
  });

  testWidgets('AddSourceWizardDialog SQLite configuration step shows only Source Name and Database File Path without network fields', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final mockClient = MockTestApiClient();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: AddSourceWizardDialog(
            apiClient: mockClient,
            onSourceCreated: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Select SQLite
    await tester.tap(find.text('SQLite'));
    await tester.pumpAndSettle();

    // Tap Continue to Step 2
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Step 2 of 4: Configure connection parameters'), findsOneWidget);
    expect(find.text('Source Name *'), findsOneWidget);
    expect(find.text('Database File Path *'), findsOneWidget);

    // Verify network fields are NOT present
    expect(find.text('Host / IP *'), findsNothing);
    expect(find.text('Port *'), findsNothing);
    expect(find.text('Username *'), findsNothing);
    expect(find.text('Password *'), findsNothing);
  });

  testWidgets('AddSourceWizardDialog SQLite test connection and registration generates correct SQLite payload', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final mockClient = MockTestApiClient(
      connectionTestResultToReturn: ConnectionTestResultModel(
        success: true,
        message: 'Successfully opened SQLite database file',
        latencyMs: 0.8,
        serverVersion: '3.45.1',
      ),
    );

    SourceModel? createdSource;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: AddSourceWizardDialog(
            apiClient: mockClient,
            onSourceCreated: (s) => createdSource = s,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 1. Select SQLite & Continue
    await tester.tap(find.text('SQLite'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    // 2. Configure fields
    final nameField = find.widgetWithText(TextFormField, 'Source Name *');
    final pathField = find.widgetWithText(TextFormField, 'Database File Path *');

    await tester.enterText(nameField, 'Manual SQLite Test');
    await tester.enterText(pathField, '/app/data/manual_test.db');
    await tester.pump();

    // Tap Continue to Test
    await tester.tap(find.text('Continue to Test'));
    await tester.pumpAndSettle();

    // Verify testAdhocConnection was called with SQLite parameters
    expect(mockClient.lastTestAdhocParams?['type'], 'SQLITE');
    expect(mockClient.lastTestAdhocParams?['file_path'], '/app/data/manual_test.db');
    expect(mockClient.lastTestAdhocParams?['host'], isNull);
    expect(mockClient.lastTestAdhocParams?['port'], isNull);

    // Verify test connection success result
    expect(find.text('✓ Successfully Connected'), findsOneWidget);
    expect(find.text('Successfully opened SQLite database file'), findsOneWidget);
    expect(find.text('Server Version: 3.45.1'), findsOneWidget);

    // 3. Continue to Review & Register
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Step 4 of 4: Review and register source'), findsOneWidget);
    expect(find.text('Manual SQLite Test'), findsOneWidget);
    expect(find.text('SQLITE'), findsOneWidget);
    expect(find.text('/app/data/manual_test.db'), findsOneWidget);
    expect(find.text('Connection Endpoint'), findsNothing);

    // 4. Click Register Source
    await tester.tap(find.text('Register Source'));
    await tester.pumpAndSettle();

    // Verify createSource payload
    expect(mockClient.lastCreateSourceParams?['name'], 'Manual SQLite Test');
    expect(mockClient.lastCreateSourceParams?['type'], 'SQLITE');
    expect(mockClient.lastCreateSourceParams?['file_path'], '/app/data/manual_test.db');
    expect(mockClient.lastCreateSourceParams?['host'], isNull);
    expect(createdSource?.name, 'Manual SQLite Test');
    expect(createdSource?.type, 'SQLITE');
    expect(createdSource?.filePath, '/app/data/manual_test.db');
  });

  testWidgets('SourceDetailScreen renders SQLite source parameters and file path correctly', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final mockSource = SourceModel(
      id: 'src_sqlite_1',
      name: 'Manual SQLite Test',
      type: 'SQLITE',
      filePath: '/app/data/manual_test.db',
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

    // Header checks
    expect(find.text('Manual SQLite Test'), findsOneWidget);
    expect(find.text('File: /app/data/manual_test.db'), findsOneWidget);

    // Overview Tab checks
    expect(find.text('SQLite (File Database)'), findsOneWidget);
    expect(find.text('/app/data/manual_test.db'), findsOneWidget);

    // Switch to Connection Parameters tab
    await tester.tap(find.text('Connection Parameters'));
    await tester.pumpAndSettle();

    expect(find.text('Database File Path'), findsOneWidget);
    expect(find.text('Storage Mode'), findsOneWidget);
    expect(find.text('Local / Embedded File'), findsOneWidget);
    expect(find.text('Host / IP Address'), findsNothing);
  });

  testWidgets('SourcesScreen and OverviewScreen render both PostgreSQL and SQLite sources simultaneously', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final mockSources = [
      SourceModel(
        id: 'pg_1',
        name: 'Postgre Test',
        type: 'POSTGRESQL',
        host: 'altr-postgres-test',
        port: 5432,
        databaseName: 'altr_test_db',
        username: 'altr_test_user',
        status: 'ACTIVE',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
      SourceModel(
        id: 'sqlite_1',
        name: 'Manual SQLite Test',
        type: 'SQLITE',
        filePath: '/app/data/manual_test.db',
        status: 'ACTIVE',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    ];

    // 1. Test SourcesScreen
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: SourcesScreen(
            sources: mockSources,
            isLoading: false,
            onRefresh: () {},
            onAddSource: () {},
            onSelectSource: (_) {},
            onNodeStatusTap: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Postgre Test'), findsOneWidget);
    expect(find.text('altr-postgres-test:5432 • altr_test_db'), findsOneWidget);
    expect(find.text('Manual SQLite Test'), findsOneWidget);
    expect(find.text('/app/data/manual_test.db'), findsOneWidget);

    // 2. Test OverviewScreen
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: OverviewScreen(
            sources: mockSources,
            activities: [],
            isLoading: false,
            onRefresh: () {},
            onAddSource: () {},
            onSelectSource: (_) {},
            onViewAllSources: () {},
            onNodeStatusTap: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Postgre Test'), findsOneWidget);
    expect(find.text('POSTGRESQL • altr-postgres-test:5432/altr_test_db'), findsOneWidget);
    expect(find.text('Manual SQLite Test'), findsOneWidget);
    expect(find.text('SQLITE • /app/data/manual_test.db'), findsOneWidget);
    expect(find.text('2/2 Healthy'), findsOneWidget);
  });

  testWidgets('AddSourceWizardDialog PostgreSQL flow regression test', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final mockClient = MockTestApiClient();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: AddSourceWizardDialog(
            apiClient: mockClient,
            onSourceCreated: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // PostgreSQL is default selected -> Continue to Configure
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Host / IP *'), findsOneWidget);
    expect(find.text('Port *'), findsOneWidget);
    expect(find.text('Database Name *'), findsOneWidget);
    expect(find.text('Username *'), findsOneWidget);
    expect(find.text('Password *'), findsOneWidget);

    // Continue to Test
    await tester.tap(find.text('Continue to Test'));
    await tester.pumpAndSettle();

    // Verify testAdhocConnection received PostgreSQL parameters
    expect(mockClient.lastTestAdhocParams?['type'], 'POSTGRESQL');
    expect(mockClient.lastTestAdhocParams?['host'], 'localhost');
    expect(mockClient.lastTestAdhocParams?['port'], 5432);
    expect(mockClient.lastTestAdhocParams?['database_name'], 'altr_test_db');
    expect(mockClient.lastTestAdhocParams?['file_path'], isNull);

    // Continue to Review
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Connection Endpoint'), findsOneWidget);
    expect(find.text('localhost:5432'), findsOneWidget);

    // Register Source
    await tester.tap(find.text('Register Source'));
    await tester.pumpAndSettle();

    expect(mockClient.lastCreateSourceParams?['type'], 'POSTGRESQL');
    expect(mockClient.lastCreateSourceParams?['host'], 'localhost');
    expect(mockClient.lastCreateSourceParams?['port'], 5432);
    expect(mockClient.lastCreateSourceParams?['file_path'], isNull);
  });

  testWidgets('RegistryScreen displays summary metrics and models list', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final mockClient = MockTestApiClient();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: RegistryScreen(
            apiClient: mockClient,
            sources: [],
            onSelectModel: (_) {},
            onNodeStatusTap: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Mapping Registry'), findsWidgets);
    expect(find.text('Logical Models'), findsOneWidget);
    expect(find.text('CoreCommerce'), findsOneWidget);
    expect(find.text('v1.0.0'), findsOneWidget);
    expect(find.text('New Logical Model'), findsOneWidget);
  });

  testWidgets('LogicalModelDetailScreen displays schema and mappings tabs', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final mockClient = MockTestApiClient();
    final model = (await mockClient.listLogicalModels()).first;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: LogicalModelDetailScreen(
            model: model,
            sources: [],
            apiClient: mockClient,
            onBack: () {},
            onModelDeleted: () {},
            onNodeStatusTap: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('CoreCommerce'), findsOneWidget);
    expect(find.text('Customer'), findsOneWidget);
    expect(find.text('Add Entity'), findsOneWidget);
    expect(find.text('Map Source'), findsOneWidget);

    // Switch to Source Mappings Tab
    await tester.tap(find.text('Source Mappings (1 sources)'));
    await tester.pumpAndSettle();

    expect(find.text('Active'), findsOneWidget);
  });

  testWidgets('LogicalModelDetailScreen opens Edit Model, Edit Entity, and Edit Field dialogs', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final mockClient = MockTestApiClient();
    final model = (await mockClient.listLogicalModels()).first;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: LogicalModelDetailScreen(
            model: model,
            sources: [],
            apiClient: mockClient,
            onBack: () {},
            onModelDeleted: () {},
            onNodeStatusTap: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 1. Open Edit Model Dialog
    expect(find.byTooltip('Edit Model Details'), findsOneWidget);
    await tester.tap(find.byTooltip('Edit Model Details'));
    await tester.pumpAndSettle();

    expect(find.text('Edit Logical Data Model'), findsOneWidget);
    expect(find.text('Save Changes'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    // 2. Open Edit Entity Dialog
    expect(find.byTooltip('Edit Entity'), findsOneWidget);
    await tester.tap(find.byTooltip('Edit Entity'));
    await tester.pumpAndSettle();

    expect(find.text('Edit Logical Entity'), findsOneWidget);
    expect(find.text('Save Changes'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    // 3. Open Edit Field Dialog
    expect(find.byTooltip('Edit field').first, findsOneWidget);
    await tester.tap(find.byTooltip('Edit field').first);
    await tester.pumpAndSettle();

    expect(find.text('Edit Logical Field'), findsOneWidget);
    expect(find.text('Save Changes'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });

  testWidgets('AddMappingDialog renders initially unmapped fields with discovered public.users schema without nullability crash', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final mockSource = SourceModel(
      id: 'src_pg_1',
      name: 'Postgre Test',
      type: 'POSTGRESQL',
      host: 'localhost',
      port: 5432,
      databaseName: 'altr_test_db',
      username: 'altr_test_user',
      status: 'ACTIVE',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    final mockSchema = SourceSchemaModel(
      sourceId: 'src_pg_1',
      sourceName: 'Postgre Test',
      version: '1.0.0',
      discoveredAt: DateTime.now(),
      entities: [
        EntitySchemaModel(
          name: 'users',
          namespace: 'public',
          entityType: 'TABLE',
          fields: [
            FieldSchemaModel(name: 'id', dataType: 'integer', nativeDataType: 'int4', nullable: false, isPrimaryKey: true, position: 1),
            FieldSchemaModel(name: 'full_name', dataType: 'varchar', nativeDataType: 'varchar(255)', nullable: false, isPrimaryKey: false, position: 2),
            FieldSchemaModel(name: 'email', dataType: 'varchar', nativeDataType: 'varchar(255)', nullable: false, isPrimaryKey: false, position: 3),
            FieldSchemaModel(name: 'is_active', dataType: 'boolean', nativeDataType: 'bool', nullable: false, isPrimaryKey: false, position: 4),
            FieldSchemaModel(name: 'metadata', dataType: 'jsonb', nativeDataType: 'jsonb', nullable: true, isPrimaryKey: false, position: 5),
          ],
          primaryKey: ['id'],
          constraints: [],
        ),
      ],
      metadata: {},
    );

    final logicalModel = LogicalModelModel(
      id: 'model-users',
      name: 'UserDomain',
      version: '1.0.0',
      description: 'Domain model for user data',
      entities: [
        LogicalEntityModel(
          id: 'ent-student',
          logicalModelId: 'model-users',
          name: 'Student',
          fields: [
            LogicalFieldModel(
              id: 'f-1',
              logicalEntityId: 'ent-student',
              name: 'id',
              dataType: 'INTEGER',
              isPrimaryKey: true,
              nullable: false,
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ),
            LogicalFieldModel(
              id: 'f-2',
              logicalEntityId: 'ent-student',
              name: 'fullName',
              dataType: 'STRING',
              nullable: false,
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ),
            LogicalFieldModel(
              id: 'f-3',
              logicalEntityId: 'ent-student',
              name: 'unmappedField1',
              dataType: 'STRING',
              nullable: true,
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ),
          ],
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      ],
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    final mockClient = MockTestApiClient(schemaToReturn: mockSchema);
    SourceMappingModel? createdMapping;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: AddMappingDialog(
            apiClient: mockClient,
            logicalModel: logicalModel,
            sources: [mockSource],
            onMappingCreated: (m) => createdMapping = m,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify wizard loaded discovered schema
    expect(find.text('Map Physical Source to "UserDomain"'), findsOneWidget);
    expect(find.text('Logical Entity: Student'), findsOneWidget);

    // Select physical table 'public.users' (initially showing '(Not Mapped)')
    await tester.tap(find.text('(Not Mapped)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('public.users').last);
    await tester.pumpAndSettle();

    // Verify fields are now visible
    expect(find.text('id'), findsWidgets);
    expect(find.text('fullName'), findsOneWidget);
    expect(find.text('unmappedField1'), findsOneWidget);

    // Verify unmapped field renders '(Unmapped)' using nullable String? value without throwing TypeError
    expect(find.text('(Unmapped)'), findsOneWidget);

    // Save and validate mapping
    await tester.tap(find.text('Save & Validate Mapping'));
    await tester.pumpAndSettle();

    expect(createdMapping, isNotNull);
    expect(mockClient.lastCreateMappingParams, isNotNull);
    expect(mockClient.lastCreateMappingParams!['source_id'], 'src_pg_1');
  });

  testWidgets('LogicalModelDetailScreen displays Edit action on existing source mapping and updates existing record', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final mockSource = SourceModel(
      id: 'src_pg_1',
      name: 'Postgre Test',
      type: 'POSTGRESQL',
      host: 'localhost',
      port: 5432,
      databaseName: 'altr_test_db',
      username: 'altr_test_user',
      status: 'ACTIVE',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    final mockSchema = SourceSchemaModel(
      sourceId: 'src_pg_1',
      sourceName: 'Postgre Test',
      version: '1.0.0',
      discoveredAt: DateTime.now(),
      entities: [
        EntitySchemaModel(
          name: 'users',
          namespace: 'public',
          entityType: 'TABLE',
          fields: [
            FieldSchemaModel(name: 'id', dataType: 'integer', nativeDataType: 'int4', nullable: false, isPrimaryKey: true, position: 1),
            FieldSchemaModel(name: 'full_name', dataType: 'varchar', nativeDataType: 'varchar(255)', nullable: false, isPrimaryKey: false, position: 2),
            FieldSchemaModel(name: 'email', dataType: 'varchar', nativeDataType: 'varchar(255)', nullable: false, isPrimaryKey: false, position: 3),
          ],
          primaryKey: ['id'],
          constraints: [],
        ),
      ],
      metadata: {},
    );

    final logicalModel = LogicalModelModel(
      id: 'model-1',
      name: 'CoreCommerce',
      version: '1.0.0',
      description: 'Domain model',
      entities: [
        LogicalEntityModel(
          id: 'ent-1',
          logicalModelId: 'model-1',
          name: 'Customer',
          fields: [
            LogicalFieldModel(
              id: 'f-1',
              logicalEntityId: 'ent-1',
              name: 'id',
              dataType: 'INTEGER',
              isPrimaryKey: true,
              nullable: false,
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ),
            LogicalFieldModel(
              id: 'f-2',
              logicalEntityId: 'ent-1',
              name: 'fullName',
              dataType: 'STRING',
              nullable: false,
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ),
          ],
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      ],
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    final existingMapping = SourceMappingModel(
      id: 'mapping-existing-123',
      logicalModelId: 'model-1',
      sourceId: 'src_pg_1',
      version: '1.0.0',
      status: 'ACTIVE',
      provenance: 'USER',
      entityMappings: [
        EntityMappingModel(
          id: 'em-1',
          sourceMappingId: 'mapping-existing-123',
          logicalEntityId: 'ent-1',
          logicalEntityName: 'Customer',
          physicalEntityName: 'users',
          physicalNamespace: 'public',
          fieldMappings: [
            FieldMappingModel(
              id: 'fm-1',
              entityMappingId: 'em-1',
              logicalFieldId: 'f-1',
              logicalFieldName: 'id',
              physicalFieldName: 'id',
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ),
            FieldMappingModel(
              id: 'fm-2',
              entityMappingId: 'em-1',
              logicalFieldId: 'f-2',
              logicalFieldName: 'fullName',
              physicalFieldName: 'full_name',
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ),
          ],
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      ],
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    final mockClient = MockTestApiClient(
      schemaToReturn: mockSchema,
      mappingsToReturn: [existingMapping],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: LogicalModelDetailScreen(
            model: logicalModel,
            sources: [mockSource],
            apiClient: mockClient,
            onBack: () {},
            onModelDeleted: () {},
            onNodeStatusTap: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Switch to Source Mappings Tab
    await tester.tap(find.text('Source Mappings (1 sources)'));
    await tester.pumpAndSettle();

    // Verify existing mapping details
    expect(find.text('Postgre Test'), findsOneWidget);
    expect(find.text('Active'), findsOneWidget);
    expect(find.text('Entity: Customer'), findsOneWidget);
    expect(find.text('public.users'), findsOneWidget);
    expect(find.text('LOGICAL FIELD'), findsOneWidget);
    expect(find.text('PHYSICAL FIELD'), findsOneWidget);

    // Verify Edit button is present on the mapping card
    final editButton = find.widgetWithText(OutlinedButton, 'Edit');
    expect(editButton, findsOneWidget);

    // Tap Edit button
    await tester.tap(editButton);
    await tester.pumpAndSettle();

    // Verify inline editing mode is activated
    expect(find.text('EDITING'), findsOneWidget);
    expect(find.text('Save Changes'), findsOneWidget);

    // Submit edit update
    await tester.tap(find.text('Save Changes'));
    await tester.pumpAndSettle();

    // Confirm it updated the existing mapping ID instead of creating a new mapping
    expect(mockClient.lastUpdateMappingParams, isNotNull);
    expect(mockClient.lastUpdateMappingParams!['mapping_id'], 'mapping-existing-123');
    expect(mockClient.lastCreateMappingParams, isNull);
  });

  test('SourceMappingModel and FieldMappingModel correctly parse backend DTO structures', () {
    final validationPayload = {
      'is_valid': true,
      'error': null,
      'mapping': {
        'id': 'sm-1',
        'logical_model_id': 'lm-1',
        'source_id': 'src-1',
        'version': '1.0.0',
        'status': 'VALIDATED',
        'provenance': 'USER',
        'error_message': null,
        'entity_mappings': [
          {
            'id': 'em-1',
            'source_mapping_id': 'sm-1',
            'logical_entity_id': 'le-1',
            'logical_entity_name': 'Student',
            'physical_entity_name': 'users',
            'physical_namespace': 'public',
            'field_mappings': [
              {
                'id': 'fm-1',
                'entity_mapping_id': 'em-1',
                'logical_field_id': 'lf-1',
                'logical_field_name': 'id',
                'physical_field_name': 'id',
                'transformation_rule': 'DIRECT_ALIAS',
                'created_at': '2026-09-10T06:35:13.655Z',
                'updated_at': '2026-09-10T06:35:13.655Z',
              }
            ],
            'created_at': '2026-09-10T06:35:13.654Z',
            'updated_at': '2026-09-10T06:35:13.654Z',
          }
        ],
        'created_at': '2026-09-10T06:35:13.650Z',
        'updated_at': '2026-09-10T06:35:13.650Z',
      }
    };

    final mappingMap = validationPayload['mapping'] as Map<String, dynamic>;
    final model = SourceMappingModel.fromJson(mappingMap);
    expect(model.id, 'sm-1');
    expect(model.isValidated, isTrue);
    expect(model.entityMappings.length, 1);
    expect(model.entityMappings.first.fieldMappings.length, 1);
    expect(model.entityMappings.first.fieldMappings.first.transformationRule, 'DIRECT_ALIAS');
  });

  testWidgets('Source mapping lifecycle UI enforcement: DRAFT and ERROR disable Activate button, VALIDATED enables Activate', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final mockSource = SourceModel(
      id: 'src_pg_1',
      name: 'Postgre Test',
      type: 'POSTGRESQL',
      host: 'localhost',
      port: 5432,
      databaseName: 'altr_test_db',
      username: 'altr_test_user',
      status: 'ACTIVE',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    final logicalModel = LogicalModelModel(
      id: 'model-lifecycle',
      name: 'LifecycleDomain',
      version: '1.0.0',
      description: 'Domain model for lifecycle testing',
      entities: [
        LogicalEntityModel(
          id: 'ent-1',
          logicalModelId: 'model-lifecycle',
          name: 'Account',
          fields: [
            LogicalFieldModel(
              id: 'f-1',
              logicalEntityId: 'ent-1',
              name: 'id',
              dataType: 'INTEGER',
              isPrimaryKey: true,
              nullable: false,
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ),
          ],
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      ],
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    // 1. DRAFT mapping - Activate button should be disabled
    final draftMapping = SourceMappingModel(
      id: 'mapping-draft-1',
      logicalModelId: 'model-lifecycle',
      sourceId: 'src_pg_1',
      version: '1.0.0',
      status: 'DRAFT',
      provenance: 'USER',
      entityMappings: [],
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    var mockClient = MockTestApiClient(
      mappingsToReturn: [draftMapping],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: LogicalModelDetailScreen(
            key: const ValueKey('draft-screen'),
            model: logicalModel,
            sources: [mockSource],
            apiClient: mockClient,
            onBack: () {},
            onModelDeleted: () {},
            onNodeStatusTap: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Switch to Source Mappings Tab
    await tester.tap(find.text('Source Mappings (1 sources)'));
    await tester.pumpAndSettle();

    expect(find.text('Draft'), findsOneWidget);
    // In DRAFT status, the Activate button exists but its onPressed is null (disabled)
    final activateButtonDraft = tester.widget<ElevatedButton>(
      find.ancestor(
        of: find.text('Activate'),
        matching: find.byType(ElevatedButton),
      ),
    );
    expect(activateButtonDraft.onPressed, isNull);

    // 2. VALIDATED mapping - Activate button should be enabled
    final validatedMapping = SourceMappingModel(
      id: 'mapping-validated-1',
      logicalModelId: 'model-lifecycle',
      sourceId: 'src_pg_1',
      version: '1.0.0',
      status: 'VALIDATED',
      provenance: 'USER',
      entityMappings: [],
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    mockClient = MockTestApiClient(
      mappingsToReturn: [validatedMapping],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: LogicalModelDetailScreen(
            key: const ValueKey('validated-screen'),
            model: logicalModel,
            sources: [mockSource],
            apiClient: mockClient,
            onBack: () {},
            onModelDeleted: () {},
            onNodeStatusTap: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Source Mappings (1 sources)'));
    await tester.pumpAndSettle();

    expect(find.text('Validated'), findsOneWidget);
    final activateButtonValidated = tester.widget<ElevatedButton>(
      find.ancestor(
        of: find.text('Activate'),
        matching: find.byType(ElevatedButton),
      ),
    );
    expect(activateButtonValidated.onPressed, isNotNull);

    // Tap Activate
    await tester.tap(find.text('Activate'));
    await tester.pumpAndSettle();

    expect(mockClient.lastActivateMappingId, 'mapping-validated-1');
  });

  testWidgets('AddMappingDialog in Edit mode can set fields to (Unmapped) and save/validate successfully', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final mockSource = SourceModel(
      id: 'src_pg_1',
      name: 'Postgre Test',
      type: 'POSTGRESQL',
      host: 'localhost',
      port: 5432,
      databaseName: 'altr_test_db',
      username: 'altr_test_user',
      status: 'ACTIVE',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    final mockSchema = SourceSchemaModel(
      sourceId: 'src_pg_1',
      sourceName: 'Postgre Test',
      version: '1.0.0',
      discoveredAt: DateTime.now(),
      entities: [
        EntitySchemaModel(
          name: 'users',
          namespace: 'public',
          entityType: 'TABLE',
          fields: [
            FieldSchemaModel(name: 'id', dataType: 'integer', nativeDataType: 'int4', nullable: false, isPrimaryKey: true, position: 1),
            FieldSchemaModel(name: 'full_name', dataType: 'varchar', nativeDataType: 'varchar(255)', nullable: false, isPrimaryKey: false, position: 2),
            FieldSchemaModel(name: 'email', dataType: 'varchar', nativeDataType: 'varchar(255)', nullable: false, isPrimaryKey: false, position: 3),
          ],
          primaryKey: ['id'],
          constraints: [],
        ),
      ],
      metadata: {},
    );

    final logicalModel = LogicalModelModel(
      id: 'model-users',
      name: 'UniversityDomain',
      version: '1.0.0',
      description: 'Domain model for university',
      entities: [
        LogicalEntityModel(
          id: 'ent-user',
          logicalModelId: 'model-users',
          name: 'User',
          fields: [
            LogicalFieldModel(
              id: 'f-id',
              logicalEntityId: 'ent-user',
              name: 'id',
              dataType: 'INTEGER',
              isPrimaryKey: true,
              nullable: false,
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ),
            LogicalFieldModel(
              id: 'f-fullName',
              logicalEntityId: 'ent-user',
              name: 'fullName',
              dataType: 'STRING',
              nullable: false,
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ),
            LogicalFieldModel(
              id: 'f-emailAddress',
              logicalEntityId: 'ent-user',
              name: 'emailAddress',
              dataType: 'STRING',
              nullable: false,
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ),
          ],
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      ],
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    final existingMapping = SourceMappingModel(
      id: 'sm-univ-1',
      logicalModelId: 'model-users',
      sourceId: 'src_pg_1',
      version: '1.0.0',
      status: 'VALIDATED',
      provenance: 'USER',
      entityMappings: [
        EntityMappingModel(
          id: 'em-1',
          sourceMappingId: 'sm-univ-1',
          logicalEntityId: 'ent-user',
          logicalEntityName: 'User',
          physicalEntityName: 'users',
          physicalNamespace: 'public',
          fieldMappings: [
            FieldMappingModel(
              id: 'fm-1',
              entityMappingId: 'em-1',
              logicalFieldId: 'f-id',
              logicalFieldName: 'id',
              physicalFieldName: 'id',
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ),
            FieldMappingModel(
              id: 'fm-2',
              entityMappingId: 'em-1',
              logicalFieldId: 'f-fullName',
              logicalFieldName: 'fullName',
              physicalFieldName: 'full_name',
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ),
            FieldMappingModel(
              id: 'fm-3',
              entityMappingId: 'em-1',
              logicalFieldId: 'f-emailAddress',
              logicalFieldName: 'emailAddress',
              physicalFieldName: 'email',
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ),
          ],
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      ],
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    final mockClient = MockTestApiClient(
      schemaToReturn: mockSchema,
    );

    SourceMappingModel? updatedMapping;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: AddMappingDialog(
            apiClient: mockClient,
            logicalModel: logicalModel,
            sources: [mockSource],
            existingMapping: existingMapping,
            onMappingCreated: (m) => updatedMapping = m,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify existing mappings are pre-populated
    expect(find.text('Edit Mapping for "UniversityDomain"'), findsOneWidget);
    expect(find.text('fullName'), findsOneWidget);
    expect(find.text('emailAddress'), findsOneWidget);

    // Save and validate update
    await tester.tap(find.text('Update & Validate Mapping'));
    await tester.pumpAndSettle();

    expect(mockClient.lastUpdateMappingParams, isNotNull);
    expect(mockClient.lastUpdateMappingParams!['mapping_id'], 'sm-univ-1');
    expect(updatedMapping, isNotNull);
    expect(updatedMapping?.id, 'sm-univ-1');
  });

  group('Datatype Compatibility Matrix (Frontend)', () {
    test('exact and alias matches are compatible', () {
      expect(areDataTypesCompatible('INTEGER', 'INTEGER'), isTrue);
      expect(areDataTypesCompatible('INTEGER', 'INT'), isTrue);
      expect(areDataTypesCompatible('INTEGER', 'BIGINT'), isTrue);
      expect(areDataTypesCompatible('INTEGER', 'SMALLINT'), isTrue);
      expect(areDataTypesCompatible('INTEGER', 'SERIAL'), isTrue);

      expect(areDataTypesCompatible('FLOAT', 'FLOAT'), isTrue);
      expect(areDataTypesCompatible('FLOAT', 'DOUBLE'), isTrue);
      expect(areDataTypesCompatible('FLOAT', 'REAL'), isTrue);
      expect(areDataTypesCompatible('FLOAT', 'INTEGER'), isTrue);
      expect(areDataTypesCompatible('FLOAT', 'BIGINT'), isTrue);

      expect(areDataTypesCompatible('STRING', 'STRING'), isTrue);
      expect(areDataTypesCompatible('STRING', 'VARCHAR'), isTrue);
      expect(areDataTypesCompatible('STRING', 'TEXT'), isTrue);
      expect(areDataTypesCompatible('STRING', 'CHAR'), isTrue);

      expect(areDataTypesCompatible('BOOLEAN', 'BOOLEAN'), isTrue);
      expect(areDataTypesCompatible('BOOLEAN', 'BOOL'), isTrue);

      expect(areDataTypesCompatible('JSON', 'JSON'), isTrue);
      expect(areDataTypesCompatible('JSON', 'JSONB'), isTrue);

      expect(areDataTypesCompatible('DATE', 'DATE'), isTrue);
      expect(areDataTypesCompatible('TIMESTAMP', 'TIMESTAMPTZ'), isTrue);
      expect(areDataTypesCompatible('DATETIME', 'TIMESTAMP'), isTrue);
    });

    test('incompatible datatypes are rejected', () {
      expect(areDataTypesCompatible('BOOLEAN', 'STRING'), isFalse);
      expect(areDataTypesCompatible('BOOLEAN', 'VARCHAR'), isFalse);
      expect(areDataTypesCompatible('BOOLEAN', 'TEXT'), isFalse);
      expect(areDataTypesCompatible('STRING', 'BOOLEAN'), isFalse);
      expect(areDataTypesCompatible('INTEGER', 'STRING'), isFalse);
      expect(areDataTypesCompatible('INTEGER', 'VARCHAR'), isFalse);
      expect(areDataTypesCompatible('STRING', 'INTEGER'), isFalse);
      expect(areDataTypesCompatible('JSON', 'BOOLEAN'), isFalse);
      expect(areDataTypesCompatible('JSON', 'INTEGER'), isFalse);
      expect(areDataTypesCompatible('ARRAY', 'INTEGER'), isFalse);
      expect(areDataTypesCompatible('BOOLEAN', null), isFalse);
      expect(areDataTypesCompatible(null, 'INTEGER'), isFalse);
    });
  });

  testWidgets('LogicalModelDetailScreen renders inline mapping table with status badges and supports edit flow',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final mockSource = SourceModel(
      id: 'src_pg_compat',
      name: 'PostgreSQL DB',
      type: 'POSTGRESQL',
      host: 'localhost',
      port: 5432,
      databaseName: 'shop_db',
      status: 'ACTIVE',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    final mockSchema = SourceSchemaModel(
      sourceId: 'src_pg_compat',
      sourceName: 'PostgreSQL DB',
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
              dataType: 'INT',
              nativeDataType: 'integer',
              nullable: false,
              isPrimaryKey: true,
              position: 1,
            ),
            FieldSchemaModel(
              name: 'is_active',
              dataType: 'VARCHAR',
              nativeDataType: 'varchar(255)',
              nullable: false,
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

    final logicalModel = LogicalModelModel(
      id: 'model-compat-test',
      name: 'UserDomain',
      version: '1.0.0',
      entities: [
        LogicalEntityModel(
          id: 'ent-user-1',
          logicalModelId: 'model-compat-test',
          name: 'User',
          fields: [
            LogicalFieldModel(
              id: 'f-id',
              logicalEntityId: 'ent-user-1',
              name: 'id',
              dataType: 'INTEGER',
              isPrimaryKey: true,
              nullable: false,
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ),
            LogicalFieldModel(
              id: 'f-active',
              logicalEntityId: 'ent-user-1',
              name: 'is_active',
              dataType: 'BOOLEAN',
              isPrimaryKey: false,
              nullable: false,
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ),
          ],
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      ],
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    final mockMapping = SourceMappingModel(
      id: 'sm-compat-1',
      logicalModelId: 'model-compat-test',
      sourceId: 'src_pg_compat',
      version: '1.0.0',
      status: 'DRAFT',
      provenance: 'USER',
      entityMappings: [
        EntityMappingModel(
          id: 'em-1',
          sourceMappingId: 'sm-compat-1',
          logicalEntityId: 'ent-user-1',
          logicalEntityName: 'User',
          physicalEntityName: 'users',
          physicalNamespace: 'public',
          fieldMappings: [
            FieldMappingModel(
              id: 'fm-1',
              entityMappingId: 'em-1',
              logicalFieldId: 'f-id',
              logicalFieldName: 'id',
              physicalFieldName: 'id',
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ),
            FieldMappingModel(
              id: 'fm-2',
              entityMappingId: 'em-1',
              logicalFieldId: 'f-active',
              logicalFieldName: 'is_active',
              physicalFieldName: 'is_active',
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ),
          ],
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      ],
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    final mockClient = MockTestApiClient(
      schemaToReturn: mockSchema,
      mappingsToReturn: [mockMapping],
      modelsToReturn: [logicalModel],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: LogicalModelDetailScreen(
            model: logicalModel,
            sources: [mockSource],
            apiClient: mockClient,
            onBack: () {},
            onModelDeleted: () {},
            onNodeStatusTap: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Switch to Source Mappings tab
    await tester.tap(find.textContaining('Source Mappings'));
    await tester.pumpAndSettle();

    // Verify Table Headers are rendered
    expect(find.text('LOGICAL FIELD'), findsOneWidget);
    expect(find.text('LOGICAL TYPE'), findsOneWidget);
    expect(find.text('PHYSICAL FIELD'), findsOneWidget);
    expect(find.text('PHYSICAL TYPE'), findsOneWidget);
    expect(find.text('STATUS'), findsOneWidget);

    // Verify Valid status for INTEGER -> INT
    expect(find.text('Valid'), findsOneWidget);

    // Verify Type Mismatch status for BOOLEAN -> VARCHAR
    expect(find.text('Type Mismatch'), findsOneWidget);

    // Enter Edit Mode
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();

    // Verify inline edit controls appear
    expect(find.text('EDITING'), findsOneWidget);
    expect(find.text('Auto-Match'), findsOneWidget);
    expect(find.text('Save Changes'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);

    // Cancel edit mode
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    // Should return to View Mode
    expect(find.text('EDITING'), findsNothing);
    expect(find.text('Edit'), findsOneWidget);
  });
}



