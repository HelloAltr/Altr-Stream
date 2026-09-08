"""Binding and type validation subsystem for AltrQL."""

from altr_stream.query_engine.binding.binder import bind_altrql
from altr_stream.query_engine.binding.resolver import resolve_entity, resolve_field_path
from altr_stream.query_engine.binding.type_validator import (
    to_logical_category,
    validate_assignment_value,
    validate_field_operator_and_operand,
)

__all__ = [
    "bind_altrql",
    "resolve_entity",
    "resolve_field_path",
    "to_logical_category",
    "validate_assignment_value",
    "validate_field_operator_and_operand",
]
