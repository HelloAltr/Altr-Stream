import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hugeicons_pro/hugeicons.dart';
import 'package:altr_stream_manager/main.dart';
import 'package:altr_stream_manager/models/node_status.dart';
import 'package:altr_stream_manager/models/node_title_status.dart';
import 'package:altr_stream_manager/services/engine_backend_service.dart';
import 'package:altr_stream_manager/services/mock_backend_service.dart';

void main() {
  group('1. MockBackendService & EngineBackendService Boundaries', () {
    test('Default initBackendService selects EngineBackendService when ALTR_MOCK is unset', () {
      final service = initBackendService();
      expect(service, isA<EngineBackendService>());
    });

    test('EngineBackendService never silently falls back to MockBackendService on failure', () async {
      final engine = EngineBackendService(
        commandRunner: (cmd, args) async => throw Exception('Engine binary missing'),
      );
      final status = await engine.getStatus();
      expect(status.dockerDiag.state, equals(DockerState.error));
      expect(status.nodeState, equals(NodeState.error));
      expect(status.healthy, isFalse);
    });
  });

  group('2. Indeterminate Progress for Docker Startup and Resume', () {
    testWidgets('Starting Docker Desktop shows indeterminate progress and explicit message', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final completer = Completer<bool>();
      final mock = _ControllableBackendService(
        initialStatus: const NodeStatus(
          installDir: '/test/dir',
          nodeState: NodeState.notInstalled,
          dockerDiag: DockerDiagnostics(
            state: DockerState.stopped,
            desktopInstalled: true,
          ),
        ),
        startDockerHandler: () => completer.future,
      );
      backendService = mock;

      await tester.pumpWidget(const AltrStreamManagerApp());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Start Docker Desktop'), findsOneWidget);
      await tester.tap(find.text('Start Docker Desktop'));
      await tester.pump(); // Triggers setState for startDocker

      // Indeterminate LinearProgressIndicator has value == null
      final progressIndicator = tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator));
      expect(progressIndicator.value, isNull);

      // Explicit message without fabricated percentage
      expect(find.text('Starting Docker Desktop…'), findsOneWidget);
      expect(find.textContaining('%'), findsNothing);

      // Attempt duplicate tap while operation is active
      await tester.tap(find.byType(LinearProgressIndicator));
      expect(mock.startDockerCallCount, equals(1));

      // Complete operation
      completer.complete(true);
      await tester.pumpAndSettle();

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });

    testWidgets('Resuming Docker Desktop shows indeterminate progress and explicit message', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final completer = Completer<bool>();
      final mock = _ControllableBackendService(
        initialStatus: const NodeStatus(
          installDir: '/test/dir',
          nodeState: NodeState.notInstalled,
          dockerDiag: DockerDiagnostics(
            state: DockerState.paused,
            desktopInstalled: true,
          ),
        ),
        resumeDockerHandler: () => completer.future,
      );
      backendService = mock;

      await tester.pumpWidget(const AltrStreamManagerApp());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Resume Docker Desktop'), findsOneWidget);
      await tester.tap(find.text('Resume Docker Desktop'));
      await tester.pump();

      final progressIndicator = tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator));
      expect(progressIndicator.value, isNull);
      expect(find.text('Resuming Docker Desktop…'), findsOneWidget);
      expect(find.textContaining('%'), findsNothing);

      completer.complete(true);
      await tester.pumpAndSettle();

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
  });

  group('3. Technical Logs De-cluttering & Raw Logs Access', () {
    test('filterContainerLogs collapses repetitive successful health check lines', () {
      const rawLogs = '''
INFO:     Started server process [1]
INFO:     Waiting for application startup.
INFO:     Application startup complete.
INFO:     127.0.0.1:45322 - "GET /api/v1/health HTTP/1.1" 200 OK
INFO:     172.20.0.1:51120 - "GET /api/v1/health HTTP/1.1" 200 OK
INFO:     127.0.0.1:45330 - "GET /api/v1/health HTTP/1.1" 200 OK
INFO:     172.20.0.1:51124 - "GET /api/v1/health HTTP/1.1" 200 OK
INFO:     Node operational
''';

      final filtered = EngineBackendService.filterContainerLogs(rawLogs);
      expect(filtered.contains('Application startup complete.'), isTrue);
      expect(filtered.contains('Node operational'), isTrue);
      expect(filtered.contains('4 successful GET /api/v1/health (200 OK) checks collapsed'), isTrue);
      expect(filtered.contains('127.0.0.1:45322'), isFalse);
    });

    test('filterContainerLogs preserves errors, warnings, and non-200 responses', () {
      const rawLogs = '''
INFO:     127.0.0.1:45322 - "GET /api/v1/health HTTP/1.1" 200 OK
INFO:     172.20.0.1:51120 - "GET /api/v1/health HTTP/1.1" 200 OK
WARNING:  Memory pressure threshold reached
ERROR:    500 Internal Server Error - DB connection timed out
INFO:     127.0.0.1:45330 - "GET /api/v1/health HTTP/1.1" 503 Service Unavailable
''';

      final filtered = EngineBackendService.filterContainerLogs(rawLogs);
      expect(filtered.contains('WARNING:  Memory pressure threshold reached'), isTrue);
      expect(filtered.contains('ERROR:    500 Internal Server Error'), isTrue);
      expect(filtered.contains('503 Service Unavailable'), isTrue);
    });

    testWidgets('TechnicalLogsDialog toggles between Decluttered and Raw logs', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final mock = MockBackendService(currentScenario: MockScenario.running);
      backendService = mock;

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: TechnicalLogsDialog(backendService: mock),
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Default is decluttered
      expect(find.text('Decluttered'), findsOneWidget);
      expect(find.text('Raw Logs'), findsOneWidget);
      expect(find.textContaining('collapsed'), findsWidgets);

      // Switch to Raw Logs
      await tester.tap(find.text('Raw Logs'));
      await tester.pumpAndSettle();

      expect(find.textContaining('GET /api/v1/health HTTP/1.1" 200 OK'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
  });

  group('4. Quit Confirmation Dialog', () {
    testWidgets('Header close button opens confirmation dialog and Cancel retains manager', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final mock = MockBackendService(currentScenario: MockScenario.running);
      backendService = mock;

      await tester.pumpWidget(const AltrStreamManagerApp());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Find the Quit Manager button in header
      final quitButton = find.byTooltip('Quit Manager');
      expect(quitButton, findsOneWidget);
      expect(find.byIcon(HugeIconsStroke.shutDown), findsOneWidget);

      await tester.tap(quitButton);
      await tester.pumpAndSettle();

      // Dialog is displayed with explanation that background services keep running
      expect(find.text('Quit Altr Stream Manager?'), findsOneWidget);
      expect(find.textContaining('They will continue running safely in the background'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Quit Manager'), findsWidgets);

      // Verify Quit dialog width is constrained to kDialogStandardWidth (360)
      final contentSizedBox = tester.widget<SizedBox>(
        find.ancestor(
          of: find.textContaining('Closing the Manager does not stop'),
          matching: find.byType(SizedBox),
        ).first,
      );
      expect(contentSizedBox.width, equals(kDialogStandardWidth));

      // Cancel leaves Manager running
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Quit Altr Stream Manager?'), findsNothing);
      expect(find.text('Altr Stream'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
  });

  group('5. Node Lifecycle Controls (Pause / Resume / Start)', () {
    testWidgets('Node running presents Pause Node button together with Open Dashboard, Stop Node, and Uninstall', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final mock = MockBackendService(currentScenario: MockScenario.running);
      backendService = mock;

      await tester.pumpWidget(const AltrStreamManagerApp());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Verifies 'Open Dashboard', 'Pause Node', 'Stop Node', and 'Uninstall Node' appear together
      expect(find.text('Open Dashboard'), findsOneWidget);
      expect(find.text('Pause Node'), findsOneWidget);
      expect(find.text('Stop Node'), findsOneWidget);
      expect(find.text('Uninstall Node'), findsOneWidget);

      await tester.tap(find.text('Pause Node'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      // Status transitions to Paused
      expect(find.text('Altr Stream Paused'), findsOneWidget);
      expect(find.text('Resume Node'), findsOneWidget);
      expect(find.text('Stop Node'), findsOneWidget);
      expect(find.text('Uninstall Node'), findsOneWidget);
      expect(find.text('Pause Node'), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });

    testWidgets('Node running presents Stop Node button and triggers stopNode', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final mock = MockBackendService(currentScenario: MockScenario.running);
      backendService = mock;

      await tester.pumpWidget(const AltrStreamManagerApp());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Stop Node'), findsOneWidget);

      await tester.tap(find.text('Stop Node'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      // Transitions to stopped state where Start Altr Stream is presented
      expect(find.text('Start Altr Stream'), findsOneWidget);
      expect(find.text('Stop Node'), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });

    testWidgets('Node paused presents Resume Node button and triggers resumeNode', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final mock = MockBackendService(currentScenario: MockScenario.nodePaused);
      backendService = mock;

      await tester.pumpWidget(const AltrStreamManagerApp());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Resume Node'), findsOneWidget);
      expect(find.text('Stop Node'), findsOneWidget);
      expect(find.text('Uninstall Node'), findsOneWidget);

      await tester.tap(find.text('Resume Node'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      expect(find.text('Altr Stream Running'), findsOneWidget);
      expect(find.text('Open Dashboard'), findsOneWidget);
      expect(find.text('Pause Node'), findsOneWidget);
      expect(find.text('Stop Node'), findsOneWidget);
      expect(find.text('Uninstall Node'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });

    testWidgets('When Docker is not ready, Node pause/resume actions are not shown', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final mock = MockBackendService(currentScenario: MockScenario.dockerStopped);
      backendService = mock;

      await tester.pumpWidget(const AltrStreamManagerApp());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Container lifecycle buttons are absent when Docker is stopped; Docker recovery action is shown
      expect(find.text('Start Docker Desktop'), findsOneWidget);
      expect(find.text('Pause Node'), findsNothing);
      expect(find.text('Stop Node'), findsNothing);
      expect(find.text('Resume Node'), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
  });
}

class _ControllableBackendService extends MockBackendService {
  final NodeStatus initialStatus;
  final Future<bool> Function()? startDockerHandler;
  final Future<bool> Function()? resumeDockerHandler;
  int startDockerCallCount = 0;
  int resumeDockerCallCount = 0;

  _ControllableBackendService({
    required this.initialStatus,
    this.startDockerHandler,
    this.resumeDockerHandler,
  });

  @override
  Future<NodeStatus> getStatus() async => initialStatus;

  @override
  Future<NodeStatus> refreshStatus() async => initialStatus;

  @override
  Future<bool> startDockerDesktop() async {
    startDockerCallCount++;
    if (startDockerHandler != null) {
      return await startDockerHandler!();
    }
    return true;
  }

  @override
  Future<bool> resumeDockerDesktop() async {
    resumeDockerCallCount++;
    if (resumeDockerHandler != null) {
      return await resumeDockerHandler!();
    }
    return true;
  }
}
