"""Pure, deterministic mutation classifier for AltrQL v0.2."""

from __future__ import annotations

from altr_stream.query_engine.classification.models import (
    MutationClassification,
    MutationScope,
)
from altr_stream.query_engine.domain.ast import QueryOperation
from altr_stream.query_engine.domain.bound_ast import BoundAltrQueryIR


def classify_query(query: BoundAltrQueryIR) -> MutationClassification:
    """Classify a schema-bound query into operational categories and safety scopes.

    Guarantees:
    - 100% pure and deterministic.
    - Zero I/O, database access, or connector dependencies.
    - Mass mutations (UPDATE / DELETE with no WHERE clause) are flagged with requires_confirmation=True.
    """
    entity_name = query.entity.name

    if query.operation == QueryOperation.READ:
        return MutationClassification(
            operation=QueryOperation.READ,
            mutation_scope=MutationScope.NOT_APPLICABLE,
            requires_confirmation=False,
            entity=entity_name,
            description=f"Read query on entity '{entity_name}'.",
        )

    if query.operation == QueryOperation.CREATE:
        return MutationClassification(
            operation=QueryOperation.CREATE,
            mutation_scope=MutationScope.NOT_APPLICABLE,
            requires_confirmation=False,
            entity=entity_name,
            description=f"Create record on entity '{entity_name}'.",
        )

    if query.operation == QueryOperation.UPDATE:
        if query.where is None:
            return MutationClassification(
                operation=QueryOperation.UPDATE,
                mutation_scope=MutationScope.MASS,
                requires_confirmation=True,
                entity=entity_name,
                description=f"Mass UPDATE on entity '{entity_name}' without WHERE clause.",
            )
        return MutationClassification(
            operation=QueryOperation.UPDATE,
            mutation_scope=MutationScope.CONSTRAINED,
            requires_confirmation=False,
            entity=entity_name,
            description=f"Constrained UPDATE on entity '{entity_name}' with WHERE filter.",
        )

    if query.operation == QueryOperation.DELETE:
        if query.where is None:
            return MutationClassification(
                operation=QueryOperation.DELETE,
                mutation_scope=MutationScope.MASS,
                requires_confirmation=True,
                entity=entity_name,
                description=f"Mass DELETE on entity '{entity_name}' without WHERE clause.",
            )
        return MutationClassification(
            operation=QueryOperation.DELETE,
            mutation_scope=MutationScope.CONSTRAINED,
            requires_confirmation=False,
            entity=entity_name,
            description=f"Constrained DELETE on entity '{entity_name}' with WHERE filter.",
        )

    raise ValueError(f"Unknown query operation: {query.operation}")
