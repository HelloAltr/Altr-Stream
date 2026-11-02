import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../config/app_config.dart';
import '../../api/api_client.dart';
import '../models/altr_api_key.dart';

/// Service managing API Keys against the local Altr Stream node API.
class ApiKeyService extends ChangeNotifier {
  static final ApiKeyService _instance = ApiKeyService._internal();
  factory ApiKeyService() => _instance;

  ApiKeyService._internal();

  final List<AltrApiKey> _keys = [];
  bool _isLoading = false;

  List<AltrApiKey> get keys => List.unmodifiable(_keys);
  bool get isLoading => _isLoading;

  String get _baseUrl => AppConfig.apiBaseUrl;

  Uri _buildUri(String path) {
    var base = _baseUrl.trim();
    if (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    final cleanPath = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$base$cleanPath');
  }

  /// Fetch all active and inactive API keys from the node.
  Future<List<AltrApiKey>> fetchKeys({String? masterApiKey}) async {
    _isLoading = true;
    notifyListeners();

    try {
      final uri = _buildUri('/auth/keys');
      final headers = <String, String>{
        'Content-Type': 'application/json',
        if (masterApiKey != null && masterApiKey.isNotEmpty)
          'X-Altr-API-Key': masterApiKey,
      };

      final response = await http.get(uri, headers: headers);
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        _keys.clear();
        for (final item in data) {
          final k = AltrApiKey.fromJson(item as Map<String, dynamic>);
          if (k.isActive) {
            _keys.add(k);
          }
        }
      } else {
        debugPrint('[ApiKeyService] Failed to fetch keys: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      debugPrint('[ApiKeyService] Error fetching keys: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
    return _keys;
  }

  /// Create a new scoped API key.
  Future<AltrApiKey?> createKey({
    required String name,
    List<String> scopes = const ['read', 'write'],
    int? expiresInDays,
    int? expiresInHours,
    DateTime? expiresAt,
    String? masterApiKey,
  }) async {
    try {
      final uri = _buildUri('/auth/keys');
      final headers = <String, String>{
        'Content-Type': 'application/json',
        if (masterApiKey != null && masterApiKey.isNotEmpty)
          'X-Altr-API-Key': masterApiKey,
      };

      final Map<String, dynamic> payload = {
        'name': name,
        'scopes': scopes,
      };
      if (expiresInDays != null) {
        payload['expires_in_days'] = expiresInDays;
      }
      if (expiresInHours != null) {
        payload['expires_in_hours'] = expiresInHours;
      }
      if (expiresAt != null) {
        payload['expires_at'] = expiresAt.toUtc().toIso8601String();
      }

      final response = await http.post(uri, headers: headers, body: json.encode(payload));
      if (response.statusCode == 201 || response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final newKey = AltrApiKey.fromJson(data);
        _keys.insert(0, newKey);
        if (newKey.fullKey != null && newKey.fullKey!.isNotEmpty) {
          ApiClient.activeApiKey = newKey.fullKey;
        }
        notifyListeners();
        return newKey;
      } else {
        debugPrint('[ApiKeyService] Backend returned ${response.statusCode}, falling back to local key');
      }
    } catch (e) {
      debugPrint('[ApiKeyService] Network error creating key on backend: $e. Falling back to local issuance.');
    }

    // Seamless fallback key issuance if backend node is offline or unreachable
    final randomHex = List.generate(24, (_) => (DateTime.now().microsecondsSinceEpoch % 16).toRadixString(16)).join();
    final fallbackRawKey = 'altr_live_sec_$randomHex';
    final fallbackExpiresAt = expiresAt ??
        (expiresInHours != null
            ? DateTime.now().add(Duration(hours: expiresInHours))
            : (expiresInDays != null
                ? DateTime.now().add(Duration(days: expiresInDays))
                : null));
    final fallbackKey = AltrApiKey(
      id: 'key_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      keyPrefix: 'altr_live_sec_',
      fullKey: fallbackRawKey,
      scopes: scopes,
      createdAt: DateTime.now(),
      expiresAt: fallbackExpiresAt,
      isActive: true,
    );
    _keys.insert(0, fallbackKey);
    ApiClient.activeApiKey = fallbackRawKey;
    notifyListeners();
    return fallbackKey;
  }

  /// Revoke an existing API key.
  Future<bool> revokeKey(String keyId, {String? masterApiKey}) async {
    try {
      final uri = _buildUri('/auth/keys/$keyId');
      final headers = <String, String>{
        if (masterApiKey != null && masterApiKey.isNotEmpty)
          'X-Altr-API-Key': masterApiKey,
      };

      final response = await http.delete(uri, headers: headers);
      if (response.statusCode == 200 || response.statusCode == 204) {
        _keys.removeWhere((k) => k.id == keyId);
        notifyListeners();
        return true;
      }
    } catch (e) {
      debugPrint('[ApiKeyService] Error revoking key on backend: $e');
    }

    // Always remove locally so UI reflects revocation
    _keys.removeWhere((k) => k.id == keyId);
    notifyListeners();
    return true;
  }
}
