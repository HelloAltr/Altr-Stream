/// Represents a parameter in an OpenAPI operation (in path, query, or header)
class ApiParameter {
  final String name;
  final String inLocation; // 'path', 'query', 'header', 'cookie'
  final bool required;
  final String description;
  final String schemaType; // 'string', 'integer', 'boolean', 'array', 'object', etc.
  final dynamic defaultValue;
  final List<String> enumOptions;
  final Map<String, dynamic>? schema;

  const ApiParameter({
    required this.name,
    required this.inLocation,
    this.required = false,
    this.description = '',
    this.schemaType = 'string',
    this.defaultValue,
    this.enumOptions = const [],
    this.schema,
  });

  bool get isPath => inLocation == 'path';
  bool get isQuery => inLocation == 'query';
  bool get isHeader => inLocation == 'header';

  factory ApiParameter.fromJson(Map<String, dynamic> json, {Map<String, dynamic>? rootSchemas}) {
    final name = json['name']?.toString() ?? '';
    final inLoc = json['in']?.toString() ?? 'query';
    final isReq = json['required'] == true || inLoc == 'path';
    final desc = json['description']?.toString() ?? '';

    String type = 'string';
    dynamic defVal;
    List<String> enums = [];
    Map<String, dynamic>? schemaMap;

    if (json['schema'] is Map) {
      schemaMap = Map<String, dynamic>.from(json['schema'] as Map);
      type = schemaMap['type']?.toString() ?? 'string';
      defVal = schemaMap['default'];
      if (schemaMap['enum'] is List) {
        enums = (schemaMap['enum'] as List).map((e) => e.toString()).toList();
      }
    }

    return ApiParameter(
      name: name,
      inLocation: inLoc,
      required: isReq,
      description: desc,
      schemaType: type,
      defaultValue: defVal,
      enumOptions: enums,
      schema: schemaMap,
    );
  }
}

/// Represents the request body definition in an OpenAPI operation
class ApiRequestBody {
  final String contentType;
  final bool required;
  final String description;
  final Map<String, dynamic>? schema;
  final String sampleJson;

  const ApiRequestBody({
    this.contentType = 'application/json',
    this.required = false,
    this.description = '',
    this.schema,
    this.sampleJson = '{}',
  });

  factory ApiRequestBody.fromJson(
    Map<String, dynamic> json, {
    required String sampleJson,
  }) {
    final desc = json['description']?.toString() ?? '';
    final isReq = json['required'] == true;
    String cType = 'application/json';
    Map<String, dynamic>? schemaMap;

    if (json['content'] is Map) {
      final content = json['content'] as Map;
      if (content.containsKey('application/json')) {
        cType = 'application/json';
        final jsonContent = content['application/json'];
        if (jsonContent is Map && jsonContent['schema'] is Map) {
          schemaMap = Map<String, dynamic>.from(jsonContent['schema'] as Map);
        }
      } else if (content.isNotEmpty) {
        final firstKey = content.keys.first.toString();
        cType = firstKey;
        final firstContent = content[firstKey];
        if (firstContent is Map && firstContent['schema'] is Map) {
          schemaMap = Map<String, dynamic>.from(firstContent['schema'] as Map);
        }
      }
    }

    return ApiRequestBody(
      contentType: cType,
      required: isReq,
      description: desc,
      schema: schemaMap,
      sampleJson: sampleJson,
    );
  }
}

/// Represents a response definition for a status code in an OpenAPI operation
class ApiResponseDefinition {
  final String statusCode;
  final String description;
  final Map<String, dynamic>? schema;

  const ApiResponseDefinition({
    required this.statusCode,
    this.description = '',
    this.schema,
  });

  factory ApiResponseDefinition.fromJson(String statusCode, Map<String, dynamic> json) {
    Map<String, dynamic>? schemaMap;
    if (json['content'] is Map) {
      final content = json['content'] as Map;
      if (content.containsKey('application/json')) {
        final jsonContent = content['application/json'];
        if (jsonContent is Map && jsonContent['schema'] is Map) {
          schemaMap = Map<String, dynamic>.from(jsonContent['schema'] as Map);
        }
      }
    }
    return ApiResponseDefinition(
      statusCode: statusCode,
      description: json['description']?.toString() ?? '',
      schema: schemaMap,
    );
  }
}

/// Represents a single API Endpoint discovered dynamically from OpenAPI
class ApiEndpoint {
  final String path;
  final String method; // 'GET', 'POST', 'PUT', 'DELETE', 'PATCH', etc.
  final String summary;
  final String description;
  final List<String> tags;
  final String? operationId;
  final List<ApiParameter> parameters;
  final ApiRequestBody? requestBody;
  final Map<String, ApiResponseDefinition> responses;

  const ApiEndpoint({
    required this.path,
    required this.method,
    this.summary = '',
    this.description = '',
    this.tags = const [],
    this.operationId,
    this.parameters = const [],
    this.requestBody,
    this.responses = const {},
  });

  /// Primary tag for grouping (falls back to 'General' if no tag specified)
  String get primaryTag => tags.isNotEmpty ? tags.first : 'General';

  /// Path parameters
  List<ApiParameter> get pathParameters => parameters.where((p) => p.isPath).toList();

  /// Query parameters
  List<ApiParameter> get queryParameters => parameters.where((p) => p.isQuery).toList();

  /// Header parameters
  List<ApiParameter> get headerParameters => parameters.where((p) => p.isHeader).toList();

  /// Whether endpoint expects request body
  bool get hasRequestBody => requestBody != null && method != 'GET' && method != 'HEAD';

  /// Case-insensitive search across method, path, summary, description, tags, and parameter names
  bool matchesSearch(String query) {
    if (query.trim().isEmpty) return true;
    final q = query.trim().toLowerCase();

    // Check method
    if (method.toLowerCase().contains(q)) return true;

    // Check path
    if (path.toLowerCase().contains(q)) return true;

    // Check summary
    if (summary.toLowerCase().contains(q)) return true;

    // Check description
    if (description.toLowerCase().contains(q)) return true;

    // Check tags
    for (final tag in tags) {
      if (tag.toLowerCase().contains(q)) return true;
    }

    // Check parameter names and descriptions
    for (final p in parameters) {
      if (p.name.toLowerCase().contains(q) || p.description.toLowerCase().contains(q)) {
        return true;
      }
    }

    return false;
  }

  /// Whether this endpoint accepts a logical model ID (for Altr Stream smart selector)
  bool get isModelAware {
    if (parameters.any((p) => p.name == 'model_id' || p.name == 'modelId' || p.name == 'logical_model_id')) return true;
    if (path.contains('{model_id}') || path.contains('{modelId}') || path.contains('{logical_model_id}')) return true;
    if (requestBody != null && (requestBody!.sampleJson.contains('"model_id"') || requestBody!.sampleJson.contains('"logical_model_id"'))) return true;
    return false;
  }

  /// Whether this endpoint accepts a physical source ID (for Altr Stream smart selector)
  bool get isSourceAware {
    if (parameters.any((p) => p.name == 'source_id' || p.name == 'sourceId')) return true;
    if (path.contains('{source_id}') || path.contains('{sourceId}')) return true;
    if (requestBody != null && (requestBody!.sampleJson.contains('"source_id"') || requestBody!.sampleJson.contains('"sourceId"'))) return true;
    return false;
  }

  /// Whether this endpoint accepts a source mapping ID (for Altr Stream smart selector)
  bool get isMappingAware {
    if (parameters.any((p) => p.name == 'mapping_id' || p.name == 'mappingId')) return true;
    if (path.contains('{mapping_id}') || path.contains('{mappingId}')) return true;
    if (requestBody != null && (requestBody!.sampleJson.contains('"mapping_id"') || requestBody!.sampleJson.contains('"mappingId"'))) return true;
    return false;
  }
}

/// Container for the parsed OpenAPI specification data
class OpenApiSpecData {
  final String title;
  final String version;
  final String description;
  final List<ApiEndpoint> endpoints;
  final List<String> discoveredMethods;
  final List<String> discoveredTags;
  final Map<String, dynamic> rawSpec;

  const OpenApiSpecData({
    required this.title,
    required this.version,
    required this.description,
    required this.endpoints,
    required this.discoveredMethods,
    required this.discoveredTags,
    required this.rawSpec,
  });

  static const OpenApiSpecData empty = OpenApiSpecData(
    title: 'API Explorer',
    version: '1.0.0',
    description: '',
    endpoints: [],
    discoveredMethods: [],
    discoveredTags: [],
    rawSpec: {},
  );
}
