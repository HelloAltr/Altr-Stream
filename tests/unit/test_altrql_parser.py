"""Comprehensive test suite for AltrQL v0.1 Lexer, Parser, and AST / IR domain models."""

import pytest

from altr_stream.query_engine import (
    AltrQueryError,
    AltrQueryIR,
    AltrQueryLexError,
    AltrQueryParseError,
    BooleanLiteral,
    ComparisonConstraint,
    ComparisonOperator,
    CompoundAndConstraint,
    FieldExpression,
    FieldPath,
    FieldSelection,
    FloatLiteral,
    IntegerLiteral,
    LogicalExpression,
    LogicalOperator,
    NullLiteral,
    Range,
    RankingClause,
    RankingDirection,
    SortClause,
    SortDirection,
    StringLiteral,
    StringOperator,
    TemporalKeyword,
    TemporalLiteral,
    ValueSet,
    parse_altrql,
)


# ===========================================================================
# A. Basic Query Parsing & Mandatory Semicolon
# ===========================================================================


def test_basic_query_all_fields():
    ir = parse_altrql("GET users;")
    assert ir.entity == "users"
    assert ir.projection == []
    assert ir.is_wildcard_projection is True
    assert ir.where is None
    assert ir.sort == []
    assert ir.ranking is None
    assert ir.offset is None


def test_basic_query_with_projection():
    ir = parse_altrql("GET users(id, name);")
    assert ir.entity == "users"
    assert len(ir.projection) == 2
    assert ir.is_wildcard_projection is False
    assert ir.projection[0].path.segments == ["id"]
    assert ir.projection[1].path.segments == ["name"]


def test_missing_semicolon_raises_error():
    with pytest.raises(AltrQueryParseError) as exc_info:
        parse_altrql("GET users")
    assert "Expected ';'" in str(exc_info.value)


def test_missing_semicolon_after_where_raises_error():
    with pytest.raises(AltrQueryParseError) as exc_info:
        parse_altrql("GET users WHERE { status = \"ACTIVE\" }")
    assert "Expected ';'" in str(exc_info.value)


def test_trailing_tokens_after_semicolon_raises_error():
    with pytest.raises(AltrQueryParseError) as exc_info:
        parse_altrql("GET users; EXTRA")
    assert "Unexpected tokens after query terminating ';'" in str(exc_info.value)


# ===========================================================================
# B. Projection, Aliases & Nested Field Paths
# ===========================================================================


def test_projection_order_and_aliases():
    query = """
    GET users (
        id,
        name AS username,
        address.country,
        address.geo.lat AS latitude
    );
    """
    ir = parse_altrql(query)
    assert ir.entity == "users"
    assert len(ir.projection) == 4

    # 1. id
    assert ir.projection[0].path.segments == ["id"]
    assert ir.projection[0].alias is None
    assert ir.projection[0].path.full_path == "id"
    assert ir.projection[0].path.is_nested is False

    # 2. name AS username
    assert ir.projection[1].path.segments == ["name"]
    assert ir.projection[1].alias == "username"

    # 3. address.country
    assert ir.projection[2].path.segments == ["address", "country"]
    assert ir.projection[2].path.full_path == "address.country"
    assert ir.projection[2].path.root == "address"
    assert ir.projection[2].path.leaf == "country"
    assert ir.projection[2].path.is_nested is True
    assert ir.projection[2].alias is None

    # 4. address.geo.lat AS latitude
    assert ir.projection[3].path.segments == ["address", "geo", "lat"]
    assert ir.projection[3].alias == "latitude"


def test_projection_trailing_comma_fails():
    with pytest.raises(AltrQueryParseError) as exc_info:
        parse_altrql("GET users (id, name,);")
    assert "Unexpected trailing comma in projection list" in str(exc_info.value)


# ===========================================================================
# C. WHERE Clauses, Precedence & Boolean Operators
# ===========================================================================


def test_where_simple_equality():
    ir = parse_altrql('GET users WHERE { status = "ACTIVE" };')
    assert isinstance(ir.where, FieldExpression)
    assert ir.where.field.full_path == "status"
    assert ir.where.operator == ComparisonOperator.EQ
    assert isinstance(ir.where.operand, StringLiteral)
    assert ir.where.operand.value == "ACTIVE"


def test_where_implicit_and_with_commas():
    query = """
    GET users WHERE {
        age = 18,
        status = "ACTIVE",
        verified = TRUE
    };
    """
    ir = parse_altrql(query)
    assert isinstance(ir.where, LogicalExpression)
    assert ir.where.operator == "AND"

    # AND(AND(age=18, status="ACTIVE"), verified=TRUE)
    assert isinstance(ir.where.left, LogicalExpression)
    assert ir.where.left.left.field.full_path == "age"
    assert ir.where.left.left.operand.value == 18
    assert ir.where.left.right.field.full_path == "status"
    assert ir.where.left.right.operand.value == "ACTIVE"

    assert isinstance(ir.where.right, FieldExpression)
    assert ir.where.right.field.full_path == "verified"
    assert ir.where.right.operand.value is True


def test_where_explicit_or():
    query = 'GET users WHERE { age = 60 OR role = "ADMIN" };'
    ir = parse_altrql(query)
    assert isinstance(ir.where, LogicalExpression)
    assert ir.where.operator == "OR"
    assert ir.where.left.field.full_path == "age"
    assert ir.where.right.field.full_path == "role"


def test_where_precedence_or_within_comma_and():
    # 1. Without grouping: Comma (AND) has higher precedence than OR -> OR(a=18, AND(role="ADMIN", status="ACTIVE"))
    query = """
    GET users WHERE {
        age = 18 OR role = "ADMIN",
        status = "ACTIVE"
    };
    """
    ir = parse_altrql(query)
    assert isinstance(ir.where, LogicalExpression)
    assert ir.where.operator == LogicalOperator.OR
    assert ir.where.left.field.full_path == "age"

    right_and = ir.where.right
    assert isinstance(right_and, LogicalExpression)
    assert right_and.operator == LogicalOperator.AND
    assert right_and.left.field.full_path == "role"
    assert right_and.right.field.full_path == "status"

    # 2. With explicit { ... } grouping: overrides default precedence -> AND(OR(age=18, role="ADMIN"), status="ACTIVE")
    query_grouped = """
    GET users WHERE {
        { age = 18 OR role = "ADMIN" },
        status = "ACTIVE"
    };
    """
    ir_grouped = parse_altrql(query_grouped)
    assert isinstance(ir_grouped.where, LogicalExpression)
    assert ir_grouped.where.operator == LogicalOperator.AND

    group1 = ir_grouped.where.left
    assert isinstance(group1, LogicalExpression)
    assert group1.operator == LogicalOperator.OR
    assert group1.left.field.full_path == "age"
    assert group1.right.field.full_path == "role"

    group2 = ir_grouped.where.right
    assert isinstance(group2, FieldExpression)
    assert group2.field.full_path == "status"


def test_where_complex_multiple_or_groups():
    query = """
    GET users WHERE {
        { tier = "GOLD" OR tier = "PLATINUM" },
        { country = "US" OR country = "CA" },
        active = TRUE
    };
    """
    ir = parse_altrql(query)
    assert isinstance(ir.where, LogicalExpression)
    assert ir.where.operator == "AND"

    # AND(AND(group1, group2), active=TRUE)
    inner_and = ir.where.left
    assert isinstance(inner_and, LogicalExpression)
    assert inner_and.left.operator == "OR"
    assert inner_and.right.operator == "OR"
    assert ir.where.right.field.full_path == "active"


# ===========================================================================
# D. Value Sets & Conjunctions (& and ,)
# ===========================================================================


def test_value_set_discrete_or_alternatives():
    query = 'GET users WHERE { status = {"ACTIVE", "PENDING"} };'
    ir = parse_altrql(query)
    assert isinstance(ir.where, FieldExpression)
    assert ir.where.field.full_path == "status"
    assert isinstance(ir.where.operand, ValueSet)
    assert len(ir.where.operand.elements) == 2
    assert ir.where.operand.elements[0].value == "ACTIVE"
    assert ir.where.operand.elements[1].value == "PENDING"


def test_value_set_comparison_constraints():
    query = "GET users WHERE { age = {>18} };"
    ir = parse_altrql(query)
    assert isinstance(ir.where, FieldExpression)
    assert isinstance(ir.where.operand, ValueSet)
    assert len(ir.where.operand.elements) == 1
    constraint = ir.where.operand.elements[0]
    assert isinstance(constraint, ComparisonConstraint)
    assert constraint.operator == ComparisonOperator.GT
    assert constraint.value.value == 18


def test_value_set_compound_and_constraint():
    query = "GET users WHERE { age = {>=18 & <=30} };"
    ir = parse_altrql(query)
    assert isinstance(ir.where, FieldExpression)
    assert isinstance(ir.where.operand, ValueSet)
    assert len(ir.where.operand.elements) == 1

    compound = ir.where.operand.elements[0]
    assert isinstance(compound, CompoundAndConstraint)
    assert len(compound.constraints) == 2
    assert compound.constraints[0].operator == ComparisonOperator.GTE
    assert compound.constraints[0].value.value == 18
    assert compound.constraints[1].operator == ComparisonOperator.LTE
    assert compound.constraints[1].value.value == 30


def test_value_set_mixed_complex():
    query = "GET users WHERE { id = {1, 2, 6..10, >18 & <=25} };"
    ir = parse_altrql(query)
    assert isinstance(ir.where, FieldExpression)
    assert isinstance(ir.where.operand, ValueSet)
    elements = ir.where.operand.elements
    assert len(elements) == 4

    # 1. Integer 1
    assert isinstance(elements[0], IntegerLiteral)
    assert elements[0].value == 1

    # 2. Integer 2
    assert isinstance(elements[1], IntegerLiteral)
    assert elements[1].value == 2

    # 3. Range 6..10
    assert isinstance(elements[2], Range)
    assert elements[2].start.value == 6
    assert elements[2].end.value == 10
    assert elements[2].inclusive is True

    # 4. CompoundAndConstraint >18 & <=25
    assert isinstance(elements[3], CompoundAndConstraint)
    assert len(elements[3].constraints) == 2
    assert elements[3].constraints[0].operator == ComparisonOperator.GT
    assert elements[3].constraints[0].value.value == 18
    assert elements[3].constraints[1].operator == ComparisonOperator.LTE
    assert elements[3].constraints[1].value.value == 25


# ===========================================================================
# E. Ranges & Negated Ranges
# ===========================================================================


def test_range_in_value_set():
    query = "GET users WHERE { age = {18..30} };"
    ir = parse_altrql(query)
    assert isinstance(ir.where, FieldExpression)
    assert ir.where.operator == ComparisonOperator.EQ
    assert isinstance(ir.where.operand, ValueSet)
    assert isinstance(ir.where.operand.elements[0], Range)
    assert ir.where.operand.elements[0].start.value == 18
    assert ir.where.operand.elements[0].end.value == 30


def test_negated_range():
    query = "GET users WHERE { age != {18..30} };"
    ir = parse_altrql(query)
    assert isinstance(ir.where, FieldExpression)
    assert ir.where.operator == ComparisonOperator.NEQ
    assert isinstance(ir.where.operand, ValueSet)
    assert isinstance(ir.where.operand.elements[0], Range)


def test_direct_range_without_braces():
    query = "GET users WHERE { age = 18..30 };"
    ir = parse_altrql(query)
    assert isinstance(ir.where, FieldExpression)
    assert isinstance(ir.where.operand, Range)
    assert ir.where.operand.start.value == 18
    assert ir.where.operand.end.value == 30


# ===========================================================================
# F. String Operators (STARTS, ENDS, HAS, NOT HAS)
# ===========================================================================


def test_string_operators():
    query = """
    GET users WHERE {
        name STARTS "San",
        email ENDS "@helloaltr.com",
        description HAS "database",
        notes NOT HAS "spam"
    };
    """
    ir = parse_altrql(query)
    assert isinstance(ir.where, LogicalExpression)

    op4 = ir.where.right
    assert op4.operator == StringOperator.NOT_HAS
    assert op4.operand.value == "spam"

    and3 = ir.where.left
    op3 = and3.right
    assert op3.operator == StringOperator.HAS
    assert op3.operand.value == "database"

    and2 = and3.left
    op2 = and2.right
    assert op2.operator == StringOperator.ENDS
    assert op2.operand.value == "@helloaltr.com"

    op1 = and2.left
    assert op1.operator == StringOperator.STARTS
    assert op1.operand.value == "San"


# ===========================================================================
# G. Reserved Literals (TRUE, FALSE, NULL, TODAY, NOW)
# ===========================================================================


def test_reserved_literals():
    query = """
    GET events WHERE {
        verified = TRUE,
        deleted = FALSE,
        archived_at = NULL,
        created_at >= TODAY,
        updated_at <= NOW
    };
    """
    ir = parse_altrql(query)
    assert isinstance(ir.where, LogicalExpression)

    e5 = ir.where.right
    assert isinstance(e5.operand, TemporalLiteral)
    assert e5.operand.keyword == TemporalKeyword.NOW

    and4 = ir.where.left
    e4 = and4.right
    assert isinstance(e4.operand, TemporalLiteral)
    assert e4.operand.keyword == TemporalKeyword.TODAY

    and3 = and4.left
    e3 = and3.right
    assert isinstance(e3.operand, NullLiteral)

    and2 = and3.left
    e2 = and2.right
    assert isinstance(e2.operand, BooleanLiteral)
    assert e2.operand.value is False

    e1 = and2.left
    assert isinstance(e1.operand, BooleanLiteral)
    assert e1.operand.value is True


def test_float_and_escaped_string_literals():
    query = r'GET items WHERE { score = 98.75, note = "line1\nline2" };'
    ir = parse_altrql(query)
    assert isinstance(ir.where, LogicalExpression)
    assert isinstance(ir.where.left.operand, FloatLiteral)
    assert ir.where.left.operand.value == 98.75
    assert ir.where.right.operand.value == "line1\nline2"


# ===========================================================================
# H. Sorting, Ranking & Mutual Exclusion
# ===========================================================================


def test_sort_clause():
    query = """
    GET users SORT {
        id ASC,
        age DESC
    };
    """
    ir = parse_altrql(query)
    assert len(ir.sort) == 2
    assert ir.sort[0].field.full_path == "id"
    assert ir.sort[0].direction == SortDirection.ASC
    assert ir.sort[1].field.full_path == "age"
    assert ir.sort[1].direction == SortDirection.DESC


def test_top_ranking():
    query = 'GET users WHERE { status = "ACTIVE" } TOP 10 BY age;'
    ir = parse_altrql(query)
    assert ir.ranking is not None
    assert ir.ranking.direction == RankingDirection.TOP
    assert ir.ranking.count == 10
    assert ir.ranking.field.full_path == "age"


def test_bottom_ranking():
    query = "GET products BOTTOM 5 BY price;"
    ir = parse_altrql(query)
    assert ir.ranking is not None
    assert ir.ranking.direction == RankingDirection.BOTTOM
    assert ir.ranking.count == 5
    assert ir.ranking.field.full_path == "price"


def test_sort_and_ranking_mutual_exclusion():
    query1 = "GET users SORT { id ASC } TOP 10 BY age;"
    with pytest.raises(AltrQueryParseError) as exc_info1:
        parse_altrql(query1)
    assert "Cannot combine 'SORT' with 'TOP'/'BOTTOM'" in str(exc_info1.value)

    query2 = "GET users TOP 10 BY age SORT { id ASC };"
    with pytest.raises(AltrQueryParseError) as exc_info2:
        parse_altrql(query2)
    assert "Cannot combine 'SORT' with 'TOP'/'BOTTOM'" in str(exc_info2.value)


# ===========================================================================
# I. Pagination & Offset
# ===========================================================================


def test_offset_standalone():
    query = "GET users OFFSET 20;"
    ir = parse_altrql(query)
    assert ir.offset == 20


def test_offset_with_top():
    query = "GET users TOP 10 BY age OFFSET 20;"
    ir = parse_altrql(query)
    assert ir.ranking is not None
    assert ir.ranking.count == 10
    assert ir.ranking.field.full_path == "age"
    assert ir.offset == 20


# ===========================================================================
# J. Comments
# ===========================================================================


def test_comments_are_ignored():
    query = """
    // Retrieve active adult users
    GET users (
        id,
        name // user display name
    ) WHERE {
        // filter conditions
        age = {>18},
        status = "ACTIVE"
    };
    """
    ir = parse_altrql(query)
    assert ir.entity == "users"
    assert len(ir.projection) == 2
    assert isinstance(ir.where, LogicalExpression)


# ===========================================================================
# K. Case Sensitivity Enforcement
# ===========================================================================


@pytest.mark.parametrize(
    "invalid_query,expected_err",
    [
        ("get users;", "Unexpected identifier 'get'"),
        ("Get users;", "Unexpected identifier 'Get'"),
        ('GET users where { status = "ACTIVE" };', "Unexpected identifier 'where'"),
        ("GET users WHERE { verified = true };", "Unexpected identifier 'true'"),
        ("GET users WHERE { verified = True };", "Unexpected identifier 'True'"),
        ("GET users WHERE { verified = false };", "Unexpected identifier 'false'"),
        ("GET users WHERE { deleted_at = null };", "Unexpected identifier 'null'"),
        ("GET users WHERE { created_at >= today };", "Unexpected identifier 'today'"),
        ("GET users WHERE { updated_at <= now };", "Unexpected identifier 'now'"),
        ("GET users sort { id asc };", "Unexpected identifier 'sort'"),
        ("GET users top 10 by age;", "Unexpected identifier 'top'"),
        ("GET users bottom 5 by price;", "Unexpected identifier 'bottom'"),
        ("GET users offset 20;", "Unexpected identifier 'offset'"),
    ],
)
def test_case_sensitivity_failures(invalid_query, expected_err):
    with pytest.raises(AltrQueryParseError) as exc_info:
        parse_altrql(invalid_query)
    assert expected_err in str(exc_info.value)


# ===========================================================================
# L. Invalid Syntax & Diagnostic Error Messages
# ===========================================================================


def test_missing_entity_fails():
    with pytest.raises(AltrQueryParseError) as exc_info:
        parse_altrql("GET;")
    assert "Expected entity name after 'GET'" in str(exc_info.value)


def test_empty_where_fails():
    with pytest.raises(AltrQueryParseError) as exc_info:
        parse_altrql("GET users WHERE {};")
    assert "WHERE block cannot be empty" in str(exc_info.value)


def test_incomplete_field_comparison_fails():
    with pytest.raises(AltrQueryParseError) as exc_info:
        parse_altrql("GET users WHERE { age = };")
    assert "Expected literal value" in str(exc_info.value) or "Expected" in str(exc_info.value)


def test_unclosed_value_set_fails():
    with pytest.raises(AltrQueryParseError) as exc_info:
        parse_altrql("GET users WHERE { age = {>18 };")
    assert "Expected" in str(exc_info.value)


def test_unterminated_string_fails():
    with pytest.raises(AltrQueryLexError) as exc_info:
        parse_altrql('GET users WHERE { name = "unclosed };')
    assert "Unterminated string literal" in str(exc_info.value)


# ===========================================================================
# M. AST Serialization / Roundtrip
# ===========================================================================


def test_ast_to_dict_serialization():
    query = """
    GET users (
        id,
        name AS username,
        address.country
    ) WHERE {
        age = {18..30},
        status = {"ACTIVE", "PENDING"}
    } SORT {
        id ASC
    } OFFSET 10;
    """
    ir = parse_altrql(query)
    ast_dict = ir.to_dict()

    assert isinstance(ast_dict, dict)
    assert ast_dict["entity"] == "users"
    assert len(ast_dict["projection"]) == 3
    assert ast_dict["projection"][1]["alias"] == "username"
    assert ast_dict["projection"][2]["path"]["segments"] == ["address", "country"]
    assert ast_dict["where"]["operator"] == "AND"
    assert ast_dict["sort"][0]["direction"] == "ASC"
    assert ast_dict["offset"] == 10

    # Test deserialization back into AltrQueryIR
    reloaded = AltrQueryIR.model_validate(ast_dict)
    assert reloaded == ir


# ===========================================================================
# N. Explicit Temporal ISO Date Literals (@YYYY-MM-DD)
# ===========================================================================


def test_explicit_iso_date_literal():
    query = "GET users WHERE { created_at = @2026-01-01 };"
    ir = parse_altrql(query)
    assert isinstance(ir.where, FieldExpression)
    assert isinstance(ir.where.operand, TemporalLiteral)
    assert ir.where.operand.value == "2026-01-01"
    assert ir.where.operand.keyword is None


def test_explicit_iso_date_leap_year_and_past():
    query = "GET events WHERE { ts1 = @2024-02-29, ts2 = @1999-12-31 };"
    ir = parse_altrql(query)
    assert isinstance(ir.where, LogicalExpression)
    assert isinstance(ir.where.left.operand, TemporalLiteral)
    assert ir.where.left.operand.value == "2024-02-29"
    assert isinstance(ir.where.right.operand, TemporalLiteral)
    assert ir.where.right.operand.value == "1999-12-31"


def test_explicit_iso_date_in_ranges_and_value_sets():
    query = """
    GET logs WHERE {
        created_at = {@2026-01-01..@2026-12-31},
        event_date = {@2026-01-01, @2026-06-01, TODAY}
    };
    """
    ir = parse_altrql(query)
    assert isinstance(ir.where, LogicalExpression)
    # Range element
    vs1 = ir.where.left.operand
    assert isinstance(vs1, ValueSet)
    assert isinstance(vs1.elements[0], Range)
    assert vs1.elements[0].start.value == "2026-01-01"
    assert vs1.elements[0].end.value == "2026-12-31"

    # Multi-element ValueSet with mixed ISO and keyword
    vs2 = ir.where.right.operand
    assert isinstance(vs2, ValueSet)
    assert len(vs2.elements) == 3
    assert vs2.elements[0].value == "2026-01-01"
    assert vs2.elements[1].value == "2026-06-01"
    assert vs2.elements[2].keyword == TemporalKeyword.TODAY


def test_explicit_iso_date_in_compound_constraints():
    query = "GET orders WHERE { order_date = {>=@2026-01-01 & <=@2026-12-31} };"
    ir = parse_altrql(query)
    vs = ir.where.operand
    assert isinstance(vs, ValueSet)
    assert isinstance(vs.elements[0], CompoundAndConstraint)
    assert vs.elements[0].constraints[0].value.value == "2026-01-01"
    assert vs.elements[0].constraints[1].value.value == "2026-12-31"


def test_quoted_date_remains_string_literal():
    query = 'GET users WHERE { created_at = "2026-01-01" };'
    ir = parse_altrql(query)
    assert isinstance(ir.where, FieldExpression)
    assert isinstance(ir.where.operand, StringLiteral)
    assert ir.where.operand.value == "2026-01-01"


@pytest.mark.parametrize(
    "invalid_temporal_query,expected_err",
    [
        ("GET users WHERE { created_at = @2026-1-1 };", "Malformed temporal literal '@2026-1-1'"),
        ("GET users WHERE { created_at = @hello };", "Malformed temporal literal '@hello'"),
        ("GET users WHERE { created_at = @2026-99-99 };", "Invalid calendar date"),
        ("GET users WHERE { created_at = @2026-02-30 };", "Invalid calendar date in temporal literal '@2026-02-30'"),
        ("GET users WHERE { created_at = @2025-02-29 };", "Invalid calendar date in temporal literal '@2025-02-29'"),
        ("GET users WHERE { created_at = @2026-13-01 };", "Invalid calendar date in temporal literal '@2026-13-01'"),
        ("GET users WHERE { created_at = @ };", "Malformed temporal literal '@'"),
    ],
)
def test_invalid_temporal_literals_fail_lexing(invalid_temporal_query, expected_err):
    with pytest.raises(AltrQueryLexError) as exc_info:
        parse_altrql(invalid_temporal_query)
    assert expected_err in str(exc_info.value)
