import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:altr_stream_admin/core/api/api_client.dart';
import 'package:altr_stream_admin/shared/feedback/feedback_dialog.dart';

class MockFeedbackApiClient extends ApiClient {
  Map<String, dynamic>? lastSubmittedPayload;
  int submitCount = 0;
  Completer<Map<String, dynamic>>? pendingCompleter;
  Map<String, dynamic> responseToReturn = {
    'success': true,
    'issue_number': 42,
    'issue_url': 'https://github.com/HelloAltr/Altr-Stream/issues/42',
    'title': '[Bug] Test bug',
  };
  Object? errorToThrow;

  @override
  Future<Map<String, dynamic>> submitFeedback(
    Map<String, dynamic> payload,
  ) async {
    lastSubmittedPayload = payload;
    submitCount++;
    if (pendingCompleter != null) {
      return pendingCompleter!.future;
    }
    if (errorToThrow != null) {
      throw errorToThrow!;
    }
    return responseToReturn;
  }
}

void main() {
  group('FeedbackDialog Tests', () {
    testWidgets('Renders with default Bug category, inputs, and buttons', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final mockClient = MockFeedbackApiClient();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: FeedbackDialog(apiClient: mockClient)),
        ),
      );

      expect(find.text('Send Beta Feedback'), findsOneWidget);
      expect(find.text('Bug'), findsOneWidget);
      expect(find.text('Feature Request'), findsOneWidget);
      expect(find.text('Usability / UX'), findsOneWidget);
      expect(find.text('General'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('feedback_summary_input')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('feedback_message_input')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('feedback_contact_input')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('feedback_diagnostics_checkbox')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('feedback_submit_button')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('feedback_cancel_button')),
        findsOneWidget,
      );

      // Verify diagnostics checkbox is unchecked by default
      final checkbox = tester.widget<CheckboxListTile>(
        find.byKey(const ValueKey('feedback_diagnostics_checkbox')),
      );
      expect(checkbox.value, isFalse);
    });

    testWidgets('Category selection switches active chip', (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final mockClient = MockFeedbackApiClient();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: FeedbackDialog(apiClient: mockClient)),
        ),
      );

      // Tap 'Feature Request'
      await tester.tap(
        find.byKey(const ValueKey('feedback_category_Feature Request')),
      );
      await tester.pumpAndSettle();

      final featureChip = tester.widget<ChoiceChip>(
        find.byKey(const ValueKey('feedback_category_Feature Request')),
      );
      expect(featureChip.selected, isTrue);

      final bugChip = tester.widget<ChoiceChip>(
        find.byKey(const ValueKey('feedback_category_Bug')),
      );
      expect(bugChip.selected, isFalse);
    });

    testWidgets('Validates required summary and message fields', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final mockClient = MockFeedbackApiClient();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: FeedbackDialog(apiClient: mockClient)),
        ),
      );

      // Scroll to submit button and tap
      await tester.ensureVisible(
        find.byKey(const ValueKey('feedback_submit_button')),
      );
      await tester.tap(find.byKey(const ValueKey('feedback_submit_button')));
      await tester.pumpAndSettle();

      expect(find.text('Please provide a brief summary'), findsOneWidget);
      expect(find.text('Feedback message cannot be empty'), findsOneWidget);
      expect(mockClient.lastSubmittedPayload, isNull);
    });

    testWidgets('Submits feedback with diagnostics omitted by default', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final mockClient = MockFeedbackApiClient();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () =>
                    FeedbackDialog.show(context, apiClient: mockClient),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Enter summary and message without checking diagnostics
      await tester.enterText(
        find.byKey(const ValueKey('feedback_summary_input')),
        'Issue with source sync',
      );
      await tester.enterText(
        find.byKey(const ValueKey('feedback_message_input')),
        'When syncing MongoDB source, preview times out.',
      );

      await tester.ensureVisible(
        find.byKey(const ValueKey('feedback_submit_button')),
      );
      await tester.tap(find.byKey(const ValueKey('feedback_submit_button')));
      await tester.pumpAndSettle();

      expect(mockClient.lastSubmittedPayload, isNotNull);
      final payload = mockClient.lastSubmittedPayload!;
      expect(payload['category'], 'Bug');
      expect(payload['summary'], 'Issue with source sync');
      expect(
        payload['message'],
        'When syncing MongoDB source, preview times out.',
      );
      expect(payload['include_diagnostics'], isFalse);
      expect(payload['diagnostics'], isNull);

      // Dialog should be dismissed
      expect(find.byType(FeedbackDialog), findsNothing);
    });

    testWidgets(
      'Submits feedback with diagnostics included when user opts in',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 1000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final mockClient = MockFeedbackApiClient();

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () =>
                      FeedbackDialog.show(context, apiClient: mockClient),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const ValueKey('feedback_summary_input')),
          'Issue with source sync',
        );
        await tester.enterText(
          find.byKey(const ValueKey('feedback_message_input')),
          'When syncing MongoDB source, preview times out.',
        );
        await tester.enterText(
          find.byKey(const ValueKey('feedback_contact_input')),
          '@beta_tester',
        );

        // Scroll to diagnostics checkbox and toggle ON
        await tester.ensureVisible(
          find.byKey(const ValueKey('feedback_diagnostics_checkbox')),
        );
        await tester.tap(
          find.byKey(const ValueKey('feedback_diagnostics_checkbox')),
        );
        await tester.pumpAndSettle();

        // Submit
        await tester.ensureVisible(
          find.byKey(const ValueKey('feedback_submit_button')),
        );
        await tester.tap(find.byKey(const ValueKey('feedback_submit_button')));
        await tester.pumpAndSettle();

        expect(mockClient.lastSubmittedPayload, isNotNull);
        final payload = mockClient.lastSubmittedPayload!;
        expect(payload['include_diagnostics'], isTrue);
        expect(payload['diagnostics'], isNotNull);
        expect(payload['contact'], '@beta_tester');

        expect(find.byType(FeedbackDialog), findsNothing);
      },
    );

    testWidgets('Shows error banner when API returns 503 unconfigured error', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final mockClient = MockFeedbackApiClient();
      mockClient.errorToThrow = ApiException(
        message: 'Feedback service is not configured on this node.',
        statusCode: 503,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: FeedbackDialog(apiClient: mockClient)),
        ),
      );

      await tester.enterText(
        find.byKey(const ValueKey('feedback_summary_input')),
        'Some bug',
      );
      await tester.enterText(
        find.byKey(const ValueKey('feedback_message_input')),
        'Some detailed description of the bug',
      );

      await tester.ensureVisible(
        find.byKey(const ValueKey('feedback_submit_button')),
      );
      await tester.tap(find.byKey(const ValueKey('feedback_submit_button')));
      await tester.pumpAndSettle();

      // Dialog remains open and displays error banner
      expect(find.byType(FeedbackDialog), findsOneWidget);
      expect(
        find.text('Feedback service is not configured on this node.'),
        findsOneWidget,
      );
    });

    testWidgets('Shows error banner when API returns 400 bad request error', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final mockClient = MockFeedbackApiClient();
      mockClient.errorToThrow = ApiException(
        message: 'Invalid feedback request. Please verify your message.',
        statusCode: 400,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: FeedbackDialog(apiClient: mockClient)),
        ),
      );

      await tester.enterText(
        find.byKey(const ValueKey('feedback_summary_input')),
        'Some bug',
      );
      await tester.enterText(
        find.byKey(const ValueKey('feedback_message_input')),
        'Some detailed description',
      );

      await tester.ensureVisible(
        find.byKey(const ValueKey('feedback_submit_button')),
      );
      await tester.tap(find.byKey(const ValueKey('feedback_submit_button')));
      await tester.pumpAndSettle();

      expect(find.byType(FeedbackDialog), findsOneWidget);
      expect(
        find.text('Invalid feedback request. Please verify your message.'),
        findsOneWidget,
      );
    });

    testWidgets('Shows error banner when API returns 502 upstream error', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final mockClient = MockFeedbackApiClient();
      mockClient.errorToThrow = ApiException(
        message: 'Unable to submit feedback right now. Please try again later.',
        statusCode: 502,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: FeedbackDialog(apiClient: mockClient)),
        ),
      );

      await tester.enterText(
        find.byKey(const ValueKey('feedback_summary_input')),
        'Some bug',
      );
      await tester.enterText(
        find.byKey(const ValueKey('feedback_message_input')),
        'Some detailed description',
      );

      await tester.ensureVisible(
        find.byKey(const ValueKey('feedback_submit_button')),
      );
      await tester.tap(find.byKey(const ValueKey('feedback_submit_button')));
      await tester.pumpAndSettle();

      expect(find.byType(FeedbackDialog), findsOneWidget);
      expect(
        find.text(
          'Unable to submit feedback right now. Please try again later.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('Shows error banner on network failure / 504 timeout', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final mockClient = MockFeedbackApiClient();
      // Non-ApiException network error triggers fallback
      mockClient.errorToThrow = Exception('Network socket closed');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: FeedbackDialog(apiClient: mockClient)),
        ),
      );

      await tester.enterText(
        find.byKey(const ValueKey('feedback_summary_input')),
        'Some bug',
      );
      await tester.enterText(
        find.byKey(const ValueKey('feedback_message_input')),
        'Some detailed description',
      );

      await tester.ensureVisible(
        find.byKey(const ValueKey('feedback_submit_button')),
      );
      await tester.tap(find.byKey(const ValueKey('feedback_submit_button')));
      await tester.pumpAndSettle();

      expect(find.byType(FeedbackDialog), findsOneWidget);
      expect(
        find.text(
          'Feedback service is unreachable. Please check your connection and try again.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('Submit loading state and double-submit prevention', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final mockClient = MockFeedbackApiClient();
      final completer = Completer<Map<String, dynamic>>();
      mockClient.pendingCompleter = completer;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: FeedbackDialog(apiClient: mockClient)),
        ),
      );

      await tester.enterText(
        find.byKey(const ValueKey('feedback_summary_input')),
        'Slow query test',
      );
      await tester.enterText(
        find.byKey(const ValueKey('feedback_message_input')),
        'Testing in-flight submission state',
      );

      await tester.ensureVisible(
        find.byKey(const ValueKey('feedback_submit_button')),
      );
      await tester.tap(find.byKey(const ValueKey('feedback_submit_button')));
      await tester.pump(); // Advance to start submission

      // Verify submit button is disabled and shows progress indicator
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(mockClient.submitCount, 1);

      // Attempt second tap while in-flight
      await tester.tap(
        find.byKey(const ValueKey('feedback_submit_button')),
        warnIfMissed: false,
      );
      await tester.pump();
      expect(mockClient.submitCount, 1); // Not incremented

      // Complete the request
      completer.complete(mockClient.responseToReturn);
      await tester.pumpAndSettle();
    });

    testWidgets('Cancel button dismisses dialog without submitting', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final mockClient = MockFeedbackApiClient();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () =>
                    FeedbackDialog.show(context, apiClient: mockClient),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.byType(FeedbackDialog), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const ValueKey('feedback_cancel_button')),
      );
      await tester.tap(find.byKey(const ValueKey('feedback_cancel_button')));
      await tester.pumpAndSettle();

      expect(find.byType(FeedbackDialog), findsNothing);
      expect(mockClient.lastSubmittedPayload, isNull);
    });
  });
}
