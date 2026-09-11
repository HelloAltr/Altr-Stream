"""Unit tests for logical-to-physical AltrQL IR resolver."""

import pytest
from altr_stream.domain.errors import LogicalEntityNotFoundError
from altr_stream.domain.mapping import EntityMapping, FieldMapping, SourceMapping
from altr_stream.query_engine.binding.logical_resolver import resolve_logical_ir
from altr_stream.query_engine.domain.ast import (
    AltrQueryIR,
    CreateRecord,
    FieldExpression,
    FieldPath,
    FieldSelection,
    IntegerLiteral,
    LogicalExpression,
    LogicalOperator,
    MutationAssignment,
    NegationExpression,
    QueryOperation,
    RankingClause,
    RankingDirection,
    SortClause,
    SortDirection,
    StringLiteral,
)
from altr_stream.query_engine.domain.operators import ComparisonOperator, StringOperator
from altr_stream.query_engine.parser import parse_altrql


@pytest.fixture
def test_mapping() -> SourceMapping:
    fm_id = FieldMapping(
        entity_mapping_id="em-1",
        logical_field_id="lf-1",
        logical_field_name="id",
        physical_field_name="student_id",
    )
    fm_name = FieldMapping(
        entity_mapping_id="em-1",
        logical_field_id="lf-2",
        logical_field_name="name",
        physical_field_name="full_name",
    )
    fm_email = FieldMapping(
        entity_mapping_id="em-1",
        logical_field_id="lf-3",
        logical_field_name="email",
        physical_field_name="email_addr",
    )
    fm_dept = FieldMapping(
        entity_mapping_id="em-1",
        logical_field_id="lf-4",
        logical_field_name="department",
        physical_field_name="dept",
    )

    em = EntityMapping(
        id="em-1",
        source_mapping_id="sm-1",
        logical_entity_id="le-1",
        logical_entity_name="Student",
        physical_entity_name="students_tbl",
        physical_namespace="public",
        field_mappings=[fm_id, fm_name, fm_email, fm_dept],
    )

    return SourceMapping(
        id="sm-1",
        logical_model_id="lm-1",
        source_id="src-1",
        entity_mappings=[em],
    )


def test_resolve_simple_get_projection(test_mapping: SourceMapping):
    query = "GET Student(id, name, email);"
    ir = parse_altrql(query)

    resolved = resolve_logical_ir(ir, test_mapping)

    assert resolved.entity == "students_tbl"
    assert len(resolved.projection) == 3
    assert resolved.projection[0].path.full_path == "student_id"
    assert resolved.projection[1].path.full_path == "full_name"
    assert resolved.projection[2].path.full_path == "email_addr"


def test_resolve_where_expressions(test_mapping: SourceMapping):
    query = 'GET Student(id) WHERE { department = "Computer Science", { name = "Alice" OR email != "none" } };'
    ir = parse_altrql(query)

    resolved = resolve_logical_ir(ir, test_mapping)

    assert resolved.entity == "students_tbl"
    # Check WHERE tree
    assert isinstance(resolved.where, LogicalExpression)
    left = resolved.where.left
    assert isinstance(left, FieldExpression)
    assert left.field.full_path == "dept"

    right = resolved.where.right
    assert isinstance(right, LogicalExpression)
    assert isinstance(right.left, FieldExpression)
    assert right.left.field.full_path == "full_name"
    assert isinstance(right.right, FieldExpression)
    assert right.right.field.full_path == "email_addr"


def test_resolve_sort_and_ranking(test_mapping: SourceMapping):
    query_sort = "GET Student(id, name) SORT { name DESC };"
    ir_sort = parse_altrql(query_sort)
    resolved_sort = resolve_logical_ir(ir_sort, test_mapping)
    assert resolved_sort.sort[0].field.full_path == "full_name"
    assert resolved_sort.sort[0].direction == SortDirection.DESC

    query_rank = "GET Student(id, name) TOP 5 BY id;"
    ir_rank = parse_altrql(query_rank)
    resolved_rank = resolve_logical_ir(ir_rank, test_mapping)
    assert resolved_rank.ranking.field.full_path == "student_id"
    assert resolved_rank.ranking.count == 5


def test_resolve_mutation_assignments_and_records(test_mapping: SourceMapping):
    query = 'CREATE Student (name: "Bob", email: "bob@example.com", department: "Physics");'
    ir = parse_altrql(query)

    resolved = resolve_logical_ir(ir, test_mapping)

    assert resolved.entity == "students_tbl"
    assert len(resolved.records[0].assignments) == 3
    assert resolved.records[0].assignments[0].field.full_path == "full_name"
    assert resolved.records[0].assignments[1].field.full_path == "email_addr"
    assert resolved.records[0].assignments[2].field.full_path == "dept"


def test_resolve_unmapped_entity_raises(test_mapping: SourceMapping):
    query = "GET Professor(id, name);"
    ir = parse_altrql(query)

    with pytest.raises(LogicalEntityNotFoundError):
        resolve_logical_ir(ir, test_mapping)


def test_resolve_update_and_delete_mutations(test_mapping: SourceMapping):
    query_update = 'UPDATE Student(email: "alice_new@example.com") WHERE { id = 1 };'
    ir_update = parse_altrql(query_update)
    resolved_update = resolve_logical_ir(ir_update, test_mapping)
    assert resolved_update.entity == "students_tbl"
    assert resolved_update.assignments[0].field.full_path == "email_addr"
    assert isinstance(resolved_update.where, FieldExpression)
    assert resolved_update.where.field.full_path == "student_id"

    query_delete = 'DELETE Student WHERE { department = "Physics" };'
    ir_delete = parse_altrql(query_delete)
    resolved_delete = resolve_logical_ir(ir_delete, test_mapping)
    assert resolved_delete.entity == "students_tbl"
    assert resolved_delete.where.field.full_path == "dept"


def test_resolve_not_and_has_expressions(test_mapping: SourceMapping):
    query = 'GET Student(id) WHERE { NOT { email HAS "spam" } };'
    ir = parse_altrql(query)
    resolved = resolve_logical_ir(ir, test_mapping)
    assert resolved.entity == "students_tbl"
    assert isinstance(resolved.where, NegationExpression)
    assert resolved.where.operand.field.full_path == "email_addr"

