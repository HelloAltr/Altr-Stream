"""MongoDB physical query lowerer for AltrQL.

Translates schema-bound BoundAltrQueryIR into deterministic, fully structured
PyMongo/MongoDB command specifications with locked PhysicalQuery contract.
"""

from __future__ import annotations

import datetime
import re
from typing import Any, List, Optional, Union

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
    BoundFieldPath,
    BoundLogicalExpression,
    BoundNegationExpression,
)
from altr_stream.query_engine.domain.operators import (
    ComparisonOperator,
    RankingDirection,
    SortDirection,
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
    """Convert an AltrQL literal value into a Python/BSON native parameter."""
    if isinstance(lit, TemporalLiteral):
        if lit.keyword == TemporalKeyword.TODAY:
            return datetime.datetime.now(datetime.timezone.utc).replace(
                hour=0, minute=0, second=0, microsecond=0
            )
        if lit.keyword == TemporalKeyword.NOW:
            return datetime.datetime.now(datetime.timezone.utc)
        if lit.value is not None:
            try:
                if "T" in lit.value or " " in lit.value:
                    return datetime.datetime.fromisoformat(lit.value)
                return datetime.date.fromisoformat(lit.value)
            except (ValueError, TypeError):
                return lit.value
        return None
    if isinstance(lit, NullLiteral):
        return None
    if isinstance(lit, BooleanLiteral):
        return bool(lit.value)
    if isinstance(lit, IntegerLiteral):
        return int(lit.value)
    if isinstance(lit, FloatLiteral):
        return float(lit.value)
    if isinstance(lit, StringLiteral):
        return str(lit.value)
    return getattr(lit, "value", None)


def _is_date_only_literal(lit: LiteralValue) -> bool:
    """Check if a literal is a date-only TemporalLiteral (YYYY-MM-DD) without time component."""
    if isinstance(lit, TemporalLiteral) and lit.keyword is None and lit.value is not None:
        return "T" not in lit.value and " " not in lit.value
    return False


def _parse_date_only_range(value: str) -> tuple[datetime.datetime, datetime.datetime]:
    """Parse YYYY-MM-DD string into start of day and start of next day UTC datetimes."""
    d = datetime.date.fromisoformat(value)
    start_dt = datetime.datetime(d.year, d.month, d.day, 0, 0, 0, tzinfo=datetime.timezone.utc)
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


class MongoDBLowerer(QueryLowerer):
    """Deterministic physical query compiler for MongoDB dialect."""

    def lower(self, query: BoundAltrQueryIR) -> PhysicalQueryResult:
        """Translate a schema-bound AltrQL query into a structured MongoDB PhysicalQuery or PhysicalQueryBatch."""
        coll_name = query.entity.name

        # -------------------------------------------------------------------
        # 1. CREATE Operation (Single & Batch)
        # -------------------------------------------------------------------
        if query.operation == QueryOperation.CREATE:
            records = (
                query.records
                if query.records
                else ([BoundCreateRecord(assignments=query.assignments)] if query.assignments else [])
            )

            documents: List[dict[str, Any]] = []
            for rec in records:
                doc: dict[str, Any] = {}
                for a in rec.assignments:
                    doc[a.field.path.full_path] = _convert_literal_to_parameter(a.value)
                documents.append(doc)

            spec = {
                "collection": coll_name,
                "documents": documents,
                "ordered": True,
            }
            return PhysicalQuery(
                dialect="mongodb",
                query="mongodb:insert_many",
                parameters=[spec],
                source_id=query.source_id,
                source_name=query.source_name,
            )

        # -------------------------------------------------------------------
        # Helper: Expression Lowering to BSON MQL Filter
        # -------------------------------------------------------------------
        op_map = {
            ComparisonOperator.GT: "$gt",
            ComparisonOperator.GTE: "$gte",
            ComparisonOperator.LT: "$lt",
            ComparisonOperator.LTE: "$lte",
            ComparisonOperator.EQ: "$eq",
            ComparisonOperator.NEQ: "$ne",
        }

        def lower_field_expression(expr: BoundFieldExpression) -> dict[str, Any]:
            field_path = expr.field.path.full_path
            op = expr.operator
            operand = expr.operand
            is_timestamp_field = expr.field.data_type in (
                StandardDataType.TIMESTAMP,
                StandardDataType.TIMESTAMPTZ,
            )

            # String operators: STARTS, ENDS, HAS, NOT HAS
            if isinstance(op, StringOperator):
                if isinstance(operand, ValueSet):
                    null_elems = [el for el in operand.elements if isinstance(el, NullLiteral)]
                    non_null_elems = [el for el in operand.elements if not isinstance(el, NullLiteral)]
                    has_null = len(null_elems) > 0

                    if op == StringOperator.HAS:
                        elem_preds: List[dict[str, Any]] = []
                        if has_null:
                            elem_preds.append({field_path: None})

                        for elem in non_null_elems:
                            if isinstance(elem, Range):
                                s_val = str(getattr(elem.start, "value", ""))
                                e_val = str(getattr(elem.end, "value", ""))
                                elem_preds.append({field_path: {"$gte": s_val, "$lte": e_val}})
                            else:
                                val_str = str(getattr(elem, "value", ""))
                                elem_preds.append({field_path: {"$regex": re.escape(val_str)}})

                        if not elem_preds:
                            return {}
                        if len(elem_preds) == 1:
                            return elem_preds[0]
                        return {"$or": elem_preds}

                    elif op == StringOperator.NOT_HAS:
                        not_likes: List[dict[str, Any]] = []
                        for elem in non_null_elems:
                            if isinstance(elem, Range):
                                s_val = str(getattr(elem.start, "value", ""))
                                e_val = str(getattr(elem.end, "value", ""))
                                not_likes.append(
                                    {"$or": [{field_path: {"$lt": s_val}}, {field_path: {"$gt": e_val}}]}
                                )
                            else:
                                val_str = str(getattr(elem, "value", ""))
                                not_likes.append({field_path: {"$not": {"$regex": re.escape(val_str)}}})

                        if has_null:
                            # NOT HAS with NULL in ValueSet: must NOT contain substrings AND must NOT be null/missing
                            if not not_likes:
                                return {field_path: {"$ne": None, "$exists": True}}
                            return {"$and": [*not_likes, {field_path: {"$ne": None, "$exists": True}}]}
                        else:
                            # NOT HAS without NULL: matches non-matching strings OR null/missing fields
                            if not not_likes:
                                return {field_path: None}
                            if len(not_likes) == 1:
                                return {"$or": [not_likes[0], {field_path: None}]}
                            return {"$or": [{"$and": not_likes}, {field_path: None}]}

                val_str = str(getattr(operand, "value", ""))
                if op == StringOperator.STARTS:
                    return {field_path: {"$regex": f"^{re.escape(val_str)}"}}
                if op == StringOperator.ENDS:
                    return {field_path: {"$regex": f"{re.escape(val_str)}$"}}
                if op == StringOperator.HAS:
                    return {field_path: {"$regex": re.escape(val_str)}}
                if op == StringOperator.NOT_HAS:
                    return {"$or": [{field_path: {"$not": {"$regex": re.escape(val_str)}}}, {field_path: None}]}

            # Comparison operators (=, !=, >, <, >=, <=)
            if isinstance(op, ComparisonOperator):
                # 1. NullLiteral direct operand
                if isinstance(operand, NullLiteral):
                    if op == ComparisonOperator.EQ:
                        return {field_path: None}
                    if op == ComparisonOperator.NEQ:
                        return {field_path: {"$ne": None, "$exists": True}}
                    return {field_path: {op_map[op]: None}}

                # 2. Range operand
                if isinstance(operand, Range):
                    s_val = _convert_literal_to_parameter(operand.start)
                    e_val = _convert_literal_to_parameter(operand.end)
                    if op == ComparisonOperator.EQ:
                        return {field_path: {"$gte": s_val, "$lte": e_val}}
                    if op == ComparisonOperator.NEQ:
                        return {"$or": [{field_path: {"$lt": s_val}}, {field_path: {"$gt": e_val}}, {field_path: None}]}
                    return {field_path: {"$gte": s_val, "$lte": e_val}}

                # 3. CompoundAndConstraint operand
                if isinstance(operand, CompoundAndConstraint):
                    c_dict = {op_map[c.operator]: _convert_literal_to_parameter(c.value) for c in operand.constraints}
                    return {field_path: c_dict}

                # 4. ComparisonConstraint operand
                if isinstance(operand, ComparisonConstraint):
                    if isinstance(operand.value, NullLiteral):
                        if operand.operator == ComparisonOperator.EQ:
                            return {field_path: None}
                        if operand.operator == ComparisonOperator.NEQ:
                            return {field_path: {"$ne": None, "$exists": True}}
                        return {field_path: {op_map[operand.operator]: None}}

                    if (
                        operand.operator == ComparisonOperator.EQ
                        and is_timestamp_field
                        and _is_date_only_literal(operand.value)
                    ):
                        s_dt, e_dt = _parse_date_only_range(operand.value.value)  # type: ignore[arg-type]
                        return {field_path: {"$gte": s_dt, "$lt": e_dt}}

                    val = _convert_literal_to_parameter(operand.value)
                    if operand.operator == ComparisonOperator.EQ:
                        return {field_path: val}
                    return {field_path: {op_map[operand.operator]: val}}

                # 5. ValueSet operand
                if isinstance(operand, ValueSet):
                    null_elems = [el for el in operand.elements if isinstance(el, NullLiteral)]
                    non_null_elems = [el for el in operand.elements if not isinstance(el, NullLiteral)]
                    has_null = len(null_elems) > 0

                    if op == ComparisonOperator.EQ:
                        predicates: List[dict[str, Any]] = []
                        if has_null:
                            predicates.append({field_path: None})

                        simple_scalars = [
                            el
                            for el in non_null_elems
                            if isinstance(el, (IntegerLiteral, FloatLiteral, StringLiteral, BooleanLiteral))
                            or (isinstance(el, TemporalLiteral) and not (is_timestamp_field and _is_date_only_literal(el)))
                        ]
                        other_elems = [el for el in non_null_elems if el not in simple_scalars]

                        if simple_scalars:
                            if len(simple_scalars) == 1 and not predicates and not other_elems:
                                return {field_path: _convert_literal_to_parameter(simple_scalars[0])}
                            elif len(simple_scalars) == 1:
                                predicates.append({field_path: _convert_literal_to_parameter(simple_scalars[0])})
                            else:
                                predicates.append(
                                    {field_path: {"$in": [_convert_literal_to_parameter(el) for el in simple_scalars]}}
                                )

                        for el in other_elems:
                            if isinstance(el, Range):
                                predicates.append(
                                    {
                                        field_path: {
                                            "$gte": _convert_literal_to_parameter(el.start),
                                            "$lte": _convert_literal_to_parameter(el.end),
                                        }
                                    }
                                )
                            elif isinstance(el, ComparisonConstraint):
                                predicates.append(
                                    {field_path: {op_map[el.operator]: _convert_literal_to_parameter(el.value)}}
                                )
                            elif isinstance(el, CompoundAndConstraint):
                                c_dict = {
                                    op_map[c.operator]: _convert_literal_to_parameter(c.value)
                                    for c in el.constraints
                                }
                                predicates.append({field_path: c_dict})
                            elif isinstance(el, TemporalLiteral) and is_timestamp_field and _is_date_only_literal(el):
                                s_dt, e_dt = _parse_date_only_range(el.value)  # type: ignore[arg-type]
                                predicates.append({field_path: {"$gte": s_dt, "$lt": e_dt}})

                        if len(predicates) == 1:
                            return predicates[0]
                        if not predicates:
                            return {}
                        return {"$or": predicates}

                    elif op == ComparisonOperator.NEQ:
                        predicates: List[dict[str, Any]] = []
                        simple_scalars = [
                            el
                            for el in non_null_elems
                            if isinstance(el, (IntegerLiteral, FloatLiteral, StringLiteral, BooleanLiteral))
                            or (isinstance(el, TemporalLiteral) and not (is_timestamp_field and _is_date_only_literal(el)))
                        ]
                        other_elems = [el for el in non_null_elems if el not in simple_scalars]

                        if simple_scalars:
                            if len(simple_scalars) == 1:
                                predicates.append({field_path: {"$ne": _convert_literal_to_parameter(simple_scalars[0])}})
                            else:
                                predicates.append(
                                    {field_path: {"$nin": [_convert_literal_to_parameter(el) for el in simple_scalars]}}
                                )

                        for el in other_elems:
                            if isinstance(el, Range):
                                predicates.append(
                                    {
                                        "$or": [
                                            {field_path: {"$lt": _convert_literal_to_parameter(el.start)}},
                                            {field_path: {"$gt": _convert_literal_to_parameter(el.end)}},
                                        ]
                                    }
                                )
                            elif isinstance(el, ComparisonConstraint):
                                inv_op = _invert_operator(el.operator)
                                predicates.append(
                                    {field_path: {op_map[inv_op]: _convert_literal_to_parameter(el.value)}}
                                )
                            elif isinstance(el, CompoundAndConstraint):
                                inv_preds = [
                                    {field_path: {op_map[_invert_operator(c.operator)]: _convert_literal_to_parameter(c.value)}}
                                    for c in el.constraints
                                ]
                                predicates.append({"$or": inv_preds})
                            elif isinstance(el, TemporalLiteral) and is_timestamp_field and _is_date_only_literal(el):
                                s_dt, e_dt = _parse_date_only_range(el.value)  # type: ignore[arg-type]
                                predicates.append(
                                    {"$or": [{field_path: {"$lt": s_dt}}, {field_path: {"$gte": e_dt}}]}
                                )

                        if has_null:
                            # Exclude null and missing fields
                            predicates.append({field_path: {"$ne": None, "$exists": True}})
                            if len(predicates) == 1:
                                return predicates[0]
                            return {"$and": predicates}
                        else:
                            # In MongoDB, $ne and $nin natively match missing and null fields
                            if len(predicates) == 1:
                                return predicates[0]
                            return {"$and": predicates}

                # 6. Direct scalar operand comparison
                if op == ComparisonOperator.EQ:
                    if is_timestamp_field and _is_date_only_literal(operand):
                        s_dt, e_dt = _parse_date_only_range(operand.value)  # type: ignore[arg-type]
                        return {field_path: {"$gte": s_dt, "$lt": e_dt}}
                    return {field_path: _convert_literal_to_parameter(operand)}

                if op == ComparisonOperator.NEQ:
                    return {field_path: {"$ne": _convert_literal_to_parameter(operand)}}

                return {field_path: {op_map[op]: _convert_literal_to_parameter(operand)}}

            raise NotImplementedError(f"Unsupported operator '{op}' in MongoDBLowerer")

        def lower_expression(expr: BoundExpression) -> dict[str, Any]:
            if isinstance(expr, BoundFieldExpression):
                return lower_field_expression(expr)

            if isinstance(expr, BoundNegationExpression):
                inner_filter = lower_expression(expr.operand)
                return {"$nor": [inner_filter]}

            if isinstance(expr, BoundLogicalExpression):
                left_filter = lower_expression(expr.left)
                right_filter = lower_expression(expr.right)
                if expr.operator.value == "AND":
                    return {"$and": [left_filter, right_filter]}
                elif expr.operator.value == "OR":
                    return {"$or": [left_filter, right_filter]}

            return {}

        # -------------------------------------------------------------------
        # 2. UPDATE Operation
        # -------------------------------------------------------------------
        if query.operation == QueryOperation.UPDATE:
            set_doc: dict[str, Any] = {}
            for a in query.assignments:
                set_doc[a.field.path.full_path] = _convert_literal_to_parameter(a.value)

            filter_doc = lower_expression(query.where) if query.where is not None else {}
            spec = {
                "collection": coll_name,
                "filter": filter_doc,
                "update": {"$set": set_doc},
                "upsert": False,
            }
            return PhysicalQuery(
                dialect="mongodb",
                query="mongodb:update_many",
                parameters=[spec],
                source_id=query.source_id,
                source_name=query.source_name,
            )

        # -------------------------------------------------------------------
        # 3. DELETE Operation
        # -------------------------------------------------------------------
        if query.operation == QueryOperation.DELETE:
            filter_doc = lower_expression(query.where) if query.where is not None else {}
            spec = {
                "collection": coll_name,
                "filter": filter_doc,
            }
            return PhysicalQuery(
                dialect="mongodb",
                query="mongodb:delete_many",
                parameters=[spec],
                source_id=query.source_id,
                source_name=query.source_name,
            )

        # -------------------------------------------------------------------
        # 4. READ Operation (GET / find)
        # -------------------------------------------------------------------
        filter_doc = lower_expression(query.where) if query.where is not None else {}
        find_spec: dict[str, Any] = {
            "collection": coll_name,
            "filter": filter_doc,
        }

        # Projection handling
        if not query.is_wildcard_projection and query.projection:
            proj_dict: dict[str, int] = {}
            has_id = False
            for sel in query.projection:
                col = sel.field.path.full_path
                proj_dict[col] = 1
                if col == "_id":
                    has_id = True
            if not has_id:
                proj_dict["_id"] = 0
            find_spec["projection"] = proj_dict
        else:
            find_spec["projection"] = None

        # Sorting & Ordering
        sort_items: List[List[Any]] = []
        if query.ranking:
            rank_col = query.ranking.field.path.full_path
            rank_dir = -1 if query.ranking.direction == RankingDirection.TOP else 1
            sort_items.append([rank_col, rank_dir])

        if query.sort:
            for s in query.sort:
                sort_col = s.field.path.full_path
                sort_dir = 1 if s.direction == SortDirection.ASC else -1
                sort_items.append([sort_col, sort_dir])

        # Default Primary Key Ordering
        if not query.ranking and not query.sort and query.entity.primary_key:
            for pk_col in query.entity.primary_key:
                sort_items.append([pk_col, 1])
        elif not query.ranking and not query.sort and not query.entity.primary_key:
            # Fallback deterministic sort by _id
            sort_items.append(["_id", 1])

        if sort_items:
            find_spec["sort"] = sort_items

        # Limit & Skip
        limit_val = query.ranking.count if query.ranking else query.limit
        if limit_val is not None:
            find_spec["limit"] = int(limit_val)

        if query.offset is not None:
            find_spec["skip"] = int(query.offset)

        return PhysicalQuery(
            dialect="mongodb",
            query="mongodb:find",
            parameters=[find_spec],
            source_id=query.source_id,
            source_name=query.source_name,
        )
