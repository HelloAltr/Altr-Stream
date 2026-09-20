"""Integration tests for Altr Stream v0.10: Unmapped Entity Auto-Discovery and Resilient Federated Execution."""

from unittest.mock import patch
import pytest
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from altr_stream.domain.logical import LogicalEntity, LogicalField, LogicalModel
from altr_stream.domain.mapping import (
    EntityMapping,
    FieldMapping,
    MappingProvenance,
    MappingStatus,
    SourceMapping,
)
from altr_stream.domain.query import QueryResult
from altr_stream.domain.schema import (
    EntitySchema,
    FieldSchema,
    SourceSchema,
    StandardDataType,
)
from altr_stream.domain.source import Source, SourceStatus, SourceType
from altr_stream.infrastructure.database.registry_repository import SqliteRegistryRepository
from altr_stream.infrastructure.database.repository import SqliteSourceRepository
from altr_stream.query_engine.planning.models import (
    SourceExclusionReason,
    SourceExecutionStatus,
)


@pytest.fixture
async def setup_quad_mixed_environment(test_session: AsyncSession):
    """Setup four sources:
    - PostgreSQL: has 'students' (mapped to College.Student) and 'users' (unmapped)
    - MySQL: has 'students' (mapped to College.Student) and 'users' (unmapped)
    - MongoDB: has 'students' (mapped to College.Student) and 'users' (unmapped, but missing 'department')
    - SQLite: has 'students' (mapped to College.Student), NO 'users' table
    """
    source_repo = SqliteSourceRepository(test_session)
    reg_repo = SqliteRegistryRepository(test_session)

    # 1. PostgreSQL Source
    pg_source = await source_repo.create(
        Source(
            id="src_pg",
            name="PostgreSQL Prod",
            type=SourceType.POSTGRESQL,
            host="localhost",
            port=5432,
            database_name="college_pg",
            status=SourceStatus.ACTIVE,
        )
    )
    pg_schema = SourceSchema(
        source_id=pg_source.id,
        source_name=pg_source.name,
        entities=[
            EntitySchema(
                name="students",
                namespace="public",
                fields=[
                    FieldSchema(name="roll_number", data_type=StandardDataType.INTEGER, native_data_type="INTEGER", is_primary_key=True),
                    FieldSchema(name="full_name", data_type=StandardDataType.STRING, native_data_type="VARCHAR"),
                    FieldSchema(name="email", data_type=StandardDataType.STRING, native_data_type="VARCHAR"),
                    FieldSchema(name="department", data_type=StandardDataType.STRING, native_data_type="VARCHAR"),
                    FieldSchema(name="year", data_type=StandardDataType.INTEGER, native_data_type="INTEGER"),
                    FieldSchema(name="cgpa", data_type=StandardDataType.DECIMAL, native_data_type="NUMERIC"),
                    FieldSchema(name="city", data_type=StandardDataType.STRING, native_data_type="VARCHAR"),
                ],
                primary_key=["roll_number"],
            ),
            EntitySchema(
                name="users",
                namespace="public",
                fields=[
                    FieldSchema(name="id", data_type=StandardDataType.INTEGER, native_data_type="INTEGER", is_primary_key=True),
                    FieldSchema(name="name", data_type=StandardDataType.STRING, native_data_type="VARCHAR"),
                    FieldSchema(name="email", data_type=StandardDataType.STRING, native_data_type="VARCHAR"),
                    FieldSchema(name="city", data_type=StandardDataType.STRING, native_data_type="VARCHAR"),
                    FieldSchema(name="department", data_type=StandardDataType.STRING, native_data_type="VARCHAR"),
                ],
                primary_key=["id"],
            ),
        ],
    )
    await source_repo.save_schema_snapshot(pg_source.id, pg_schema)

    # 2. MySQL Source
    mysql_source = await source_repo.create(
        Source(
            id="src_mysql",
            name="MySQL Prod",
            type=SourceType.MYSQL,
            host="localhost",
            port=3306,
            database_name="college_mysql",
            status=SourceStatus.ACTIVE,
        )
    )
    mysql_schema = SourceSchema(
        source_id=mysql_source.id,
        source_name=mysql_source.name,
        entities=[
            EntitySchema(
                name="students",
                namespace="college_mysql",
                fields=[
                    FieldSchema(name="roll_no", data_type=StandardDataType.INTEGER, native_data_type="INT", is_primary_key=True),
                    FieldSchema(name="student_name", data_type=StandardDataType.STRING, native_data_type="VARCHAR"),
                    FieldSchema(name="email", data_type=StandardDataType.STRING, native_data_type="VARCHAR"),
                    FieldSchema(name="dept", data_type=StandardDataType.STRING, native_data_type="VARCHAR"),
                    FieldSchema(name="year", data_type=StandardDataType.INTEGER, native_data_type="INT"),
                    FieldSchema(name="cgpa", data_type=StandardDataType.DECIMAL, native_data_type="DECIMAL"),
                    FieldSchema(name="city", data_type=StandardDataType.STRING, native_data_type="VARCHAR"),
                ],
                primary_key=["roll_no"],
            ),
            EntitySchema(
                name="users",
                namespace="college_mysql",
                fields=[
                    FieldSchema(name="id", data_type=StandardDataType.INTEGER, native_data_type="INT", is_primary_key=True),
                    FieldSchema(name="name", data_type=StandardDataType.STRING, native_data_type="VARCHAR"),
                    FieldSchema(name="email", data_type=StandardDataType.STRING, native_data_type="VARCHAR"),
                    FieldSchema(name="city", data_type=StandardDataType.STRING, native_data_type="VARCHAR"),
                    FieldSchema(name="department", data_type=StandardDataType.STRING, native_data_type="VARCHAR"),
                    FieldSchema(name="salary", data_type=StandardDataType.DECIMAL, native_data_type="DECIMAL"),
                ],
                primary_key=["id"],
            ),
        ],
    )
    await source_repo.save_schema_snapshot(mysql_source.id, mysql_schema)

    # 3. MongoDB Source
    mongo_source = await source_repo.create(
        Source(
            id="src_mongo",
            name="MongoDB Atlas",
            type=SourceType.MONGODB,
            host="localhost",
            port=27017,
            database_name="college_mongo",
            status=SourceStatus.ACTIVE,
        )
    )
    mongo_schema = SourceSchema(
        source_id=mongo_source.id,
        source_name=mongo_source.name,
        entities=[
            EntitySchema(
                name="students",
                namespace="college_mongo",
                fields=[
                    FieldSchema(name="_id", data_type=StandardDataType.STRING, native_data_type="ObjectId", is_primary_key=True),
                    FieldSchema(name="student_id", data_type=StandardDataType.INTEGER, native_data_type="int"),
                    FieldSchema(name="name", data_type=StandardDataType.STRING, native_data_type="string"),
                    FieldSchema(name="email", data_type=StandardDataType.STRING, native_data_type="string"),
                    FieldSchema(name="dept", data_type=StandardDataType.STRING, native_data_type="string"),
                    FieldSchema(name="academic_year", data_type=StandardDataType.INTEGER, native_data_type="int"),
                    FieldSchema(name="gpa", data_type=StandardDataType.DECIMAL, native_data_type="double"),
                    FieldSchema(name="location", data_type=StandardDataType.STRING, native_data_type="string"),
                ],
                primary_key=["_id"],
            ),
            EntitySchema(
                name="users",
                namespace="college_mongo",
                fields=[
                    FieldSchema(name="_id", data_type=StandardDataType.STRING, native_data_type="ObjectId", is_primary_key=True),
                    FieldSchema(name="id", data_type=StandardDataType.INTEGER, native_data_type="int"),
                    FieldSchema(name="name", data_type=StandardDataType.STRING, native_data_type="string"),
                    FieldSchema(name="email", data_type=StandardDataType.STRING, native_data_type="string"),
                    FieldSchema(name="city", data_type=StandardDataType.STRING, native_data_type="string"),
                ],
                primary_key=["_id"],
            ),
        ],
    )
    await source_repo.save_schema_snapshot(mongo_source.id, mongo_schema)

    # 4. SQLite Source (NO 'users' entity)
    sqlite_source = await source_repo.create(
        Source(
            id="src_sqlite",
            name="SQLite Analytics",
            type=SourceType.SQLITE,
            host="localhost",
            port=0,
            database_name="college.db",
            status=SourceStatus.ACTIVE,
        )
    )
    sqlite_schema = SourceSchema(
        source_id=sqlite_source.id,
        source_name=sqlite_source.name,
        entities=[
            EntitySchema(
                name="students",
                namespace="main",
                fields=[
                    FieldSchema(name="student_id", data_type=StandardDataType.INTEGER, native_data_type="INTEGER", is_primary_key=True),
                    FieldSchema(name="name", data_type=StandardDataType.STRING, native_data_type="TEXT"),
                    FieldSchema(name="email", data_type=StandardDataType.STRING, native_data_type="TEXT"),
                    FieldSchema(name="department", data_type=StandardDataType.STRING, native_data_type="TEXT"),
                    FieldSchema(name="year", data_type=StandardDataType.INTEGER, native_data_type="INTEGER"),
                    FieldSchema(name="gpa", data_type=StandardDataType.DECIMAL, native_data_type="REAL"),
                    FieldSchema(name="city", data_type=StandardDataType.STRING, native_data_type="TEXT"),
                ],
                primary_key=["student_id"],
            )
        ],
    )
    await source_repo.save_schema_snapshot(sqlite_source.id, sqlite_schema)

    # 5. Persistent LogicalModel: College -> Student
    college_model = await reg_repo.create_model(
        LogicalModel(
            name="College",
            entities=[
                LogicalEntity(
                    logical_model_id="",
                    name="Student",
                    fields=[
                        LogicalField(logical_entity_id="", name="roll_number", data_type=StandardDataType.INTEGER, is_primary_key=True),
                        LogicalField(logical_entity_id="", name="name", data_type=StandardDataType.STRING),
                        LogicalField(logical_entity_id="", name="email", data_type=StandardDataType.STRING),
                        LogicalField(logical_entity_id="", name="department", data_type=StandardDataType.STRING),
                        LogicalField(logical_entity_id="", name="year", data_type=StandardDataType.INTEGER),
                        LogicalField(logical_entity_id="", name="cgpa", data_type=StandardDataType.DECIMAL),
                        LogicalField(logical_entity_id="", name="city", data_type=StandardDataType.STRING),
                    ],
                )
            ],
        )
    )
    student_entity = college_model.entities[0]
    fld = {f.name: f.id for f in student_entity.fields}

    # Mappings for Student
    for src, p_entity, f_tuples in [
        (pg_source, "students", [("roll_number", "roll_number"), ("name", "full_name"), ("email", "email"), ("department", "department"), ("year", "year"), ("cgpa", "cgpa"), ("city", "city")]),
        (mysql_source, "students", [("roll_number", "roll_no"), ("name", "student_name"), ("email", "email"), ("department", "dept"), ("year", "year"), ("cgpa", "cgpa"), ("city", "city")]),
        (mongo_source, "students", [("roll_number", "student_id"), ("name", "name"), ("email", "email"), ("department", "dept"), ("year", "academic_year"), ("cgpa", "gpa"), ("city", "location")]),
        (sqlite_source, "students", [("roll_number", "student_id"), ("name", "name"), ("email", "email"), ("department", "department"), ("year", "year"), ("cgpa", "gpa"), ("city", "city")]),
    ]:
        em = EntityMapping(
            id=f"em_{src.id}",
            source_mapping_id=f"map_{src.id}",
            logical_entity_id=student_entity.id,
            logical_entity_name=student_entity.name,
            physical_entity_name=p_entity,
            field_mappings=[
                FieldMapping(
                    id=f"fm_{src.id}_{l}",
                    entity_mapping_id=f"em_{src.id}",
                    logical_field_id=fld[l],
                    logical_field_name=l,
                    physical_field_name=p,
                )
                for l, p in f_tuples
            ],
        )
        sm = SourceMapping(
            id=f"map_{src.id}",
            logical_model_id=college_model.id,
            source_id=src.id,
            status=MappingStatus.ACTIVE,
            provenance=MappingProvenance.USER,
            entity_mappings=[em],
        )
        await reg_repo.create_source_mapping(sm)

    return {
        "pg": pg_source,
        "mysql": mysql_source,
        "mongo": mongo_source,
        "sqlite": sqlite_source,
        "model": college_model,
    }


# ====================================================================
# 1. Unmapped Entity Discovery & Execution (Path B)
# ====================================================================

@pytest.mark.asyncio
async def test_unmapped_entity_auto_discovery_and_federated_execution(
    client: AsyncClient,
    setup_quad_mixed_environment: dict,
):
    """Verify GET users; discovers PG, MySQL, Mongo and excludes SQLite (PHYSICAL_ENTITY_NOT_FOUND)."""
    env = setup_quad_mixed_environment

    mock_pg_data = [{"id": 1, "name": "Alice PG", "email": "alice@pg.com", "city": "Bengaluru", "department": "CS"}]
    mock_my_data = [{"id": 2, "name": "Bob MySQL", "email": "bob@mysql.com", "city": "Mumbai", "department": "EC", "salary": 50000}]
    mock_mg_data = [{"_id": "507f1f77bcf86cd799439011", "id": 3, "name": "Carol Mongo", "email": "carol@mongo.com", "city": "Delhi"}]

    async def mock_execute(source_id, query, **kwargs):
        if source_id == "src_pg":
            return QueryResult(rows=mock_pg_data, columns=["id", "name", "email", "city", "department"], row_count=len(mock_pg_data), execution_time_ms=1.2)
        elif source_id == "src_mysql":
            return QueryResult(rows=mock_my_data, columns=["id", "name", "email", "city", "department", "salary"], row_count=len(mock_my_data), execution_time_ms=1.5)
        elif source_id == "src_mongo":
            return QueryResult(rows=mock_mg_data, columns=["_id", "id", "name", "email", "city"], row_count=len(mock_mg_data), execution_time_ms=2.1)
        return QueryResult(rows=[], columns=[], row_count=0, execution_time_ms=0.5)

    with patch("altr_stream.application.query_service.QueryService.execute_query", side_effect=mock_execute):
        resp = await client.post(
            "/api/v1/altrql/execute",
            json={
                "query": "GET users;",
                "normalize": True,
            },
        )

        assert resp.status_code == 200, resp.text
        data = resp.json()

        assert data["success"] is True
        rows = data["rows"]
        assert len(rows) == 3
        # Common fields should be id, name, email, city (salary omitted, _id omitted)
        for r in rows:
            assert "id" in r
            assert "name" in r
            assert "email" in r
            assert "city" in r
            assert "salary" not in r
            assert "_id" not in r

        # Check telemetry metadata
        meta = data["metadata"]
        assert meta["is_ephemeral"] is True
        assert meta["execution_mode"] == "federated"
        assert meta["row_count"] == 3
        assert meta["source_count"] == 3

        # Included sources should have PG, MySQL, Mongo
        included_ids = {s["source_id"] for s in meta["included_sources"]}
        assert included_ids == {"src_pg", "src_mysql", "src_mongo"}
        for s in meta["included_sources"]:
            assert s["status"] == "SUCCESS"
            assert s["rows"] == 1

        # Excluded sources should have SQLite
        excluded_ids = {s["source_id"] for s in meta["excluded_sources"]}
        assert "src_sqlite" in excluded_ids
        sqlite_ex = next(s for s in meta["excluded_sources"] if s["source_id"] == "src_sqlite")
        assert sqlite_ex["reason_code"] == "PHYSICAL_ENTITY_NOT_FOUND"


# ====================================================================
# 2. Resilient Execution: Partial Source Failure Isolation
# ====================================================================

@pytest.mark.asyncio
async def test_resilient_execution_one_source_fails_others_succeed(
    client: AsyncClient,
    setup_quad_mixed_environment: dict,
):
    """Verify that when Mongo fails with connection timeout, PG and MySQL still return rows successfully."""
    env = setup_quad_mixed_environment

    mock_pg_data = [{"id": 1, "name": "Alice PG", "email": "alice@pg.com", "city": "Bengaluru"}]
    mock_my_data = [{"id": 2, "name": "Bob MySQL", "email": "bob@mysql.com", "city": "Mumbai"}]

    async def mock_execute(source_id, query, **kwargs):
        if source_id == "src_pg":
            return QueryResult(rows=mock_pg_data, columns=["id", "name", "email", "city"], row_count=1, execution_time_ms=1.1)
        elif source_id == "src_mysql":
            return QueryResult(rows=mock_my_data, columns=["id", "name", "email", "city"], row_count=1, execution_time_ms=1.4)
        elif source_id == "src_mongo":
            raise ConnectionRefusedError("MongoDB server unreachable at localhost:27017")
        return QueryResult(rows=[], columns=[], row_count=0, execution_time_ms=0.5)

    with patch("altr_stream.application.query_service.QueryService.execute_query", side_effect=mock_execute):
        resp = await client.post(
            "/api/v1/altrql/execute",
            json={
                "query": "GET users;",
                "normalize": True,
            },
        )

        assert resp.status_code == 200, resp.text
        data = resp.json()

        assert data["success"] is True
        assert len(data["rows"]) == 2

        meta = data["metadata"]
        assert meta["is_ephemeral"] is True
        assert meta["row_count"] == 2

        # Included sources should show PG (SUCCESS), MySQL (SUCCESS)
        included_map = {s["source_id"]: s for s in meta["included_sources"]}
        assert included_map["src_pg"]["status"] == "SUCCESS"
        assert included_map["src_pg"]["rows"] == 1
        assert included_map["src_mysql"]["status"] == "SUCCESS"
        assert included_map["src_mysql"]["rows"] == 1

        # Excluded/failed sources should show Mongo (FAILED) and SQLite (EXCLUDED)
        excluded_map = {s["source_id"]: s for s in meta["excluded_sources"]}
        assert excluded_map["src_mongo"]["status"] == "FAILED"
        assert excluded_map["src_mongo"]["reason_code"] == "SOURCE_UNREACHABLE"
        assert "unreachable" in excluded_map["src_mongo"]["message"].lower()

        assert excluded_map["src_sqlite"]["status"] == "EXCLUDED"
        assert excluded_map["src_sqlite"]["reason_code"] == "PHYSICAL_ENTITY_NOT_FOUND"


# ====================================================================
# 3. Explicit Field Selection with Missing Field Exclusion
# ====================================================================

@pytest.mark.asyncio
async def test_explicit_field_missing_in_one_source_exclusion(
    client: AsyncClient,
    setup_quad_mixed_environment: dict,
):
    """Verify GET users (id, name, department); excludes MongoDB because it lacks 'department'."""
    env = setup_quad_mixed_environment

    mock_pg_data = [{"id": 1, "name": "Alice PG", "department": "CS"}]
    mock_my_data = [{"id": 2, "name": "Bob MySQL", "department": "EC"}]

    async def mock_execute(source_id, query, **kwargs):
        if source_id == "src_pg":
            return QueryResult(rows=mock_pg_data, columns=["id", "name", "department"], row_count=1, execution_time_ms=1.0)
        elif source_id == "src_mysql":
            return QueryResult(rows=mock_my_data, columns=["id", "name", "department"], row_count=1, execution_time_ms=1.2)
        return QueryResult(rows=[], columns=[], row_count=0, execution_time_ms=0.5)

    with patch("altr_stream.application.query_service.QueryService.execute_query", side_effect=mock_execute):
        resp = await client.post(
            "/api/v1/altrql/execute",
            json={
                "query": "GET users (id, name, department);",
                "normalize": True,
            },
        )

        assert resp.status_code == 200, resp.text
        data = resp.json()

        assert data["success"] is True
        assert len(data["rows"]) == 2
        meta = data["metadata"]

        # Participating sources should be PG and MySQL
        included_ids = {s["source_id"] for s in meta["included_sources"]}
        assert included_ids == {"src_pg", "src_mysql"}

        # Excluded sources should include Mongo (INCOMPLETE_FIELD_MAPPING) and SQLite (PHYSICAL_ENTITY_NOT_FOUND)
        excluded_map = {s["source_id"]: s for s in meta["excluded_sources"]}
        assert "src_mongo" in excluded_map
        assert excluded_map["src_mongo"]["reason_code"] == "INCOMPLETE_FIELD_MAPPING"
        assert "department" in excluded_map["src_mongo"]["message"]

        assert "src_sqlite" in excluded_map
        assert excluded_map["src_sqlite"]["reason_code"] == "PHYSICAL_ENTITY_NOT_FOUND"


# ====================================================================
# 4. Zero Rows Returned from Participating Sources
# ====================================================================

@pytest.mark.asyncio
async def test_participating_sources_zero_rows_returned(
    client: AsyncClient,
    setup_quad_mixed_environment: dict,
):
    """Verify that if participating sources return 0 rows, it is a success with row_count=0."""
    async def mock_empty_exec(source_id, query, **kwargs):
        return QueryResult(rows=[], columns=["id", "name", "email", "city"], row_count=0, execution_time_ms=1.0)

    with patch("altr_stream.application.query_service.QueryService.execute_query", side_effect=mock_empty_exec):
        resp = await client.post(
            "/api/v1/altrql/execute",
            json={
                "query": "GET users WHERE { id > 9999 };",
                "normalize": True,
            },
        )

        assert resp.status_code == 200, resp.text
        data = resp.json()

        assert data["success"] is True
        assert data["rows"] == []
        meta = data["metadata"]
        assert meta["row_count"] == 0
        assert meta["source_count"] == 3
        for s in meta["included_sources"]:
            assert s["status"] == "SUCCESS"
            assert s["rows"] == 0


# ====================================================================
# 5. All Sources Excluded or Failed
# ====================================================================

@pytest.mark.asyncio
async def test_entity_not_found_on_any_source(
    client: AsyncClient,
    setup_quad_mixed_environment: dict,
):
    """Verify that querying a nonexistent entity returns success=False and structured error."""
    resp = await client.post(
        "/api/v1/altrql/execute",
        json={
            "query": "GET non_existent_table_xyz;",
            "normalize": True,
        },
    )

    assert resp.status_code == 200
    data = resp.json()
    assert data["success"] is False
    assert data["error"] is not None
    assert "not found" in data["error"]["message"].lower() or "no active source mapping" in data["error"]["message"].lower()


@pytest.mark.asyncio
async def test_all_participating_sources_fail_returns_structured_error(
    client: AsyncClient,
    setup_quad_mixed_environment: dict,
):
    """Verify that if all participating sources fail during execution, a structured FederatedExecutionFailedError is returned."""
    async def mock_fail_exec(source_id, query, **kwargs):
        raise RuntimeError("Database connection crashed")

    with patch("altr_stream.application.query_service.QueryService.execute_query", side_effect=mock_fail_exec):
        resp = await client.post(
            "/api/v1/altrql/execute",
            json={
                "query": "GET users;",
                "normalize": True,
            },
        )

        assert resp.status_code == 200
        data = resp.json()
        assert data["success"] is False
        assert data["error"] is not None
        assert data["error"]["type"] == "FederatedExecutionFailedError"
        assert "failed during query execution" in data["error"]["message"].lower()


# ====================================================================
# 6. Global Sorting and Pagination over Ephemeral Results
# ====================================================================

@pytest.mark.asyncio
async def test_ephemeral_global_sorting_and_pagination(
    client: AsyncClient,
    setup_quad_mixed_environment: dict,
):
    """Verify deterministic sorting and global pagination over ephemeral multi-source results."""
    # PG rows
    mock_pg = [
        {"id": 1, "name": "Alice", "email": "alice@a.com", "city": "Bengaluru"},
        {"id": 4, "name": "David", "email": "david@d.com", "city": "Chennai"},
    ]
    # MySQL rows
    mock_my = [
        {"id": 2, "name": "Bob", "email": "bob@b.com", "city": "Mumbai"},
        {"id": 5, "name": "Eve", "email": "eve@e.com", "city": "Hyderabad"},
    ]
    # Mongo rows
    mock_mg = [
        {"_id": "1", "id": 3, "name": "Charlie", "email": "charlie@c.com", "city": "Delhi"},
        {"_id": "2", "id": 6, "name": "Frank", "email": "frank@f.com", "city": "Kolkata"},
    ]

    async def mock_exec(source_id, query, **kwargs):
        if source_id == "src_pg":
            return QueryResult(rows=mock_pg, columns=["id", "name", "email", "city"], row_count=2, execution_time_ms=1.0)
        elif source_id == "src_mysql":
            return QueryResult(rows=mock_my, columns=["id", "name", "email", "city"], row_count=2, execution_time_ms=1.0)
        elif source_id == "src_mongo":
            return QueryResult(rows=mock_mg, columns=["_id", "id", "name", "email", "city"], row_count=2, execution_time_ms=1.0)
        return QueryResult(rows=[], columns=[], row_count=0, execution_time_ms=0.5)

    with patch("altr_stream.application.query_service.QueryService.execute_query", side_effect=mock_exec):
        # Total rows: 6 (Alice, Bob, Charlie, David, Eve, Frank).
        # Request SORT { name ASC } LIMIT 3 OFFSET 2 -> should return [Charlie, David, Eve]
        resp = await client.post(
            "/api/v1/altrql/execute",
            json={
                "query": "GET users SORT { name ASC } LIMIT 3 OFFSET 2;",
                "normalize": True,
            },
        )

        assert resp.status_code == 200, resp.text
        data = resp.json()

        assert data["success"] is True
        rows = data["rows"]
        assert len(rows) == 3
        names = [r["name"] for r in rows]
        assert names == ["Charlie", "David", "Eve"]


# ====================================================================
# 7. Bind and Plan Endpoints Expose Ephemeral Metadata
# ====================================================================

@pytest.mark.asyncio
async def test_bind_and_plan_endpoints_ephemeral_metadata(
    client: AsyncClient,
    setup_quad_mixed_environment: dict,
):
    """Verify /bind and /plan endpoints return is_ephemeral=True and source participation."""
    # 1. Test /bind
    resp_bind = await client.post(
        "/api/v1/altrql/bind",
        json={"query": "GET users;"},
    )
    assert resp_bind.status_code == 200, resp_bind.text
    bind_data = resp_bind.json()
    assert bind_data["is_ephemeral"] is True
    assert bind_data["ephemeral_projection"] is not None
    assert bind_data["ephemeral_projection"]["entity_name"] == "users"

    # 2. Test /plan
    resp_plan = await client.post(
        "/api/v1/altrql/plan",
        json={"query": "GET users;"},
    )
    assert resp_plan.status_code == 200, resp_plan.text
    plan_data = resp_plan.json()
    assert plan_data["is_ephemeral"] is True
    assert len(plan_data["physical_plans"]) == 3
    assert len(plan_data["excluded_sources"]) == 1
    assert plan_data["excluded_sources"][0]["source_id"] == "src_sqlite"


# ====================================================================
# 8. Path A Regression Verification
# ====================================================================

@pytest.mark.asyncio
async def test_path_a_registered_logical_model_regression(
    client: AsyncClient,
    setup_quad_mixed_environment: dict,
):
    """Verify GET students; under registered model operates via Path A with is_ephemeral=False."""
    env = setup_quad_mixed_environment

    mock_pg = [{"roll_number": 101, "full_name": "Alice", "email": "a@c.com", "department": "CS", "year": 4, "cgpa": 9.2, "city": "BLR"}]
    mock_my = [{"roll_no": 102, "student_name": "Bob", "email": "b@c.com", "dept": "EC", "year": 3, "cgpa": 8.8, "city": "MUM"}]
    mock_mg = [{"_id": "1", "student_id": 103, "name": "Carol", "email": "c@c.com", "dept": "CS", "academic_year": 2, "gpa": 9.0, "location": "DEL"}]
    mock_sq = [{"student_id": 104, "name": "David", "email": "d@c.com", "department": "ME", "year": 1, "gpa": 8.5, "city": "HYD"}]

    async def mock_exec(source_id, query, **kwargs):
        if source_id == "src_pg":
            return QueryResult(rows=mock_pg, columns=list(mock_pg[0].keys()), row_count=1, execution_time_ms=1.0)
        elif source_id == "src_mysql":
            return QueryResult(rows=mock_my, columns=list(mock_my[0].keys()), row_count=1, execution_time_ms=1.0)
        elif source_id == "src_mongo":
            return QueryResult(rows=mock_mg, columns=list(mock_mg[0].keys()), row_count=1, execution_time_ms=1.0)
        elif source_id == "src_sqlite":
            return QueryResult(rows=mock_sq, columns=list(mock_sq[0].keys()), row_count=1, execution_time_ms=1.0)
        return QueryResult(rows=[], columns=[], row_count=0, execution_time_ms=0.5)

    with patch("altr_stream.application.query_service.QueryService.execute_query", side_effect=mock_exec):
        resp = await client.post(
            "/api/v1/altrql/execute",
            json={
                "query": "GET students;",
                "logical_model_id": env["model"].id,
                "normalize": True,
            },
        )

        assert resp.status_code == 200, resp.text
        data = resp.json()

        assert data["success"] is True
        assert len(data["rows"]) == 4
        meta = data["metadata"]
        assert meta["is_ephemeral"] is False
        assert meta["row_count"] == 4
        assert meta["source_count"] == 4
        assert len(meta["included_sources"]) == 4
        assert len(meta["excluded_sources"]) == 0
