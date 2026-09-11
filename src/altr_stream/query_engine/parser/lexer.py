"""Strict, case-sensitive lexical analyzer (tokenizer) for AltrQL v0.4."""

from __future__ import annotations

import datetime
from dataclasses import dataclass
from enum import Enum, auto
import re
from typing import Any, List, Optional

from altr_stream.query_engine.domain.errors import AltrQueryLexError


class TokenType(Enum):
    # Structural
    LPAREN = auto()       # (
    RPAREN = auto()       # )
    LBRACE = auto()       # {
    RBRACE = auto()       # }
    COMMA = auto()        # ,
    SEMICOLON = auto()    # ;
    DOT = auto()          # .
    COLON = auto()        # :
    AMPERSAND = auto()    # &
    DOTDOT = auto()       # ..

    # Comparison Operators
    EQ = auto()           # =
    NEQ = auto()          # !=
    GT = auto()           # >
    LT = auto()           # <
    GTE = auto()          # >=
    LTE = auto()          # <=

    # Literals
    IDENTIFIER = auto()        # e.g. users, id, age
    STRING = auto()            # "hello"
    INTEGER = auto()           # 42
    FLOAT = auto()             # 3.14
    TEMPORAL_LITERAL = auto()  # @YYYY-MM-DD (e.g. @2026-01-01)

    # Reserved Keywords (Strictly Uppercase)
    GET = auto()
    CREATE = auto()
    UPDATE = auto()
    DELETE = auto()
    WHERE = auto()
    AND = auto()
    OR = auto()
    SORT = auto()
    ASC = auto()
    DESC = auto()
    TOP = auto()
    BOTTOM = auto()
    BY = auto()
    LIMIT = auto()
    OFFSET = auto()
    AS = auto()
    NOT = auto()
    HAS = auto()
    STARTS = auto()
    ENDS = auto()
    TRUE = auto()
    FALSE = auto()
    NULL = auto()
    TODAY = auto()
    NOW = auto()

    # End of Input
    EOF = auto()


RESERVED_KEYWORDS = {
    "GET": TokenType.GET,
    "CREATE": TokenType.CREATE,
    "UPDATE": TokenType.UPDATE,
    "DELETE": TokenType.DELETE,
    "WHERE": TokenType.WHERE,
    "AND": TokenType.AND,
    "OR": TokenType.OR,
    "SORT": TokenType.SORT,
    "ASC": TokenType.ASC,
    "DESC": TokenType.DESC,
    "TOP": TokenType.TOP,
    "BOTTOM": TokenType.BOTTOM,
    "BY": TokenType.BY,
    "LIMIT": TokenType.LIMIT,
    "OFFSET": TokenType.OFFSET,
    "AS": TokenType.AS,
    "NOT": TokenType.NOT,
    "HAS": TokenType.HAS,
    "STARTS": TokenType.STARTS,
    "ENDS": TokenType.ENDS,
    "TRUE": TokenType.TRUE,
    "FALSE": TokenType.FALSE,
    "NULL": TokenType.NULL,
    "TODAY": TokenType.TODAY,
    "NOW": TokenType.NOW,
}


@dataclass(frozen=True)
class Token:
    """Represents a scanned lexical token with position metadata."""

    type: TokenType
    value: Any
    line: int
    column: int
    lexeme: str

    def __repr__(self) -> str:
        return f"Token({self.type.name}, value={self.value!r}, line={self.line}, col={self.column})"


class Lexer:
    """Scans AltrQL text into a stream of typed tokens."""

    def __init__(self, source: str) -> None:
        self.source = source
        self.length = len(source)
        self.cursor = 0
        self.line = 1
        self.column = 1

    def _is_at_end(self) -> bool:
        return self.cursor >= self.length

    def _peek(self, offset: int = 0) -> str:
        pos = self.cursor + offset
        if pos >= self.length:
            return "\0"
        return self.source[pos]

    def _advance(self) -> str:
        char = self.source[self.cursor]
        self.cursor += 1
        if char == "\n":
            self.line += 1
            self.column = 1
        else:
            self.column += 1
        return char

    def tokenize(self) -> List[Token]:
        """Tokenize the entire source string into a list of Tokens ending with EOF."""
        tokens: List[Token] = []

        while not self._is_at_end():
            start_line = self.line
            start_col = self.column
            char = self._peek()

            # 1. Skip Whitespace
            if char in (" ", "\t", "\r", "\n"):
                self._advance()
                continue

            # 2. Comments (// to end of line)
            if char == "/" and self._peek(1) == "/":
                self._advance()
                self._advance()
                while not self._is_at_end() and self._peek() != "\n":
                    self._advance()
                continue

            # 3. Two-character and single-character structural tokens
            if char == "." and self._peek(1) == ".":
                self._advance()
                self._advance()
                tokens.append(Token(TokenType.DOTDOT, "..", start_line, start_col, ".."))
                continue

            if char == "!" and self._peek(1) == "=":
                self._advance()
                self._advance()
                tokens.append(Token(TokenType.NEQ, "!=", start_line, start_col, "!="))
                continue

            if char == ">" and self._peek(1) == "=":
                self._advance()
                self._advance()
                tokens.append(Token(TokenType.GTE, ">=", start_line, start_col, ">="))
                continue

            if char == "<" and self._peek(1) == "=":
                self._advance()
                self._advance()
                tokens.append(Token(TokenType.LTE, "<=", start_line, start_col, "<="))
                continue

            single_tokens = {
                "(": TokenType.LPAREN,
                ")": TokenType.RPAREN,
                "{": TokenType.LBRACE,
                "}": TokenType.RBRACE,
                ",": TokenType.COMMA,
                ";": TokenType.SEMICOLON,
                ".": TokenType.DOT,
                ":": TokenType.COLON,
                "&": TokenType.AMPERSAND,
                "=": TokenType.EQ,
                ">": TokenType.GT,
                "<": TokenType.LT,
            }

            if char in single_tokens:
                self._advance()
                tokens.append(Token(single_tokens[char], char, start_line, start_col, char))
                continue

            # 4. String Literals ("...")
            if char == '"':
                tokens.append(self._scan_string(start_line, start_col))
                continue

            # 5. Explicit Temporal Date Literals (@YYYY-MM-DD)
            if char == '@':
                tokens.append(self._scan_temporal_literal(start_line, start_col))
                continue

            # 6. Number Literals (Integer & Float)
            if char.isdigit():
                tokens.append(self._scan_number(start_line, start_col))
                continue

            # 7. Identifiers & Keywords
            if char.isalpha() or char == "_":
                tokens.append(self._scan_identifier_or_keyword(start_line, start_col))
                continue

            # Invalid Character
            self._advance()
            raise AltrQueryLexError(
                f"Unexpected character {char!r}",
                line=start_line,
                column=start_col,
            )

        tokens.append(Token(TokenType.EOF, "", self.line, self.column, ""))
        return tokens

    def _scan_temporal_literal(self, start_line: int, start_col: int) -> Token:
        self._advance()  # Consume '@'
        start_idx = self.cursor

        # Consume raw literal characters until whitespace or structural delimiter
        while not self._is_at_end():
            c = self._peek()
            if c in (" ", "\t", "\r", "\n", ",", ";", ")", "}", "(", "{", "&", "=", "!", "<", ">", "/"):
                break
            if c == "." and self._peek(1) == ".":
                break
            self._advance()

        raw_str = self.source[start_idx : self.cursor]
        lexeme = f"@{raw_str}"

        # 1. Format validation: must match exact \d{4}-\d{2}-\d{2}
        if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", raw_str):
            raise AltrQueryLexError(
                f"Malformed temporal literal '{lexeme}'. Expected ISO format '@YYYY-MM-DD'.",
                line=start_line,
                column=start_col,
            )

        # 2. Calendar date validation (real calendar date)
        try:
            datetime.date.fromisoformat(raw_str)
        except ValueError as e:
            raise AltrQueryLexError(
                f"Invalid calendar date in temporal literal '{lexeme}': {e}.",
                line=start_line,
                column=start_col,
            )

        return Token(TokenType.TEMPORAL_LITERAL, raw_str, start_line, start_col, lexeme)

    def _scan_string(self, start_line: int, start_col: int) -> Token:
        self._advance()  # opening quote
        chars: List[str] = []

        while not self._is_at_end():
            c = self._peek()
            if c == '"':
                self._advance()  # closing quote
                lexeme = self.source[self.cursor - len(chars) - 2 : self.cursor]
                return Token(TokenType.STRING, "".join(chars), start_line, start_col, lexeme)

            if c == "\n":
                raise AltrQueryLexError(
                    "Unterminated string literal (newline in string)",
                    line=start_line,
                    column=start_col,
                )

            if c == "\\":
                self._advance()
                if self._is_at_end():
                    raise AltrQueryLexError(
                        "Unterminated escape sequence at end of string",
                        line=start_line,
                        column=start_col,
                    )
                escaped = self._advance()
                escape_map = {"n": "\n", "t": "\t", "r": "\r", "\\": "\\", '"': '"'}
                chars.append(escape_map.get(escaped, escaped))
            else:
                chars.append(self._advance())

        raise AltrQueryLexError(
            "Unterminated string literal",
            line=start_line,
            column=start_col,
        )

    def _scan_number(self, start_line: int, start_col: int) -> Token:
        start_idx = self.cursor

        while not self._is_at_end() and self._peek().isdigit():
            self._advance()

        # Check for float dot, ensuring it is NOT a range operator '..'
        is_float = False
        if self._peek() == "." and self._peek(1) != ".":
            is_float = True
            self._advance()  # Consume '.'
            if not self._peek().isdigit():
                raise AltrQueryLexError(
                    "Malformed float literal: expected digits after decimal point",
                    line=start_line,
                    column=start_col,
                )
            while not self._is_at_end() and self._peek().isdigit():
                self._advance()

        raw_str = self.source[start_idx : self.cursor]
        if is_float:
            return Token(TokenType.FLOAT, float(raw_str), start_line, start_col, raw_str)
        return Token(TokenType.INTEGER, int(raw_str), start_line, start_col, raw_str)

    def _scan_identifier_or_keyword(self, start_line: int, start_col: int) -> Token:
        start_idx = self.cursor

        while not self._is_at_end() and (self._peek().isalnum() or self._peek() == "_"):
            self._advance()

        lexeme = self.source[start_idx : self.cursor]

        # Strict case sensitivity check
        if lexeme in RESERVED_KEYWORDS:
            return Token(RESERVED_KEYWORDS[lexeme], lexeme, start_line, start_col, lexeme)

        return Token(TokenType.IDENTIFIER, lexeme, start_line, start_col, lexeme)
