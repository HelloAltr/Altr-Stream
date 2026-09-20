"""Integration tests for Altr Stream v0.11: Query Engine Hardening & Advanced Query Execution."""

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
async def setup_quad_hardening_environment(test_session: AsyncSession):
    """Setup four sources configured with 'students' mapped to 'College.Student'."""
    source_repo = SqliteSourceRepository(test_session)
    reg_repo = SqliteRegistryRepository(test_session)

    # 1. PostgreSQL Source
    src_pg = await source_repo.create(
        Source(
            id="src_pg_011",
            name="PostgreSQL Prod",
            type=SourceType.POSTGRESQL,
            host="localhost",
            port=5432,
            database_name="college_pg",
            status=SourceStatus.ACTIVE,
        )
    )
    pg_schema = SourceSchema(
        source_id=src_pg.id,
        source_name=src_pg.name,
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
    await source_repo.save_schema_snapshot(src_pg.id, pg_schema)

    # 2. MySQL Source
    src_mysql = await source_repo.create(
        Source(
            id="src_mysql_011",
            name="MySQL Prod",
            type=SourceType.MYSQL,
            host="localhost",
            port=3306,
            database_name="college_mysql",
            status=SourceStatus.ACTIVE,
        )
    )
    mysql_schema = SourceSchema(
        source_id=src_mysql.id,
        source_name=src_mysql.name,
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
    await source_repo.save_schema_snapshot(src_mysql.id, mysql_schema)

    # 3. SQLite Source
    src_sqlite = await source_repo.create(
        Source(
            id="src_sqlite_011",
            name="SQLite Edge",
            type=SourceType.SQLITE,
            host="localhost",
            port=0,
            database_name="college_sqlite",
            status=SourceStatus.ACTIVE,
        )
    )
    sqlite_schema = SourceSchema(
        source_id=src_sqlite.id,
        source_name=src_sqlite.name,
        entities=[
            EntitySchema(
                name="students",
                fields=[
                    FieldSchema(name="roll_number", data_type=StandardDataType.INTEGER, native_data_type="INTEGER", is_primary_key=True),
                    FieldSchema(name="name", data_type=StandardDataType.STRING, native_data_type="TEXT"),
                    FieldSchema(name="email", data_type=StandardDataType.STRING, native_data_type="TEXT"),
                    FieldSchema(name="department", data_type=StandardDataType.STRING, native_data_type="TEXT"),
                    FieldSchema(name="year", data_type=StandardDataType.INTEGER, native_data_type="INTEGER"),
                    FieldSchema(name="cgpa", data_type=StandardDataType.DECIMAL, native_data_type="REAL"),
                    FieldSchema(name="city", data_type=StandardDataType.STRING, native_data_type="TEXT"),
                ],
                primary_key=["roll_number"],
            )
        ],
    )
    await source_repo.save_schema_snapshot(src_sqlite.id, sqlite_schema)

    # 4. MongoDB Source
    src_mongo = await source_repo.create(
        Source(
            id="src_mongo_011",
            name="MongoDB DocStore",
            type=SourceType.MONGODB,
            host="localhost",
            port=27017,
            database_name="college_mongo",
            status=SourceStatus.ACTIVE,
        )
    )
    mongo_schema = SourceSchema(
        source_id=src_mongo.id,
        source_name=src_mongo.name,
        entities=[
            EntitySchema(
                name="students",
                fields=[
                    FieldSchema(name="_id", data_type=StandardDataType.STRING, native_data_type="ObjectId", is_primary_key=True),
                    FieldSchema(name="roll_number", data_type=StandardDataType.INTEGER, native_data_type="int"),
                    FieldSchema(name="name", data_type=StandardDataType.STRING, native_data_type="string"),
                    FieldSchema(name="email", data_type=StandardDataType.STRING, native_data_type="string"),
                    FieldSchema(name="department", data_type=StandardDataType.STRING, native_data_type="string"),
                    FieldSchema(name="year", data_type=StandardDataType.INTEGER, native_data_type="int"),
                    FieldSchema(name="cgpa", data_type=StandardDataType.DECIMAL, native_data_type="double"),
                    FieldSchema(name="city", data_type=StandardDataType.STRING, native_data_type="string"),
                ],
                primary_key=["_id"],
            )
        ],
    )
    await source_repo.save_schema_snapshot(src_mongo.id, mongo_schema)

    # Register Canonical Logical Model
    model = await reg_repo.create_model(
        LogicalModel(
            id="model_college_011",
            name="College",
            version="1.0.0",
            entities=[
                LogicalEntity(
                    id="ent_student_011",
                    logical_model_id="model_college_011",
                    name="Student",
                    fields=[
                        LogicalField(id="f_roll_011", logical_entity_id="ent_student_011", name="roll_number", data_type=StandardDataType.INTEGER, is_primary_key=True),
                        LogicalField(id="f_name_011", logical_entity_id="ent_student_011", name="name", data_type=StandardDataType.STRING),
                        LogicalField(id="f_email_011", logical_entity_id="ent_student_011", name="email", data_type=StandardDataType.STRING),
                        LogicalField(id="f_dept_011", logical_entity_id="ent_student_011", name="department", data_type=StandardDataType.STRING),
                        LogicalField(id="f_year_011", logical_entity_id="ent_student_011", name="year", data_type=StandardDataType.INTEGER),
                        LogicalField(id="f_cgpa_011", logical_entity_id="ent_student_011", name="cgpa", data_type=StandardDataType.DECIMAL),
                        LogicalField(id="f_city_011", logical_entity_id="ent_student_011", name="city", data_type=StandardDataType.STRING),
                    ],
                )
            ],
        )
    )

    # Register Mappings for All 4 Sources
    # PG Mapping
    await reg_repo.create_source_mapping(
        SourceMapping(
            id="map_pg_011",
            logical_model_id=model.id,
            source_id=src_pg.id,
            status=MappingStatus.ACTIVE,
            provenance=MappingProvenance.USER,
            entity_mappings=[
                EntityMapping(
                    id="em_pg_011",
                    source_mapping_id="map_pg_011",
                    logical_entity_id="ent_student_011",
                    logical_entity_name="Student",
                    physical_entity_name="students",
                    field_mappings=[
                        FieldMapping(entity_mapping_id="em_pg_011", logical_field_id="f_roll_011", logical_field_name="roll_number", physical_field_name="roll_number"),
                        FieldMapping(entity_mapping_id="em_pg_011", logical_field_id="f_name_011", logical_field_name="name", physical_field_name="full_name"),
                        FieldMapping(entity_mapping_id="em_pg_011", logical_field_id="f_email_011", logical_field_name="email", physical_field_name="email"),
                        FieldMapping(entity_mapping_id="em_pg_011", logical_field_id="f_dept_011", logical_field_name="department", physical_field_name="department"),
                        FieldMapping(entity_mapping_id="em_pg_011", logical_field_id="f_year_011", logical_field_name="year", physical_field_name="year"),
                        FieldMapping(entity_mapping_id="em_pg_011", logical_field_id="f_cgpa_011", logical_field_name="cgpa", physical_field_name="cgpa"),
                        FieldMapping(entity_mapping_id="em_pg_011", logical_field_id="f_city_011", logical_field_name="city", physical_field_name="city"),
                    ],
                )
            ],
        )
    )

    # MySQL Mapping
    await reg_repo.create_source_mapping(
        SourceMapping(
            id="map_mysql_011",
            logical_model_id=model.id,
            source_id=src_mysql.id,
            status=MappingStatus.ACTIVE,
            provenance=MappingProvenance.USER,
            entity_mappings=[
                EntityMapping(
                    id="em_mysql_011",
                    source_mapping_id="map_mysql_011",
                    logical_entity_id="ent_student_011",
                    logical_entity_name="Student",
                    physical_entity_name="students",
                    field_mappings=[
                        FieldMapping(entity_mapping_id="em_mysql_011", logical_field_id="f_roll_011", logical_field_name="roll_number", physical_field_name="roll_no"),
                        FieldMapping(entity_mapping_id="em_mysql_011", logical_field_id="f_name_011", logical_field_name="name", physical_field_name="student_name"),
                        FieldMapping(entity_mapping_id="em_mysql_011", logical_field_id="f_email_011", logical_field_name="email", physical_field_name="email"),
                        FieldMapping(entity_mapping_id="em_mysql_011", logical_field_id="f_dept_011", logical_field_name="department", physical_field_name="dept"),
                        FieldMapping(entity_mapping_id="em_mysql_011", logical_field_id="f_year_011", logical_field_name="year", physical_field_name="year"),
                        FieldMapping(entity_mapping_id="em_mysql_011", logical_field_id="f_cgpa_011", logical_field_name="cgpa", physical_field_name="cgpa"),
                        FieldMapping(entity_mapping_id="em_mysql_011", logical_field_id="f_city_011", logical_field_name="city", physical_field_name="city"),
                    ],
                )
            ],
        )
    )

    # SQLite Mapping
    await reg_repo.create_source_mapping(
        SourceMapping(
            id="map_sqlite_011",
            logical_model_id=model.id,
            source_id=src_sqlite.id,
            status=MappingStatus.ACTIVE,
            provenance=MappingProvenance.USER,
            entity_mappings=[
                EntityMapping(
                    id="em_sqlite_011",
                    source_mapping_id="map_sqlite_011",
                    logical_entity_id="ent_student_011",
                    logical_entity_name="Student",
                    physical_entity_name="students",
                    field_mappings=[
                        FieldMapping(entity_mapping_id="em_sqlite_011", logical_field_id="f_roll_011", logical_field_name="roll_number", physical_field_name="roll_number"),
                        FieldMapping(entity_mapping_id="em_sqlite_011", logical_field_id="f_name_011", logical_field_name="name", physical_field_name="name"),
                        FieldMapping(entity_mapping_id="em_sqlite_011", logical_field_id="f_email_011", logical_field_name="email", physical_field_name="email"),
                        FieldMapping(entity_mapping_id="em_sqlite_011", logical_field_id="f_dept_011", logical_field_name="department", physical_field_name="department"),
                        FieldMapping(entity_mapping_id="em_sqlite_011", logical_field_id="f_year_011", logical_field_name="year", physical_field_name="year"),
                        FieldMapping(entity_mapping_id="em_sqlite_011", logical_field_id="f_cgpa_011", logical_field_name="cgpa", physical_field_name="cgpa"),
                        FieldMapping(entity_mapping_id="em_sqlite_011", logical_field_id="f_city_011", logical_field_name="city", physical_field_name="city"),
                    ],
                )
            ],
        )
    )

    # MongoDB Mapping
    await reg_repo.create_source_mapping(
        SourceMapping(
            id="map_mongo_011",
            logical_model_id=model.id,
            source_id=src_mongo.id,
            status=MappingStatus.ACTIVE,
            provenance=MappingProvenance.USER,
            entity_mappings=[
                EntityMapping(
                    id="em_mongo_011",
                    source_mapping_id="map_mongo_011",
                    logical_entity_id="ent_student_011",
                    logical_entity_name="Student",
                    physical_entity_name="students",
                    field_mappings=[
                        FieldMapping(entity_mapping_id="em_mongo_011", logical_field_id="f_roll_011", logical_field_name="roll_number", physical_field_name="roll_number"),
                        FieldMapping(entity_mapping_id="em_mongo_011", logical_field_id="f_name_011", logical_field_name="name", physical_field_name="name"),
                        FieldMapping(entity_mapping_id="em_mongo_011", logical_field_id="f_email_011", logical_field_name="email", physical_field_name="email"),
                        FieldMapping(entity_mapping_id="em_mongo_011", logical_field_id="f_dept_011", logical_field_name="department", physical_field_name="department"),
                        FieldMapping(entity_mapping_id="em_mongo_011", logical_field_id="f_year_011", logical_field_name="year", physical_field_name="year"),
                        FieldMapping(entity_mapping_id="em_mongo_011", logical_field_id="f_cgpa_011", logical_field_name="cgpa", physical_field_name="cgpa"),
                        FieldMapping(entity_mapping_id="em_mongo_011", logical_field_id="f_city_011", logical_field_name="city", physical_field_name="city"),
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
    }


@pytest.mark.asyncio
async def test_federated_pagination_with_skewed_row_counts(client: AsyncClient, setup_quad_hardening_environment):
    """Test 1: Federated pagination SORT + OFFSET + LIMIT across skewed row counts across 4 sources."""
    env = setup_quad_hardening_environment

    async def mock_exec_query(source_id: str, query: str, parameters=None):
        if source_id == env["src_pg"].id:
            return QueryResult(
                columns=["roll_number", "full_name", "cgpa"],
                rows=[
                    {"roll_number": 101, "full_name": "PG_Aarav", "cgpa": 3.90},
                    {"roll_number": 102, "full_name": "PG_Bob", "cgpa": 3.50},
                ],
                total_rows=2,
            )
        elif source_id == env["src_mysql"].id:
            return QueryResult(
                columns=["roll_no", "student_name", "cgpa"],
                rows=[
                    {"roll_no": 201, "student_name": "MY_Charlie", "cgpa": 4.00},
                    {"roll_no": 202, "student_name": "MY_David", "cgpa": 3.80},
                    {"roll_no": 203, "student_name": "MY_Eve", "cgpa": 3.60},
                    {"roll_no": 204, "student_name": "MY_Frank", "cgpa": 3.20},
                ],
                total_rows=4,
            )
        elif source_id == env["src_sqlite"].id:
            return QueryResult(
                columns=["roll_number", "name", "cgpa"],
                rows=[
                    {"roll_number": 301, "name": "SQL_Grace", "cgpa": 3.70},
                ],
                total_rows=1,
            )
        elif source_id == env["src_mongo"].id:
            return QueryResult(
                columns=["roll_number", "name", "cgpa"],
                rows=[
                    {"roll_number": 401, "name": "MDB_Hannah", "cgpa": 3.95},
                    {"roll_number": 402, "name": "MDB_Isaac", "cgpa": 3.85},
                    {"roll_number": 403, "name": "MDB_Jack", "cgpa": 3.10},
                ],
                total_rows=3,
            )
        return QueryResult(columns=[], rows=[])

    # Complete expected global ordering by CGPA DESC:
    # 1. MY_Charlie (4.00)
    # 2. MDB_Hannah (3.95)
    # 3. PG_Aarav (3.90)
    # 4. MDB_Isaac (3.85)
    # 5. MY_David (3.80)
    # 6. SQL_Grace (3.70)
    # 7. MY_Eve (3.60)
    # 8. PG_Bob (3.50)
    # 9. MY_Frank (3.20)
    # 10. MDB_Jack (3.10)

    # Test Query: OFFSET 3 LIMIT 4 (Expect items 4, 5, 6, 7)
    with patch("altr_stream.application.query_service.QueryService.execute_query", side_effect=mock_exec_query):
        res = await client.post(
            "/api/v1/altrql/execute",
            json={
                "query": "GET students (name, cgpa) SORT { cgpa DESC } OFFSET 3 LIMIT 4;",
                "logical_model_id": env["model"].id,
            },
        )
        assert res.status_code == 200
        data = res.json()
        assert data["success"] is True
        assert data["metadata"]["row_count"] == 4
        assert len(data["rows"]) == 4

        # Verify exact 4 items in global sort order
        assert data["rows"][0]["name"] == "MDB_Isaac"
        assert data["rows"][0]["cgpa"] == 3.85

        assert data["rows"][1]["name"] == "MY_David"
        assert data["rows"][1]["cgpa"] == 3.80

        assert data["rows"][2]["name"] == "SQL_Grace"
        assert data["rows"][2]["cgpa"] == 3.70

        assert data["rows"][3]["name"] == "MY_Eve"
        assert data["rows"][3]["cgpa"] == 3.60


@pytest.mark.asyncio
async def test_federated_aliased_projection_and_sorting(client: AsyncClient, setup_quad_hardening_environment):
    """Test 2: Federated query with explicit aliased projection and sorting on the alias."""
    env = setup_quad_hardening_environment

    async def mock_exec_query(source_id: str, query: str, parameters=None):
        if source_id == env["src_pg"].id:
            return QueryResult(
                columns=["student_full_name", "score"],
                rows=[{"student_full_name": "Aarav", "score": 3.90}],
                total_rows=1,
            )
        elif source_id == env["src_mysql"].id:
            return QueryResult(
                columns=["student_full_name", "score"],
                rows=[{"student_full_name": "Charlie", "score": 4.00}],
                total_rows=1,
            )
        return QueryResult(columns=[], rows=[])

    with patch("altr_stream.application.query_service.QueryService.execute_query", side_effect=mock_exec_query):
        res = await client.post(
            "/api/v1/altrql/execute",
            json={
                "query": "GET students (name AS student_full_name, cgpa AS score) SORT { score DESC } LIMIT 2;",
                "logical_model_id": env["model"].id,
            },
        )
        assert res.status_code == 200
        data = res.json()
        assert data["success"] is True
        assert data["columns"] == ["student_full_name", "score"]
        assert len(data["rows"]) == 2
        assert data["rows"][0] == {"student_full_name": "Charlie", "score": 4.00}
        assert data["rows"][1] == {"student_full_name": "Aarav", "score": 3.90}


@pytest.mark.asyncio
async def test_federated_offset_beyond_total_rows(client: AsyncClient, setup_quad_hardening_environment):
    """Test 3: OFFSET beyond total available rows safely returns empty rows without error."""
    env = setup_quad_hardening_environment

    async def mock_exec_query(source_id: str, query: str, parameters=None):
        return QueryResult(
            columns=["name", "cgpa"],
            rows=[{"name": "Aarav", "cgpa": 3.90}],
            total_rows=1,
        )

    with patch("altr_stream.application.query_service.QueryService.execute_query", side_effect=mock_exec_query):
        res = await client.post(
            "/api/v1/altrql/execute",
            json={
                "query": "GET students (name, cgpa) OFFSET 50 LIMIT 5;",
                "logical_model_id": env["model"].id,
            },
        )
        assert res.status_code == 200
        data = res.json()
        assert data["success"] is True
        assert data["columns"] == ["name", "cgpa"]
        assert data["rows"] == []
        assert data["metadata"]["row_count"] == 0


@pytest.mark.asyncio
async def test_federated_limit_zero(client: AsyncClient, setup_quad_hardening_environment):
    """Test 4: LIMIT 0 is rejected by the semantic validator with a descriptive error."""
    env = setup_quad_hardening_environment

    res = await client.post(
        "/api/v1/altrql/execute",
        json={
            "query": "GET students (name, cgpa) LIMIT 0;",
            "logical_model_id": env["model"].id,
        },
    )
    assert res.status_code == 200
    data = res.json()
    assert data["success"] is False
    assert data["error"]["type"] == "AltrQuerySemanticError"
    assert "LIMIT must be a positive integer greater than 0" in data["error"]["message"]


@pytest.mark.asyncio
async def test_federated_offset_without_limit(client: AsyncClient, setup_quad_hardening_environment):
    """Test 5: OFFSET without LIMIT returns all remaining rows from offset to end."""
    env = setup_quad_hardening_environment

    async def mock_exec_query(source_id: str, query: str, parameters=None):
        if source_id == env["src_pg"].id:
            return QueryResult(
                columns=["full_name", "cgpa"],
                rows=[
                    {"full_name": "PG_1", "cgpa": 3.9},
                    {"full_name": "PG_2", "cgpa": 3.5},
                ],
                total_rows=2,
            )
        elif source_id == env["src_mysql"].id:
            return QueryResult(
                columns=["student_name", "cgpa"],
                rows=[
                    {"student_name": "MY_1", "cgpa": 4.0},
                    {"student_name": "MY_2", "cgpa": 3.8},
                ],
                total_rows=2,
            )
        return QueryResult(columns=[], rows=[])

    # Sorted CGPA DESC: MY_1 (4.0), PG_1 (3.9), MY_2 (3.8), PG_2 (3.5)
    # OFFSET 2 should return: MY_2 (3.8) and PG_2 (3.5)
    with patch("altr_stream.application.query_service.QueryService.execute_query", side_effect=mock_exec_query):
        res = await client.post(
            "/api/v1/altrql/execute",
            json={
                "query": "GET students (name, cgpa) SORT { cgpa DESC } OFFSET 2;",
                "logical_model_id": env["model"].id,
            },
        )
        assert res.status_code == 200
        data = res.json()
        assert data["success"] is True
        assert len(data["rows"]) == 2
        assert data["rows"][0]["name"] == "MY_2"
        assert data["rows"][1]["name"] == "PG_2"


@pytest.mark.asyncio
async def test_federated_query6_explicit_projection_alias_preservation(client: AsyncClient, setup_quad_hardening_environment):
    """Regression Test for Query 6: Federated query with roll_number AS student_id preserves student_id across all 4 sources."""
    env = setup_quad_hardening_environment

    async def mock_exec_query(source_id: str, query: str, parameters=None):
        if source_id == env["src_mysql"].id:
            return QueryResult(
                columns=["student_id", "name", "cgpa"],
                rows=[
                    {"student_id": "MSQL001", "name": "Devansh Mehta", "cgpa": 9.30},
                    {"student_id": "MSQL002", "name": "Harshavardhan Rao", "cgpa": 8.05},
                ],
                total_rows=2,
            )
        elif source_id == env["src_pg"].id:
            return QueryResult(
                columns=["student_id", "name", "cgpa"],
                rows=[
                    {"student_id": "PG001", "name": "Riddhi Shah", "cgpa": 8.60},
                ],
                total_rows=1,
            )
        elif source_id == env["src_sqlite"].id:
            return QueryResult(
                columns=["student_id", "name", "cgpa"],
                rows=[
                    {"student_id": "SQL001", "name": "Gautam Singhal", "cgpa": 7.70},
                ],
                total_rows=1,
            )
        elif source_id == env["src_mongo"].id:
            return QueryResult(
                columns=["student_id", "name", "cgpa"],
                rows=[
                    {"student_id": "MDB001", "name": "Neha Agarwal", "cgpa": 9.10},
                ],
                total_rows=1,
            )
        return QueryResult(columns=[], rows=[])

    with patch("altr_stream.application.query_service.QueryService.execute_query", side_effect=mock_exec_query):
        res = await client.post(
            "/api/v1/altrql/execute",
            json={
                "query": """GET students (
                    roll_number AS student_id,
                    name,
                    cgpa
                )
                SORT {
                    student_id ASC
                } LIMIT 5;""",
                "logical_model_id": env["model"].id,
            },
        )
        assert res.status_code == 200
        data = res.json()
        assert data["success"] is True
        assert data["columns"] == ["student_id", "name", "cgpa"]
        assert len(data["rows"]) == 5

        # Verify exact rows ordered by student_id ASC: MDB001, MSQL001, MSQL002, PG001, SQL001
        assert data["rows"][0] == {"student_id": "MDB001", "name": "Neha Agarwal", "cgpa": 9.10}
        assert data["rows"][1] == {"student_id": "MSQL001", "name": "Devansh Mehta", "cgpa": 9.30}
        assert data["rows"][2] == {"student_id": "MSQL002", "name": "Harshavardhan Rao", "cgpa": 8.05}
        assert data["rows"][3] == {"student_id": "PG001", "name": "Riddhi Shah", "cgpa": 8.60}
        assert data["rows"][4] == {"student_id": "SQL001", "name": "Gautam Singhal", "cgpa": 7.70}

        # Verify no duplicate roll_number field in output rows
        for r in data["rows"]:
            assert "student_id" in r
            assert "roll_number" not in r


@pytest.mark.asyncio
async def test_explicit_source_aliased_projection_with_normalize_on(client: AsyncClient, setup_quad_hardening_environment):
    """Regression Test for Path A: Explicit source query with Normalize ON preserves user-defined alias."""
    env = setup_quad_hardening_environment

    async def mock_exec_query(source_id: str, query: str, parameters=None):
        return QueryResult(
            columns=["student_id", "name", "cgpa"],
            rows=[
                {"student_id": "MSQL001", "name": "Devansh Mehta", "cgpa": 9.30},
            ],
            total_rows=1,
        )

    with patch("altr_stream.application.query_service.QueryService.execute_query", side_effect=mock_exec_query):
        res = await client.post(
            "/api/v1/altrql/execute",
            json={
                "query": "GET students (roll_number AS student_id, name, cgpa);",
                "source_id": env["src_mysql"].id,
                "normalize": True,
            },
        )
        assert res.status_code == 200
        data = res.json()
        assert data["success"] is True
        assert data["columns"] == ["student_id", "name", "cgpa"]
        assert len(data["rows"]) == 1
        assert data["rows"][0] == {"student_id": "MSQL001", "name": "Devansh Mehta", "cgpa": 9.30}
        assert "roll_number" not in data["rows"][0]

