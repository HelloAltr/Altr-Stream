"""Unit tests for Logical Data Model domain objects."""

import pytest
from altr_stream.domain.logical import LogicalEntity, LogicalField, LogicalModel
from altr_stream.domain.schema import StandardDataType


def test_logical_field_creation():
    field = LogicalField(
        logical_entity_id="entity-1",
        name="email",
        data_type=StandardDataType.STRING,
        is_primary_key=False,
        nullable=True,
    )
    assert field.name == "email"
    assert field.data_type == StandardDataType.STRING
    assert field.is_primary_key is False
    assert field.nullable is True
    assert field.id is not None


def test_logical_entity_creation_and_field_lookup():
    f1 = LogicalField(logical_entity_id="e-1", name="id", data_type=StandardDataType.INTEGER, is_primary_key=True)
    f2 = LogicalField(logical_entity_id="e-1", name="name", data_type=StandardDataType.STRING)

    entity = LogicalEntity(
        id="e-1",
        logical_model_id="m-1",
        name="Student",
        description="University student entity",
        fields=[f1, f2],
    )
    assert entity.name == "Student"
    assert entity.field_count == 2
    assert entity.get_field_by_name("id") == f1
    assert entity.get_field_by_name("name") == f2
    assert entity.get_field_by_name("non_existent") is None
    assert entity.get_field_by_id(f1.id) == f1


def test_logical_model_creation_and_entity_lookup():
    f1 = LogicalField(logical_entity_id="e-1", name="student_id", data_type=StandardDataType.INTEGER, is_primary_key=True)
    e1 = LogicalEntity(id="e-1", logical_model_id="m-1", name="Student", fields=[f1])

    f2 = LogicalField(logical_entity_id="e-2", name="course_id", data_type=StandardDataType.INTEGER, is_primary_key=True)
    e2 = LogicalEntity(id="e-2", logical_model_id="m-1", name="Course", fields=[f2])

    model = LogicalModel(
        id="m-1",
        name="UniversityModel",
        version="1.0.0",
        description="Academic domain model",
        entities=[e1, e2],
    )
    assert model.name == "UniversityModel"
    assert model.entity_count == 2
    assert model.total_field_count == 2
    assert model.get_entity_by_name("Student") == e1
    assert model.get_entity_by_name("Course") == e2
    assert model.get_entity_by_name("Department") is None
    assert model.get_entity_by_id("e-1") == e1
