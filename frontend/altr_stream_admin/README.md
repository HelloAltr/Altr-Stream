# Altr Stream Admin — Flutter Web Application

Desktop-first administrative portal for managing physical data sources, connection lifecycle, and local schema introspection on an **Altr Stream** node.

## Features
- **Persistent Desktop Sidebar Navigation:** Overview, Data Sources, Activity, and Settings (`AppShell`).
- **Progressive Disclosure:** 3-tier data exposure model for source identity, connection parameters, and column-level introspection.
- **Guided Onboarding Wizard:** 4-step database connector configuration and connection validation (`AddSourceWizardDialog`).
- **Canonical Schema Introspection:** Deep schema explorer embedded inside Data Source details (`Data Sources → Select Source → Discovered Schemas`).
- **Live Node Telemetry:** Real-time health, latency, and status monitoring (`NodeStatusDialog`).

## Local Development
```bash
# Run locally targeting Chrome
flutter run -d chrome

# Run multi-viewport widget test suite
flutter test

# Compile release bundle for production
flutter build web --release
```
