import 'dart:convert';
import '../models/api_endpoint_model.dart';

/// Parses raw OpenAPI 3.0/3.1 JSON definitions into structured [OpenApiSpecData]
class OpenApiParser {
  /// Parse the root OpenAPI JSON map
  static OpenApiSpecData parse(Map<String, dynamic> spec) {
    final info = spec['info'] is Map ? spec['info'] as Map : {};
    final title = info['title']?.toString() ?? 'FastAPI Service';
    final version = info['version']?.toString() ?? 'v1.0.0';
    final description = info['description']?.toString() ?? '';

    final components = spec['components'] is Map ? spec['components'] as Map : {};
    final schemas = components['schemas'] is Map ? Map<String, dynamic>.from(components['schemas'] as Map) : <String, dynamic>{};

    final pathsMap = spec['paths'] is Map ? spec['paths'] as Map : {};
    final List<ApiEndpoint> endpoints = [];
    final Set<String> methodsFound = <String>{};
    final Set<String> tagsFound = <String>{};

    pathsMap.forEach((pathKey, pathItemRaw) {
      if (pathItemRaw is! Map) return;
      final pathItem = Map<String, dynamic>.from(pathItemRaw);
      final String path = pathKey.toString();

      // Common parameters at path level
      final List<ApiParameter> commonParams = [];
      if (pathItem['parameters'] is List) {
        for (final p in pathItem['parameters'] as List) {
          if (p is Map) {
            commonParams.add(ApiParameter.fromJson(Map<String, dynamic>.from(p), rootSchemas: schemas));
          }
        }
      }

      // Check all HTTP operations
      const validOps = ['get', 'post', 'put', 'delete', 'patch', 'head', 'options', 'trace'];
      pathItem.forEach((opKey, opValRaw) {
        final lowerOp = opKey.toLowerCase();
        if (!validOps.contains(lowerOp) || opValRaw is! Map) return;

        final opMap = Map<String, dynamic>.from(opValRaw);
        final String method = lowerOp.toUpperCase();
        methodsFound.add(method);

        final summary = opMap['summary']?.toString() ?? '';
        final desc = opMap['description']?.toString() ?? '';
        final operationId = opMap['operationId']?.toString();

        // Tags
        final List<String> tags = [];
        if (opMap['tags'] is List) {
          for (final t in opMap['tags'] as List) {
            final tagStr = t.toString().trim();
            if (tagStr.isNotEmpty) {
              tags.add(tagStr);
              tagsFound.add(tagStr);
            }
          }
        }
        if (tags.isEmpty) {
          tags.add('General');
          tagsFound.add('General');
        }

        // Operation parameters (merging with path common parameters)
        final List<ApiParameter> opParams = List.from(commonParams);
        if (opMap['parameters'] is List) {
          for (final p in opMap['parameters'] as List) {
            if (p is Map) {
              final parsedParam = ApiParameter.fromJson(Map<String, dynamic>.from(p), rootSchemas: schemas);
              // Avoid duplicate parameter names
              opParams.removeWhere((existing) => existing.name == parsedParam.name && existing.inLocation == parsedParam.inLocation);
              opParams.add(parsedParam);
            }
          }
        }

        // Request Body
        ApiRequestBody? requestBody;
        if (opMap['requestBody'] is Map) {
          final rbMap = Map<String, dynamic>.from(opMap['requestBody'] as Map);
          final sampleJson = _generateSampleRequestBody(rbMap, schemas);
          requestBody = ApiRequestBody.fromJson(rbMap, sampleJson: sampleJson);
        }

        // Responses
        final Map<String, ApiResponseDefinition> responses = {};
        if (opMap['responses'] is Map) {
          (opMap['responses'] as Map).forEach((statusCodeKey, respRaw) {
            if (respRaw is Map) {
              responses[statusCodeKey.toString()] = ApiResponseDefinition.fromJson(
                statusCodeKey.toString(),
                Map<String, dynamic>.from(respRaw),
              );
            }
          });
        }

        endpoints.add(ApiEndpoint(
          path: path,
          method: method,
          summary: summary,
          description: desc,
          tags: tags,
          operationId: operationId,
          parameters: opParams,
          requestBody: requestBody,
          responses: responses,
        ));
      });
    });

    // Sort endpoints logically by Tag then by Path then by Method
    endpoints.sort((a, b) {
      final tagCmp = a.primaryTag.compareTo(b.primaryTag);
      if (tagCmp != 0) return tagCmp;
      final pathCmp = a.path.compareTo(b.path);
      if (pathCmp != 0) return pathCmp;
      return _methodPriority(a.method).compareTo(_methodPriority(b.method));
    });

    // Order discovered methods logically
    final List<String> sortedMethods = _sortDiscoveredMethods(methodsFound);
    final List<String> sortedTags = tagsFound.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    return OpenApiSpecData(
      title: title,
      version: version,
      description: description,
      endpoints: endpoints,
      discoveredMethods: sortedMethods,
      discoveredTags: sortedTags,
      rawSpec: spec,
    );
  }

  static int _methodPriority(String method) {
    switch (method.toUpperCase()) {
      case 'GET':
        return 1;
      case 'POST':
        return 2;
      case 'PUT':
        return 3;
      case 'PATCH':
        return 4;
      case 'DELETE':
        return 5;
      case 'HEAD':
        return 6;
      case 'OPTIONS':
        return 7;
      default:
        return 10;
    }
  }

  static List<String> _sortDiscoveredMethods(Set<String> methods) {
    final list = methods.toList();
    list.sort((a, b) {
      final pa = _methodPriority(a);
      final pb = _methodPriority(b);
      if (pa != pb) return pa.compareTo(pb);
      return a.compareTo(b);
    });
    return list;
  }

  /// Generate formatted JSON template for a request body schema
  static String _generateSampleRequestBody(Map<String, dynamic> requestBodyJson, Map<String, dynamic> rootSchemas) {
    if (requestBodyJson['content'] is Map) {
      final content = requestBodyJson['content'] as Map;
      Map<String, dynamic>? targetSchema;

      if (content.containsKey('application/json')) {
        final jsonContent = content['application/json'];
        if (jsonContent is Map && jsonContent['schema'] is Map) {
          targetSchema = Map<String, dynamic>.from(jsonContent['schema'] as Map);
        }
      } else if (content.isNotEmpty) {
        final firstContent = content.values.first;
        if (firstContent is Map && firstContent['schema'] is Map) {
          targetSchema = Map<String, dynamic>.from(firstContent['schema'] as Map);
        }
      }

      if (targetSchema != null) {
        final sampleObject = _generateSampleFromSchema(targetSchema, rootSchemas, depth: 0);
        try {
          const encoder = JsonEncoder.withIndent('  ');
          return encoder.convert(sampleObject);
        } catch (_) {
          return '{}';
        }
      }
    }
    return '{}';
  }

  /// Recursively generate a sample Dart data object from OpenAPI schema
  static dynamic _generateSampleFromSchema(
    Map<String, dynamic> schema,
    Map<String, dynamic> rootSchemas, {
    int depth = 0,
  }) {
    if (depth > 8) return {}; // Guard against infinite circular schema refs

    // 1. Handle $ref resolution
    if (schema.containsKey('\$ref')) {
      final refStr = schema['\$ref'].toString();
      final resolved = _resolveRef(refStr, rootSchemas);
      if (resolved != null) {
        return _generateSampleFromSchema(resolved, rootSchemas, depth: depth + 1);
      }
      return {};
    }

    // 2. Schema-provided values take precedence where available: example, default, enum
    if (schema.containsKey('example') && schema['example'] != null) {
      return schema['example'];
    }
    if (schema.containsKey('default') && schema['default'] != null) {
      return schema['default'];
    }
    if (schema.containsKey('enum') && schema['enum'] is List && (schema['enum'] as List).isNotEmpty) {
      return (schema['enum'] as List).first;
    }

    // 3. Handle allOf
    if (schema.containsKey('allOf') && schema['allOf'] is List) {
      final mergedMap = <String, dynamic>{};
      for (final sub in schema['allOf'] as List) {
        if (sub is Map) {
          final sampleSub = _generateSampleFromSchema(Map<String, dynamic>.from(sub), rootSchemas, depth: depth + 1);
          if (sampleSub is Map) {
            mergedMap.addAll(Map<String, dynamic>.from(sampleSub));
          }
        }
      }
      return mergedMap;
    }

    // 4. Handle anyOf / oneOf (e.g. nullable types like str | None in OpenAPI 3.1)
    if (schema.containsKey('anyOf') && schema['anyOf'] is List) {
      final nonNullSubs = (schema['anyOf'] as List)
          .where((s) => s is Map && s['type']?.toString().toLowerCase() != 'null')
          .map((s) => Map<String, dynamic>.from(s as Map))
          .toList();
      if (nonNullSubs.isNotEmpty) {
        return _generateSampleFromSchema(nonNullSubs.first, rootSchemas, depth: depth + 1);
      }
    }
    if (schema.containsKey('oneOf') && schema['oneOf'] is List) {
      final nonNullSubs = (schema['oneOf'] as List)
          .where((s) => s is Map && s['type']?.toString().toLowerCase() != 'null')
          .map((s) => Map<String, dynamic>.from(s as Map))
          .toList();
      if (nonNullSubs.isNotEmpty) {
        return _generateSampleFromSchema(nonNullSubs.first, rootSchemas, depth: depth + 1);
      }
    }

    // 5. If properties are defined, it is an object
    if (schema.containsKey('properties') && schema['properties'] is Map) {
      final result = <String, dynamic>{};
      final props = schema['properties'] as Map;
      props.forEach((propKey, propValRaw) {
        if (propValRaw is Map) {
          final propSchema = Map<String, dynamic>.from(propValRaw);
          result[propKey.toString()] = _generateSampleFromSchema(propSchema, rootSchemas, depth: depth + 1);
        } else {
          result[propKey.toString()] = '';
        }
      });
      return result;
    }

    // 6. Explicit type dispatch
    final type = schema['type']?.toString().toLowerCase();

    switch (type) {
      case 'string':
        return '';

      case 'integer':
      case 'number':
        return 0;

      case 'boolean':
        return false;

      case 'array':
        if (schema['items'] is Map) {
          final itemSchema = Map<String, dynamic>.from(schema['items'] as Map);
          final itemSample = _generateSampleFromSchema(itemSchema, rootSchemas, depth: depth + 1);
          return [itemSample];
        }
        return [];

      case 'object':
        return {};

      default:
        // Default scalar fallback
        return '';
    }
  }

  static Map<String, dynamic>? _resolveRef(String ref, Map<String, dynamic> rootSchemas) {
    // Standard format: #/components/schemas/ModelName
    final prefix = '#/components/schemas/';
    if (ref.startsWith(prefix)) {
      final name = ref.substring(prefix.length);
      if (rootSchemas.containsKey(name) && rootSchemas[name] is Map) {
        return Map<String, dynamic>.from(rootSchemas[name] as Map);
      }
    }
    return null;
  }
}
