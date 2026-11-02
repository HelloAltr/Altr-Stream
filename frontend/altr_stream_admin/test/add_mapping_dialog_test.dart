import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:altr_stream_admin/core/api/api_client.dart';
import 'package:altr_stream_admin/core/api/models.dart';
import 'package:altr_stream_admin/core/theme/app_theme.dart';
import 'package:altr_stream_admin/features/registry/widgets/add_mapping_dialog.dart';

class _FakeApiClient extends Fake implements ApiClient {
  final SourceSchemaModel schema;
  _FakeApiClient(this.schema);

  @override
  Future<SourceSchemaModel?> getLatestSchema(String sourceId) async => schema;

  @override
  Future<SourceSchemaModel> discoverSchema(String sourceId) async => schema;
}

void main() {
  testWidgets(
    'AddMappingDialog visually distinguishes auto-matched vs left out fields with badges and filter pills',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final logicalModel = LogicalModelModel(
        id: 'lm_test_1',
        name: 'InventoryModel',
        version: '1.0.0',
        entities: [
          LogicalEntityModel(
            id: 'le_1',
            logicalModelId: 'lm_test_1',
            name: 'Item',
            fields: [
              LogicalFieldModel(
                id: 'lf_1',
                logicalEntityId: 'le_1',
                name: 'itemId',
                dataType: 'INTEGER',
                isPrimaryKey: true,
                nullable: false,
                createdAt: DateTime.now(),
                updatedAt: DateTime.now(),
              ),
              LogicalFieldModel(
                id: 'lf_2',
                logicalEntityId: 'le_1',
                name: 'title',
                dataType: 'STRING',
                isPrimaryKey: false,
                nullable: false,
                createdAt: DateTime.now(),
                updatedAt: DateTime.now(),
              ),
              LogicalFieldModel(
                id: 'lf_3',
                logicalEntityId: 'le_1',
                name: 'skuCode', // Will be left out (not auto-matched)
                dataType: 'STRING',
                isPrimaryKey: false,
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

      final mockSource = SourceModel(
        id: 'src_1',
        name: 'Warehouse DB',
        type: 'POSTGRESQL',
        host: 'localhost',
        port: 5432,
        databaseName: 'warehouse',
        status: 'CONNECTED',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final mockSchema = SourceSchemaModel(
        sourceId: 'src_1',
        sourceName: 'Warehouse DB',
        version: '1.0.0',
        discoveredAt: DateTime.now(),
        entities: [
          EntitySchemaModel(
            name: 'items', // Matches 'Item' (plural match)
            namespace: 'public',
            entityType: 'TABLE',
            fields: [
              FieldSchemaModel(
                name: 'item_id', // Matches itemId
                dataType: 'int4',
                nativeDataType: 'int4',
                nullable: false,
                isPrimaryKey: true,
                position: 1,
              ),
              FieldSchemaModel(
                name: 'title', // Matches title
                dataType: 'varchar',
                nativeDataType: 'varchar',
                nullable: false,
                isPrimaryKey: false,
                position: 2,
              ),
              FieldSchemaModel(
                name: 'warehouse_bin', // Does not match skuCode
                dataType: 'varchar',
                nativeDataType: 'varchar',
                nullable: true,
                isPrimaryKey: false,
                position: 3,
              ),
            ],
            primaryKey: ['item_id'],
            constraints: [],
          ),
        ],
        metadata: {},
      );

      final fakeClient = _FakeApiClient(mockSchema);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: AddMappingDialog(
              apiClient: fakeClient,
              logicalModel: logicalModel,
              sources: [mockSource],
              onMappingCreated: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify Title
      expect(find.text('Map Physical Source to "InventoryModel"'), findsOneWidget);

      // Verify Overall Progress Banner
      expect(find.textContaining('2 of 3 fields mapped'), findsOneWidget);
      expect(find.text('2 auto-matched'), findsOneWidget);
      expect(find.text('1 left out (needs selection)'), findsOneWidget);

      // Verify Distinct Badges
      expect(find.text('Auto-Matched'), findsNWidgets(2));
      expect(find.text('Needs Mapping'), findsOneWidget);

      // Verify Filter Pills
      expect(find.text('All (3)'), findsOneWidget);
      expect(find.text('Auto-Matched (2)'), findsOneWidget);
      expect(find.text('Needs Mapping (1)'), findsOneWidget);

      // Tap Needs Mapping filter pill -> only unmapped skuCode should be visible
      await tester.tap(find.text('Needs Mapping (1)'));
      await tester.pumpAndSettle();

      expect(find.text('skuCode'), findsOneWidget);
      expect(find.text('itemId'), findsNothing);
      expect(find.text('title'), findsNothing);

      // Tap All filter pill -> all 3 fields return
      await tester.tap(find.text('All (3)'));
      await tester.pumpAndSettle();

      // Verify Dropdown and Auto-Match All button have matching heights
      final dropdownFinder = find.byType(DropdownButtonFormField<String>).first;
      final autoMatchFinder = find.widgetWithText(OutlinedButton, 'Auto-Match All');
      final dropdownHeight = tester.getSize(dropdownFinder).height;
      final autoMatchHeight = tester.getSize(autoMatchFinder).height;
      expect(autoMatchHeight, dropdownHeight);

      // Verify Overall Progress Banner is in-line to the left of Cancel and Save
      final bannerFinder = find.textContaining('2 of 3 fields mapped');
      final cancelFinder = find.widgetWithText(TextButton, 'Cancel');
      final saveFinder = find.text('Save & Validate Mapping');
      final bannerRect = tester.getRect(bannerFinder);
      final cancelRect = tester.getRect(cancelFinder);
      final saveRect = tester.getRect(saveFinder);
      expect(bannerRect.right < cancelRect.left, isTrue);
      expect(cancelRect.right < saveRect.left, isTrue);
      expect((bannerRect.center.dy - cancelRect.center.dy).abs() < 40, isTrue);


      // Verify Spacing between Data Type and Matching Status
      final dataTypeFinder = find.text('INTEGER');
      final autoMatchedBadgeFinder = find.text('Auto-Matched').first;
      final dataTypeRect = tester.getRect(dataTypeFinder);
      final autoMatchedBadgeRect = tester.getRect(autoMatchedBadgeFinder);
      expect(autoMatchedBadgeRect.left - dataTypeRect.right >= 28, isTrue);
    },
  );
}
