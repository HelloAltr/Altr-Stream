# Altr Stream — REST API Reference

Altr Stream exposes a versioned REST API under `/api/v1`. All endpoints accept and return JSON payloads.

---

## 1. System Health

### `GET /api/v1/health`
Returns the operational health and version of the Altr Stream node.

**Response `200 OK`**:
```json
{
  "service": "Altr Stream",
  "version": "1.0.0-beta",
  "status": "healthy",
  "timestamp": "2026-09-25T12:00:00.000000"
}
```

---

## 2. Physical Sources

### `GET /api/v1/sources`
List all registered physical data sources.

### `POST /api/v1/sources`
Register a new physical database source.
**Request Body**:
```json
{
  "name": "Production PostgreSQL",
  "source_type": "postgresql",
  "host": "postgres-host",
  "port": 5432,
  "database": "analytics",
  "username": "altr_reader",
  "password": "secret_password",
  "options": {}
}
```

### `POST /api/v1/sources/{id}/test`
Test physical connectivity and credentials for a source.

### `POST /api/v1/sources/{id}/discover`
Trigger live schema introspection against the physical database.

### `GET /api/v1/sources/{id}/schema`
Retrieve the cached physical schema (tables/collections and columns/fields).

---

## 3. Logical Model & Mapping Registry

### `GET /api/v1/models`
List all abstract business entity models.

### `POST /api/v1/models`
Create a new logical model.
**Request Body**:
```json
{
  "name": "users",
  "description": "Canonical user profile entity",
  "fields": [
    {"name": "id", "data_type": "INTEGER", "is_primary_key": true, "is_nullable": false},
    {"name": "username", "data_type": "STRING", "is_primary_key": false, "is_nullable": false},
    {"name": "email", "data_type": "STRING", "is_primary_key": false, "is_nullable": true}
  ]
}
```

### `POST /api/v1/models/{id}/mappings`
Create an explicit field mapping binding a logical model to a physical table/collection.

---

## 4. AltrQL Federated Query Engine

### `POST /api/v1/altrql/parse`
Parse a raw AltrQL string and return the Canonical AST.

### `POST /api/v1/altrql/bind`
Validate AST against active schema models and type compatibility rules.

### `POST /api/v1/altrql/plan`
Produce physical query plans for participating candidate sources.

### `POST /api/v1/altrql/execute`
Execute an AltrQL query across target sources or Auto-Select.

**Request Body**:
```json
{
  "query": "GET users (id, username, email) WHERE { status = \"ACTIVE\" } TOP 10;",
  "target_source_id": null,
  "confirm_mass_mutation": false
}
```

**Response `200 OK`**:
```json
{
  "data": [
    {"id": 1, "username": "alice", "email": "alice@example.com"}
  ],
  "meta": {
    "execution_mode": "federated",
    "normalized": true,
    "is_ephemeral": false,
    "source_count": 1,
    "row_count": 1,
    "duration_ms": 12.4,
    "included_sources": [
      {
        "source_id": "src-uuid-1",
        "source_name": "Postgres Primary",
        "source_type": "postgresql",
        "status": "SUCCESS",
        "rows": 1,
        "execution_time_ms": 10.1
      }
    ],
    "excluded_sources": []
  }
}
```

---

## 5. Update & Distribution APIs

### `GET /api/v1/updates/check`
Check GitHub Releases for new updates matching the current channel (`alpha`, `beta`, `stable`).

### `GET /api/v1/updates/status`
Read current update state from the supervisor (`idle`, `staging`, `applying`, `verifying`, `success`, `failed`).

### `POST /api/v1/updates/apply`
Trigger an in-place update to a discovered release tag.

### `POST /api/v1/updates/retry`
Retry a failed update from the last stable state.

### `POST /api/v1/updates/cancel`
Cancel an update in `staging` state before container application begins.
