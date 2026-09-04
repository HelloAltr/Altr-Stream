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
  final List<String> supportedOperations;

  SourceCapabilitiesModel({
    required this.schemaDiscovery,
    required this.read,
    required this.write,
    required this.cdc,
    required this.supportedOperations,
  });

  factory SourceCapabilitiesModel.fromJson(Map<String, dynamic> json) {
    return SourceCapabilitiesModel(
      schemaDiscovery: json['schema_discovery'] as bool? ?? true,
      read: json['read'] as bool? ?? true,
      write: json['write'] as bool? ?? true,
      cdc: json['cdc'] as bool? ?? false,
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
