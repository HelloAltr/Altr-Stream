"""Source selection engine for deterministic, capability-aware physical source resolution."""

from __future__ import annotations

from typing import Any

from altr_stream.domain.connector import ParameterStyle, SourceCapabilities
from altr_stream.domain.errors import (
    IncompleteFieldMappingError,
    NoActiveSourceMappingError,
    SourceCapabilityMismatchError,
)
from altr_stream.domain.mapping import ResolvedSourceCandidate
from altr_stream.domain.source import SourceType
from altr_stream.query_engine.domain.ast import (
    AltrQueryIR,
    Expression,
    FieldExpression,
    LogicalExpression,
    NegationExpression,
    QueryOperation,
)
from altr_stream.query_engine.planning.models import (
    CandidateEvaluation,
    LogicalPlanContext,
)


def get_static_source_capabilities(source_type: SourceType) -> SourceCapabilities:
    """Return verified static SourceCapabilities for a given source type without database I/O."""
    if source_type == SourceType.POSTGRESQL:
        return SourceCapabilities(
            schema_discovery=True,
            read=True,
            write=True,
            cdc=False,
            batch_execution=True,
            streaming=False,
            custom_query=True,
            supports_transactions=True,
            supports_returning=True,
            supports_date_only_equality=True,
            parameter_style=ParameterStyle.POSITIONAL_NUMERIC,
            max_batch_size=1000,
            entity_types=["TABLE", "VIEW"],
            supported_operations=["SELECT", "INSERT", "UPDATE", "DELETE", "SCHEMA_DISCOVERY"],
        )
    elif source_type == SourceType.MYSQL:
        return SourceCapabilities(
            schema_discovery=True,
            read=True,
            write=True,
            cdc=False,
            batch_execution=True,
            streaming=False,
            custom_query=True,
            supports_transactions=True,
            supports_returning=False,
            supports_date_only_equality=True,
            parameter_style=ParameterStyle.POSITIONAL_FORMAT,
            max_batch_size=1000,
            entity_types=["TABLE", "VIEW"],
            supported_operations=["SELECT", "INSERT", "UPDATE", "DELETE", "SCHEMA_DISCOVERY"],
        )
    elif source_type == SourceType.SQLITE:
        return SourceCapabilities(
            schema_discovery=True,
            read=True,
            write=True,
            cdc=False,
            batch_execution=True,
            streaming=False,
            custom_query=True,
            supports_transactions=True,
            supports_returning=True,
            supports_date_only_equality=True,
            parameter_style=ParameterStyle.POSITIONAL_QMARK,
            max_batch_size=1000,
            entity_types=["TABLE", "VIEW"],
            supported_operations=["SELECT", "INSERT", "UPDATE", "DELETE", "SCHEMA_DISCOVERY"],
        )
    elif source_type == SourceType.MONGODB:
        return SourceCapabilities(
            schema_discovery=True,
            read=True,
            write=True,
            cdc=False,
            batch_execution=True,
            streaming=False,
            custom_query=True,
            supports_transactions=True,
            supports_returning=True,
            supports_date_only_equality=True,
            parameter_style=ParameterStyle.DOCUMENT_BSON,
            max_batch_size=1000,
            entity_types=["COLLECTION"],
            supported_operations=["find", "insert_many", "update_many", "delete_many", "SCHEMA_DISCOVERY"],
        )
    # Default fallback
    return SourceCapabilities(custom_query=True)


def extract_logical_context(ir: AltrQueryIR, logical_model_id: str) -> LogicalPlanContext:
    """Extract all referenced logical entities and fields from an AST into a planning context."""
    projected: list[str] = []
    if not ir.is_wildcard_projection:
        for sel in ir.projection:
            projected.append(sel.path.root)

    filter_fields: list[str] = []

    def _collect_expr_fields(expr: Expression | None) -> None:
        if expr is None:
            return
        if isinstance(expr, FieldExpression):
            filter_fields.append(expr.field.root)
        elif isinstance(expr, LogicalExpression):
            _collect_expr_fields(expr.left)
            _collect_expr_fields(expr.right)
        elif isinstance(expr, NegationExpression):
            _collect_expr_fields(expr.operand)

    _collect_expr_fields(ir.where)

    mutation_fields: list[str] = []
    for a in ir.assignments:
        mutation_fields.append(a.field.root)
    for rec in ir.records:
        for a in rec.assignments:
            mutation_fields.append(a.field.root)

    sort_fields: list[str] = []
    for s in ir.sort:
        sort_fields.append(s.field.root)
    if ir.ranking:
        sort_fields.append(ir.ranking.field.root)

    return LogicalPlanContext(
        logical_model_id=logical_model_id,
        target_entity=ir.entity,
        operation=ir.operation,
        is_wildcard=ir.is_wildcard_projection,
        projected_fields=projected,
        filter_fields=filter_fields,
        mutation_fields=mutation_fields,
        sort_fields=sort_fields,
        requires_returning=ir.operation in (QueryOperation.CREATE, QueryOperation.UPDATE, QueryOperation.DELETE),
        requires_transactions=False,
    )


def coerce_source_type(val: SourceType | str) -> SourceType:
    """Coerce string or enum to SourceType enum safely."""
    if isinstance(val, SourceType):
        return val
    try:
        return SourceType(val.upper())
    except (ValueError, KeyError):
        return SourceType[val.upper()]


class SourceSelector:
    """Evaluates candidate source mappings against query requirements and applies deterministic selection."""

    def evaluate_candidates(
        self,
        context: LogicalPlanContext,
        candidates: list[ResolvedSourceCandidate],
    ) -> tuple[list[ResolvedSourceCandidate], list[CandidateEvaluation]]:
        """Evaluate and filter candidate mappings by field coverage and connector capabilities."""
        evaluations: list[CandidateEvaluation] = []
        eligible_candidates: list[ResolvedSourceCandidate] = []

        referenced_fields = {f.lower() for f in context.all_referenced_fields}

        for cand in candidates:
            mapped_fields = {fm.logical_field_name.lower() for fm in cand.field_mappings if fm.logical_field_name}
            mapped_fields.update(fm.physical_field_name.lower() for fm in cand.field_mappings if fm.physical_field_name)
            unmapped = [
                f for f in referenced_fields
                if f not in mapped_fields and f.rstrip("s") not in {mf.rstrip("s") for mf in mapped_fields}
            ]
            missing_caps: list[str] = []

            source_type_enum = coerce_source_type(cand.source_type)
            caps = get_static_source_capabilities(source_type_enum)

            # Check field coverage
            if unmapped:
                evaluations.append(
                    CandidateEvaluation(
                        source_id=cand.source_id,
                        source_name=cand.source_name,
                        source_type=source_type_enum,
                        mapping_id=cand.mapping_id,
                        physical_entity_name=cand.physical_entity_name,
                        is_eligible=False,
                        rejection_reason=f"Candidate does not map required logical field(s): {', '.join(unmapped)}",
                        unmapped_fields=unmapped,
                        missing_capabilities=[],
                    )
                )
                continue

            # Check capabilities
            if context.operation in (QueryOperation.CREATE, QueryOperation.UPDATE, QueryOperation.DELETE):
                if not caps.custom_query:
                    missing_caps.append("custom_query")

            if missing_caps:
                evaluations.append(
                    CandidateEvaluation(
                        source_id=cand.source_id,
                        source_name=cand.source_name,
                        source_type=source_type_enum,
                        mapping_id=cand.mapping_id,
                        physical_entity_name=cand.physical_entity_name,
                        is_eligible=False,
                        rejection_reason=f"Candidate lacks required capabilities: {', '.join(missing_caps)}",
                        unmapped_fields=[],
                        missing_capabilities=missing_caps,
                    )
                )
                continue

            # Candidate is eligible
            evaluations.append(
                CandidateEvaluation(
                    source_id=cand.source_id,
                    source_name=cand.source_name,
                    source_type=source_type_enum,
                    mapping_id=cand.mapping_id,
                    physical_entity_name=cand.physical_entity_name,
                    is_eligible=True,
                    rejection_reason=None,
                    unmapped_fields=[],
                    missing_capabilities=[],
                )
            )
            eligible_candidates.append(cand)

        return eligible_candidates, evaluations

    def select_all_eligible_sources(
        self,
        context: LogicalPlanContext,
        candidates: list[ResolvedSourceCandidate],
    ) -> tuple[list[ResolvedSourceCandidate], list[CandidateEvaluation]]:
        """Select all compatible physical candidate sources deterministically for federated execution.

        Raises:
            NoActiveSourceMappingError: If no candidates were provided.
            IncompleteFieldMappingError: If all candidates were rejected due to unmapped fields.
            SourceCapabilityMismatchError: If all candidates were rejected due to unsupported capabilities.
        """
        if not candidates:
            raise NoActiveSourceMappingError(
                entity_name=context.target_entity,
                model_id=context.logical_model_id,
            )

        eligible, evaluations = self.evaluate_candidates(context, candidates)

        if not eligible:
            # Diagnose rejection reason
            unmapped_all: set[str] = set()
            caps_all: set[str] = set()
            for ev in evaluations:
                unmapped_all.update(ev.unmapped_fields)
                caps_all.update(ev.missing_capabilities)

            if unmapped_all:
                raise IncompleteFieldMappingError(
                    entity_name=context.target_entity,
                    unmapped_fields=sorted(list(unmapped_all)),
                )
            elif caps_all:
                raise SourceCapabilityMismatchError(
                    entity_name=context.target_entity,
                    capability=", ".join(sorted(list(caps_all))),
                )
            else:
                raise NoActiveSourceMappingError(
                    entity_name=context.target_entity,
                    model_id=context.logical_model_id,
                )

        # Deterministic stable sort: (source_id ASC, mapping_id ASC)
        sorted_eligible = sorted(
            eligible,
            key=lambda c: (c.source_id, c.mapping_id),
        )

        return sorted_eligible, evaluations

    def select_source(
        self,
        context: LogicalPlanContext,
        candidates: list[ResolvedSourceCandidate],
    ) -> tuple[ResolvedSourceCandidate, list[CandidateEvaluation]]:
        """Select exactly one physical candidate source deterministically.

        Raises:
            NoActiveSourceMappingError: If no candidates were provided.
            IncompleteFieldMappingError: If all candidates were rejected due to unmapped fields.
            SourceCapabilityMismatchError: If all candidates were rejected due to unsupported capabilities.
        """
        sorted_eligible, evaluations = self.select_all_eligible_sources(context, candidates)
        return sorted_eligible[0], evaluations

