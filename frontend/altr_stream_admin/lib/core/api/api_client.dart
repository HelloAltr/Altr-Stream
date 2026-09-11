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
    String? mappingId,
    String? logicalModelId,
  }) async {
    final body = jsonEncode({
      'query': query,
      'source_id': sourceId,
      if (mappingId != null && mappingId.isNotEmpty) 'mapping_id': mappingId,
      if (logicalModelId != null && logicalModelId.isNotEmpty) 'logical_model_id': logicalModelId,
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
    String? mappingId,
    String? logicalModelId,
    bool confirmMassMutation = false,
  }) async {
    final body = jsonEncode({
      'query': query,
      'source_id': sourceId,
      if (mappingId != null && mappingId.isNotEmpty) 'mapping_id': mappingId,
      if (logicalModelId != null && logicalModelId.isNotEmpty) 'logical_model_id': logicalModelId,
      'confirm_mass_mutation': confirmMassMutation,
    });

    final res = await _client.post(
      _uri('/altrql/execute'),
      headers: _headers,
      body: body,
    );
    return AltrQLExecuteResponseModel.fromJson(_processResponse(res) as Map<String, dynamic>);
  }

  // =========================================================================
  // Schema & Mapping Registry APIs (v0.7.0)
  // =========================================================================

  /// Fetch registry summary metrics
  Future<RegistrySummaryModel> getRegistrySummary() async {
    final res = await _client.get(_uri('/registry/summary'), headers: _headers);
    return RegistrySummaryModel.fromJson(_processResponse(res) as Map<String, dynamic>);
  }

  /// List all logical data models
  Future<List<LogicalModelModel>> listLogicalModels() async {
    final res = await _client.get(_uri('/registry/models'), headers: _headers);
    final data = _processResponse(res) as List<dynamic>;
    return data.map((e) => LogicalModelModel.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Get single logical data model with its entities and fields
  Future<LogicalModelModel> getLogicalModel(String modelId) async {
    final res = await _client.get(_uri('/registry/models/$modelId'), headers: _headers);
    return LogicalModelModel.fromJson(_processResponse(res) as Map<String, dynamic>);
  }

  /// Create a new logical data model
  Future<LogicalModelModel> createLogicalModel({
    required String name,
    String version = '1.0.0',
    String? description,
    List<Map<String, dynamic>> entities = const [],
    Map<String, dynamic> metadata = const {},
  }) async {
    final body = jsonEncode({
      'name': name,
      'version': version,
      'description': description,
      'entities': entities,
      'metadata': metadata,
    });

    final res = await _client.post(
      _uri('/registry/models'),
      headers: _headers,
      body: body,
    );
    return LogicalModelModel.fromJson(_processResponse(res) as Map<String, dynamic>);
  }

  /// Update an existing logical data model
  Future<LogicalModelModel> updateLogicalModel({
    required String modelId,
    String? name,
    String? version,
    String? description,
    Map<String, dynamic>? metadata,
  }) async {
    final Map<String, dynamic> payload = {};
    if (name != null) payload['name'] = name;
    if (version != null) payload['version'] = version;
    if (description != null) payload['description'] = description;
    if (metadata != null) payload['metadata'] = metadata;

    final res = await _client.put(
      _uri('/registry/models/$modelId'),
      headers: _headers,
      body: jsonEncode(payload),
    );
    return LogicalModelModel.fromJson(_processResponse(res) as Map<String, dynamic>);
  }

  /// Delete a logical data model
  Future<void> deleteLogicalModel(String modelId) async {
    final res = await _client.delete(_uri('/registry/models/$modelId'), headers: _headers);
    _processResponse(res);
  }

  /// Add a logical entity to a model
  Future<LogicalEntityModel> createLogicalEntity({
    required String modelId,
    required String name,
    String? description,
    List<Map<String, dynamic>> fields = const [],
    Map<String, dynamic> metadata = const {},
  }) async {
    final body = jsonEncode({
      'name': name,
      'description': description,
      'fields': fields,
      'metadata': metadata,
    });

    final res = await _client.post(
      _uri('/registry/models/$modelId/entities'),
      headers: _headers,
      body: body,
    );
    return LogicalEntityModel.fromJson(_processResponse(res) as Map<String, dynamic>);
  }

  /// Update an existing logical entity
  Future<LogicalEntityModel> updateLogicalEntity({
    required String entityId,
    String? name,
    String? description,
  }) async {
    final Map<String, dynamic> payload = {};
    if (name != null) payload['name'] = name;
    if (description != null) payload['description'] = description;

    final res = await _client.put(
      _uri('/registry/entities/$entityId'),
      headers: _headers,
      body: jsonEncode(payload),
    );
    return LogicalEntityModel.fromJson(_processResponse(res) as Map<String, dynamic>);
  }

  /// Delete a logical entity
  Future<void> deleteLogicalEntity(String entityId) async {
    final res = await _client.delete(_uri('/registry/entities/$entityId'), headers: _headers);
    _processResponse(res);
  }

  /// Add a logical field to an entity
  Future<LogicalFieldModel> createLogicalField({
    required String entityId,
    required String name,
    required String dataType,
    bool nullable = true,
    bool isPrimaryKey = false,
    String? description,
    Map<String, dynamic> metadata = const {},
  }) async {
    final body = jsonEncode({
      'name': name,
      'data_type': dataType,
      'nullable': nullable,
      'is_primary_key': isPrimaryKey,
      'description': description,
      'metadata': metadata,
    });

    final res = await _client.post(
      _uri('/registry/entities/$entityId/fields'),
      headers: _headers,
      body: body,
    );
    return LogicalFieldModel.fromJson(_processResponse(res) as Map<String, dynamic>);
  }

  /// Update an existing logical field
  Future<LogicalFieldModel> updateLogicalField({
    required String fieldId,
    String? name,
    String? dataType,
    bool? isPrimaryKey,
    bool? nullable,
    String? description,
  }) async {
    final Map<String, dynamic> payload = {};
    if (name != null) payload['name'] = name;
    if (dataType != null) payload['data_type'] = dataType;
    if (isPrimaryKey != null) payload['is_primary_key'] = isPrimaryKey;
    if (nullable != null) payload['nullable'] = nullable;
    if (description != null) payload['description'] = description;

    final res = await _client.put(
      _uri('/registry/fields/$fieldId'),
      headers: _headers,
      body: jsonEncode(payload),
    );
    return LogicalFieldModel.fromJson(_processResponse(res) as Map<String, dynamic>);
  }

  /// Delete a logical field
  Future<void> deleteLogicalField(String fieldId) async {
    final res = await _client.delete(_uri('/registry/fields/$fieldId'), headers: _headers);
    _processResponse(res);
  }

  /// List source mappings
  Future<List<SourceMappingModel>> listSourceMappings({
    String? modelId,
    String? sourceId,
    String? status,
  }) async {
    final queryParams = <String, String>{};
    if (modelId != null && modelId.isNotEmpty) queryParams['model_id'] = modelId;
    if (sourceId != null && sourceId.isNotEmpty) queryParams['source_id'] = sourceId;
    if (status != null && status.isNotEmpty) queryParams['status'] = status;

    var path = '/registry/mappings';
    if (queryParams.isNotEmpty) {
      final queryStr = queryParams.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&');
      path = '$path?$queryStr';
    }

    final res = await _client.get(_uri(path), headers: _headers);
    final raw = _processResponse(res);
    if (raw is List) {
      return raw.map((e) => SourceMappingModel.fromJson(Map<String, dynamic>.from(e as Map))).toList();
    }
    return [];
  }

  /// Get single source mapping with its entity and field mappings
  Future<SourceMappingModel> getSourceMapping(String mappingId) async {
    final res = await _client.get(_uri('/registry/mappings/$mappingId'), headers: _headers);
    final raw = _processResponse(res);
    if (raw is Map) {
      return SourceMappingModel.fromJson(Map<String, dynamic>.from(raw));
    }
    throw ApiException(statusCode: res.statusCode, message: 'Invalid mapping response format');
  }

  /// Create a new source mapping
  Future<SourceMappingModel> createSourceMapping({
    required String logicalModelId,
    required String sourceId,
    String version = '1.0.0',
    String provenance = 'USER',
    List<Map<String, dynamic>> entityMappings = const [],
    Map<String, dynamic> metadata = const {},
  }) async {
    final body = jsonEncode({
      'logical_model_id': logicalModelId,
      'source_id': sourceId,
      'version': version,
      'provenance': provenance,
      'entity_mappings': entityMappings,
      'metadata': metadata,
    });

    final res = await _client.post(
      _uri('/registry/mappings'),
      headers: _headers,
      body: body,
    );
    final raw = _processResponse(res);
    if (raw is Map) {
      return SourceMappingModel.fromJson(Map<String, dynamic>.from(raw));
    }
    throw ApiException(statusCode: res.statusCode, message: 'Invalid mapping creation response');
  }

  /// Update an existing source mapping
  Future<SourceMappingModel> updateSourceMapping(
    String mappingId, {
    String? version,
    String? status,
    String? provenance,
    String? errorMessage,
    List<Map<String, dynamic>>? entityMappings,
  }) async {
    final payload = <String, dynamic>{};
    if (version != null) payload['version'] = version;
    if (status != null) payload['status'] = status;
    if (provenance != null) payload['provenance'] = provenance;
    if (errorMessage != null) payload['error_message'] = errorMessage;
    if (entityMappings != null) payload['entity_mappings'] = entityMappings;

    final res = await _client.put(
      _uri('/registry/mappings/$mappingId'),
      headers: _headers,
      body: jsonEncode(payload),
    );
    final raw = _processResponse(res);
    if (raw is Map) {
      return SourceMappingModel.fromJson(Map<String, dynamic>.from(raw));
    }
    throw ApiException(statusCode: res.statusCode, message: 'Invalid mapping update response');
  }

  /// Validate a source mapping against source physical schema
  Future<SourceMappingModel> validateSourceMapping(String mappingId) async {
    final res = await _client.post(
      _uri('/registry/mappings/$mappingId/validate'),
      headers: _headers,
    );
    final raw = _processResponse(res);
    if (raw is Map) {
      final json = Map<String, dynamic>.from(raw);
      if (json.containsKey('mapping') && json['mapping'] is Map) {
        final mappingMap = Map<String, dynamic>.from(json['mapping'] as Map);
        if (json['error'] != null && json['error'].toString().isNotEmpty && mappingMap['error_message'] == null) {
          mappingMap['error_message'] = json['error'].toString();
        }
        return SourceMappingModel.fromJson(mappingMap);
      }
      return SourceMappingModel.fromJson(json);
    }
    throw ApiException(statusCode: res.statusCode, message: 'Invalid validation response format');
  }

  /// Activate a source mapping
  Future<SourceMappingModel> activateSourceMapping(String mappingId) async {
    final res = await _client.post(
      _uri('/registry/mappings/$mappingId/activate'),
      headers: _headers,
    );
    final raw = _processResponse(res);
    if (raw is Map) {
      final json = Map<String, dynamic>.from(raw);
      if (json.containsKey('mapping') && json['mapping'] is Map) {
        return SourceMappingModel.fromJson(Map<String, dynamic>.from(json['mapping'] as Map));
      }
      return SourceMappingModel.fromJson(json);
    }
    throw ApiException(statusCode: res.statusCode, message: 'Invalid activation response format');
  }

  /// Delete a source mapping
  Future<void> deleteSourceMapping(String mappingId) async {
    final res = await _client.delete(_uri('/registry/mappings/$mappingId'), headers: _headers);
    _processResponse(res);
  }
}


