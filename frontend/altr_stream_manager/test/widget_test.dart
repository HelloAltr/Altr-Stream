import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:altr_stream_manager/main.dart';
import 'package:altr_stream_manager/services/mock_backend_service.dart';

void main() {
  testWidgets('AltrStreamManagerApp smoke test', (WidgetTester tester) async {
    // Set desktop testing viewport to accommodate headless test font metrics
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    backendService = MockBackendService(currentScenario: MockScenario.running);

    await tester.pumpWidget(const AltrStreamManagerApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Altr Stream'), findsOneWidget);
    expect(find.text('Local Node Manager'), findsOneWidget);
    expect(find.text('Docker Desktop Status'), findsOneWidget);
    expect(find.text('Altr Stream Node Status'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
