class SourceModel {
  final String id;
  final String name;
  final String type;
  final String host;
  final int port;
  final String databaseName;
  final String username;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String passwordMasked;

  SourceModel({
    required this.id,
    required this.name,
    required this.type,
    required this.host,
    required this.port,
    required this.databaseName,
    required this.username,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.passwordMasked = '••••••••',
  });

  factory SourceModel.fromJson(Map<String, dynamic> json) {
    return SourceModel(
      id: json['id'] as String,
      name: json['name'] as String,
      type: json['type'] as String,
      host: json['host'] as String,
      port: (json['port'] as num).toInt(),
      databaseName: json['database_name'] as String,
      username: json['username'] as String,
      status: (json['status'] as String?) ?? 'UNKNOWN',
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      passwordMasked: (json['password_masked'] as String?) ?? '••••••••',
    );
  }

  bool get isActive => status.toUpperCase() == 'ACTIVE';
  bool get isUnreachable => status.toUpperCase() == 'UNREACHABLE';
  bool get isError => status.toUpperCase() == 'ERROR';
}

class ConnectionTestResultModel {
  final bool success;
  final String message;
  final double? latencyMs;
  final String? serverVersion;
  final String? errorDetails;

  ConnectionTestResultModel({
    required this.success,
    required this.message,
    this.latencyMs,
    this.serverVersion,
    this.errorDetails,
  });

  factory ConnectionTestResultModel.fromJson(Map<String, dynamic> json) {
    return ConnectionTestResultModel(
      success: json['success'] as bool,
      message: json['message'] as String,
      latencyMs: (json['latency_ms'] as num?)?.toDouble(),
      serverVersion: json['server_version'] as String?,
      errorDetails: json['error_details'] as String?,
    );
  }
}

class SourceCapabilitiesModel {
  final bool schemaDiscovery;
  final bool read;
  final bool write;
  final bool cdc;
  final bool customQuery;
  final List<String> supportedOperations;

  SourceCapabilitiesModel({
    required this.schemaDiscovery,
    required this.read,
    required this.write,
    required this.cdc,
    this.customQuery = false,
    required this.supportedOperations,
  });

  factory SourceCapabilitiesModel.fromJson(Map<String, dynamic> json) {
    return SourceCapabilitiesModel(
      schemaDiscovery: json['schema_discovery'] as bool? ?? true,
      read: json['read'] as bool? ?? true,
      write: json['write'] as bool? ?? true,
      cdc: json['cdc'] as bool? ?? false,
      customQuery: json['custom_query'] as bool? ?? false,
      supportedOperations: (json['supported_operations'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
    );
  }
}

class FieldSchemaModel {
  final String name;
  final String dataType;
  final String nativeDataType;
  final bool nullable;
  final bool isPrimaryKey;
  final String? defaultValue;
  final int position;

  FieldSchemaModel({
    required this.name,
    required this.dataType,
    required this.nativeDataType,
    required this.nullable,
    required this.isPrimaryKey,
    this.defaultValue,
    required this.position,
  });

  factory FieldSchemaModel.fromJson(Map<String, dynamic> json) {
    return FieldSchemaModel(
      name: json['name'] as String,
      dataType: json['data_type'] as String,
      nativeDataType: json['native_data_type'] as String,
      nullable: json['nullable'] as bool? ?? true,
      isPrimaryKey: json['is_primary_key'] as bool? ?? false,
      defaultValue: json['default_value'] as String?,
      position: (json['position'] as num?)?.toInt() ?? 0,
    );
  }
}

class ConstraintSchemaModel {
  final String name;
  final String constraintType;
  final List<String> fields;
  final String? referencedEntity;
  final List<String> referencedFields;

  ConstraintSchemaModel({
    required this.name,
    required this.constraintType,
    required this.fields,
    this.referencedEntity,
    required this.referencedFields,
  });

  factory ConstraintSchemaModel.fromJson(Map<String, dynamic> json) {
    return ConstraintSchemaModel(
      name: json['name'] as String,
      constraintType: json['constraint_type'] as String,
      fields: (json['fields'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      referencedEntity: json['referenced_entity'] as String?,
      referencedFields:
          (json['referenced_fields'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
    );
  }
}

class EntitySchemaModel {
  final String name;
  final String namespace;
  final String entityType;
  final List<FieldSchemaModel> fields;
  final List<String> primaryKey;
  final List<ConstraintSchemaModel> constraints;

  EntitySchemaModel({
    required this.name,
    required this.namespace,
    required this.entityType,
    required this.fields,
    required this.primaryKey,
    required this.constraints,
  });

  factory EntitySchemaModel.fromJson(Map<String, dynamic> json) {
    return EntitySchemaModel(
      name: json['name'] as String,
      namespace: json['namespace'] as String? ?? 'public',
      entityType: json['entity_type'] as String? ?? 'TABLE',
      fields: (json['fields'] as List<dynamic>?)
              ?.map((e) => FieldSchemaModel.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      primaryKey:
          (json['primary_key'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      constraints: (json['constraints'] as List<dynamic>?)
              ?.map((e) => ConstraintSchemaModel.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  int get fieldCount => fields.length;
}

class SourceSchemaModel {
  final String sourceId;
  final String sourceName;
  final String version;
  final DateTime discoveredAt;
  final List<EntitySchemaModel> entities;
  final Map<String, dynamic> metadata;

  SourceSchemaModel({
    required this.sourceId,
    required this.sourceName,
    required this.version,
    required this.discoveredAt,
    required this.entities,
    required this.metadata,
  });

  factory SourceSchemaModel.fromJson(Map<String, dynamic> json) {
    return SourceSchemaModel(
      sourceId: json['source_id'] as String,
      sourceName: json['source_name'] as String,
      version: json['version'] as String? ?? '1.0.0',
      discoveredAt: DateTime.parse(json['discovered_at'] as String),
      entities: (json['entities'] as List<dynamic>?)
              ?.map((e) => EntitySchemaModel.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      metadata: (json['metadata'] as Map<String, dynamic>?) ?? {},
    );
  }

  int get entityCount => entities.length;
  int get totalFieldCount => entities.fold<int>(0, (prev, e) => prev + e.fields.length);
}

enum ActivityType {
  nodeStart,
  sourceRegistered,
  sourceUpdated,
  sourceDeleted,
  connectionTested,
  schemaDiscovered,
  healthCheck,
}

class ActivityLogModel {
  final String id;
  final ActivityType type;
  final String title;
  final String description;
  final DateTime timestamp;
  final bool isSuccess;
  final String? sourceId;
  final String? sourceName;

  ActivityLogModel({
    required this.id,
    required this.type,
    required this.title,
    required this.description,
    required this.timestamp,
    this.isSuccess = true,
    this.sourceId,
    this.sourceName,
  });
}

class QueryMetadataModel {
  final int rowCount;
  final int? affectedRows;
  final String? message;
  final double executionTimeMs;
  final String? operation;
  final String? mutationScope;

  QueryMetadataModel({
    required this.rowCount,
    this.affectedRows,
    this.message,
    required this.executionTimeMs,
    this.operation,
    this.mutationScope,
  });

  factory QueryMetadataModel.fromJson(Map<String, dynamic> json) {
    return QueryMetadataModel(
      rowCount: (json['row_count'] as num?)?.toInt() ?? 0,
      affectedRows: (json['affected_rows'] as num?)?.toInt(),
      message: json['message'] as String?,
      executionTimeMs: (json['execution_time_ms'] as num?)?.toDouble() ?? 0.0,
      operation: json['operation'] as String?,
      mutationScope: json['mutation_scope'] as String?,
    );
  }
}

class MutationClassificationModel {
  final String operation;
  final String mutationScope;
  final bool requiresConfirmation;
  final String entity;
  final String description;

  MutationClassificationModel({
    required this.operation,
    required this.mutationScope,
    required this.requiresConfirmation,
    required this.entity,
    required this.description,
  });

  factory MutationClassificationModel.fromJson(Map<String, dynamic> json) {
    return MutationClassificationModel(
      operation: json['operation'] as String? ?? 'READ',
      mutationScope: json['mutation_scope'] as String? ?? 'NOT_APPLICABLE',
      requiresConfirmation: json['requires_confirmation'] as bool? ?? false,
      entity: json['entity'] as String? ?? '',
      description: json['description'] as String? ?? '',
    );
  }
}

class QueryExecuteResponseModel {
  final bool success;
  final List<String> columns;
  final List<Map<String, dynamic>> rows;
  final QueryMetadataModel metadata;

  QueryExecuteResponseModel({
    required this.success,
    required this.columns,
    required this.rows,
    required this.metadata,
  });

  factory QueryExecuteResponseModel.fromJson(Map<String, dynamic> json) {
    final rawColumns = (json['columns'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
    final rawRows = (json['rows'] as List<dynamic>?)
            ?.map((e) => Map<String, dynamic>.from(e as Map))
            .toList() ??
        [];
    return QueryExecuteResponseModel(
      success: json['success'] as bool? ?? true,
      columns: rawColumns,
      rows: rawRows,
      metadata: QueryMetadataModel.fromJson(json['metadata'] as Map<String, dynamic>? ?? {}),
    );
  }

  bool get isResultSet => columns.isNotEmpty;
  bool get isCommandOutcome => columns.isEmpty;
}

class AltrQLErrorDetailModel {
  final String type;
  final String message;
  final int? line;
  final int? column;

  AltrQLErrorDetailModel({
    required this.type,
    required this.message,
    this.line,
    this.column,
  });

  factory AltrQLErrorDetailModel.fromJson(Map<String, dynamic> json) {
    return AltrQLErrorDetailModel(
      type: json['type'] as String? ?? 'AltrQueryError',
      message: json['message'] as String? ?? 'Unknown query error',
      line: (json['line'] as num?)?.toInt(),
      column: (json['column'] as num?)?.toInt(),
    );
  }

  String get locationDescription {
    if (line != null && column != null) {
      return 'Line $line · Column $column';
    } else if (line != null) {
      return 'Line $line';
    }
    return '';
  }
}

typedef AltrQLParseErrorModel = AltrQLErrorDetailModel;

class AltrQLParseResponseModel {
  final bool success;
  final Map<String, dynamic>? ir;
  final AltrQLErrorDetailModel? error;

  AltrQLParseResponseModel({
    required this.success,
    this.ir,
    this.error,
  });

  factory AltrQLParseResponseModel.fromJson(Map<String, dynamic> json) {
    return AltrQLParseResponseModel(
      success: json['success'] as bool? ?? false,
      ir: json['ir'] as Map<String, dynamic>?,
      error: json['error'] != null
          ? AltrQLErrorDetailModel.fromJson(json['error'] as Map<String, dynamic>)
          : null,
    );
  }
}

class AltrQLBindResponseModel {
  final bool success;
  final Map<String, dynamic>? ir;
  final Map<String, dynamic>? boundIr;
  final MutationClassificationModel? classification;
  final AltrQLErrorDetailModel? error;

  AltrQLBindResponseModel({
    required this.success,
    this.ir,
    this.boundIr,
    this.classification,
    this.error,
  });

  factory AltrQLBindResponseModel.fromJson(Map<String, dynamic> json) {
    return AltrQLBindResponseModel(
      success: json['success'] as bool? ?? false,
      ir: json['ir'] as Map<String, dynamic>?,
      boundIr: json['bound_ir'] as Map<String, dynamic>?,
      classification: json['classification'] != null
          ? MutationClassificationModel.fromJson(json['classification'] as Map<String, dynamic>)
          : null,
      error: json['error'] != null
          ? AltrQLErrorDetailModel.fromJson(json['error'] as Map<String, dynamic>)
          : null,
    );
  }
}

class PhysicalQueryModel {
  final String dialect;
  final String query;
  final List<dynamic> parameters;
  final String sourceId;
  final String sourceName;

  PhysicalQueryModel({
    required this.dialect,
    required this.query,
    required this.parameters,
    required this.sourceId,
    required this.sourceName,
  });

  factory PhysicalQueryModel.fromJson(Map<String, dynamic> json) {
    return PhysicalQueryModel(
      dialect: json['dialect'] as String? ?? 'unknown',
      query: json['query'] as String? ?? '',
      parameters: (json['parameters'] as List<dynamic>?) ?? [],
      sourceId: json['source_id'] as String? ?? '',
      sourceName: json['source_name'] as String? ?? '',
    );
  }
}

class AltrQLExecuteResponseModel {
  final bool success;
  final Map<String, dynamic>? ir;
  final Map<String, dynamic>? boundIr;
  final MutationClassificationModel? classification;
  final PhysicalQueryModel? physicalQuery;
  final List<String> columns;
  final List<Map<String, dynamic>> rows;
  final QueryMetadataModel? metadata;
  final AltrQLErrorDetailModel? error;

  AltrQLExecuteResponseModel({
    required this.success,
    this.ir,
    this.boundIr,
    this.classification,
    this.physicalQuery,
    required this.columns,
    required this.rows,
    this.metadata,
    this.error,
  });

  factory AltrQLExecuteResponseModel.fromJson(Map<String, dynamic> json) {
    return AltrQLExecuteResponseModel(
      success: json['success'] as bool? ?? false,
      ir: json['ir'] as Map<String, dynamic>?,
      boundIr: json['bound_ir'] as Map<String, dynamic>?,
      classification: json['classification'] != null
          ? MutationClassificationModel.fromJson(json['classification'] as Map<String, dynamic>)
          : null,
      physicalQuery: json['physical_query'] != null
          ? PhysicalQueryModel.fromJson(json['physical_query'] as Map<String, dynamic>)
          : null,
      columns: (json['columns'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      rows: (json['rows'] as List<dynamic>?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          [],
      metadata: json['metadata'] != null
          ? QueryMetadataModel.fromJson(json['metadata'] as Map<String, dynamic>)
          : null,
      error: json['error'] != null
          ? AltrQLErrorDetailModel.fromJson(json['error'] as Map<String, dynamic>)
          : null,
    );
  }
}



