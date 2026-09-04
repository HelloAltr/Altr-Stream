import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import 'models.dart';

class ApiException implements Exception {
  final int statusCode;
  final String message;
  final dynamic details;

  ApiException({
    required this.statusCode,
    required this.message,
    this.details,
  });

  @override
  String toString() => message;
}

class ApiClient {
  final String baseUrl;
  final http.Client _client;

  ApiClient({String? baseUrl, http.Client? client})
      : baseUrl = baseUrl ?? AppConfig.apiBaseUrl,
        _client = client ?? http.Client();

  Uri _uri(String path) {
    // Handle both relative URLs and absolute URLs
    if (baseUrl.startsWith('http://') || baseUrl.startsWith('https://')) {
      final normalizedBase = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
      return Uri.parse('$normalizedBase$path');
    }
    return Uri.parse('$baseUrl$path');
  }

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };

  dynamic _processResponse(http.Response response) {
    final status = response.statusCode;
    if (status >= 200 && status < 300) {
      if (response.body.isEmpty) return null;
      return jsonDecode(response.body);
    }

    String errorMsg = 'HTTP Error $status';
    dynamic details;
    try {
      if (response.body.isNotEmpty) {
        final bodyJson = jsonDecode(response.body);
        if (bodyJson is Map && bodyJson.containsKey('detail')) {
          errorMsg = bodyJson['detail'].toString();
          details = bodyJson;
        }
      }
    } catch (_) {
      errorMsg = response.body.isNotEmpty ? response.body : errorMsg;
    }

    throw ApiException(
      statusCode: status,
      message: errorMsg,
      details: details,
    );
  }

  /// Check backend health
  Future<Map<String, dynamic>> getHealth() async {
    final res = await _client.get(_uri('/health'), headers: _headers);
    return _processResponse(res) as Map<String, dynamic>;
  }

  /// List all registered data sources
  Future<List<SourceModel>> listSources() async {
    final res = await _client.get(_uri('/sources'), headers: _headers);
    final data = _processResponse(res) as List<dynamic>;
    return data.map((e) => SourceModel.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Get single source details
  Future<SourceModel> getSource(String id) async {
    final res = await _client.get(_uri('/sources/$id'), headers: _headers);
    return SourceModel.fromJson(_processResponse(res) as Map<String, dynamic>);
  }

  /// Register a new data source
  Future<SourceModel> createSource({
    required String name,
    required String type,
    required String host,
    required int port,
    required String databaseName,
    required String username,
    required String password,
    bool testConnectionFirst = false,
  }) async {
    final body = jsonEncode({
      'name': name,
      'type': type,
      'host': host,
      'port': port,
      'database_name': databaseName,
      'username': username,
      'password': password,
      'test_connection_first': testConnectionFirst,
    });

    final res = await _client.post(_uri('/sources'), headers: _headers, body: body);
    return SourceModel.fromJson(_processResponse(res) as Map<String, dynamic>);
  }

  /// Update an existing source
  Future<SourceModel> updateSource(
    String id, {
    String? name,
    String? host,
    int? port,
    String? databaseName,
    String? username,
    String? password,
  }) async {
    final payload = <String, dynamic>{};
    if (name != null) payload['name'] = name;
    if (host != null) payload['host'] = host;
    if (port != null) payload['port'] = port;
    if (databaseName != null) payload['database_name'] = databaseName;
    if (username != null) payload['username'] = username;
    if (password != null && password.isNotEmpty) payload['password'] = password;

    final res = await _client.put(
      _uri('/sources/$id'),
      headers: _headers,
      body: jsonEncode(payload),
    );
    return SourceModel.fromJson(_processResponse(res) as Map<String, dynamic>);
  }

  /// Delete a source
  Future<void> deleteSource(String id) async {
    final res = await _client.delete(_uri('/sources/$id'), headers: _headers);
    _processResponse(res);
  }

  /// Test ad-hoc connection parameters before saving
  Future<ConnectionTestResultModel> testAdhocConnection({
    required String type,
    required String host,
    required int port,
    required String databaseName,
    required String username,
    required String password,
  }) async {
    final body = jsonEncode({
      'type': type,
      'host': host,
      'port': port,
      'database_name': databaseName,
      'username': username,
      'password': password,
    });

    final res = await _client.post(_uri('/sources/test'), headers: _headers, body: body);
    return ConnectionTestResultModel.fromJson(_processResponse(res) as Map<String, dynamic>);
  }

  /// Test connection for an existing registered source
  Future<ConnectionTestResultModel> testSavedConnection(String id) async {
    final res = await _client.post(_uri('/sources/$id/test'), headers: _headers);
    return ConnectionTestResultModel.fromJson(_processResponse(res) as Map<String, dynamic>);
  }

  /// Get source connector capabilities
  Future<SourceCapabilitiesModel> getSourceCapabilities(String id) async {
    final res = await _client.get(_uri('/sources/$id/capabilities'), headers: _headers);
    return SourceCapabilitiesModel.fromJson(_processResponse(res) as Map<String, dynamic>);
  }

  /// Trigger schema discovery on a physical source
  Future<SourceSchemaModel> discoverSchema(String id) async {
    final res = await _client.post(_uri('/sources/$id/schema/discover'), headers: _headers);
    return SourceSchemaModel.fromJson(_processResponse(res) as Map<String, dynamic>);
  }

  /// Get the most recent discovered schema snapshot
  Future<SourceSchemaModel?> getLatestSchema(String id) async {
    try {
      final res = await _client.get(_uri('/sources/$id/schema'), headers: _headers);
      if (res.statusCode == 404) return null;
      return SourceSchemaModel.fromJson(_processResponse(res) as Map<String, dynamic>);
    } on ApiException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }
}
