# Altr Stream Admin — Flutter Web Application

Desktop-first administrative portal for managing physical data sources, connection lifecycle, schema catalog introspection, and the **AltrQL v0.5 Query Engine & Compiler** on an **Altr Stream** node.

## Features

- **Persistent Desktop Sidebar Navigation:** Overview, Data Sources, Activity, and Settings (`AppShell`).
- **Global AltrQL Console & Compiler Inspector (`/altrql`):**
  - **Interactive Editor & Templates:** Full support for AltrQL v0.5 operations (`GET`, `CREATE` single/batch, `UPDATE` set-based, `DELETE` constrained/mass, `NULL` equality/inequality & ValueSets) with one-click templates and keyboard shortcut (`⌘ + Enter` / `Ctrl + Enter`).
  - **Mutation Badges & Safety Scoping:** Visual classification badges (`READ`, `CREATE`, `UPDATE`, `DELETE`, `BATCH`) and confirmation modals for mass mutations.
  - **Multi-View Inspection Tabs:**
    - **Results:** Interactive tabular rendering with latency (`X ms`) and affected/returned row count badges.
    - **Physical Query:** Dialect-specific generated SQL (e.g. PostgreSQL `FROM "public"."users"`) and 100% parameterized placeholder chips (`$1 = ...`), supporting multi-statement batch inspection.
    - **Bound IR:** Monospace JSON view of the schema-bound AST with resolved column types.
    - **Canonical IR:** Monospace JSON view of the normalized language AST.
  - **Structured Error Diagnostics:** Line and column diagnostic badges with dedicated error clipboard copying.
- **Progressive Disclosure:** 3-tier data exposure model for source identity, connection parameters, and column-level introspection.
- **Guided Onboarding Wizard:** 4-step database connector configuration and connection validation (`AddSourceWizardDialog`).
- **Canonical Schema Introspection:** Deep schema explorer embedded inside Data Source details (`Data Sources → Select Source → Discovered Schemas`).
- **Source-Scoped Native SQL Playground:** Interactive raw SQL playground with schema tree navigation, query autocomplete helpers, and destructive operation guardrails (`DROP`, `TRUNCATE`, `DELETE`, `ALTER`).
- **Live Node Telemetry:** Real-time health, latency, and status monitoring (`NodeStatusDialog`).

## Local Development & Testing

```bash
# Fetch dependencies
flutter pub get

# Run locally targeting Chrome
flutter run -d chrome

# Run multi-viewport widget test suite (25 tests)
flutter test

# Run static analysis
flutter analyze

# Compile release bundle for production
flutter build web --release
```

