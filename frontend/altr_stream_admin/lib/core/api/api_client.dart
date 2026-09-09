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
    String? host,
    int? port,
    String? databaseName,
    String? username,
    String? password,
    String? filePath,
    bool testConnectionFirst = false,
  }) async {
    final payload = <String, dynamic>{
      'name': name,
      'type': type,
      'test_connection_first': testConnectionFirst,
    };
    if (host != null) payload['host'] = host;
    if (port != null) payload['port'] = port;
    if (databaseName != null) payload['database_name'] = databaseName;
    if (username != null) payload['username'] = username;
    if (password != null) payload['password'] = password;
    if (filePath != null) payload['file_path'] = filePath;

    final res = await _client.post(_uri('/sources'), headers: _headers, body: jsonEncode(payload));
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
    String? filePath,
  }) async {
    final payload = <String, dynamic>{};
    if (name != null) payload['name'] = name;
    if (host != null) payload['host'] = host;
    if (port != null) payload['port'] = port;
    if (databaseName != null) payload['database_name'] = databaseName;
    if (username != null) payload['username'] = username;
    if (password != null && password.isNotEmpty) payload['password'] = password;
    if (filePath != null) payload['file_path'] = filePath;

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
    String? host,
    int? port,
    String? databaseName,
    String? username,
    String? password,
    String? filePath,
  }) async {
    final payload = <String, dynamic>{
      'type': type,
    };
    if (host != null) payload['host'] = host;
    if (port != null) payload['port'] = port;
    if (databaseName != null) payload['database_name'] = databaseName;
    if (username != null) payload['username'] = username;
    if (password != null) payload['password'] = password;
    if (filePath != null) payload['file_path'] = filePath;

    final res = await _client.post(_uri('/sources/test'), headers: _headers, body: jsonEncode(payload));
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

  /// Execute a native query against a registered data source in the Query Playground
  Future<QueryExecuteResponseModel> executeQuery({
    required String sourceId,
    required String query,
  }) async {
    final body = jsonEncode({
      'source_id': sourceId,
      'query': query,
    });

    final res = await _client.post(
      _uri('/queries/execute'),
      headers: _headers,
      body: body,
    );
    return QueryExecuteResponseModel.fromJson(_processResponse(res) as Map<String, dynamic>);
  }

  /// Parse an AltrQL query text into a typed Abstract Syntax Tree (AltrQueryIR)
  Future<AltrQLParseResponseModel> parseAltrQL(String query) async {
    final body = jsonEncode({
      'query': query,
    });

    final res = await _client.post(
      _uri('/altrql/parse'),
      headers: _headers,
      body: body,
    );
    return AltrQLParseResponseModel.fromJson(_processResponse(res) as Map<String, dynamic>);
  }

  /// Bind a parsed AltrQL query against a registered data source's discovered schema snapshot
  Future<AltrQLBindResponseModel> bindAltrQL({
    required String query,
    required String sourceId,
  }) async {
    final body = jsonEncode({
      'query': query,
      'source_id': sourceId,
    });

    final res = await _client.post(
      _uri('/altrql/bind'),
      headers: _headers,
      body: body,
    );
    return AltrQLBindResponseModel.fromJson(_processResponse(res) as Map<String, dynamic>);
  }

  /// Execute an AltrQL query against a registered data source through the complete compiler and execution pipeline
  Future<AltrQLExecuteResponseModel> executeAltrQL({
    required String query,
    required String sourceId,
    bool confirmMassMutation = false,
  }) async {
    final body = jsonEncode({
      'query': query,
      'source_id': sourceId,
      'confirm_mass_mutation': confirmMassMutation,
    });

    final res = await _client.post(
      _uri('/altrql/execute'),
      headers: _headers,
      body: body,
    );
    return AltrQLExecuteResponseModel.fromJson(_processResponse(res) as Map<String, dynamic>);
  }
}


