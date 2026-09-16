"""Live integration tests for MongoDB physical query execution and result normalization against a live MongoDB container."""

import asyncio
from datetime import datetime, timezone
import decimal
import uuid

import bson
from bson import Binary, Decimal128, ObjectId
from bson.timestamp import Timestamp
import pytest
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

from altr_stream.application.query_service import QueryService
from altr_stream.domain.errors import QueryExecutionError
from altr_stream.domain.source import ConnectionConfig, Source, SourceStatus, SourceType
from altr_stream.infrastructure.connectors.mongodb.connector import MongoDBConnector
from altr_stream.infrastructure.database.models import Base
from altr_stream.infrastructure.database.repository import SqliteSourceRepository

MONGO_CONFIG = ConnectionConfig(
    host="localhost",
    port=27017,
    database_name="altr_test_db",
    username="altr_test_user",
    password="altr_test_pass",
    options={"authSource": "admin"},
)


async def _is_mongodb_available() -> bool:
    """Check if MongoDB test container is reachable on localhost:27017."""
    try:
        conn = MongoDBConnector(MONGO_CONFIG, timeout_sec=2.0)
        res = await conn.test_connection()
        return res.success
    except Exception:
        return False


@pytest.fixture(scope="module")
def event_loop():
    loop = asyncio.new_event_loop()
    yield loop
    loop.close()


@pytest.mark.asyncio
async def test_mongodb_live_insert_many_and_find_normalization():
    """Verify live insert_many and find execution with full BSON type normalization."""
    if not await _is_mongodb_available():
        pytest.skip("MongoDB test container not available on port 27017")

    connector = MongoDBConnector(MONGO_CONFIG)
    await connector.initialize()

    coll_name = "test_live_exec_norm"
    db = connector._client["altr_test_db"]
    coll = db[coll_name]
    await coll.delete_many({})

    try:
        custom_oid = ObjectId("507f1f77bcf86cd799439099")
        test_uuid = uuid.UUID("a1b2c3d4-e5f6-4a5b-8c9d-0e1f2a3b4c5d")
        test_dt = datetime(2026, 9, 16, 12, 0, 0, tzinfo=timezone.utc)
        test_ts = Timestamp(1726488000, 1)
        test_bin_sub4 = Binary(test_uuid.bytes, subtype=4)
        test_bin_sub3 = Binary(b"\xaa" * 16, subtype=3)
        test_bin_sub0 = Binary(b"\x01\x02\x03\x04", subtype=0)

        # 1. CREATE: insert_many
        insert_spec = {
            "collection": coll_name,
            "documents": [
                {
                    "_id": custom_oid,
                    "username": "charlie",
                    "balance": Decimal128("12345.6789"),
                    "created_at": test_dt,
                    "op_timestamp": test_ts,
                    "uuid_sub4": test_bin_sub4,
                    "bin_sub3": test_bin_sub3,
                    "bin_sub0": test_bin_sub0,
                    "raw_bytes": b"binary_data",
                    "profile": {
                        "tier": "platinum",
                        "score": 98.5,
                        "verified": True,
                    },
                    "tags": ["premium", "vip"],
                    "age": 28,
                },
                {
                    "username": "david",
                    "balance": Decimal128("50.00"),
                    "age": 35,
                },
            ],
            "ordered": True,
        }

        insert_res = await connector.execute_query("mongodb:insert_many", parameters=[insert_spec])
        assert insert_res.row_count == 2
        assert insert_res.affected_rows == 2
        assert insert_res.columns == ["_id"]
        assert len(insert_res.rows) == 2
        assert insert_res.rows[0]["_id"] == "507f1f77bcf86cd799439099"
        assert isinstance(insert_res.rows[1]["_id"], str)
        assert len(insert_res.rows[1]["_id"]) == 24

        # 2. READ: find with filter, projection, sort
        find_spec = {
            "collection": coll_name,
            "filter": {"username": "charlie"},
            "projection": {
                "_id": 1,
                "username": 1,
                "balance": 1,
                "created_at": 1,
                "op_timestamp": 1,
                "uuid_sub4": 1,
                "bin_sub3": 1,
                "bin_sub0": 1,
                "raw_bytes": 1,
                "profile": 1,
                "tags": 1,
                "age": 1,
            },
            "sort": [("_id", 1)],
            "limit": 5,
            "skip": 0,
        }

        find_res = await connector.execute_query("mongodb:find", parameters=[find_spec])
        assert find_res.row_count == 1
        assert find_res.affected_rows is None
        assert find_res.columns[0] == "_id"
        assert "username" in find_res.columns
        assert "balance" in find_res.columns

        row = find_res.rows[0]

        # Normalization Verification
        # ObjectId -> canonical string
        assert row["_id"] == "507f1f77bcf86cd799439099"
        assert isinstance(row["_id"], str)

        # Decimal128 -> decimal.Decimal (NEVER float)
        assert isinstance(row["balance"], decimal.Decimal)
        assert not isinstance(row["balance"], float)
        assert row["balance"] == decimal.Decimal("12345.6789")

        # datetime -> timezone-aware UTC datetime
        assert isinstance(row["created_at"], datetime)
        assert row["created_at"].tzinfo == timezone.utc
        assert row["created_at"] == test_dt

        # Timestamp -> integer seconds
        assert isinstance(row["op_timestamp"], int)
        assert row["op_timestamp"] == 1726488000

        # UUID / Subtype 4 -> canonical uuid.UUID
        assert isinstance(row["uuid_sub4"], uuid.UUID)
        assert row["uuid_sub4"] == test_uuid

        # Binary Subtype 3 & Subtype 0 & raw bytes -> bytes
        assert isinstance(row["bin_sub3"], bytes)
        assert row["bin_sub3"] == b"\xaa" * 16
        assert isinstance(row["bin_sub0"], bytes)
        assert row["bin_sub0"] == b"\x01\x02\x03\x04"
        assert isinstance(row["raw_bytes"], bytes)
        assert row["raw_bytes"] == b"binary_data"

        # Embedded document -> dict
        assert isinstance(row["profile"], dict)
        assert row["profile"]["tier"] == "platinum"
        assert row["profile"]["score"] == 98.5
        assert row["profile"]["verified"] is True

        # Array -> list
        assert isinstance(row["tags"], list)
        assert row["tags"] == ["premium", "vip"]

        # Primitives
        assert row["username"] == "charlie"
        assert row["age"] == 28

    finally:
        await coll.delete_many({})
        await connector.close()


@pytest.mark.asyncio
async def test_mongodb_live_update_many():
    """Verify live update_many modifies documents and reports affected rows accurately."""
    if not await _is_mongodb_available():
        pytest.skip("MongoDB test container not available on port 27017")

    connector = MongoDBConnector(MONGO_CONFIG)
    await connector.initialize()

    coll_name = "test_live_exec_update"
    db = connector._client["altr_test_db"]
    coll = db[coll_name]
    await coll.delete_many({})

    try:
        # Seed 3 documents
        await coll.insert_many([
            {"user_id": 1, "status": "pending", "points": 10},
            {"user_id": 2, "status": "pending", "points": 20},
            {"user_id": 3, "status": "active", "points": 30},
        ])

        update_spec = {
            "collection": coll_name,
            "filter": {"status": "pending"},
            "update": {"$set": {"status": "active"}, "$inc": {"points": 5}},
            "upsert": False,
        }

        res = await connector.execute_query("mongodb:update_many", parameters=[update_spec])
        assert res.row_count == 0
        assert res.affected_rows == 2
        assert res.columns == []
        assert res.rows == []
        assert "Updated 2 document(s)" in (res.message or "")

        # Verify documents updated in database
        updated_docs = await coll.find({"status": "active"}).to_list(length=10)
        assert len(updated_docs) == 3

    finally:
        await coll.delete_many({})
        await connector.close()


@pytest.mark.asyncio
async def test_mongodb_live_delete_many():
    """Verify live delete_many deletes matching documents and reports affected rows accurately."""
    if not await _is_mongodb_available():
        pytest.skip("MongoDB test container not available on port 27017")

    connector = MongoDBConnector(MONGO_CONFIG)
    await connector.initialize()

    coll_name = "test_live_exec_delete"
    db = connector._client["altr_test_db"]
    coll = db[coll_name]
    await coll.delete_many({})

    try:
        # Seed 4 documents
        await coll.insert_many([
            {"task": "t1", "completed": True},
            {"task": "t2", "completed": True},
            {"task": "t3", "completed": False},
            {"task": "t4", "completed": True},
        ])

        delete_spec = {
            "collection": coll_name,
            "filter": {"completed": True},
        }

        res = await connector.execute_query("mongodb:delete_many", parameters=[delete_spec])
        assert res.row_count == 0
        assert res.affected_rows == 3
        assert res.columns == []
        assert res.rows == []
        assert "Deleted 3 document(s)" in (res.message or "")

        remaining = await coll.find({}).to_list(length=10)
        assert len(remaining) == 1
        assert remaining[0]["task"] == "t3"

    finally:
        await coll.delete_many({})
        await connector.close()


@pytest.mark.asyncio
async def test_mongodb_live_execute_batch():
    """Verify live execute_batch executes sequential operations and returns combined metrics."""
    if not await _is_mongodb_available():
        pytest.skip("MongoDB test container not available on port 27017")

    connector = MongoDBConnector(MONGO_CONFIG)
    await connector.initialize()

    coll_name = "test_live_exec_batch"
    db = connector._client["altr_test_db"]
    coll = db[coll_name]
    await coll.delete_many({})

    try:
        batch = [
            (
                "mongodb:insert_many",
                [{"collection": coll_name, "documents": [{"key": "k1", "val": 10}, {"key": "k2", "val": 20}]}],
            ),
            (
                "mongodb:update_many",
                [{"collection": coll_name, "filter": {"key": "k1"}, "update": {"$set": {"val": 15}}}],
            ),
            (
                "mongodb:delete_many",
                [{"collection": coll_name, "filter": {"key": "k2"}}],
            ),
        ]

        res = await connector.execute_batch(batch)
        assert res.affected_rows == 4  # 2 inserted + 1 updated + 1 deleted

        remaining = await coll.find({}).to_list(length=10)
        assert len(remaining) == 1
        assert remaining[0]["key"] == "k1"
        assert remaining[0]["val"] == 15

    finally:
        await coll.delete_many({})
        await connector.close()


@pytest.mark.asyncio
async def test_mongodb_live_query_service_execution():
    """Verify QueryService executes MongoDB command specifications against a registered MongoDB source."""
    if not await _is_mongodb_available():
        pytest.skip("MongoDB test container not available on port 27017")

    engine = create_async_engine("sqlite+aiosqlite:///:memory:", echo=False)
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)

    session_factory = async_sessionmaker(engine, expire_on_commit=False, class_=AsyncSession)
    async with session_factory() as session:
        repo = SqliteSourceRepository(session)
        service = QueryService(repo)

        source = Source(
            name="Live MongoDB Exec Source",
            type=SourceType.MONGODB,
            host="localhost",
            port=27017,
            database_name="altr_test_db",
            username="altr_test_user",
            password="altr_test_pass",
            options={"authSource": "admin"},
            status=SourceStatus.ACTIVE,
        )
        created_source = await repo.create(source)
        await session.commit()

        # Execute insert via QueryService
        insert_spec = {
            "collection": "test_service_exec",
            "documents": [{"item": "widget", "qty": 5}],
        }
        ins_res = await service.execute_query(
            created_source.id,
            "mongodb:insert_many",
            parameters=[insert_spec],
        )
        assert ins_res.row_count == 1
        assert ins_res.affected_rows == 1

        # Execute find via QueryService
        find_spec = {
            "collection": "test_service_exec",
            "filter": {"item": "widget"},
        }
        find_res = await service.execute_query(
            created_source.id,
            "mongodb:find",
            parameters=[find_spec],
        )
        assert find_res.row_count == 1
        assert find_res.rows[0]["item"] == "widget"
        assert find_res.rows[0]["qty"] == 5

        # Cleanup
        del_spec = {"collection": "test_service_exec", "filter": {}}
        await service.execute_query(
            created_source.id,
            "mongodb:delete_many",
            parameters=[del_spec],
        )


@pytest.mark.asyncio
async def test_mongodb_live_playground_raw_json_queries():
    """Verify QueryService parses and executes raw Playground JSON queries against live MongoDB container."""
    if not await _is_mongodb_available():
        pytest.skip("MongoDB test container not available on port 27017")

    engine = create_async_engine("sqlite+aiosqlite:///:memory:", echo=False)
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)

    session_factory = async_sessionmaker(engine, expire_on_commit=False, class_=AsyncSession)
    async with session_factory() as session:
        repo = SqliteSourceRepository(session)
        service = QueryService(repo)

        source = Source(
            name="Live MongoDB Playground Source",
            type=SourceType.MONGODB,
            host="localhost",
            port=27017,
            database_name="altr_test_db",
            username="altr_test_user",
            password="altr_test_pass",
            options={"authSource": "admin"},
            status=SourceStatus.ACTIVE,
        )
        created_source = await repo.create(source)
        await session.commit()

        coll_name = "test_playground_live_exec"

        # 1. Insert documents using Playground JSON query (without parameters argument)
        insert_query = f"""{{
            "collection": "{coll_name}",
            "documents": [
                {{"username": "carol", "role": "engineer", "score": 95}},
                {{"username": "dave", "role": "designer", "score": 88}}
            ]
        }}"""
        ins_res = await service.execute_query(created_source.id, insert_query)
        assert ins_res.affected_rows == 2

        # 2. Find documents using standard Playground JSON query: {"collection": "...", "filter": {}}
        find_query = f"""{{
            "collection": "{coll_name}",
            "filter": {{"role": "engineer"}},
            "projection": {{"_id": 1, "username": 1, "score": 1}}
        }}"""
        find_res = await service.execute_query(created_source.id, find_query)
        assert find_res.row_count == 1
        assert find_res.columns == ["_id", "username", "score"]
        assert find_res.rows[0]["username"] == "carol"
        assert find_res.rows[0]["score"] == 95

        # 3. Find with sort and limit
        all_query = f"""{{
            "collection": "{coll_name}",
            "filter": {{}},
            "sort": [["score", -1]],
            "limit": 10
        }}"""
        all_res = await service.execute_query(created_source.id, all_query)
        assert all_res.row_count == 2
        assert all_res.rows[0]["username"] == "carol"
        assert all_res.rows[1]["username"] == "dave"

        # 4. Cleanup with delete query
        del_query = f"""{{
            "operation": "delete_many",
            "collection": "{coll_name}",
            "filter": {{}}
        }}"""
        del_res = await service.execute_query(created_source.id, del_query)
        assert del_res.affected_rows == 2


@pytest.mark.asyncio
async def test_mongodb_live_playground_shell_queries():
    """Verify QueryService parses and executes live MongoDB Shell queries (db.collection.find().pretty(), sort, limit, mutations)."""
    if not await _is_mongodb_available():
        pytest.skip("MongoDB test container not available on port 27017")

    engine = create_async_engine("sqlite+aiosqlite:///:memory:", echo=False)
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)

    session_factory = async_sessionmaker(engine, expire_on_commit=False, class_=AsyncSession)
    async with session_factory() as session:
        repo = SqliteSourceRepository(session)
        service = QueryService(repo)

        source = Source(
            name="Live MongoDB Shell Playground Source",
            type=SourceType.MONGODB,
            host="localhost",
            port=27017,
            database_name="altr_test_db",
            username="altr_test_user",
            password="altr_test_pass",
            options={"authSource": "admin"},
            status=SourceStatus.ACTIVE,
        )
        created_source = await repo.create(source)
        await session.commit()

        coll_name = "test_shell_live_exec"

        # 1. Insert documents using MongoDB Shell insertMany
        insert_query = f"""db.{coll_name}.insertMany([
            {{ username: "emma", role: "lead", age: 32 }},
            {{ username: "frank", role: "qa", age: 29 }}
        ])"""
        ins_res = await service.execute_query(created_source.id, insert_query, mode="shell")
        assert ins_res.affected_rows == 2
        assert len(ins_res.rows) == 2

        # 2. Find using db.coll.find().pretty()
        find_query = f"db.{coll_name}.find().pretty()"
        find_res = await service.execute_query(created_source.id, find_query, mode="shell")
        assert find_res.row_count == 2
        assert "_id" in find_res.columns
        assert "username" in find_res.columns

        # 3. Find with filter, sort, limit
        filter_query = f'db.{coll_name}.find({{ role: "lead" }}).sort({{ age: -1 }}).limit(1)'
        filter_res = await service.execute_query(created_source.id, filter_query, mode="shell")
        assert filter_res.row_count == 1
        assert filter_res.rows[0]["username"] == "emma"
        assert filter_res.rows[0]["age"] == 32

        # 4. Update using updateMany
        update_query = f'db.{coll_name}.updateMany({{ role: "qa" }}, {{ $set: {{ status: "verified" }} }})'
        upd_res = await service.execute_query(created_source.id, update_query, mode="shell")
        assert upd_res.affected_rows == 1

        # 5. Delete using deleteMany
        del_query = f"db.{coll_name}.deleteMany({{}})"
        del_res = await service.execute_query(created_source.id, del_query, mode="shell")
        assert del_res.affected_rows == 2


