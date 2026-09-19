"""Integration tests for explicit-source execution logical result normalization across PostgreSQL, MySQL, SQLite, and MongoDB."""

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
async def setup_quad_db_environment(test_session: AsyncSession):
    """Setup PostgreSQL, MySQL, SQLite, and MongoDB sources with active mappings to Student logical model."""
    source_repo = SqliteSourceRepository(test_session)
    reg_repo = SqliteRegistryRepository(test_session)

    # 1. PostgreSQL Source
    src_pg = await source_repo.create(
        Source(
            id="src_pg",
            name="PostgreSQL Students",
            type=SourceType.POSTGRESQL,
            host="localhost",
            port=5432,
            database_name="pg_students",
            status=SourceStatus.ACTIVE,
        )
    )
    pg_fields = [
        FieldSchema(name="roll_number", data_type=StandardDataType.STRING, native_data_type="VARCHAR", is_primary_key=True),
        FieldSchema(name="full_name", data_type=StandardDataType.STRING, native_data_type="VARCHAR"),
        FieldSchema(name="email", data_type=StandardDataType.STRING, native_data_type="VARCHAR"),
        FieldSchema(name="department", data_type=StandardDataType.STRING, native_data_type="VARCHAR"),
        FieldSchema(name="year", data_type=StandardDataType.INTEGER, native_data_type="INTEGER"),
        FieldSchema(name="cgpa", data_type=StandardDataType.FLOAT, native_data_type="FLOAT"),
        FieldSchema(name="city", data_type=StandardDataType.STRING, native_data_type="VARCHAR"),
    ]
    await source_repo.save_schema_snapshot(
        src_pg.id,
        SourceSchema(
            source_id=src_pg.id,
            source_name=src_pg.name,
            entities=[EntitySchema(name="students", namespace="public", fields=pg_fields, primary_key=["roll_number"])],
        ),
    )

    # 2. MySQL Source
    src_mysql = await source_repo.create(
        Source(
            id="src_mysql",
            name="MySQL Students",
            type=SourceType.MYSQL,
            host="localhost",
            port=3306,
            database_name="mysql_students",
            status=SourceStatus.ACTIVE,
        )
    )
    mysql_fields = [
        FieldSchema(name="roll_no", data_type=StandardDataType.STRING, native_data_type="VARCHAR", is_primary_key=True),
        FieldSchema(name="student_name", data_type=StandardDataType.STRING, native_data_type="VARCHAR"),
        FieldSchema(name="email", data_type=StandardDataType.STRING, native_data_type="VARCHAR"),
        FieldSchema(name="dept", data_type=StandardDataType.STRING, native_data_type="VARCHAR"),
        FieldSchema(name="year", data_type=StandardDataType.INTEGER, native_data_type="INT"),
        FieldSchema(name="cgpa", data_type=StandardDataType.FLOAT, native_data_type="FLOAT"),
        FieldSchema(name="city", data_type=StandardDataType.STRING, native_data_type="VARCHAR"),
    ]
    await source_repo.save_schema_snapshot(
        src_mysql.id,
        SourceSchema(
            source_id=src_mysql.id,
            source_name=src_mysql.name,
            entities=[EntitySchema(name="students", namespace="public", fields=mysql_fields, primary_key=["roll_no"])],
        ),
    )

    # 3. SQLite Source
    src_sqlite = await source_repo.create(
        Source(
            id="src_sqlite",
            name="SQLite Students",
            type=SourceType.SQLITE,
            file_path="/tmp/students.db",
            status=SourceStatus.ACTIVE,
        )
    )
    sqlite_fields = [
        FieldSchema(name="student_id", data_type=StandardDataType.STRING, native_data_type="TEXT", is_primary_key=True),
        FieldSchema(name="name", data_type=StandardDataType.STRING, native_data_type="TEXT"),
        FieldSchema(name="email", data_type=StandardDataType.STRING, native_data_type="TEXT"),
        FieldSchema(name="department", data_type=StandardDataType.STRING, native_data_type="TEXT"),
        FieldSchema(name="year", data_type=StandardDataType.INTEGER, native_data_type="INTEGER"),
        FieldSchema(name="gpa", data_type=StandardDataType.FLOAT, native_data_type="REAL"),
        FieldSchema(name="city", data_type=StandardDataType.STRING, native_data_type="TEXT"),
    ]
    await source_repo.save_schema_snapshot(
        src_sqlite.id,
        SourceSchema(
            source_id=src_sqlite.id,
            source_name=src_sqlite.name,
            entities=[EntitySchema(name="students", namespace="main", fields=sqlite_fields, primary_key=["student_id"])],
        ),
    )

    # 4. MongoDB Source
    src_mongo = await source_repo.create(
        Source(
            id="src_mongo",
            name="MongoDB Students",
            type=SourceType.MONGODB,
            host="localhost",
            port=27017,
            database_name="mongo_students",
            status=SourceStatus.ACTIVE,
        )
    )
    mongo_fields = [
        FieldSchema(name="_id", data_type=StandardDataType.STRING, native_data_type="objectId", is_primary_key=True),
        FieldSchema(name="rollNumber", data_type=StandardDataType.STRING, native_data_type="string"),
        FieldSchema(name="name", data_type=StandardDataType.STRING, native_data_type="string"),
        FieldSchema(name="email", data_type=StandardDataType.STRING, native_data_type="string"),
        FieldSchema(name="department", data_type=StandardDataType.STRING, native_data_type="string"),
        FieldSchema(name="year", data_type=StandardDataType.INTEGER, native_data_type="int"),
        FieldSchema(name="cgpa", data_type=StandardDataType.FLOAT, native_data_type="double"),
        FieldSchema(name="city", data_type=StandardDataType.STRING, native_data_type="string"),
    ]
    await source_repo.save_schema_snapshot(
        src_mongo.id,
        SourceSchema(
            source_id=src_mongo.id,
            source_name=src_mongo.name,
            entities=[EntitySchema(name="students", namespace="mongo_students", fields=mongo_fields, primary_key=["_id"])],
        ),
    )

    # Logical Model: Student
    lf_roll = LogicalField(logical_entity_id="", name="roll_number", data_type=StandardDataType.STRING, is_primary_key=True)
    lf_name = LogicalField(logical_entity_id="", name="name", data_type=StandardDataType.STRING)
    lf_email = LogicalField(logical_entity_id="", name="email", data_type=StandardDataType.STRING)
    lf_dept = LogicalField(logical_entity_id="", name="department", data_type=StandardDataType.STRING)
    lf_year = LogicalField(logical_entity_id="", name="year", data_type=StandardDataType.INTEGER)
    lf_cgpa = LogicalField(logical_entity_id="", name="cgpa", data_type=StandardDataType.FLOAT)
    lf_city = LogicalField(logical_entity_id="", name="city", data_type=StandardDataType.STRING)

    le_student = LogicalEntity(
        logical_model_id="",
        name="Student",
        fields=[lf_roll, lf_name, lf_email, lf_dept, lf_year, lf_cgpa, lf_city],
    )
    model = await reg_repo.create_model(LogicalModel(name="UniversityModel", entities=[le_student]))
    saved_entity = model.entities[0]
    fld = {f.name: f.id for f in saved_entity.fields}

    # PostgreSQL Mapping
    map_pg = await reg_repo.create_source_mapping(
        SourceMapping(
            id="map_pg",
            logical_model_id=model.id,
            source_id=src_pg.id,
            status=MappingStatus.ACTIVE,
            provenance=MappingProvenance.USER,
            entity_mappings=[
                EntityMapping(
                    source_mapping_id="",
                    logical_entity_id=saved_entity.id,
                    logical_entity_name="Student",
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

    # MySQL Mapping
    map_mysql = await reg_repo.create_source_mapping(
        SourceMapping(
            id="map_mysql",
            logical_model_id=model.id,
            source_id=src_mysql.id,
            status=MappingStatus.ACTIVE,
            provenance=MappingProvenance.USER,
            entity_mappings=[
                EntityMapping(
                    source_mapping_id="",
                    logical_entity_id=saved_entity.id,
                    logical_entity_name="Student",
                    physical_entity_name="students",
                    physical_namespace="public",
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

    # SQLite Mapping
    map_sqlite = await reg_repo.create_source_mapping(
        SourceMapping(
            id="map_sqlite",
            logical_model_id=model.id,
            source_id=src_sqlite.id,
            status=MappingStatus.ACTIVE,
            provenance=MappingProvenance.USER,
            entity_mappings=[
                EntityMapping(
                    source_mapping_id="",
                    logical_entity_id=saved_entity.id,
                    logical_entity_name="Student",
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

    # MongoDB Mapping
    map_mongo = await reg_repo.create_source_mapping(
        SourceMapping(
            id="map_mongo",
            logical_model_id=model.id,
            source_id=src_mongo.id,
            status=MappingStatus.ACTIVE,
            provenance=MappingProvenance.USER,
            entity_mappings=[
                EntityMapping(
                    source_mapping_id="",
                    logical_entity_id=saved_entity.id,
                    logical_entity_name="Student",
                    physical_entity_name="students",
                    physical_namespace="mongo_students",
                    field_mappings=[
                        FieldMapping(entity_mapping_id="", logical_field_id=fld["roll_number"], logical_field_name="roll_number", physical_field_name="rollNumber"),
                        FieldMapping(entity_mapping_id="", logical_field_id=fld["name"], logical_field_name="name", physical_field_name="name"),
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

    return {
        "model": model,
        "src_pg": src_pg,
        "src_mysql": src_mysql,
        "src_sqlite": src_sqlite,
        "src_mongo": src_mongo,
        "map_pg": map_pg,
        "map_mysql": map_mysql,
        "map_sqlite": map_sqlite,
        "map_mongo": map_mongo,
    }


@pytest.mark.asyncio
async def test_explicit_postgres_normalize_on(client: AsyncClient, setup_quad_db_environment):
    """Test 1: Explicit PostgreSQL + Normalize ON returns canonical logical fields."""
    env = setup_quad_db_environment

    async def mock_exec_query(source_id: str, query: str, parameters=None):
        return QueryResult(
            columns=["roll_number", "full_name", "email", "department", "year", "cgpa", "city"],
            rows=[
                {
                    "roll_number": "PGS001",
                    "full_name": "Aarav Patel",
                    "email": "aarav.patel@altr.edu",
                    "department": "Computer Science",
                    "year": 3,
                    "cgpa": 3.85,
                    "city": "Mumbai",
                }
            ],
            total_rows=1,
            execution_time_ms=2.5,
        )

    with patch("altr_stream.application.query_service.QueryService.execute_query", side_effect=mock_exec_query):
        res = await client.post(
            "/api/v1/altrql/execute",
            json={
                "source_id": env["src_pg"].id,
                "query": "GET students;",
                "normalize": True,
            },
        )
        assert res.status_code == 200
        data = res.json()
        assert data["success"] is True
        assert data["columns"] == ["roll_number", "name", "email", "department", "year", "cgpa", "city"]
        row = data["rows"][0]
        assert row["roll_number"] == "PGS001"
        assert row["name"] == "Aarav Patel"
        assert row["cgpa"] == 3.85
        assert data["metadata"]["execution_mode"] == "single"
        assert data["metadata"]["normalized"] is True
        assert data["metadata"]["source_count"] == 1
        assert len(data["metadata"]["sources"]) == 1
        assert data["metadata"]["sources"][0]["source_id"] == env["src_pg"].id


@pytest.mark.asyncio
async def test_explicit_mysql_normalize_on(client: AsyncClient, setup_quad_db_environment):
    """Test 2: Explicit MySQL + Normalize ON returns canonical logical fields."""
    env = setup_quad_db_environment

    async def mock_exec_query(source_id: str, query: str, parameters=None):
        return QueryResult(
            columns=["roll_no", "student_name", "email", "dept", "year", "cgpa", "city"],
            rows=[
                {
                    "roll_no": "MSQL001",
                    "student_name": "Kavya Shah",
                    "email": "kavya.shah@altr.edu",
                    "dept": "Computer Science",
                    "year": 2,
                    "cgpa": 3.90,
                    "city": "Ahmedabad",
                }
            ],
            total_rows=1,
            execution_time_ms=2.0,
        )

    with patch("altr_stream.application.query_service.QueryService.execute_query", side_effect=mock_exec_query):
        res = await client.post(
            "/api/v1/altrql/execute",
            json={
                "source_id": env["src_mysql"].id,
                "query": "GET students;",
                "normalize": True,
            },
        )
        assert res.status_code == 200
        data = res.json()
        assert data["success"] is True
        assert data["columns"] == ["roll_number", "name", "email", "department", "year", "cgpa", "city"]
        row = data["rows"][0]
        assert row["roll_number"] == "MSQL001"
        assert row["name"] == "Kavya Shah"
        assert "roll_no" not in row
        assert "student_name" not in row
        assert row["department"] == "Computer Science"
        assert "dept" not in row


@pytest.mark.asyncio
async def test_explicit_sqlite_normalize_on(client: AsyncClient, setup_quad_db_environment):
    """Test 3: Explicit SQLite + Normalize ON returns canonical logical fields."""
    env = setup_quad_db_environment

    async def mock_exec_query(source_id: str, query: str, parameters=None):
        return QueryResult(
            columns=["student_id", "name", "email", "department", "year", "gpa", "city"],
            rows=[
                {
                    "student_id": "SQL001",
                    "name": "Rohan Gupta",
                    "email": "rohan.gupta@altr.edu",
                    "department": "Computer Science",
                    "year": 1,
                    "gpa": 3.75,
                    "city": "Delhi",
                }
            ],
            total_rows=1,
            execution_time_ms=1.5,
        )

    with patch("altr_stream.application.query_service.QueryService.execute_query", side_effect=mock_exec_query):
        res = await client.post(
            "/api/v1/altrql/execute",
            json={
                "source_id": env["src_sqlite"].id,
                "query": "GET students;",
                "normalize": True,
            },
        )
        assert res.status_code == 200
        data = res.json()
        assert data["success"] is True
        assert data["columns"] == ["roll_number", "name", "email", "department", "year", "cgpa", "city"]
        row = data["rows"][0]
        assert row["roll_number"] == "SQL001"
        assert row["name"] == "Rohan Gupta"
        assert "student_id" not in row
        assert row["cgpa"] == 3.75
        assert "gpa" not in row


@pytest.mark.asyncio
async def test_explicit_mongodb_normalize_on_and_id_exclusion(client: AsyncClient, setup_quad_db_environment):
    """Test 4 & 6: Explicit MongoDB + Normalize ON returns canonical logical fields and excludes _id."""
    env = setup_quad_db_environment

    async def mock_exec_query(source_id: str, query: str, parameters=None):
        return QueryResult(
            columns=["_id", "rollNumber", "name", "email", "department", "year", "cgpa", "city"],
            rows=[
                {
                    "_id": "65f1234abcd56789",
                    "rollNumber": "MDB001",
                    "name": "Aditya Roy",
                    "email": "aditya.roy@altr.edu",
                    "department": "Information Technology",
                    "year": 4,
                    "cgpa": 3.65,
                    "city": "Kolkata",
                }
            ],
            total_rows=1,
            execution_time_ms=3.0,
        )

    with patch("altr_stream.application.query_service.QueryService.execute_query", side_effect=mock_exec_query):
        res = await client.post(
            "/api/v1/altrql/execute",
            json={
                "source_id": env["src_mongo"].id,
                "query": "GET students;",
                "normalize": True,
            },
        )
        assert res.status_code == 200
        data = res.json()
        assert data["success"] is True
        assert data["columns"] == ["roll_number", "name", "email", "department", "year", "cgpa", "city"]
        assert "_id" not in data["columns"]
        row = data["rows"][0]
        assert "_id" not in row
        assert row["roll_number"] == "MDB001"
        assert "rollNumber" not in row
        assert row["name"] == "Aditya Roy"
        assert row["cgpa"] == 3.65


@pytest.mark.asyncio
async def test_explicit_source_normalize_off_remains_raw(client: AsyncClient, setup_quad_db_environment):
    """Test 5: Explicit source + Normalize OFF preserves raw physical columns and rows."""
    env = setup_quad_db_environment

    async def mock_exec_query(source_id: str, query: str, parameters=None):
        if source_id == env["src_mysql"].id:
            return QueryResult(
                columns=["roll_no", "student_name", "email", "dept", "year", "cgpa", "city"],
                rows=[
                    {
                        "roll_no": "MSQL001",
                        "student_name": "Kavya Shah",
                        "email": "kavya.shah@altr.edu",
                        "dept": "Computer Science",
                        "year": 2,
                        "cgpa": 3.90,
                        "city": "Ahmedabad",
                    }
                ],
                total_rows=1,
                execution_time_ms=2.0,
            )
        elif source_id == env["src_mongo"].id:
            return QueryResult(
                columns=["_id", "rollNumber", "name", "email", "department", "year", "cgpa", "city"],
                rows=[
                    {
                        "_id": "65f1234abcd56789",
                        "rollNumber": "MDB001",
                        "name": "Aditya Roy",
                        "email": "aditya.roy@altr.edu",
                        "department": "Information Technology",
                        "year": 4,
                        "cgpa": 3.65,
                        "city": "Kolkata",
                    }
                ],
                total_rows=1,
                execution_time_ms=2.5,
            )

    with patch("altr_stream.application.query_service.QueryService.execute_query", side_effect=mock_exec_query):
        # 1. MySQL with normalize=False
        res_mysql = await client.post(
            "/api/v1/altrql/execute",
            json={
                "source_id": env["src_mysql"].id,
                "query": "GET students;",
                "normalize": False,
            },
        )
        assert res_mysql.status_code == 200
        data_mysql = res_mysql.json()
        assert data_mysql["columns"] == ["roll_no", "student_name", "email", "dept", "year", "cgpa", "city"]
        row_mysql = data_mysql["rows"][0]
        assert "roll_no" in row_mysql
        assert "student_name" in row_mysql
        assert "dept" in row_mysql

        # 2. MongoDB with normalize=False
        res_mongo = await client.post(
            "/api/v1/altrql/execute",
            json={
                "source_id": env["src_mongo"].id,
                "query": "GET students;",
                "normalize": False,
            },
        )
        assert res_mongo.status_code == 200
        data_mongo = res_mongo.json()
        assert "_id" in data_mongo["columns"]
        assert "rollNumber" in data_mongo["columns"]
        row_mongo = data_mongo["rows"][0]
        assert "_id" in row_mongo
        assert "rollNumber" in row_mongo


@pytest.mark.asyncio
async def test_explicit_source_explicit_projections_normalize_on(client: AsyncClient, setup_quad_db_environment):
    """Test 7: Explicit projections (e.g. name, email) with Normalize ON returns exact requested logical columns."""
    env = setup_quad_db_environment

    async def mock_exec_query(source_id: str, query: str, parameters=None):
        return QueryResult(
            columns=["full_name", "email"],
            rows=[{"full_name": "Aarav Patel", "email": "aarav.patel@altr.edu"}],
            total_rows=1,
            execution_time_ms=2.0,
        )

    with patch("altr_stream.application.query_service.QueryService.execute_query", side_effect=mock_exec_query):
        res = await client.post(
            "/api/v1/altrql/execute",
            json={
                "source_id": env["src_pg"].id,
                "query": "GET students (name, email);",
                "normalize": True,
            },
        )
        assert res.status_code == 200
        data = res.json()
        assert data["success"] is True
        assert data["columns"] == ["name", "email"]
        assert data["rows"] == [{"name": "Aarav Patel", "email": "aarav.patel@altr.edu"}]
