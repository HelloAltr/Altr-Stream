import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:altr_stream_admin/core/api/models.dart';
import 'package:altr_stream_admin/features/overview/screens/overview_screen.dart';
import 'package:altr_stream_admin/features/overview/services/overview_layout_service.dart';
import 'package:altr_stream_admin/features/overview/services/local_storage_adapter.dart';
import 'package:altr_stream_admin/features/overview/widgets/dashboard_card_wrapper.dart';
import 'package:altr_stream_admin/features/overview/widgets/bento_grid_engine.dart';

void main() {
  setUp(() async {
    await OverviewLayoutService.resetLayout();
  });

  group('Bento Grid Engine & Layout Persistence Tests', () {
    test('OverviewLayoutService loads authentic default Bento layout', () async {
      final layout = await OverviewLayoutService.loadLayout();
      expect(layout.length, 5);

      final kpi = layout.firstWhere((c) => c.id == 'kpi');
      expect(kpi.col, 0);
      expect(kpi.row, 0);
      expect(kpi.colSpan, 1);
      expect(kpi.rowSpan, 1);

      final usage = layout.firstWhere((c) => c.id == 'usage');
      expect(usage.col, 0);
      expect(usage.row, 1);
      expect(usage.colSpan, 1);
      expect(usage.rowSpan, 1);

      final sources = layout.firstWhere((c) => c.id == 'sources');
      expect(sources.col, 1);
      expect(sources.row, 0);
      expect(sources.colSpan, 2);
      expect(sources.rowSpan, 2);
    });

    test('OverviewLayoutService saves and reloads customized Bento layout', () async {
      final custom = [
        const BentoCardConfig(id: 'sources', col: 0, row: 0, colSpan: 3, rowSpan: 2, title: 'Sources List'),
        const BentoCardConfig(id: 'kpi', col: 0, row: 2, colSpan: 1, rowSpan: 1, title: 'Connected Sources'),
      ];

      await OverviewLayoutService.saveLayout(custom);
      final loaded = await OverviewLayoutService.loadLayout();

      expect(loaded[0].id, 'sources');
      expect(loaded[0].colSpan, 3);
      expect(loaded[1].id, 'kpi');
      expect(loaded[1].row, 2);
      expect(loaded.length, 5);
    });

    test('OverviewLayoutService resetLayout restores default Bento layout and clears storage', () async {
      final custom = [
        const BentoCardConfig(id: 'activity', col: 1, row: 1, colSpan: 2, rowSpan: 2, title: 'Recent Activity'),
      ];
      await OverviewLayoutService.saveLayout(custom);

      final reset = await OverviewLayoutService.resetLayout();
      expect(reset.length, 5);
      expect(reset[0].id, 'kpi');
      expect(reset[0].col, 0);
      expect(reset[0].row, 0);

      expect(LocalStorageAdapter.read('altr_stream_overview_bento_v2'), isNull);
    });

    test('BentoCollisionResolver automatically pushes overlapping cards downward', () {
      // Two cards placed at the exact same slot (col: 0, row: 0)
      final colliding = [
        const BentoCardConfig(id: 'card1', col: 0, row: 0, colSpan: 2, rowSpan: 2, title: 'Card 1'),
        const BentoCardConfig(id: 'card2', col: 0, row: 0, colSpan: 1, rowSpan: 1, title: 'Card 2'),
        const BentoCardConfig(id: 'card3', col: 0, row: 1, colSpan: 3, rowSpan: 1, title: 'Card 3'),
      ];

      // With card1 as the fixed anchor
      final resolved = BentoCollisionResolver.resolve(colliding, fixedId: 'card1');

      // Card 1 stays at row 0, rowSpan 2 (occupies rows 0..1, cols 0..1)
      final r1 = resolved.firstWhere((c) => c.id == 'card1');
      expect(r1.row, 0);

      // Card 2 must be pushed down to at least row 2
      final r2 = resolved.firstWhere((c) => c.id == 'card2');
      expect(r2.row, greaterThanOrEqualTo(2));

      // Verify no two cards in the resolved list overlap
      for (int i = 0; i < resolved.length; i++) {
        for (int j = 0; j < resolved.length; j++) {
          if (i != j) {
            expect(
              BentoCollisionResolver.itemsOverlap(resolved[i], resolved[j]),
              isFalse,
              reason: '${resolved[i].id} overlaps with ${resolved[j].id}',
            );
          }
        }
      }
    });

    test('Placing a card into an empty slot retains its position without moving other cards', () {
      final initial = [
        const BentoCardConfig(id: 'kpi', col: 0, row: 0, colSpan: 1, rowSpan: 1, title: 'KPI'),
        const BentoCardConfig(id: 'sources', col: 1, row: 0, colSpan: 2, rowSpan: 2, title: 'Sources'),
        const BentoCardConfig(id: 'activity', col: 0, row: 3, colSpan: 3, rowSpan: 1, title: 'Activity'),
      ];

      // Note: (col: 0, row: 1) is currently empty!
      // Move activity to that empty slot: col: 0, row: 1, colSpan: 1, rowSpan: 1
      final updated = [
        initial[0],
        initial[1],
        const BentoCardConfig(id: 'activity', col: 0, row: 1, colSpan: 1, rowSpan: 1, title: 'Activity'),
      ];

      final resolved = BentoCollisionResolver.resolve(updated, fixedId: 'activity');

      final act = resolved.firstWhere((c) => c.id == 'activity');
      expect(act.col, 0);
      expect(act.row, 1);

      // KPI and Sources remain at their positions because there is no collision
      final kpi = resolved.firstWhere((c) => c.id == 'kpi');
      expect(kpi.col, 0);
      expect(kpi.row, 0);

      final sources = resolved.firstWhere((c) => c.id == 'sources');
      expect(sources.col, 1);
      expect(sources.row, 0);
    });

    test('Dragging an element into empty space formed by a pushed-down card places it directly without moving others if space permits', () {
      // Setup: sources (2x2) was pushed down to row 2 by placing something at (1, 0)
      // leaving slots (1, 0), (2, 0), (1, 1), (2, 1) free
      final pushedState = [
        const BentoCardConfig(id: 'kpi', col: 0, row: 0, colSpan: 1, rowSpan: 1, title: 'KPI'),
        const BentoCardConfig(id: 'usage', col: 0, row: 1, colSpan: 1, rowSpan: 1, title: 'Usage'),
        const BentoCardConfig(id: 'sources', col: 1, row: 2, colSpan: 2, rowSpan: 2, title: 'Sources (Pushed)'),
        const BentoCardConfig(id: 'registry', col: 0, row: 4, colSpan: 3, rowSpan: 1, title: 'Registry'),
        const BentoCardConfig(id: 'activity', col: 0, row: 5, colSpan: 3, rowSpan: 1, title: 'Activity'),
      ];

      // Now drag 'usage' (1x1) into the empty space at (col: 1, row: 0)
      final movedList = [
        pushedState[0],
        const BentoCardConfig(id: 'usage', col: 1, row: 0, colSpan: 1, rowSpan: 1, title: 'Usage'),
        pushedState[2],
        pushedState[3],
        pushedState[4],
      ];

      final resolved = BentoCollisionResolver.resolve(movedList, fixedId: 'usage');

      // 'usage' sits directly in that empty spot (1, 0)
      final usage = resolved.firstWhere((c) => c.id == 'usage');
      expect(usage.col, 1);
      expect(usage.row, 0);

      // KPI remains at (0, 0)
      final kpi = resolved.firstWhere((c) => c.id == 'kpi');
      expect(kpi.col, 0);
      expect(kpi.row, 0);

      // Since row 1 became completely empty, sources, registry, and activity dynamically moved up by 1 row!
      final sources = resolved.firstWhere((c) => c.id == 'sources');
      expect(sources.col, 1);
      expect(sources.row, 1);

      final registry = resolved.firstWhere((c) => c.id == 'registry');
      expect(registry.row, 3);

      final activity = resolved.firstWhere((c) => c.id == 'activity');
      expect(activity.row, 4);
    });

    test('If an empty row exists in the grid, bottom elements dynamically move up', () {
      // Row 0: KPI (0, 0, 1x1)
      // Row 1: Completely empty!
      // Row 2: Registry (0, 2, 3x1)
      // Row 3: Activity (0, 3, 3x1)
      final withEmptyRow = [
        const BentoCardConfig(id: 'kpi', col: 0, row: 0, colSpan: 1, rowSpan: 1, title: 'KPI'),
        const BentoCardConfig(id: 'registry', col: 0, row: 2, colSpan: 3, rowSpan: 1, title: 'Registry'),
        const BentoCardConfig(id: 'activity', col: 0, row: 3, colSpan: 3, rowSpan: 1, title: 'Activity'),
      ];

      final compacted = BentoCollisionResolver.compactRows(withEmptyRow);

      // KPI remains at row 0
      final kpi = compacted.firstWhere((c) => c.id == 'kpi');
      expect(kpi.row, 0);

      // Registry moves up from row 2 to row 1
      final registry = compacted.firstWhere((c) => c.id == 'registry');
      expect(registry.row, 1);

      // Activity moves up from row 3 to row 2
      final activity = compacted.firstWhere((c) => c.id == 'activity');
      expect(activity.row, 2);
    });

    test('Multiple consecutive empty rows are compacted upward', () {
      // Cards starting at row 3 with rows 0, 1, 2 empty
      final list = [
        const BentoCardConfig(id: 'card1', col: 0, row: 3, colSpan: 2, rowSpan: 1, title: 'Card 1'),
        const BentoCardConfig(id: 'card2', col: 0, row: 5, colSpan: 3, rowSpan: 2, title: 'Card 2'), // row 4 empty
      ];

      final compacted = BentoCollisionResolver.compactRows(list);

      // card1 shifts up by 3 (from row 3 to row 0)
      final c1 = compacted.firstWhere((c) => c.id == 'card1');
      expect(c1.row, 0);

      // card2 was at row 5 (with empty rows 0, 1, 2, 4 = 4 empty rows before it -> row 1)
      final c2 = compacted.firstWhere((c) => c.id == 'card2');
      expect(c2.row, 1);
    });

    testWidgets('OverviewScreen renders Edit button and toggles into Edit mode with Bento drag & resize handles', (tester) async {
      tester.view.physicalSize = const Size(1400, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final dummySources = [
        SourceModel(
          id: 'src-1',
          name: 'Main Postgres DB',
          type: 'POSTGRESQL',
          status: 'ACTIVE',
          host: '127.0.0.1',
          port: 5432,
          databaseName: 'production',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: OverviewScreen(
                sources: dummySources,
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
      await tester.pumpAndSettle();

      // Find the Edit Overview Layout button
      expect(find.text('Edit Overview Layout'), findsOneWidget);

      // Initially, edit mode toolbar should NOT be visible
      expect(find.text('Editing Overview Layout'), findsNothing);
      expect(find.byType(BentoGridEngine), findsOneWidget);

      // Tap 'Edit Overview Layout'
      await tester.tap(find.text('Edit Overview Layout'));
      await tester.pumpAndSettle();

      // Verify Edit Mode elements appear
      expect(find.text('Editing Overview Layout'), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);
      // Verify '=' drag handle and diagonal resize grip handles exist in edit mode
      final equalIcons = find.byWidgetPredicate(
        (widget) => widget is HugeIcon && widget.icon == HugeIcons.strokeRoundedEqualSign,
      );
      expect(equalIcons, findsWidgets);

      final resizeIcons = find.byWidgetPredicate(
        (widget) => widget is HugeIcon && widget.icon == HugeIcons.strokeRoundedDiagonalScrollPoint02,
      );
      expect(resizeIcons, findsWidgets);

      // Tap Done to exit edit mode
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      expect(find.text('Editing Overview Layout'), findsNothing);
      expect(find.text('Edit Overview Layout'), findsOneWidget);
    });

    testWidgets('DashboardCardWrapper renders dimensions badge and triggers resize on click/pan', (tester) async {
      int colSpanValue = 1;
      int rowSpanValue = 1;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 400,
                height: 300,
                child: StatefulBuilder(
                  builder: (context, setState) {
                    return DashboardCardWrapper(
                      config: BentoCardConfig(
                        id: 'kpi',
                        col: 0,
                        row: 0,
                        colSpan: colSpanValue,
                        rowSpan: rowSpanValue,
                        title: 'KPI',
                      ),
                      isEditMode: true,
                      onCycleSpan: () {
                        setState(() {
                          colSpanValue = 2;
                          rowSpanValue = 2;
                        });
                      },
                      child: const Card(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text('Card Content'),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('1x1'), findsOneWidget);

      // Tap the dimensions badge to cycle to 2x2
      await tester.tap(find.text('1x1'));
      await tester.pumpAndSettle();

      expect(find.text('2x2'), findsOneWidget);
    });

    test('BentoCardConfig enforces per-component max dimensions constraints', () {
      const kpi = BentoCardConfig(id: 'kpi', col: 0, row: 0, colSpan: 1, rowSpan: 1, title: 'KPI');
      expect(kpi.maxRowSpan, 1);
      expect(kpi.maxColSpan, 1);
      expect(kpi.isResizable, isFalse);

      const sources = BentoCardConfig(id: 'sources', col: 0, row: 0, colSpan: 1, rowSpan: 1, title: 'Sources');
      expect(sources.maxRowSpan, 3);
      expect(sources.maxColSpan, 3);
      expect(sources.isResizable, isTrue);

      const usage = BentoCardConfig(id: 'usage', col: 0, row: 0, colSpan: 1, rowSpan: 1, title: 'Usage');
      expect(usage.maxRowSpan, 3);
      expect(usage.maxColSpan, 3);

      const activity = BentoCardConfig(id: 'activity', col: 0, row: 0, colSpan: 1, rowSpan: 1, title: 'Activity');
      expect(activity.maxRowSpan, 2);
      expect(activity.maxColSpan, 3);

      const registry = BentoCardConfig(id: 'registry', col: 0, row: 0, colSpan: 1, rowSpan: 1, title: 'Registry');
      expect(registry.maxRowSpan, 1);
      expect(registry.maxColSpan, 3);
    });

    testWidgets('BentoGridEngine updates layout and cascades collisions in real time during corner drag resizing', (tester) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      List<BentoCardConfig> currentConfigs = [
        const BentoCardConfig(id: 'usage', col: 0, row: 0, colSpan: 1, rowSpan: 1, title: 'Usage'),
        const BentoCardConfig(id: 'sources', col: 0, row: 1, colSpan: 2, rowSpan: 1, title: 'Sources'),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return BentoGridEngine(
                  configs: currentConfigs,
                  isEditMode: true,
                  cardBuilder: (context, config) => Card(child: Center(child: Text(config.title))),
                  onLayoutChanged: (updated) {
                    setState(() {
                      currentConfigs = updated;
                    });
                  },
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Find the resize grip on the Usage card (which is at 0, 0 and is resizable)
      final resizeGrips = find.byWidgetPredicate(
        (widget) => widget is HugeIcon && widget.icon == HugeIcons.strokeRoundedDiagonalScrollPoint02,
      );
      expect(resizeGrips, findsWidgets);

      // Drag the resize grip downwards by 260px to expand Usage from 1x1 to 1x2 in real time
      final firstGrip = resizeGrips.first;
      await tester.drag(firstGrip, const Offset(0, 260));
      await tester.pumpAndSettle();

      // Verify that in real time, Usage became 1x2 and Sources yielded space and moved down to row 2
      final usage = currentConfigs.firstWhere((c) => c.id == 'usage');
      expect(usage.rowSpan, 2);

      final sources = currentConfigs.firstWhere((c) => c.id == 'sources');
      expect(sources.row, greaterThanOrEqualTo(2));
    });
  });
}
