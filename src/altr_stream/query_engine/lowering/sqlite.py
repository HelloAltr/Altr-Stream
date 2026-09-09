"""SQLite physical query lowerer for AltrQL.

Translates schema-bound BoundAltrQueryIR into deterministic, fully parameterized
SQLite SELECT, INSERT, UPDATE, and DELETE statements with '?' parameter markers.
"""

from __future__ import annotations

import datetime
from typing import Any, List

from altr_stream.domain.schema import StandardDataType
from altr_stream.query_engine.domain.ast import (
    BooleanLiteral,
    ComparisonConstraint,
    CompoundAndConstraint,
    FloatLiteral,
    IntegerLiteral,
    LiteralValue,
    NullLiteral,
    QueryOperation,
    Range,
    StringLiteral,
    TemporalLiteral,
    ValueSet,
)
from altr_stream.query_engine.domain.bound_ast import (
    BoundAltrQueryIR,
    BoundCreateRecord,
    BoundExpression,
    BoundFieldExpression,
    BoundLogicalExpression,
    BoundNegationExpression,
)
from altr_stream.query_engine.domain.operators import (
    ComparisonOperator,
    RankingDirection,
    StringOperator,
    TemporalKeyword,
)
from altr_stream.query_engine.domain.physical_query import (
    PhysicalQuery,
    PhysicalQueryBatch,
    PhysicalQueryResult,
)
from altr_stream.query_engine.lowering.base import QueryLowerer


def _convert_literal_to_parameter(lit: LiteralValue) -> Any:
    """Convert an AltrQL literal value into a Python native parameter for SQLite drivers."""
    if isinstance(lit, TemporalLiteral):
        if lit.value is not None:
            return lit.value
        return None
    if isinstance(lit, NullLiteral):
        return None
    if isinstance(lit, BooleanLiteral):
        return 1 if lit.value else 0
    if isinstance(lit, (IntegerLiteral, FloatLiteral, StringLiteral)):
        return lit.value
    return getattr(lit, "value", None)


def _is_date_only_literal(lit: LiteralValue) -> bool:
    """Check if a literal is a date-only TemporalLiteral (YYYY-MM-DD) without time component."""
    if isinstance(lit, TemporalLiteral) and lit.keyword is None and lit.value is not None:
        return "T" not in lit.value and " " not in lit.value
    return False


def _parse_date_only_range(value: str) -> tuple[str, str]:
    """Parse YYYY-MM-DD string into start of day and start of next day ISO strings."""
    d = datetime.date.fromisoformat(value)
    start_dt = datetime.datetime(d.year, d.month, d.day, 0, 0, 0)
    end_dt = start_dt + datetime.timedelta(days=1)
    return start_dt.isoformat(), end_dt.isoformat()


def _invert_operator(op: ComparisonOperator) -> ComparisonOperator:
    """Return the boolean negation of a comparison operator."""
    inversion_map = {
        ComparisonOperator.EQ: ComparisonOperator.NEQ,
        ComparisonOperator.NEQ: ComparisonOperator.EQ,
        ComparisonOperator.GT: ComparisonOperator.LTE,
        ComparisonOperator.LT: ComparisonOperator.GTE,
        ComparisonOperator.GTE: ComparisonOperator.LT,
        ComparisonOperator.LTE: ComparisonOperator.GT,
    }
    return inversion_map[op]


class SQLiteLowerer(QueryLowerer):
    """Deterministic physical query compiler for SQLite dialect."""

    def lower(self, query: BoundAltrQueryIR) -> PhysicalQueryResult:
        """Translate a schema-bound AltrQL query into a parameterized SQLite PhysicalQuery or PhysicalQueryBatch."""
        def quote_ident(name: str) -> str:
            escaped = name.replace('"', '""')
            return f'"{escaped}"'

        target_table = quote_ident(query.entity.name)

        # -------------------------------------------------------------------
        # CREATE Operation Handling (Single & Batch with Consecutive Grouping)
        # -------------------------------------------------------------------
        if query.operation == QueryOperation.CREATE:
            records = (
                query.records
                if query.records
                else ([BoundCreateRecord(assignments=query.assignments)] if query.assignments else [])
            )

            # Chunk consecutive records with identical ordered column tuples:
            groups: List[List[BoundCreateRecord]] = []
            for rec in records:
                cols = tuple(a.field.path.leaf for a in rec.assignments)
                if not groups:
                    groups.append([rec])
                    continue

                previous_cols = tuple(
                    a.field.path.leaf for a in groups[-1][0].assignments
                )
                if previous_cols == cols:
                    groups[-1].append(rec)
                else:
                    groups.append([rec])

            physical_queries: List[PhysicalQuery] = []
            for group in groups:
                group_params: List[Any] = []

                def add_group_param(val: Any) -> str:
                    group_params.append(val)
                    return "?"

                def lower_group_literal(lit: LiteralValue) -> str:
                    if isinstance(lit, TemporalLiteral):
                        if lit.keyword == TemporalKeyword.TODAY:
                            return "DATE('now')"
                        if lit.keyword == TemporalKeyword.NOW:
                            return "DATETIME('now')"
                        if lit.value is not None:
                            return add_group_param(_convert_literal_to_parameter(lit))
                        return "NULL"
                    if isinstance(lit, NullLiteral):
                        return "NULL"
                    if isinstance(lit, (IntegerLiteral, FloatLiteral, StringLiteral, BooleanLiteral)):
                        return add_group_param(_convert_literal_to_parameter(lit))
                    return add_group_param(_convert_literal_to_parameter(lit))

                cols = [quote_ident(a.field.path.leaf) for a in group[0].assignments]
                row_value_tuples: List[str] = []
                for rec in group:
                    row_vals = [lower_group_literal(a.value) for a in rec.assignments]
                    row_value_tuples.append(f"({', '.join(row_vals)})")

                group_sql = f"INSERT INTO {target_table} ({', '.join(cols)}) VALUES {', '.join(row_value_tuples)} RETURNING *;"
                physical_queries.append(
                    PhysicalQuery(
                        dialect="sqlite",
                        query=group_sql,
                        parameters=group_params,
                        source_id=query.source_id,
                        source_name=query.source_name,
                    )
                )

            if len(physical_queries) == 1:
                return physical_queries[0]
            return PhysicalQueryBatch(
                dialect="sqlite",
                queries=physical_queries,
                source_id=query.source_id,
                source_name=query.source_name,
            )

        params: List[Any] = []

        def add_param(val: Any) -> str:
            params.append(val)
            return "?"

        # Literal lowering helper
        def lower_literal(lit: LiteralValue) -> str:
            if isinstance(lit, TemporalLiteral):
                if lit.keyword == TemporalKeyword.TODAY:
                    return "DATE('now')"
                if lit.keyword == TemporalKeyword.NOW:
                    return "DATETIME('now')"
                if lit.value is not None:
                    return add_param(_convert_literal_to_parameter(lit))
                return "NULL"
            if isinstance(lit, NullLiteral):
                return "NULL"
            if isinstance(lit, (IntegerLiteral, FloatLiteral, StringLiteral, BooleanLiteral)):
                return add_param(_convert_literal_to_parameter(lit))
            return add_param(_convert_literal_to_parameter(lit))

        def lower_field_expression(expr: BoundFieldExpression) -> str:
            col = quote_ident(expr.field.path.leaf)
            op = expr.operator
            operand = expr.operand
            is_timestamp_field = expr.field.data_type in (StandardDataType.TIMESTAMP, StandardDataType.TIMESTAMPTZ)

            # String operators: STARTS, ENDS, HAS, NOT HAS
            if isinstance(op, StringOperator):
                val_str = str(getattr(operand, "value", ""))
                if op == StringOperator.STARTS:
                    return f"{col} LIKE {add_param(f'{val_str}%')}"
                if op == StringOperator.ENDS:
                    return f"{col} LIKE {add_param(f'%{val_str}')}"
                if op == StringOperator.HAS:
                    return f"{col} LIKE {add_param(f'%{val_str}%')}"
                if op == StringOperator.NOT_HAS:
                    return f"({col} NOT LIKE {add_param(f'%{val_str}%')} OR {col} IS NULL)"

            # Comparison operators (=, !=, >, <, >=, <=)
            if isinstance(op, ComparisonOperator):
                # NullLiteral direct operand
                if isinstance(operand, NullLiteral):
                    if op == ComparisonOperator.EQ:
                        return f"{col} IS NULL"
                    if op == ComparisonOperator.NEQ:
                        return f"{col} IS NOT NULL"
                    return f"{col} {op.value} NULL"

                # Range operand: BETWEEN start AND end
                if isinstance(operand, Range):
                    start_str = lower_literal(operand.start)
                    end_str = lower_literal(operand.end)
                    return f"{col} BETWEEN {start_str} AND {end_str}"

                # CompoundAndConstraint operand: (col >= ? AND col <= ?)
                if isinstance(operand, CompoundAndConstraint):
                    c_preds = [f"{col} {c.operator.value} {lower_literal(c.value)}" for c in operand.constraints]
                    return f"({' AND '.join(c_preds)})"

                # ComparisonConstraint operand
                if isinstance(operand, ComparisonConstraint):
                    if isinstance(operand.value, NullLiteral):
                        if operand.operator == ComparisonOperator.EQ:
                            return f"{col} IS NULL"
                        if operand.operator == ComparisonOperator.NEQ:
                            return f"{col} IS NOT NULL"
                        return f"{col} {operand.operator.value} NULL"

                    if (
                        operand.operator == ComparisonOperator.EQ
                        and is_timestamp_field
                        and _is_date_only_literal(operand.value)
                    ):
                        start_dt, end_dt = _parse_date_only_range(operand.value.value)  # type: ignore[arg-type]
                        p1 = add_param(start_dt)
                        p2 = add_param(end_dt)
                        return f"({col} >= {p1} AND {col} < {p2})"
                    return f"{col} {operand.operator.value} {lower_literal(operand.value)}"

                # ValueSet operand
                if isinstance(operand, ValueSet):
                    null_elems = [el for el in operand.elements if isinstance(el, NullLiteral)]
                    non_null_elems = [el for el in operand.elements if not isinstance(el, NullLiteral)]
                    has_null = len(null_elems) > 0

                    if op == ComparisonOperator.EQ:
                        predicates = []
                        if has_null:
                            predicates.append(f"{col} IS NULL")

                        # Group scalar values for IN clause if possible
                        simple_scalars = [
                            el for el in non_null_elems
                            if isinstance(el, (IntegerLiteral, FloatLiteral, StringLiteral, BooleanLiteral))
                            or (isinstance(el, TemporalLiteral) and not (is_timestamp_field and _is_date_only_literal(el)))
                        ]
                        other_elems = [el for el in non_null_elems if el not in simple_scalars]

                        if simple_scalars:
                            in_params = [add_param(_convert_literal_to_parameter(el)) for el in simple_scalars]
                            predicates.append(f"{col} IN ({', '.join(in_params)})")

                        for el in other_elems:
                            if isinstance(el, Range):
                                s_str = lower_literal(el.start)
                                e_str = lower_literal(el.end)
                                predicates.append(f"{col} BETWEEN {s_str} AND {e_str}")
                            elif isinstance(el, ComparisonConstraint):
                                predicates.append(f"{col} {el.operator.value} {lower_literal(el.value)}")
                            elif isinstance(el, CompoundAndConstraint):
                                c_preds = [f"{col} {c.operator.value} {lower_literal(c.value)}" for c in el.constraints]
                                predicates.append(f"({' AND '.join(c_preds)})")
                            elif isinstance(el, TemporalLiteral) and is_timestamp_field and _is_date_only_literal(el):
                                s_dt, e_dt = _parse_date_only_range(el.value)  # type: ignore[arg-type]
                                p1 = add_param(s_dt)
                                p2 = add_param(e_dt)
                                predicates.append(f"({col} >= {p1} AND {col} < {p2})")

                        if len(predicates) == 1:
                            return predicates[0]
                        return f"({' OR '.join(predicates)})"

                    elif op == ComparisonOperator.NEQ:
                        predicates = []
                        if has_null:
                            predicates.append(f"{col} IS NOT NULL")

                        simple_scalars = [
                            el for el in non_null_elems
                            if isinstance(el, (IntegerLiteral, FloatLiteral, StringLiteral, BooleanLiteral))
                            or (isinstance(el, TemporalLiteral) and not (is_timestamp_field and _is_date_only_literal(el)))
                        ]
                        other_elems = [el for el in non_null_elems if el not in simple_scalars]

                        if simple_scalars:
                            in_params = [add_param(_convert_literal_to_parameter(el)) for el in simple_scalars]
                            predicates.append(f"{col} NOT IN ({', '.join(in_params)})")

                        for el in other_elems:
                            if isinstance(el, Range):
                                s_str = lower_literal(el.start)
                                e_str = lower_literal(el.end)
                                predicates.append(f"{col} NOT BETWEEN {s_str} AND {e_str}")
                            elif isinstance(el, ComparisonConstraint):
                                inv_op = _invert_operator(el.operator)
                                predicates.append(f"{col} {inv_op.value} {lower_literal(el.value)}")
                            elif isinstance(el, CompoundAndConstraint):
                                inv_preds = [f"{col} {_invert_operator(c.operator).value} {lower_literal(c.value)}" for c in el.constraints]
                                predicates.append(f"({' OR '.join(inv_preds)})")
                            elif isinstance(el, TemporalLiteral) and is_timestamp_field and _is_date_only_literal(el):
                                s_dt, e_dt = _parse_date_only_range(el.value)  # type: ignore[arg-type]
                                p1 = add_param(s_dt)
                                p2 = add_param(e_dt)
                                predicates.append(f"({col} < {p1} OR {col} >= {p2})")

                        if not has_null:
                            predicates.append(f"{col} IS NOT NULL")

                        if len(predicates) == 1:
                            return predicates[0]
                        return f"({' AND '.join(predicates)})"

                # Direct scalar operand comparison
                if op == ComparisonOperator.EQ and is_timestamp_field and _is_date_only_literal(operand):
                    start_dt, end_dt = _parse_date_only_range(operand.value)  # type: ignore[arg-type]
                    p1 = add_param(start_dt)
                    p2 = add_param(end_dt)
                    return f"({col} >= {p1} AND {col} < {p2})"

                param_placeholder = lower_literal(operand)
                return f"{col} {op.value} {param_placeholder}"

            raise NotImplementedError(f"Unsupported operator '{op}' in SQLiteLowerer")

        def lower_expression(expr: BoundExpression) -> str:
            if isinstance(expr, BoundFieldExpression):
                return lower_field_expression(expr)

            if isinstance(expr, BoundNegationExpression):
                inner_sql = lower_expression(expr.operand)
                if inner_sql.startswith("(") and inner_sql.endswith(")"):
                    return f"NOT {inner_sql}"
                return f"NOT ({inner_sql})"

            if isinstance(expr, BoundLogicalExpression):
                left_sql = lower_expression(expr.left)
                right_sql = lower_expression(expr.right)
                op_str = expr.operator.value if hasattr(expr.operator, "value") else str(expr.operator)
                return f"({left_sql} {op_str} {right_sql})"

            return "1=1"

        # -------------------------------------------------------------------
        # Operation Dispatch (UPDATE, DELETE, READ)
        # -------------------------------------------------------------------

        if query.operation == QueryOperation.UPDATE:
            set_items = [f"{quote_ident(a.field.path.leaf)} = {lower_literal(a.value)}" for a in query.assignments]
            where_sql = f" WHERE {lower_expression(query.where)}" if query.where is not None else ""
            final_sql = f"UPDATE {target_table} SET {', '.join(set_items)}{where_sql} RETURNING *;"

        elif query.operation == QueryOperation.DELETE:
            where_sql = f" WHERE {lower_expression(query.where)}" if query.where is not None else ""
            final_sql = f"DELETE FROM {target_table}{where_sql} RETURNING *;"

        else:
            # READ (SELECT query)
            if query.is_wildcard_projection:
                select_clause = "SELECT *"
            else:
                select_items: List[str] = []
                for sel in query.projection:
                    col_name = quote_ident(sel.field.path.leaf)
                    if sel.alias:
                        select_items.append(f"{col_name} AS {quote_ident(sel.alias)}")
                    else:
                        select_items.append(col_name)
                select_clause = f"SELECT {', '.join(select_items)}"

            from_clause = f"FROM {target_table}"
            where_clause = f"WHERE {lower_expression(query.where)}" if query.where is not None else None

            order_by_items: List[str] = []
            if query.ranking:
                rank_col = quote_ident(query.ranking.field.path.leaf)
                rank_dir = "DESC" if query.ranking.direction == RankingDirection.TOP else "ASC"
                order_by_items.append(f"{rank_col} {rank_dir}")

            if query.sort:
                for s in query.sort:
                    sort_col = quote_ident(s.field.path.leaf)
                    order_by_items.append(f"{sort_col} {s.direction.value}")

            order_by_clause = f"ORDER BY {', '.join(order_by_items)}" if order_by_items else None
            limit_clause = f"LIMIT {query.ranking.count}" if query.ranking else None
            offset_clause = f"OFFSET {query.offset}" if query.offset is not None else None

            query_parts = [select_clause, from_clause]
            if where_clause:
                query_parts.append(where_clause)
            if order_by_clause:
                query_parts.append(order_by_clause)
            if limit_clause:
                query_parts.append(limit_clause)
            if offset_clause:
                query_parts.append(offset_clause)

            final_sql = " ".join(query_parts) + ";"

        return PhysicalQuery(
            dialect="sqlite",
            query=final_sql,
            parameters=params,
            source_id=query.source_id,
            source_name=query.source_name,
        )
