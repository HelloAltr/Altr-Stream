"""Unit tests for the deterministic MongoDB Shell parser."""

from datetime import datetime, timezone
import decimal
import uuid

import bson
from bson import Decimal128, ObjectId, Timestamp
import pytest

from altr_stream.domain.errors import QueryExecutionError
from altr_stream.infrastructure.connectors.mongodb.shell_parser import (
    parse_mongodb_shell_query,
)


def test_parse_basic_find():
    """Test db.users.find() with no arguments."""
    op, spec = parse_mongodb_shell_query("db.users.find()")
    assert op == "mongodb:find"
    assert spec == {"collection": "users", "filter": {}}


def test_parse_find_with_pretty():
    """Test db.users.find().pretty() produces identical physical command as without pretty."""
    op, spec = parse_mongodb_shell_query("db.users.find().pretty()")
    assert op == "mongodb:find"
    assert spec == {"collection": "users", "filter": {}}


def test_parse_find_with_filter():
    """Test db.users.find with a single filter predicate."""
    op, spec = parse_mongodb_shell_query('db.users.find({ username: "alice" })')
    assert op == "mongodb:find"
    assert spec == {"collection": "users", "filter": {"username": "alice"}}


def test_parse_find_with_multiple_predicates_and_operators():
    """Test db.users.find with nested operators and multiple fields."""
    query = """
    db.users.find({
        status: "active",
        age: { $gte: 18, $lte: 65 },
        roles: { $in: ["admin", "staff"] }
    })
    """
    op, spec = parse_mongodb_shell_query(query)
    assert op == "mongodb:find"
    assert spec == {
        "collection": "users",
        "filter": {
            "status": "active",
            "age": {"$gte": 18, "$lte": 65},
            "roles": {"$in": ["admin", "staff"]},
        },
    }


def test_parse_find_with_projection():
    """Test db.users.find with filter and projection."""
    query = 'db.users.find({ status: "active" }, { username: 1, age: 1, _id: 0 })'
    op, spec = parse_mongodb_shell_query(query)
    assert op == "mongodb:find"
    assert spec == {
        "collection": "users",
        "filter": {"status": "active"},
        "projection": {"username": 1, "age": 1, "_id": 0},
    }


def test_parse_find_with_sort_asc_and_desc():
    """Test db.users.find().sort(...) with ascending and descending sort directions."""
    op1, spec1 = parse_mongodb_shell_query("db.users.find().sort({ age: 1 })")
    assert op1 == "mongodb:find"
    assert spec1 == {"collection": "users", "filter": {}, "sort": {"age": 1}}

    op2, spec2 = parse_mongodb_shell_query("db.users.find().sort({ age: -1, username: 1 })")
    assert op2 == "mongodb:find"
    assert spec2 == {"collection": "users", "filter": {}, "sort": {"age": -1, "username": 1}}


def test_parse_find_with_skip_and_limit():
    """Test db.users.find().skip(5).limit(10)."""
    op, spec = parse_mongodb_shell_query("db.users.find().skip(5).limit(10)")
    assert op == "mongodb:find"
    assert spec == {"collection": "users", "filter": {}, "skip": 5, "limit": 10}


def test_parse_find_chained_all_modifiers():
    """Test db.users.find with filter, sort, skip, limit, and pretty."""
    query = """
    db.users.find({ status: "active" })
        .sort({ created_at: -1 })
        .skip(10)
        .limit(20)
        .pretty();
    """
    op, spec = parse_mongodb_shell_query(query)
    assert op == "mongodb:find"
    assert spec == {
        "collection": "users",
        "filter": {"status": "active"},
        "sort": {"created_at": -1},
        "skip": 10,
        "limit": 20,
    }


def test_parse_insert_many():
    """Test db.users.insertMany([...])."""
    query = """
    db.users.insertMany([
        { name: "alice", age: 25, active: true },
        { name: "bob", age: 30, active: false, tags: ["developer"] }
    ])
    """
    op, spec = parse_mongodb_shell_query(query)
    assert op == "mongodb:insert_many"
    assert spec == {
        "collection": "users",
        "documents": [
            {"name": "alice", "age": 25, "active": True},
            {"name": "bob", "age": 30, "active": False, "tags": ["developer"]},
        ],
        "ordered": True,
    }


def test_parse_insert_many_with_ordered_option():
    """Test db.users.insertMany([...], { ordered: false })."""
    query = 'db.users.insertMany([{ name: "alice" }], { ordered: false })'
    op, spec = parse_mongodb_shell_query(query)
    assert op == "mongodb:insert_many"
    assert spec == {
        "collection": "users",
        "documents": [{"name": "alice"}],
        "ordered": False,
    }


def test_parse_update_many():
    """Test db.users.updateMany(filter, update)."""
    query = """
    db.users.updateMany(
        { status: "pending" },
        { $set: { status: "processed", processed_at: null } }
    )
    """
    op, spec = parse_mongodb_shell_query(query)
    assert op == "mongodb:update_many"
    assert spec == {
        "collection": "users",
        "filter": {"status": "pending"},
        "update": {"$set": {"status": "processed", "processed_at": None}},
    }


def test_parse_update_many_with_upsert():
    """Test db.users.updateMany(filter, update, { upsert: true })."""
    query = """
    db.users.updateMany(
        { email: "new@example.com" },
        { $set: { verified: true } },
        { upsert: true }
    )
    """
    op, spec = parse_mongodb_shell_query(query)
    assert op == "mongodb:update_many"
    assert spec == {
        "collection": "users",
        "filter": {"email": "new@example.com"},
        "update": {"$set": {"verified": True}},
        "upsert": True,
    }


def test_parse_delete_many():
    """Test db.users.deleteMany(filter)."""
    query = 'db.users.deleteMany({ status: "inactive" });'
    op, spec = parse_mongodb_shell_query(query)
    assert op == "mongodb:delete_many"
    assert spec == {
        "collection": "users",
        "filter": {"status": "inactive"},
    }


def test_parse_bson_constructors():
    """Test parsing BSON constructors (ObjectId, ISODate, UUID, Decimal128, Timestamp)."""
    query = """
    db.orders.find({
        _id: ObjectId("507f1f77bcf86cd799439011"),
        created_at: ISODate("2026-09-16T10:00:00Z"),
        account_id: UUID("12345678-1234-5678-1234-567812345678"),
        total: Decimal128("99.99"),
        ts: Timestamp(1700000000, 2)
    })
    """
    op, spec = parse_mongodb_shell_query(query)
    assert op == "mongodb:find"
    filter_doc = spec["filter"]

    assert isinstance(filter_doc["_id"], ObjectId)
    assert str(filter_doc["_id"]) == "507f1f77bcf86cd799439011"

    assert isinstance(filter_doc["created_at"], datetime)
    assert filter_doc["created_at"] == datetime(2026, 9, 16, 10, 0, 0, tzinfo=timezone.utc)

    assert isinstance(filter_doc["account_id"], uuid.UUID)
    assert filter_doc["account_id"] == uuid.UUID("12345678-1234-5678-1234-567812345678")

    assert isinstance(filter_doc["total"], Decimal128)
    assert filter_doc["total"] == Decimal128("99.99")

    assert isinstance(filter_doc["ts"], Timestamp)
    assert filter_doc["ts"].time == 1700000000
    assert filter_doc["ts"].inc == 2


def test_parse_malformed_syntax_errors():
    """Test that malformed shell syntax produces clear descriptive errors."""
    # 1. Unclosed parenthesis
    with pytest.raises(QueryExecutionError) as exc1:
        parse_mongodb_shell_query("db.users.find(")
    assert "Invalid MongoDB shell syntax" in str(exc1.value)

    # 2. Missing collection
    with pytest.raises(QueryExecutionError) as exc2:
        parse_mongodb_shell_query("db..find()")
    assert "Invalid MongoDB shell syntax" in str(exc2.value)

    # 3. Not starting with db
    with pytest.raises(QueryExecutionError) as exc3:
        parse_mongodb_shell_query("users.find()")
    assert "must begin with 'db.<collection>.<operation>()'" in str(exc3.value)

    # 4. Unterminated string
    with pytest.raises(QueryExecutionError) as exc4:
        parse_mongodb_shell_query('db.users.find({ username: "alice })')
    assert "Unterminated string literal" in str(exc4.value)

    # 5. Unterminated object
    with pytest.raises(QueryExecutionError) as exc5:
        parse_mongodb_shell_query("db.users.find({ age: 25")
    assert "Invalid MongoDB shell syntax" in str(exc5.value)


def test_parse_unsupported_expressions_and_functions():
    """Test that unsupported JS expressions or functions are safely rejected."""
    # 1. .map() on find cursor
    with pytest.raises(QueryExecutionError) as exc1:
        parse_mongodb_shell_query("db.users.find().map(x => x.name)")
    assert "Unsupported MongoDB shell expression" in str(exc1.value)

    # 2. Arbitrary JS function call
    with pytest.raises(QueryExecutionError) as exc2:
        parse_mongodb_shell_query("someRandomJavascript()")
    assert "must begin with 'db.<collection>.<operation>()'" in str(exc2.value)

    # 3. Unsupported operation on collection
    with pytest.raises(QueryExecutionError) as exc3:
        parse_mongodb_shell_query("db.users.dropDatabase()")
    assert "Unsupported collection operation 'dropDatabase'" in str(exc3.value)

    # 4. Chained modifier on write operation
    with pytest.raises(QueryExecutionError) as exc4:
        parse_mongodb_shell_query('db.users.deleteMany({}).sort({ id: 1 })')
    assert "Chained modifier 'sort()' is not supported on write operation 'deleteMany()'" in str(exc4.value)

    # 6. .count() cursor modifier (not part of v0.7.4 physical contract)
    with pytest.raises(QueryExecutionError) as exc6:
        parse_mongodb_shell_query("db.users.find().count()")
    assert "'count()' is not a supported cursor modifier" in str(exc6.value)

    # 7. Single-document mutations (not part of v0.7.4 physical contract)
    with pytest.raises(QueryExecutionError) as exc7a:
        parse_mongodb_shell_query('db.users.insertOne({ name: "Alice" })')
    assert "Unsupported collection operation 'insertOne'" in str(exc7a.value)

    with pytest.raises(QueryExecutionError) as exc7b:
        parse_mongodb_shell_query('db.users.updateOne({ name: "Alice" }, { $set: { age: 30 } })')
    assert "Unsupported collection operation 'updateOne'" in str(exc7b.value)

    with pytest.raises(QueryExecutionError) as exc7c:
        parse_mongodb_shell_query('db.users.deleteOne({ name: "Alice" })')
    assert "Unsupported collection operation 'deleteOne'" in str(exc7c.value)


def test_parse_empty_query():
    """Test empty query raises QueryExecutionError."""
    with pytest.raises(QueryExecutionError) as exc:
        parse_mongodb_shell_query("   ")
    assert "Query cannot be empty" in str(exc.value)

