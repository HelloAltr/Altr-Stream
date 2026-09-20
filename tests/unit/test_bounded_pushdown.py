"""Unit tests for safe bounded pagination pushdown in Altr Stream v0.11."""

import pytest
from altr_stream.query_engine.domain.ast import (
    AltrQueryIR,
    FieldPath,
    FieldSelection,
    QueryOperation,
    RankingClause,
    SortClause,
)
from altr_stream.query_engine.domain.operators import RankingDirection, SortDirection
from altr_stream.query_engine.parser.parser import parse_altrql
from altr_stream.query_engine.planning.planner import _compute_federated_plan_ir_updates


def test_sort_and_limit_pushes_bounded_limit():
    """Verify SORT + LIMIT pushes down bounded limit = limit."""
    ir = parse_altrql("GET students SORT { cgpa DESC } LIMIT 10;")
    updates = _compute_federated_plan_ir_updates(ir)

    assert updates["limit"] == 10
    assert updates["offset"] is None


def test_sort_offset_and_limit_pushes_bounded_limit():
    """Verify SORT + OFFSET + LIMIT pushes down bounded limit = offset + limit."""
    ir = parse_altrql("GET students SORT { cgpa DESC } OFFSET 15 LIMIT 5;")
    updates = _compute_federated_plan_ir_updates(ir)

    assert updates["limit"] == 20  # 15 + 5
    assert updates["offset"] is None


def test_ranking_clause_pushes_bounded_limit_and_converts_to_sort():
    """Verify TOP n BY field pushes down bounded limit = n and converts ranking to sort."""
    ir = parse_altrql("GET students TOP 7 BY cgpa;")
    updates = _compute_federated_plan_ir_updates(ir)

    assert updates["limit"] == 7
    assert updates["offset"] is None
    assert updates["ranking"] is None
    assert len(updates["sort"]) == 1
    assert updates["sort"][0].field.leaf == "cgpa"
    assert updates["sort"][0].direction == SortDirection.DESC


def test_bottom_ranking_clause_converts_to_asc_sort():
    """Verify BOTTOM n BY field pushes down bounded limit = n and converts ranking to ASC sort."""
    ir = parse_altrql("GET students BOTTOM 3 BY cgpa;")
    updates = _compute_federated_plan_ir_updates(ir)

    assert updates["limit"] == 3
    assert updates["offset"] is None
    assert updates["ranking"] is None
    assert len(updates["sort"]) == 1
    assert updates["sort"][0].field.leaf == "cgpa"
    assert updates["sort"][0].direction == SortDirection.ASC


def test_limit_without_sort_does_not_push_bounded_limit():
    """Safety: LIMIT without SORT must NOT push down per-source limit because physical order is non-deterministic."""
    ir = parse_altrql("GET students LIMIT 10;")
    updates = _compute_federated_plan_ir_updates(ir)

    assert updates["limit"] is None
    assert updates["offset"] is None


def test_offset_without_limit_does_not_push_artificial_limit():
    """Safety: OFFSET without LIMIT represents an open-ended stream and must NOT push an artificial limit."""
    ir = parse_altrql("GET students SORT { cgpa DESC } OFFSET 25;")
    updates = _compute_federated_plan_ir_updates(ir)

    assert updates["limit"] is None
    assert updates["offset"] is None


def test_offset_only_query_does_not_push_limit():
    """Safety: OFFSET-only queries must NOT push limits."""
    ir = parse_altrql("GET students OFFSET 10;")
    updates = _compute_federated_plan_ir_updates(ir)

    assert updates["limit"] is None
    assert updates["offset"] is None


def test_limit_zero_with_sort_pushes_zero_limit():
    """Verify LIMIT 0 with SORT pushes limit 0 for immediate zero-row return."""
    ir = AltrQueryIR(
        entity="students",
        sort=[SortClause(field=FieldPath(segments=["id"]), direction=SortDirection.ASC)],
        limit=0,
    )
    updates = _compute_federated_plan_ir_updates(ir)

    assert updates["limit"] == 0
    assert updates["offset"] is None


def test_offset_zero_plus_limit_with_sort():
    """Verify OFFSET 0 + LIMIT with SORT computes bounded limit = limit."""
    ir = parse_altrql("GET students SORT { cgpa DESC } OFFSET 0 LIMIT 10;")
    updates = _compute_federated_plan_ir_updates(ir)

    assert updates["limit"] == 10
    assert updates["offset"] is None


def test_large_offset_and_limit_calculation():
    """Verify large offset and limit values calculate bounded sum correctly without overflow."""
    ir = parse_altrql("GET students SORT { cgpa DESC } OFFSET 5000 LIMIT 100;")
    updates = _compute_federated_plan_ir_updates(ir)

    assert updates["limit"] == 5100
    assert updates["offset"] is None
