"""MongoDB metadata and document sampling to standardized Altr Schema mapper."""

from datetime import datetime, timezone
import decimal
from typing import Any
import uuid

import bson
from bson import Binary, Decimal128, Int64, ObjectId
from bson.timestamp import Timestamp

from altr_stream.domain.schema import (
    EntitySchema,
    FieldSchema,
    INTEGER_TYPES,
    FLOAT_TYPES,
    TEMPORAL_TYPES,
    SourceSchema,
    StandardDataType,
)


def map_bson_value_to_standard(val: Any) -> tuple[StandardDataType, str]:
    """Map a Python / BSON value to its standardized Altr Stream data type and native BSON type name."""
    if val is None:
        return StandardDataType.STRING, "null"

    # 1. ObjectId
    if isinstance(val, ObjectId):
        return StandardDataType.STRING, "objectId"

    # 2. Decimal128 (exact precision, never float)
    if isinstance(val, (Decimal128, decimal.Decimal)):
        return StandardDataType.DECIMAL, "decimal128"

    # 3. Temporal types (datetime, Timestamp)
    if isinstance(val, datetime):
        return StandardDataType.TIMESTAMP, "date"
    if isinstance(val, Timestamp):
        return StandardDataType.INTEGER, "timestamp"

    # 4. UUID & Binary types
    if isinstance(val, uuid.UUID):
        return StandardDataType.UUID, "uuid"
    if isinstance(val, Binary):
        # BSON Binary subtype 4 is standard RFC 4122 UUID (network byte order)
        # BSON Binary subtype 3 is legacy UUID with driver-dependent byte order;
        # treating subtype 3 as BINARY avoids driver-dependent UUID parsing ambiguities.
        if val.subtype == 4:
            return StandardDataType.UUID, "uuid"
        return StandardDataType.BINARY, "binary"
    if isinstance(val, bytes):
        return StandardDataType.BINARY, "binary"

    # 5. Embedded Document (dict)
    if isinstance(val, dict):
        return StandardDataType.JSON, "document"

    # 6. Array (list)
    if isinstance(val, (list, tuple)):
        return StandardDataType.ARRAY, "array"

    # 7. String
    if isinstance(val, str):
        return StandardDataType.STRING, "string"

    # 8. Boolean (MUST be checked before int because bool is a subclass of int in Python)
    if isinstance(val, bool):
        return StandardDataType.BOOLEAN, "bool"

    # 9. Integer & 64-bit Long
    if isinstance(val, (int, Int64)):
        if isinstance(val, Int64) or val > 2147483647 or val < -2147483648:
            return StandardDataType.BIGINT, "long"
        return StandardDataType.INTEGER, "int"

    # 10. Float / Double
    if isinstance(val, float):
        return StandardDataType.FLOAT, "double"

    # 11. Unsupported / other BSON types
    type_name = type(val).__name__.lower()
    return StandardDataType.OTHER, type_name


def merge_observed_types(types: set[tuple[StandardDataType, str]]) -> tuple[StandardDataType, str]:
    """Deterministically resolve a single representative data type from multiple observed types."""
    if not types:
        return StandardDataType.STRING, "null"

    if len(types) == 1:
        return next(iter(types))

    std_types = {t[0] for t in types}

    # Integer promotion
    if std_types.issubset(INTEGER_TYPES):
        if StandardDataType.BIGINT in std_types:
            return StandardDataType.BIGINT, "long"
        return StandardDataType.INTEGER, "int"

    # Numeric promotion (integer + float / decimal)
    if std_types.issubset(INTEGER_TYPES | FLOAT_TYPES):
        if StandardDataType.DECIMAL in std_types:
            return StandardDataType.DECIMAL, "decimal128"
        return StandardDataType.FLOAT, "double"

    # Temporal promotion
    if std_types.issubset(TEMPORAL_TYPES):
        return StandardDataType.TIMESTAMP, "date"

    # Incompatible mixed types: deterministically resolve to OTHER with sorted native type labels
    sorted_natives = sorted(list({t[1] for t in types}))
    return StandardDataType.OTHER, f"mixed({', '.join(sorted_natives)})"


def traverse_document_fields(
    doc: dict[str, Any],
    depth: int = 1,
    prefix: str = "",
    max_depth: int = 3,
) -> list[tuple[str, Any]]:
    """Recursively traverse a MongoDB document up to max_depth and yield (field_path, value) pairs."""
    results: list[tuple[str, Any]] = []

    for key, val in doc.items():
        field_path = f"{prefix}.{key}" if prefix else key
        results.append((field_path, val))

        # Recurse into nested documents if within depth limit
        if isinstance(val, dict) and depth < max_depth:
            results.extend(
                traverse_document_fields(
                    val,
                    depth=depth + 1,
                    prefix=field_path,
                    max_depth=max_depth,
                )
            )

    return results


def build_source_schema_from_mongodb_samples(
    source_id: str,
    source_name: str,
    database_name: str,
    sampled_collections: dict[str, list[dict[str, Any]]],
    sample_limit: int = 100,
) -> SourceSchema:
    """Construct a standardized SourceSchema from observed deterministic document samples."""
    entities: list[EntitySchema] = []

    # Sort collection names for deterministic entity ordering
    for coll_name in sorted(sampled_collections.keys()):
        docs = sampled_collections[coll_name]
        total_docs = len(docs)

        # Handle empty collection explicitly
        if total_docs == 0:
            default_id_field = FieldSchema(
                name="_id",
                data_type=StandardDataType.STRING,
                native_data_type="objectId (inferred default)",
                nullable=False,
                is_primary_key=True,
                position=1,
                comment="Inferred default identifier for empty collection (not an observed fact)",
            )
            entities.append(
                EntitySchema(
                    name=coll_name,
                    namespace=database_name or "default",
                    entity_type="COLLECTION",
                    fields=[default_id_field],
                    primary_key=["_id"],
                    constraints=[],
                    comment="Empty MongoDB collection (observed sample count: 0)",
                )
            )
            continue

        # Aggregate observed field properties across all sampled documents
        field_presence: dict[str, int] = {}
        field_nulls: dict[str, int] = {}
        field_types: dict[str, set[tuple[StandardDataType, str]]] = {}

        for doc in docs:
            observed_in_doc = traverse_document_fields(doc, depth=1, prefix="", max_depth=3)
            # Ensure each field path is counted once per document
            doc_fields: dict[str, Any] = {}
            for path, val in observed_in_doc:
                doc_fields[path] = val

            for path, val in doc_fields.items():
                field_presence[path] = field_presence.get(path, 0) + 1
                if val is None:
                    field_nulls[path] = field_nulls.get(path, 0) + 1
                else:
                    std_type, nat_type = map_bson_value_to_standard(val)
                    if path not in field_types:
                        field_types[path] = set()
                    field_types[path].add((std_type, nat_type))

        # Order fields: _id always first (position 1), then non-_id sorted alphabetically
        all_paths = set(field_presence.keys())
        has_id = "_id" in all_paths
        non_id_paths = sorted([p for p in all_paths if p != "_id"])

        ordered_paths: list[str] = []
        if has_id:
            ordered_paths.append("_id")
        ordered_paths.extend(non_id_paths)

        fields: list[FieldSchema] = []
        for pos, path in enumerate(ordered_paths, start=1):
            is_pk = (path == "_id")
            observed_types = field_types.get(path, set())

            if observed_types:
                data_type, native_data_type = merge_observed_types(observed_types)
            else:
                data_type, native_data_type = StandardDataType.STRING, "null"

            present_count = field_presence.get(path, 0)
            null_count = field_nulls.get(path, 0)

            # _id in MongoDB documents is strictly non-nullable
            if is_pk:
                nullable = False
            else:
                # Nullable if missing in any document or observed as explicit null
                nullable = (present_count < total_docs) or (null_count > 0)

            fields.append(
                FieldSchema(
                    name=path,
                    data_type=data_type,
                    native_data_type=native_data_type,
                    nullable=nullable,
                    is_primary_key=is_pk,
                    position=pos,
                )
            )

        entities.append(
            EntitySchema(
                name=coll_name,
                namespace=database_name or "default",
                entity_type="COLLECTION",
                fields=fields,
                primary_key=["_id"] if has_id else [],
                constraints=[],
                comment=f"Observed MongoDB collection (sample count: {total_docs})",
            )
        )

    return SourceSchema(
        source_id=source_id,
        source_name=source_name,
        version="1.0.0",
        discovered_at=datetime.now(timezone.utc),
        entities=entities,
        metadata={
            "database_name": database_name,
            "discovery_method": "deterministic_sampling",
            "sample_limit": sample_limit,
            "sample_sort": {"_id": 1},
            "max_nested_depth": 3,
        },
    )
