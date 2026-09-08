"""Strongly-typed Schema-Bound Abstract Syntax Tree (Bound AST) and IR models for AltrQL v0.1.

Attaches resolved schema metadata, logical type categories, and field properties
to logical AltrQL queries without lowering into physical SQL or database dialect representations.
"""

from __future__ import annotations

from enum import Enum
from typing import List, Literal, Optional, Union
from pydantic import Field

from altr_stream.domain.schema import StandardDataType
from altr_stream.query_engine.domain.ast import (
    ASTNode,
    FieldPath,
    LiteralValue,
    LogicalOperator,
    QueryOperation,
    Range,
    ValueSet,
)
from altr_stream.query_engine.domain.operators import (
    ComparisonOperator,
    RankingDirection,
    SortDirection,
    StringOperator,
)


class LogicalTypeCategory(str, Enum):
    """High-level logical data type categories for AltrQL operator/operand validation."""

    NUMERIC = "NUMERIC"
    STRING = "STRING"
    BOOLEAN = "BOOLEAN"
    TEMPORAL = "TEMPORAL"
    UNKNOWN = "UNKNOWN"


class BoundFieldPath(ASTNode):
    """Resolved field path annotated with schema type metadata and physical properties."""

    path: FieldPath
    data_type: StandardDataType
    logical_category: LogicalTypeCategory
    native_type: str
    nullable: bool = True
    is_primary_key: bool = False

    @property
    def full_path(self) -> str:
        return self.path.full_path

    @property
    def segments(self) -> List[str]:
        return self.path.segments


class BoundFieldSelection(ASTNode):
    """A projected field selection bound to schema metadata with an optional alias."""

    field: BoundFieldPath
    alias: Optional[str] = None


class BoundMutationAssignment(ASTNode):
    """Schema-bound field-to-value assignment in a mutation payload."""

    field: BoundFieldPath
    value: LiteralValue


class BoundCreateRecord(ASTNode):
    """Schema-bound individual record payload in a CREATE operation."""

    kind: Literal["bound_create_record"] = "bound_create_record"
    assignments: List[BoundMutationAssignment]


class BoundEntity(ASTNode):
    """Resolved entity metadata from the target data source schema."""

    name: str
    namespace: str = "default"
    entity_type: str = "TABLE"
    comment: Optional[str] = None


class BoundFieldExpression(ASTNode):
    """Atomic evaluation of a schema-bound field against an operator and operand."""

    kind: Literal["bound_field_expression"] = "bound_field_expression"
    field: BoundFieldPath
    operator: Union[ComparisonOperator, StringOperator]
    operand: Union[LiteralValue, ValueSet, Range]


class BoundLogicalExpression(ASTNode):
    """Binary boolean compound expression combining bound left and right with AND or OR."""

    kind: Literal["bound_logical_expression"] = "bound_logical_expression"
    operator: LogicalOperator
    left: BoundExpression
    right: BoundExpression


class BoundNegationExpression(ASTNode):
    """Unary boolean negation expression on a bound expression."""

    kind: Literal["bound_negation_expression"] = "bound_negation_expression"
    operand: BoundExpression


BoundExpression = Union[BoundLogicalExpression, BoundNegationExpression, BoundFieldExpression]

# Rebuild models for recursive type reference
BoundLogicalExpression.model_rebuild()
BoundNegationExpression.model_rebuild()


class BoundSortClause(ASTNode):
    """Individual sorting requirement on a schema-bound field."""

    field: BoundFieldPath
    direction: SortDirection = SortDirection.ASC


class BoundRankingClause(ASTNode):
    """Top-level ranking expression on a schema-bound field."""

    direction: RankingDirection
    count: int
    field: BoundFieldPath


class BoundAltrQueryIR(ASTNode):
    """Root representation of a schema-bound and type-validated AltrQL query.

    Contains complete logical query semantics plus resolved source and field metadata.
    """

    operation: QueryOperation = QueryOperation.READ
    entity: BoundEntity
    projection: List[BoundFieldSelection] = Field(default_factory=list)
    where: Optional[BoundExpression] = None
    assignments: List[BoundMutationAssignment] = Field(default_factory=list)
    records: List[BoundCreateRecord] = Field(default_factory=list)
    sort: List[BoundSortClause] = Field(default_factory=list)
    ranking: Optional[BoundRankingClause] = None
    offset: Optional[int] = None
    source_id: str
    source_name: str

    @property
    def is_wildcard_projection(self) -> bool:
        """True if all fields are implicitly selected."""
        return len(self.projection) == 0
