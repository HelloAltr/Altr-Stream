"""Federated result normalization, global sorting, pagination, and deterministic merging."""

from __future__ import annotations

import functools
from typing import Any

from altr_stream.domain.query import QueryResult
from altr_stream.query_engine.domain.ast import (
    AltrQueryIR,
    RankingDirection,
    SortDirection,
)
from altr_stream.query_engine.planning.models import (
    FederatedQueryPlan,
    PhysicalQueryPlan,
)


def normalize_row(
    row: dict[str, Any],
    physical_to_logical: dict[str, str],
    preserve_unmapped: bool = False,
) -> dict[str, Any]:
    """Normalize a single physical database row into canonical logical field names.

    Omits internal connector-specific primary keys (like MongoDB's '_id')
    unless explicitly mapped in the logical schema.
    If preserve_unmapped is False, physical-only fields not present in the
    active mapping are excluded in logical mode.
    """
    normalized: dict[str, Any] = {}
    phys_lookup = {k.lower(): v for k, v in physical_to_logical.items()}

    for physical_col, val in row.items():
        if physical_col == "_id" and "_id" not in physical_to_logical and "_id" not in phys_lookup:
            continue
        if physical_col in physical_to_logical:
            logical_field = physical_to_logical[physical_col]
            normalized[logical_field] = val
        elif physical_col.lower() in phys_lookup:
            logical_field = phys_lookup[physical_col.lower()]
            normalized[logical_field] = val
        elif preserve_unmapped:
            normalized[physical_col] = val
    return normalized


def _compare_values(a: Any, b: Any) -> int:
    """Compare two arbitrary values for global sorting with safe NULL handling."""
    if a is None and b is None:
        return 0
    if a is None:
        return -1
    if b is None:
        return 1

    # Numeric coercion if types differ (e.g. Decimal / float / int)
    try:
        if isinstance(a, (int, float)) and isinstance(b, (int, float)):
            if a < b:
                return -1
            elif a > b:
                return 1
            return 0
    except Exception:
        pass

    try:
        if a < b:
            return -1
        elif a > b:
            return 1
        return 0
    except TypeError:
        # Fallback to string comparison on incompatible types
        sa, sb = str(a), str(b)
        if sa < sb:
            return -1
        elif sa > sb:
            return 1
        return 0


def _build_row_comparator(ir: AltrQueryIR):
    """Construct a composite comparator function for global sorting based on IR clauses."""
    sort_specs: list[tuple[str, bool]] = []

    if ir.sort:
        for s in ir.sort:
            field_name = s.field.leaf
            is_desc = s.direction == SortDirection.DESC
            sort_specs.append((field_name, is_desc))
    elif ir.ranking:
        field_name = ir.ranking.field.leaf
        is_desc = ir.ranking.direction == RankingDirection.TOP
        sort_specs.append((field_name, is_desc))

    if not sort_specs:
        return None

    def comparator(row_a: dict[str, Any], row_b: dict[str, Any]) -> int:
        for field_name, is_desc in sort_specs:
            val_a = row_a.get(field_name)
            val_b = row_b.get(field_name)
            res = _compare_values(val_a, val_b)
            if res != 0:
                return -res if is_desc else res
        return 0

    return functools.cmp_to_key(comparator)


def merge_federated_results(
    ir: AltrQueryIR,
    federated_plan: FederatedQueryPlan,
    execution_results: list[tuple[PhysicalQueryPlan, QueryResult]],
) -> tuple[list[str], list[dict[str, Any]]]:
    """Normalize and merge physical query results across all federated datasources.

    Guarantees:
    1. Per-source physical-to-logical field normalization.
    2. Deterministic source ordering (plans ordered by source_id ASC, mapping_id ASC).
    3. Global sorting across all rows from all sources according to logical sort/ranking clauses.
    4. Global LIMIT and OFFSET pagination applied at the unified result level.
    """
    all_normalized_rows: list[dict[str, Any]] = []

    for plan, result in execution_results:
        for row in result.rows:
            norm_row = normalize_row(row, plan.physical_to_logical_map)
            all_normalized_rows.append(norm_row)

    # 1. Determine canonical logical columns
    columns: list[str] = []
    if not ir.is_wildcard_projection:
        for sel in ir.projection:
            col_name = sel.alias or sel.path.leaf
            columns.append(col_name)
    else:
        seen_cols: set[str] = set()
        # Order columns using the logical fields defined in candidate mappings
        if federated_plan.physical_plans:
            for log_field in federated_plan.physical_plans[0].logical_to_physical_map.keys():
                if log_field not in seen_cols:
                    seen_cols.add(log_field)
                    columns.append(log_field)
        for r in all_normalized_rows:
            for k in r.keys():
                if k not in seen_cols:
                    seen_cols.add(k)
                    columns.append(k)

        # Fallback if no rows returned
        if not columns and federated_plan.physical_plans:
            first_plan = federated_plan.physical_plans[0]
            columns = list(first_plan.logical_to_physical_map.keys())

    # 2. Global Sorting
    sort_key_fn = _build_row_comparator(ir)
    if sort_key_fn is not None:
        all_normalized_rows.sort(key=sort_key_fn)

    # 3. Global Pagination (OFFSET and LIMIT / TOP)
    final_rows = all_normalized_rows

    if ir.offset is not None and ir.offset > 0:
        final_rows = final_rows[ir.offset:]

    if ir.limit is not None and ir.limit >= 0:
        final_rows = final_rows[: ir.limit]
    elif ir.ranking is not None and ir.ranking.count >= 0:
        final_rows = final_rows[: ir.ranking.count]

    return columns, final_rows
