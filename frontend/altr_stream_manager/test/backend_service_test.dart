import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:altr_stream_manager/main.dart';
import 'package:altr_stream_manager/models/node_title_status.dart';
import 'package:altr_stream_manager/services/engine_backend_service.dart';
import 'package:altr_stream_manager/services/mock_backend_service.dart';

void main() {
  group('BackendService and Engine Resolution Tests', () {
    test('1. Engine missing in real mode produces error state and not simulated success', () async {
      final engine = EngineBackendService(
        customEnginePath: '/nonexistent/path/to/altr-installer-engine',
      );
      final status = await engine.getStatus();

      expect(status.nodeState, NodeState.error);
      expect(status.dockerDiag.state, DockerState.error);
      expect(status.isRunning, isFalse);
      expect(status.dockerDiag.technicalError, contains('not found'));

      final titleStatus = NodeTitleStatus.fromNodeStatus(status);
      expect(titleStatus, NodeTitleStatus.dockerError);
    });

    test('2. Engine process failing to start produces visible error state', () async {
      final engine = EngineBackendService(
        commandRunner: (exe, args) async {
          throw const ProcessException('dummy-engine', ['status'], 'Permission denied', 13);
        },
      );
      final status = await engine.getStatus();

      expect(status.nodeState, NodeState.error);
      expect(status.dockerDiag.state, DockerState.error);
      expect(status.dockerDiag.technicalError, contains('Permission denied'));

      final titleStatus = NodeTitleStatus.fromNodeStatus(status);
      expect(titleStatus, NodeTitleStatus.dockerError);
    });

    test('3. Malformed engine response produces visible error state', () async {
      final engine = EngineBackendService(
        commandRunner: (exe, args) async {
          return ProcessResult(101, 0, 'INVALID NON-JSON OUTPUT', '');
        },
      );
      final status = await engine.getStatus();

      expect(status.nodeState, NodeState.error);
      expect(status.dockerDiag.state, DockerState.error);
      expect(status.dockerDiag.technicalError, contains('Failed to decode engine output as JSON'));

      final titleStatus = NodeTitleStatus.fromNodeStatus(status);
      expect(titleStatus, NodeTitleStatus.dockerError);
    });

    test('3b. Unsuccessful engine exit code produces visible error state', () async {
      final engine = EngineBackendService(
        commandRunner: (exe, args) async {
          return ProcessResult(102, 1, '', 'Daemon unreachable: connection refused');
        },
      );
      final status = await engine.getStatus();

      expect(status.nodeState, NodeState.error);
      expect(status.dockerDiag.state, DockerState.error);
      expect(status.dockerDiag.technicalError, contains('Engine command failed (code 1)'));

      final titleStatus = NodeTitleStatus.fromNodeStatus(status);
      expect(titleStatus, NodeTitleStatus.dockerError);
    });

    test('4. Explicit mock mode returns MockBackendService', () async {
      final service = initBackendService(forceMock: true);
      expect(service, isA<MockBackendService>());

      final status = await service.getStatus();
      expect(status.nodeState, NodeState.running);
      expect(status.dockerDiag.state, DockerState.ready);
      expect(NodeTitleStatus.fromNodeStatus(status), NodeTitleStatus.nodeRunning);
    });

    test('5. Real mode never silently falls back to simulated success', () async {
      final service = initBackendService(forceMock: false);
      expect(service, isA<EngineBackendService>());
      expect(service is MockBackendService, isFalse);
    });

    test('6. Correct development and packaged path resolution', () {
      final engine = EngineBackendService();
      // Should find the binary in the local dev tree without throwing or needing hardcoded machine paths
      final devPath = engine.resolveEngineBinary();
      expect(devPath, isNotNull);
      expect(File(devPath!).existsSync(), isTrue);
      expect(devPath.contains('altr-installer-engine'), isTrue);
    });

    test('6b. Packaged path strategy detects Resources and adjacent binaries', () {
      final tempDir = Directory.systemTemp.createTempSync('altr_test_bundle_');
      try {
        final macosDir = Directory('${tempDir.path}/Contents/MacOS')..createSync(recursive: true);
        final resourcesDir = Directory('${tempDir.path}/Contents/Resources')..createSync(recursive: true);
        final fakeEngine = File('${resourcesDir.path}/altr-installer-engine')..writeAsStringSync('#!/bin/sh\nexit 0\n');
        if (!Platform.isWindows) {
          Process.runSync('chmod', ['+x', fakeEngine.path]);
        }

        final engine = EngineBackendService();
        final resolved = engine.resolveEngineBinary(
          overrideExecutable: '${macosDir.path}/Altr Stream Manager',
        );

        expect(resolved, equals(fakeEngine.path));
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('6c. Non-executable file is rejected by path resolver', () {
      final tempDir = Directory.systemTemp.createTempSync('altr_test_nonexec_');
      try {
        final nonExecFile = File('${tempDir.path}/altr-installer-engine')..writeAsStringSync('not an executable');
        if (!Platform.isWindows) {
          Process.runSync('chmod', ['-x', nonExecFile.path]);
        }

        final engine = EngineBackendService(customEnginePath: nonExecFile.path);
        final resolved = engine.resolveEngineBinary();

        expect(resolved, isNull);
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('6d. Stale or non-existent override fails clearly without falling through', () {
      final engine = EngineBackendService(customEnginePath: '/stale/nonexistent/engine/binary');
      final resolved = engine.resolveEngineBinary();

      // Must return null immediately and NEVER fall through to local dev or packaged binaries
      expect(resolved, isNull);
    });

    test('6e. Arbitrary /tmp binary is never resolved as a fallback', () {
      // Create a test binary ONLY in /tmp with a unique name
      final uniqueTmpName = 'altr-test-only-in-tmp-${DateTime.now().millisecondsSinceEpoch}';
      final tmpBinary = File('/tmp/$uniqueTmpName')..writeAsStringSync('#!/bin/sh\n');
      if (!Platform.isWindows) {
        Process.runSync('chmod', ['+x', tmpBinary.path]);
      }
      try {
        // Without an override, resolveEngineBinary looks strictly for standard binaryName in valid tiers
        final engine = EngineBackendService();
        final resolved = engine.resolveEngineBinary();

        // If a binary is resolved, it must be from packaging/engine or dist, NEVER from /tmp
        if (resolved != null) {
          expect(resolved.startsWith('/tmp'), isFalse);
          expect(resolved.contains('packaging/engine') || resolved.contains('dist'), isTrue);
        }
      } finally {
        if (tmpBinary.existsSync()) {
          tmpBinary.deleteSync();
        }
      }
    });

    test('MockBackendService handles startNode and stopNode', () async {
      final mock = MockBackendService(currentScenario: MockScenario.dockerStopped);
      expect(await mock.startNode(), isTrue);
      expect(mock.currentScenario, MockScenario.running);

      expect(await mock.stopNode(), isTrue);
    });

    test('EngineBackendService executes live engine status', () async {
      final engine = EngineBackendService();
      final status = await engine.getStatus();

      expect(status.installDir, isNotEmpty);
      expect(status.targetVersion, isNotEmpty);
      expect(status.dockerDiag.state, isNotNull);
      expect(status.nodeState, isNotNull);
    });
  });

  group('Docker Detection and Startup Recovery Tests', () {
    test('Docker stopped -> Docker running state transition mapping', () {
      final stoppedStatus = NodeStatus(
        installDir: '/tmp/test',
        targetVersion: '1.0.0-beta',
        nodeState: NodeState.notInstalled,
        dockerDiag: const DockerDiagnostics(
          state: DockerState.stopped,
          statusText: 'Docker Desktop is Stopped',
        ),
      );
      expect(NodeTitleStatus.fromNodeStatus(stoppedStatus), NodeTitleStatus.dockerStopped);

      final runningStatus = NodeStatus(
        installDir: '/tmp/test',
        targetVersion: '1.0.0-beta',
        nodeState: NodeState.running,
        healthy: true,
        dockerDiag: const DockerDiagnostics(
          state: DockerState.ready,
          statusText: 'Ready',
          engineRunning: true,
        ),
      );
      expect(NodeTitleStatus.fromNodeStatus(runningStatus), NodeTitleStatus.nodeRunning);
    });

    test('Docker Desktop launched but daemon not yet ready maps to dockerStarting', () {
      final startingStatus = NodeStatus(
        installDir: '/tmp/test',
        targetVersion: '1.0.0-beta',
        nodeState: NodeState.stopped,
        dockerDiag: const DockerDiagnostics(
          state: DockerState.starting,
          statusText: 'Docker Desktop is Starting',
          actionHint: 'Waiting for Docker daemon to become ready...',
        ),
      );
      final titleStatus = NodeTitleStatus.fromNodeStatus(startingStatus);
      expect(titleStatus, NodeTitleStatus.dockerStarting);
      expect(titleStatus.isProgressActive, isTrue);
      expect(titleStatus.dockerState, DockerState.starting);
    });

    test('Daemon becomes ready within the polling window (startDockerDesktop returns true)', () async {
      final calls = <List<String>>[];
      final engine = EngineBackendService(
        commandRunner: (exe, args) async {
          calls.add(args);
          if (args.contains('launch-docker')) {
            return ProcessResult(1, 0, 'Docker launched', '');
          }
          if (args.contains('wait-docker')) {
            return ProcessResult(2, 0, '{"success":true,"state":"ready"}', '');
          }
          return ProcessResult(0, 0, '{}', '');
        },
      );

      final started = await engine.startDockerDesktop();
      expect(started, isTrue);
      expect(calls.any((c) => c.contains('launch-docker')), isTrue);
      expect(calls.any((c) => c.contains('wait-docker')), isTrue);
      expect(engine.lastEngineError, isNull);
    });

    test('Daemon never becomes ready and timeout is reported correctly', () async {
      final engine = EngineBackendService(
        commandRunner: (exe, args) async {
          if (args.contains('launch-docker')) {
            return ProcessResult(1, 0, 'Docker launched', '');
          }
          if (args.contains('wait-docker')) {
            return ProcessResult(2, 1, '', 'timeout waiting for Docker Engine readiness after 60s');
          }
          return ProcessResult(0, 0, '{}', '');
        },
      );

      final started = await engine.startDockerDesktop();
      expect(started, isFalse);
      expect(engine.lastEngineError, isNotNull);
      expect(engine.lastEngineError, contains('did not become ready within 60s'));
      expect(engine.lastEngineError, contains('timeout waiting for Docker Engine'));
    });

    test('Manual refresh after Docker starts updates status without requiring app restart', () async {
      int queryCount = 0;
      final engine = EngineBackendService(
        commandRunner: (exe, args) async {
          queryCount++;
          if (queryCount == 1) {
            // First check: Docker is stopped
            return ProcessResult(1, 0, '''{
              "install_dir": "/tmp/test",
              "target_version": "1.0.0-beta",
              "container_state": "not_installed",
              "docker_diag": {
                "state": "stopped",
                "status_text": "Docker Desktop is Stopped"
              }
            }''', '');
          } else {
            // Subsequent check (manual refresh): Docker is now ready and running
            return ProcessResult(2, 0, '''{
              "install_dir": "/tmp/test",
              "target_version": "1.0.0-beta",
              "container_state": "running",
              "healthy": true,
              "docker_diag": {
                "state": "ready",
                "status_text": "Ready",
                "engine_running": true
              }
            }''', '');
          }
        },
      );

      final initial = await engine.getStatus();
      expect(initial.dockerDiag.state, DockerState.stopped);
      expect(NodeTitleStatus.fromNodeStatus(initial), NodeTitleStatus.dockerStopped);

      // Manual refresh
      final refreshed = await engine.refreshStatus();
      expect(refreshed.dockerDiag.state, DockerState.ready);
      expect(refreshed.nodeState, NodeState.running);
      expect(NodeTitleStatus.fromNodeStatus(refreshed), NodeTitleStatus.nodeRunning);
    });

    test('Engine failure or malformed output does not get mistaken for permanently stopped', () async {
      final engine = EngineBackendService(
        commandRunner: (exe, args) async {
          return ProcessResult(99, 1, '', 'Fatal daemon crash');
        },
      );

      final status = await engine.getStatus();
      expect(status.dockerDiag.state, DockerState.error);
      expect(status.dockerDiag.state == DockerState.stopped, isFalse);
      expect(NodeTitleStatus.fromNodeStatus(status), NodeTitleStatus.dockerError);
    });
  });
}

