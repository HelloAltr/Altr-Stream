"""Unit tests for Altr Stream v0.9 source-agnostic query planning and deterministic selection."""

import pytest
from unittest.mock import AsyncMock

from altr_stream.domain.errors import (
    IncompleteFieldMappingError,
    NoActiveSourceMappingError,
)
from altr_stream.domain.mapping import (
    EntityMapping,
    EntityResolutionResult,
    FieldMapping,
    MappingProvenance,
    MappingStatus,
    ResolvedFieldInfo,
    ResolvedSourceCandidate,
    SourceMapping,
)
from altr_stream.domain.schema import EntitySchema, FieldSchema, SourceSchema, StandardDataType
from altr_stream.domain.source import SourceType
from altr_stream.query_engine.domain.ast import QueryOperation
from altr_stream.query_engine.parser import parse_altrql
from altr_stream.query_engine.planning.models import PhysicalQueryPlan
from altr_stream.query_engine.planning.planner import QueryPlanner
from altr_stream.query_engine.planning.selector import (
    SourceSelector,
    extract_logical_context,
)


def _make_candidate(
    source_id: str,
    source_name: str,
    source_type: str,
    mapping_id: str,
    physical_entity_name: str,
    field_tuples: list[tuple[str, str]],
) -> ResolvedSourceCandidate:
    """Helper to construct ResolvedSourceCandidate for tests."""
    return ResolvedSourceCandidate(
        mapping_id=mapping_id,
        mapping_status=MappingStatus.ACTIVE,
        mapping_provenance=MappingProvenance.USER,
        source_id=source_id,
        source_name=source_name,
        source_type=source_type,
        entity_mapping_id="em_test",
        physical_entity_name=physical_entity_name,
        physical_namespace="public",
        field_mappings=[
            ResolvedFieldInfo(
                logical_field_id=f"lf_{l}",
                logical_field_name=l,
                physical_field_name=p,
            )
            for l, p in field_tuples
        ],
    )


def test_extract_logical_context_read_query():
    """Verify that logical context correctly extracts projections, filters, and sort fields."""
    ir = parse_altrql('GET Customer (email, age) WHERE { email = "alice@example.com" AND age >= 21 } SORT { name ASC } LIMIT 10;')
    ctx = extract_logical_context(ir, logical_model_id="retail")

    assert ctx.logical_model_id == "retail"
    assert ctx.target_entity == "Customer"
    assert ctx.operation == QueryOperation.READ
    assert not ctx.is_wildcard
    assert set(ctx.projected_fields) == {"email", "age"}
    assert set(ctx.filter_fields) == {"email", "age"}
    assert set(ctx.sort_fields) == {"name"}
    assert ctx.all_referenced_fields == {"email", "age", "name"}


def test_extract_logical_context_wildcard():
    """Verify that wildcard query sets is_wildcard = True."""
    ir = parse_altrql('GET Customer WHERE { email = "alice@example.com" };')
    ctx = extract_logical_context(ir, logical_model_id="retail")

    assert ctx.is_wildcard is True
    assert ctx.projected_fields == []
    assert ctx.all_referenced_fields == {"email"}


def test_source_selector_single_eligible_candidate():
    """Verify selection when exactly one compatible active mapping exists."""
    ir = parse_altrql('GET Customer WHERE { email = "alice@example.com" };')
    ctx = extract_logical_context(ir, logical_model_id="retail")

    candidates = [
        _make_candidate(
            source_id="pg_warehouse",
            source_name="PostgreSQL Prod",
            source_type="postgresql",
            mapping_id="map_pg_1",
            physical_entity_name="users",
            field_tuples=[("email", "email_address"), ("name", "full_name")],
        )
    ]

    selector = SourceSelector()
    selected, evaluations = selector.select_source(ctx, candidates)

    assert selected.source_id == "pg_warehouse"
    assert selected.mapping_id == "map_pg_1"
    assert len(evaluations) == 1
    assert evaluations[0].is_eligible is True


def test_source_selector_deterministic_tie_breaker():
    """Verify deterministic stable tie-breaking when multiple eligible active mappings exist."""
    ir = parse_altrql('GET Customer WHERE { email = "alice@example.com" };')
    ctx = extract_logical_context(ir, logical_model_id="retail")

    candidates = [
        _make_candidate(
            source_id="sqlite_b",
            source_name="SQLite Secondary",
            source_type="sqlite",
            mapping_id="map_sqlite_2",
            physical_entity_name="customers_b",
            field_tuples=[("email", "email")],
        ),
        _make_candidate(
            source_id="pg_a",
            source_name="Postgres Alpha",
            source_type="postgresql",
            mapping_id="map_pg_1",
            physical_entity_name="users",
            field_tuples=[("email", "email_addr")],
        ),
        _make_candidate(
            source_id="mongo_c",
            source_name="MongoDB Catalog",
            source_type="mongodb",
            mapping_id="map_mongo_3",
            physical_entity_name="clients",
            field_tuples=[("email", "contact_email")],
        ),
    ]

    selector = SourceSelector()
    selected, evaluations = selector.select_source(ctx, candidates)

    # Deterministic sort key: (source_id ASC, mapping_id ASC) -> "mongo_c" comes before "pg_a" and "sqlite_b"
    assert selected.source_id == "mongo_c"
    assert selected.mapping_id == "map_mongo_3"
    assert all(e.is_eligible for e in evaluations)


def test_source_selector_rejects_incomplete_field_coverage():
    """Verify that a candidate missing required query fields is rejected."""
    ir = parse_altrql('GET Customer WHERE { email = "alice@example.com" AND age > 30 };')
    ctx = extract_logical_context(ir, logical_model_id="retail")

    candidates = [
        _make_candidate(
            source_id="sqlite_main",
            source_name="SQLite Main",
            source_type="sqlite",
            mapping_id="map_sqlite_1",
            physical_entity_name="customers",
            field_tuples=[("email", "email")],  # Missing 'age'!
        )
    ]

    selector = SourceSelector()
    with pytest.raises(IncompleteFieldMappingError) as exc_info:
        selector.select_source(ctx, candidates)

    assert "age" in exc_info.value.message


def test_source_selector_no_candidates_raises_error():
    """Verify that empty candidate list raises NoActiveSourceMappingError."""
    ir = parse_altrql("GET Customer WHERE { id = 1 };")
    ctx = extract_logical_context(ir, logical_model_id="retail")

    selector = SourceSelector()
    with pytest.raises(NoActiveSourceMappingError):
        selector.select_source(ctx, [])


@pytest.mark.asyncio
async def test_query_planner_end_to_end_compilation():
    """Verify QueryPlanner compiles a logical query into a PhysicalQueryPlan with field maps."""
    ir = parse_altrql('GET Customer WHERE { email = "bob@example.com" };')

    mock_registry = AsyncMock()
    mock_schema = AsyncMock()
    mock_source = AsyncMock()

    candidate = _make_candidate(
        source_id="pg_prod",
        source_name="Postgres Prod",
        source_type="postgresql",
        mapping_id="map_pg_1",
        physical_entity_name="users",
        field_tuples=[("email", "email_addr"), ("id", "user_id")],
    )

    mock_registry.resolve_logical_entity.return_value = EntityResolutionResult(
        logical_model_id="retail",
        logical_model_name="Retail Model",
        logical_entity_id="le_1",
        logical_entity_name="Customer",
        candidates=[candidate],
    )

    full_mapping = SourceMapping(
        id="map_pg_1",
        logical_model_id="retail",
        source_id="pg_prod",
        version="1.0.0",
        status=MappingStatus.ACTIVE,
        entity_mappings=[
            EntityMapping(
                id="em_1",
                source_mapping_id="map_pg_1",
                logical_entity_id="le_1",
                logical_entity_name="Customer",
                physical_entity_name="users",
                physical_namespace="public",
                field_mappings=[
                    FieldMapping(
                        id="fm_1",
                        entity_mapping_id="em_1",
                        logical_field_id="lf_1",
                        logical_field_name="email",
                        physical_field_name="email_addr",
                    ),
                    FieldMapping(
                        id="fm_2",
                        entity_mapping_id="em_1",
                        logical_field_id="lf_2",
                        logical_field_name="id",
                        physical_field_name="user_id",
                    ),
                ],
            )
        ],
    )
    mock_registry.get_source_mapping.return_value = full_mapping

    source_schema = SourceSchema(
        source_id="pg_prod",
        source_name="Postgres Prod",
        entities=[
            EntitySchema(
                name="users",
                namespace="public",
                fields=[
                    FieldSchema(name="email_addr", native_data_type="VARCHAR", data_type=StandardDataType.STRING, nullable=False),
                    FieldSchema(name="user_id", native_data_type="INTEGER", data_type=StandardDataType.INTEGER, nullable=False, is_primary_key=True),
                ],
                primary_key=["user_id"],
            )
        ],
    )
    mock_schema.get_latest_schema.return_value = source_schema

    planner = QueryPlanner(mock_registry, mock_schema, mock_source)
    plan: PhysicalQueryPlan = await planner.create_physical_plan(ir, logical_model_id="retail")

    assert plan.selected_source_id == "pg_prod"
    assert plan.selected_mapping_id == "map_pg_1"
    assert plan.physical_entity_name == "users"
    assert plan.logical_to_physical_map["email"] == "email_addr"
    assert plan.physical_to_logical_map["email_addr"] == "email"
    assert "users" in plan.physical_query.query
    assert "email_addr" in plan.physical_query.query


@pytest.mark.asyncio
async def test_query_planner_federated_plan_strips_physical_limit_offset():
    """Verify that QueryPlanner.create_federated_plan strips physical limit/offset for global merger pagination."""
    ir = parse_altrql('GET Customer (email) WHERE { email = "bob@example.com" } LIMIT 10 OFFSET 5;')

    mock_registry = AsyncMock()
    mock_schema = AsyncMock()
    mock_source = AsyncMock()

    candidate_a = _make_candidate(
        source_id="pg_prod",
        source_name="Postgres Prod",
        source_type="postgresql",
        mapping_id="map_pg_1",
        physical_entity_name="users",
        field_tuples=[("email", "email_addr")],
    )
    candidate_b = _make_candidate(
        source_id="sqlite_prod",
        source_name="SQLite Prod",
        source_type="sqlite",
        mapping_id="map_sqlite_1",
        physical_entity_name="tbl_users",
        field_tuples=[("email", "user_email")],
    )

    mock_registry.resolve_logical_entity.return_value = EntityResolutionResult(
        logical_model_id="retail",
        logical_model_name="Retail Model",
        logical_entity_id="le_1",
        logical_entity_name="Customer",
        candidates=[candidate_a, candidate_b],
    )

    mapping_pg = SourceMapping(
        id="map_pg_1",
        logical_model_id="retail",
        source_id="pg_prod",
        version="1.0.0",
        status=MappingStatus.ACTIVE,
        entity_mappings=[
            EntityMapping(
                id="em_1",
                source_mapping_id="map_pg_1",
                logical_entity_id="le_1",
                logical_entity_name="Customer",
                physical_entity_name="users",
                physical_namespace="public",
                field_mappings=[
                    FieldMapping(
                        id="fm_1",
                        entity_mapping_id="em_1",
                        logical_field_id="lf_1",
                        logical_field_name="email",
                        physical_field_name="email_addr",
                    ),
                ],
            )
        ],
    )

    mapping_sqlite = SourceMapping(
        id="map_sqlite_1",
        logical_model_id="retail",
        source_id="sqlite_prod",
        version="1.0.0",
        status=MappingStatus.ACTIVE,
        entity_mappings=[
            EntityMapping(
                id="em_2",
                source_mapping_id="map_sqlite_1",
                logical_entity_id="le_1",
                logical_entity_name="Customer",
                physical_entity_name="tbl_users",
                physical_namespace="main",
                field_mappings=[
                    FieldMapping(
                        id="fm_2",
                        entity_mapping_id="em_2",
                        logical_field_id="lf_2",
                        logical_field_name="email",
                        physical_field_name="user_email",
                    ),
                ],
            )
        ],
    )

    async def mock_get_mapping(m_id: str):
        return mapping_pg if m_id == "map_pg_1" else mapping_sqlite

    mock_registry.get_source_mapping.side_effect = mock_get_mapping

    schema_pg = SourceSchema(
        source_id="pg_prod",
        source_name="Postgres Prod",
        entities=[
            EntitySchema(
                name="users",
                namespace="public",
                fields=[
                    FieldSchema(name="email_addr", native_data_type="VARCHAR", data_type=StandardDataType.STRING, nullable=False),
                ],
            )
        ],
    )
    schema_sqlite = SourceSchema(
        source_id="sqlite_prod",
        source_name="SQLite Prod",
        entities=[
            EntitySchema(
                name="tbl_users",
                namespace="main",
                fields=[
                    FieldSchema(name="user_email", native_data_type="TEXT", data_type=StandardDataType.STRING, nullable=False),
                ],
            )
        ],
    )

    async def mock_get_schema(s_id: str):
        return schema_pg if s_id == "pg_prod" else schema_sqlite

    mock_schema.get_latest_schema.side_effect = mock_get_schema

    planner = QueryPlanner(mock_registry, mock_schema, mock_source)
    fed_plan = await planner.create_federated_plan(ir, logical_model_id="retail")

    assert fed_plan.execution_mode == "federated"
    assert len(fed_plan.physical_plans) == 2
    assert fed_plan.accepted_sources == ["pg_prod", "sqlite_prod"]

    # Verify physical queries do NOT contain LIMIT or OFFSET clauses
    for p in fed_plan.physical_plans:
        assert p.bound_ir.limit is None
        assert p.bound_ir.offset is None
        assert "LIMIT" not in p.physical_query.query.upper()
        assert "OFFSET" not in p.physical_query.query.upper()

