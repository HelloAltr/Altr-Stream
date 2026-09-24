class SourceModel {
  final String id;
  final String name;
  final String type;
  final String? host;
  final int? port;
  final String? databaseName;
  final String? username;
  final String? filePath;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String passwordMasked;

  SourceModel({
    required this.id,
    required this.name,
    required this.type,
    this.host,
    this.port,
    this.databaseName,
    this.username,
    this.filePath,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.passwordMasked = '••••••••',
  });

  factory SourceModel.fromJson(Map<String, dynamic> json) {
    return SourceModel(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      type: json['type']?.toString() ?? '',
      host: json['host']?.toString(),
      port: (json['port'] as num?)?.toInt(),
      databaseName: json['database_name']?.toString(),
      username: json['username']?.toString(),
      filePath: json['file_path']?.toString(),
      status: json['status']?.toString() ?? 'UNKNOWN',
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at'].toString()) : DateTime.now(),
      updatedAt: json['updated_at'] != null ? DateTime.parse(json['updated_at'].toString()) : DateTime.now(),
      passwordMasked: json['password_masked']?.toString() ?? '••••••••',
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
      success: json['success'] as bool? ?? false,
      message: json['message']?.toString() ?? '',
      latencyMs: (json['latency_ms'] as num?)?.toDouble(),
      serverVersion: json['server_version']?.toString(),
      errorDetails: json['error_details']?.toString(),
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
      name: json['name']?.toString() ?? '',
      dataType: json['data_type']?.toString() ?? 'STRING',
      nativeDataType: json['native_data_type']?.toString() ?? '',
      nullable: json['nullable'] as bool? ?? true,
      isPrimaryKey: json['is_primary_key'] as bool? ?? false,
      defaultValue: json['default_value']?.toString(),
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
      name: json['name']?.toString() ?? '',
      constraintType: json['constraint_type']?.toString() ?? '',
      fields: (json['fields'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      referencedEntity: json['referenced_entity']?.toString(),
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
      name: json['name']?.toString() ?? '',
      namespace: json['namespace']?.toString() ?? 'public',
      entityType: json['entity_type']?.toString() ?? 'TABLE',
      fields: (json['fields'] as List<dynamic>?)
              ?.map((e) => FieldSchemaModel.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList() ??
          [],
      primaryKey:
          (json['primary_key'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      constraints: (json['constraints'] as List<dynamic>?)
              ?.map((e) => ConstraintSchemaModel.fromJson(Map<String, dynamic>.from(e as Map)))
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
      sourceId: json['source_id']?.toString() ?? '',
      sourceName: json['source_name']?.toString() ?? '',
      version: json['version']?.toString() ?? '1.0.0',
      discoveredAt: json['discovered_at'] != null ? DateTime.parse(json['discovered_at'].toString()) : DateTime.now(),
      entities: (json['entities'] as List<dynamic>?)
              ?.map((e) => EntitySchemaModel.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList() ??
          [],
      metadata: (json['metadata'] is Map) ? Map<String, dynamic>.from(json['metadata'] as Map) : {},
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

class SourceExecutionInfoModel {
  final String sourceId;
  final String? sourceName;
  final String? sourceType;
  final String? physicalEntity;
  final String status;
  final int rows;
  final double? executionTimeMs;

  SourceExecutionInfoModel({
    required this.sourceId,
    this.sourceName,
    this.sourceType,
    this.physicalEntity,
    this.status = 'SUCCESS',
    this.rows = 0,
    this.executionTimeMs,
  });

  factory SourceExecutionInfoModel.fromJson(Map<String, dynamic> json) {
    return SourceExecutionInfoModel(
      sourceId: json['source_id'] as String? ?? '',
      sourceName: json['source_name'] as String?,
      sourceType: json['source_type'] as String?,
      physicalEntity: json['physical_entity'] as String?,
      status: json['status'] as String? ?? 'SUCCESS',
      rows: (json['rows'] as num?)?.toInt() ?? 0,
      executionTimeMs: (json['execution_time_ms'] as num?)?.toDouble(),
    );
  }
}

class SourceExclusionInfoModel {
  final String sourceId;
  final String? sourceName;
  final String? sourceType;
  final String? physicalEntity;
  final String status;
  final String reasonCode;
  final String message;

  SourceExclusionInfoModel({
    required this.sourceId,
    this.sourceName,
    this.sourceType,
    this.physicalEntity,
    this.status = 'EXCLUDED',
    this.reasonCode = 'PHYSICAL_ENTITY_NOT_FOUND',
    this.message = '',
  });

  factory SourceExclusionInfoModel.fromJson(Map<String, dynamic> json) {
    return SourceExclusionInfoModel(
      sourceId: json['source_id'] as String? ?? '',
      sourceName: json['source_name'] as String?,
      sourceType: json['source_type'] as String?,
      physicalEntity: json['physical_entity'] as String?,
      status: json['status'] as String? ?? 'EXCLUDED',
      reasonCode: json['reason_code'] as String? ?? 'PHYSICAL_ENTITY_NOT_FOUND',
      message: json['message'] as String? ?? '',
    );
  }
}

class QueryMetadataModel {
  final int rowCount;
  final int? affectedRows;
  final String? message;
  final double executionTimeMs;
  final String? operation;
  final String? mutationScope;
  final String executionMode;
  final bool normalized;
  final bool isEphemeral;
  final int sourceCount;
  final List<SourceExecutionInfoModel> sources;
  final List<SourceExecutionInfoModel> includedSources;
  final List<SourceExclusionInfoModel> excludedSources;

  QueryMetadataModel({
    required this.rowCount,
    this.affectedRows,
    this.message,
    required this.executionTimeMs,
    this.operation,
    this.mutationScope,
    this.executionMode = 'single_source',
    this.normalized = false,
    this.isEphemeral = false,
    this.sourceCount = 1,
    this.sources = const [],
    this.includedSources = const [],
    this.excludedSources = const [],
  });

  factory QueryMetadataModel.fromJson(Map<String, dynamic> json) {
    final sourcesList = (json['sources'] as List<dynamic>?)
            ?.map((e) => SourceExecutionInfoModel.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];
    final includedList = (json['included_sources'] as List<dynamic>?)
            ?.map((e) => SourceExecutionInfoModel.fromJson(e as Map<String, dynamic>))
            .toList() ??
        sourcesList;
    final excludedList = (json['excluded_sources'] as List<dynamic>?)
            ?.map((e) => SourceExclusionInfoModel.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];
    return QueryMetadataModel(
      rowCount: (json['row_count'] as num?)?.toInt() ?? 0,
      affectedRows: (json['affected_rows'] as num?)?.toInt(),
      message: json['message'] as String?,
      executionTimeMs: (json['execution_time_ms'] as num?)?.toDouble() ?? 0.0,
      operation: json['operation'] as String?,
      mutationScope: json['mutation_scope'] as String?,
      executionMode: json['execution_mode'] as String? ?? 'single_source',
      normalized: json['normalized'] as bool? ?? false,
      isEphemeral: json['is_ephemeral'] as bool? ?? false,
      sourceCount: (json['source_count'] as num?)?.toInt() ?? (includedList.isNotEmpty ? includedList.length : 1),
      sources: sourcesList,
      includedSources: includedList,
      excludedSources: excludedList,
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
  final String executionMode;
  final String? selectedSourceId;
  final String? selectedMappingId;
  final bool isEphemeral;
  final AltrQLErrorDetailModel? error;

  AltrQLBindResponseModel({
    required this.success,
    this.ir,
    this.boundIr,
    this.classification,
    this.executionMode = 'single',
    this.isEphemeral = false,
    this.selectedSourceId,
    this.selectedMappingId,
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
      executionMode: json['execution_mode'] as String? ?? 'single',
      isEphemeral: json['is_ephemeral'] as bool? ?? false,
      selectedSourceId: json['selected_source_id'] as String?,
      selectedMappingId: json['selected_mapping_id'] as String?,
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
  final List<PhysicalQueryModel> physicalQueries;
  final List<String> columns;
  final List<Map<String, dynamic>> rows;
  final QueryMetadataModel? metadata;
  final String executionMode;
  final List<String> sourcesExecuted;
  final String? selectedSourceId;
  final String? selectedMappingId;
  final AltrQLErrorDetailModel? error;

  AltrQLExecuteResponseModel({
    required this.success,
    this.ir,
    this.boundIr,
    this.classification,
    this.physicalQuery,
    this.physicalQueries = const [],
    required this.columns,
    required this.rows,
    this.metadata,
    this.executionMode = 'single',
    this.sourcesExecuted = const [],
    this.selectedSourceId,
    this.selectedMappingId,
    this.error,
  });

  factory AltrQLExecuteResponseModel.fromJson(Map<String, dynamic> json) {
    final physicalQueriesList = (json['physical_queries'] as List<dynamic>?)
            ?.map((e) => PhysicalQueryModel.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];

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
      physicalQueries: physicalQueriesList,
      columns: (json['columns'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      rows: (json['rows'] as List<dynamic>?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          [],
      metadata: json['metadata'] != null
          ? QueryMetadataModel.fromJson(json['metadata'] as Map<String, dynamic>)
          : null,
      executionMode: json['execution_mode'] as String? ?? 'single',
      sourcesExecuted: (json['sources_executed'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      selectedSourceId: json['selected_source_id'] as String?,
      selectedMappingId: json['selected_mapping_id'] as String?,
      error: json['error'] != null
          ? AltrQLErrorDetailModel.fromJson(json['error'] as Map<String, dynamic>)
          : null,
    );
  }
}

// ==========================================
// Schema & Mapping Registry Models (v0.7.0)
// ==========================================

class LogicalFieldModel {
  final String id;
  final String logicalEntityId;
  final String name;
  final String dataType;
  final bool nullable;
  final bool isPrimaryKey;
  final String? description;
  final Map<String, dynamic> metadata;
  final DateTime createdAt;
  final DateTime updatedAt;

  LogicalFieldModel({
    required this.id,
    required this.logicalEntityId,
    required this.name,
    required this.dataType,
    this.nullable = true,
    this.isPrimaryKey = false,
    this.description,
    this.metadata = const {},
    required this.createdAt,
    required this.updatedAt,
  });

  factory LogicalFieldModel.fromJson(Map<String, dynamic> json) {
    return LogicalFieldModel(
      id: json['id']?.toString() ?? '',
      logicalEntityId: json['logical_entity_id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      dataType: json['data_type']?.toString() ?? 'STRING',
      nullable: json['nullable'] as bool? ?? true,
      isPrimaryKey: json['is_primary_key'] as bool? ?? false,
      description: json['description']?.toString(),
      metadata: (json['metadata'] is Map) ? Map<String, dynamic>.from(json['metadata'] as Map) : {},
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at'].toString()) : DateTime.now(),
      updatedAt: json['updated_at'] != null ? DateTime.parse(json['updated_at'].toString()) : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'data_type': dataType,
        'nullable': nullable,
        'is_primary_key': isPrimaryKey,
        'description': description,
        'metadata': metadata,
      };
}

class LogicalEntityModel {
  final String id;
  final String logicalModelId;
  final String name;
  final String? description;
  final List<LogicalFieldModel> fields;
  final Map<String, dynamic> metadata;
  final DateTime createdAt;
  final DateTime updatedAt;

  LogicalEntityModel({
    required this.id,
    required this.logicalModelId,
    required this.name,
    this.description,
    this.fields = const [],
    this.metadata = const {},
    required this.createdAt,
    required this.updatedAt,
  });

  factory LogicalEntityModel.fromJson(Map<String, dynamic> json) {
    return LogicalEntityModel(
      id: json['id']?.toString() ?? '',
      logicalModelId: json['logical_model_id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      description: json['description']?.toString(),
      fields: (json['fields'] as List<dynamic>?)
              ?.map((e) => LogicalFieldModel.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList() ??
          [],
      metadata: (json['metadata'] is Map) ? Map<String, dynamic>.from(json['metadata'] as Map) : {},
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at'].toString()) : DateTime.now(),
      updatedAt: json['updated_at'] != null ? DateTime.parse(json['updated_at'].toString()) : DateTime.now(),
    );
  }

  int get fieldCount => fields.length;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'fields': fields.map((f) => f.toJson()).toList(),
        'metadata': metadata,
      };
}

class LogicalModelModel {
  final String id;
  final String name;
  final String version;
  final String? description;
  final List<LogicalEntityModel> entities;
  final Map<String, dynamic> metadata;
  final DateTime createdAt;
  final DateTime updatedAt;

  LogicalModelModel({
    required this.id,
    required this.name,
    this.version = '1.0.0',
    this.description,
    this.entities = const [],
    this.metadata = const {},
    required this.createdAt,
    required this.updatedAt,
  });

  factory LogicalModelModel.fromJson(Map<String, dynamic> json) {
    return LogicalModelModel(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      version: json['version']?.toString() ?? '1.0.0',
      description: json['description']?.toString(),
      entities: (json['entities'] as List<dynamic>?)
              ?.map((e) => LogicalEntityModel.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList() ??
          [],
      metadata: (json['metadata'] is Map) ? Map<String, dynamic>.from(json['metadata'] as Map) : {},
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at'].toString()) : DateTime.now(),
      updatedAt: json['updated_at'] != null ? DateTime.parse(json['updated_at'].toString()) : DateTime.now(),
    );
  }

  int get entityCount => entities.length;
  int get totalFieldCount => entities.fold<int>(0, (prev, e) => prev + e.fields.length);
}

class FieldMappingModel {
  final String id;
  final String entityMappingId;
  final String logicalFieldId;
  final String logicalFieldName;
  final String physicalFieldName;
  final String? transformationRule;
  final Map<String, dynamic> metadata;
  final DateTime createdAt;
  final DateTime updatedAt;

  FieldMappingModel({
    required this.id,
    required this.entityMappingId,
    required this.logicalFieldId,
    required this.logicalFieldName,
    required this.physicalFieldName,
    this.transformationRule,
    this.metadata = const {},
    required this.createdAt,
    required this.updatedAt,
  });

  factory FieldMappingModel.fromJson(Map<String, dynamic> json) {
    return FieldMappingModel(
      id: json['id']?.toString() ?? '',
      entityMappingId: json['entity_mapping_id']?.toString() ?? '',
      logicalFieldId: json['logical_field_id']?.toString() ?? '',
      logicalFieldName: json['logical_field_name']?.toString() ?? '',
      physicalFieldName: json['physical_field_name']?.toString() ?? '',
      transformationRule: json['transformation_rule']?.toString(),
      metadata: (json['metadata'] is Map) ? Map<String, dynamic>.from(json['metadata'] as Map) : {},
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at'].toString()) : DateTime.now(),
      updatedAt: json['updated_at'] != null ? DateTime.parse(json['updated_at'].toString()) : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'logical_field_id': logicalFieldId,
        'logical_field_name': logicalFieldName,
        'physical_field_name': physicalFieldName,
        'transformation_rule': transformationRule,
        'metadata': metadata,
      };
}

class EntityMappingModel {
  final String id;
  final String sourceMappingId;
  final String logicalEntityId;
  final String logicalEntityName;
  final String physicalEntityName;
  final String physicalNamespace;
  final List<FieldMappingModel> fieldMappings;
  final Map<String, dynamic> metadata;
  final DateTime createdAt;
  final DateTime updatedAt;

  EntityMappingModel({
    required this.id,
    required this.sourceMappingId,
    required this.logicalEntityId,
    required this.logicalEntityName,
    required this.physicalEntityName,
    this.physicalNamespace = 'public',
    this.fieldMappings = const [],
    this.metadata = const {},
    required this.createdAt,
    required this.updatedAt,
  });

  factory EntityMappingModel.fromJson(Map<String, dynamic> json) {
    return EntityMappingModel(
      id: json['id']?.toString() ?? '',
      sourceMappingId: json['source_mapping_id']?.toString() ?? '',
      logicalEntityId: json['logical_entity_id']?.toString() ?? '',
      logicalEntityName: json['logical_entity_name']?.toString() ?? '',
      physicalEntityName: json['physical_entity_name']?.toString() ?? '',
      physicalNamespace: json['physical_namespace']?.toString() ?? 'public',
      fieldMappings: (json['field_mappings'] as List<dynamic>?)
              ?.map((e) => FieldMappingModel.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList() ??
          [],
      metadata: (json['metadata'] is Map) ? Map<String, dynamic>.from(json['metadata'] as Map) : {},
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at'].toString()) : DateTime.now(),
      updatedAt: json['updated_at'] != null ? DateTime.parse(json['updated_at'].toString()) : DateTime.now(),
    );
  }

  int get fieldMappingCount => fieldMappings.length;

  Map<String, dynamic> toJson() => {
        'id': id,
        'logical_entity_id': logicalEntityId,
        'logical_entity_name': logicalEntityName,
        'physical_entity_name': physicalEntityName,
        'physical_namespace': physicalNamespace,
        'field_mappings': fieldMappings.map((f) => f.toJson()).toList(),
        'metadata': metadata,
      };
}

class SourceMappingModel {
  final String id;
  final String logicalModelId;
  final String sourceId;
  final String version;
  final String status;
  final String provenance;
  final List<String> validationErrors;
  final List<EntityMappingModel> entityMappings;
  final Map<String, dynamic> metadata;
  final DateTime createdAt;
  final DateTime updatedAt;

  SourceMappingModel({
    required this.id,
    required this.logicalModelId,
    required this.sourceId,
    this.version = '1.0.0',
    this.status = 'DRAFT',
    this.provenance = 'USER',
    this.validationErrors = const [],
    this.entityMappings = const [],
    this.metadata = const {},
    required this.createdAt,
    required this.updatedAt,
  });

  factory SourceMappingModel.fromJson(Map<String, dynamic> json) {
    final List<String> errs = [];
    if (json['validation_errors'] is List) {
      errs.addAll((json['validation_errors'] as List).map((e) => e.toString()));
    }
    if (json['error_message'] != null && json['error_message'].toString().isNotEmpty) {
      final msg = json['error_message'].toString();
      if (!errs.contains(msg)) {
        errs.add(msg);
      }
    }

    return SourceMappingModel(
      id: json['id']?.toString() ?? '',
      logicalModelId: json['logical_model_id']?.toString() ?? '',
      sourceId: json['source_id']?.toString() ?? '',
      version: json['version']?.toString() ?? '1.0.0',
      status: json['status']?.toString() ?? 'DRAFT',
      provenance: json['provenance']?.toString() ?? 'USER',
      validationErrors: errs,
      entityMappings: (json['entity_mappings'] as List<dynamic>?)
              ?.map((e) => EntityMappingModel.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList() ??
          [],
      metadata: (json['metadata'] is Map) ? Map<String, dynamic>.from(json['metadata'] as Map) : {},
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at'].toString()) : DateTime.now(),
      updatedAt: json['updated_at'] != null ? DateTime.parse(json['updated_at'].toString()) : DateTime.now(),
    );
  }

  bool get isActive => status.toUpperCase() == 'ACTIVE';
  bool get isDraft => status.toUpperCase() == 'DRAFT';
  bool get isValidated => status.toUpperCase() == 'VALIDATED';
  bool get isError => status.toUpperCase() == 'ERROR';
  int get entityMappingCount => entityMappings.length;
}

class RegistrySummaryModel {
  final int totalModels;
  final int totalEntities;
  final int totalLogicalFields;
  final int totalSourceMappings;
  final int activeSourceMappings;
  final int draftSourceMappings;
  final int validatedSourceMappings;
  final int errorSourceMappings;

  RegistrySummaryModel({
    required this.totalModels,
    required this.totalEntities,
    required this.totalLogicalFields,
    required this.totalSourceMappings,
    required this.activeSourceMappings,
    required this.draftSourceMappings,
    required this.validatedSourceMappings,
    required this.errorSourceMappings,
  });

  factory RegistrySummaryModel.fromJson(Map<String, dynamic> json) {
    return RegistrySummaryModel(
      totalModels: (json['total_models'] as num?)?.toInt() ?? 0,
      totalEntities: (json['total_entities'] as num?)?.toInt() ?? 0,
      totalLogicalFields: (json['total_logical_fields'] as num?)?.toInt() ?? 0,
      totalSourceMappings: (json['total_source_mappings'] as num?)?.toInt() ?? 0,
      activeSourceMappings: (json['active_source_mappings'] as num?)?.toInt() ?? 0,
      draftSourceMappings: (json['draft_source_mappings'] as num?)?.toInt() ?? 0,
      validatedSourceMappings: (json['validated_source_mappings'] as num?)?.toInt() ?? 0,
      errorSourceMappings: (json['error_source_mappings'] as num?)?.toInt() ?? 0,
    );
  }
}

const Set<String> _kIntegerTypes = {'INTEGER', 'BIGINT', 'SMALLINT', 'INT', 'INT2', 'INT4', 'INT8', 'SERIAL', 'BIGSERIAL', 'SMALLSERIAL'};
const Set<String> _kFloatTypes = {'FLOAT', 'DECIMAL', 'REAL', 'DOUBLE', 'NUMERIC', 'FLOAT4', 'FLOAT8', 'DOUBLE PRECISION'};
const Set<String> _kStringTypes = {'STRING', 'VARCHAR', 'TEXT', 'CHAR', 'CHARACTER', 'CHARACTER VARYING', 'CITEXT', 'UUID'};
const Set<String> _kBooleanTypes = {'BOOLEAN', 'BOOL'};
const Set<String> _kTemporalTypes = {'DATE', 'TIME', 'TIMESTAMP', 'TIMESTAMPTZ', 'TIMETZ', 'DATETIME'};
const Set<String> _kJsonTypes = {'JSON', 'JSONB'};
const Set<String> _kBinaryTypes = {'BINARY', 'BYTEA', 'BLOB'};
const Set<String> _kArrayTypes = {'ARRAY'};

bool areDataTypesCompatible(String? logicalType, String? physicalType) {
  if (logicalType == null || physicalType == null) return false;
  final l = logicalType.toUpperCase().trim();
  final p = physicalType.toUpperCase().trim();
  if (l.isEmpty || p.isEmpty) return false;
  if (l == p) return true;

  if (_kIntegerTypes.contains(l)) {
    return _kIntegerTypes.contains(p);
  }
  if (_kFloatTypes.contains(l)) {
    return _kFloatTypes.contains(p) || _kIntegerTypes.contains(p);
  }
  if (_kStringTypes.contains(l)) {
    return _kStringTypes.contains(p);
  }
  if (_kBooleanTypes.contains(l)) {
    return _kBooleanTypes.contains(p);
  }
  if (_kTemporalTypes.contains(l)) {
    return _kTemporalTypes.contains(p);
  }
  if (_kJsonTypes.contains(l)) {
    return _kJsonTypes.contains(p);
  }
  if (_kBinaryTypes.contains(l)) {
    return _kBinaryTypes.contains(p);
  }
  if (_kArrayTypes.contains(l)) {
    return _kArrayTypes.contains(p);
  }

  return false;
}

class ApiExecutionResult {
  final int statusCode;
  final String statusText;
  final Duration duration;
  final String requestMethod;
  final String requestUrl;
  final Map<String, String> requestHeaders;
  final String? requestBody;
  final Map<String, String> responseHeaders;
  final dynamic responseBody;
  final String? errorMessage;
  final bool isSuccess;

  ApiExecutionResult({
    required this.statusCode,
    required this.statusText,
    required this.duration,
    required this.requestMethod,
    required this.requestUrl,
    required this.requestHeaders,
    this.requestBody,
    required this.responseHeaders,
    this.responseBody,
    this.errorMessage,
    required this.isSuccess,
  });

  String get formattedDuration {
    final ms = duration.inMilliseconds;
    if (ms < 1000) {
      return '${ms}ms';
    }
    return '${(ms / 1000).toStringAsFixed(2)}s';
  }
}

class UserProfile {
  final String id;
  final String displayName;
  final String email;
  final String? photoUrl;
  final String? provider;

  const UserProfile({
    required this.id,
    required this.displayName,
    required this.email,
    this.photoUrl,
    this.provider = 'google.com',
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id']?.toString() ?? '',
      displayName: json['displayName']?.toString() ?? json['name']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      photoUrl: json['photoUrl']?.toString() ?? json['picture']?.toString() ?? json['avatar_url']?.toString(),
      provider: json['provider']?.toString() ?? 'google.com',
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'displayName': displayName,
    'email': email,
    'photoUrl': photoUrl,
    'provider': provider,
  };
}

class UsageMetricsModel {
  final int totalReads;
  final int totalWrites;
  final double opsPerMinute;
  final double readPercentage;
  final double writePercentage;
  final String timeWindow;
  final List<String> timestamps;
  final List<int> rawReads;
  final List<int> rawWrites;
  final List<double> readHistory;
  final List<double> writeHistory;
  final int yMax;

  const UsageMetricsModel({
    required this.totalReads,
    required this.totalWrites,
    required this.opsPerMinute,
    required this.readPercentage,
    required this.writePercentage,
    this.timeWindow = '30m',
    this.timestamps = const [],
    this.rawReads = const [],
    this.rawWrites = const [],
    required this.readHistory,
    required this.writeHistory,
    this.yMax = 10,
  });

  factory UsageMetricsModel.fromJson(Map<String, dynamic> json) {
    return UsageMetricsModel(
      totalReads: (json['total_reads'] as num?)?.toInt() ?? 0,
      totalWrites: (json['total_writes'] as num?)?.toInt() ?? 0,
      opsPerMinute: (json['ops_per_minute'] as num?)?.toDouble() ?? 0.0,
      readPercentage: (json['read_percentage'] as num?)?.toDouble() ?? 0.0,
      writePercentage: (json['write_percentage'] as num?)?.toDouble() ?? 0.0,
      timeWindow: json['time_window']?.toString() ?? '30m',
      timestamps: (json['timestamps'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? const [],
      rawReads: (json['raw_reads'] as List<dynamic>?)?.map((e) => (e as num).toInt()).toList() ?? const [],
      rawWrites: (json['raw_writes'] as List<dynamic>?)?.map((e) => (e as num).toInt()).toList() ?? const [],
      readHistory: (json['read_history'] as List<dynamic>?)
              ?.map((e) => (e as num).toDouble())
              .toList() ??
          const [],
      writeHistory: (json['write_history'] as List<dynamic>?)
              ?.map((e) => (e as num).toDouble())
              .toList() ??
          const [],
      yMax: (json['y_max'] as num?)?.toInt() ?? 10,
    );
  }

  Map<String, dynamic> toJson() => {
        'total_reads': totalReads,
        'total_writes': totalWrites,
        'ops_per_minute': opsPerMinute,
        'read_percentage': readPercentage,
        'write_percentage': writePercentage,
        'time_window': timeWindow,
        'timestamps': timestamps,
        'raw_reads': rawReads,
        'raw_writes': rawWrites,
        'read_history': readHistory,
        'write_history': writeHistory,
        'y_max': yMax,
      };

  String get formattedOpsPerMinute {
    if (opsPerMinute >= 1000) {
      return '${(opsPerMinute / 1000).toStringAsFixed(1)}k ops/m';
    }
    return '${opsPerMinute.toStringAsFixed(1)} ops/m';
  }
}

class UpdateCheckResponse {
  final String currentVersion;
  final String? latestVersion;
  final bool updateAvailable;
  final String channel;
  final String? releaseTag;
  final String? releaseName;
  final String? releaseNotes;
  final String? publishedAt;
  final String? htmlUrl;

  const UpdateCheckResponse({
    required this.currentVersion,
    this.latestVersion,
    required this.updateAvailable,
    required this.channel,
    this.releaseTag,
    this.releaseName,
    this.releaseNotes,
    this.publishedAt,
    this.htmlUrl,
  });

  factory UpdateCheckResponse.fromJson(Map<String, dynamic> json) {
    final rel = json['release'] as Map<String, dynamic>?;
    return UpdateCheckResponse(
      currentVersion: json['current_version']?.toString() ?? '',
      latestVersion: json['latest_version']?.toString(),
      updateAvailable: json['update_available'] == true,
      channel: json['channel']?.toString() ?? 'alpha',
      releaseTag: rel?['tag_name']?.toString(),
      releaseName: rel?['name']?.toString(),
      releaseNotes: rel?['body']?.toString(),
      publishedAt: rel?['published_at']?.toString(),
      htmlUrl: rel?['html_url']?.toString(),
    );
  }
}

class UpdateStatusResponse {
  final String? requestId;
  final String state;
  final String currentVersion;
  final String? targetVersion;
  final int progressPercent;
  final String message;
  final String? error;
  final String updatedAt;
  final bool rollbackPerformed;

  const UpdateStatusResponse({
    this.requestId,
    required this.state,
    required this.currentVersion,
    this.targetVersion,
    required this.progressPercent,
    required this.message,
    this.error,
    required this.updatedAt,
    this.rollbackPerformed = false,
  });

  factory UpdateStatusResponse.fromJson(Map<String, dynamic> json) {
    return UpdateStatusResponse(
      requestId: json['request_id']?.toString(),
      state: json['state']?.toString() ?? 'idle',
      currentVersion: json['current_version']?.toString() ?? '',
      targetVersion: json['target_version']?.toString(),
      progressPercent: (json['progress_percent'] as num?)?.toInt() ?? 0,
      message: json['message']?.toString() ?? '',
      error: json['error']?.toString(),
      updatedAt: json['updated_at']?.toString() ?? '',
      rollbackPerformed: json['rollback_performed'] == true,
    );
  }

  bool get isIdle => state == 'idle';
  bool get isRequested => state == 'requested';
  bool get isStaging => state == 'staging';
  bool get isApplying => state == 'applying';
  bool get isHealthCheck => state == 'health_check';
  bool get isCompleted => state == 'completed';
  bool get isFailed => state == 'failed';
  bool get isRollingBack => state == 'rolling_back';
  bool get isRolledBack => state == 'rolled_back';

  bool get isActive => isRequested || isStaging || isApplying || isHealthCheck || isRollingBack;
}


