"""Safe deterministic parser for MongoDB Shell query syntax.

Translates a constrained, safe subset of MongoDB Shell syntax into the standard
PhysicalQuery structured command dictionary without using eval(), exec(), or arbitrary JavaScript execution.
"""

from datetime import datetime, timezone
import decimal
import re
from typing import Any
import uuid

import bson
from bson import Decimal128, ObjectId
from bson.timestamp import Timestamp

from altr_stream.domain.errors import QueryExecutionError


class TokenType:
    IDENTIFIER = "IDENTIFIER"
    STRING = "STRING"
    NUMBER = "NUMBER"
    DOT = "DOT"
    LPAREN = "LPAREN"
    RPAREN = "RPAREN"
    LBRACE = "LBRACE"
    RBRACE = "RBRACE"
    LBRACKET = "LBRACKET"
    RBRACKET = "RBRACKET"
    COLON = "COLON"
    COMMA = "COMMA"
    SEMICOLON = "SEMICOLON"
    EOF = "EOF"


class Token:
    def __init__(self, token_type: str, value: Any, position: int):
        self.type = token_type
        self.value = value
        self.position = position

    def __repr__(self) -> str:
        return f"Token({self.type}, {self.value!r}, pos={self.position})"


class MongoShellLexer:
    """Deterministic lexer for MongoDB Shell syntax."""

    def __init__(self, text: str):
        self.text = text
        self.length = len(text)
        self.pos = 0

    def _peek(self) -> str:
        if self.pos < self.length:
            return self.text[self.pos]
        return ""

    def _peek_next(self) -> str:
        if self.pos + 1 < self.length:
            return self.text[self.pos + 1]
        return ""

    def _advance(self) -> str:
        ch = self._peek()
        self.pos += 1
        return ch

    def _skip_whitespace_and_comments(self) -> None:
        while self.pos < self.length:
            ch = self._peek()
            # Whitespace
            if ch.isspace():
                self.pos += 1
                continue
            # Single-line comment //
            if ch == "/" and self._peek_next() == "/":
                self.pos += 2
                while self.pos < self.length and self.text[self.pos] not in "\r\n":
                    self.pos += 1
                continue
            # Multi-line comment /* ... */
            if ch == "/" and self._peek_next() == "*":
                self.pos += 2
                while self.pos < self.length:
                    if self.text[self.pos] == "*" and self.pos + 1 < self.length and self.text[self.pos + 1] == "/":
                        self.pos += 2
                        break
                    self.pos += 1
                continue
            break

    def tokenize(self) -> list[Token]:
        tokens: list[Token] = []
        while self.pos < self.length:
            self._skip_whitespace_and_comments()
            if self.pos >= self.length:
                break

            start_pos = self.pos
            ch = self._peek()

            if ch == ".":
                self._advance()
                tokens.append(Token(TokenType.DOT, ".", start_pos))
            elif ch == "(":
                self._advance()
                tokens.append(Token(TokenType.LPAREN, "(", start_pos))
            elif ch == ")":
                self._advance()
                tokens.append(Token(TokenType.RPAREN, ")", start_pos))
            elif ch == "{":
                self._advance()
                tokens.append(Token(TokenType.LBRACE, "{", start_pos))
            elif ch == "}":
                self._advance()
                tokens.append(Token(TokenType.RBRACE, "}", start_pos))
            elif ch == "[":
                self._advance()
                tokens.append(Token(TokenType.LBRACKET, "[", start_pos))
            elif ch == "]":
                self._advance()
                tokens.append(Token(TokenType.RBRACKET, "]", start_pos))
            elif ch == ":":
                self._advance()
                tokens.append(Token(TokenType.COLON, ":", start_pos))
            elif ch == ",":
                self._advance()
                tokens.append(Token(TokenType.COMMA, ",", start_pos))
            elif ch == ";":
                self._advance()
                tokens.append(Token(TokenType.SEMICOLON, ";", start_pos))
            elif ch in ("'", '"'):
                # String literal
                quote = self._advance()
                chars = []
                while self.pos < self.length:
                    curr = self._advance()
                    if curr == quote:
                        break
                    if curr == "\\" and self.pos < self.length:
                        esc = self._advance()
                        if esc == "n":
                            chars.append("\n")
                        elif esc == "t":
                            chars.append("\t")
                        elif esc == "r":
                            chars.append("\r")
                        elif esc == "\\":
                            chars.append("\\")
                        elif esc == quote:
                            chars.append(quote)
                        elif esc == "/":
                            chars.append("/")
                        elif esc == "b":
                            chars.append("\b")
                        elif esc == "f":
                            chars.append("\f")
                        elif esc == "u" and self.pos + 4 <= self.length:
                            hex_code = self.text[self.pos : self.pos + 4]
                            self.pos += 4
                            try:
                                chars.append(chr(int(hex_code, 16)))
                            except Exception:
                                chars.append("\\u" + hex_code)
                        else:
                            chars.append(esc)
                    else:
                        chars.append(curr)
                else:
                    raise QueryExecutionError(
                        f"Invalid MongoDB shell syntax: Unterminated string literal starting at position {start_pos}."
                    )
                tokens.append(Token(TokenType.STRING, "".join(chars), start_pos))
            elif ch == "-" or ch.isdigit():
                # Number literal
                num_str = self._read_number()
                try:
                    if "." in num_str or "e" in num_str.lower():
                        val = float(num_str)
                    else:
                        val = int(num_str)
                    tokens.append(Token(TokenType.NUMBER, val, start_pos))
                except Exception as e:
                    raise QueryExecutionError(
                        f"Invalid MongoDB shell syntax: Malformed number '{num_str}' at position {start_pos}."
                    ) from e
            elif ch in ("=", ">", "<", "!", "&", "|", "+", "*", "/", "%", "^", "~", "?"):
                sym = self._advance()
                if self._peek() == ">" and sym == "=": # =>
                    sym += self._advance()
                elif self._peek() == "=" and sym in ("=", "!", "<", ">"): # ==, !=, <=, >=
                    sym += self._advance()
                tokens.append(Token(TokenType.IDENTIFIER, sym, start_pos))
            elif ch.isalpha() or ch in ("_", "$"):
                # Identifier or keyword
                ident = self._read_identifier()
                tokens.append(Token(TokenType.IDENTIFIER, ident, start_pos))
            else:
                raise QueryExecutionError(
                    f"Invalid MongoDB shell syntax: Unexpected character '{ch}' at position {start_pos}."
                )

        tokens.append(Token(TokenType.EOF, "", self.pos))
        return tokens

    def _read_identifier(self) -> str:
        start = self.pos
        while self.pos < self.length:
            ch = self.text[self.pos]
            if ch.isalnum() or ch in ("_", "$", "-"):
                self.pos += 1
            else:
                break
        return self.text[start : self.pos]

    def _read_number(self) -> str:
        start = self.pos
        if self._peek() == "-":
            self._advance()
        while self.pos < self.length and (self.text[self.pos].isdigit() or self.text[self.pos] in (".", "e", "E", "+", "-")):
            # Check for negative exponent vs operator
            curr = self.text[self.pos]
            if curr in ("+", "-") and self.pos > start and self.text[self.pos - 1] not in ("e", "E"):
                break
            self.pos += 1
        return self.text[start : self.pos]


class MongoShellParser:
    """Deterministic recursive-descent parser for MongoDB Shell queries."""

    def __init__(self, tokens: list[Token], original_query: str):
        self.tokens = tokens
        self.pos = 0
        self.original_query = original_query

    def _current(self) -> Token:
        if self.pos < len(self.tokens):
            return self.tokens[self.pos]
        return self.tokens[-1]

    def _match(self, *expected_types: str) -> bool:
        if self._current().type in expected_types:
            self.pos += 1
            return True
        return False

    def _expect(self, expected_type: str, error_msg: str | None = None) -> Token:
        curr = self._current()
        if curr.type != expected_type:
            msg = error_msg or f"Expected '{expected_type}', found '{curr.type}' ({curr.value!r}) at position {curr.position}."
            raise QueryExecutionError(f"Invalid MongoDB shell syntax: {msg}")
        self.pos += 1
        return curr

    def parse(self) -> tuple[str, dict[str, Any]]:
        """Parse shell statement and return (operation_string, spec_dict)."""
        curr = self._current()

        # Check db identifier
        if curr.type == TokenType.IDENTIFIER and curr.value == "db":
            self.pos += 1
        else:
            raise QueryExecutionError(
                f"Invalid MongoDB shell syntax: Query must begin with 'db.<collection>.<operation>()', found '{curr.value}' at position {curr.position}."
            )

        # Expect .<collection>
        self._expect(TokenType.DOT, "Expected '.' after 'db'.")
        coll_token = self._expect(TokenType.IDENTIFIER, "Expected collection name after 'db.'.")
        collection_name = coll_token.value

        # Expect .<operation>
        self._expect(TokenType.DOT, f"Expected '.' after 'db.{collection_name}'.")
        op_token = self._expect(TokenType.IDENTIFIER, f"Expected operation name after 'db.{collection_name}.'.")
        raw_op = op_token.value

        # Normalize operation name
        op_map = {
            "find": "find",
            "insertmany": "insert_many",
            "insert_many": "insert_many",
            "updatemany": "update_many",
            "update_many": "update_many",
            "deletemany": "delete_many",
            "delete_many": "delete_many",
        }

        normalized_op_key = raw_op.lower()
        if normalized_op_key not in op_map:
            raise QueryExecutionError(
                f"Unsupported MongoDB shell expression: Unsupported collection operation '{raw_op}'. Supported operations are: find(), insertMany(), updateMany(), deleteMany()."
            )

        canonical_op = op_map[normalized_op_key]
        spec: dict[str, Any] = {"collection": collection_name}

        # Parse operation arguments
        self._expect(TokenType.LPAREN, f"Expected '(' after '{raw_op}'.")

        if canonical_op == "find":
            self._parse_find_args(spec)
        elif canonical_op == "insert_many":
            self._parse_insert_many_args(spec)
        elif canonical_op == "update_many":
            self._parse_update_many_args(spec)
        elif canonical_op == "delete_many":
            self._parse_delete_many_args(spec)

        self._expect(TokenType.RPAREN, f"Expected ')' closing '{raw_op}' arguments.")

        # Parse chained modifiers (e.g. .sort(), .skip(), .limit(), .pretty())
        while self._current().type == TokenType.DOT:
            self.pos += 1
            mod_token = self._expect(TokenType.IDENTIFIER, "Expected modifier name after '.'.")
            mod_name = mod_token.value
            mod_key = mod_name.lower()

            if canonical_op != "find":
                raise QueryExecutionError(
                    f"Unsupported MongoDB shell expression: Chained modifier '{mod_name}()' is not supported on write operation '{raw_op}()'."
                )

            self._expect(TokenType.LPAREN, f"Expected '(' after '{mod_name}'.")

            if mod_key == "pretty":
                # Presentation modifier: no arguments, no effect on physical command
                self._expect(TokenType.RPAREN, "Expected ')' for pretty().")
            elif mod_key == "sort":
                sort_val = self._parse_value()
                if not isinstance(sort_val, (dict, list)):
                    raise QueryExecutionError(
                        f"MongoDB 'sort()' expects an object or list specification, found {type(sort_val).__name__}."
                    )
                spec["sort"] = sort_val
                self._expect(TokenType.RPAREN, "Expected ')' closing sort().")
            elif mod_key == "skip":
                skip_val = self._parse_value()
                if not isinstance(skip_val, int) or skip_val < 0:
                    raise QueryExecutionError(
                        f"MongoDB 'skip()' expects a non-negative integer, found {skip_val!r}."
                    )
                spec["skip"] = skip_val
                self._expect(TokenType.RPAREN, "Expected ')' closing skip().")
            elif mod_key == "limit":
                limit_val = self._parse_value()
                if not isinstance(limit_val, int) or limit_val < 0:
                    raise QueryExecutionError(
                        f"MongoDB 'limit()' expects a non-negative integer, found {limit_val!r}."
                    )
                spec["limit"] = limit_val
                self._expect(TokenType.RPAREN, "Expected ')' closing limit().")
            else:
                raise QueryExecutionError(
                    f"Unsupported MongoDB shell expression: '{mod_name}()' is not a supported cursor modifier."
                )

        # Allow optional trailing semicolons
        while self._current().type == TokenType.SEMICOLON:
            self.pos += 1

        # Check for unconsumed trailing tokens
        if self._current().type != TokenType.EOF:
            curr = self._current()
            raise QueryExecutionError(
                f"Invalid MongoDB shell syntax: Unexpected token '{curr.value}' at position {curr.position} after valid query expression."
            )

        return f"mongodb:{canonical_op}", spec

    def _parse_find_args(self, spec: dict[str, Any]) -> None:
        if self._current().type == TokenType.RPAREN:
            spec["filter"] = {}
            return

        # 1st argument: filter
        filter_doc = self._parse_value()
        if not isinstance(filter_doc, dict):
            raise QueryExecutionError(
                f"MongoDB 'find()' filter must be a document object, found {type(filter_doc).__name__}."
            )
        spec["filter"] = filter_doc

        # Optional 2nd argument: projection
        if self._match(TokenType.COMMA):
            if self._current().type == TokenType.RPAREN:
                return
            projection_doc = self._parse_value()
            if not isinstance(projection_doc, dict):
                raise QueryExecutionError(
                    f"MongoDB 'find()' projection must be a document object, found {type(projection_doc).__name__}."
                )
            spec["projection"] = projection_doc

    def _parse_insert_many_args(self, spec: dict[str, Any]) -> None:
        if self._current().type == TokenType.RPAREN:
            raise QueryExecutionError("MongoDB 'insertMany()' requires a non-empty array of document objects.")

        docs = self._parse_value()
        if not isinstance(docs, list) or len(docs) == 0:
            raise QueryExecutionError("MongoDB 'insertMany()' requires a non-empty array of document objects.")

        for i, d in enumerate(docs):
            if not isinstance(d, dict):
                raise QueryExecutionError(
                    f"MongoDB 'insertMany()' documents must all be objects; item at index {i} is {type(d).__name__}."
                )

        spec["documents"] = docs
        spec["ordered"] = True

        # Optional options document
        if self._match(TokenType.COMMA):
            if self._current().type != TokenType.RPAREN:
                opts = self._parse_value()
                if isinstance(opts, dict) and "ordered" in opts:
                    spec["ordered"] = bool(opts["ordered"])

    def _parse_update_many_args(self, spec: dict[str, Any]) -> None:
        if self._current().type == TokenType.RPAREN:
            raise QueryExecutionError("MongoDB 'updateMany()' requires filter and update document arguments.")

        # 1st argument: filter
        filter_doc = self._parse_value()
        if not isinstance(filter_doc, dict):
            raise QueryExecutionError(
                f"MongoDB 'updateMany()' filter must be an object, found {type(filter_doc).__name__}."
            )
        spec["filter"] = filter_doc

        # Expect comma before update doc
        self._expect(TokenType.COMMA, "Expected ',' between filter and update document in updateMany().")

        # 2nd argument: update
        update_doc = self._parse_value()
        if not isinstance(update_doc, dict) or not update_doc:
            raise QueryExecutionError("MongoDB 'updateMany()' requires a non-empty update document.")
        spec["update"] = update_doc

        # Optional 3rd argument: options (e.g. { upsert: true })
        if self._match(TokenType.COMMA):
            if self._current().type != TokenType.RPAREN:
                opts = self._parse_value()
                if isinstance(opts, dict) and "upsert" in opts:
                    spec["upsert"] = bool(opts["upsert"])

    def _parse_delete_many_args(self, spec: dict[str, Any]) -> None:
        if self._current().type == TokenType.RPAREN:
            raise QueryExecutionError("MongoDB 'deleteMany()' requires a filter document argument.")

        filter_doc = self._parse_value()
        if not isinstance(filter_doc, dict):
            raise QueryExecutionError(
                f"MongoDB 'deleteMany()' filter must be an object, found {type(filter_doc).__name__}."
            )
        spec["filter"] = filter_doc

    def _parse_value(self) -> Any:
        curr = self._current()

        # Object
        if curr.type == TokenType.LBRACE:
            return self._parse_object()

        # Array
        if curr.type == TokenType.LBRACKET:
            return self._parse_array()

        # String
        if curr.type == TokenType.STRING:
            self.pos += 1
            return curr.value

        # Number
        if curr.type == TokenType.NUMBER:
            self.pos += 1
            return curr.value

        # Identifier keywords & BSON constructors
        if curr.type == TokenType.IDENTIFIER:
            val = curr.value

            if val in ("true", "True"):
                self.pos += 1
                return True
            if val in ("false", "False"):
                self.pos += 1
                return False
            if val in ("null", "None"):
                self.pos += 1
                return None

            # Optional 'new' constructor keyword e.g. new Date(...) or new ObjectId(...)
            if val == "new":
                self.pos += 1
                ctor_token = self._expect(TokenType.IDENTIFIER, "Expected constructor name after 'new'.")
                return self._parse_bson_constructor(ctor_token.value)

            # Direct constructor call e.g. ObjectId("..."), ISODate("...")
            if self.pos + 1 < len(self.tokens) and self.tokens[self.pos + 1].type == TokenType.LPAREN:
                self.pos += 1
                return self._parse_bson_constructor(val)

            raise QueryExecutionError(
                f"Invalid MongoDB shell syntax: Unrecognized identifier '{val}' at position {curr.position}."
            )

        raise QueryExecutionError(
            f"Invalid MongoDB shell syntax: Unexpected token '{curr.value}' ({curr.type}) at position {curr.position}."
        )

    def _parse_object(self) -> dict[str, Any]:
        self._expect(TokenType.LBRACE)
        res: dict[str, Any] = {}

        if self._match(TokenType.RBRACE):
            return res

        while True:
            curr = self._current()
            key_name: str
            if curr.type in (TokenType.IDENTIFIER, TokenType.STRING):
                key_name = str(curr.value)
                self.pos += 1
            elif curr.type == TokenType.NUMBER:
                key_name = str(curr.value)
                self.pos += 1
            else:
                raise QueryExecutionError(
                    f"Invalid MongoDB shell syntax: Expected property name in object, found '{curr.value}' ({curr.type}) at position {curr.position}."
                )

            self._expect(TokenType.COLON, f"Expected ':' after property '{key_name}'.")
            val = self._parse_value()
            res[key_name] = val

            if self._match(TokenType.COMMA):
                # Allow trailing comma in object { a: 1, }
                if self._match(TokenType.RBRACE):
                    break
                continue
            elif self._match(TokenType.RBRACE):
                break
            else:
                curr = self._current()
                raise QueryExecutionError(
                    f"Invalid MongoDB shell syntax: Expected ',' or '}}' in object, found '{curr.value}' at position {curr.position}."
                )

        return res

    def _parse_array(self) -> list[Any]:
        self._expect(TokenType.LBRACKET)
        items: list[Any] = []

        if self._match(TokenType.RBRACKET):
            return items

        while True:
            items.append(self._parse_value())

            if self._match(TokenType.COMMA):
                # Allow trailing comma in array [1, 2, ]
                if self._match(TokenType.RBRACKET):
                    break
                continue
            elif self._match(TokenType.RBRACKET):
                break
            else:
                curr = self._current()
                raise QueryExecutionError(
                    f"Invalid MongoDB shell syntax: Expected ',' or ']' in array, found '{curr.value}' at position {curr.position}."
                )

        return items

    def _parse_bson_constructor(self, ctor_name: str) -> Any:
        self._expect(TokenType.LPAREN, f"Expected '(' after constructor '{ctor_name}'.")

        ctor_lower = ctor_name.lower()

        if ctor_lower in ("objectid",):
            arg = self._parse_value()
            self._expect(TokenType.RPAREN, f"Expected ')' closing {ctor_name}().")
            if not isinstance(arg, str):
                raise QueryExecutionError(f"ObjectId() expects a 24-character hexadecimal string, found {type(arg).__name__}.")
            try:
                return ObjectId(arg)
            except Exception as e:
                raise QueryExecutionError(f"Invalid ObjectId string '{arg}': {e}") from e

        elif ctor_lower in ("isodate", "date"):
            arg = self._parse_value()
            self._expect(TokenType.RPAREN, f"Expected ')' closing {ctor_name}().")
            if not isinstance(arg, str):
                raise QueryExecutionError(f"{ctor_name}() expects an ISO datetime string, found {type(arg).__name__}.")
            try:
                # Handle 'Z' suffix in ISO strings
                dt_str = arg.replace("Z", "+00:00") if arg.endswith("Z") else arg
                dt = datetime.fromisoformat(dt_str)
                if dt.tzinfo is None:
                    dt = dt.replace(tzinfo=timezone.utc)
                return dt
            except Exception as e:
                raise QueryExecutionError(f"Invalid ISO date string '{arg}': {e}") from e

        elif ctor_lower in ("uuid",):
            arg = self._parse_value()
            self._expect(TokenType.RPAREN, f"Expected ')' closing UUID().")
            if not isinstance(arg, str):
                raise QueryExecutionError(f"UUID() expects a valid UUID string, found {type(arg).__name__}.")
            try:
                return uuid.UUID(arg)
            except Exception as e:
                raise QueryExecutionError(f"Invalid UUID string '{arg}': {e}") from e

        elif ctor_lower in ("decimal128",):
            arg = self._parse_value()
            self._expect(TokenType.RPAREN, f"Expected ')' closing Decimal128().")
            if not isinstance(arg, (str, int, float, decimal.Decimal)):
                raise QueryExecutionError(f"Decimal128() expects a string or number, found {type(arg).__name__}.")
            try:
                return Decimal128(str(arg))
            except Exception as e:
                raise QueryExecutionError(f"Invalid Decimal128 value '{arg}': {e}") from e

        elif ctor_lower in ("timestamp",):
            # Timestamp(t, i) or Timestamp(t)
            t_arg = self._parse_value()
            i_arg = 1
            if self._match(TokenType.COMMA):
                i_arg = self._parse_value()
            self._expect(TokenType.RPAREN, "Expected ')' closing Timestamp().")
            try:
                return Timestamp(int(t_arg), int(i_arg))
            except Exception as e:
                raise QueryExecutionError(f"Invalid Timestamp({t_arg}, {i_arg}): {e}") from e

        else:
            raise QueryExecutionError(
                f"Unsupported MongoDB shell expression: Unsupported BSON constructor or function '{ctor_name}()'."
            )


def parse_mongodb_shell_query(query: str) -> tuple[str, dict[str, Any]]:
    """Parse a MongoDB Shell query string into a canonical operation string and parameter specification."""
    if not query or not query.strip():
        raise QueryExecutionError("Query cannot be empty.")

    lexer = MongoShellLexer(query)
    tokens = lexer.tokenize()
    parser = MongoShellParser(tokens, query)
    return parser.parse()
