"""Strongly-typed Abstract Syntax Tree (AST) and Intermediate Representation (IR) models for AltrQL v0.2."""

from __future__ import annotations

from enum import Enum
from typing import Any, List, Literal, Optional, Union
from pydantic import BaseModel, ConfigDict, Field

from altr_stream.query_engine.domain.operators import (
    ComparisonOperator,
    RankingDirection,
    SortDirection,
    StringOperator,
    TemporalKeyword,
)


class ASTNode(BaseModel):
    """Base class for all AltrQL AST nodes."""

    model_config = ConfigDict(frozen=True, extra="forbid")

    def to_dict(self) -> dict[str, Any]:
        """Serialize AST node to dictionary."""
        return self.model_dump()


# ---------------------------------------------------------------------------
# Field Paths & Projections
# ---------------------------------------------------------------------------


class FieldPath(ASTNode):
    """Represents a direct or nested field access path (e.g. 'id' or 'address.country')."""

    segments: List[str]

    @property
    def full_path(self) -> str:
        return ".".join(self.segments)

    @property
    def root(self) -> str:
        return self.segments[0]

    @property
    def leaf(self) -> str:
        return self.segments[-1]

    @property
    def is_nested(self) -> bool:
        return len(self.segments) > 1

    def __str__(self) -> str:
        return self.full_path


class FieldSelection(ASTNode):
    """A projected field with an optional alias."""

    path: FieldPath
    alias: Optional[str] = None


# ---------------------------------------------------------------------------
# Literals
# ---------------------------------------------------------------------------


class StringLiteral(ASTNode):
    kind: Literal["string"] = "string"
    value: str


class IntegerLiteral(ASTNode):
    kind: Literal["integer"] = "integer"
    value: int


class FloatLiteral(ASTNode):
    kind: Literal["float"] = "float"
    value: float


class BooleanLiteral(ASTNode):
    kind: Literal["boolean"] = "boolean"
    value: bool


class NullLiteral(ASTNode):
    kind: Literal["null"] = "null"


class TemporalLiteral(ASTNode):
    kind: Literal["temporal"] = "temporal"
    keyword: Optional[TemporalKeyword] = None
    value: Optional[str] = None


LiteralValue = Union[
    StringLiteral,
    IntegerLiteral,
    FloatLiteral,
    BooleanLiteral,
    NullLiteral,
    TemporalLiteral,
]


# ---------------------------------------------------------------------------
# Ranges and Value Set Constraints
# ---------------------------------------------------------------------------


class Range(ASTNode):
    """Inclusive or exclusive continuous range (e.g. 18..30)."""

    kind: Literal["range"] = "range"
    start: LiteralValue
    end: LiteralValue
    inclusive: bool = True


class ComparisonConstraint(ASTNode):
    """Single comparison operator and literal value constraint (e.g. >18 or <=60)."""

    kind: Literal["comparison_constraint"] = "comparison_constraint"
    operator: ComparisonOperator
    value: LiteralValue


class CompoundAndConstraint(ASTNode):
    """Conjunction of multiple comparison constraints joined by & (e.g. >=18 & <=30)."""

    kind: Literal["compound_and_constraint"] = "compound_and_constraint"
    constraints: List[ComparisonConstraint]


ValueSetElement = Union[
    LiteralValue,
    Range,
    ComparisonConstraint,
    CompoundAndConstraint,
]


class ValueSet(ASTNode):
    """A set of alternative constraints or literals enclosed in { ... } representing OR logic."""

    kind: Literal["value_set"] = "value_set"
    elements: List[ValueSetElement]


# ---------------------------------------------------------------------------
# Expressions (WHERE tree)
# ---------------------------------------------------------------------------


class FieldExpression(ASTNode):
    """Atomic field evaluation against a value, string operator, range, or value set."""

    kind: Literal["field_expression"] = "field_expression"
    field: FieldPath
    operator: Union[ComparisonOperator, StringOperator]
    operand: Union[LiteralValue, ValueSet, Range]


class LogicalExpression(ASTNode):
    """Boolean compound expression combining operands with AND or OR."""

    kind: Literal["logical_expression"] = "logical_expression"
    operator: Literal["AND", "OR"]
    operands: List[Expression]


Expression = Union[LogicalExpression, FieldExpression]

# Rebuild model for recursive type reference
LogicalExpression.model_rebuild()


# ---------------------------------------------------------------------------
# Query Operations & Mutation Payloads
# ---------------------------------------------------------------------------


class QueryOperation(str, Enum):
    """Supported AltrQL root query operations."""

    READ = "READ"
    CREATE = "CREATE"
    UPDATE = "UPDATE"
    DELETE = "DELETE"


class MutationAssignment(ASTNode):
    """Field-to-value assignment in a mutation payload (e.g. 'is_active: TRUE')."""

    field: FieldPath
    value: LiteralValue


# ---------------------------------------------------------------------------
# Sorting, Ranking, and Pagination Clauses
# ---------------------------------------------------------------------------


class SortClause(ASTNode):
    """Individual sorting requirement on a field."""

    field: FieldPath
    direction: SortDirection = SortDirection.ASC


class RankingClause(ASTNode):
    """Top-level ranking expression (TOP n BY field or BOTTOM n BY field)."""

    direction: RankingDirection
    count: int
    field: FieldPath


# ---------------------------------------------------------------------------
# Root Query Intermediate Representation (IR)
# ---------------------------------------------------------------------------


class AltrQueryIR(ASTNode):
    """Root representation of an AltrQL query."""

    operation: QueryOperation = QueryOperation.READ
    entity: str
    projection: List[FieldSelection] = Field(default_factory=list)
    where: Optional[Expression] = None
    assignments: List[MutationAssignment] = Field(default_factory=list)
    sort: List[SortClause] = Field(default_factory=list)
    ranking: Optional[RankingClause] = None
    offset: Optional[int] = None

    @property
    def is_wildcard_projection(self) -> bool:
        """True if all fields are implicitly selected."""
        return len(self.projection) == 0
