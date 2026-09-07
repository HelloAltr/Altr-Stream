"""Domain enums for AltrQL operators, directions, and temporal keywords."""

from enum import Enum


class ComparisonOperator(str, Enum):
    """Comparison operators supported in field expressions and value sets."""

    EQ = "="
    NEQ = "!="
    GT = ">"
    LT = "<"
    GTE = ">="
    LTE = "<="


class StringOperator(str, Enum):
    """String pattern and inclusion operators."""

    STARTS = "STARTS"
    ENDS = "ENDS"
    HAS = "HAS"
    NOT_HAS = "NOT HAS"


class SortDirection(str, Enum):
    """Explicit sorting direction."""

    ASC = "ASC"
    DESC = "DESC"


class RankingDirection(str, Enum):
    """Ranking directions for TOP / BOTTOM clauses."""

    TOP = "TOP"
    BOTTOM = "BOTTOM"


class TemporalKeyword(str, Enum):
    """Reserved temporal literal keywords."""

    TODAY = "TODAY"
    NOW = "NOW"
