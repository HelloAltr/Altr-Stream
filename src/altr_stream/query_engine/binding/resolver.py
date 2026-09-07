"""Schema resolver for AltrQL v0.1.

Resolves logical query entity names and field paths against an in-memory SourceSchema snapshot.
"""

from __future__ import annotations

from altr_stream.domain.schema import EntitySchema, FieldSchema, SourceSchema
from altr_stream.query_engine.domain.ast import FieldPath
from altr_stream.query_engine.domain.errors import UnknownEntityError, UnknownFieldError


def resolve_entity(entity_name: str, schema: SourceSchema) -> EntitySchema:
    """Resolve an entity name against a SourceSchema snapshot.

    Raises:
        UnknownEntityError: If entity_name does not match any EntitySchema in the source.
    """
    for entity in schema.entities:
        if entity.name == entity_name:
            return entity

    raise UnknownEntityError(
        f"Unknown entity '{entity_name}' in source schema '{schema.source_name}'."
    )


def resolve_field_path(field_path: FieldPath, entity: EntitySchema) -> FieldSchema:
    """Resolve a field path against an EntitySchema.

    For flat relational entities (the current schema model), single-segment paths match
    directly against entity fields. Multi-segment nested paths are checked as literal field
    names or explicitly rejected with an informative error.

    Raises:
        UnknownFieldError: If field_path cannot be resolved against entity.
    """
    if len(field_path.segments) == 1:
        field_name = field_path.segments[0]
        field = entity.get_field(field_name)
        if field is not None:
            return field
        raise UnknownFieldError(
            f"Unknown field '{field_name}' on entity '{entity.name}'."
        )

    # Multi-segment nested path
    direct_match = entity.get_field(field_path.full_path)
    if direct_match is not None:
        return direct_match

    raise UnknownFieldError(
        f"Unknown field '{field_path.full_path}' on entity '{entity.name}'. "
        f"Nested field structures are not supported on flat schema entity '{entity.name}'."
    )
