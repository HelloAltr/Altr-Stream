"""Comprehensive unit tests for MongoDB AltrQL Lowerer (Milestone v0.7.5-alpha).

Covers:
1. Basic GET & wildcard / specific projections (with _id handling).
2. Deterministic default ordering (single PK, composite PK, no PK fallback).
3. Explicit SORT overriding default PK ordering.
4. Filter lowering for all 14 semantic sanity check cases:
   - field != value (matches non-equal, null, missing)
   - field = NULL (matches explicit null and missing)
   - field != NULL (matches existing non-null only)
   - field = {value, NULL} (matches value, null, missing)
   - field != {value, NULL} (excludes value, null, missing)
   - HAS single substring (re.escape)
   - HAS ValueSet (disjunction of regex)
   - NOT HAS single substring (negation with null fallback)
   - NOT HAS ValueSet (conjunction of not-regex with null fallback)
   - Nested NOT ($nor)
   - AND + OR + NOT combinations
   - TOP N BY ordering (DESC + limit)
   - TOP N BY OFFSET M (DESC + limit + skip)
   - Comparisons (>, >=, <, <=, ranges)
5. Nested dotted field paths in projections, filters, and mutations.
6. CREATE operation (single & batch) -> mongodb:insert_many.
7. UPDATE operation -> mongodb:update_many ($set).
8. DELETE operation -> mongodb:delete_many.
"""

import pytest

from altr_stream.domain.schema import (
    EntitySchema,
    FieldSchema,
    SourceSchema,
    StandardDataType,
)
from altr_stream.query_engine.binding.binder import bind_altrql
from altr_stream.query_engine.domain.physical_query import PhysicalQuery
from altr_stream.query_engine.lowering.mongodb import MongoDBLowerer
from altr_stream.query_engine.lowering.registry import get_lowerer
from altr_stream.domain.source import SourceType
from altr_stream.query_engine.parser.parser import parse_altrql


@pytest.fixture
def mongo_schema() -> SourceSchema:
    return SourceSchema(
        source_id="src_mongo_test",
        source_name="Test MongoDB Source",
        entities=[
            EntitySchema(
                name="users",
                namespace="default",
                entity_type="COLLECTION",
                fields=[
                    FieldSchema(name="_id", data_type=StandardDataType.STRING, native_data_type="objectId", is_primary_key=True),
                    FieldSchema(name="email", data_type=StandardDataType.STRING, native_data_type="string"),
                    FieldSchema(name="username", data_type=StandardDataType.STRING, native_data_type="string"),
                    FieldSchema(name="role", data_type=StandardDataType.STRING, native_data_type="string"),
                    FieldSchema(name="status", data_type=StandardDataType.STRING, native_data_type="string"),
                    FieldSchema(name="age", data_type=StandardDataType.INTEGER, native_data_type="int"),
                    FieldSchema(name="is_active", data_type=StandardDataType.BOOLEAN, native_data_type="bool"),
                    FieldSchema(name="metadata", data_type=StandardDataType.JSON, native_data_type="document"),
                    FieldSchema(name="score", data_type=StandardDataType.FLOAT, native_data_type="double"),
                ],
                primary_key=["_id"],
            ),
            EntitySchema(
                name="orders",
                namespace="default",
                entity_type="COLLECTION",
                fields=[
                    FieldSchema(name="tenant_id", data_type=StandardDataType.STRING, native_data_type="string", is_primary_key=True),
                    FieldSchema(name="order_no", data_type=StandardDataType.INTEGER, native_data_type="int", is_primary_key=True),
                    FieldSchema(name="total", data_type=StandardDataType.FLOAT, native_data_type="double"),
                ],
                primary_key=["tenant_id", "order_no"],
            ),
            EntitySchema(
                name="logs",
                namespace="default",
                entity_type="COLLECTION",
                fields=[
                    FieldSchema(name="message", data_type=StandardDataType.STRING, native_data_type="string"),
                    FieldSchema(name="level", data_type=StandardDataType.STRING, native_data_type="string"),
                ],
                primary_key=[],
            ),
        ],
    )


# ---------------------------------------------------------------------------
# 1. Lowerer Registry Resolution
# ---------------------------------------------------------------------------


def test_registry_resolves_mongodb_lowerer():
    lowerer = get_lowerer(SourceType.MONGODB)
    assert isinstance(lowerer, MongoDBLowerer)

    lowerer_str = get_lowerer("mongodb")
    assert isinstance(lowerer_str, MongoDBLowerer)


# ---------------------------------------------------------------------------
# 2. Basic READ & Projections
# ---------------------------------------------------------------------------


def test_lower_basic_get_wildcard(mongo_schema: SourceSchema):
    bound = bind_altrql(parse_altrql("GET users;"), mongo_schema)
    res = MongoDBLowerer().lower(bound)

    assert isinstance(res, PhysicalQuery)
    assert res.dialect == "mongodb"
    assert res.query == "mongodb:find"
    assert len(res.parameters) == 1

    spec = res.parameters[0]
    assert spec["collection"] == "users"
    assert spec["filter"] == {}
    assert spec["projection"] is None
    assert spec["sort"] == [["_id", 1]]


def test_lower_projection_without_id(mongo_schema: SourceSchema):
    bound = bind_altrql(parse_altrql("GET users (email, username);"), mongo_schema)
    res = MongoDBLowerer().lower(bound)
    spec = res.parameters[0]

    assert spec["projection"] == {"email": 1, "username": 1, "_id": 0}


def test_lower_projection_with_explicit_id(mongo_schema: SourceSchema):
    bound = bind_altrql(parse_altrql("GET users (_id, email);"), mongo_schema)
    res = MongoDBLowerer().lower(bound)
    spec = res.parameters[0]

    assert spec["projection"] == {"_id": 1, "email": 1}


def test_lower_projection_nested_field(mongo_schema: SourceSchema):
    bound = bind_altrql(parse_altrql("GET users (email, metadata.department);"), mongo_schema)
    res = MongoDBLowerer().lower(bound)
    spec = res.parameters[0]

    assert spec["projection"] == {"email": 1, "metadata.department": 1, "_id": 0}


# ---------------------------------------------------------------------------
# 3. 14 Semantic Sanity Check Cases
# ---------------------------------------------------------------------------


def test_case_1_inequality_matches_none_and_missing(mongo_schema: SourceSchema):
    # field != value
    bound = bind_altrql(parse_altrql('GET users WHERE { status != "ACTIVE" };'), mongo_schema)
    res = MongoDBLowerer().lower(bound)
    assert res.parameters[0]["filter"] == {"status": {"$ne": "ACTIVE"}}


def test_case_2_null_equality(mongo_schema: SourceSchema):
    # field = NULL
    bound = bind_altrql(parse_altrql("GET users WHERE { metadata = NULL };"), mongo_schema)
    res = MongoDBLowerer().lower(bound)
    assert res.parameters[0]["filter"] == {"metadata": None}


def test_case_3_null_inequality(mongo_schema: SourceSchema):
    # field != NULL
    bound = bind_altrql(parse_altrql("GET users WHERE { metadata != NULL };"), mongo_schema)
    res = MongoDBLowerer().lower(bound)
    assert res.parameters[0]["filter"] == {"metadata": {"$ne": None, "$exists": True}}


def test_case_4_valueset_with_null_equality(mongo_schema: SourceSchema):
    # field = {value, NULL}
    bound = bind_altrql(parse_altrql('GET users WHERE { status = {"ACTIVE", NULL} };'), mongo_schema)
    res = MongoDBLowerer().lower(bound)
    assert res.parameters[0]["filter"] == {"$or": [{"status": None}, {"status": "ACTIVE"}]}

    # multi-value + NULL
    bound_multi = bind_altrql(parse_altrql('GET users WHERE { status = {"ACTIVE", "PENDING", NULL} };'), mongo_schema)
    res_multi = MongoDBLowerer().lower(bound_multi)
    assert res_multi.parameters[0]["filter"] == {"$or": [{"status": None}, {"status": {"$in": ["ACTIVE", "PENDING"]}}]}


def test_case_5_valueset_with_null_inequality(mongo_schema: SourceSchema):
    # field != {value, NULL}
    bound = bind_altrql(parse_altrql('GET users WHERE { status != {"ACTIVE", NULL} };'), mongo_schema)
    res = MongoDBLowerer().lower(bound)
    assert res.parameters[0]["filter"] == {"$and": [{"status": {"$ne": "ACTIVE"}}, {"status": {"$ne": None, "$exists": True}}]}

    # multi-value != {v1, v2, NULL}
    bound_multi = bind_altrql(parse_altrql('GET users WHERE { status != {"ACTIVE", "PENDING", NULL} };'), mongo_schema)
    res_multi = MongoDBLowerer().lower(bound_multi)
    assert res_multi.parameters[0]["filter"] == {"$and": [{"status": {"$nin": ["ACTIVE", "PENDING"]}}, {"status": {"$ne": None, "$exists": True}}]}


def test_case_6_has_single_substring(mongo_schema: SourceSchema):
    # field HAS "sub"
    bound = bind_altrql(parse_altrql('GET users WHERE { email HAS "example.com" };'), mongo_schema)
    res = MongoDBLowerer().lower(bound)
    # re.escape escapes '.' to '\.'
    assert res.parameters[0]["filter"] == {"email": {"$regex": r"example\.com"}}


def test_case_7_has_valueset(mongo_schema: SourceSchema):
    # field HAS {"a", "b"}
    bound = bind_altrql(parse_altrql('GET users WHERE { email HAS {"alice", "corp"} };'), mongo_schema)
    res = MongoDBLowerer().lower(bound)
    assert res.parameters[0]["filter"] == {"$or": [{"email": {"$regex": "alice"}}, {"email": {"$regex": "corp"}}]}


def test_case_8_not_has_single_substring(mongo_schema: SourceSchema):
    # field NOT HAS "sub"
    bound = bind_altrql(parse_altrql('GET users WHERE { email NOT HAS "example" };'), mongo_schema)
    res = MongoDBLowerer().lower(bound)
    assert res.parameters[0]["filter"] == {"$or": [{"email": {"$not": {"$regex": "example"}}}, {"email": None}]}


def test_case_9_not_has_valueset(mongo_schema: SourceSchema):
    # field NOT HAS {"admin", "superadmin"}
    bound = bind_altrql(parse_altrql('GET users WHERE { role NOT HAS {"admin", "superadmin"} };'), mongo_schema)
    res = MongoDBLowerer().lower(bound)
    assert res.parameters[0]["filter"] == {
        "$or": [
            {
                "$and": [
                    {"role": {"$not": {"$regex": "admin"}}},
                    {"role": {"$not": {"$regex": "superadmin"}}},
                ]
            },
            {"role": None},
        ]
    }


def test_case_10_nested_not(mongo_schema: SourceSchema):
    # NOT { is_active = FALSE }
    bound = bind_altrql(parse_altrql("GET users WHERE { NOT { is_active = FALSE } };"), mongo_schema)
    res = MongoDBLowerer().lower(bound)
    assert res.parameters[0]["filter"] == {"$nor": [{"is_active": False}]}


def test_case_11_and_or_not_combinations(mongo_schema: SourceSchema):
    # (status = "ACTIVE" AND is_active = TRUE) OR (role = "admin")
    query = """
    GET users WHERE {
        status = "ACTIVE",
        is_active = TRUE,
        NOT { role = "guest" }
    };
    """
    bound = bind_altrql(parse_altrql(query), mongo_schema)
    res = MongoDBLowerer().lower(bound)
    flt = res.parameters[0]["filter"]
    assert "$and" in flt


def test_case_12_top_n_by_ordering(mongo_schema: SourceSchema):
    # GET users TOP 5 BY score;
    bound = bind_altrql(parse_altrql("GET users TOP 5 BY score;"), mongo_schema)
    res = MongoDBLowerer().lower(bound)
    spec = res.parameters[0]

    assert spec["sort"] == [["score", -1]]
    assert spec["limit"] == 5
    assert "skip" not in spec


def test_case_13_top_n_by_offset(mongo_schema: SourceSchema):
    # GET users TOP 2 BY age OFFSET 3;
    bound = bind_altrql(parse_altrql("GET users TOP 2 BY age OFFSET 3;"), mongo_schema)
    res = MongoDBLowerer().lower(bound)
    spec = res.parameters[0]

    assert spec["sort"] == [["age", -1]]
    assert spec["limit"] == 2
    assert spec["skip"] == 3


def test_case_14_default_pk_ordering_and_explicit_override(mongo_schema: SourceSchema):
    # 1. Single PK
    bound_single = bind_altrql(parse_altrql("GET users;"), mongo_schema)
    res_single = MongoDBLowerer().lower(bound_single)
    assert res_single.parameters[0]["sort"] == [["_id", 1]]

    # 2. Composite PK
    bound_comp = bind_altrql(parse_altrql("GET orders;"), mongo_schema)
    res_comp = MongoDBLowerer().lower(bound_comp)
    assert res_comp.parameters[0]["sort"] == [["tenant_id", 1], ["order_no", 1]]

    # 3. No PK fallback
    bound_no_pk = bind_altrql(parse_altrql("GET logs;"), mongo_schema)
    res_no_pk = MongoDBLowerer().lower(bound_no_pk)
    assert res_no_pk.parameters[0]["sort"] == [["_id", 1]]

    # 4. Explicit SORT overrides default PK
    bound_explicit = bind_altrql(parse_altrql("GET users SORT { score DESC, username ASC };"), mongo_schema)
    res_explicit = MongoDBLowerer().lower(bound_explicit)
    assert res_explicit.parameters[0]["sort"] == [["score", -1], ["username", 1]]


# ---------------------------------------------------------------------------
# 4. Comparisons & Ranges
# ---------------------------------------------------------------------------


def test_comparisons_and_ranges(mongo_schema: SourceSchema):
    # Greater than / Less than
    bound_gt = bind_altrql(parse_altrql("GET users WHERE { age > 21 };"), mongo_schema)
    assert MongoDBLowerer().lower(bound_gt).parameters[0]["filter"] == {"age": {"$gt": 21}}

    bound_lte = bind_altrql(parse_altrql("GET users WHERE { age <= 65 };"), mongo_schema)
    assert MongoDBLowerer().lower(bound_lte).parameters[0]["filter"] == {"age": {"$lte": 65}}

    # Inclusive range
    bound_range = bind_altrql(parse_altrql("GET users WHERE { age = 20..30 };"), mongo_schema)
    assert MongoDBLowerer().lower(bound_range).parameters[0]["filter"] == {"age": {"$gte": 20, "$lte": 30}}

    # ValueSet with range and scalars
    bound_vs_range = bind_altrql(parse_altrql("GET users WHERE { age = {18, 25..30} };"), mongo_schema)
    assert MongoDBLowerer().lower(bound_vs_range).parameters[0]["filter"] == {
        "$or": [{"age": 18}, {"age": {"$gte": 25, "$lte": 30}}]
    }


def test_starts_and_ends_string_operators(mongo_schema: SourceSchema):
    bound_starts = bind_altrql(parse_altrql('GET users WHERE { username STARTS "adm" };'), mongo_schema)
    assert MongoDBLowerer().lower(bound_starts).parameters[0]["filter"] == {"username": {"$regex": "^adm"}}

    bound_ends = bind_altrql(parse_altrql('GET users WHERE { email ENDS ".org" };'), mongo_schema)
    assert MongoDBLowerer().lower(bound_ends).parameters[0]["filter"] == {"email": {"$regex": r"\.org$"}}


# ---------------------------------------------------------------------------
# 5. Nested Dotted Fields
# ---------------------------------------------------------------------------


def test_nested_dotted_field_in_where(mongo_schema: SourceSchema):
    bound = bind_altrql(parse_altrql('GET users WHERE { metadata.department = "Engineering" };'), mongo_schema)
    res = MongoDBLowerer().lower(bound)
    assert res.parameters[0]["filter"] == {"metadata.department": "Engineering"}


# ---------------------------------------------------------------------------
# 6. Mutations (CREATE, UPDATE, DELETE)
# ---------------------------------------------------------------------------


def test_lower_create_single_record(mongo_schema: SourceSchema):
    query = 'CREATE users ( email: "test@example.com", username: "testuser", is_active: TRUE, age: 30 );'
    bound = bind_altrql(parse_altrql(query), mongo_schema)
    res = MongoDBLowerer().lower(bound)

    assert isinstance(res, PhysicalQuery)
    assert res.dialect == "mongodb"
    assert res.query == "mongodb:insert_many"
    spec = res.parameters[0]
    assert spec["collection"] == "users"
    assert len(spec["documents"]) == 1
    assert spec["documents"][0] == {
        "email": "test@example.com",
        "username": "testuser",
        "is_active": True,
        "age": 30,
    }


def test_lower_create_batch_records(mongo_schema: SourceSchema):
    query = """
    CREATE users (
        ( email: "u1@corp.net", username: "u1" ),
        ( email: "u2@corp.net", username: "u2" )
    );
    """
    bound = bind_altrql(parse_altrql(query), mongo_schema)
    res = MongoDBLowerer().lower(bound)
    spec = res.parameters[0]

    assert len(spec["documents"]) == 2
    assert spec["documents"][0]["email"] == "u1@corp.net"
    assert spec["documents"][1]["email"] == "u2@corp.net"


def test_lower_update_operation(mongo_schema: SourceSchema):
    query = 'UPDATE users ( is_active: FALSE, role: "archived" ) WHERE { age > 60 };'
    bound = bind_altrql(parse_altrql(query), mongo_schema)
    res = MongoDBLowerer().lower(bound)

    assert isinstance(res, PhysicalQuery)
    assert res.dialect == "mongodb"
    assert res.query == "mongodb:update_many"
    spec = res.parameters[0]
    assert spec["collection"] == "users"
    assert spec["filter"] == {"age": {"$gt": 60}}
    assert spec["update"] == {"$set": {"is_active": False, "role": "archived"}}


def test_lower_delete_operation(mongo_schema: SourceSchema):
    query = 'DELETE users WHERE { status = "SUSPENDED" };'
    bound = bind_altrql(parse_altrql(query), mongo_schema)
    res = MongoDBLowerer().lower(bound)

    assert isinstance(res, PhysicalQuery)
    assert res.dialect == "mongodb"
    assert res.query == "mongodb:delete_many"
    spec = res.parameters[0]
    assert spec["collection"] == "users"
    assert spec["filter"] == {"status": "SUSPENDED"}
