"""Recursive descent parser for AltrQL v0.1 producing typed Intermediate Representation (IR)."""

from __future__ import annotations

from typing import List, NoReturn, Optional, Sequence, Union

from altr_stream.query_engine.domain.ast import (
    AltrQueryIR,
    BooleanLiteral,
    ComparisonConstraint,
    CompoundAndConstraint,
    Expression,
    FieldExpression,
    FieldPath,
    FieldSelection,
    FloatLiteral,
    IntegerLiteral,
    LiteralValue,
    LogicalExpression,
    MutationAssignment,
    NullLiteral,
    QueryOperation,
    Range,
    RankingClause,
    SortClause,
    StringLiteral,
    TemporalLiteral,
    ValueSet,
    ValueSetElement,
)
from altr_stream.query_engine.domain.errors import AltrQueryParseError
from altr_stream.query_engine.domain.operators import (
    ComparisonOperator,
    RankingDirection,
    SortDirection,
    StringOperator,
    TemporalKeyword,
)
from altr_stream.query_engine.parser.lexer import Lexer, RESERVED_KEYWORDS, Token, TokenType
from altr_stream.query_engine.semantic.normalizer import normalize_ir
from altr_stream.query_engine.semantic.validator import validate_ir


class Parser:
    """Parses a sequence of AltrQL tokens into a deterministic, typed AltrQueryIR."""

    def __init__(self, tokens: List[Token]) -> None:
        self.tokens = tokens
        self.cursor = 0

    # -----------------------------------------------------------------------
    # Helper Inspection & Consumption Methods
    # -----------------------------------------------------------------------

    def _peek(self, offset: int = 0) -> Token:
        pos = self.cursor + offset
        if pos >= len(self.tokens):
            return self.tokens[-1]  # EOF token
        return self.tokens[pos]

    def _is_at_end(self) -> bool:
        return self._peek().type == TokenType.EOF

    def _check(self, token_type: TokenType) -> bool:
        if self._is_at_end():
            return token_type == TokenType.EOF
        return self._peek().type == token_type

    def _advance(self) -> Token:
        if not self._is_at_end():
            self.cursor += 1
        return self.tokens[self.cursor - 1]

    def _match(self, *token_types: TokenType) -> bool:
        for t in token_types:
            if self._check(t):
                self._advance()
                return True
        return False

    def _error(
        self,
        message: str,
        token: Optional[Token] = None,
        expected: Optional[Sequence[str]] = None,
    ) -> NoReturn:
        tok = token if token is not None else self._peek()
        # If user typed a lowercase/mixed-case keyword, give an explicit suggestion
        if tok.type == TokenType.IDENTIFIER and tok.lexeme.upper() in RESERVED_KEYWORDS:
            kw = tok.lexeme.upper()
            msg = f"Unexpected identifier '{tok.lexeme}' (keywords must be strictly uppercase: '{kw}')"
            raise AltrQueryParseError(
                message=msg,
                line=tok.line,
                column=tok.column,
                unexpected_token=tok.lexeme,
                expected_tokens=expected,
            )

        raise AltrQueryParseError(
            message=message,
            line=tok.line,
            column=tok.column,
            unexpected_token=tok.lexeme if tok.type != TokenType.EOF else "EOF",
            expected_tokens=expected,
        )

    def _consume(self, token_type: TokenType, message: str, expected: Optional[Sequence[str]] = None) -> Token:
        if self._check(token_type):
            return self._advance()
        self._error(message, expected=expected or [token_type.name])

    def _consume_terminating_semicolon(self) -> None:
        """Verify mandatory semicolon at the end of every statement and ensure EOF."""
        if not self._match(TokenType.SEMICOLON):
            self._error("Expected ';' at end of query.", expected=[";"])
        if not self._is_at_end():
            self._error("Unexpected tokens after query terminating ';'.")

    # -----------------------------------------------------------------------
    # Root Entry Point
    # -----------------------------------------------------------------------

    def parse(self) -> AltrQueryIR:
        """Parse complete query string (GET, CREATE, UPDATE, DELETE) and verify mandatory semicolon."""
        if self._match(TokenType.GET):
            return self._parse_get()
        if self._match(TokenType.CREATE):
            return self._parse_create()
        if self._match(TokenType.UPDATE):
            return self._parse_update()
        if self._match(TokenType.DELETE):
            return self._parse_delete()

        self._error(
            "Expected 'GET', 'CREATE', 'UPDATE', or 'DELETE' keyword at beginning of query.",
            expected=["GET", "CREATE", "UPDATE", "DELETE"],
        )

    def _parse_get(self) -> AltrQueryIR:
        # 1. Require Entity Identifier
        if not self._check(TokenType.IDENTIFIER):
            self._error("Expected entity name after 'GET'.", expected=["IDENTIFIER"])
        entity_token = self._advance()
        entity_name = entity_token.value

        # 2. Optional Projection List ( ... )
        projection: List[FieldSelection] = []
        if self._match(TokenType.LPAREN):
            projection = self._parse_projection_list()

        # 3. Optional WHERE { ... }
        where_clause: Optional[Expression] = None
        if self._match(TokenType.WHERE):
            where_clause = self._parse_where_block()

        # 4. Optional SORT or TOP/BOTTOM Ranking
        sort_clauses: List[SortClause] = []
        ranking_clause: Optional[RankingClause] = None

        has_sort = False
        has_ranking = False

        while self._check(TokenType.SORT) or self._check(TokenType.TOP) or self._check(TokenType.BOTTOM):
            if self._check(TokenType.SORT):
                if has_ranking:
                    self._error("Cannot combine 'SORT' with 'TOP'/'BOTTOM' ranking clause in AltrQL v0.1.")
                self._advance()
                sort_clauses = self._parse_sort_block()
                has_sort = True
            elif self._check(TokenType.TOP) or self._check(TokenType.BOTTOM):
                if has_sort:
                    self._error("Cannot combine 'SORT' with 'TOP'/'BOTTOM' ranking clause in AltrQL v0.1.")
                direction_token = self._advance()
                ranking_clause = self._parse_ranking_clause(direction_token)
                has_ranking = True

        # 5. Optional OFFSET n
        offset_val: Optional[int] = None
        if self._match(TokenType.OFFSET):
            if not self._check(TokenType.INTEGER):
                self._error("Expected integer value after 'OFFSET'.", expected=["INTEGER"])
            offset_token = self._advance()
            offset_val = offset_token.value

        # 6. Mandatory Semicolon & EOF
        self._consume_terminating_semicolon()

        return AltrQueryIR(
            operation=QueryOperation.READ,
            entity=entity_name,
            projection=projection,
            where=where_clause,
            sort=sort_clauses,
            ranking=ranking_clause,
            offset=offset_val,
        )

    def _parse_create(self) -> AltrQueryIR:
        # 1. Require Entity Identifier
        if not self._check(TokenType.IDENTIFIER):
            self._error("Expected entity name after 'CREATE'.", expected=["IDENTIFIER"])
        entity_token = self._advance()
        entity_name = entity_token.value

        # 2. Require Mutation Payload ( field: value, ... )
        if not self._check(TokenType.LPAREN):
            self._error(f"Expected '(' starting mutation payload after entity '{entity_name}'.", expected=["("])
        assignments = self._parse_mutation_payload()

        # 3. Disallowed clauses on CREATE
        if self._check(TokenType.WHERE):
            self._error("WHERE clause is not supported on 'CREATE' operations.")
        if self._check(TokenType.SORT) or self._check(TokenType.TOP) or self._check(TokenType.BOTTOM):
            self._error("SORT / ranking clauses are not supported on 'CREATE' operations.")
        if self._check(TokenType.OFFSET):
            self._error("OFFSET clause is not supported on 'CREATE' operations.")

        # 4. Mandatory Semicolon & EOF
        self._consume_terminating_semicolon()

        return AltrQueryIR(
            operation=QueryOperation.CREATE,
            entity=entity_name,
            assignments=assignments,
        )

    def _parse_update(self) -> AltrQueryIR:
        # 1. Require Entity Identifier
        if not self._check(TokenType.IDENTIFIER):
            self._error("Expected entity name after 'UPDATE'.", expected=["IDENTIFIER"])
        entity_token = self._advance()
        entity_name = entity_token.value

        # 2. Require Mutation Payload ( field: value, ... )
        if not self._check(TokenType.LPAREN):
            self._error(f"Expected '(' starting mutation payload after entity '{entity_name}'.", expected=["("])
        assignments = self._parse_mutation_payload()

        # 3. Optional WHERE Clause
        where_clause: Optional[Expression] = None
        if self._match(TokenType.WHERE):
            where_clause = self._parse_where_block()

        # 4. Disallowed clauses on UPDATE
        if self._check(TokenType.SORT) or self._check(TokenType.TOP) or self._check(TokenType.BOTTOM):
            self._error("SORT / ranking clauses are not supported on 'UPDATE' operations.")
        if self._check(TokenType.OFFSET):
            self._error("OFFSET clause is not supported on 'UPDATE' operations.")

        # 5. Mandatory Semicolon & EOF
        self._consume_terminating_semicolon()

        return AltrQueryIR(
            operation=QueryOperation.UPDATE,
            entity=entity_name,
            assignments=assignments,
            where=where_clause,
        )

    def _parse_delete(self) -> AltrQueryIR:
        # 1. Require Entity Identifier
        if not self._check(TokenType.IDENTIFIER):
            self._error("Expected entity name after 'DELETE'.", expected=["IDENTIFIER"])
        entity_token = self._advance()
        entity_name = entity_token.value

        # 2. Reject mutation payload on DELETE
        if self._check(TokenType.LPAREN):
            self._error("Mutation assignment payloads are not supported on 'DELETE' operations.")

        # 3. Optional WHERE Clause
        where_clause: Optional[Expression] = None
        if self._match(TokenType.WHERE):
            where_clause = self._parse_where_block()

        # 4. Disallowed clauses on DELETE
        if self._check(TokenType.SORT) or self._check(TokenType.TOP) or self._check(TokenType.BOTTOM):
            self._error("SORT / ranking clauses are not supported on 'DELETE' operations.")
        if self._check(TokenType.OFFSET):
            self._error("OFFSET clause is not supported on 'DELETE' operations.")

        # 5. Mandatory Semicolon & EOF
        self._consume_terminating_semicolon()

        return AltrQueryIR(
            operation=QueryOperation.DELETE,
            entity=entity_name,
            where=where_clause,
        )

    def _parse_mutation_payload(self) -> List[MutationAssignment]:
        """Parse mutation assignment payload enclosed in parentheses: ( field: value, ... )."""
        self._consume(TokenType.LPAREN, "Expected '(' starting mutation payload.", expected=["("])
        assignments: List[MutationAssignment] = []

        if self._check(TokenType.RPAREN):
            self._error("Mutation payload cannot be empty.", expected=["field assignment"])

        seen_fields: set[str] = set()

        while not self._check(TokenType.RPAREN) and not self._is_at_end():
            field = self._parse_field_path()
            if field.full_path in seen_fields:
                self._error(f"Duplicate assignment for field '{field.full_path}' in mutation payload.")
            seen_fields.add(field.full_path)

            self._consume(TokenType.COLON, f"Expected ':' after field '{field.full_path}' in mutation assignment.", expected=[":"])
            value = self._parse_literal()

            assignments.append(MutationAssignment(field=field, value=value))

            if self._match(TokenType.COMMA):
                if self._check(TokenType.RPAREN):
                    self._error("Unexpected trailing comma in mutation payload.")
                continue
            elif self._check(TokenType.RPAREN):
                break
            else:
                self._error("Expected ',' or ')' in mutation payload.", expected=[",", ")"])

        self._consume(TokenType.RPAREN, "Expected ')' closing mutation payload.", expected=[")"])
        return assignments


    # -----------------------------------------------------------------------
    # Projection Parsing
    # -----------------------------------------------------------------------

    def _parse_projection_list(self) -> List[FieldSelection]:
        selections: List[FieldSelection] = []

        if self._match(TokenType.RPAREN):
            return selections

        while True:
            field_path = self._parse_field_path()
            alias: Optional[str] = None
            if self._match(TokenType.AS):
                if not self._check(TokenType.IDENTIFIER):
                    self._error("Expected alias identifier after 'AS'.", expected=["IDENTIFIER"])
                alias_tok = self._advance()
                alias = alias_tok.value

            selections.append(FieldSelection(path=field_path, alias=alias))

            if self._match(TokenType.COMMA):
                # Disallow trailing comma before closing parenthesis e.g. (id, name,)
                if self._check(TokenType.RPAREN):
                    self._error("Unexpected trailing comma in projection list.")
                continue
            elif self._match(TokenType.RPAREN):
                break
            else:
                self._error("Expected ',' or ')' in projection list.", expected=[",", ")"])

        return selections

    def _parse_field_path(self) -> FieldPath:
        if not self._check(TokenType.IDENTIFIER):
            self._error("Expected field name.", expected=["IDENTIFIER"])

        segments: List[str] = [self._advance().value]
        while self._match(TokenType.DOT):
            if not self._check(TokenType.IDENTIFIER):
                self._error("Expected field segment after '.'.", expected=["IDENTIFIER"])
            segments.append(self._advance().value)

        return FieldPath(segments=segments)

    # -----------------------------------------------------------------------
    # WHERE Block Parsing
    # -----------------------------------------------------------------------

    def _parse_where_block(self) -> Expression:
        self._consume(TokenType.LBRACE, "Expected '{' after 'WHERE'.", expected=["{"])

        if self._check(TokenType.RBRACE):
            self._error("WHERE block cannot be empty.", expected=["expression"])

        entries: List[Expression] = []

        while not self._check(TokenType.RBRACE) and not self._is_at_end():
            or_expr = self._parse_or_expression()
            entries.append(or_expr)

            if self._match(TokenType.COMMA):
                if self._check(TokenType.RBRACE):
                    # Cleanly allow or reject trailing comma? Let's disallow trailing comma inside WHERE
                    break
                continue
            elif self._check(TokenType.RBRACE):
                break
            else:
                self._error("Expected ',' or '}' after expression in WHERE block.", expected=[",", "}"])

        self._consume(TokenType.RBRACE, "Expected '}' closing WHERE block.", expected=["}"])

        if len(entries) == 1:
            return entries[0]
        return LogicalExpression(operator="AND", operands=entries)

    def _parse_or_expression(self) -> Expression:
        first = self._parse_atomic_field_expression()
        if not self._match(TokenType.OR):
            return first

        or_operands: List[Expression] = [first]
        while True:
            next_expr = self._parse_atomic_field_expression()
            or_operands.append(next_expr)
            if not self._match(TokenType.OR):
                break

        return LogicalExpression(operator="OR", operands=or_operands)

    def _parse_atomic_field_expression(self) -> FieldExpression:
        field = self._parse_field_path()
        op, operand = self._parse_operator_and_operand()
        return FieldExpression(field=field, operator=op, operand=operand)

    def _parse_operator_and_operand(self) -> tuple[Union[ComparisonOperator, StringOperator], Union[LiteralValue, ValueSet, Range]]:
        # 1. String Operators: STARTS, ENDS, HAS, NOT HAS
        if self._match(TokenType.STARTS):
            val = self._parse_string_literal()
            return StringOperator.STARTS, val

        if self._match(TokenType.ENDS):
            val = self._parse_string_literal()
            return StringOperator.ENDS, val

        if self._match(TokenType.HAS):
            val = self._parse_string_literal()
            return StringOperator.HAS, val

        if self._match(TokenType.NOT):
            self._consume(TokenType.HAS, "Expected 'HAS' after 'NOT'.", expected=["HAS"])
            val = self._parse_string_literal()
            return StringOperator.NOT_HAS, val

        # 2. Comparison Operators: =, !=, >, <, >=, <=
        comp_map = {
            TokenType.EQ: ComparisonOperator.EQ,
            TokenType.NEQ: ComparisonOperator.NEQ,
            TokenType.GT: ComparisonOperator.GT,
            TokenType.LT: ComparisonOperator.LT,
            TokenType.GTE: ComparisonOperator.GTE,
            TokenType.LTE: ComparisonOperator.LTE,
        }

        matched_op: Optional[ComparisonOperator] = None
        for tok_t, cop in comp_map.items():
            if self._match(tok_t):
                matched_op = cop
                break

        if matched_op is None:
            self._error(
                "Expected operator (=, !=, >, <, >=, <=, STARTS, ENDS, HAS, NOT HAS) after field.",
                expected=["=", "!=", ">", "<", ">=", "<=", "STARTS", "ENDS", "HAS", "NOT HAS"],
            )

        # 3. Parse Operand: ValueSet { ... }, or Literal
        if self._match(TokenType.LBRACE):
            value_set = self._parse_value_set()
            return matched_op, value_set

        literal = self._parse_literal_or_range()
        return matched_op, literal

    # -----------------------------------------------------------------------
    # Value Set Parsing: { ... }
    # -----------------------------------------------------------------------

    def _parse_value_set(self) -> ValueSet:
        elements: List[ValueSetElement] = []

        if self._check(TokenType.RBRACE):
            self._error("Value set '{ }' cannot be empty.", expected=["value, range, or comparison constraint"])

        while not self._check(TokenType.RBRACE) and not self._is_at_end():
            element = self._parse_value_set_element()
            elements.append(element)

            if self._match(TokenType.COMMA):
                if self._check(TokenType.RBRACE):
                    break
                continue
            elif self._check(TokenType.RBRACE):
                break
            else:
                self._error("Expected ',' or '}' in value set.", expected=[",", "}"])

        self._consume(TokenType.RBRACE, "Expected '}' closing value set.", expected=["}"])
        return ValueSet(elements=elements)

    def _parse_value_set_element(self) -> ValueSetElement:
        # Check for comparison constraint: e.g. >18 or >=18 & <=30
        if self._is_comparison_token(self._peek().type):
            first_constraint = self._parse_comparison_constraint()
            if self._match(TokenType.AMPERSAND):
                constraints: List[ComparisonConstraint] = [first_constraint]
                while True:
                    if not self._is_comparison_token(self._peek().type):
                        self._error("Expected comparison constraint after '&'.", expected=[">", "<", ">=", "<="])
                    constraints.append(self._parse_comparison_constraint())
                    if not self._match(TokenType.AMPERSAND):
                        break
                return CompoundAndConstraint(constraints=constraints)
            return first_constraint

        # Parse literal or range: e.g. 1, "ACTIVE", 6..10
        first_lit = self._parse_literal()
        if self._match(TokenType.DOTDOT):
            second_lit = self._parse_literal()
            return Range(start=first_lit, end=second_lit, inclusive=True)

        return first_lit

    def _is_comparison_token(self, t: TokenType) -> bool:
        return t in (TokenType.GT, TokenType.LT, TokenType.GTE, TokenType.LTE, TokenType.EQ, TokenType.NEQ)

    def _parse_comparison_constraint(self) -> ComparisonConstraint:
        tok = self._advance()
        op_map = {
            TokenType.GT: ComparisonOperator.GT,
            TokenType.LT: ComparisonOperator.LT,
            TokenType.GTE: ComparisonOperator.GTE,
            TokenType.LTE: ComparisonOperator.LTE,
            TokenType.EQ: ComparisonOperator.EQ,
            TokenType.NEQ: ComparisonOperator.NEQ,
        }
        op = op_map[tok.type]
        lit = self._parse_literal()
        return ComparisonConstraint(operator=op, value=lit)

    # -----------------------------------------------------------------------
    # Literals and Ranges
    # -----------------------------------------------------------------------

    def _parse_literal_or_range(self) -> Union[LiteralValue, Range]:
        lit = self._parse_literal()
        if self._match(TokenType.DOTDOT):
            end_lit = self._parse_literal()
            return Range(start=lit, end=end_lit, inclusive=True)
        return lit

    def _parse_literal(self) -> LiteralValue:
        tok = self._peek()

        if self._match(TokenType.STRING):
            return StringLiteral(value=tok.value)

        if self._match(TokenType.INTEGER):
            return IntegerLiteral(value=tok.value)

        if self._match(TokenType.FLOAT):
            return FloatLiteral(value=tok.value)

        if self._match(TokenType.TRUE):
            return BooleanLiteral(value=True)

        if self._match(TokenType.FALSE):
            return BooleanLiteral(value=False)

        if self._match(TokenType.NULL):
            return NullLiteral()

        if self._match(TokenType.TODAY):
            return TemporalLiteral(keyword=TemporalKeyword.TODAY)

        if self._match(TokenType.NOW):
            return TemporalLiteral(keyword=TemporalKeyword.NOW)

        if self._match(TokenType.TEMPORAL_LITERAL):
            return TemporalLiteral(value=tok.value)

        self._error(
            f"Expected literal value (string, integer, float, TRUE, FALSE, NULL, TODAY, NOW, or @YYYY-MM-DD), got '{tok.lexeme}'.",
            expected=["STRING", "INTEGER", "FLOAT", "TRUE", "FALSE", "NULL", "TODAY", "NOW", "TEMPORAL_LITERAL"],
        )

    def _parse_string_literal(self) -> StringLiteral:
        if not self._check(TokenType.STRING):
            self._error("Expected string literal in quotes.", expected=["STRING"])
        return StringLiteral(value=self._advance().value)

    # -----------------------------------------------------------------------
    # Sorting & Ranking Parsing
    # -----------------------------------------------------------------------

    def _parse_sort_block(self) -> List[SortClause]:
        self._consume(TokenType.LBRACE, "Expected '{' after 'SORT'.", expected=["{"])
        clauses: List[SortClause] = []

        if self._check(TokenType.RBRACE):
            self._error("SORT block cannot be empty.", expected=["field sorting clause"])

        while not self._check(TokenType.RBRACE) and not self._is_at_end():
            field = self._parse_field_path()
            direction = SortDirection.ASC
            if self._match(TokenType.ASC):
                direction = SortDirection.ASC
            elif self._match(TokenType.DESC):
                direction = SortDirection.DESC
            else:
                self._error("Expected 'ASC' or 'DESC' sort direction.", expected=["ASC", "DESC"])

            clauses.append(SortClause(field=field, direction=direction))

            if self._match(TokenType.COMMA):
                if self._check(TokenType.RBRACE):
                    break
                continue
            elif self._check(TokenType.RBRACE):
                break
            else:
                self._error("Expected ',' or '}' in SORT block.", expected=[",", "}"])

        self._consume(TokenType.RBRACE, "Expected '}' closing SORT block.", expected=["}"])
        return clauses

    def _parse_ranking_clause(self, direction_token: Token) -> RankingClause:
        direction = RankingDirection.TOP if direction_token.type == TokenType.TOP else RankingDirection.BOTTOM

        if not self._check(TokenType.INTEGER):
            self._error(f"Expected count integer after '{direction.value}'.", expected=["INTEGER"])
        count = self._advance().value

        self._consume(TokenType.BY, f"Expected 'BY' after count in {direction.value} clause.", expected=["BY"])
        field = self._parse_field_path()

        return RankingClause(direction=direction, count=count, field=field)


def parse_altrql(query_text: str) -> AltrQueryIR:
    """Convenience function: Tokenize, parse, validate, and normalize AltrQL text into a canonical AltrQueryIR."""
    lexer = Lexer(query_text)
    tokens = lexer.tokenize()
    parser = Parser(tokens)
    raw_ir = parser.parse()
    validate_ir(raw_ir)
    normalized_ir = normalize_ir(raw_ir)
    validate_ir(normalized_ir)
    return normalized_ir

