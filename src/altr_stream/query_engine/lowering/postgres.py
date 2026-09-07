"""PostgreSQL physical query lowerer for AltrQL v0.1.

Translates schema-bound BoundAltrQueryIR into deterministic, fully parameterized
PostgreSQL SELECT statements without performing database I/O or network calls.
"""

from __future__ import annotations

from typing import Any, List

from altr_stream.query_engine.domain.ast import (
    BooleanLiteral,
    ComparisonConstraint,
    CompoundAndConstraint,
    FloatLiteral,
    IntegerLiteral,
    LiteralValue,
    NullLiteral,
    Range,
    StringLiteral,
    TemporalLiteral,
    ValueSet,
)
from altr_stream.query_engine.domain.bound_ast import (
    BoundAltrQueryIR,
    BoundExpression,
    BoundFieldExpression,
    BoundLogicalExpression,
)
from altr_stream.query_engine.domain.operators import (
    ComparisonOperator,
    RankingDirection,
    StringOperator,
    TemporalKeyword,
)
from altr_stream.query_engine.domain.physical_query import PhysicalQuery
from altr_stream.query_engine.lowering.base import QueryLowerer


class PostgreSQLLowerer(QueryLowerer):
    """Deterministic physical query compiler for PostgreSQL dialect."""

    def lower(self, query: BoundAltrQueryIR) -> PhysicalQuery:
        """Translate a schema-bound AltrQL query into a parameterized PostgreSQL PhysicalQuery."""
        params: List[Any] = []

        def add_param(val: Any) -> str:
            params.append(val)
            return f"${len(params)}"

        def quote_ident(name: str) -> str:
            return f'"{name}"'

        # 1. Projections (SELECT clause)
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

        # 2. Entity (FROM clause with schema qualification if available)
        if query.entity.namespace:
            from_clause = f"FROM {quote_ident(query.entity.namespace)}.{quote_ident(query.entity.name)}"
        else:
            from_clause = f"FROM {quote_ident(query.entity.name)}"

        # 3. WHERE clause lowering helpers
        def lower_literal(lit: LiteralValue) -> str:
            if isinstance(lit, TemporalLiteral):
                if lit.keyword == TemporalKeyword.TODAY:
                    return "CURRENT_DATE"
                if lit.keyword == TemporalKeyword.NOW:
                    return "CURRENT_TIMESTAMP"
                if lit.value is not None:
                    return add_param(lit.value)
                return "NULL"
            if isinstance(lit, NullLiteral):
                return "NULL"
            if isinstance(lit, (IntegerLiteral, FloatLiteral, StringLiteral, BooleanLiteral)):
                return add_param(lit.value)
            return add_param(getattr(lit, "value", None))

        def lower_field_expression(expr: BoundFieldExpression) -> str:
            col = quote_ident(expr.field.path.leaf)
            op = expr.operator
            operand = expr.operand

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
                    return f"{col} NOT LIKE {add_param(f'%{val_str}%')}"

            # Comparison operators (=, !=, >, <, >=, <=)
            if isinstance(op, ComparisonOperator):
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
                    return f"{col} {operand.operator.value} {lower_literal(operand.value)}"

                # ValueSet operand
                if isinstance(operand, ValueSet):
                    # Check if all elements are simple literal values (not Range/Constraints/Temporal Keywords)
                    all_simple_literals = all(
                        isinstance(elem, (IntegerLiteral, FloatLiteral, StringLiteral, BooleanLiteral))
                        or (isinstance(elem, TemporalLiteral) and elem.keyword is None and elem.value is not None)
                        for elem in operand.elements
                    )
                    if all_simple_literals and len(operand.elements) > 0:
                        placeholders = [lower_literal(elem) for elem in operand.elements]  # type: ignore[arg-type]
                        return f"{col} IN ({', '.join(placeholders)})"

                    # Complex / mixed ValueSet: OR together element conditions
                    elem_preds: List[str] = []
                    for elem in operand.elements:
                        if isinstance(elem, Range):
                            elem_preds.append(f"{col} BETWEEN {lower_literal(elem.start)} AND {lower_literal(elem.end)}")
                        elif isinstance(elem, ComparisonConstraint):
                            elem_preds.append(f"{col} {elem.operator.value} {lower_literal(elem.value)}")
                        elif isinstance(elem, CompoundAndConstraint):
                            c_preds = [f"{col} {c.operator.value} {lower_literal(c.value)}" for c in elem.constraints]
                            elem_preds.append(f"({' AND '.join(c_preds)})")
                        elif isinstance(elem, TemporalLiteral):
                            if elem.keyword == TemporalKeyword.TODAY:
                                elem_preds.append(f"{col} = CURRENT_DATE")
                            elif elem.keyword == TemporalKeyword.NOW:
                                elem_preds.append(f"{col} = CURRENT_TIMESTAMP")
                            else:
                                elem_preds.append(f"{col} = {lower_literal(elem)}")
                        elif isinstance(elem, (IntegerLiteral, FloatLiteral, StringLiteral, BooleanLiteral)):
                            elem_preds.append(f"{col} = {lower_literal(elem)}")

                    if not elem_preds:
                        return "1=1"
                    if len(elem_preds) == 1:
                        return elem_preds[0]
                    return f"({' OR '.join(elem_preds)})"

                # Direct LiteralValue operand
                if isinstance(operand, TemporalLiteral):
                    if operand.keyword == TemporalKeyword.TODAY:
                        return f"{col} {op.value} CURRENT_DATE"
                    if operand.keyword == TemporalKeyword.NOW:
                        return f"{col} {op.value} CURRENT_TIMESTAMP"
                    return f"{col} {op.value} {lower_literal(operand)}"

                if isinstance(operand, LiteralValue):  # type: ignore[misc]
                    return f"{col} {op.value} {lower_literal(operand)}"

            # Fallback
            return f"{col} = {lower_literal(operand)}"  # type: ignore[arg-type]

        def lower_expression(expr: BoundExpression) -> str:
            if isinstance(expr, BoundFieldExpression):
                return lower_field_expression(expr)
            if isinstance(expr, BoundLogicalExpression):
                if not expr.operands:
                    return "1=1"
                if len(expr.operands) == 1:
                    return lower_expression(expr.operands[0])
                child_sqls = [lower_expression(op) for op in expr.operands]
                if expr.operator == "AND":
                    return f"{' AND '.join(child_sqls)}"
                return f"({f' {expr.operator} '.join(child_sqls)})"
            return "1=1"

        where_clause: str | None = None
        if query.where is not None:
            where_sql = lower_expression(query.where)
            where_clause = f"WHERE {where_sql}"

        # 4. ORDER BY (Ranking provides primary ordering, explicit SORT provides secondary ordering)
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

        # 5. LIMIT (from ranking)
        limit_clause = f"LIMIT {query.ranking.count}" if query.ranking else None

        # 6. OFFSET
        offset_clause = f"OFFSET {query.offset}" if query.offset is not None else None

        # Assemble query parts
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
