# Altr Stream Admin — Flutter Web Application

Desktop-first administrative portal for managing physical data sources (**PostgreSQL**, **MySQL**, **SQLite**, **MongoDB**), connection lifecycle, canonical schema catalog introspection, the **Logical Model & Source Mapping Registry**, and the **AltrQL v0.7.6-alpha Query Engine & Compiler** on an **Altr Stream** node.

## Features

- **Persistent Desktop Sidebar Navigation:** Overview, Data Sources, Logical Models, Activity, and Settings (`AppShell`).
- **Logical Model & Source Mapping Registry:**
  - **Entity Modeling:** Define logical business models and strongly-typed fields.
  - **Physical Source Mappings:** Map logical models and fields to physical database tables/collections and columns/paths.
  - **Automated Validation Lifecycle:** Visual lifecycle badges (`DRAFT`, `VALIDATED`, `ACTIVE`, `ERROR`) and real-time schema compatibility validation.
- **Global AltrQL Console & Compiler Inspector (`/altrql`):**
  - **Interactive Editor & Templates:** Full support for AltrQL v0.7.6-alpha operations (`GET` with projection aliases and explicit `SORT` NULL parity, `CREATE` single/batch with consecutive grouping, `UPDATE` set-based with mandatory `WHERE`, `DELETE` constrained/mass, `NULL` equality/inequality & ValueSet substring matching).
  - **Mutation Badges & Safety Scoping:** Visual classification badges (`READ`, `CREATE`, `UPDATE`, `DELETE`, `BATCH`) and confirmation modals for mass mutations.
  - **Multi-View Inspection Tabs:**
    - **Results:** Interactive tabular rendering with execution latency (`X ms`) and affected/returned row count badges.
    - **Physical Query:** Dialect-specific generated SQL (Postgres, MySQL, SQLite) or MongoDB BSON operation pipeline with parameterized chips.
    - **Bound IR:** Monospace JSON view of the schema-bound AST with resolved physical column types.
    - **Canonical IR:** Monospace JSON view of the normalized language AST.
  - **Clipboard Actions:** Dedicated **"Copy Response"** and **"Copy Error"** clipboard buttons.
  - **Structured Error Diagnostics:** Line and column diagnostic badges with actionable compiler error messages.
- **Progressive Disclosure:** 3-tier data exposure model for source identity, connection parameters, and column-level introspection.
- **Guided Onboarding Wizard:** 4-step database connector configuration and connection validation (`AddSourceWizardDialog`).
- **Canonical Schema Introspection:** Deep schema explorer embedded inside Data Source details (`Data Sources → Select Source → Discovered Schemas`).
- **Source-Scoped Native Database Playground:**
  - **Relational Mode:** SQL query editor with table/column tree and query autocomplete helpers.
  - **Document Mode (MongoDB):** Native Mongo Shell query interface, collection tree, and BSON result viewer.
  - **Destructive Operation Safety:** Guardrail confirmation modal on `DROP`, `TRUNCATE`, `DELETE`, or `ALTER`.
- **Live Node Telemetry:** Real-time health, latency, and status monitoring (`NodeStatusDialog`).

## Local Development & Testing

```bash
# Fetch dependencies
flutter pub get

# Run locally targeting Chrome
flutter run -d chrome

# Run multi-viewport widget test suite (51 tests)
flutter test

# Run static analysis
flutter analyze

# Compile release bundle for production
flutter build web --release
```


