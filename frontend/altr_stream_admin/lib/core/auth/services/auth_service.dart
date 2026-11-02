import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../../../firebase_options.dart';
import '../../api/models.dart';
import 'passcode_service.dart';
import 'workspace_service.dart';

/// Firebase Authentication & Google Sign-In Service for Altr Stream Admin (Web).
class AuthService extends ChangeNotifier {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;

  AuthService._internal();

  FirebaseAuth? _auth;
  FirebaseFirestore? _firestore;
  UserProfile? _currentProfile;
  bool _isInitialized = false;

  bool get isInitialized => _isInitialized;
  bool get isAuthenticated => _auth?.currentUser != null;
  User? get currentUser => _auth?.currentUser;
  UserProfile? get currentProfile => _currentProfile;

  /// Initialize Firebase app and listen to auth state changes.
  Future<void> initialize() async {
    if (_isInitialized) return;
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      _auth = FirebaseAuth.instance;
      _firestore = FirebaseFirestore.instance;

      _auth?.authStateChanges().listen(_handleAuthStateChanged);
      _isInitialized = true;
      notifyListeners();
    } catch (e) {
      debugPrint('[AuthService] Firebase initialization note: $e');
      _isInitialized = true;
      notifyListeners();
    }
  }

  /// Set active profile directly.
  void setProfileDirect(UserProfile profile) {
    _currentProfile = profile;
    notifyListeners();
  }

  /// Check whether an account exists in Firestore for the given userId.
  Future<UserProfile?> checkProfileExists(String userId) async {
    try {
      final fs = FirebaseFirestore.instance;
      final docRef = fs.collection('users').doc(userId);
      final snapshot = await docRef.get();
      if (snapshot.exists && snapshot.data() != null) {
        final profile = UserProfile.fromFirestore(userId, snapshot.data()!);
        _currentProfile = profile;
        await WorkspaceService().fetchUserWorkspaces(userId, workspaceIds: profile.workspaceIds);
        notifyListeners();
        return profile;
      }
    } catch (e) {
      debugPrint('[AuthService] Error checking profile existence in Firestore: $e');
    }
    return null;
  }

  Future<void> _handleAuthStateChanged(User? user) async {
    if (user == null) {
      _currentProfile = null;
      notifyListeners();
      return;
    }

    try {
      final existing = await checkProfileExists(user.uid);
      if (existing != null) {
        if (user.photoURL != null &&
            user.photoURL!.isNotEmpty &&
            existing.photoUrl != user.photoURL) {
          final updated = existing.copyWith(photoUrl: user.photoURL);
          _currentProfile = updated;
          _firestore?.collection('users').doc(user.uid).set(
            {'photo_url': user.photoURL},
            SetOptions(merge: true),
          );
        } else {
          _currentProfile = existing;
        }
      } else {
        // No Firestore profile yet. Leave as null so the UI opens AccountWorkspaceSetupDialog.
        _currentProfile = null;
      }
    } catch (e) {
      debugPrint('[AuthService] Error loading user profile: $e');
      _currentProfile = null;
    }
    notifyListeners();
  }

  /// Sign in with Google on Web.
  Future<UserCredential?> signInWithGoogle() async {
    if (_auth == null) {
      await initialize();
    }
    try {
      final googleProvider = GoogleAuthProvider();
      googleProvider.addScope('email');
      googleProvider.addScope('profile');

      final userCredential = await _auth!.signInWithPopup(googleProvider);
      return userCredential;
    } catch (e) {
      debugPrint('[AuthService] Google Sign-In error: $e');
      rethrow;
    }
  }

  /// Refresh user profile from Firestore.
  Future<void> refreshProfile() async {
    final user = _auth?.currentUser;
    if (user != null) {
      await _handleAuthStateChanged(user);
    }
  }

  /// Update active profile passcode details and notify listeners.
  void updatePasscodeDetails({
    required String passcodeType,
    required String salt,
    required String verifier,
  }) {
    if (_currentProfile != null) {
      _currentProfile = _currentProfile!.copyWith(
        passcodeType: passcodeType,
        passcodeSalt: salt,
        passcodeVerifier: verifier,
      );
    } else {
      _currentProfile = UserProfile(
        id: 'local_admin',
        displayName: 'Local Admin',
        email: 'admin@localhost',
        passcodeType: passcodeType,
        passcodeSalt: salt,
        passcodeVerifier: verifier,
      );
    }
    notifyListeners();
  }

  /// Manually activate and sync a user profile (e.g. In manual sign-in fallback).
  Future<void> setManualProfile(UserProfile profile) async {
    _currentProfile = profile;
    try {
      final docRef = _firestore?.collection('users').doc(profile.id);
      if (docRef != null) {
        final snap = await docRef.get();
        if (snap.exists && snap.data() != null) {
          final data = snap.data()!;
          _currentProfile = UserProfile.fromFirestore(snap.id, data);
        } else {
          await docRef.set(profile.toFirestore(), SetOptions(merge: true));
        }
      }
    } catch (e) {
      debugPrint('[AuthService] Error syncing manual profile with Firestore: $e');
    }
    notifyListeners();
  }

  /// Sign out.
  Future<void> signOut() async {
    try {
      await _auth?.signOut();
      _currentProfile = null;
      PasscodeService().lockSudo();
      notifyListeners();
    } catch (e) {
      debugPrint('[AuthService] Sign-out error: $e');
      _currentProfile = null;
      PasscodeService().lockSudo();
      notifyListeners();
    }
  }
}
