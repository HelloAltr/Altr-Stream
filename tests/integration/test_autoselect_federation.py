"""Integration tests for Altr Stream v0.9 Auto-Select / All Sources federated execution and entity resolution."""

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


@pytest.fixture
async def setup_quad_college_environment(test_session: AsyncSession):
    """Setup four sources (PostgreSQL, MySQL, SQLite, MongoDB) mapped to College.Student."""
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
            )
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
            )
        ],
    )
    await source_repo.save_schema_snapshot(mysql_source.id, mysql_schema)

    # 3. SQLite Source
    sqlite_source = await source_repo.create(
        Source(
            id="src_sqlite",
            name="SQLite Local",
            type=SourceType.SQLITE,
            file_path="/tmp/college.db",
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

    # 4. MongoDB Source
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
                    FieldSchema(name="rollNumber", data_type=StandardDataType.INTEGER, native_data_type="int"),
                    FieldSchema(name="name", data_type=StandardDataType.STRING, native_data_type="string"),
                    FieldSchema(name="email", data_type=StandardDataType.STRING, native_data_type="string"),
                    FieldSchema(name="dept", data_type=StandardDataType.STRING, native_data_type="string"),
                    FieldSchema(name="year", data_type=StandardDataType.INTEGER, native_data_type="int"),
                    FieldSchema(name="cgpa", data_type=StandardDataType.DECIMAL, native_data_type="double"),
                    FieldSchema(name="city", data_type=StandardDataType.STRING, native_data_type="string"),
                ],
                primary_key=["_id"],
            )
        ],
    )
    await source_repo.save_schema_snapshot(mongo_source.id, mongo_schema)

    # Logical Model: College with Logical Entity: Student
    lf_roll = LogicalField(logical_entity_id="", name="roll_number", data_type=StandardDataType.INTEGER, is_primary_key=True)
    lf_name = LogicalField(logical_entity_id="", name="name", data_type=StandardDataType.STRING)
    lf_email = LogicalField(logical_entity_id="", name="email", data_type=StandardDataType.STRING)
    lf_dept = LogicalField(logical_entity_id="", name="department", data_type=StandardDataType.STRING)
    lf_year = LogicalField(logical_entity_id="", name="year", data_type=StandardDataType.INTEGER)
    lf_cgpa = LogicalField(logical_entity_id="", name="cgpa", data_type=StandardDataType.DECIMAL)
    lf_city = LogicalField(logical_entity_id="", name="city", data_type=StandardDataType.STRING)

    le_student = LogicalEntity(
        logical_model_id="",
        name="Student",
        fields=[lf_roll, lf_name, lf_email, lf_dept, lf_year, lf_cgpa, lf_city],
    )

    college_model = await reg_repo.create_model(
        LogicalModel(name="College", entities=[le_student])
    )
    student_entity = college_model.entities[0]
    fld = {f.name: f.id for f in student_entity.fields}

    # Active Mapping 1: PG
    await reg_repo.create_source_mapping(
        SourceMapping(
            id="map_pg",
            logical_model_id=college_model.id,
            source_id=pg_source.id,
            status=MappingStatus.ACTIVE,
            entity_mappings=[
                EntityMapping(
                    source_mapping_id="",
                    logical_entity_id=student_entity.id,
                    logical_entity_name=student_entity.name,
                    physical_entity_name="students",
                    physical_namespace="public",
                    field_mappings=[
                        FieldMapping(entity_mapping_id="", logical_field_id=fld["roll_number"], logical_field_name="roll_number", physical_field_name="roll_number"),
                        FieldMapping(entity_mapping_id="", logical_field_id=fld["name"], logical_field_name="name", physical_field_name="full_name"),
                        FieldMapping(entity_mapping_id="", logical_field_id=fld["email"], logical_field_name="email", physical_field_name="email"),
                        FieldMapping(entity_mapping_id="", logical_field_id=fld["department"], logical_field_name="department", physical_field_name="department"),
                        FieldMapping(entity_mapping_id="", logical_field_id=fld["year"], logical_field_name="year", physical_field_name="year"),
                        FieldMapping(entity_mapping_id="", logical_field_id=fld["cgpa"], logical_field_name="cgpa", physical_field_name="cgpa"),
                        FieldMapping(entity_mapping_id="", logical_field_id=fld["city"], logical_field_name="city", physical_field_name="city"),
                    ],
                )
            ],
        )
    )

    # Active Mapping 2: MySQL
    await reg_repo.create_source_mapping(
        SourceMapping(
            id="map_mysql",
            logical_model_id=college_model.id,
            source_id=mysql_source.id,
            status=MappingStatus.ACTIVE,
            entity_mappings=[
                EntityMapping(
                    source_mapping_id="",
                    logical_entity_id=student_entity.id,
                    logical_entity_name=student_entity.name,
                    physical_entity_name="students",
                    physical_namespace="college_mysql",
                    field_mappings=[
                        FieldMapping(entity_mapping_id="", logical_field_id=fld["roll_number"], logical_field_name="roll_number", physical_field_name="roll_no"),
                        FieldMapping(entity_mapping_id="", logical_field_id=fld["name"], logical_field_name="name", physical_field_name="student_name"),
                        FieldMapping(entity_mapping_id="", logical_field_id=fld["email"], logical_field_name="email", physical_field_name="email"),
                        FieldMapping(entity_mapping_id="", logical_field_id=fld["department"], logical_field_name="department", physical_field_name="dept"),
                        FieldMapping(entity_mapping_id="", logical_field_id=fld["year"], logical_field_name="year", physical_field_name="year"),
                        FieldMapping(entity_mapping_id="", logical_field_id=fld["cgpa"], logical_field_name="cgpa", physical_field_name="cgpa"),
                        FieldMapping(entity_mapping_id="", logical_field_id=fld["city"], logical_field_name="city", physical_field_name="city"),
                    ],
                )
            ],
        )
    )

    # Active Mapping 3: SQLite
    await reg_repo.create_source_mapping(
        SourceMapping(
            id="map_sqlite",
            logical_model_id=college_model.id,
            source_id=sqlite_source.id,
            status=MappingStatus.ACTIVE,
            entity_mappings=[
                EntityMapping(
                    source_mapping_id="",
                    logical_entity_id=student_entity.id,
                    logical_entity_name=student_entity.name,
                    physical_entity_name="students",
                    physical_namespace="main",
                    field_mappings=[
                        FieldMapping(entity_mapping_id="", logical_field_id=fld["roll_number"], logical_field_name="roll_number", physical_field_name="student_id"),
                        FieldMapping(entity_mapping_id="", logical_field_id=fld["name"], logical_field_name="name", physical_field_name="name"),
                        FieldMapping(entity_mapping_id="", logical_field_id=fld["email"], logical_field_name="email", physical_field_name="email"),
                        FieldMapping(entity_mapping_id="", logical_field_id=fld["department"], logical_field_name="department", physical_field_name="department"),
                        FieldMapping(entity_mapping_id="", logical_field_id=fld["year"], logical_field_name="year", physical_field_name="year"),
                        FieldMapping(entity_mapping_id="", logical_field_id=fld["cgpa"], logical_field_name="cgpa", physical_field_name="gpa"),
                        FieldMapping(entity_mapping_id="", logical_field_id=fld["city"], logical_field_name="city", physical_field_name="city"),
                    ],
                )
            ],
        )
    )

    # Active Mapping 4: MongoDB
    await reg_repo.create_source_mapping(
        SourceMapping(
            id="map_mongo",
            logical_model_id=college_model.id,
            source_id=mongo_source.id,
            status=MappingStatus.ACTIVE,
            entity_mappings=[
                EntityMapping(
                    source_mapping_id="",
                    logical_entity_id=student_entity.id,
                    logical_entity_name=student_entity.name,
                    physical_entity_name="students",
                    physical_namespace="college_mongo",
                    field_mappings=[
                        FieldMapping(entity_mapping_id="", logical_field_id=fld["roll_number"], logical_field_name="roll_number", physical_field_name="rollNumber"),
                        FieldMapping(entity_mapping_id="", logical_field_id=fld["name"], logical_field_name="name", physical_field_name="name"),
                        FieldMapping(entity_mapping_id="", logical_field_id=fld["email"], logical_field_name="email", physical_field_name="email"),
                        FieldMapping(entity_mapping_id="", logical_field_id=fld["department"], logical_field_name="department", physical_field_name="dept"),
                        FieldMapping(entity_mapping_id="", logical_field_id=fld["year"], logical_field_name="year", physical_field_name="year"),
                        FieldMapping(entity_mapping_id="", logical_field_id=fld["cgpa"], logical_field_name="cgpa", physical_field_name="cgpa"),
                        FieldMapping(entity_mapping_id="", logical_field_id=fld["city"], logical_field_name="city", physical_field_name="city"),
                    ],
                )
            ],
        )
    )

    return {
        "model": college_model,
        "pg": pg_source,
        "mysql": mysql_source,
        "sqlite": sqlite_source,
        "mongo": mongo_source,
    }


@pytest.mark.asyncio
async def test_autoselect_entity_resolution_and_multi_source_planning(
    client: AsyncClient, setup_quad_college_environment
):
    """Verify 'GET students;' successfully resolves against logical entity 'Student' and creates 4 physical plans."""
    # Test Auto-Select (no source_id, no logical_model_id provided)
    payload = {
        "query": "GET students;",
    }

    res = await client.post("/api/v1/altrql/plan", json=payload)
    assert res.status_code == 200
    data = res.json()
    assert data["success"] is True, f"Plan failed: {data.get('error')}"
    assert data["execution_mode"] == "federated"
    assert data["total_sources_planned"] == 4

    source_ids = {p["source_id"] for p in data["physical_plans"]}
    assert source_ids == {"src_pg", "src_mysql", "src_sqlite", "src_mongo"}


@pytest.mark.asyncio
async def test_autoselect_case_insensitive_and_singular_plural_variants(
    client: AsyncClient, setup_quad_college_environment
):
    """Verify STUDENTS, student, Student, and students all resolve consistently in Auto-Select mode."""
    variants = ["GET STUDENTS;", "GET student;", "GET Student;", "GET students;"]
    for q in variants:
        res = await client.post("/api/v1/altrql/plan", json={"query": q})
        assert res.status_code == 200
        data = res.json()
        assert data["success"] is True, f"Failed for query '{q}': {data.get('error')}"
        assert data["total_sources_planned"] == 4


@pytest.mark.asyncio
async def test_autoselect_federated_execution_and_normalization(
    client: AsyncClient, setup_quad_college_environment
):
    """Verify Auto-Select executes across all 4 databases and returns normalized canonical logical fields."""
    payload = {
        "query": "GET students SORT { roll_number ASC };",
    }

    # Mock responses for all 4 databases with distinct physical field names
    async def mock_exec_query(source_id: str, query: str, parameters=None):
        if source_id == "src_pg":
            return QueryResult(
                columns=["roll_number", "full_name", "email", "department", "year", "cgpa", "city"],
                rows=[
                    {
                        "roll_number": 101,
                        "full_name": "Aarav Sharma",
                        "email": "aarav@pg.com",
                        "department": "Computer Science",
                        "year": 3,
                        "cgpa": 9.1,
                        "city": "Delhi",
                    }
                ],
                total_rows=1,
            )
        elif source_id == "src_mysql":
            return QueryResult(
                columns=["roll_no", "student_name", "email", "dept", "year", "cgpa", "city"],
                rows=[
                    {
                        "roll_no": 102,
                        "student_name": "Bhavya Patel",
                        "email": "bhavya@mysql.com",
                        "dept": "Information Technology",
                        "year": 2,
                        "cgpa": 8.7,
                        "city": "Ahmedabad",
                    }
                ],
                total_rows=1,
            )
        elif source_id == "src_sqlite":
            return QueryResult(
                columns=["student_id", "name", "email", "department", "year", "gpa", "city"],
                rows=[
                    {
                        "student_id": 103,
                        "name": "Chirag Sen",
                        "email": "chirag@sqlite.com",
                        "department": "Electronics",
                        "year": 4,
                        "gpa": 8.4,
                        "city": "Kolkata",
                    }
                ],
                total_rows=1,
            )
        elif source_id == "src_mongo":
            return QueryResult(
                columns=["_id", "rollNumber", "name", "email", "dept", "year", "cgpa", "city"],
                rows=[
                    {
                        "_id": "64f1a2b3c4d5e6f7a8b9c0d1",
                        "rollNumber": 104,
                        "name": "Divya Rao",
                        "email": "divya@mongo.com",
                        "dept": "Mechanical",
                        "year": 1,
                        "cgpa": 9.5,
                        "city": "Bangalore",
                    }
                ],
                total_rows=1,
            )
        return QueryResult(columns=[], rows=[], total_rows=0)

    with patch(
        "altr_stream.application.query_service.QueryService.execute_query",
        side_effect=mock_exec_query,
    ):
        res = await client.post("/api/v1/altrql/execute", json=payload)
        assert res.status_code == 200
        data = res.json()
        assert data["success"] is True, f"Execution failed: {data.get('error')}"
        assert data["execution_mode"] == "federated"
        assert len(data["sources_executed"]) == 4
        assert len(data["rows"]) == 4

        # 1. Check columns are normalized to logical field names
        expected_cols = ["roll_number", "name", "email", "department", "year", "cgpa", "city"]
        for col in expected_cols:
            assert col in data["columns"]

        # 2. Check MongoDB _id is NOT present in logical result
        assert "_id" not in data["columns"]
        for row in data["rows"]:
            assert "_id" not in row

        # 3. Check field normalization across all 4 rows
        # PG row: full_name -> name
        assert data["rows"][0]["roll_number"] == 101
        assert data["rows"][0]["name"] == "Aarav Sharma"
        assert data["rows"][0]["department"] == "Computer Science"

        # MySQL row: student_name -> name, roll_no -> roll_number, dept -> department
        assert data["rows"][1]["roll_number"] == 102
        assert data["rows"][1]["name"] == "Bhavya Patel"
        assert data["rows"][1]["department"] == "Information Technology"

        # SQLite row: student_id -> roll_number, gpa -> cgpa
        assert data["rows"][2]["roll_number"] == 103
        assert data["rows"][2]["name"] == "Chirag Sen"
        assert data["rows"][2]["cgpa"] == 8.4

        # MongoDB row: rollNumber -> roll_number, dept -> department, no _id
        assert data["rows"][3]["roll_number"] == 104
        assert data["rows"][3]["name"] == "Divya Rao"
        assert data["rows"][3]["department"] == "Mechanical"

        # 4. Check execution metadata contract
        meta = data["metadata"]
        assert meta["execution_mode"] == "federated"
        assert meta["normalized"] is True
        assert meta["source_count"] == 4
        assert meta["row_count"] == 4
        assert len(meta["sources"]) == 4
        assert {s["source_id"] for s in meta["sources"]} == {"src_pg", "src_mysql", "src_sqlite", "src_mongo"}
        for s in meta["sources"]:
            assert s["status"] == "success"
            assert s["rows"] == 1


@pytest.mark.asyncio
async def test_autoselect_global_sorting_and_pagination(
    client: AsyncClient, setup_quad_college_environment
):
    """Verify global SORT and LIMIT/OFFSET are merged across all sources."""
    payload = {
        "query": "GET students SORT { roll_number DESC } OFFSET 1 LIMIT 2;",
    }

    async def mock_exec_query(source_id: str, query: str, parameters=None):
        if source_id == "src_pg":
            return QueryResult(columns=["roll_number", "full_name"], rows=[{"roll_number": 101, "full_name": "Aarav"}], total_rows=1)
        elif source_id == "src_mysql":
            return QueryResult(columns=["roll_no", "student_name"], rows=[{"roll_no": 104, "student_name": "Divya"}], total_rows=1)
        elif source_id == "src_sqlite":
            return QueryResult(columns=["student_id", "name"], rows=[{"student_id": 102, "name": "Bhavya"}], total_rows=1)
        elif source_id == "src_mongo":
            return QueryResult(columns=["rollNumber", "name"], rows=[{"rollNumber": 103, "name": "Chirag"}], total_rows=1)
        return QueryResult(columns=[], rows=[], total_rows=0)

    with patch(
        "altr_stream.application.query_service.QueryService.execute_query",
        side_effect=mock_exec_query,
    ):
        res = await client.post("/api/v1/altrql/execute", json=payload)
        assert res.status_code == 200
        data = res.json()
        assert data["success"] is True
        assert len(data["rows"]) == 2

        # Sorted DESC: 104, 103, 102, 101. Offset 1 -> 103, 102. Limit 2 -> [103, 102]
        rolls = [r["roll_number"] for r in data["rows"]]
        assert rolls == [103, 102]
