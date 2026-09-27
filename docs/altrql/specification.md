# AltrQL Language & Execution Specification

AltrQL is a declarative, database-neutral logical query and mutation language designed for multi-source data infrastructure in the Altr ecosystem.

---

## 1. Syntax & Supported Statements

### 1.1 `GET` (Retrieval)
```altrql
GET <entity_name> (
    <field_expr> [AS <alias>], ...
)
[WHERE { <predicate_tree> }]
[SORT { <sort_field> [ASC|DESC], ... }]
[TOP <limit>]
[OFFSET <offset>];
```

#### Predicates & Logical Operators
- **Equality & Inequality**: `field = "value"`, `field != 100`
- **Strict Two-Valued NULL Logic**:
  - `field = NULL` compiles to `"field" IS NULL` (SQL) / `{"field": None}` (MongoDB).
  - `field != NULL` compiles to `"field" IS NOT NULL` (SQL) / `{"field": {"$ne": None}}` (MongoDB).
  - `field != "val"` includes NULL rows: `("field" != $1 OR "field" IS NULL)`.
- **Value Sets**: `field = {1, 2, 3}`, `field HAS {"term1", "term2"}`
- **Pattern Matchers**:
  - `field STARTS "prefix"`
  - `field ENDS "suffix"`
  - `field HAS "substring"`
  - `field NOT HAS "substring"`
- **Temporal Comparators**:
  - Literal syntax: `@YYYY-MM-DD` or `@YYYY-MM-DDTHH:MM:SSZ`
  - Comparing a date-only literal against a timestamp column compiles to a half-open day range: `[00:00:00, 24:00:00)`.

#### Sort Order & NULL Parity
AltrQL enforces deterministic NULL ordering semantics across all underlying databases:
- `ASC`: NULL values are sorted **FIRST** (`ASC NULLS FIRST`).
- `DESC`: NULL values are sorted **LAST** (`DESC NULLS LAST`).

---

### 1.2 `CREATE` (Single & Batch Insertion)

#### Single Record Insertion
```altrql
CREATE users (
    username: "alice",
    email: "alice@example.com",
    metadata: NULL
);
```

#### Batch Insertion
```altrql
CREATE users (
    (username: "alice", email: "alice@example.com"),
    (username: "bob", email: "bob@example.com")
);
```
- **Explicit NULL vs Omission**:
  - Specifying `field: NULL` passes an explicit `NULL` to the underlying database. Non-nullable fields fail with `TypeCompatibilityError`.
  - Omitting a field excludes it from the `INSERT` column list, allowing database column defaults to apply.
- **Consecutive-Only Grouping**: Homogeneous adjacent records are grouped into multi-row inserts (`INSERT INTO ... VALUES (...)` or MongoDB `insert_many`). Heterogeneous record shapes are partitioned into consecutive batches, preserving logical order.
- **Transaction Safety**: Batch mutations execute inside an atomic transaction.

---

### 1.3 `UPDATE` (Mutations with Mandatory WHERE)
```altrql
UPDATE users (
    full_name: "Alice Updated",
    status: "ACTIVE"
) WHERE {
    email = "alice@example.com"
};
```
- **Safety Invariant**: Unbounded updates lacking a `WHERE` clause are rejected at parse time.
- **Nullability Enforcement**: Assigning `field: NULL` to non-nullable fields is caught and rejected during schema validation.

---

### 1.4 `DELETE` (Constrained vs Mass Mutations)

#### Constrained DELETE
```altrql
DELETE users WHERE { status = "INACTIVE" };
```

#### Mass DELETE (Full Table Truncation / Deletion)
```altrql
DELETE users;
```
- Executing an unconstrained `DELETE` requires explicit confirmation in the execution request: `confirm_mass_mutation=true`.
- If omitted, the API rejects the request with `MassMutationConfirmationRequiredError`.

---

## 2. Execution Telemetry & Response Schema

Every query submitted to `POST /api/v1/altrql/execute` produces a standardized response containing data rows and detailed source participation metadata:

```json
{
  "data": [
    {
      "id": 101,
      "username": "alice",
      "user_tier": "GOLD",
      "created_at": "2026-09-24T10:15:00Z"
    }
  ],
  "meta": {
    "execution_mode": "federated",
    "normalized": true,
    "is_ephemeral": false,
    "source_count": 2,
    "row_count": 1,
    "duration_ms": 14.8,
    "included_sources": [
      {
        "source_id": "postgres-prod",
        "source_name": "PostgreSQL Primary",
        "source_type": "postgresql",
        "status": "SUCCESS",
        "rows": 1,
        "execution_time_ms": 11.2
      }
    ],
    "excluded_sources": [
      {
        "source_id": "sqlite-edge",
        "source_name": "SQLite Local",
        "source_type": "sqlite",
        "status": "EXCLUDED",
        "reason_code": "PHYSICAL_ENTITY_NOT_FOUND",
        "message": "Physical entity 'users' not found in source schema"
      }
    ]
  }
}
```

### Deterministic Reason Codes
| Code | Description |
| :--- | :--- |
| `PHYSICAL_ENTITY_NOT_FOUND` | Target table or collection does not exist in the physical source catalog. |
| `NO_ACTIVE_MAPPING` | No active mapping exists in the Logical Model Registry for this source. |
| `INCOMPLETE_FIELD_MAPPING` | The source lacks one or more required projected fields. |
| `SOURCE_CAPABILITY_MISMATCH` | The source connector does not support requested operations (e.g. JSON extraction). |
| `SOURCE_UNREACHABLE` | Network timeout, socket error, or connection refusal. |
| `EXECUTION_FAILED` | Database returned a syntax, constraint, or execution error. |
| `EXECUTION_TIMEOUT` | Query exceeded the configured per-source execution timeout. |
| `NORMALIZATION_FAILED` | Internal error transforming physical rows into canonical logical records. |
