class WorkspaceMember {
  final String email;
  final String displayName;
  final String role; // 'owner', 'admin', 'member'
  final DateTime? joinedAt;

  const WorkspaceMember({
    required this.email,
    required this.displayName,
    this.role = 'member',
    this.joinedAt,
  });

  factory WorkspaceMember.fromMap(Map<String, dynamic> map) {
    return WorkspaceMember(
      email: map['email']?.toString() ?? '',
      displayName: map['display_name']?.toString() ?? '',
      role: map['role']?.toString() ?? 'member',
      joinedAt: map['joined_at'] != null
          ? (map['joined_at'] is DateTime
              ? map['joined_at'] as DateTime
              : DateTime.tryParse(map['joined_at'].toString()))
          : null,
    );
  }

  Map<String, dynamic> toMap() => {
        'email': email,
        'display_name': displayName,
        'role': role,
        'joined_at': joinedAt?.toIso8601String(),
      };
}

/// Unified Workspace entity shared across Altr Mesh products.
class Workspace {
  final String id;
  final String name;
  final String ownerId;
  final List<String> memberUids;
  final List<String> adminUids;
  final List<String> enabledServices;
  final Map<String, WorkspaceMember> members;
  final DateTime? createdAt;

  const Workspace({
    required this.id,
    required this.name,
    required this.ownerId,
    required this.memberUids,
    this.adminUids = const [],
    this.enabledServices = const ['altr_stream'],
    this.members = const {},
    this.createdAt,
  });

  bool isServiceEnabled(String serviceName) =>
      enabledServices.contains(serviceName);

  bool isOwner(String uid) => ownerId == uid;
  bool isAdmin(String uid) => isOwner(uid) || adminUids.contains(uid);

  factory Workspace.fromFirestore(String docId, Map<String, dynamic> data) {
    final rawMembers = data['members'] as Map<String, dynamic>? ?? {};
    final parsedMembers = rawMembers.map(
      (key, val) => MapEntry(
        key,
        WorkspaceMember.fromMap(
          val is Map<String, dynamic> ? val : Map<String, dynamic>.from(val as Map),
        ),
      ),
    );

    return Workspace(
      id: docId,
      name: data['name']?.toString() ?? 'Unnamed Workspace',
      ownerId: data['owner_id']?.toString() ?? '',
      memberUids: List<String>.from(data['member_uids'] ?? []),
      adminUids: List<String>.from(data['admin_uids'] ?? []),
      enabledServices: List<String>.from(data['enabled_services'] ?? ['altr_stream']),
      members: parsedMembers,
      createdAt: data['created_at'] != null
          ? (data['created_at'] is DateTime
              ? data['created_at'] as DateTime
              : DateTime.tryParse(data['created_at'].toString()))
          : null,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'owner_id': ownerId,
      'member_uids': memberUids,
      'admin_uids': adminUids,
      'enabled_services': enabledServices,
      'members': members.map((key, val) => MapEntry(key, val.toMap())),
      'created_at': createdAt?.toIso8601String(),
    };
  }

  Workspace copyWith({
    String? name,
    List<String>? enabledServices,
    List<String>? memberUids,
    List<String>? adminUids,
    Map<String, WorkspaceMember>? members,
  }) {
    return Workspace(
      id: id,
      name: name ?? this.name,
      ownerId: ownerId,
      memberUids: memberUids ?? this.memberUids,
      adminUids: adminUids ?? this.adminUids,
      enabledServices: enabledServices ?? this.enabledServices,
      members: members ?? this.members,
      createdAt: createdAt,
    );
  }
}
