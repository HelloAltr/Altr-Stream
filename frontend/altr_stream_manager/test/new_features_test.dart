import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:altr_stream_manager/main.dart';
import 'package:altr_stream_manager/models/node_title_status.dart';
import 'package:altr_stream_manager/services/directory_picker_service.dart';
import 'package:altr_stream_manager/services/engine_backend_service.dart';
import 'package:altr_stream_manager/services/mock_backend_service.dart';

void main() {
  group('NodeTitleStatus.discovering Tests', () {
    test('discovering state is configured correctly', () {
      const status = NodeTitleStatus.discovering;
      expect(status.dockerState, equals(DockerState.unknown));
      expect(status.nodeState, equals(NodeState.unknown));
      expect(status.isProgressActive, isTrue);
    });

    test('NodeTitleStatus.fromNodeStatus resolves discovering for unknown initial state', () {
      final status = NodeStatus(
        installDir: '',
        targetVersion: '',
        activeVersion: null,
        recommendedVersion: '',
        nodeState: NodeState.unknown,
        dockerDiag: const DockerDiagnostics(
          state: DockerState.unknown,
          cliInstalled: false,
          desktopInstalled: false,
          engineRunning: false,
          statusText: 'Discovering...',
        ),
      );

      expect(NodeTitleStatus.fromNodeStatus(status), equals(NodeTitleStatus.discovering));
    });
  });

  group('DirectoryPickerService Validation Tests', () {
    test('Empty directory path returns error', () async {
      final error = await DirectoryPickerService.validateDirectory('   ');
      expect(error, contains('cannot be empty'));
    });

    test('Non-existent parent path returns error', () async {
      final error = await DirectoryPickerService.validateDirectory('/nonexistent_root_dir_abc123/sub/folder');
      expect(error, contains('Parent directory does not exist'));
    });

    test('Valid writable temp directory passes validation', () async {
      final tempDir = Directory.systemTemp.createTempSync('altr_picker_test_');
      try {
        final error = await DirectoryPickerService.validateDirectory(tempDir.path);
        expect(error, isNull);
      } finally {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      }
    });
  });

  group('Session Logging and Clear Logs Tests', () {
    test('MockBackendService clearLogs executes cleanly', () async {
      final mock = MockBackendService();
      await mock.clearLogs();
      final logs = await mock.getInstallationLogs();
      expect(logs, contains('No operations logged in current session'));
    });

    test('EngineBackendService records chronological session log events', () async {
      final engine = EngineBackendService(
        commandRunner: (exe, args) async => ProcessResult(1234, 0, 'ok', ''),
      );

      engine.logEvent('TestCategory', 'Test message for unit test', level: 'INFO');
      final logs = await engine.getInstallationLogs();

      expect(logs, contains('Session Activity & Installation Events'));
      expect(logs, contains('[INFO] [TestCategory] Test message for unit test'));
    });

    test('EngineBackendService clearLogs clears session events and resets cache', () async {
      final engine = EngineBackendService(
        commandRunner: (exe, args) async => ProcessResult(1234, 0, 'ok', ''),
      );

      engine.logEvent('TestCategory', 'Temporary test entry');
      await engine.clearLogs();
      final logs = await engine.getInstallationLogs();

      expect(logs, contains('No operations logged in current session'));
      expect(logs, isNot(contains('Temporary test entry')));
    });

    test('EngineBackendService clearLogs prevents old container logs and errors from reappearing on refresh or reopen', () async {
      List<String>? recordedDockerArgs;
      final engine = EngineBackendService(
        commandRunner: (exe, args) async {
          if (exe.contains('docker') && args.contains('logs')) {
            recordedDockerArgs = args;
            if (args.contains('--since')) {
              // Simulating Docker daemon returning empty when filtered by clear timestamp
              return ProcessResult(1, 0, '', '');
            }
            return ProcessResult(1, 0, 'old container output line 1\nold container output line 2', '');
          }
          return ProcessResult(1, 0, '{}', '');
        },
      );

      engine.logEvent('Session', 'Initial session message');
      var logs = await engine.getInstallationLogs();
      expect(logs, contains('Initial session message'));
      expect(logs, contains('old container output line 1'));

      // Clear logs
      await engine.clearLogs();

      // Subsequent refresh
      logs = await engine.getInstallationLogs(forceRefresh: true);
      expect(logs, contains('No operations logged in current session'));
      expect(logs, isNot(contains('Initial session message')));
      expect(logs, isNot(contains('old container output line 1')));
      expect(recordedDockerArgs, contains('--since'));

      // Reopening dialog (fresh fetch)
      logs = await engine.getInstallationLogs();
      expect(logs, contains('No operations logged in current session'));
      expect(logs, isNot(contains('old container output line 1')));
    });

    testWidgets('TechnicalLogsDialog clear -> refresh -> reopen maintains clean state', (tester) async {
      final mock = MockBackendService();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: TechnicalLogsDialog(backendService: mock),
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byWidgetPredicate((w) => w is SelectableText && w.data?.contains('Initializing Altr Stream Supervisor') == true), findsOneWidget);

      // Tap clear logs
      await tester.tap(find.byTooltip('Clear Logs'));
      await tester.pumpAndSettle();

      // Confirmation dialog
      expect(find.text('Clear Displayed Logs?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Clear Logs'));
      await tester.pumpAndSettle();

      expect(find.byWidgetPredicate((w) => w is SelectableText && w.data?.contains('No operations logged in current session') == true), findsOneWidget);

      // Tap Refresh
      await tester.tap(find.byTooltip('Refresh'));
      await tester.pumpAndSettle();

      expect(find.byWidgetPredicate((w) => w is SelectableText && w.data?.contains('No operations logged in current session') == true), findsOneWidget);
      expect(find.byWidgetPredicate((w) => w is SelectableText && w.data?.contains('Initializing Altr Stream Supervisor') == true), findsNothing);

      // Reopen dialog with same backend
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: TechnicalLogsDialog(backendService: mock),
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byWidgetPredicate((w) => w is SelectableText && w.data?.contains('No operations logged in current session') == true), findsOneWidget);
      expect(find.byWidgetPredicate((w) => w is SelectableText && w.data?.contains('Initializing Altr Stream Supervisor') == true), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
  });

  group('Manager Manual Test Issues Regression Suite', () {
    testWidgets('Unpublished version 1.0.1-beta is displayed in status but excluded from selectable dropdown', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final mock = MockBackendService(currentScenario: MockScenario.running);
      mock.setActiveVersionForTesting('1.0.1-beta');
      backendService = mock;

      await tester.pumpWidget(const AltrStreamManagerApp());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Current version row displays whatever is active/target (does not hide installed version)
      expect(find.text('1.0.1-beta'), findsWidgets);

      // Inspect dropdown options directly without relying on popup tap
      final dropdown = tester.widget<DropdownButton<String>>(find.byType(DropdownButton<String>));
      final dropdownValues = dropdown.items!.map((item) => item.value).toList();

      // The selectable list MUST NOT include 1.0.1-beta
      expect(dropdownValues.contains('1.0.1-beta'), isFalse);
      expect(dropdownValues.contains('1.0.0-beta'), isTrue);
      expect(dropdownValues.contains('0.13.7-alpha'), isTrue);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });

    testWidgets('UI resolves to Docker Desktop not Running and shows Start Docker Desktop button when stopped', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final mock = MockBackendService(currentScenario: MockScenario.dockerStopped);
      backendService = mock;

      await tester.pumpWidget(const AltrStreamManagerApp());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Must NOT be stuck on "Checking System Status..."
      expect(find.text('Checking System Status...'), findsNothing);
      expect(find.text('Docker Desktop not Running'), findsOneWidget);

      // Button "Start Docker Desktop" must be visible
      expect(find.text('Start Docker Desktop'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });

    testWidgets('Tapping Start Docker Desktop initiates startup and readiness polling', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final mock = MockBackendService(currentScenario: MockScenario.dockerStopped);
      backendService = mock;

      await tester.pumpWidget(const AltrStreamManagerApp());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Start Docker Desktop'), findsOneWidget);

      // Tap button
      await tester.tap(find.text('Start Docker Desktop'));
      await tester.pump();

      // Snack bar shown
      expect(find.text('Starting Docker Desktop, please wait...'), findsOneWidget);

      // Allow 500ms startup delay + 150ms status refresh to complete
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pumpAndSettle();

      // Successfully transitioned to ready
      expect(find.text('Docker Desktop is ready!'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
  });
}
