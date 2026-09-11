"""SQLAlchemy models for internal Altr Stream SQLite metadata store."""

from datetime import datetime, timezone
import uuid
from sqlalchemy import Boolean, DateTime, ForeignKey, Integer, String, Text
from sqlalchemy.orm import Mapped, mapped_column, relationship

from altr_stream.infrastructure.database.session import Base


class SourceModel(Base):
    """Registered external source metadata record."""

    __tablename__ = "sources"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    name: Mapped[str] = mapped_column(String(255), unique=True, nullable=False, index=True)
    type: Mapped[str] = mapped_column(String(50), nullable=False)
    host: Mapped[str | None] = mapped_column(String(255), nullable=True, default=None)
    port: Mapped[int | None] = mapped_column(Integer, nullable=True, default=None)
    database_name: Mapped[str | None] = mapped_column(String(255), nullable=True, default=None)
    username: Mapped[str | None] = mapped_column(String(255), nullable=True, default=None)
    password: Mapped[str | None] = mapped_column(String(255), nullable=True, default=None)
    file_path: Mapped[str | None] = mapped_column(String(1024), nullable=True, default=None)
    status: Mapped[str] = mapped_column(String(50), default="UNKNOWN", nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), nullable=False
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
        onupdate=lambda: datetime.now(timezone.utc),
        nullable=False,
    )

    schema_snapshots: Mapped[list["SchemaSnapshotModel"]] = relationship(
        "SchemaSnapshotModel",
        back_populates="source",
        cascade="all, delete-orphan",
        order_by="desc(SchemaSnapshotModel.discovered_at)",
    )


class SchemaSnapshotModel(Base):
    """Historical schema snapshot discovered for a source."""

    __tablename__ = "schema_snapshots"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    source_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("sources.id", ondelete="CASCADE"), nullable=False, index=True
    )
    version: Mapped[str] = mapped_column(String(50), default="1.0.0", nullable=False)
    schema_json: Mapped[str] = mapped_column(Text, nullable=False)
    discovered_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), nullable=False, index=True
    )

    source: Mapped[SourceModel] = relationship("SourceModel", back_populates="schema_snapshots")


class LogicalModelDB(Base):
    """Logical data model containing canonical entities."""

    __tablename__ = "logical_models"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    name: Mapped[str] = mapped_column(String(255), unique=True, nullable=False, index=True)
    version: Mapped[str] = mapped_column(String(50), default="1.0.0", nullable=False)
    description: Mapped[str | None] = mapped_column(Text, nullable=True, default=None)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), nullable=False
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
        onupdate=lambda: datetime.now(timezone.utc),
        nullable=False,
    )

    entities: Mapped[list["LogicalEntityDB"]] = relationship(
        "LogicalEntityDB",
        back_populates="model",
        cascade="all, delete-orphan",
        order_by="LogicalEntityDB.name",
    )
    source_mappings: Mapped[list["SourceMappingDB"]] = relationship(
        "SourceMappingDB",
        back_populates="logical_model",
        cascade="all, delete-orphan",
    )


class LogicalEntityDB(Base):
    """Logical entity within a logical model."""

    __tablename__ = "logical_entities"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    model_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("logical_models.id", ondelete="CASCADE"), nullable=False, index=True
    )
    name: Mapped[str] = mapped_column(String(255), nullable=False, index=True)
    description: Mapped[str | None] = mapped_column(Text, nullable=True, default=None)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), nullable=False
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
        onupdate=lambda: datetime.now(timezone.utc),
        nullable=False,
    )

    model: Mapped["LogicalModelDB"] = relationship("LogicalModelDB", back_populates="entities")
    fields: Mapped[list["LogicalFieldDB"]] = relationship(
        "LogicalFieldDB",
        back_populates="entity",
        cascade="all, delete-orphan",
        order_by="LogicalFieldDB.name",
    )


class LogicalFieldDB(Base):
    """Logical field attribute within a logical entity."""

    __tablename__ = "logical_fields"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    entity_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("logical_entities.id", ondelete="CASCADE"), nullable=False, index=True
    )
    name: Mapped[str] = mapped_column(String(255), nullable=False)
    data_type: Mapped[str] = mapped_column(String(50), default="STRING", nullable=False)
    is_primary_key: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    nullable: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), nullable=False
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
        onupdate=lambda: datetime.now(timezone.utc),
        nullable=False,
    )

    entity: Mapped["LogicalEntityDB"] = relationship("LogicalEntityDB", back_populates="fields")


class SourceMappingDB(Base):
    """Mapping binding between a logical model and a registered physical source."""

    __tablename__ = "source_mappings"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    logical_model_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("logical_models.id", ondelete="CASCADE"), nullable=False, index=True
    )
    source_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("sources.id", ondelete="CASCADE"), nullable=False, index=True
    )
    version: Mapped[str] = mapped_column(String(50), default="1.0.0", nullable=False)
    status: Mapped[str] = mapped_column(String(50), default="DRAFT", nullable=False)
    provenance: Mapped[str] = mapped_column(String(50), default="USER", nullable=False)
    error_message: Mapped[str | None] = mapped_column(Text, nullable=True, default=None)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), nullable=False
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
        onupdate=lambda: datetime.now(timezone.utc),
        nullable=False,
    )

    logical_model: Mapped["LogicalModelDB"] = relationship("LogicalModelDB", back_populates="source_mappings")
    source: Mapped["SourceModel"] = relationship("SourceModel")
    entity_mappings: Mapped[list["EntityMappingDB"]] = relationship(
        "EntityMappingDB",
        back_populates="source_mapping",
        cascade="all, delete-orphan",
    )


class EntityMappingDB(Base):
    """Entity-level mapping linking a logical entity to a physical table/view."""

    __tablename__ = "entity_mappings"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    source_mapping_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("source_mappings.id", ondelete="CASCADE"), nullable=False, index=True
    )
    logical_entity_id: Mapped[str] = mapped_column(String(36), nullable=False, index=True)
    logical_entity_name: Mapped[str] = mapped_column(String(255), nullable=False)
    physical_entity_name: Mapped[str] = mapped_column(String(255), nullable=False)
    physical_namespace: Mapped[str] = mapped_column(String(255), default="public", nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), nullable=False
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
        onupdate=lambda: datetime.now(timezone.utc),
        nullable=False,
    )

    source_mapping: Mapped["SourceMappingDB"] = relationship("SourceMappingDB", back_populates="entity_mappings")
    field_mappings: Mapped[list["FieldMappingDB"]] = relationship(
        "FieldMappingDB",
        back_populates="entity_mapping",
        cascade="all, delete-orphan",
    )


class FieldMappingDB(Base):
    """Field-level mapping linking a logical field to a physical column."""

    __tablename__ = "field_mappings"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    entity_mapping_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("entity_mappings.id", ondelete="CASCADE"), nullable=False, index=True
    )
    logical_field_id: Mapped[str] = mapped_column(String(36), nullable=False, index=True)
    logical_field_name: Mapped[str] = mapped_column(String(255), nullable=False)
    physical_field_name: Mapped[str] = mapped_column(String(255), nullable=False)
    transformation_rule: Mapped[str | None] = mapped_column(Text, nullable=True, default=None)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), nullable=False
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
        onupdate=lambda: datetime.now(timezone.utc),
        nullable=False,
    )

    entity_mapping: Mapped["EntityMappingDB"] = relationship("EntityMappingDB", back_populates="field_mappings")
