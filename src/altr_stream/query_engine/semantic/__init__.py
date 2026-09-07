"""AltrQL semantic analysis and IR normalization module."""

from altr_stream.query_engine.semantic.normalizer import normalize_ir
from altr_stream.query_engine.semantic.validator import validate_ir

__all__ = [
    "validate_ir",
    "normalize_ir",
]
