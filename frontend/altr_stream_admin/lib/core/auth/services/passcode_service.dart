import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../../api/models.dart';
import 'auth_service.dart';

/// Zero-knowledge passcode management and 5-minute Sudo grace period for Altr Stream Admin.
class PasscodeService extends ChangeNotifier {
  static final PasscodeService _instance = PasscodeService._internal();
  factory PasscodeService() => _instance;

  PasscodeService._internal();

  DateTime? _sudoExpiresAt;
  Timer? _sudoTimer;

  // In-memory credential fallback so passcode functions immediately offline/in-memory
  final Map<String, ({String salt, String verifier, String type})> _localCredentials = {};

  bool get isSudoActive =>
      _sudoExpiresAt != null && DateTime.now().isBefore(_sudoExpiresAt!);

  int get sudoRemainingSeconds {
    if (!isSudoActive || _sudoExpiresAt == null) return 0;
    final diff = _sudoExpiresAt!.difference(DateTime.now()).inSeconds;
    return diff > 0 ? diff : 0;
  }

  /// Activates Sudo mode for a 5-minute (300 seconds) grace period.
  void activateSudo({int durationSeconds = 300}) {
    _sudoExpiresAt = DateTime.now().add(Duration(seconds: durationSeconds));
    _sudoTimer?.cancel();
    _sudoTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!isSudoActive) {
        _sudoTimer?.cancel();
        _sudoTimer = null;
        _sudoExpiresAt = null;
        notifyListeners();
      } else {
        notifyListeners();
      }
    });
    notifyListeners();
  }

  /// Locks elevated Sudo privileges immediately.
  void lockSudo() {
    _sudoTimer?.cancel();
    _sudoTimer = null;
    _sudoExpiresAt = null;
    notifyListeners();
  }

  /// Generate cryptographically secure random hex salt.
  String generateSalt([int length = 16]) {
    final random = Random.secure();
    final bytes = List<int>.generate(length, (_) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Compute HMAC-SHA256 verifier for the passcode.
  String computeVerifier({
    required String passcode,
    required String salt,
    required String userId,
  }) {
    final key = utf8.encode(salt);
    final payload = utf8.encode('$passcode:$userId');
    final hmacSha256 = Hmac(sha256, key);
    return hmacSha256.convert(payload).toString();
  }

  /// Clear credentials from local cache and ensure Sudo is locked.
  void clearCredentials([String? userId]) {
    if (userId != null) {
      _localCredentials.remove(userId);
    } else {
      _localCredentials.clear();
    }
    lockSudo();
  }

  /// Get the configured passcode type for user ('pin' or 'password').
  String? getCredentialType(String? userId, [String? email]) {
    if (userId != null && _localCredentials.containsKey(userId)) {
      return _localCredentials[userId]!.type;
    }
    if (email != null && email.isNotEmpty) {
      final emailSlug = 'usr_${email.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';
      if (_localCredentials.containsKey(emailSlug)) {
        return _localCredentials[emailSlug]!.type;
      }
    }
    if (_localCredentials.isNotEmpty) {
      return _localCredentials.values.first.type;
    }
    return null;
  }

  /// Check whether credentials are registered for the given user profile.
  bool hasConfiguredPasscode(UserProfile? profile) {
    if (profile == null) {
      return _localCredentials.isNotEmpty;
    }
    if (profile.hasPasscode) return true;
    if (_localCredentials.containsKey(profile.id)) return true;
    if (profile.email.isNotEmpty) {
      final emailSlug = 'usr_${profile.email.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';
      if (_localCredentials.containsKey(emailSlug)) return true;
    }
    return false;
  }

  /// Set up or update passcode in Firestore user profile and local state.
  Future<void> setupPasscode({
    required String userId,
    required String passcode,
    required String passcodeType, // 'pin' or 'password'
  }) async {
    final salt = generateSalt();
    final verifier = computeVerifier(
      passcode: passcode.trim(),
      salt: salt,
      userId: userId,
    );

    // Save locally
    _localCredentials[userId] = (salt: salt, verifier: verifier, type: passcodeType);
    final activeEmail = AuthService().currentProfile?.email;
    if (activeEmail != null && activeEmail.isNotEmpty) {
      final emailSlug = 'usr_${activeEmail.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';
      _localCredentials[emailSlug] = (salt: salt, verifier: verifier, type: passcodeType);
    }

    // Update active profile in AuthService
    AuthService().updatePasscodeDetails(
      passcodeType: passcodeType,
      salt: salt,
      verifier: verifier,
    );

    // Persist to Firestore if available
    try {
      await FirebaseFirestore.instance.collection('users').doc(userId).set({
        'passcode_type': passcodeType,
        'passcode_salt': salt,
        'passcode_verifier': verifier,
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[PasscodeService] Error saving passcode to Firestore: $e');
    }

    // Entering or updating passcode immediately unlocks Sudo mode
    activateSudo();
  }

  /// Verify entered passcode against the user's stored verifier and salt.
  Future<bool> verifyPasscode({
    required UserProfile profile,
    required String enteredPasscode,
  }) async {
    if (isSudoActive) {
      return true; // Already verified within grace period
    }

    final emailSlug = profile.email.isNotEmpty
        ? 'usr_${profile.email.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}'
        : null;
    final local = _localCredentials[profile.id] ??
        (emailSlug != null ? _localCredentials[emailSlug] : null);
    final salt = profile.passcodeSalt ?? local?.salt ?? AuthService().currentProfile?.passcodeSalt;
    final storedVerifier = profile.passcodeVerifier ?? local?.verifier ?? AuthService().currentProfile?.passcodeVerifier;

    // Security requirement: if user has not yet configured a passcode, NEVER activate sudo!
    if (salt == null || storedVerifier == null || storedVerifier.isEmpty) {
      return false;
    }

    final calculatedVerifier = computeVerifier(
      passcode: enteredPasscode.trim(),
      salt: salt,
      userId: profile.id,
    );

    if (calculatedVerifier == storedVerifier) {
      activateSudo();
      return true;
    }

    return false;
  }

  /// Verify entered passcode strictly against credentials without bypassing on sudo status.
  bool checkPasscodeMatch({
    required UserProfile profile,
    required String enteredPasscode,
  }) {
    final emailSlug = profile.email.isNotEmpty
        ? 'usr_${profile.email.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}'
        : null;
    final local = _localCredentials[profile.id] ??
        (emailSlug != null ? _localCredentials[emailSlug] : null);
    final salt = profile.passcodeSalt ?? local?.salt ?? AuthService().currentProfile?.passcodeSalt;
    final storedVerifier = profile.passcodeVerifier ?? local?.verifier ?? AuthService().currentProfile?.passcodeVerifier;

    if (salt == null || storedVerifier == null || storedVerifier.isEmpty) {
      return false;
    }

    final calculatedVerifier = computeVerifier(
      passcode: enteredPasscode.trim(),
      salt: salt,
      userId: profile.id,
    );

    return calculatedVerifier == storedVerifier;
  }
}
