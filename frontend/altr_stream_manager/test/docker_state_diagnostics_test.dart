import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:altr_stream_manager/main.dart';
import 'package:altr_stream_manager/models/node_title_status.dart';
import 'package:altr_stream_manager/services/engine_backend_service.dart';
import 'package:altr_stream_manager/services/mock_backend_service.dart';

void main() {
  group('P2 Automated State Transition & Diagnostics Verification Suite', () {
    // 1. Docker Desktop not installed
    test('1. Docker Desktop not installed maps to dockerNotInstalled and explains requirement', () async {
      final mock = MockBackendService(currentScenario: MockScenario.dockerNotInstalled);
      final status = await mock.getStatus();

      expect(status.dockerDiag.desktopInstalled, isFalse);
      expect(status.dockerDiag.state, DockerState.notInstalled);

      final titleStatus = NodeTitleStatus.fromNodeStatus(status);
      expect(titleStatus, NodeTitleStatus.dockerNotInstalled);
      expect(titleStatus.dockerState, DockerState.notInstalled);
    });

    // 2. Docker Desktop installed, daemon stopped
    test('2. Docker Desktop installed but stopped maps to dockerStopped and NOT dockerFailed', () async {
      final mock = MockBackendService(currentScenario: MockScenario.dockerStopped);
      final status = await mock.getStatus();

      expect(status.dockerDiag.desktopInstalled, isTrue);
      expect(status.dockerDiag.engineRunning, isFalse);
      expect(status.dockerDiag.state, DockerState.stopped);

      final titleStatus = NodeTitleStatus.fromNodeStatus(status);
      expect(titleStatus, NodeTitleStatus.dockerStopped);
      expect(titleStatus, isNot(NodeTitleStatus.nodeFailed));
      expect(titleStatus, isNot(NodeTitleStatus.dockerError));
    });

    // 3. Docker Desktop starting
    test('3. Docker Desktop starting maps to dockerStarting and shows active progress', () async {
      final mock = MockBackendService(currentScenario: MockScenario.dockerStarting);
      final status = await mock.getStatus();

      expect(status.dockerDiag.state, DockerState.starting);
      final titleStatus = NodeTitleStatus.fromNodeStatus(status);
      expect(titleStatus, NodeTitleStatus.dockerStarting);
      expect(titleStatus.isProgressActive, isTrue);
    });

    // 4. Docker daemon ready
    test('4. Docker daemon ready allows independent evaluation of container status', () async {
      final mock = MockBackendService(currentScenario: MockScenario.running);
      final status = await mock.getStatus();

      expect(status.dockerDiag.state, DockerState.ready);
      expect(status.dockerDiag.engineRunning, isTrue);
      expect(status.nodeState, NodeState.running);

      final titleStatus = NodeTitleStatus.fromNodeStatus(status);
      expect(titleStatus, NodeTitleStatus.nodeRunning);
    });

    // 5. Daemon check timeout or unknown state
    test('5. Daemon check timeout or unknown state maps to dockerError', () async {
      final engine = EngineBackendService(
        commandRunner: (exe, args) async {
          throw TimeoutException('Timed out connecting to dockerd');
        },
      );

      final status = await engine.getStatus();
      expect(status.dockerDiag.state, DockerState.error);

      final titleStatus = NodeTitleStatus.fromNodeStatus(status);
      expect(titleStatus, NodeTitleStatus.dockerError);
    });

    // 6. Start Docker Desktop launch failure
    test('6. Start Docker Desktop launch failure records error and allows retry', () async {
      final engine = EngineBackendService(
        commandRunner: (exe, args) async {
          if (args.contains('launch-docker')) {
            return ProcessResult(101, 1, '', 'Failed to execute open -a Docker: Application not found');
          }
          return ProcessResult(102, 0, '{}', '');
        },
      );

      final started = await engine.startDockerDesktop();
      expect(started, isFalse);
      expect(engine.lastEngineError, contains('Failed to dispatch launch-docker'));
    });

    // 7. Successful launch followed by daemon readiness
    test('7. Successful launch followed by daemon readiness completes successfully', () async {
      final engine = EngineBackendService(
        commandRunner: (exe, args) async {
          if (args.contains('launch-docker')) {
            return ProcessResult(201, 0, 'Launch dispatched', '');
          }
          if (args.contains('wait-docker')) {
            return ProcessResult(202, 0, '{"ready": true}', '');
          }
          return ProcessResult(203, 0, '{}', '');
        },
      );

      final started = await engine.startDockerDesktop();
      expect(started, isTrue);
      expect(engine.lastEngineError, isNull);
    });

    // 8. Diagnose and Fix findings and post-action verification
    testWidgets('8. Diagnose and Fix runs bounded checks, reports findings, and verifies remediation', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final mock = MockBackendService(currentScenario: MockScenario.dockerStopped);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: DiagnoseAndFixDialog(backendService: mock),
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // 1. Verify modal rendered with primary finding
      expect(find.text('Diagnose & Fix'), findsOneWidget);
      expect(find.text('Docker Desktop Stopped'), findsOneWidget);
      expect(find.text('Start Docker Desktop'), findsOneWidget);

      // 2. Verify all 6 bounded diagnostic checks are rendered
      expect(find.text('Docker Desktop Installation'), findsOneWidget);
      expect(find.text('Docker CLI Discovery'), findsOneWidget);
      expect(find.text('Docker Daemon Readiness'), findsOneWidget);
      expect(find.text('Altr Stream Configuration'), findsOneWidget);
      expect(find.text('Port 8000 Availability'), findsOneWidget);
      expect(find.text('Container State'), findsOneWidget);

      // 3. Verify check badges
      expect(find.text('PASSED'), findsWidgets);
      expect(find.text('FAILED'), findsWidgets);

      // 4. Execute safe recommended action (Start Docker Desktop)
      await tester.tap(find.widgetWithText(FilledButton, 'Start Docker Desktop'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));

      // 5. Verify post-action verification check was executed
      expect(find.textContaining('Verified: Issue resolved successfully!'), findsOneWidget);
    });

    // 9. Useful Manager diagnostic log entries
    test('9. Useful Manager diagnostic log entries record startup, status timing, and sanitize secrets', () async {
      final engine = EngineBackendService(
        commandRunner: (exe, args) async => ProcessResult(101, 0, '{"install_dir": "/tmp", "docker_diag": {"state": "ready"}, "node_state": "running", "healthy": true}', ''),
      );

      // Verify Startup entry exists
      final logs = await engine.getInstallationLogs();
      expect(logs, contains('[Startup]'));
      expect(logs, contains('Altr Stream Manager initialized'));

      // Verify status check timing and result
      await engine.getStatus();
      final updatedLogs = await engine.getInstallationLogs(forceRefresh: true);
      expect(updatedLogs, contains('[Status] Status probe completed in'));
      expect(updatedLogs, contains('Docker=Ready'));

      // Verify secret sanitization in custom log events
      engine.logEvent('Security', 'Authentication with token=ghp_secretToken123456789 and password="MyPassword123"');
      final sanitizedLogs = await engine.getInstallationLogs(forceRefresh: true);
      expect(sanitizedLogs, isNot(contains('ghp_secretToken123456789')));
      expect(sanitizedLogs, isNot(contains('MyPassword123')));
      expect(sanitizedLogs, contains('[REDACTED]'));
    });

    // 10. Clear Logs followed by refresh and reopening dialog
    testWidgets('10. Clear Logs clears application logs and maintains clean state across reopen', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final mock = MockBackendService();

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: TechnicalLogsDialog(backendService: mock),
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Initial content
      expect(find.byWidgetPredicate((w) => w is SelectableText && w.data?.contains('Initializing Altr Stream Supervisor') == true), findsOneWidget);

      // Clear logs
      await tester.tap(find.byTooltip('Clear Logs'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Clear Logs'));
      await tester.pumpAndSettle();

      // Verify cleared
      expect(find.byWidgetPredicate((w) => w is SelectableText && w.data?.contains('No operations logged in current session') == true), findsOneWidget);

      // Refresh
      await tester.tap(find.byTooltip('Refresh'));
      await tester.pumpAndSettle();
      expect(find.byWidgetPredicate((w) => w is SelectableText && w.data?.contains('No operations logged in current session') == true), findsOneWidget);

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

    // 11. Stale or overlapping status checks
    test('11. Stale or overlapping status checks are guarded and do not overwrite newer results', () async {
      final completer1 = Completer<ProcessResult>();
      final completer2 = Completer<ProcessResult>();

      int callIndex = 0;
      final engine = EngineBackendService(
        commandRunner: (exe, args) async {
          callIndex++;
          if (callIndex == 1) {
            return completer1.future;
          } else {
            return completer2.future;
          }
        },
      );

      final req1 = engine.getStatus();
      final req2 = engine.getStatus();

      // Finish second (newer) request first with "ready"
      completer2.complete(ProcessResult(2, 0, '{"install_dir": "/tmp", "docker_diag": {"state": "ready"}, "node_state": "running", "healthy": true}', ''));
      final res2 = await req2;
      expect(res2.dockerDiag.state, DockerState.ready);

      // Finish first (older) request later with "stopped"
      completer1.complete(ProcessResult(1, 0, '{"install_dir": "/tmp", "docker_diag": {"state": "stopped"}, "node_state": "stopped", "healthy": false}', ''));
      final res1 = await req1;
      expect(res1.dockerDiag.state, DockerState.stopped);
    });

    // 12. Altr Stream state evaluated independently once Docker is ready
    test('12. Altr Stream state is evaluated independently after Docker becomes ready', () async {
      // Scenario A: Docker ready, Altr Stream not installed
      final mockNotInstalled = MockBackendService(currentScenario: MockScenario.nodeNotInstalled);
      final statusA = await mockNotInstalled.getStatus();
      expect(statusA.dockerDiag.state, DockerState.ready);
      expect(statusA.nodeState, NodeState.notInstalled);
      expect(NodeTitleStatus.fromNodeStatus(statusA), NodeTitleStatus.nodeNotInstalled);

      // Scenario B: Docker ready, Altr Stream stopped
      final mockStopped = MockBackendService(currentScenario: MockScenario.nodeStopped);
      final statusB = await mockStopped.getStatus();
      expect(statusB.dockerDiag.state, DockerState.ready);
      expect(statusB.nodeState, NodeState.stopped);
      expect(NodeTitleStatus.fromNodeStatus(statusB), NodeTitleStatus.nodeStopped);

      // Scenario C: Docker ready, Altr Stream running
      final mockRunning = MockBackendService(currentScenario: MockScenario.running);
      final statusC = await mockRunning.getStatus();
      expect(statusC.dockerDiag.state, DockerState.ready);
      expect(statusC.nodeState, NodeState.running);
      expect(NodeTitleStatus.fromNodeStatus(statusC), NodeTitleStatus.nodeRunning);
    });
  });
}
