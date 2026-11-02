class AltrApiKey {
  final String id;
  final String name;
  final String keyPrefix;
  final String? fullKey; // Only exposed immediately upon generation
  final List<String> scopes;
  final DateTime? expiresAt;
  final DateTime createdAt;
  final DateTime? lastUsedAt;
  final bool isActive;

  AltrApiKey({
    required this.id,
    required this.name,
    required this.keyPrefix,
    this.fullKey,
    required this.scopes,
    this.expiresAt,
    required this.createdAt,
    this.lastUsedAt,
    this.isActive = true,
  });

  bool get isExpired =>
      expiresAt != null && DateTime.now().isAfter(expiresAt!);

  static DateTime? _parseUtcDateTime(dynamic value) {
    if (value == null) return null;
    final str = value.toString().trim();
    if (str.isEmpty || str == 'null') return null;
    DateTime? dt = DateTime.tryParse(str);
    if (dt == null) return null;
    // If backend serialized without timezone suffix (e.g. SQLite naive ISO "2026-11-02T04:09:22"),
    // interpret it as UTC and convert to local time for the client.
    if (!str.endsWith('Z') && !str.contains('+') && !RegExp(r'-\d{2}:\d{2}$').hasMatch(str)) {
      dt = DateTime.tryParse('${str}Z') ?? dt;
    }
    return dt.toLocal();
  }

  factory AltrApiKey.fromJson(Map<String, dynamic> json) {
    final rawKey = json['raw_key']?.toString() ?? json['key']?.toString();
    final prefix = json['key_prefix']?.toString() ??
        (rawKey != null && rawKey.length >= 14 ? rawKey.substring(0, 14) : '');

    return AltrApiKey(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      keyPrefix: prefix,
      fullKey: rawKey,
      scopes: List<String>.from(json['scopes'] ?? ['read']),
      expiresAt: _parseUtcDateTime(json['expires_at']),
      createdAt: _parseUtcDateTime(json['created_at']) ?? DateTime.now(),
      lastUsedAt: _parseUtcDateTime(json['last_used_at']),
      isActive: json['is_active'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'key_prefix': keyPrefix,
        'scopes': scopes,
        'expires_at': expiresAt?.toIso8601String(),
        'created_at': createdAt.toIso8601String(),
        'last_used_at': lastUsedAt?.toIso8601String(),
        'is_active': isActive,
      };
}
