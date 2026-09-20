"""Unit tests for Altr Stream v0.10 ephemeral projection synthesis, physical entity discovery, and planning."""

import pytest
from unittest.mock import AsyncMock

from altr_stream.application.schema_service import SchemaService
from altr_stream.domain.errors import (
    IncompleteFieldMappingError,
    PhysicalEntityNotFoundError,
)
from altr_stream.domain.schema import (
    EntitySchema,
    FieldSchema,
    SourceSchema,
    StandardDataType,
)
from altr_stream.domain.source import Source, SourceStatus, SourceType
from altr_stream.query_engine.domain.ast import QueryOperation
from altr_stream.query_engine.parser import parse_altrql
from altr_stream.query_engine.planning.models import (
    EphemeralFieldProjection,
    EphemeralLogicalProjection,
    SourceExclusionInfo,
    SourceExclusionReason,
)
from altr_stream.query_engine.planning.planner import QueryPlanner
from altr_stream.query_engine.planning.selector import (
    SourceSelector,
    extract_logical_context,
    synthesize_ephemeral_projection,
)


def _make_source_schema(
    source_id: str,
    source_name: str,
    entity_name: str,
    fields: list[tuple[str, StandardDataType, bool]],
) -> SourceSchema:
    """Helper to construct SourceSchema for unit tests."""
    return SourceSchema(
        source_id=source_id,
        source_name=source_name,
        entities=[
            EntitySchema(
                name=entity_name,
                namespace="public",
                fields=[
                    FieldSchema(
                        name=f_name,
                        data_type=f_type,
                        native_data_type=f_type.value,
                        is_primary_key=is_pk,
                    )
                    for f_name, f_type, is_pk in fields
                ],
                primary_key=[f_name for f_name, _, is_pk in fields if is_pk],
            )
        ],
    )


# ====================================================================
# 1. SchemaService Discovery Tests
# ====================================================================

@pytest.mark.asyncio
async def test_schema_service_find_sources_case_insensitive_and_plural():
    """Verify that find_sources_with_physical_entity matches case-insensitively and handles plurals."""
    source_repo = AsyncMock()
    service = SchemaService(source_repo)

    # Setup active sources
    sources = [
        Source(id="s1", name="Postgres", type=SourceType.POSTGRESQL, host="h", port=5432, database_name="db", status=SourceStatus.ACTIVE),
        Source(id="s2", name="MySQL", type=SourceType.MYSQL, host="h", port=3306, database_name="db", status=SourceStatus.ACTIVE),
        Source(id="s3", name="SQLite", type=SourceType.SQLITE, host="h", port=0, database_name="db", status=SourceStatus.ACTIVE),
        Source(id="s4", name="Mongo", type=SourceType.MONGODB, host="h", port=27017, database_name="db", status=SourceStatus.ACTIVE),
        Source(id="s5", name="Inactive", type=SourceType.POSTGRESQL, host="h", port=5432, database_name="db", status=SourceStatus.INACTIVE),
    ]
    source_repo.list_all.return_value = sources
    source_repo.get_all.return_value = sources

    # Schemas: s1 has 'users', s2 has 'Users', s3 has 'user', s4 has 'orders'
    s1_schema = _make_source_schema("s1", "Postgres", "users", [("id", StandardDataType.INTEGER, True)])
    s2_schema = _make_source_schema("s2", "MySQL", "Users", [("id", StandardDataType.INTEGER, True)])
    s3_schema = _make_source_schema("s3", "SQLite", "user", [("id", StandardDataType.INTEGER, True)])
    s4_schema = _make_source_schema("s4", "Mongo", "orders", [("id", StandardDataType.STRING, True)])

    async def get_snapshot(s_id):
        return {"s1": s1_schema, "s2": s2_schema, "s3": s3_schema, "s4": s4_schema}.get(s_id)

    source_repo.get_schema_snapshot.side_effect = get_snapshot
    source_repo.get_latest_schema.side_effect = get_snapshot

    # Search for 'users'
    matching, excluded = await service.find_sources_with_physical_entity("users")

    # s1, s2, s3 should match
    matching_ids = {s.id for s, _, _ in matching}
    assert matching_ids == {"s1", "s2", "s3"}

    # s4 should be excluded as PHYSICAL_ENTITY_NOT_FOUND (s5 is inactive, ignored)
    assert len(excluded) == 1
    assert excluded[0].source_id == "s4"
    assert excluded[0].reason_code == SourceExclusionReason.PHYSICAL_ENTITY_NOT_FOUND.value


# ====================================================================
# 2. Ephemeral Projection Synthesis Tests
# ====================================================================

def test_synthesize_ephemeral_projection_common_field_intersection():
    """Verify common-field intersection across sources, excluding mongo _id and non-common fields."""
    ir = parse_altrql("GET users;")
    ctx = extract_logical_context(ir)

    # Postgres: id, name, email, city
    pg_source = Source(id="s_pg", name="PG", type=SourceType.POSTGRESQL, host="h", port=5432, database_name="db")
    pg_schema = _make_source_schema("s_pg", "PG", "users", [
        ("id", StandardDataType.INTEGER, True),
        ("name", StandardDataType.STRING, False),
        ("email", StandardDataType.STRING, False),
        ("city", StandardDataType.STRING, False),
    ])

    # MySQL: id, name, email, city, salary (extra field)
    mysql_source = Source(id="s_my", name="MySQL", type=SourceType.MYSQL, host="h", port=3306, database_name="db")
    mysql_schema = _make_source_schema("s_my", "MySQL", "users", [
        ("id", StandardDataType.INTEGER, True),
        ("name", StandardDataType.STRING, False),
        ("email", StandardDataType.STRING, False),
        ("city", StandardDataType.STRING, False),
        ("salary", StandardDataType.DECIMAL, False),
    ])

    # Mongo: _id, id, name, email, city
    mongo_source = Source(id="s_mg", name="Mongo", type=SourceType.MONGODB, host="h", port=27017, database_name="db")
    mongo_schema = _make_source_schema("s_mg", "Mongo", "users", [
        ("_id", StandardDataType.STRING, True),
        ("id", StandardDataType.INTEGER, False),
        ("name", StandardDataType.STRING, False),
        ("email", StandardDataType.STRING, False),
        ("city", StandardDataType.STRING, False),
    ])

    matching = [
        (pg_source, pg_schema, pg_schema.entities[0]),
        (mysql_source, mysql_schema, mysql_schema.entities[0]),
        (mongo_source, mongo_schema, mongo_schema.entities[0]),
    ]

    sqlite_ex = SourceExclusionInfo(
        source_id="s_sq",
        source_name="SQLite",
        source_type=SourceType.SQLITE.value,
        reason_code=SourceExclusionReason.PHYSICAL_ENTITY_NOT_FOUND.value,
        message="Entity 'users' not found in schema snapshot",
    )

    proj = synthesize_ephemeral_projection(ctx, matching, [sqlite_ex])

    assert proj is not None
    assert proj.entity_name == "users"
    assert proj.is_ephemeral is True

    # Canonical fields should be: id, name, email, city
    field_names = [f.name for f in proj.canonical_fields]
    assert set(field_names) == {"id", "name", "email", "city"}
    assert "salary" not in field_names
    assert "_id" not in field_names

    # Check participating sources
    assert set(proj.participating_sources) == {"s_pg", "s_my", "s_mg"}
    assert len(proj.excluded_sources) == 1
    assert proj.excluded_sources[0].source_id == "s_sq"


def test_synthesize_ephemeral_projection_explicit_missing_field_exclusion():
    """Verify that if query requests explicit fields and a source is missing one, that source is excluded."""
    ir = parse_altrql("GET users (id, name, department);")
    ctx = extract_logical_context(ir)

    # Postgres has department
    pg_source = Source(id="s_pg", name="PG", type=SourceType.POSTGRESQL, host="h", port=5432, database_name="db")
    pg_schema = _make_source_schema("s_pg", "PG", "users", [
        ("id", StandardDataType.INTEGER, True),
        ("name", StandardDataType.STRING, False),
        ("department", StandardDataType.STRING, False),
    ])

    # Mongo does NOT have department
    mongo_source = Source(id="s_mg", name="Mongo", type=SourceType.MONGODB, host="h", port=27017, database_name="db")
    mongo_schema = _make_source_schema("s_mg", "Mongo", "users", [
        ("_id", StandardDataType.STRING, True),
        ("id", StandardDataType.INTEGER, False),
        ("name", StandardDataType.STRING, False),
    ])

    matching = [
        (pg_source, pg_schema, pg_schema.entities[0]),
        (mongo_source, mongo_schema, mongo_schema.entities[0]),
    ]

    proj = synthesize_ephemeral_projection(ctx, matching, [])

    assert proj is not None
    # PG participates, Mongo is excluded
    assert proj.participating_sources == ["s_pg"]
    assert len(proj.excluded_sources) == 1
    assert proj.excluded_sources[0].source_id == "s_mg"
    assert proj.excluded_sources[0].reason_code == SourceExclusionReason.INCOMPLETE_FIELD_MAPPING.value
    assert "department" in proj.excluded_sources[0].message


def test_synthesize_ephemeral_projection_all_sources_missing_explicit_field():
    """Verify that if no sources satisfy explicit fields, empty participating_sources is returned and all are excluded."""
    ir = parse_altrql("GET users (id, nonexistent_field);")
    ctx = extract_logical_context(ir)

    pg_source = Source(id="s_pg", name="PG", type=SourceType.POSTGRESQL, host="h", port=5432, database_name="db")
    pg_schema = _make_source_schema("s_pg", "PG", "users", [
        ("id", StandardDataType.INTEGER, True),
        ("name", StandardDataType.STRING, False),
    ])

    matching = [(pg_source, pg_schema, pg_schema.entities[0])]
    proj = synthesize_ephemeral_projection(ctx, matching, [])

    assert proj is not None
    assert len(proj.participating_sources) == 0
    assert len(proj.excluded_sources) == 1



# ====================================================================
# 3. QueryPlanner Path B Federated Plan Tests
# ====================================================================

@pytest.mark.asyncio
async def test_planner_create_federated_plan_path_b():
    """Verify QueryPlanner.create_federated_plan on unmapped entity using SchemaService discovery."""
    reg_service = AsyncMock()
    schema_service = AsyncMock()
    source_service = AsyncMock()

    planner = QueryPlanner(
        registry_service=reg_service,
        schema_service=schema_service,
        source_service=source_service,
    )

    # Model resolution returns None (unmapped)
    reg_service.resolve_entity_mappings.return_value = None

    # Setup 2 matching sources for 'users'
    pg_source = Source(id="s_pg", name="PG", type=SourceType.POSTGRESQL, host="h", port=5432, database_name="db", status=SourceStatus.ACTIVE)
    pg_schema = _make_source_schema("s_pg", "PG", "users", [
        ("id", StandardDataType.INTEGER, True),
        ("name", StandardDataType.STRING, False),
    ])

    mysql_source = Source(id="s_my", name="MySQL", type=SourceType.MYSQL, host="h", port=3306, database_name="db", status=SourceStatus.ACTIVE)
    mysql_schema = _make_source_schema("s_my", "MySQL", "users", [
        ("id", StandardDataType.INTEGER, True),
        ("name", StandardDataType.STRING, False),
    ])

    excluded_sq = SourceExclusionInfo(
        source_id="s_sq",
        source_name="SQLite",
        source_type=SourceType.SQLITE.value,
        reason_code=SourceExclusionReason.PHYSICAL_ENTITY_NOT_FOUND.value,
        message="Entity not found",
    )

    schema_service.find_sources_with_physical_entity.return_value = (
        [
            (pg_source, pg_schema, pg_schema.entities[0]),
            (mysql_source, mysql_schema, mysql_schema.entities[0]),
        ],
        [excluded_sq],
    )

    ir = parse_altrql("GET users;")
    plan = await planner.create_federated_plan(ir)

    assert plan.target_entity == "users"
    assert len(plan.physical_plans) == 2
    assert [p.selected_source_id for p in plan.physical_plans] == ["s_my", "s_pg"]
    assert len(plan.excluded_sources) == 1
    assert plan.excluded_sources[0].source_id == "s_sq"

    # Ephemeral projection is populated
    assert plan.ephemeral_projection is not None
    assert plan.ephemeral_projection.entity_name == "users"
    assert set(plan.ephemeral_projection.participating_sources) == {"s_pg", "s_my"}
