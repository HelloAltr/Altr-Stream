import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:altr_stream_admin/core/api/api_client.dart';
import 'package:altr_stream_admin/core/api/models.dart';
import 'package:altr_stream_admin/core/auth/models/altr_api_key.dart';
import 'package:altr_stream_admin/core/auth/models/workspace.dart';
import 'package:altr_stream_admin/core/auth/services/passcode_service.dart';
import 'package:altr_stream_admin/shared/live_actions/live_actions_controller.dart';
import 'package:altr_stream_admin/features/settings/screens/settings_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PasscodeService & Zero-Knowledge Verification', () {
    late PasscodeService passcodeService;

    setUp(() {
      passcodeService = PasscodeService();
      passcodeService.lockSudo();
    });

    test('generateSalt generates distinct cryptographic hex salts', () {
      final salt1 = passcodeService.generateSalt(16);
      final salt2 = passcodeService.generateSalt(16);

      expect(salt1.isNotEmpty, isTrue);
      expect(salt2.isNotEmpty, isTrue);
      expect(salt1, isNot(equals(salt2)));
      expect(salt1.length, equals(32)); // 16 bytes = 32 hex chars
    });

    test('computeVerifier produces deterministic HMAC-SHA256 verifier', () {
      const salt = 'a1b2c3d4e5f6';
      const uid = 'usr_test_123';
      const pin = '123456';

      final verifier1 = passcodeService.computeVerifier(
        passcode: pin,
        salt: salt,
        userId: uid,
      );
      final verifier2 = passcodeService.computeVerifier(
        passcode: pin,
        salt: salt,
        userId: uid,
      );

      expect(verifier1, equals(verifier2));
      expect(verifier1.length, equals(64)); // SHA256 hex length

      // Changing pin yields different verifier
      final verifierWrong = passcodeService.computeVerifier(
        passcode: '654321',
        salt: salt,
        userId: uid,
      );
      expect(verifier1, isNot(equals(verifierWrong)));
    });

    test('verifyPasscode validates correct passcode and manages Sudo mode', () async {
      const salt = '7f80ccaf';
      const uid = 'usr_agent_007';
      const correctPin = '998877';
      final verifier = passcodeService.computeVerifier(
        passcode: correctPin,
        salt: salt,
        userId: uid,
      );

      final userProfile = UserProfile(
        id: uid,
        displayName: 'Test User',
        email: 'test@example.com',
        passcodeType: 'pin',
        passcodeSalt: salt,
        passcodeVerifier: verifier,
      );

      expect(passcodeService.isSudoActive, isFalse);

      // Wrong passcode fails
      final wrongRes = await passcodeService.verifyPasscode(
        profile: userProfile,
        enteredPasscode: '000000',
      );
      expect(wrongRes, isFalse);
      expect(passcodeService.isSudoActive, isFalse);

      // Correct passcode succeeds and activates Sudo
      final correctRes = await passcodeService.verifyPasscode(
        profile: userProfile,
        enteredPasscode: correctPin,
      );
      expect(correctRes, isTrue);
      expect(passcodeService.isSudoActive, isTrue);
      expect(passcodeService.sudoRemainingSeconds, greaterThan(290));

      // Lock sudo
      passcodeService.lockSudo();
      expect(passcodeService.isSudoActive, isFalse);
      expect(passcodeService.sudoRemainingSeconds, equals(0));
    });
  });

  group('Workspace & API Key Models', () {
    test('Workspace serialization and service enablement', () {
      final now = DateTime(2026, 10, 30);
      final ws = Workspace(
        id: 'ws_altr_alpha',
        name: 'Altr Core Workspace',
        ownerId: 'usr_owner_1',
        memberUids: ['usr_owner_1', 'usr_dev_2'],
        adminUids: ['usr_owner_1'],
        enabledServices: ['altr_stream'],
        members: {
          'usr_owner_1': WorkspaceMember(
            email: 'owner@altr.dev',
            displayName: 'Lead Engineer',
            role: 'owner',
            joinedAt: now,
          ),
          'usr_dev_2': WorkspaceMember(
            email: 'dev@altr.dev',
            displayName: 'Mesh Collaborator',
            role: 'member',
            joinedAt: now,
          ),
        },
        createdAt: now,
      );

      final firestoreData = ws.toFirestore();
      expect(firestoreData['name'], equals('Altr Core Workspace'));
      expect(firestoreData['owner_id'], equals('usr_owner_1'));
      expect((firestoreData['member_uids'] as List).length, equals(2));
      expect((firestoreData['enabled_services'] as List), contains('altr_stream'));

      final restored = Workspace.fromFirestore('ws_altr_alpha', firestoreData);
      expect(restored.id, equals('ws_altr_alpha'));
      expect(restored.members.length, equals(2));
      expect(restored.members['usr_dev_2']?.displayName, equals('Mesh Collaborator'));

      // Enable new service
      final updated = restored.copyWith(
        enabledServices: [...restored.enabledServices, 'altr_chat'],
      );
      expect(updated.enabledServices, containsAll(['altr_stream', 'altr_chat']));
    });

    test('AltrApiKey parses scopes and formatting', () {
      final key = AltrApiKey.fromJson({
        'id': 'key_123',
        'key': 'altr_live_sec_abcdef123456',
        'name': 'Production Engine Sync',
        'scopes': ['read', 'write', 'admin'],
        'created_at': '2026-10-30T09:00:00Z',
        'expires_at': null,
      });

      expect(key.id, equals('key_123'));
      expect(key.keyPrefix, equals('altr_live_sec_'));
      expect(key.scopes, containsAll(['read', 'write', 'admin']));
      expect(key.isExpired, isFalse);
    });
  });

  group('LiveActionsController Sudo Synchronization', () {
    test('activateSudo and lockSudo manage live Sudo action chip', () {
      final controller = LiveActionsController();

      expect(controller.isSudoActive, isFalse);
      expect(controller.activeActions.any((a) => a.id == 'sudo'), isFalse);

      controller.activateSudo(durationSeconds: 300);
      expect(controller.isSudoActive, isTrue);
      expect(controller.activeActions.any((a) => a.id == 'sudo'), isTrue);

      final sudoAction = controller.activeActions.firstWhere((a) => a.id == 'sudo');
      expect(sudoAction.label, contains('Sudo'));

      controller.lockSudo();
      expect(controller.isSudoActive, isFalse);
      expect(controller.activeActions.any((a) => a.id == 'sudo'), isFalse);

      controller.dispose();
    });
  });

  group('SettingsScreen Security UI', () {
    testWidgets('Renders Security, Passcode & API Keys card and fires callbacks', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(1440, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      bool passcodeTapped = false;
      bool workspacesTapped = false;

      final user = UserProfile(
        id: 'usr_mock',
        displayName: 'Security Admin',
        email: 'sec@helloaltr.com',
        passcodeType: 'pin',
        passcodeSalt: 'salt123',
        passcodeVerifier: 'verifier123',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SettingsScreen(
              apiClient: ApiClient(),
              onNodeStatusTap: () {},
              currentUser: user,
              activeWorkspaceName: 'Alpha Research Lab',
              onPasscodeTap: () => passcodeTapped = true,
              onWorkspacesTap: () => workspacesTapped = true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Security & Passcode'), findsWidgets);
      expect(find.text('Alpha Research Lab'), findsOneWidget);
      expect(find.text('PROTECTED (PIN)'), findsOneWidget);

      // Tap Workspaces
      await tester.tap(find.text('Workspaces').first);
      await tester.pumpAndSettle();
      expect(workspacesTapped, isTrue);

      // Tap Change passcode
      await tester.tap(find.text('Change'));
      await tester.pumpAndSettle();
      expect(passcodeTapped, isTrue);

      // Switch to dedicated API Keys page
      await tester.tap(find.text('API Keys & Access'));
      await tester.pumpAndSettle();
      expect(find.text('Generate New Key'), findsWidgets);
    });
  });
}
