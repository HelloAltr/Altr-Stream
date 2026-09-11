"""Unit tests for Mapping Registry domain objects."""

import pytest
from altr_stream.domain.mapping import (
    EntityMapping,
    FieldMapping,
    MappingProvenance,
    MappingStatus,
    SourceMapping,
)


def test_field_mapping_creation():
    fm = FieldMapping(
        entity_mapping_id="em-1",
        logical_field_id="lf-1",
        logical_field_name="email",
        physical_field_name="user_email",
        transformation_rule="DIRECT_ALIAS",
    )
    assert fm.logical_field_name == "email"
    assert fm.physical_field_name == "user_email"
    assert fm.transformation_rule == "DIRECT_ALIAS"


def test_entity_mapping_lookup():
    fm1 = FieldMapping(entity_mapping_id="em-1", logical_field_id="lf-1", logical_field_name="id", physical_field_name="student_id")
    fm2 = FieldMapping(entity_mapping_id="em-1", logical_field_id="lf-2", logical_field_name="name", physical_field_name="full_name")

    em = EntityMapping(
        id="em-1",
        source_mapping_id="sm-1",
        logical_entity_id="le-1",
        logical_entity_name="Student",
        physical_entity_name="tbl_students",
        physical_namespace="public",
        field_mappings=[fm1, fm2],
    )
    assert em.logical_entity_name == "Student"
    assert em.physical_entity_name == "tbl_students"
    assert em.field_mapping_count == 2
    assert em.get_field_mapping_by_logical_name("id") == fm1
    assert em.get_field_mapping_by_logical_name("name") == fm2
    assert em.get_field_mapping_by_logical_name("missing") is None
    assert em.get_field_mapping_by_logical_id("lf-1") == fm1


def test_source_mapping_properties():
    fm1 = FieldMapping(entity_mapping_id="em-1", logical_field_id="lf-1", logical_field_name="id", physical_field_name="student_id")
    em1 = EntityMapping(
        id="em-1",
        source_mapping_id="sm-1",
        logical_entity_id="le-1",
        logical_entity_name="Student",
        physical_entity_name="students",
        field_mappings=[fm1],
    )

    sm = SourceMapping(
        id="sm-1",
        logical_model_id="lm-1",
        source_id="src-1",
        version="1.0.0",
        status=MappingStatus.ACTIVE,
        provenance=MappingProvenance.USER,
        entity_mappings=[em1],
    )
    assert sm.status == MappingStatus.ACTIVE
    assert sm.provenance == MappingProvenance.USER
    assert sm.entity_mapping_count == 1
    assert sm.total_field_mapping_count == 1
    assert sm.get_entity_mapping_by_logical_name("Student") == em1
    assert sm.get_entity_mapping_by_logical_name("Unknown") is None
