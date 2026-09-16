"""Unit tests for MongoDB BSON mapping, deterministic sampling, and SourceSchema construction."""

from datetime import datetime, timedelta, timezone
import decimal
import uuid

import bson
from bson import Binary, Decimal128, Int64, ObjectId
from bson.regex import Regex
from bson.timestamp import Timestamp
import pytest

from altr_stream.domain.schema import StandardDataType
from altr_stream.infrastructure.connectors.mongodb.mapper import (
    build_source_schema_from_mongodb_samples,
    extract_columns_from_documents,
    map_bson_value_to_standard,
    merge_observed_types,
    normalize_bson_document,
    normalize_bson_value,
    traverse_document_fields,
)


def test_map_bson_value_to_standard_primitives():
    """Verify BSON mapping for primitive Python and BSON types."""
    # 1. String
    assert map_bson_value_to_standard("hello") == (StandardDataType.STRING, "string")

    # 2. Boolean (must not be confused with int)
    assert map_bson_value_to_standard(True) == (StandardDataType.BOOLEAN, "bool")
    assert map_bson_value_to_standard(False) == (StandardDataType.BOOLEAN, "bool")

    # 3. Integer (32-bit vs 64-bit Long)
    assert map_bson_value_to_standard(42) == (StandardDataType.INTEGER, "int")
    assert map_bson_value_to_standard(Int64(42)) == (StandardDataType.BIGINT, "long")
    assert map_bson_value_to_standard(3000000000) == (StandardDataType.BIGINT, "long")

    # 4. Float / Double
    assert map_bson_value_to_standard(3.14159) == (StandardDataType.FLOAT, "double")

    # 5. Null
    assert map_bson_value_to_standard(None) == (StandardDataType.STRING, "null")


def test_map_bson_value_to_standard_specialized_bson():
    """Verify specialized BSON types: ObjectId, Decimal128, datetime, Timestamp, Binary, UUID."""
    # 1. ObjectId
    oid = ObjectId("507f1f77bcf86cd799439011")
    assert map_bson_value_to_standard(oid) == (StandardDataType.STRING, "objectId")

    # 2. Decimal128 (exact precision preservation)
    dec128 = Decimal128("12345.6789")
    assert map_bson_value_to_standard(dec128) == (StandardDataType.DECIMAL, "decimal128")
    dec_std = decimal.Decimal("9876.54")
    assert map_bson_value_to_standard(dec_std) == (StandardDataType.DECIMAL, "decimal128")

    # 3. datetime and Timestamp
    dt = datetime(2026, 9, 16, 9, 0, 0, tzinfo=timezone.utc)
    assert map_bson_value_to_standard(dt) == (StandardDataType.TIMESTAMP, "date")
    ts = Timestamp(1726477200, 1)
    assert map_bson_value_to_standard(ts) == (StandardDataType.INTEGER, "timestamp")

    # 4. UUID & Binary
    u = uuid.uuid4()
    assert map_bson_value_to_standard(u) == (StandardDataType.UUID, "uuid")
    # Subtype 4 = Standard RFC 4122 UUID
    bin_uuid = Binary(u.bytes, subtype=4)
    assert map_bson_value_to_standard(bin_uuid) == (StandardDataType.UUID, "uuid")
    # Subtype 3 = Legacy UUID (treated as BINARY for safety and driver-independence)
    bin_legacy_uuid = Binary(u.bytes, subtype=3)
    assert map_bson_value_to_standard(bin_legacy_uuid) == (StandardDataType.BINARY, "binary")
    # Subtype 0 = Generic Binary
    bin_general = Binary(b"\x01\x02\x03\x04", subtype=0)
    assert map_bson_value_to_standard(bin_general) == (StandardDataType.BINARY, "binary")
    assert map_bson_value_to_standard(b"raw bytes") == (StandardDataType.BINARY, "binary")

    # 5. Embedded document and Array
    assert map_bson_value_to_standard({"a": 1}) == (StandardDataType.JSON, "document")
    assert map_bson_value_to_standard([1, 2, 3]) == (StandardDataType.ARRAY, "array")

    # 6. Unsupported / other BSON type
    regex_val = Regex("abc", "i")
    assert map_bson_value_to_standard(regex_val) == (StandardDataType.OTHER, "regex")


def test_merge_observed_types_numeric_promotion():
    """Verify numeric promotion for integer and float/decimal combinations."""
    # int + int -> int
    assert merge_observed_types({(StandardDataType.INTEGER, "int")}) == (StandardDataType.INTEGER, "int")

    # int + bigint -> bigint
    types_int_bigint = {
        (StandardDataType.INTEGER, "int"),
        (StandardDataType.BIGINT, "long"),
    }
    assert merge_observed_types(types_int_bigint) == (StandardDataType.BIGINT, "long")

    # int + float -> float
    types_int_float = {
        (StandardDataType.INTEGER, "int"),
        (StandardDataType.FLOAT, "double"),
    }
    assert merge_observed_types(types_int_float) == (StandardDataType.FLOAT, "double")

    # int + decimal -> decimal
    types_int_dec = {
        (StandardDataType.INTEGER, "int"),
        (StandardDataType.DECIMAL, "decimal128"),
    }
    assert merge_observed_types(types_int_dec) == (StandardDataType.DECIMAL, "decimal128")


def test_merge_observed_types_temporal_promotion():
    """Verify temporal type promotions (date + timestamp -> timestamp)."""
    types_temporal = {
        (StandardDataType.TIMESTAMP, "date"),
        (StandardDataType.TIMESTAMP, "timestamp"),
    }
    assert merge_observed_types(types_temporal) == (StandardDataType.TIMESTAMP, "date")


def test_merge_observed_types_string_and_uuid_deterministic_mixed():
    """Verify that string + UUID resolves to deterministic mixed type (StandardDataType.OTHER)."""
    types_str_uuid = {
        (StandardDataType.STRING, "string"),
        (StandardDataType.UUID, "uuid"),
    }
    assert merge_observed_types(types_str_uuid) == (StandardDataType.OTHER, "mixed(string, uuid)")


def test_merge_observed_types_incompatible_deterministic():
    """Verify deterministic conflict resolution for incompatible types."""
    # int + string -> OTHER with sorted native labels
    types_int_str = {
        (StandardDataType.INTEGER, "int"),
        (StandardDataType.STRING, "string"),
    }
    assert merge_observed_types(types_int_str) == (StandardDataType.OTHER, "mixed(int, string)")

    # document + int -> OTHER with sorted native labels
    types_doc_int = {
        (StandardDataType.JSON, "document"),
        (StandardDataType.INTEGER, "int"),
    }
    assert merge_observed_types(types_doc_int) == (StandardDataType.OTHER, "mixed(document, int)")


def test_traverse_document_fields_nested_depth():
    """Verify nested document traversal up to max_depth = 3."""
    doc = {
        "_id": ObjectId("507f1f77bcf86cd799439011"),
        "title": "Project Alpha",
        "metadata": {
            "tier": "gold",
            "audit": {
                "verified": True,
                "deep_nested": {
                    "level_4_key": "hidden_leaf",
                },
            },
        },
    }

    fields = traverse_document_fields(doc, depth=1, prefix="", max_depth=3)
    field_paths = [f[0] for f in fields]

    # Depth 1 paths
    assert "_id" in field_paths
    assert "title" in field_paths
    assert "metadata" in field_paths

    # Depth 2 paths
    assert "metadata.tier" in field_paths
    assert "metadata.audit" in field_paths

    # Depth 3 paths
    assert "metadata.audit.verified" in field_paths
    assert "metadata.audit.deep_nested" in field_paths

    # Depth > 3 MUST NOT be traversed into separate dot-paths
    assert "metadata.audit.deep_nested.level_4_key" not in field_paths

    # When converted to SourceSchema, depth 3 nested dict must map to JSON / document
    schema = build_source_schema_from_mongodb_samples("s1", "src", "db", {"coll": [doc]})
    field_deep = schema.entities[0].get_field("metadata.audit.deep_nested")
    assert field_deep is not None
    assert field_deep.data_type == StandardDataType.JSON
    assert field_deep.native_data_type == "document"


def test_traverse_document_fields_arrays():
    """Verify arrays remain ARRAY and are not flattened into dot-paths."""
    doc = {
        "_id": 1,
        "tags": ["python", "mongodb", "fastapi"],
        "scores": [10, 20, 30],
        "nested_array_obj": [{"name": "item1"}, {"name": "item2"}],
    }

    fields = traverse_document_fields(doc, depth=1, prefix="", max_depth=3)
    field_paths = [f[0] for f in fields]

    assert "tags" in field_paths
    assert "scores" in field_paths
    assert "nested_array_obj" in field_paths

    # Array items must not be exploded as tags.0, tags.1, etc.
    assert "tags.0" not in field_paths
    assert "nested_array_obj.0.name" not in field_paths


def test_build_source_schema_from_empty_collection():
    """Verify empty collections produce explicit inferred default _id and zero fabricated fields."""
    samples = {"empty_coll": []}
    schema = build_source_schema_from_mongodb_samples(
        source_id="src_mongo_1",
        source_name="MongoDB Test",
        database_name="testdb",
        sampled_collections=samples,
    )

    assert schema.entity_count == 1
    entity = schema.entities[0]
    assert entity.name == "empty_coll"
    assert entity.entity_type == "COLLECTION"
    assert len(entity.fields) == 1
    assert entity.comment == "Empty MongoDB collection (observed sample count: 0)"

    id_field = entity.fields[0]
    assert id_field.name == "_id"
    assert id_field.is_primary_key is True
    assert id_field.nullable is False
    assert id_field.position == 1
    assert id_field.native_data_type == "objectId (inferred default)"
    assert id_field.comment == "Inferred default identifier for empty collection (not an observed fact)"
    assert entity.primary_key == ["_id"]


def test_empty_collection_vs_observed_collection_id_provenance():
    """Verify that inferred default _id on empty collections is clearly distinguished from an observed physical ObjectId."""
    samples_empty = {"empty_coll": []}
    samples_observed = {
        "observed_coll": [{"_id": ObjectId("507f1f77bcf86cd799439011"), "value": 42}]
    }

    schema_empty = build_source_schema_from_mongodb_samples("s1", "src", "db", samples_empty)
    schema_observed = build_source_schema_from_mongodb_samples("s1", "src", "db", samples_observed)

    empty_entity = schema_empty.entities[0]
    observed_entity = schema_observed.entities[0]

    # Inferred default _id
    empty_id = empty_entity.get_field("_id")
    assert empty_id is not None
    assert empty_id.native_data_type == "objectId (inferred default)"
    assert empty_id.comment == "Inferred default identifier for empty collection (not an observed fact)"
    assert empty_entity.comment == "Empty MongoDB collection (observed sample count: 0)"

    # Observed physical ObjectId
    observed_id = observed_entity.get_field("_id")
    assert observed_id is not None
    assert observed_id.native_data_type == "objectId"
    assert observed_id.comment is None
    assert observed_entity.comment == "Observed MongoDB collection (sample count: 1)"


def test_build_source_schema_multi_document_field_merging():
    """Verify fields appearing across different documents are merged deterministically."""
    doc1 = {
        "_id": ObjectId("507f1f77bcf86cd799439011"),
        "name": "Alice",
        "email": "alice@example.com",
    }
    doc2 = {
        "_id": ObjectId("507f1f77bcf86cd799439012"),
        "name": "Bob",
        "age": 30,
        "is_active": True,
    }
    doc3 = {
        "_id": ObjectId("507f1f77bcf86cd799439013"),
        "name": "Charlie",
        "balance": Decimal128("150.75"),
    }

    samples = {"users": [doc1, doc2, doc3]}
    schema = build_source_schema_from_mongodb_samples(
        source_id="src_mongo_1",
        source_name="MongoDB Test",
        database_name="testdb",
        sampled_collections=samples,
    )

    entity = schema.entities[0]
    assert entity.name == "users"
    assert entity.entity_type == "COLLECTION"

    field_names = [f.name for f in entity.fields]
    # _id is always first, followed by alphabetical sorting
    assert field_names[0] == "_id"
    assert field_names[1:] == ["age", "balance", "email", "is_active", "name"]

    # Check field nullability: name is in all docs (nullable=False), others missing in some docs (nullable=True)
    f_id = entity.get_field("_id")
    assert f_id is not None
    assert f_id.is_primary_key is True
    assert f_id.nullable is False
    assert f_id.data_type == StandardDataType.STRING
    assert f_id.native_data_type == "objectId"

    f_name = entity.get_field("name")
    assert f_name is not None
    assert f_name.nullable is False
    assert f_name.data_type == StandardDataType.STRING

    f_email = entity.get_field("email")
    assert f_email is not None
    assert f_email.nullable is True

    f_age = entity.get_field("age")
    assert f_age is not None
    assert f_age.nullable is True
    assert f_age.data_type == StandardDataType.INTEGER

    f_balance = entity.get_field("balance")
    assert f_balance is not None
    assert f_balance.nullable is True
    assert f_balance.data_type == StandardDataType.DECIMAL


def test_build_source_schema_mixed_type_order_independence():
    """Verify that document iteration order does not affect mixed-type resolution."""
    doc_int = {"_id": 1, "field_a": 100}
    doc_str = {"_id": 2, "field_a": "100"}

    # Order 1: int first, str second
    samples_1 = {"test_coll": [doc_int, doc_str]}
    schema_1 = build_source_schema_from_mongodb_samples("s1", "src", "db", samples_1)
    field_1 = schema_1.entities[0].get_field("field_a")

    # Order 2: str first, int second
    samples_2 = {"test_coll": [doc_str, doc_int]}
    schema_2 = build_source_schema_from_mongodb_samples("s1", "src", "db", samples_2)
    field_2 = schema_2.entities[0].get_field("field_a")

    assert field_1 is not None and field_2 is not None
    assert field_1.data_type == field_2.data_type == StandardDataType.OTHER
    assert field_1.native_data_type == field_2.native_data_type == "mixed(int, string)"


def test_build_source_schema_explicit_null_tracking():
    """Verify that explicit null values in documents correctly mark fields as nullable."""
    doc1 = {"_id": 1, "profile_pic": None}
    doc2 = {"_id": 2, "profile_pic": "https://example.com/pic.jpg"}

    samples = {"members": [doc1, doc2]}
    schema = build_source_schema_from_mongodb_samples("s1", "src", "db", samples)
    field = schema.entities[0].get_field("profile_pic")

    assert field is not None
    assert field.nullable is True
    assert field.data_type == StandardDataType.STRING
    assert field.native_data_type == "string"


def test_normalize_bson_value_objectid():
    """Verify ObjectId normalizes to canonical 24-char hex string."""
    oid = ObjectId("507f1f77bcf86cd799439011")
    normalized = normalize_bson_value(oid)
    assert normalized == "507f1f77bcf86cd799439011"
    assert isinstance(normalized, str)


def test_normalize_bson_value_decimal128_exact_never_float():
    """Verify Decimal128 normalizes to exact decimal.Decimal, never float."""
    dec = Decimal128("12345.678901234567890123456789")
    normalized = normalize_bson_value(dec)
    assert isinstance(normalized, decimal.Decimal)
    assert not isinstance(normalized, float)
    assert str(normalized) == "12345.678901234567890123456789"

    # Also test Python Decimal is preserved
    std_dec = decimal.Decimal("99.99")
    assert normalize_bson_value(std_dec) == std_dec


def test_normalize_bson_value_datetime_timezone_aware_utc():
    """Verify datetime normalizes to timezone-aware UTC datetime."""
    # Naive datetime
    naive_dt = datetime(2026, 9, 16, 10, 30, 0)
    norm_naive = normalize_bson_value(naive_dt)
    assert isinstance(norm_naive, datetime)
    assert norm_naive.tzinfo == timezone.utc
    assert norm_naive.hour == 10

    # Aware datetime in non-UTC timezone
    offset = timezone(timedelta(hours=5, minutes=30))
    aware_dt = datetime(2026, 9, 16, 15, 30, 0, tzinfo=offset)
    norm_aware = normalize_bson_value(aware_dt)
    assert norm_aware.tzinfo == timezone.utc
    assert norm_aware.hour == 10  # 15:30 +05:30 is 10:00 UTC


def test_normalize_bson_value_timestamp_integer_seconds():
    """Verify BSON Timestamp normalizes to integer seconds."""
    ts = Timestamp(1726477200, 5)
    normalized = normalize_bson_value(ts)
    assert normalized == 1726477200
    assert isinstance(normalized, int)


def test_normalize_bson_value_binary_and_uuid():
    """Verify UUID subtype 4 normalizes to canonical UUID, while subtype 3 & 0 normalize to bytes."""
    u = uuid.UUID("c0a80101-0000-0000-0000-000000000000")

    # UUID object -> canonical uuid.UUID
    assert normalize_bson_value(u) == u

    # Binary subtype 4 -> canonical uuid.UUID
    bin_subtype_4 = Binary(u.bytes, subtype=4)
    norm_sub4 = normalize_bson_value(bin_subtype_4)
    assert isinstance(norm_sub4, uuid.UUID)
    assert norm_sub4 == u

    # Binary subtype 3 (legacy UUID) -> bytes (not UUID)
    bin_subtype_3 = Binary(u.bytes, subtype=3)
    norm_sub3 = normalize_bson_value(bin_subtype_3)
    assert isinstance(norm_sub3, bytes)
    assert norm_sub3 == u.bytes

    # Binary subtype 0 (generic) -> bytes
    bin_gen = Binary(b"\x01\x02\x03\x04", subtype=0)
    norm_gen = normalize_bson_value(bin_gen)
    assert isinstance(norm_gen, bytes)
    assert norm_gen == b"\x01\x02\x03\x04"

    # raw bytes -> bytes
    assert normalize_bson_value(b"raw data") == b"raw data"


def test_normalize_bson_value_nested_documents_and_arrays():
    """Verify recursive normalization of nested documents and arrays."""
    doc = {
        "_id": ObjectId("507f1f77bcf86cd799439011"),
        "balance": Decimal128("500.25"),
        "created_at": datetime(2026, 9, 16, 9, 0, 0),
        "tags": ["alpha", Decimal128("10.5")],
        "profile": {
            "tier": "gold",
            "scores": [Int64(100), Int64(200)],
            "meta": {
                "active": True,
                "null_field": None,
            },
        },
    }

    normalized = normalize_bson_document(doc)

    assert normalized["_id"] == "507f1f77bcf86cd799439011"
    assert isinstance(normalized["balance"], decimal.Decimal)
    assert normalized["balance"] == decimal.Decimal("500.25")
    assert normalized["created_at"] == datetime(2026, 9, 16, 9, 0, 0, tzinfo=timezone.utc)
    assert normalized["tags"][0] == "alpha"
    assert normalized["tags"][1] == decimal.Decimal("10.5")

    assert normalized["profile"]["tier"] == "gold"
    assert normalized["profile"]["scores"] == [100, 200]
    assert normalized["profile"]["meta"]["active"] is True
    assert normalized["profile"]["meta"]["null_field"] is None


def test_extract_columns_from_documents_deterministic():
    """Verify deterministic column extraction with and without projections."""
    docs = [
        {"_id": ObjectId("507f1f77bcf86cd799439011"), "username": "alice", "age": 30},
        {"_id": ObjectId("507f1f77bcf86cd799439012"), "email": "bob@example.com", "username": "bob"},
    ]

    # Without projection: _id first, remaining sorted alphabetically
    cols = extract_columns_from_documents(docs)
    assert cols == ["_id", "age", "email", "username"]

    # With inclusion projection including _id
    proj_with_id = {"_id": 1, "username": 1, "email": 1}
    cols_proj = extract_columns_from_documents(docs, projection=proj_with_id)
    assert cols_proj == ["_id", "username", "email"]

    # With projection suppressing _id: {"_id": 0, "username": 1, "age": 1}
    proj_no_id = {"_id": 0, "username": 1, "age": 1}
    cols_no_id = extract_columns_from_documents(docs, projection=proj_no_id)
    assert cols_no_id == ["username", "age"]

    # Empty documents without projection
    assert extract_columns_from_documents([]) == []

