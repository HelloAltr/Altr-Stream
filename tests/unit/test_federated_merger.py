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
    QueryOperation,
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


def test_normalize_row_already_canonical_and_explicit_projection():
    """Verify normalize_row preserves already-canonical logical field names from aliased queries."""
    phys_to_log = {
        "roll_no": "roll_number",
        "student_name": "name",
        "email": "email",
        "dept": "department",
    }

    # Row returned from database executing: SELECT roll_no AS roll_number, student_name AS name, email, dept AS department
    aliased_row = {
        "roll_number": "MSQL001",
        "name": "Kavya Shah",
        "email": "kavya@example.com",
        "department": "Computer Science",
    }

    norm = normalize_row(aliased_row, phys_to_log)
    assert norm == {
        "roll_number": "MSQL001",
        "name": "Kavya Shah",
        "email": "kavya@example.com",
        "department": "Computer Science",
    }


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


def _make_mock_physical_plan(
    selected_source_id: str,
    target_entity: str = "students",
    physical_entity_name: str = "tbl_students",
    physical_to_logical_map: dict[str, str] | None = None,
    logical_to_physical_map: dict[str, str] | None = None,
) -> PhysicalQueryPlan:
    ir = AltrQueryIR(entity=target_entity)
    return PhysicalQueryPlan(
        logical_model_id="mod1",
        target_entity=target_entity,
        selected_source_id=selected_source_id,
        selected_source_name=f"Source_{selected_source_id}",
        selected_source_type=SourceType.POSTGRESQL,
        selected_mapping_id=f"map_{selected_source_id}",
        physical_entity_name=physical_entity_name,
        resolved_ir=ir,
        bound_ir=ir,
        classification=None,
        physical_query=None,
        logical_to_physical_map=logical_to_physical_map or {},
        physical_to_logical_map=physical_to_logical_map or {},
    )


def test_merge_federated_results_with_aliased_projection_and_sorting():
    """Verify federated merging correctly projects aliased columns and sorts by alias or canonical field."""
    from altr_stream.query_engine.domain.ast import FieldSelection

    ir = AltrQueryIR(
        operation=QueryOperation.READ,
        entity="students",
        projection=[
            FieldSelection(path=FieldPath(segments=["name"]), alias="student_name"),
            FieldSelection(path=FieldPath(segments=["gpa"]), alias="grade_point_avg"),
        ],
        sort=[SortClause(field=FieldPath(segments=["grade_point_avg"]), direction=SortDirection.DESC)],
        limit=2,
        offset=0,
    )

    plan_pg = _make_mock_physical_plan(
        selected_source_id="src_pg",
        physical_to_logical_map={"full_name": "name", "gpa_val": "gpa"},
    )
    plan_mysql = _make_mock_physical_plan(
        selected_source_id="src_mysql",
        physical_to_logical_map={"student_name": "name", "grade_point": "gpa"},
    )

    fed_plan = FederatedQueryPlan(
        logical_model_id="mod1",
        target_entity="students",
        logical_ir=ir,
        physical_plans=[plan_pg, plan_mysql],
    )

    res_pg = QueryResult(
        columns=["full_name", "gpa_val"],
        rows=[{"full_name": "Alice", "gpa_val": 3.8}],
        total_rows=1,
    )
    res_mysql = QueryResult(
        columns=["student_name", "grade_point"],
        rows=[{"student_name": "Bob", "grade_point": 3.9}],
        total_rows=1,
    )

    cols, rows = merge_federated_results(
        ir=ir,
        federated_plan=fed_plan,
        execution_results=[(plan_pg, res_pg), (plan_mysql, res_mysql)],
    )

    assert cols == ["student_name", "grade_point_avg"]
    assert len(rows) == 2
    assert rows[0] == {"student_name": "Bob", "grade_point_avg": 3.9}
    assert rows[1] == {"student_name": "Alice", "grade_point_avg": 3.8}


def test_merge_federated_results_offset_beyond_total_rows():
    """Verify OFFSET beyond total available rows safely returns empty list without error."""
    ir = AltrQueryIR(
        operation=QueryOperation.READ,
        entity="students",
        offset=100,
        limit=10,
    )
    plan = _make_mock_physical_plan(
        selected_source_id="src_pg",
        physical_to_logical_map={"full_name": "name"},
    )
    fed_plan = FederatedQueryPlan(
        logical_model_id="mod1",
        target_entity="students",
        logical_ir=ir,
        physical_plans=[plan],
    )
    res = QueryResult(
        columns=["full_name"],
        rows=[{"full_name": "Alice"}, {"full_name": "Bob"}],
        total_rows=2,
    )
    cols, rows = merge_federated_results(
        ir=ir,
        federated_plan=fed_plan,
        execution_results=[(plan, res)],
    )
    assert cols == ["name"]
    assert rows == []


def test_merge_federated_results_limit_zero():
    """Verify LIMIT 0 safely returns empty list with full columns."""
    ir = AltrQueryIR(
        operation=QueryOperation.READ,
        entity="students",
        limit=0,
    )
    plan = _make_mock_physical_plan(
        selected_source_id="src_pg",
        physical_to_logical_map={"full_name": "name"},
    )
    fed_plan = FederatedQueryPlan(
        logical_model_id="mod1",
        target_entity="students",
        logical_ir=ir,
        physical_plans=[plan],
    )
    res = QueryResult(
        columns=["full_name"],
        rows=[{"full_name": "Alice"}, {"full_name": "Bob"}],
        total_rows=2,
    )
    cols, rows = merge_federated_results(
        ir=ir,
        federated_plan=fed_plan,
        execution_results=[(plan, res)],
    )
    assert cols == ["name"]
    assert rows == []


def test_merge_federated_results_stable_tie_breaking():
    """Verify rows with tied sort keys preserve deterministic source order (source_id ASC)."""
    ir = AltrQueryIR(
        operation=QueryOperation.READ,
        entity="students",
        sort=[SortClause(field=FieldPath(segments=["gpa"]), direction=SortDirection.DESC)],
    )
    plan_a = _make_mock_physical_plan(
        selected_source_id="src_a",
        physical_to_logical_map={"name": "name", "gpa": "gpa"},
    )
    plan_b = _make_mock_physical_plan(
        selected_source_id="src_b",
        physical_to_logical_map={"name": "name", "gpa": "gpa"},
    )
    fed_plan = FederatedQueryPlan(
        logical_model_id="mod1",
        target_entity="students",
        logical_ir=ir,
        physical_plans=[plan_a, plan_b],
    )
    # Both have gpa=4.0 (tie)
    res_a = QueryResult(columns=["name", "gpa"], rows=[{"name": "Alice_from_A", "gpa": 4.0}])
    res_b = QueryResult(columns=["name", "gpa"], rows=[{"name": "Bob_from_B", "gpa": 4.0}])

    cols, rows = merge_federated_results(
        ir=ir,
        federated_plan=fed_plan,
        execution_results=[(plan_a, res_a), (plan_b, res_b)],
    )
    assert len(rows) == 2
    assert rows[0]["name"] == "Alice_from_A"
    assert rows[1]["name"] == "Bob_from_B"


def test_normalize_row_preserves_explicit_projection_aliases():
    """Verify normalize_row preserves explicit projection aliases while still dropping unmapped fields."""
    phys_to_log = {
        "roll_no": "roll_number",
        "student_name": "name",
        "cgpa": "cgpa",
    }
    raw_row = {
        "student_id": "MSQL001",
        "name": "Devansh Mehta",
        "cgpa": 9.3,
        "_id": "64f1234abcd5678",
        "unmapped_extra_col": "should_drop",
    }

    norm = normalize_row(
        row=raw_row,
        physical_to_logical=phys_to_log,
        preserve_unmapped=False,
        projected_aliases={"student_id"},
    )
    assert norm == {
        "student_id": "MSQL001",
        "name": "Devansh Mehta",
        "cgpa": 9.3,
    }
    assert "_id" not in norm
    assert "unmapped_extra_col" not in norm


def test_normalize_row_case_insensitive_aliases():
    """Verify normalize_row preserves aliases case-insensitively and maps to the requested alias casing."""
    phys_to_log = {
        "roll_no": "roll_number",
        "student_name": "name",
    }
    raw_row = {
        "STUDENT_ID": "SQL001",
        "name": "Rohan",
    }
    norm = normalize_row(
        row=raw_row,
        physical_to_logical=phys_to_log,
        preserve_unmapped=False,
        projected_aliases={"student_id"},
    )
    assert norm == {
        "student_id": "SQL001",
        "name": "Rohan",
    }


def test_normalize_row_multiple_aliases_and_different_physical_names():
    """Verify normalize_row preserves multiple explicit aliases where physical fields differ from logical."""
    phys_to_log = {
        "roll_no": "roll_number",
        "student_name": "name",
        "grade_point": "cgpa",
    }
    # Query: GET students (roll_number AS student_id, name AS display_name, cgpa AS score)
    raw_row = {
        "student_id": "MDB001",
        "display_name": "Neha Agarwal",
        "score": 9.1,
    }
    norm = normalize_row(
        row=raw_row,
        physical_to_logical=phys_to_log,
        preserve_unmapped=False,
        projected_aliases={"student_id", "display_name", "score"},
    )
    assert norm == {
        "student_id": "MDB001",
        "display_name": "Neha Agarwal",
        "score": 9.1,
    }


def test_merge_federated_results_query6_full_pipeline():
    """Verify merge_federated_results handles Query 6 across all 4 connectors returning aliased rows."""
    ir = AltrQueryIR(
        operation=QueryOperation.READ,
        entity="students",
        projection=[
            FieldSelection(path=FieldPath(segments=["roll_number"]), alias="student_id"),
            FieldSelection(path=FieldPath(segments=["name"]), alias=None),
            FieldSelection(path=FieldPath(segments=["cgpa"]), alias=None),
        ],
        sort=[SortClause(field=FieldPath(segments=["student_id"]), direction=SortDirection.ASC)],
        limit=5,
    )

    plan_mysql = _make_mock_physical_plan("mysql", physical_to_logical_map={"roll_no": "roll_number", "student_name": "name", "cgpa": "cgpa"})
    plan_pg = _make_mock_physical_plan("pg", physical_to_logical_map={"roll_number": "roll_number", "full_name": "name", "cgpa": "cgpa"})
    plan_sqlite = _make_mock_physical_plan("sqlite", physical_to_logical_map={"roll_number": "roll_number", "name": "name", "cgpa": "cgpa"})
    plan_mongo = _make_mock_physical_plan("mongo", physical_to_logical_map={"roll_number": "roll_number", "name": "name", "cgpa": "cgpa"})

    fed_plan = FederatedQueryPlan(
        logical_model_id="mod1",
        target_entity="students",
        logical_ir=ir,
        physical_plans=[plan_mysql, plan_pg, plan_sqlite, plan_mongo],
    )

    # Simulated connector outputs with aliases already produced by physical lowerers
    res_mysql = QueryResult(columns=["student_id", "name", "cgpa"], rows=[{"student_id": "MSQL001", "name": "Devansh Mehta", "cgpa": 9.3}])
    res_pg = QueryResult(columns=["student_id", "name", "cgpa"], rows=[{"student_id": "PG001", "name": "Riddhi Shah", "cgpa": 8.6}])
    res_sqlite = QueryResult(columns=["student_id", "name", "cgpa"], rows=[{"student_id": "SQL001", "name": "Gautam Singhal", "cgpa": 7.7}])
    res_mongo = QueryResult(columns=["student_id", "name", "cgpa"], rows=[{"student_id": "MDB001", "name": "Neha Agarwal", "cgpa": 9.1}])

    cols, rows = merge_federated_results(
        ir=ir,
        federated_plan=fed_plan,
        execution_results=[
            (plan_mysql, res_mysql),
            (plan_pg, res_pg),
            (plan_sqlite, res_sqlite),
            (plan_mongo, res_mongo),
        ],
    )

    assert cols == ["student_id", "name", "cgpa"]
    assert len(rows) == 4
    # Sorted by student_id ASC: MDB001, MSQL001, PG001, SQL001
    assert rows[0] == {"student_id": "MDB001", "name": "Neha Agarwal", "cgpa": 9.1}
    assert rows[1] == {"student_id": "MSQL001", "name": "Devansh Mehta", "cgpa": 9.3}
    assert rows[2] == {"student_id": "PG001", "name": "Riddhi Shah", "cgpa": 8.6}
    assert rows[3] == {"student_id": "SQL001", "name": "Gautam Singhal", "cgpa": 7.7}
    # Ensure no duplicate fields like roll_number exist
    for r in rows:
        assert "roll_number" not in r
        assert "student_id" in r

