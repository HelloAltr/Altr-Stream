import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/workspace.dart';

/// Service managing Altr Mesh workspaces and service delegations in Firestore.
class WorkspaceService extends ChangeNotifier {
  static final WorkspaceService _instance = WorkspaceService._internal();
  factory WorkspaceService() => _instance;

  WorkspaceService._internal();

  FirebaseFirestore? get _firestore {
    try {
      return FirebaseFirestore.instance;
    } catch (e) {
      return null;
    }
  }

  List<Workspace> _workspaces = [];
  Workspace? _activeWorkspace;
  bool _isLoading = false;

  List<Workspace> get workspaces => List.unmodifiable(_workspaces);
  Workspace? get activeWorkspace => _activeWorkspace;
  bool get isLoading => _isLoading;

  /// Fetch workspaces for the specified user ID or workspace IDs.
  Future<void> fetchUserWorkspaces(String uid, {List<String>? workspaceIds}) async {
    final fs = _firestore;
    if (fs == null) {
      return;
    }

    _isLoading = true;
    notifyListeners();

    try {
      final List<Workspace> loaded = [];

      // Query by member_uids array containing user ID
      final querySnapshot = await fs
          .collection('workspaces')
          .where('member_uids', arrayContains: uid)
          .get();

      for (final doc in querySnapshot.docs) {
        loaded.add(Workspace.fromFirestore(doc.id, doc.data()));
      }

      // Also ensure any IDs listed in profile are fetched if not yet caught
      if (workspaceIds != null && workspaceIds.isNotEmpty) {
        for (final id in workspaceIds) {
          if (!loaded.any((w) => w.id == id)) {
            final doc = await fs.collection('workspaces').doc(id).get();
            if (doc.exists && doc.data() != null) {
              loaded.add(Workspace.fromFirestore(doc.id, doc.data()!));
            }
          }
        }
      }

      _workspaces = loaded;
      if (_workspaces.isNotEmpty) {
        if (_activeWorkspace == null || !_workspaces.any((w) => w.id == _activeWorkspace!.id)) {
          _activeWorkspace = _workspaces.first;
        } else {
          // Refresh active workspace instance
          _activeWorkspace = _workspaces.firstWhere((w) => w.id == _activeWorkspace!.id);
        }
      } else {
        _activeWorkspace = null;
      }
    } catch (e) {
      debugPrint('[WorkspaceService] Error fetching workspaces: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Switch the active workspace.
  void setActiveWorkspace(Workspace workspace) {
    if (_activeWorkspace?.id != workspace.id) {
      _activeWorkspace = workspace;
      notifyListeners();
    }
  }

  /// Create a new workspace.
  Future<Workspace?> createWorkspace({
    required String name,
    required String ownerUid,
    required String ownerEmail,
    required String ownerDisplayName,
    List<String> enabledServices = const ['altr_stream'],
  }) async {
    final fs = _firestore;
    if (fs == null) return null;

    try {
      final docRef = fs.collection('workspaces').doc();
      final now = DateTime.now();

      final workspace = Workspace(
        id: docRef.id,
        name: name,
        ownerId: ownerUid,
        memberUids: [ownerUid],
        adminUids: [ownerUid],
        enabledServices: enabledServices.contains('altr_stream')
            ? enabledServices
            : [...enabledServices, 'altr_stream'],
        members: {
          ownerUid: WorkspaceMember(
            email: ownerEmail,
            displayName: ownerDisplayName,
            role: 'owner',
            joinedAt: now,
          ),
        },
        createdAt: now,
      );

      await docRef.set(workspace.toFirestore());

      // Update user's profile with the new workspace ID
      final userDoc = fs.collection('users').doc(ownerUid);
      await userDoc.set({
        'workspace_ids': FieldValue.arrayUnion([docRef.id]),
        'default_workspace_id': docRef.id,
      }, SetOptions(merge: true));

      _workspaces.add(workspace);
      _activeWorkspace = workspace;
      notifyListeners();
      return workspace;
    } catch (e) {
      debugPrint('[WorkspaceService] Error creating workspace: $e');
      return null;
    }
  }

  /// Enable an additional Altr Mesh service for the active workspace.
  /// Note: Once enabled, services cannot be turned off.
  Future<bool> enableService(String workspaceId, String serviceName) async {
    final fs = _firestore;
    if (fs == null) return false;

    final index = _workspaces.indexWhere((w) => w.id == workspaceId);
    if (index == -1) return false;

    final current = _workspaces[index];
    if (current.enabledServices.contains(serviceName)) return true;

    final updatedServices = List<String>.from(current.enabledServices)..add(serviceName);

    try {
      await fs.collection('workspaces').doc(workspaceId).update({
        'enabled_services': updatedServices,
      });

      final updated = current.copyWith(enabledServices: updatedServices);
      _workspaces[index] = updated;
      if (_activeWorkspace?.id == workspaceId) {
        _activeWorkspace = updated;
      }
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('[WorkspaceService] Error enabling service $serviceName: $e');
      return false;
    }
  }

  /// Add a member to a workspace.
  Future<bool> addMember({
    required String workspaceId,
    required String memberUid,
    required String memberEmail,
    required String memberDisplayName,
    String role = 'member',
  }) async {
    final fs = _firestore;
    if (fs == null) return false;

    try {
      final newMember = WorkspaceMember(
        email: memberEmail,
        displayName: memberDisplayName,
        role: role,
        joinedAt: DateTime.now(),
      );

      await fs.collection('workspaces').doc(workspaceId).update({
        'member_uids': FieldValue.arrayUnion([memberUid]),
        if (role == 'admin') 'admin_uids': FieldValue.arrayUnion([memberUid]),
        'members.$memberUid': newMember.toMap(),
      });

      // Update member's user profile
      await fs.collection('users').doc(memberUid).set({
        'workspace_ids': FieldValue.arrayUnion([workspaceId]),
      }, SetOptions(merge: true));

      return true;
    } catch (e) {
      debugPrint('[WorkspaceService] Error adding member: $e');
      return false;
    }
  }
}
