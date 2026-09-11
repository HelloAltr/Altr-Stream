"""Schema Registry application service for Logical Models and Mappings."""

from altr_stream.application.schema_service import SchemaService
from altr_stream.domain.errors import (
    DuplicateMappingError,
    LogicalEntityNotFoundError,
    LogicalFieldNotFoundError,
    LogicalModelAlreadyExistsError,
    LogicalModelNotFoundError,
    MappingValidationError,
    SourceMappingNotFoundError,
    SourceNotFoundError,
)
from altr_stream.domain.logical import LogicalEntity, LogicalField, LogicalModel
from altr_stream.domain.mapping import (
    EntityMapping,
    FieldMapping,
    MappingProvenance,
    MappingStatus,
    SourceMapping,
)
from altr_stream.domain.schema import StandardDataType, are_datatypes_compatible
from altr_stream.infrastructure.database.registry_repository import SqliteRegistryRepository
from altr_stream.infrastructure.database.repository import SqliteSourceRepository


class RegistryService:
    """Application use cases for Logical Models, Entities, Fields, and Source Mappings."""

    def __init__(
        self,
        registry_repository: SqliteRegistryRepository,
        source_repository: SqliteSourceRepository,
        schema_service: SchemaService,
    ):
        self.registry_repo = registry_repository
        self.source_repo = source_repository
        self.schema_service = schema_service

    # ==========================================
    # Logical Models
    # ==========================================

    async def create_model(
        self,
        name: str,
        version: str = "1.0.0",
        description: str | None = None,
        entities: list[LogicalEntity] | None = None,
    ) -> LogicalModel:
        """Create a new logical model."""
        existing = await self.registry_repo.get_model_by_name(name)
        if existing:
            raise LogicalModelAlreadyExistsError(name)

        model = LogicalModel(
            name=name,
            version=version,
            description=description,
            entities=entities or [],
        )
        return await self.registry_repo.create_model(model)

    async def get_model(self, model_id: str) -> LogicalModel:
        """Get logical model by ID."""
        model = await self.registry_repo.get_model_by_id(model_id)
        if not model:
            raise LogicalModelNotFoundError(model_id)
        return model

    async def get_model_by_name(self, name: str) -> LogicalModel | None:
        """Get logical model by name."""
        return await self.registry_repo.get_model_by_name(name)

    async def list_models(self) -> list[LogicalModel]:
        """List all logical models."""
        return await self.registry_repo.list_models()

    async def update_model(
        self,
        model_id: str,
        name: str | None = None,
        version: str | None = None,
        description: str | None = None,
    ) -> LogicalModel:
        """Update top-level logical model properties."""
        model = await self.get_model(model_id)
        if name and name != model.name:
            existing = await self.registry_repo.get_model_by_name(name)
            if existing and existing.id != model_id:
                raise LogicalModelAlreadyExistsError(name)
            model.name = name
        if version is not None:
            model.version = version
        if description is not None:
            model.description = description

        return await self.registry_repo.update_model(model)

    async def delete_model(self, model_id: str) -> bool:
        """Delete logical model and its mappings."""
        return await self.registry_repo.delete_model(model_id)

    # ==========================================
    # Logical Entities
    # ==========================================

    async def add_entity(
        self,
        model_id: str,
        name: str,
        description: str | None = None,
        fields: list[LogicalField] | None = None,
    ) -> LogicalEntity:
        """Add a new logical entity to a model."""
        model = await self.get_model(model_id)
        if model.get_entity_by_name(name):
            raise MappingValidationError(
                f"Logical entity '{name}' already exists in model '{model.name}'."
            )

        entity = LogicalEntity(
            logical_model_id=model_id,
            name=name,
            description=description,
            fields=fields or [],
        )
        return await self.registry_repo.add_entity(entity)

    async def get_entity(self, entity_id: str) -> LogicalEntity:
        """Get logical entity by ID."""
        entity = await self.registry_repo.get_entity_by_id(entity_id)
        if not entity:
            raise LogicalEntityNotFoundError(entity_id)
        return entity

    async def update_entity(
        self,
        entity_id: str,
        name: str | None = None,
        description: str | None = None,
    ) -> LogicalEntity:
        """Update a logical entity."""
        entity = await self.registry_repo.get_entity_by_id(entity_id)
        if not entity:
            raise LogicalEntityNotFoundError(entity_id)

        if name is not None:
            entity.name = name
        if description is not None:
            entity.description = description

        return await self.registry_repo.update_entity(entity)

    async def delete_entity(self, entity_id: str) -> bool:
        """Delete a logical entity."""
        return await self.registry_repo.delete_entity(entity_id)

    # ==========================================
    # Logical Fields
    # ==========================================

    async def add_field(
        self,
        entity_id: str,
        name: str,
        data_type: StandardDataType = StandardDataType.STRING,
        is_primary_key: bool = False,
        nullable: bool = True,
    ) -> LogicalField:
        """Add a field to an entity."""
        entity = await self.registry_repo.get_entity_by_id(entity_id)
        if not entity:
            raise LogicalEntityNotFoundError(entity_id)

        if entity.get_field_by_name(name):
            raise MappingValidationError(
                f"Logical field '{name}' already exists in entity '{entity.name}'."
            )

        field = LogicalField(
            logical_entity_id=entity_id,
            name=name,
            data_type=data_type,
            is_primary_key=is_primary_key,
            nullable=nullable,
        )
        return await self.registry_repo.add_field(field)

    async def get_field(self, field_id: str) -> LogicalField:
        """Get logical field by ID."""
        field = await self.registry_repo.get_field_by_id(field_id)
        if not field:
            raise LogicalFieldNotFoundError(field_id)
        return field

    async def update_field(
        self,
        field_id: str,
        name: str | None = None,
        data_type: StandardDataType | None = None,
        is_primary_key: bool | None = None,
        nullable: bool | None = None,
    ) -> LogicalField:
        """Update a logical field."""
        field = await self.registry_repo.get_field_by_id(field_id)
        if not field:
            raise LogicalFieldNotFoundError(field_id)

        if name is not None:
            field.name = name
        if data_type is not None:
            field.data_type = data_type
        if is_primary_key is not None:
            field.is_primary_key = is_primary_key
        if nullable is not None:
            field.nullable = nullable

        return await self.registry_repo.update_field(field)

    async def delete_field(self, field_id: str) -> bool:
        """Delete a logical field."""
        return await self.registry_repo.delete_field(field_id)

    # ==========================================
    # Source Mappings
    # ==========================================

    async def create_source_mapping(
        self,
        logical_model_id: str,
        source_id: str,
        version: str = "1.0.0",
        status: MappingStatus = MappingStatus.DRAFT,
        provenance: MappingProvenance = MappingProvenance.USER,
        entity_mappings: list[EntityMapping] | None = None,
    ) -> SourceMapping:
        """Create a new mapping between a logical model and physical source."""
        model = await self.get_model(logical_model_id)

        # Verify source exists
        source = await self.source_repo.get_by_id(source_id)
        if not source:
            raise SourceNotFoundError(source_id)

        # Check duplicate
        existing = await self.registry_repo.list_source_mappings(
            logical_model_id=logical_model_id, source_id=source_id
        )
        if existing:
            raise DuplicateMappingError(
                f"Source mapping already exists between model '{logical_model_id}' and source '{source_id}'."
            )

        ems = entity_mappings or []
        for em in ems:
            logical_entity = model.get_entity_by_id(em.logical_entity_id) or model.get_entity_by_name(em.logical_entity_name)
            if logical_entity:
                em.logical_entity_name = logical_entity.name
                for fm in em.field_mappings:
                    logical_field = logical_entity.get_field_by_id(fm.logical_field_id) or logical_entity.get_field_by_name(fm.logical_field_name)
                    if logical_field:
                        fm.logical_field_name = logical_field.name

        initial_status = MappingStatus.DRAFT if status == MappingStatus.ACTIVE else status
        mapping = SourceMapping(
            logical_model_id=logical_model_id,
            source_id=source_id,
            version=version,
            status=initial_status,
            provenance=provenance,
            entity_mappings=ems,
        )
        created = await self.registry_repo.create_source_mapping(mapping)
        return created

    async def get_source_mapping(self, mapping_id: str) -> SourceMapping:
        """Get source mapping by ID."""
        mapping = await self.registry_repo.get_source_mapping_by_id(mapping_id)
        if not mapping:
            raise SourceMappingNotFoundError(mapping_id)
        return mapping

    async def list_source_mappings(
        self,
        logical_model_id: str | None = None,
        source_id: str | None = None,
    ) -> list[SourceMapping]:
        """List source mappings with optional filters."""
        return await self.registry_repo.list_source_mappings(
            logical_model_id=logical_model_id, source_id=source_id
        )

    async def update_source_mapping(
        self,
        mapping_id: str,
        version: str | None = None,
        status: MappingStatus | None = None,
        provenance: MappingProvenance | None = None,
        error_message: str | None = None,
        entity_mappings: list[EntityMapping] | None = None,
    ) -> SourceMapping:
        """Update source mapping status, properties, or entity mappings."""
        mapping = await self.get_source_mapping(mapping_id)
        if version is not None:
            mapping.version = version
        if provenance is not None:
            mapping.provenance = provenance
        if error_message is not None:
            mapping.error_message = error_message

        if entity_mappings is not None:
            model = await self.get_model(mapping.logical_model_id)
            for em in entity_mappings:
                logical_entity = model.get_entity_by_id(em.logical_entity_id) or model.get_entity_by_name(em.logical_entity_name)
                if logical_entity:
                    em.logical_entity_name = logical_entity.name
                    for fm in em.field_mappings:
                        logical_field = logical_entity.get_field_by_id(fm.logical_field_id) or logical_entity.get_field_by_name(fm.logical_field_name)
                        if logical_field:
                            fm.logical_field_name = logical_field.name

            mapping.entity_mappings = entity_mappings
            # Reset status to DRAFT whenever mapping content is updated
            mapping.status = MappingStatus.DRAFT
            mapping.error_message = None
            return await self.registry_repo.update_source_mapping(mapping, replace_entities=True)

        if status is not None:
            if status == MappingStatus.ACTIVE and mapping.status != MappingStatus.VALIDATED:
                raise MappingValidationError("Cannot directly transition to ACTIVE without validation.")
            mapping.status = status

        return await self.registry_repo.update_source_mapping(mapping, replace_entities=False)

    async def delete_source_mapping(self, mapping_id: str) -> bool:
        """Delete source mapping."""
        return await self.registry_repo.delete_source_mapping(mapping_id)

    # ==========================================
    # Entity & Field Mappings Management
    # ==========================================

    async def add_entity_mapping(
        self,
        source_mapping_id: str,
        logical_entity_id: str,
        physical_entity_name: str,
        physical_namespace: str = "public",
        field_mappings: list[FieldMapping] | None = None,
    ) -> EntityMapping:
        """Add an entity mapping to a source mapping."""
        mapping = await self.get_source_mapping(source_mapping_id)
        model = await self.get_model(mapping.logical_model_id)

        logical_entity = model.get_entity_by_id(logical_entity_id)
        if not logical_entity:
            raise LogicalEntityNotFoundError(logical_entity_id, model.id)

        fms = field_mappings or []
        for fm in fms:
            logical_field = logical_entity.get_field_by_id(fm.logical_field_id) or logical_entity.get_field_by_name(fm.logical_field_name)
            if logical_field:
                fm.logical_field_name = logical_field.name

        em = EntityMapping(
            source_mapping_id=source_mapping_id,
            logical_entity_id=logical_entity.id,
            logical_entity_name=logical_entity.name,
            physical_entity_name=physical_entity_name,
            physical_namespace=physical_namespace,
            field_mappings=fms,
        )
        created = await self.registry_repo.add_entity_mapping(em)

        # Reset parent mapping to DRAFT
        mapping.status = MappingStatus.DRAFT
        mapping.error_message = None
        await self.registry_repo.update_source_mapping(mapping)

        return created

    async def delete_entity_mapping(self, entity_mapping_id: str) -> bool:
        """Delete an entity mapping."""
        return await self.registry_repo.delete_entity_mapping(entity_mapping_id)

    async def add_field_mapping(
        self,
        entity_mapping_id: str,
        logical_field_id: str,
        physical_field_name: str,
        transformation_rule: str | None = None,
    ) -> FieldMapping:
        """Add a field mapping to an entity mapping."""
        field_mapping = FieldMapping(
            entity_mapping_id=entity_mapping_id,
            logical_field_id=logical_field_id,
            logical_field_name="",
            physical_field_name=physical_field_name,
            transformation_rule=transformation_rule,
        )

        field = await self.registry_repo.get_field_by_id(logical_field_id)
        if not field:
            raise LogicalFieldNotFoundError(logical_field_id)
        field_mapping.logical_field_name = field.name

        created = await self.registry_repo.add_field_mapping(field_mapping)
        return created

    async def delete_field_mapping(self, field_mapping_id: str) -> bool:
        """Delete a field mapping."""
        return await self.registry_repo.delete_field_mapping(field_mapping_id)

    # ==========================================
    # Mapping Validation & Activation
    # ==========================================

    async def validate_source_mapping(self, mapping_id: str) -> tuple[bool, str | None, SourceMapping]:
        """Validate a SourceMapping against the latest physical schema snapshot.

        Checks:
        1. LogicalModel and its entities/fields exist.
        2. Physical Source exists.
        3. Physical Source has discovered schema snapshot (or discovers one).
        4. Each mapped physical entity (table/view) exists in the physical schema.
        5. Each mapped physical column exists in the physical entity.
        """
        mapping = await self.get_source_mapping(mapping_id)
        model = await self.get_model(mapping.logical_model_id)

        source = await self.source_repo.get_by_id(mapping.source_id)
        if not source:
            mapping.status = MappingStatus.ERROR
            mapping.error_message = f"Physical source '{mapping.source_id}' was not found."
            updated = await self.registry_repo.update_source_mapping(mapping)
            return False, mapping.error_message, updated

        # Retrieve or discover physical schema
        physical_schema = await self.schema_service.get_latest_schema(source.id)
        if not physical_schema:
            try:
                physical_schema = await self.schema_service.discover_and_save_schema(source.id)
            except Exception as e:
                mapping.status = MappingStatus.ERROR
                mapping.error_message = f"Physical schema discovery failed for source '{source.name}': {e}"
                updated = await self.registry_repo.update_source_mapping(mapping)
                return False, mapping.error_message, updated

        # Validate each entity mapping
        if not mapping.entity_mappings:
            mapping.status = MappingStatus.DRAFT
            mapping.error_message = "No entity mappings defined yet."
            updated = await self.registry_repo.update_source_mapping(mapping)
            return False, mapping.error_message, updated

        for em in mapping.entity_mappings:
            # Check logical entity exists in model
            logical_entity = model.get_entity_by_id(em.logical_entity_id) or model.get_entity_by_name(em.logical_entity_name)
            if not logical_entity:
                mapping.status = MappingStatus.ERROR
                mapping.error_message = f"Logical entity '{em.logical_entity_name or em.logical_entity_id}' not found in model '{model.name}'."
                updated = await self.registry_repo.update_source_mapping(mapping)
                return False, mapping.error_message, updated

            # Check physical entity exists in schema snapshot
            matching_physical_entities = [
                e for e in physical_schema.entities
                if e.name.lower() == em.physical_entity_name.lower()
                and (not em.physical_namespace or e.namespace.lower() == em.physical_namespace.lower() or em.physical_namespace in ["public", "main", "default"])
            ]
            if not matching_physical_entities:
                matching_physical_entities = [
                    e for e in physical_schema.entities
                    if e.name.lower() == em.physical_entity_name.lower()
                ]

            if not matching_physical_entities:
                mapping.status = MappingStatus.ERROR
                mapping.error_message = (
                    f"Physical entity '{em.physical_namespace}.{em.physical_entity_name}' "
                    f"does not exist in discovered schema of source '{source.name}'."
                )
                updated = await self.registry_repo.update_source_mapping(mapping)
                return False, mapping.error_message, updated

            phys_entity = matching_physical_entities[0]

            if not em.field_mappings:
                mapping.status = MappingStatus.ERROR
                mapping.error_message = f"Entity '{em.logical_entity_name or em.physical_entity_name}' has no mapped fields."
                updated = await self.registry_repo.update_source_mapping(mapping)
                return False, mapping.error_message, updated

            # Validate each field mapping
            for fm in em.field_mappings:
                # Check logical field in entity
                logical_field = (
                    logical_entity.get_field_by_id(fm.logical_field_id)
                    or logical_entity.get_field_by_name(fm.logical_field_name)
                )
                if not logical_field:
                    mapping.status = MappingStatus.ERROR
                    mapping.error_message = (
                        f"Logical field '{fm.logical_field_name or fm.logical_field_id}' not found in entity '{logical_entity.name}'."
                    )
                    updated = await self.registry_repo.update_source_mapping(mapping)
                    return False, mapping.error_message, updated

                # Check physical field in physical entity
                phys_field = phys_entity.get_field(fm.physical_field_name)
                if not phys_field:
                    # Case-insensitive column check
                    for f in phys_entity.fields:
                        if f.name.lower() == fm.physical_field_name.lower():
                            phys_field = f
                            break

                if not phys_field:
                    mapping.status = MappingStatus.ERROR
                    mapping.error_message = (
                        f"Physical field '{fm.physical_field_name}' not found in table '{phys_entity.name}'."
                    )
                    updated = await self.registry_repo.update_source_mapping(mapping)
                    return False, mapping.error_message, updated

                # Check logical-to-physical data type compatibility
                if not are_datatypes_compatible(logical_field.data_type, phys_field.data_type):
                    mapping.status = MappingStatus.ERROR
                    mapping.error_message = (
                        f"Logical field '{logical_field.name}' ({logical_field.data_type.value}) cannot map to "
                        f"physical field '{phys_field.name}' ({phys_field.data_type.value})."
                    )
                    updated = await self.registry_repo.update_source_mapping(mapping)
                    return False, mapping.error_message, updated

        # All passed
        mapping.status = MappingStatus.VALIDATED
        mapping.error_message = None
        updated = await self.registry_repo.update_source_mapping(mapping)
        return True, None, updated

    async def activate_source_mapping(self, mapping_id: str) -> SourceMapping:
        """Validate and set a VALIDATED source mapping status to ACTIVE."""
        mapping = await self.get_source_mapping(mapping_id)
        if mapping.status != MappingStatus.VALIDATED:
            raise MappingValidationError(
                f"Cannot activate mapping with status '{mapping.status.value}'. Only VALIDATED mappings can be activated."
            )

        # Enforce single active mapping rule per logical model
        all_mappings = await self.registry_repo.list_source_mappings(
            logical_model_id=mapping.logical_model_id
        )
        for other in all_mappings:
            if other.id != mapping.id and other.status == MappingStatus.ACTIVE:
                other.status = MappingStatus.VALIDATED
                await self.registry_repo.update_source_mapping(other)

        mapping.status = MappingStatus.ACTIVE
        mapping.error_message = None
        return await self.registry_repo.update_source_mapping(mapping)

    async def get_summary(self) -> dict[str, int]:
        """Aggregate summary metrics for the Overview card."""
        return await self.registry_repo.get_summary()
