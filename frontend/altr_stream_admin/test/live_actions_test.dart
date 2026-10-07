import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:altr_stream_admin/core/api/api_client.dart';
import 'package:altr_stream_admin/core/api/models.dart';
import 'package:altr_stream_admin/core/config/app_config.dart';
import 'package:altr_stream_admin/core/updates/update_controller.dart';
import 'package:altr_stream_admin/shared/live_actions/live_action_model.dart';
import 'package:altr_stream_admin/shared/live_actions/live_actions_controller.dart';
import 'package:altr_stream_admin/shared/live_actions/live_actions_bar.dart';

class MockLiveActionsApiClient extends ApiClient {
  int checkForUpdatesCallCount = 0;
  int getUpdateStatusCallCount = 0;
  UpdateCheckResponse? updateCheckResponseToReturn;
  UpdateStatusResponse? updateStatusResponseToReturn;
  bool shouldThrowOnCheck = false;

  @override
  Future<UpdateCheckResponse> checkForUpdates({
    String? channel,
    bool forceRefresh = false,
  }) async {
    checkForUpdatesCallCount++;
    if (shouldThrowOnCheck) {
      throw Exception('Network offline');
    }
    return updateCheckResponseToReturn ??
        const UpdateCheckResponse(
          currentVersion: '1.0.0',
          latestVersion: '1.1.0',
          updateAvailable: true,
          channel: 'stable',
          releaseName: 'v1.1.0 Release',
        );
  }

  @override
  Future<UpdateStatusResponse> getUpdateStatus() async {
    getUpdateStatusCallCount++;
    if (updateStatusResponseToReturn != null) {
      return updateStatusResponseToReturn!;
    }
    if (applyUpdateResponseToReturn != null) {
      return applyUpdateResponseToReturn!;
    }
    return const UpdateStatusResponse(
      requestId: null,
      targetVersion: null,
      currentVersion: '1.0.0',
      state: 'idle',
      progressPercent: 0,
      message: 'System is up to date.',
      updatedAt: '2026-10-01T12:00:00Z',
    );
  }

  UpdateStatusResponse? applyUpdateResponseToReturn;
  UpdateStatusResponse? cancelUpdateResponseToReturn;
  int cancelUpdateCallCount = 0;

  @override
  Future<UpdateStatusResponse> applyUpdate({
    required String targetVersion,
    String? channel,
  }) async {
    final res =
        applyUpdateResponseToReturn ??
        UpdateStatusResponse(
          requestId: 'test-req',
          targetVersion: targetVersion,
          currentVersion: '1.0.0',
          state: 'requested',
          progressPercent: 10,
          message: 'Update request dispatched.',
          updatedAt: '2026-10-01T12:00:00Z',
        );
    applyUpdateResponseToReturn = res;
    return res;
  }

  @override
  Future<UpdateStatusResponse> cancelUpdate() async {
    cancelUpdateCallCount++;
    applyUpdateResponseToReturn = null;
    updateStatusResponseToReturn =
        cancelUpdateResponseToReturn ??
        const UpdateStatusResponse(
          requestId: 'test-req',
          targetVersion: '1.1.0',
          currentVersion: '1.0.0',
          state: 'cancelled',
          progressPercent: 0,
          message: 'Update cancelled by user.',
          updatedAt: '2026-10-01T12:00:05Z',
        );
    return updateStatusResponseToReturn!;
  }
}

void main() {
  setUp(() {
    UpdateController.reset();
  });

  tearDown(() {
    UpdateController.reset();
  });

  group('LiveAction & LiveActionPriority Unit Tests', () {
    test('Priority rank order matches requirements', () {
      expect(LiveActionPriority.critical.rank, 0);
      expect(LiveActionPriority.update.rank, 1);
      expect(LiveActionPriority.reload.rank, 2);
      expect(LiveActionPriority.feedback.rank, 3);
      expect(LiveActionPriority.normal.rank, 4);

      expect(
        LiveActionPriority.critical.rank < LiveActionPriority.update.rank,
        isTrue,
      );
      expect(
        LiveActionPriority.update.rank < LiveActionPriority.reload.rank,
        isTrue,
      );
      expect(
        LiveActionPriority.reload.rank < LiveActionPriority.feedback.rank,
        isTrue,
      );
      expect(
        LiveActionPriority.feedback.rank < LiveActionPriority.normal.rank,
        isTrue,
      );
    });

    test('LiveActionsController sorts actions strictly by priority rank', () {
      final controller = LiveActionsController(showFeedbackAction: false);

      final normalAction = LiveAction(
        id: 'action_normal',
        label: 'Normal',
        icon: HugeIcons.strokeRoundedNotification01,
        priority: LiveActionPriority.normal,
        onTap: () {},
      );

      final criticalAction = LiveAction(
        id: 'action_critical',
        label: 'Critical',
        icon: HugeIcons.strokeRoundedAlertCircle,
        priority: LiveActionPriority.critical,
        onTap: () {},
      );

      final reloadAction = LiveAction(
        id: 'action_reload',
        label: 'Reload',
        icon: HugeIcons.strokeRoundedReload,
        priority: LiveActionPriority.reload,
        onTap: () {},
      );

      controller.registerAction(normalAction);
      controller.registerAction(criticalAction);
      controller.registerAction(reloadAction);

      final actions = controller.activeActions;
      expect(actions.length, 3);
      expect(actions[0].id, 'action_critical');
      expect(actions[1].id, 'action_reload');
      expect(actions[2].id, 'action_normal');

      controller.removeAction('action_critical');
      expect(controller.activeActions.length, 2);
      expect(controller.activeActions[0].id, 'action_reload');

      controller.dispose();
    });
  });

  group('LiveActionsBar Widget Tests', () {
    testWidgets('Renders zero actions as minimal empty box when idle', (
      tester,
    ) async {
      final controller = LiveActionsController(showFeedbackAction: false);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(
              title: const Text('Title'),
              actions: [LiveActionsBar(controller: controller)],
            ),
            body: const SizedBox(),
          ),
        ),
      );

      expect(find.byType(LiveActionsBar), findsOneWidget);
      // No live action chips or buttons rendered
      expect(find.byKey(const ValueKey('live_action_feedback')), findsNothing);
      expect(find.byKey(const ValueKey('app_bar_update_chip')), findsNothing);

      controller.dispose();
    });

    testWidgets('Renders single action with label and icon', (tester) async {
      final controller = LiveActionsController(showFeedbackAction: false);
      bool pressed = false;

      controller.registerAction(
        LiveAction(
          id: 'test_single',
          label: 'Single Action',
          icon: HugeIcons.strokeRoundedStar,
          priority: LiveActionPriority.normal,
          onTap: () => pressed = true,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(actions: [LiveActionsBar(controller: controller)]),
          ),
        ),
      );

      expect(find.text('Single Action'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('live_action_test_single')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('live_action_test_single')));
      expect(pressed, isTrue);

      controller.dispose();
    });

    testWidgets(
      'Collapses to compact icon-only mode when constrained or compact=true',
      (tester) async {
        final controller = LiveActionsController(showFeedbackAction: false);

        controller.registerAction(
          LiveAction(
            id: 'action_1',
            label: 'Action One',
            icon: HugeIcons.strokeRoundedAlertCircle,
            priority: LiveActionPriority.critical,
            tooltip: 'Critical Alert',
            onTap: () {},
          ),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              appBar: AppBar(
                actions: [
                  LiveActionsBar(controller: controller, compact: true),
                ],
              ),
            ),
          ),
        );

        // In compact mode, the label text is hidden, icon is visible, tooltip is present
        expect(find.text('Action One'), findsNothing);
        expect(
          find.byKey(const ValueKey('live_action_action_1')),
          findsOneWidget,
        );

        final tooltipFinder = find.byType(Tooltip);
        expect(tooltipFinder, findsWidgets);

        controller.dispose();
      },
    );

    testWidgets('Auto-collapses when 3 actions are present', (tester) async {
      final controller = LiveActionsController(showFeedbackAction: false);

      controller.registerAction(
        LiveAction(
          id: 'a1',
          label: 'First',
          icon: HugeIcons.strokeRoundedAdd01,
          priority: LiveActionPriority.update,
          onTap: () {},
        ),
      );
      controller.registerAction(
        LiveAction(
          id: 'a2',
          label: 'Second',
          icon: HugeIcons.strokeRoundedReload,
          priority: LiveActionPriority.reload,
          onTap: () {},
        ),
      );
      controller.registerAction(
        LiveAction(
          id: 'a3',
          label: 'Third',
          icon: HugeIcons.strokeRoundedComment01,
          priority: LiveActionPriority.feedback,
          onTap: () {},
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(actions: [LiveActionsBar(controller: controller)]),
          ),
        ),
      );

      // With 3 actions, auto-compact triggers: labels hidden, all 3 action keys present
      expect(find.text('First'), findsNothing);
      expect(find.text('Second'), findsNothing);
      expect(find.text('Third'), findsNothing);
      expect(find.byKey(const ValueKey('live_action_a1')), findsOneWidget);
      expect(find.byKey(const ValueKey('live_action_a2')), findsOneWidget);
      expect(find.byKey(const ValueKey('live_action_a3')), findsOneWidget);

      controller.dispose();
    });

    testWidgets(
      'Preserves labels when 2 actions are displayed with sufficient width',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final controller = LiveActionsController(showFeedbackAction: false);

        controller.registerAction(
          LiveAction(
            id: 'a1',
            label: 'First Action',
            icon: HugeIcons.strokeRoundedAdd01,
            priority: LiveActionPriority.update,
            onTap: () {},
          ),
        );
        controller.registerAction(
          LiveAction(
            id: 'a2',
            label: 'Second Action',
            icon: HugeIcons.strokeRoundedReload,
            priority: LiveActionPriority.reload,
            onTap: () {},
          ),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              appBar: AppBar(actions: [LiveActionsBar(controller: controller)]),
            ),
          ),
        );

        expect(find.text('First Action'), findsOneWidget);
        expect(find.text('Second Action'), findsOneWidget);

        controller.dispose();
      },
    );

    testWidgets('Feedback action opens configured callback', (tester) async {
      bool feedbackOpened = false;
      final controller = LiveActionsController(
        onOpenFeedback: () => feedbackOpened = true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(actions: [LiveActionsBar(controller: controller)]),
          ),
        ),
      );

      expect(
        find.byKey(const ValueKey('live_action_feedback')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('live_action_feedback')));
      expect(feedbackOpened, isTrue);

      controller.dispose();
    });
  });

  group('Automatic Update Check & Live Activities Integration', () {
    test(
      'init() performs exactly one automatic update check without polling',
      () async {
        final mockClient = MockLiveActionsApiClient();
        final controller = UpdateController(apiClient: mockClient);

        expect(controller.autoCheckStarted, isFalse);
        expect(mockClient.checkForUpdatesCallCount, 0);

        await controller.init();
        // Allow unawaited async check to complete
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(controller.autoCheckStarted, isTrue);
        expect(mockClient.checkForUpdatesCallCount, 1);
        expect(controller.isUpdateAvailable, isTrue);
        expect(controller.chipState, equals(UpdateChipState.updateAvailable));

        // Re-invoking init() (simulating re-renders or page navigation) does NOT cause duplicate checks
        await controller.init();
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(mockClient.checkForUpdatesCallCount, 1);

        controller.dispose();
      },
    );

    test(
      'Network/server failure during automatic update check fails gracefully without error state',
      () async {
        final mockClient = MockLiveActionsApiClient()
          ..shouldThrowOnCheck = true;
        final controller = UpdateController(apiClient: mockClient);

        await controller.init();
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(controller.autoCheckStarted, isTrue);
        expect(mockClient.checkForUpdatesCallCount, 1);
        // Fails gracefully: chip state remains idle, not error
        expect(controller.chipState, equals(UpdateChipState.idle));
        expect(controller.checkError, isNull);

        controller.dispose();
      },
    );

    test(
      'LiveActionsController formats Update Available action label with version and download icon',
      () async {
        final mockClient = MockLiveActionsApiClient();
        final updateCtrl = UpdateController(apiClient: mockClient);
        await updateCtrl.init();
        await Future<void>.delayed(const Duration(milliseconds: 20));

        bool dialogOpened = false;
        final liveCtrl = LiveActionsController(
          updateController: updateCtrl,
          onOpenFeedback: () {},
          onOpenUpdateDialog: () => dialogOpened = true,
        );

        final actions = liveCtrl.activeActions;
        expect(actions.length, 2); // Update Available + Feedback
        final updateAction = actions.firstWhere((a) => a.id == 'update');
        expect(updateAction.label, 'Update Available · v1.1.0');
        expect(updateAction.icon, equals(HugeIcons.strokeRoundedDownload04));
        expect(updateAction.tooltip, contains('v1.1.0'));

        updateAction.onTap?.call();
        expect(dialogOpened, isTrue);

        liveCtrl.dispose();
        updateCtrl.dispose();
      },
    );

    testWidgets(
      'LiveActionsBar displays expanded "Update Available · v1.1.0" in spacious layout',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final mockClient = MockLiveActionsApiClient();
        final updateCtrl = UpdateController(apiClient: mockClient);
        await updateCtrl.init();
        await tester.pumpAndSettle();

        final liveCtrl = LiveActionsController(
          updateController: updateCtrl,
          onOpenFeedback: () {},
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              appBar: AppBar(actions: [LiveActionsBar(controller: liveCtrl)]),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Update Available · v1.1.0'), findsOneWidget);
        expect(find.text('Feedback'), findsOneWidget);

        liveCtrl.dispose();
        updateCtrl.dispose();
      },
    );

    testWidgets(
      'LiveActionsBar collapses to icon-only mode when constrained or on narrow layout',
      (tester) async {
        // Default tester width is 800px (< 900px breakpoint)
        final mockClient = MockLiveActionsApiClient();
        final updateCtrl = UpdateController(apiClient: mockClient);
        await updateCtrl.init();
        await tester.pumpAndSettle();

        final liveCtrl = LiveActionsController(
          updateController: updateCtrl,
          onOpenFeedback: () {},
        );
        // Register a 3rd action to trigger 3 actions on narrow screen
        liveCtrl.registerAction(
          LiveAction(
            id: 'custom_reload',
            label: 'Reload',
            icon: HugeIcons.strokeRoundedReload,
            priority: LiveActionPriority.reload,
            onTap: () {},
          ),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              appBar: AppBar(actions: [LiveActionsBar(controller: liveCtrl)]),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // On narrow layout (<900px) with 3 actions, collapses to icon-only mode
        expect(find.text('Update Available · v1.1.0'), findsNothing);
        expect(find.text('Feedback'), findsNothing);
        expect(
          find.byKey(const ValueKey('app_bar_update_chip')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('live_action_feedback')),
          findsOneWidget,
        );

        liveCtrl.dispose();
        updateCtrl.dispose();
      },
    );

    test(
      'dismissLater() marks session as dismissed without removing Live Activity',
      () async {
        final mockClient = MockLiveActionsApiClient();
        final updateCtrl = UpdateController(apiClient: mockClient);
        await updateCtrl.init();
        await Future<void>.delayed(const Duration(milliseconds: 20));

        final liveCtrl = LiveActionsController(updateController: updateCtrl);

        expect(updateCtrl.isUpdateAvailable, isTrue);
        expect(updateCtrl.isDismissedLaterThisSession, isFalse);
        expect(liveCtrl.activeActions.any((a) => a.id == 'update'), isTrue);

        // User selects Later
        updateCtrl.dismissLater();

        expect(updateCtrl.isDismissedLaterThisSession, isTrue);
        // Live Activity remains available
        expect(updateCtrl.isUpdateAvailable, isTrue);
        expect(liveCtrl.activeActions.any((a) => a.id == 'update'), isTrue);

        liveCtrl.dispose();
        updateCtrl.dispose();
      },
    );

    test(
      'Automatic update check resolves correctly when node is already on latest version',
      () async {
        final mockClient = MockLiveActionsApiClient()
          ..updateCheckResponseToReturn = const UpdateCheckResponse(
            currentVersion: '1.0.0-beta',
            latestVersion: null,
            updateAvailable: false,
            channel: 'beta',
            checkAvailable: true,
          );
        final updateCtrl = UpdateController(apiClient: mockClient);
        await updateCtrl.init();
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(updateCtrl.isUpdateAvailable, isFalse);
        expect(updateCtrl.chipState, equals(UpdateChipState.idle));
        expect(updateCtrl.latestCheck?.checkAvailable, isTrue);

        updateCtrl.dispose();
      },
    );

    testWidgets(
      'Real ApiClient simulation flow: 1.0.0-beta -> 1.1.0 Update Available chip appears in LiveActivities',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
          AppConfig.simulateUpdateAvailable = false;
        });

        AppConfig.simulateUpdateAvailable = true;
        final realClient = ApiClient();
        final updateCtrl = UpdateController(apiClient: realClient);
        await updateCtrl.init();
        // Allow simulation delay to complete
        await tester.pump(const Duration(milliseconds: 250));
        await tester.pumpAndSettle();

        expect(updateCtrl.isUpdateAvailable, isTrue);
        expect(updateCtrl.targetVersion, '1.1.0');
        expect(updateCtrl.chipState, equals(UpdateChipState.updateAvailable));

        bool dialogOpened = false;
        final liveCtrl = LiveActionsController(
          updateController: updateCtrl,
          onOpenFeedback: () {},
          onOpenUpdateDialog: () => dialogOpened = true,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              appBar: AppBar(actions: [LiveActionsBar(controller: liveCtrl)]),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // In spacious layout (1200px), Update Available · v1.1.0 renders expanded
        expect(find.text('Update Available · v1.1.0'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('app_bar_update_chip')),
          findsOneWidget,
        );

        // Tapping the live activity invokes the dialog
        await tester.tap(find.byKey(const ValueKey('app_bar_update_chip')));
        expect(dialogOpened, isTrue);

        liveCtrl.dispose();
        updateCtrl.dispose();
      },
    );

    testWidgets(
      'Update cancellation: Cancel Update enabled during cancellable phase and cleans up state',
      (tester) async {
        final mockClient = MockLiveActionsApiClient();
        mockClient.updateCheckResponseToReturn = const UpdateCheckResponse(
          currentVersion: '1.0.0-beta',
          latestVersion: '1.1.0',
          updateAvailable: true,
          channel: 'beta',
          checkAvailable: true,
        );

        final updateCtrl = UpdateController(apiClient: mockClient);
        await updateCtrl.checkForUpdates();
        expect(updateCtrl.isUpdateAvailable, isTrue);

        // Start update -> requested state (cancellable)
        await updateCtrl.startUpdate();
        expect(updateCtrl.isActive, isTrue);
        expect(updateCtrl.isCancellable, isTrue);
        expect(updateCtrl.isCritical, isFalse);

        final liveCtrl = LiveActionsController(updateController: updateCtrl);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              appBar: AppBar(actions: [LiveActionsBar(controller: liveCtrl)]),
            ),
          ),
        );
        await tester.pump();
        // In starting/requested state, chip is rendered
        expect(
          find.byKey(const ValueKey('app_bar_update_chip')),
          findsOneWidget,
        );

        // Cancel update
        await updateCtrl.cancelUpdate();
        expect(mockClient.cancelUpdateCallCount, equals(1));
        expect(updateCtrl.isCancelled, isTrue);
        expect(updateCtrl.isActive, isFalse);
        expect(updateCtrl.isUpdateAvailable, isTrue);
        expect(updateCtrl.chipState, equals(UpdateChipState.updateAvailable));

        await tester.pumpAndSettle();
        // Live activity returns to clean Update Available state
        expect(find.text('Update Available · v1.1.0'), findsOneWidget);

        liveCtrl.dispose();
        updateCtrl.dispose();
      },
    );

    testWidgets(
      'Critical phase (applying/health_check) disables Cancel Update and prevents cancellation',
      (tester) async {
        final mockClient = MockLiveActionsApiClient();
        mockClient.updateStatusResponseToReturn = const UpdateStatusResponse(
          requestId: 'req-crit-1',
          targetVersion: '1.1.0',
          currentVersion: '1.0.0-beta',
          state: 'applying',
          progressPercent: 65,
          message: 'Recreating container...',
          updatedAt: '2026-10-07T00:00:10Z',
        );

        final updateCtrl = UpdateController(apiClient: mockClient);
        await updateCtrl.fetchStatus();

        expect(updateCtrl.isApplying, isTrue);
        expect(updateCtrl.isCritical, isTrue);
        expect(updateCtrl.isCancellable, isFalse);

        // Attempting cancellation during critical phase must be rejected
        await updateCtrl.cancelUpdate();
        expect(mockClient.cancelUpdateCallCount, equals(0));
        expect(updateCtrl.isApplying, isTrue);
        expect(updateCtrl.isCritical, isTrue);

        updateCtrl.dispose();
      },
    );

    testWidgets(
      'Polling timeout in requested state transitions to failed without infinite spinning',
      (tester) async {
        final mockClient = MockLiveActionsApiClient();
        mockClient.updateStatusResponseToReturn = const UpdateStatusResponse(
          requestId: 'req-timeout',
          targetVersion: '1.1.0',
          currentVersion: '1.0.0-beta',
          state: 'requested',
          progressPercent: 10,
          message: 'Dispatched to host supervisor.',
          updatedAt: '2026-10-07T00:00:00Z',
        );

        final updateCtrl = UpdateController(apiClient: mockClient);
        await updateCtrl.fetchStatus();
        expect(updateCtrl.isRequested, isTrue);

        // Fast-forward 30 poll intervals (60s)
        for (int i = 0; i < 31; i++) {
          await tester.pump(const Duration(seconds: 2));
        }

        expect(updateCtrl.isFailed, isTrue);
        expect(updateCtrl.statusMessage, contains('timed out'));

        updateCtrl.dispose();
      },
    );

    testWidgets(
      'Real ApiClient simulation flow: startUpdate, progress, and cancel during cancellable phase',
      (tester) async {
        addTearDown(() {
          ApiClient.resetSimulation();
          AppConfig.simulateUpdateAvailable = false;
        });

        ApiClient.resetSimulation();
        AppConfig.simulateUpdateAvailable = true;

        final client = ApiClient();
        final updateCtrl = UpdateController(apiClient: client);

        // Check for updates to resolve targetVersion 1.1.0
        await updateCtrl.checkForUpdates();
        expect(updateCtrl.isUpdateAvailable, isTrue);

        // Start update in simulation
        await updateCtrl.startUpdate();
        expect(updateCtrl.isActive, isTrue);
        expect(updateCtrl.isCancellable, isTrue);
        expect(updateCtrl.progressPercent, equals(10));

        // Cancel update while in requested phase
        await updateCtrl.cancelUpdate();
        expect(updateCtrl.isCancelled, isTrue);
        expect(updateCtrl.isActive, isFalse);

        updateCtrl.dispose();
      },
    );
  });
}
