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
    projected_aliases: set[str] | list[str] | None = None,
) -> dict[str, Any]:
    """Normalize a single physical database row into canonical logical field names.

    Omits internal connector-specific primary keys (like MongoDB's '_id')
    unless explicitly mapped in the logical schema.
    If preserve_unmapped is False, physical-only fields not present in the
    active mapping are excluded in logical mode.

    If a field name in row is already a recognized canonical logical field name
    (e.g. when physical query lowering produced logical aliases like 'roll_no AS roll_number')
    or an explicit projection alias (e.g. 'roll_no AS student_id'),
    it is preserved directly rather than discarded as unmapped.
    """
    normalized: dict[str, Any] = {}
    phys_lookup = {k.lower(): v for k, v in physical_to_logical.items()}
    log_lookup = {v.lower(): v for v in physical_to_logical.values()}
    logical_fields_set = set(physical_to_logical.values())
    alias_lookup: dict[str, str] = {}
    if projected_aliases:
        alias_lookup = {a.lower(): a for a in projected_aliases}

    for col, val in row.items():
        if col == "_id" and "_id" not in physical_to_logical and "_id" not in phys_lookup and "_id" not in log_lookup and "_id" not in alias_lookup:
            continue
        if alias_lookup and col in projected_aliases:
            normalized[col] = val
        elif alias_lookup and col.lower() in alias_lookup:
            orig_alias = alias_lookup[col.lower()]
            normalized[orig_alias] = val
        elif col in physical_to_logical:
            logical_field = physical_to_logical[col]
            normalized[logical_field] = val
        elif col.lower() in phys_lookup:
            logical_field = phys_lookup[col.lower()]
            normalized[logical_field] = val
        elif col in logical_fields_set:
            normalized[col] = val
        elif col.lower() in log_lookup:
            logical_field = log_lookup[col.lower()]
            normalized[logical_field] = val
        elif preserve_unmapped:
            normalized[col] = val
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

    # Build bidirectional alias-to-canonical lookup for projection aliases
    alias_map: dict[str, str] = {}
    if ir.projection:
        for sel in ir.projection:
            if sel.alias:
                alias_map[sel.alias] = sel.path.leaf
                alias_map[sel.alias.lower()] = sel.path.leaf
                alias_map[sel.path.leaf] = sel.alias
                alias_map[sel.path.leaf.lower()] = sel.alias

    def comparator(row_a: dict[str, Any], row_b: dict[str, Any]) -> int:
        for field_name, is_desc in sort_specs:
            val_a = row_a.get(field_name)
            if val_a is None and field_name in alias_map:
                val_a = row_a.get(alias_map[field_name])
            if val_a is None and field_name.lower() in alias_map:
                val_a = row_a.get(alias_map[field_name.lower()])

            val_b = row_b.get(field_name)
            if val_b is None and field_name in alias_map:
                val_b = row_b.get(alias_map[field_name])
            if val_b is None and field_name.lower() in alias_map:
                val_b = row_b.get(alias_map[field_name.lower()])

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
    projected_aliases: set[str] | None = None
    if not ir.is_wildcard_projection and ir.projection:
        projected_aliases = {sel.alias for sel in ir.projection if sel.alias}

    for plan, result in execution_results:
        for row in result.rows:
            norm_row = normalize_row(
                row,
                plan.physical_to_logical_map,
                projected_aliases=projected_aliases,
            )
            all_normalized_rows.append(norm_row)

    # 1. Determine canonical logical columns and format rows
    columns: list[str] = []
    if not ir.is_wildcard_projection:
        for sel in ir.projection:
            col_name = sel.alias or sel.path.leaf
            columns.append(col_name)
        ordered_rows: list[dict[str, Any]] = []
        for nr in all_normalized_rows:
            ordered_r: dict[str, Any] = {}
            for sel in ir.projection:
                out_col = sel.alias or sel.path.leaf
                src_key = sel.path.leaf
                if out_col in nr:
                    ordered_r[out_col] = nr[out_col]
                elif src_key in nr:
                    ordered_r[out_col] = nr[src_key]
                elif out_col.lower() in nr:
                    ordered_r[out_col] = nr[out_col.lower()]
                elif src_key.lower() in nr:
                    ordered_r[out_col] = nr[src_key.lower()]
            ordered_rows.append(ordered_r)
        all_normalized_rows = ordered_rows
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
