"""Database migration runner for the internal Altr Stream SQLite metadata store."""

import logging
from sqlalchemy import inspect, text
from sqlalchemy.engine import Connection

logger = logging.getLogger(__name__)


def run_migrations(connection: Connection) -> None:
    """Apply automatic idempotent schema migrations to align existing tables with current models."""
    inspector = inspect(connection)
    tables = inspector.get_table_names()

    # Migration for 'sources' table (v0.5 -> v0.6 schema)
    if "sources" in tables:
        columns_info = {c["name"]: c for c in inspector.get_columns("sources")}
        has_file_path = "file_path" in columns_info
        host_is_not_null = columns_info.get("host", {}).get("nullable") is False

        # If file_path is missing or network fields are strictly NOT NULL (pre-v0.6 schema), upgrade table
        if not has_file_path or host_is_not_null:
            logger.info("Migrating 'sources' table to v0.6 schema (relaxing network constraints & adding file_path)...")

            # Disable foreign key checks during table reconstruction
            connection.execute(text("PRAGMA foreign_keys=OFF;"))

            # 1. Create temporary v0.6 table with updated nullability and file_path column
            connection.execute(
                text(
                    """
                    CREATE TABLE sources__v06 (
                        id VARCHAR(36) NOT NULL PRIMARY KEY,
                        name VARCHAR(255) NOT NULL,
                        type VARCHAR(50) NOT NULL,
                        host VARCHAR(255),
                        port INTEGER,
                        database_name VARCHAR(255),
                        username VARCHAR(255),
                        password VARCHAR(255),
                        file_path VARCHAR(1024),
                        status VARCHAR(50) NOT NULL DEFAULT 'UNKNOWN',
                        created_at DATETIME NOT NULL,
                        updated_at DATETIME NOT NULL
                    );
                    """
                )
            )

            # 2. Copy existing data
            common_cols = [
                col
                for col in [
                    "id",
                    "name",
                    "type",
                    "host",
                    "port",
                    "database_name",
                    "username",
                    "password",
                    "file_path",
                    "status",
                    "created_at",
                    "updated_at",
                ]
                if col in columns_info
            ]
            cols_str = ", ".join(common_cols)

            connection.execute(
                text(f"INSERT INTO sources__v06 ({cols_str}) SELECT {cols_str} FROM sources;")
            )

            # 3. Drop legacy table and rename temporary table
            connection.execute(text("DROP TABLE sources;"))
            connection.execute(text("ALTER TABLE sources__v06 RENAME TO sources;"))

            # 4. Re-create indexes
            connection.execute(text("CREATE UNIQUE INDEX IF NOT EXISTS ix_sources_name ON sources (name);"))

            # 5. Re-enable foreign keys
            connection.execute(text("PRAGMA foreign_keys=ON;"))

            logger.info("Successfully migrated 'sources' table to v0.6 schema.")

    # v0.7 Schema Migration: Verify Logical Model & Mapping Registry tables and indexes
    # (Base.metadata.create_all creates them, but we ensure proper indexes here idempotently)
    connection.execute(text("CREATE UNIQUE INDEX IF NOT EXISTS ix_logical_models_name ON logical_models (name);"))
    connection.execute(text("CREATE INDEX IF NOT EXISTS ix_logical_entities_model_id ON logical_entities (model_id);"))
    connection.execute(text("CREATE INDEX IF NOT EXISTS ix_logical_entities_name ON logical_entities (name);"))
    connection.execute(text("CREATE INDEX IF NOT EXISTS ix_logical_fields_entity_id ON logical_fields (entity_id);"))
    connection.execute(text("CREATE INDEX IF NOT EXISTS ix_source_mappings_logical_model_id ON source_mappings (logical_model_id);"))
    connection.execute(text("CREATE INDEX IF NOT EXISTS ix_source_mappings_source_id ON source_mappings (source_id);"))
    connection.execute(text("CREATE INDEX IF NOT EXISTS ix_entity_mappings_source_mapping_id ON entity_mappings (source_mapping_id);"))
    connection.execute(text("CREATE INDEX IF NOT EXISTS ix_entity_mappings_logical_entity_id ON entity_mappings (logical_entity_id);"))
    connection.execute(text("CREATE INDEX IF NOT EXISTS ix_field_mappings_entity_mapping_id ON field_mappings (entity_mapping_id);"))
    connection.execute(text("CREATE INDEX IF NOT EXISTS ix_field_mappings_logical_field_id ON field_mappings (logical_field_id);"))
