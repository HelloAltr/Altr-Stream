"""Exception hierarchy for AltrQL lexical and syntactic analysis."""

from typing import Optional, Sequence


class AltrQueryError(Exception):
    """Base exception for all AltrQL query engine errors."""

    def __init__(
        self,
        message: str,
        line: Optional[int] = None,
        column: Optional[int] = None,
    ) -> None:
        self.message = message
        self.line = line
        self.column = column
        loc_str = f" at line {line}, column {column}" if line is not None and column is not None else ""
        super().__init__(f"{message}{loc_str}")


class AltrQueryLexError(AltrQueryError):
    """Raised during tokenization when encountering invalid characters or unterminated literals."""

    def __init__(
        self,
        message: str,
        line: int,
        column: int,
    ) -> None:
        super().__init__(message=message, line=line, column=column)


class AltrQueryParseError(AltrQueryError):
    """Raised during parsing when encountering syntax violations or unexpected tokens."""

    def __init__(
        self,
        message: str,
        line: Optional[int] = None,
        column: Optional[int] = None,
        unexpected_token: Optional[str] = None,
        expected_tokens: Optional[Sequence[str]] = None,
    ) -> None:
        self.unexpected_token = unexpected_token
        self.expected_tokens = list(expected_tokens) if expected_tokens is not None else None
        super().__init__(message=message, line=line, column=column)
