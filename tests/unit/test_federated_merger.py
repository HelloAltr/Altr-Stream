"""Unit tests for federated result normalization, global sorting, and global pagination."""

import pytest
from altr_stream.domain.connector import SourceCapabilities
from altr_stream.domain.mapping import ResolvedFieldInfo, ResolvedSourceCandidate
from altr_stream.domain.query import QueryResult
from altr_stream.domain.source import SourceType
from altr_stream.query_engine.domain.ast import (
    AltrQueryIR,
    FieldPath,
    FieldSelection,
    RankingClause,
    RankingDirection,
    SortClause,
    SortDirection,
)
from altr_stream.query_engine.planning.merger import (
    _compare_values,
    merge_federated_results,
    normalize_row,
)
from altr_stream.query_engine.planning.models import FederatedQueryPlan, PhysicalQueryPlan


def test_normalize_row_field_mapping_and_id_exclusion():
    """Verify normalize_row maps physical names to logical and strips unmapped _id."""
    phys_to_log = {
        "user_id": "id",
        "full_name": "name",
        "contact_email": "email",
    }

    raw_row = {
        "_id": "64f1234abcd5678",
        "user_id": 101,
        "full_name": "Alice Smith",
        "contact_email": "alice@example.com",
        "extra_unmapped": "val",
    }

    # Default: logical mode (preserve_unmapped=False) excludes physical-only fields
    norm = normalize_row(raw_row, phys_to_log)
    assert "_id" not in norm
    assert norm["id"] == 101
    assert norm["name"] == "Alice Smith"
    assert norm["email"] == "alice@example.com"
    assert "extra_unmapped" not in norm

    # Raw preserve mode (preserve_unmapped=True)
    norm_preserved = normalize_row(raw_row, phys_to_log, preserve_unmapped=True)
    assert norm_preserved["extra_unmapped"] == "val"


def test_compare_values_nulls_and_numerics():
    """Verify NULLs sort first and numeric coercion works across int and float."""
    # NULL comparisons
    assert _compare_values(None, None) == 0
    assert _compare_values(None, 10) == -1
    assert _compare_values(10, None) == 1

    # Numerics
    assert _compare_values(5, 10.0) == -1
    assert _compare_values(10.0, 5) == 1
    assert _compare_values(4.5, 4.5) == 0

    # Strings
    assert _compare_values("Alice", "Bob") == -1
    assert _compare_values("Charlie", "Bob") == 1
    assert _compare_values("Alice", "Alice") == 0


def test_merge_federated_results_global_sorting_and_pagination():
    """Verify multi-source merging with global sorting and global LIMIT/OFFSET pagination."""
    ir = AltrQueryIR(
        entity="Student",
        projection=[
            FieldSelection(path=FieldPath(segments=["name"])),
            FieldSelection(path=FieldPath(segments=["gpa"])),
        ],
        sort=[SortClause(field=FieldPath(segments=["gpa"]), direction=SortDirection.DESC)],
        limit=3,
        offset=1,
    )

    plan_pg = PhysicalQueryPlan(
        logical_model_id="mod1",
        target_entity="Student",
        selected_source_id="pg_src",
        selected_source_name="Postgres",
        selected_source_type=SourceType.POSTGRESQL,
        selected_mapping_id="map_pg",
        physical_entity_name="students",
        resolved_ir=ir,
        bound_ir=ir,  # mock
        classification=None,  # mock
        physical_query=None,
        logical_to_physical_map={"name": "full_name", "gpa": "gpa_val"},
        physical_to_logical_map={"full_name": "name", "gpa_val": "gpa"},
    )

    plan_mysql = PhysicalQueryPlan(
        logical_model_id="mod1",
        target_entity="Student",
        selected_source_id="mysql_src",
        selected_source_name="MySQL",
        selected_source_type=SourceType.MYSQL,
        selected_mapping_id="map_mysql",
        physical_entity_name="tbl_students",
        resolved_ir=ir,
        bound_ir=ir,
        classification=None,
        physical_query=None,
        logical_to_physical_map={"name": "student_name", "gpa": "grade_point"},
        physical_to_logical_map={"student_name": "name", "grade_point": "gpa"},
    )

    fed_plan = FederatedQueryPlan(
        logical_model_id="mod1",
        target_entity="Student",
        logical_ir=ir,
        physical_plans=[plan_pg, plan_mysql],
    )

    res_pg = QueryResult(
        columns=["full_name", "gpa_val"],
        rows=[
            {"full_name": "Alice", "gpa_val": 3.9},
            {"full_name": "Bob", "gpa_val": 3.5},
        ],
        total_rows=2,
    )

    res_mysql = QueryResult(
        columns=["student_name", "grade_point"],
        rows=[
            {"student_name": "Charlie", "grade_point": 4.0},
            {"student_name": "David", "grade_point": 3.7},
            {"student_name": "Eve", "grade_point": 3.2},
        ],
        total_rows=3,
    )

    # Combined 5 students sorted by GPA DESC:
    # 1. Charlie (4.0) -> offset 1 skips Charlie
    # 2. Alice (3.9)   -> row 1 of limit 3
    # 3. David (3.7)   -> row 2 of limit 3
    # 4. Bob (3.5)     -> row 3 of limit 3
    # 5. Eve (3.2)     -> truncated by limit 3

    cols, rows = merge_federated_results(
        ir=ir,
        federated_plan=fed_plan,
        execution_results=[(plan_pg, res_pg), (plan_mysql, res_mysql)],
    )

    assert cols == ["name", "gpa"]
    assert len(rows) == 3
    assert rows[0] == {"name": "Alice", "gpa": 3.9}
    assert rows[1] == {"name": "David", "gpa": 3.7}
    assert rows[2] == {"name": "Bob", "gpa": 3.5}
