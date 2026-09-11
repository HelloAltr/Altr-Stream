"""SQLite repository for Logical Data Models and Mapping Registry."""

from datetime import datetime, timezone
from sqlalchemy import delete, func, select, update
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from altr_stream.domain.errors import (
    LogicalEntityNotFoundError,
    LogicalFieldNotFoundError,
    LogicalModelNotFoundError,
    SourceMappingNotFoundError,
)
from altr_stream.domain.logical import LogicalEntity, LogicalField, LogicalModel
from altr_stream.domain.mapping import (
    EntityMapping,
    FieldMapping,
    MappingProvenance,
    MappingStatus,
    SourceMapping,
)
from altr_stream.domain.schema import StandardDataType
from altr_stream.infrastructure.database.models import (
    EntityMappingDB,
    FieldMappingDB,
    LogicalEntityDB,
    LogicalFieldDB,
    LogicalModelDB,
    SourceMappingDB,
)


class SqliteRegistryRepository:
    """Repository handling persistence of Logical Models, Entities, Fields, and Mappings."""

    def __init__(self, session: AsyncSession):
        self.session = session

    # ==========================================
    # Domain Conversion Helpers
    # ==========================================

    def _field_to_domain(self, model: LogicalFieldDB) -> LogicalField:
        return LogicalField(
            id=model.id,
            logical_entity_id=model.entity_id,
            name=model.name,
            data_type=StandardDataType(model.data_type),
            is_primary_key=model.is_primary_key,
            nullable=model.nullable,
            created_at=model.created_at,
            updated_at=model.updated_at,
        )

    def _entity_to_domain(self, model: LogicalEntityDB) -> LogicalEntity:
        fields = [self._field_to_domain(f) for f in (model.fields or [])]
        return LogicalEntity(
            id=model.id,
            logical_model_id=model.model_id,
            name=model.name,
            description=model.description,
            fields=fields,
            created_at=model.created_at,
            updated_at=model.updated_at,
        )

    def _model_to_domain(self, model: LogicalModelDB) -> LogicalModel:
        entities = [self._entity_to_domain(e) for e in (model.entities or [])]
        return LogicalModel(
            id=model.id,
            name=model.name,
            version=model.version,
            description=model.description,
            entities=entities,
            created_at=model.created_at,
            updated_at=model.updated_at,
        )

    def _field_mapping_to_domain(self, model: FieldMappingDB) -> FieldMapping:
        return FieldMapping(
            id=model.id,
            entity_mapping_id=model.entity_mapping_id,
            logical_field_id=model.logical_field_id,
            logical_field_name=model.logical_field_name,
            physical_field_name=model.physical_field_name,
            transformation_rule=model.transformation_rule,
            created_at=model.created_at,
            updated_at=model.updated_at,
        )

    def _entity_mapping_to_domain(self, model: EntityMappingDB) -> EntityMapping:
        field_mappings = [self._field_mapping_to_domain(fm) for fm in (model.field_mappings or [])]
        return EntityMapping(
            id=model.id,
            source_mapping_id=model.source_mapping_id,
            logical_entity_id=model.logical_entity_id,
            logical_entity_name=model.logical_entity_name,
            physical_entity_name=model.physical_entity_name,
            physical_namespace=model.physical_namespace,
            field_mappings=field_mappings,
            created_at=model.created_at,
            updated_at=model.updated_at,
        )

    def _source_mapping_to_domain(self, model: SourceMappingDB) -> SourceMapping:
        entity_mappings = [self._entity_mapping_to_domain(em) for em in (model.entity_mappings or [])]
        return SourceMapping(
            id=model.id,
            logical_model_id=model.logical_model_id,
            source_id=model.source_id,
            version=model.version,
            status=MappingStatus(model.status),
            provenance=MappingProvenance(model.provenance),
            error_message=model.error_message,
            entity_mappings=entity_mappings,
            created_at=model.created_at,
            updated_at=model.updated_at,
        )

    # ==========================================
    # Logical Models
    # ==========================================

    async def create_model(self, model: LogicalModel) -> LogicalModel:
        """Persist a new logical model with nested entities and fields."""
        model_db = LogicalModelDB(
            id=model.id,
            name=model.name,
            version=model.version,
            description=model.description,
            created_at=model.created_at,
            updated_at=model.updated_at,
        )
        self.session.add(model_db)

        for entity in model.entities:
            entity_db = LogicalEntityDB(
                id=entity.id,
                model_id=model.id,
                name=entity.name,
                description=entity.description,
                created_at=entity.created_at,
                updated_at=entity.updated_at,
            )
            self.session.add(entity_db)

            for field in entity.fields:
                field_db = LogicalFieldDB(
                    id=field.id,
                    entity_id=entity.id,
                    name=field.name,
                    data_type=field.data_type.value,
                    is_primary_key=field.is_primary_key,
                    nullable=field.nullable,
                    created_at=field.created_at,
                    updated_at=field.updated_at,
                )
                self.session.add(field_db)

        await self.session.flush()
        return await self.get_model_by_id(model.id)  # type: ignore

    async def get_model_by_id(self, model_id: str) -> LogicalModel | None:
        """Retrieve a logical model with all eager-loaded entities and fields."""
        stmt = (
            select(LogicalModelDB)
            .where(LogicalModelDB.id == model_id)
            .options(
                selectinload(LogicalModelDB.entities).selectinload(LogicalEntityDB.fields)
            )
        )
        result = await self.session.execute(stmt)
        model_db = result.scalar_one_or_none()
        return self._model_to_domain(model_db) if model_db else None

    async def get_model_by_name(self, name: str) -> LogicalModel | None:
        """Retrieve a logical model by name."""
        stmt = (
            select(LogicalModelDB)
            .where(LogicalModelDB.name == name)
            .options(
                selectinload(LogicalModelDB.entities).selectinload(LogicalEntityDB.fields)
            )
        )
        result = await self.session.execute(stmt)
        model_db = result.scalar_one_or_none()
        return self._model_to_domain(model_db) if model_db else None

    async def list_models(self) -> list[LogicalModel]:
        """List all logical models ordered by updated_at desc."""
        stmt = (
            select(LogicalModelDB)
            .order_by(LogicalModelDB.updated_at.desc())
            .options(
                selectinload(LogicalModelDB.entities).selectinload(LogicalEntityDB.fields)
            )
        )
        result = await self.session.execute(stmt)
        models_db = result.scalars().all()
        return [self._model_to_domain(m) for m in models_db]

    async def update_model(self, model: LogicalModel) -> LogicalModel:
        """Update top-level logical model properties."""
        stmt = select(LogicalModelDB).where(LogicalModelDB.id == model.id)
        result = await self.session.execute(stmt)
        model_db = result.scalar_one_or_none()
        if not model_db:
            raise LogicalModelNotFoundError(model.id)

        model_db.name = model.name
        model_db.version = model.version
        model_db.description = model.description
        model_db.updated_at = datetime.now(timezone.utc)

        await self.session.flush()
        return await self.get_model_by_id(model.id)  # type: ignore

    async def delete_model(self, model_id: str) -> bool:
        """Delete a logical model and cascade-delete its entities, fields, and mappings."""
        stmt = delete(LogicalModelDB).where(LogicalModelDB.id == model_id)
        result = await self.session.execute(stmt)
        return result.rowcount > 0

    # ==========================================
    # Logical Entities
    # ==========================================

    async def add_entity(self, entity: LogicalEntity) -> LogicalEntity:
        """Add a single entity to a model."""
        entity_db = LogicalEntityDB(
            id=entity.id,
            model_id=entity.logical_model_id,
            name=entity.name,
            description=entity.description,
            created_at=entity.created_at,
            updated_at=entity.updated_at,
        )
        self.session.add(entity_db)

        for field in entity.fields:
            field_db = LogicalFieldDB(
                id=field.id,
                entity_id=entity.id,
                name=field.name,
                data_type=field.data_type.value,
                is_primary_key=field.is_primary_key,
                nullable=field.nullable,
                created_at=field.created_at,
                updated_at=field.updated_at,
            )
            self.session.add(field_db)

        # Update parent model updated_at
        await self.session.execute(
            update(LogicalModelDB)
            .where(LogicalModelDB.id == entity.logical_model_id)
            .values(updated_at=datetime.now(timezone.utc))
        )

        await self.session.flush()
        return await self.get_entity_by_id(entity.id)  # type: ignore

    async def get_entity_by_id(self, entity_id: str) -> LogicalEntity | None:
        """Retrieve a logical entity with its fields."""
        stmt = (
            select(LogicalEntityDB)
            .where(LogicalEntityDB.id == entity_id)
            .options(selectinload(LogicalEntityDB.fields))
        )
        result = await self.session.execute(stmt)
        entity_db = result.scalar_one_or_none()
        return self._entity_to_domain(entity_db) if entity_db else None

    async def update_entity(self, entity: LogicalEntity) -> LogicalEntity:
        """Update logical entity metadata."""
        stmt = select(LogicalEntityDB).where(LogicalEntityDB.id == entity.id)
        result = await self.session.execute(stmt)
        entity_db = result.scalar_one_or_none()
        if not entity_db:
            raise LogicalEntityNotFoundError(entity.id)

        entity_db.name = entity.name
        entity_db.description = entity.description
        entity_db.updated_at = datetime.now(timezone.utc)

        await self.session.execute(
            update(LogicalModelDB)
            .where(LogicalModelDB.id == entity_db.model_id)
            .values(updated_at=datetime.now(timezone.utc))
        )

        await self.session.flush()
        return await self.get_entity_by_id(entity.id)  # type: ignore

    async def delete_entity(self, entity_id: str) -> bool:
        """Delete a logical entity."""
        stmt = select(LogicalEntityDB).where(LogicalEntityDB.id == entity_id)
        result = await self.session.execute(stmt)
        entity_db = result.scalar_one_or_none()
        if not entity_db:
            return False

        model_id = entity_db.model_id
        await self.session.delete(entity_db)
        await self.session.execute(
            update(LogicalModelDB)
            .where(LogicalModelDB.id == model_id)
            .values(updated_at=datetime.now(timezone.utc))
        )
        await self.session.flush()
        return True

    # ==========================================
    # Logical Fields
    # ==========================================

    async def add_field(self, field: LogicalField) -> LogicalField:
        """Add a single field to an entity."""
        field_db = LogicalFieldDB(
            id=field.id,
            entity_id=field.logical_entity_id,
            name=field.name,
            data_type=field.data_type.value,
            is_primary_key=field.is_primary_key,
            nullable=field.nullable,
            created_at=field.created_at,
            updated_at=field.updated_at,
        )
        self.session.add(field_db)

        # Update parent entity and model timestamps
        stmt = select(LogicalEntityDB).where(LogicalEntityDB.id == field.logical_entity_id)
        res = await self.session.execute(stmt)
        entity_db = res.scalar_one_or_none()
        if entity_db:
            entity_db.updated_at = datetime.now(timezone.utc)
            await self.session.execute(
                update(LogicalModelDB)
                .where(LogicalModelDB.id == entity_db.model_id)
                .values(updated_at=datetime.now(timezone.utc))
            )

        await self.session.flush()
        return self._field_to_domain(field_db)

    async def get_field_by_id(self, field_id: str) -> LogicalField | None:
        """Retrieve a logical field by ID."""
        stmt = select(LogicalFieldDB).where(LogicalFieldDB.id == field_id)
        result = await self.session.execute(stmt)
        field_db = result.scalar_one_or_none()
        return self._field_to_domain(field_db) if field_db else None

    async def update_field(self, field: LogicalField) -> LogicalField:
        """Update field parameters."""
        stmt = select(LogicalFieldDB).where(LogicalFieldDB.id == field.id)
        result = await self.session.execute(stmt)
        field_db = result.scalar_one_or_none()
        if not field_db:
            raise LogicalFieldNotFoundError(field.id)

        field_db.name = field.name
        field_db.data_type = field.data_type.value
        field_db.is_primary_key = field.is_primary_key
        field_db.nullable = field.nullable
        field_db.updated_at = datetime.now(timezone.utc)

        await self.session.flush()
        return self._field_to_domain(field_db)

    async def delete_field(self, field_id: str) -> bool:
        """Delete a logical field."""
        stmt = delete(LogicalFieldDB).where(LogicalFieldDB.id == field_id)
        result = await self.session.execute(stmt)
        return result.rowcount > 0

    # ==========================================
    # Source Mappings
    # ==========================================

    async def create_source_mapping(self, mapping: SourceMapping) -> SourceMapping:
        """Persist a source mapping with nested entity and field mappings."""
        mapping_db = SourceMappingDB(
            id=mapping.id,
            logical_model_id=mapping.logical_model_id,
            source_id=mapping.source_id,
            version=mapping.version,
            status=mapping.status.value,
            provenance=mapping.provenance.value,
            error_message=mapping.error_message,
            created_at=mapping.created_at,
            updated_at=mapping.updated_at,
        )
        self.session.add(mapping_db)

        for em in mapping.entity_mappings:
            em_db = EntityMappingDB(
                id=em.id,
                source_mapping_id=mapping.id,
                logical_entity_id=em.logical_entity_id,
                logical_entity_name=em.logical_entity_name,
                physical_entity_name=em.physical_entity_name,
                physical_namespace=em.physical_namespace,
                created_at=em.created_at,
                updated_at=em.updated_at,
            )
            self.session.add(em_db)

            for fm in em.field_mappings:
                fm_db = FieldMappingDB(
                    id=fm.id,
                    entity_mapping_id=em.id,
                    logical_field_id=fm.logical_field_id,
                    logical_field_name=fm.logical_field_name,
                    physical_field_name=fm.physical_field_name,
                    transformation_rule=fm.transformation_rule,
                    created_at=fm.created_at,
                    updated_at=fm.updated_at,
                )
                self.session.add(fm_db)

        await self.session.flush()
        return await self.get_source_mapping_by_id(mapping.id)  # type: ignore

    async def get_source_mapping_by_id(self, mapping_id: str) -> SourceMapping | None:
        """Retrieve a source mapping with eager-loaded entity and field mappings."""
        stmt = (
            select(SourceMappingDB)
            .where(SourceMappingDB.id == mapping_id)
            .options(
                selectinload(SourceMappingDB.entity_mappings).selectinload(
                    EntityMappingDB.field_mappings
                )
            )
        )
        result = await self.session.execute(stmt)
        mapping_db = result.scalar_one_or_none()
        return self._source_mapping_to_domain(mapping_db) if mapping_db else None

    async def list_source_mappings(
        self,
        logical_model_id: str | None = None,
        source_id: str | None = None,
    ) -> list[SourceMapping]:
        """List source mappings with optional model/source filters."""
        stmt = (
            select(SourceMappingDB)
            .order_by(SourceMappingDB.updated_at.desc())
            .options(
                selectinload(SourceMappingDB.entity_mappings).selectinload(
                    EntityMappingDB.field_mappings
                )
            )
        )
        if logical_model_id:
            stmt = stmt.where(SourceMappingDB.logical_model_id == logical_model_id)
        if source_id:
            stmt = stmt.where(SourceMappingDB.source_id == source_id)

        result = await self.session.execute(stmt)
        mappings_db = result.scalars().all()
        return [self._source_mapping_to_domain(m) for m in mappings_db]

    async def update_source_mapping(self, mapping: SourceMapping, replace_entities: bool = False) -> SourceMapping:
        """Update source mapping status, version, error message, and optionally entity mappings."""
        stmt = select(SourceMappingDB).where(SourceMappingDB.id == mapping.id)
        result = await self.session.execute(stmt)
        mapping_db = result.scalar_one_or_none()
        if not mapping_db:
            raise SourceMappingNotFoundError(mapping.id)

        mapping_db.version = mapping.version
        mapping_db.status = mapping.status.value
        mapping_db.provenance = mapping.provenance.value
        mapping_db.error_message = mapping.error_message
        mapping_db.updated_at = datetime.now(timezone.utc)

        if replace_entities and mapping.entity_mappings is not None:
            # Delete old entity mappings
            await self.session.execute(
                delete(EntityMappingDB).where(EntityMappingDB.source_mapping_id == mapping.id)
            )
            await self.session.flush()

            for em in mapping.entity_mappings:
                em_db = EntityMappingDB(
                    id=em.id,
                    source_mapping_id=mapping.id,
                    logical_entity_id=em.logical_entity_id,
                    logical_entity_name=em.logical_entity_name,
                    physical_entity_name=em.physical_entity_name,
                    physical_namespace=em.physical_namespace,
                    created_at=em.created_at,
                    updated_at=em.updated_at,
                )
                self.session.add(em_db)

                for fm in em.field_mappings:
                    fm_db = FieldMappingDB(
                        id=fm.id,
                        entity_mapping_id=em.id,
                        logical_field_id=fm.logical_field_id,
                        logical_field_name=fm.logical_field_name,
                        physical_field_name=fm.physical_field_name,
                        transformation_rule=fm.transformation_rule,
                        created_at=fm.created_at,
                        updated_at=fm.updated_at,
                    )
                    self.session.add(fm_db)

        await self.session.flush()
        return await self.get_source_mapping_by_id(mapping.id)  # type: ignore

    async def delete_source_mapping(self, mapping_id: str) -> bool:
        """Delete a source mapping and cascade-delete all entity/field mappings."""
        stmt = delete(SourceMappingDB).where(SourceMappingDB.id == mapping_id)
        result = await self.session.execute(stmt)
        return result.rowcount > 0

    # ==========================================
    # Entity Mappings
    # ==========================================

    async def add_entity_mapping(self, entity_mapping: EntityMapping) -> EntityMapping:
        """Add an entity mapping with child field mappings."""
        em_db = EntityMappingDB(
            id=entity_mapping.id,
            source_mapping_id=entity_mapping.source_mapping_id,
            logical_entity_id=entity_mapping.logical_entity_id,
            logical_entity_name=entity_mapping.logical_entity_name,
            physical_entity_name=entity_mapping.physical_entity_name,
            physical_namespace=entity_mapping.physical_namespace,
            created_at=entity_mapping.created_at,
            updated_at=entity_mapping.updated_at,
        )
        self.session.add(em_db)

        for fm in entity_mapping.field_mappings:
            fm_db = FieldMappingDB(
                id=fm.id,
                entity_mapping_id=entity_mapping.id,
                logical_field_id=fm.logical_field_id,
                logical_field_name=fm.logical_field_name,
                physical_field_name=fm.physical_field_name,
                transformation_rule=fm.transformation_rule,
                created_at=fm.created_at,
                updated_at=fm.updated_at,
            )
            self.session.add(fm_db)

        # Update parent source mapping timestamp
        await self.session.execute(
            update(SourceMappingDB)
            .where(SourceMappingDB.id == entity_mapping.source_mapping_id)
            .values(updated_at=datetime.now(timezone.utc))
        )

        await self.session.flush()
        stmt = (
            select(EntityMappingDB)
            .where(EntityMappingDB.id == entity_mapping.id)
            .options(selectinload(EntityMappingDB.field_mappings))
        )
        result = await self.session.execute(stmt)
        return self._entity_mapping_to_domain(result.scalar_one())

    async def delete_entity_mapping(self, entity_mapping_id: str) -> bool:
        """Delete an entity mapping."""
        stmt = delete(EntityMappingDB).where(EntityMappingDB.id == entity_mapping_id)
        result = await self.session.execute(stmt)
        return result.rowcount > 0

    # ==========================================
    # Field Mappings
    # ==========================================

    async def add_field_mapping(self, field_mapping: FieldMapping) -> FieldMapping:
        """Add a single field mapping."""
        fm_db = FieldMappingDB(
            id=field_mapping.id,
            entity_mapping_id=field_mapping.entity_mapping_id,
            logical_field_id=field_mapping.logical_field_id,
            logical_field_name=field_mapping.logical_field_name,
            physical_field_name=field_mapping.physical_field_name,
            transformation_rule=field_mapping.transformation_rule,
            created_at=field_mapping.created_at,
            updated_at=field_mapping.updated_at,
        )
        self.session.add(fm_db)
        await self.session.flush()
        return self._field_mapping_to_domain(fm_db)

    async def delete_field_mapping(self, field_mapping_id: str) -> bool:
        """Delete a field mapping."""
        stmt = delete(FieldMappingDB).where(FieldMappingDB.id == field_mapping_id)
        result = await self.session.execute(stmt)
        return result.rowcount > 0

    # ==========================================
    # Summary Metrics
    # ==========================================

    async def get_summary(self) -> dict[str, int]:
        """Aggregate high-level registry metrics for the Overview card."""
        models_count = (await self.session.execute(select(func.count(LogicalModelDB.id)))).scalar_one() or 0
        entities_count = (await self.session.execute(select(func.count(LogicalEntityDB.id)))).scalar_one() or 0
        fields_count = (await self.session.execute(select(func.count(LogicalFieldDB.id)))).scalar_one() or 0
        source_mappings_count = (await self.session.execute(select(func.count(SourceMappingDB.id)))).scalar_one() or 0
        entity_mappings_count = (await self.session.execute(select(func.count(EntityMappingDB.id)))).scalar_one() or 0
        field_mappings_count = (await self.session.execute(select(func.count(FieldMappingDB.id)))).scalar_one() or 0

        active_count = (
            await self.session.execute(
                select(func.count(SourceMappingDB.id)).where(
                    SourceMappingDB.status.in_(["ACTIVE", "VALIDATED"])
                )
            )
        ).scalar_one() or 0

        draft_count = (
            await self.session.execute(
                select(func.count(SourceMappingDB.id)).where(SourceMappingDB.status == "DRAFT")
            )
        ).scalar_one() or 0

        return {
            "logical_models_count": models_count,
            "logical_entities_count": entities_count,
            "logical_fields_count": fields_count,
            "source_mappings_count": source_mappings_count,
            "entity_mappings_count": entity_mappings_count,
            "field_mappings_count": field_mappings_count,
            "active_mappings_count": active_count,
            "draft_mappings_count": draft_count,
        }
