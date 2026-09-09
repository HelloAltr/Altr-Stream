"""Unit tests for pure deterministic AltrQL v0.4 mutation classification."""

from datetime import datetime, timezone
import pytest

from altr_stream.domain.schema import (
    EntitySchema,
    FieldSchema,
    SourceSchema,
    StandardDataType,
)
from altr_stream.query_engine.binding import bind_altrql
from altr_stream.query_engine.classification import (
    MutationClassification,
    MutationScope,
    classify_query,
)
from altr_stream.query_engine.domain.ast import QueryOperation
from altr_stream.query_engine.parser import parse_altrql


@pytest.fixture
def test_schema() -> SourceSchema:
    return SourceSchema(
        source_id="src_1",
        source_name="Postgres",
        entities=[
            EntitySchema(
                name="users",
                namespace="public",
                entity_type="TABLE",
                fields=[
                    FieldSchema(name="id", data_type=StandardDataType.INTEGER, native_data_type="int4", is_primary_key=True),
                    FieldSchema(name="username", data_type=StandardDataType.STRING, native_data_type="varchar"),
                    FieldSchema(name="email", data_type=StandardDataType.STRING, native_data_type="varchar"),
                    FieldSchema(name="is_active", data_type=StandardDataType.BOOLEAN, native_data_type="bool"),
                ],
            )
        ],
        discovered_at=datetime.now(timezone.utc),
    )


def test_classify_read_query(test_schema: SourceSchema):
    """READ queries are classified with NOT_APPLICABLE and requires_confirmation=False."""
    bound = bind_altrql(parse_altrql("GET users;"), test_schema)
    res = classify_query(bound)

    assert res.operation == QueryOperation.READ
    assert res.mutation_scope == MutationScope.NOT_APPLICABLE
    assert res.requires_confirmation is False
    assert res.entity == "users"


def test_classify_create_query(test_schema: SourceSchema):
    """CREATE mutations are classified with NOT_APPLICABLE and requires_confirmation=False."""
    bound = bind_altrql(parse_altrql('CREATE users ( username: "alice" );'), test_schema)
    res = classify_query(bound)

    assert res.operation == QueryOperation.CREATE
    assert res.mutation_scope == MutationScope.NOT_APPLICABLE
    assert res.requires_confirmation is False
    assert res.entity == "users"


def test_classify_constrained_update_query(test_schema: SourceSchema):
    """UPDATE with WHERE is classified as CONSTRAINED with requires_confirmation=False."""
    bound = bind_altrql(
        parse_altrql('UPDATE users ( email: "updated@test.com" ) WHERE { id = 1 };'),
        test_schema,
    )
    res = classify_query(bound)

    assert res.operation == QueryOperation.UPDATE
    assert res.mutation_scope == MutationScope.CONSTRAINED
    assert res.requires_confirmation is False
    assert res.entity == "users"


def test_classify_mass_update_query(test_schema: SourceSchema):
    """UPDATE without WHERE in BoundAltrQueryIR is classified as MASS with requires_confirmation=True."""
    from altr_stream.query_engine.domain.bound_ast import BoundAltrQueryIR, BoundEntity
    bound = BoundAltrQueryIR(
        operation=QueryOperation.UPDATE,
        source_id="src_1",
        source_name="Postgres",
        entity=BoundEntity(name="users", namespace="public"),
        where=None,
    )
    res = classify_query(bound)

    assert res.operation == QueryOperation.UPDATE
    assert res.mutation_scope == MutationScope.MASS
    assert res.requires_confirmation is True
    assert res.entity == "users"


def test_classify_constrained_delete_query(test_schema: SourceSchema):
    """DELETE with WHERE is classified as CONSTRAINED with requires_confirmation=False."""
    bound = bind_altrql(
        parse_altrql('DELETE users WHERE { id = 1 };'),
        test_schema,
    )
    res = classify_query(bound)

    assert res.operation == QueryOperation.DELETE
    assert res.mutation_scope == MutationScope.CONSTRAINED
    assert res.requires_confirmation is False
    assert res.entity == "users"


def test_classify_mass_delete_query(test_schema: SourceSchema):
    """DELETE without WHERE is classified as MASS with requires_confirmation=True."""
    bound = bind_altrql(
        parse_altrql('DELETE users;'),
        test_schema,
    )
    res = classify_query(bound)

    assert res.operation == QueryOperation.DELETE
    assert res.mutation_scope == MutationScope.MASS
    assert res.requires_confirmation is True
    assert res.entity == "users"
