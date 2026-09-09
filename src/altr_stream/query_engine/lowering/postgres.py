"""PostgreSQL physical query lowerer for AltrQL v0.4.

Translates schema-bound BoundAltrQueryIR into deterministic, fully parameterized
PostgreSQL SELECT, INSERT, UPDATE, and DELETE statements without performing database I/O or network calls.
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
    """Convert an AltrQL literal value into a Python native parameter for PostgreSQL drivers."""
    if isinstance(lit, TemporalLiteral):
        if lit.value is not None:
            try:
                if "T" in lit.value or " " in lit.value:
                    return datetime.datetime.fromisoformat(lit.value)
                return datetime.date.fromisoformat(lit.value)
            except ValueError:
                return lit.value
        return None
    if isinstance(lit, NullLiteral):
        return None
    if isinstance(lit, (IntegerLiteral, FloatLiteral, StringLiteral, BooleanLiteral)):
        return lit.value
    return getattr(lit, "value", None)


def _is_date_only_literal(lit: LiteralValue) -> bool:
    """Check if a literal is a date-only TemporalLiteral (YYYY-MM-DD) without time component."""
    if isinstance(lit, TemporalLiteral) and lit.keyword is None and lit.value is not None:
        return "T" not in lit.value and " " not in lit.value
    return False


def _parse_date_only_range(value: str) -> tuple[datetime.datetime, datetime.datetime]:
    """Parse YYYY-MM-DD string into start of day and start of next day datetimes."""
    d = datetime.date.fromisoformat(value)
    start_dt = datetime.datetime(d.year, d.month, d.day, 0, 0, 0)
    end_dt = start_dt + datetime.timedelta(days=1)
    return start_dt, end_dt


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


class PostgreSQLLowerer(QueryLowerer):
    """Deterministic physical query compiler for PostgreSQL dialect."""

    def lower(self, query: BoundAltrQueryIR) -> PhysicalQueryResult:
        """Translate a schema-bound AltrQL query into a parameterized PostgreSQL PhysicalQuery or PhysicalQueryBatch."""
        def quote_ident(name: str) -> str:
            return f'"{name}"'

        # Target table identifier (with namespace schema qualification if present)
        if query.entity.namespace:
            target_table = f"{quote_ident(query.entity.namespace)}.{quote_ident(query.entity.name)}"
        else:
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
                    return f"${len(group_params)}"

                def lower_group_literal(lit: LiteralValue) -> str:
                    if isinstance(lit, TemporalLiteral):
                        if lit.keyword == TemporalKeyword.TODAY:
                            return "CURRENT_DATE"
                        if lit.keyword == TemporalKeyword.NOW:
                            return "CURRENT_TIMESTAMP"
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
                        dialect="postgresql",
                        query=group_sql,
                        parameters=group_params,
                        source_id=query.source_id,
                        source_name=query.source_name,
                    )
                )

            if len(physical_queries) == 1:
                return physical_queries[0]
            return PhysicalQueryBatch(
                dialect="postgresql",
                queries=physical_queries,
                source_id=query.source_id,
                source_name=query.source_name,
            )

        params: List[Any] = []

        def add_param(val: Any) -> str:
            params.append(val)
            return f"${len(params)}"

        # Literal lowering helper
        def lower_literal(lit: LiteralValue) -> str:
            if isinstance(lit, TemporalLiteral):
                if lit.keyword == TemporalKeyword.TODAY:
                    return "CURRENT_DATE"
                if lit.keyword == TemporalKeyword.NOW:
                    return "CURRENT_TIMESTAMP"
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

                # CompoundAndConstraint operand: (col >= $1 AND col <= $2)
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

                    has_date_only_temporals = any(_is_date_only_literal(elem) for elem in non_null_elems)
                    all_simple_non_null = all(
                        isinstance(elem, (IntegerLiteral, FloatLiteral, StringLiteral, BooleanLiteral))
                        or (isinstance(elem, TemporalLiteral) and elem.keyword is None and elem.value is not None)
                        for elem in non_null_elems
                    )

                    # -------------------------------------------------------
                    # ValueSet with Equality (=)
                    # -------------------------------------------------------
                    if op == ComparisonOperator.EQ:
                        if all_simple_non_null and not (is_timestamp_field and has_date_only_temporals):
                            if has_null and len(non_null_elems) == 0:
                                return f"{col} IS NULL"
                            if has_null and len(non_null_elems) == 1:
                                p = lower_literal(non_null_elems[0])
                                return f"({col} = {p} OR {col} IS NULL)"
                            if has_null and len(non_null_elems) > 1:
                                placeholders = [lower_literal(elem) for elem in non_null_elems]
                                return f"({col} IN ({', '.join(placeholders)}) OR {col} IS NULL)"
                            if not has_null and len(non_null_elems) > 0:
                                placeholders = [lower_literal(elem) for elem in non_null_elems]
                                return f"{col} IN ({', '.join(placeholders)})"

                        # Complex / mixed ValueSet with EQ
                        elem_preds: List[str] = []
                        for elem in operand.elements:
                            if isinstance(elem, NullLiteral):
                                elem_preds.append(f"{col} IS NULL")
                            elif isinstance(elem, Range):
                                elem_preds.append(f"{col} BETWEEN {lower_literal(elem.start)} AND {lower_literal(elem.end)}")
                            elif isinstance(elem, ComparisonConstraint):
                                if isinstance(elem.value, NullLiteral):
                                    if elem.operator == ComparisonOperator.EQ:
                                        elem_preds.append(f"{col} IS NULL")
                                    elif elem.operator == ComparisonOperator.NEQ:
                                        elem_preds.append(f"{col} IS NOT NULL")
                                    else:
                                        elem_preds.append(f"{col} {elem.operator.value} NULL")
                                elif (
                                    elem.operator == ComparisonOperator.EQ
                                    and is_timestamp_field
                                    and _is_date_only_literal(elem.value)
                                ):
                                    start_dt, end_dt = _parse_date_only_range(elem.value.value)  # type: ignore[arg-type]
                                    p1 = add_param(start_dt)
                                    p2 = add_param(end_dt)
                                    elem_preds.append(f"({col} >= {p1} AND {col} < {p2})")
                                else:
                                    elem_preds.append(f"{col} {elem.operator.value} {lower_literal(elem.value)}")
                            elif isinstance(elem, CompoundAndConstraint):
                                c_preds = [f"{col} {c.operator.value} {lower_literal(c.value)}" for c in elem.constraints]
                                elem_preds.append(f"({' AND '.join(c_preds)})")
                            elif isinstance(elem, TemporalLiteral):
                                if elem.keyword == TemporalKeyword.TODAY:
                                    elem_preds.append(f"{col} = CURRENT_DATE")
                                elif elem.keyword == TemporalKeyword.NOW:
                                    elem_preds.append(f"{col} = CURRENT_TIMESTAMP")
                                elif is_timestamp_field and _is_date_only_literal(elem):
                                    start_dt, end_dt = _parse_date_only_range(elem.value)  # type: ignore[arg-type]
                                    p1 = add_param(start_dt)
                                    p2 = add_param(end_dt)
                                    elem_preds.append(f"({col} >= {p1} AND {col} < {p2})")
                                else:
                                    elem_preds.append(f"{col} = {lower_literal(elem)}")
                            elif isinstance(elem, (IntegerLiteral, FloatLiteral, StringLiteral, BooleanLiteral)):
                                elem_preds.append(f"{col} = {lower_literal(elem)}")

                        if not elem_preds:
                            return "1=1"
                        if len(elem_preds) == 1:
                            return elem_preds[0]
                        return f"({' OR '.join(elem_preds)})"

                    # -------------------------------------------------------
                    # ValueSet with Inequality (!=)
                    # -------------------------------------------------------
                    if op == ComparisonOperator.NEQ:
                        if all_simple_non_null and not (is_timestamp_field and has_date_only_temporals):
                            if has_null and len(non_null_elems) == 0:
                                return f"{col} IS NOT NULL"
                            if has_null and len(non_null_elems) == 1:
                                p = lower_literal(non_null_elems[0])
                                return f"({col} != {p} AND {col} IS NOT NULL)"
                            if has_null and len(non_null_elems) > 1:
                                placeholders = [lower_literal(elem) for elem in non_null_elems]
                                return f"({col} NOT IN ({', '.join(placeholders)}) AND {col} IS NOT NULL)"
                            if not has_null and len(non_null_elems) > 0:
                                placeholders = [lower_literal(elem) for elem in non_null_elems]
                                return f"({col} NOT IN ({', '.join(placeholders)}) OR {col} IS NULL)"

                        # Complex / mixed ValueSet with NEQ
                        elem_preds = []
                        for elem in operand.elements:
                            if isinstance(elem, NullLiteral):
                                elem_preds.append(f"{col} IS NOT NULL")
                            elif isinstance(elem, Range):
                                elem_preds.append(f"({col} < {lower_literal(elem.start)} OR {col} > {lower_literal(elem.end)} OR {col} IS NULL)")
                            elif isinstance(elem, ComparisonConstraint):
                                if isinstance(elem.value, NullLiteral):
                                    if elem.operator == ComparisonOperator.EQ:
                                        elem_preds.append(f"{col} IS NOT NULL")
                                    elif elem.operator == ComparisonOperator.NEQ:
                                        elem_preds.append(f"{col} IS NULL")
                                else:
                                    neg_op = _invert_operator(elem.operator)
                                    elem_preds.append(f"({col} {neg_op.value} {lower_literal(elem.value)} OR {col} IS NULL)")
                            elif isinstance(elem, (IntegerLiteral, FloatLiteral, StringLiteral, BooleanLiteral, TemporalLiteral)):
                                elem_preds.append(f"({col} != {lower_literal(elem)} OR {col} IS NULL)")

                        if not elem_preds:
                            return "1=1"
                        if len(elem_preds) == 1:
                            return elem_preds[0]
                        return f"({' AND '.join(elem_preds)})"

                # Direct LiteralValue operand
                if isinstance(operand, TemporalLiteral):
                    if operand.keyword == TemporalKeyword.TODAY:
                        return f"{col} {op.value} CURRENT_DATE"
                    if operand.keyword == TemporalKeyword.NOW:
                        return f"{col} {op.value} CURRENT_TIMESTAMP"
                    if (
                        op == ComparisonOperator.EQ
                        and is_timestamp_field
                        and _is_date_only_literal(operand)
                    ):
                        start_dt, end_dt = _parse_date_only_range(operand.value)  # type: ignore[arg-type]
                        p1 = add_param(start_dt)
                        p2 = add_param(end_dt)
                        return f"({col} >= {p1} AND {col} < {p2})"
                    return f"{col} {op.value} {lower_literal(operand)}"

                if isinstance(operand, LiteralValue):  # type: ignore[misc]
                    return f"{col} {op.value} {lower_literal(operand)}"

            # Fallback
            return f"{col} = {lower_literal(operand)}"  # type: ignore[arg-type]

        def lower_expression(expr: BoundExpression) -> str:
            if isinstance(expr, BoundFieldExpression):
                return lower_field_expression(expr)
            if isinstance(expr, BoundLogicalExpression):
                left_sql = lower_expression(expr.left)
                right_sql = lower_expression(expr.right)
                op_str = expr.operator.value if hasattr(expr.operator, "value") else str(expr.operator)
                return f"({left_sql} {op_str} {right_sql})"
            if isinstance(expr, BoundNegationExpression):
                operand_sql = lower_expression(expr.operand)
                if operand_sql.startswith("(") and operand_sql.endswith(")"):
                    return f"NOT {operand_sql}"
                return f"NOT ({operand_sql})"
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
            dialect="postgresql",
            query=final_sql,
            parameters=params,
            source_id=query.source_id,
            source_name=query.source_name,
        )

