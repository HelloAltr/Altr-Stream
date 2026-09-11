"""Schema Registry REST API endpoints for Logical Models and Source Mappings."""

from fastapi import APIRouter, Depends, HTTPException, Query, status

from altr_stream.application.registry_service import RegistryService
from altr_stream.domain.errors import (
    AltrStreamError,
    DuplicateMappingError,
    LogicalEntityNotFoundError,
    LogicalFieldNotFoundError,
    LogicalModelAlreadyExistsError,
    LogicalModelNotFoundError,
    MappingValidationError,
    SourceMappingNotFoundError,
    SourceNotFoundError,
)
from altr_stream.domain.logical import LogicalEntity, LogicalField
from altr_stream.domain.mapping import (
    EntityMapping,
    FieldMapping,
    MappingProvenance,
    MappingStatus,
)
from altr_stream.domain.schema import StandardDataType
from altr_stream.presentation.api.dependencies import get_registry_service
from altr_stream.presentation.api.dtos import (
    EntityMappingCreateDTO,
    EntityMappingResponseDTO,
    FieldMappingCreateDTO,
    FieldMappingResponseDTO,
    LogicalEntityCreateDTO,
    LogicalEntityResponseDTO,
    LogicalEntityUpdateDTO,
    LogicalFieldCreateDTO,
    LogicalFieldResponseDTO,
    LogicalFieldUpdateDTO,
    LogicalModelCreateDTO,
    LogicalModelResponseDTO,
    LogicalModelUpdateDTO,
    MappingValidationResponseDTO,
    RegistrySummaryDTO,
    SourceMappingCreateDTO,
    SourceMappingResponseDTO,
    SourceMappingUpdateDTO,
)

router = APIRouter(prefix="/registry", tags=["Schema Registry"])


# ==========================================
# Summary Metrics
# ==========================================

@router.get("/summary", response_model=RegistrySummaryDTO)
async def get_registry_summary(
    service: RegistryService = Depends(get_registry_service),
) -> RegistrySummaryDTO:
    """Retrieve high-level metrics for the Overview card."""
    summary = await service.get_summary()
    return RegistrySummaryDTO(**summary)


# ==========================================
# Logical Models
# ==========================================

@router.post("/models", response_model=LogicalModelResponseDTO, status_code=status.HTTP_201_CREATED)
async def create_logical_model(
    dto: LogicalModelCreateDTO,
    service: RegistryService = Depends(get_registry_service),
) -> LogicalModelResponseDTO:
    """Create a new logical data model."""
    try:
        entities: list[LogicalEntity] = []
        for e_dto in dto.entities:
            fields: list[LogicalField] = []
            for f_dto in e_dto.fields:
                fields.append(
                    LogicalField(
                        logical_entity_id="",
                        name=f_dto.name,
                        data_type=StandardDataType(f_dto.data_type.upper()),
                        is_primary_key=f_dto.is_primary_key,
                        nullable=f_dto.nullable,
                    )
                )
            entities.append(
                LogicalEntity(
                    logical_model_id="",
                    name=e_dto.name,
                    description=e_dto.description,
                    fields=fields,
                )
            )

        model = await service.create_model(
            name=dto.name,
            version=dto.version,
            description=dto.description,
            entities=entities,
        )
        return LogicalModelResponseDTO.from_domain(model)
    except LogicalModelAlreadyExistsError as e:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=e.message) from e
    except AltrStreamError as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=e.message) from e


@router.get("/models", response_model=list[LogicalModelResponseDTO])
async def list_logical_models(
    service: RegistryService = Depends(get_registry_service),
) -> list[LogicalModelResponseDTO]:
    """List all logical data models."""
    models = await service.list_models()
    return [LogicalModelResponseDTO.from_domain(m) for m in models]


@router.get("/models/{model_id}", response_model=LogicalModelResponseDTO)
async def get_logical_model(
    model_id: str,
    service: RegistryService = Depends(get_registry_service),
) -> LogicalModelResponseDTO:
    """Retrieve details for a single logical data model."""
    try:
        model = await service.get_model(model_id)
        return LogicalModelResponseDTO.from_domain(model)
    except LogicalModelNotFoundError as e:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=e.message) from e


@router.put("/models/{model_id}", response_model=LogicalModelResponseDTO)
async def update_logical_model(
    model_id: str,
    dto: LogicalModelUpdateDTO,
    service: RegistryService = Depends(get_registry_service),
) -> LogicalModelResponseDTO:
    """Update top-level logical model properties."""
    try:
        model = await service.update_model(
            model_id=model_id,
            name=dto.name,
            version=dto.version,
            description=dto.description,
        )
        return LogicalModelResponseDTO.from_domain(model)
    except LogicalModelNotFoundError as e:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=e.message) from e
    except LogicalModelAlreadyExistsError as e:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=e.message) from e


@router.delete("/models/{model_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_logical_model(
    model_id: str,
    service: RegistryService = Depends(get_registry_service),
) -> None:
    """Delete a logical data model and cascade-delete its mappings."""
    deleted = await service.delete_model(model_id)
    if not deleted:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Logical model with id '{model_id}' was not found.",
        )


# ==========================================
# Logical Entities
# ==========================================

@router.post(
    "/models/{model_id}/entities",
    response_model=LogicalEntityResponseDTO,
    status_code=status.HTTP_201_CREATED,
)
async def add_logical_entity(
    model_id: str,
    dto: LogicalEntityCreateDTO,
    service: RegistryService = Depends(get_registry_service),
) -> LogicalEntityResponseDTO:
    """Add a logical entity to an existing model."""
    try:
        fields: list[LogicalField] = []
        for f_dto in dto.fields:
            fields.append(
                LogicalField(
                    logical_entity_id="",
                    name=f_dto.name,
                    data_type=StandardDataType(f_dto.data_type.upper()),
                    is_primary_key=f_dto.is_primary_key,
                    nullable=f_dto.nullable,
                )
            )
        entity = await service.add_entity(
            model_id=model_id,
            name=dto.name,
            description=dto.description,
            fields=fields,
        )
        return LogicalEntityResponseDTO.from_domain(entity)
    except LogicalModelNotFoundError as e:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=e.message) from e
    except AltrStreamError as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=e.message) from e


@router.get("/entities/{entity_id}", response_model=LogicalEntityResponseDTO)
async def get_logical_entity(
    entity_id: str,
    service: RegistryService = Depends(get_registry_service),
) -> LogicalEntityResponseDTO:
    """Get a logical entity by ID."""
    try:
        entity = await service.get_entity(entity_id)
        return LogicalEntityResponseDTO.from_domain(entity)
    except LogicalEntityNotFoundError as e:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=e.message) from e


@router.put("/entities/{entity_id}", response_model=LogicalEntityResponseDTO)
@router.put("/models/{model_id}/entities/{entity_id}", response_model=LogicalEntityResponseDTO)
async def update_logical_entity(
    entity_id: str,
    dto: LogicalEntityUpdateDTO,
    model_id: str | None = None,
    service: RegistryService = Depends(get_registry_service),
) -> LogicalEntityResponseDTO:
    """Update a logical entity."""
    try:
        entity = await service.update_entity(
            entity_id=entity_id,
            name=dto.name,
            description=dto.description,
        )
        return LogicalEntityResponseDTO.from_domain(entity)
    except LogicalEntityNotFoundError as e:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=e.message) from e


@router.delete("/entities/{entity_id}", status_code=status.HTTP_204_NO_CONTENT)
@router.delete("/models/{model_id}/entities/{entity_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_logical_entity(
    entity_id: str,
    model_id: str | None = None,
    service: RegistryService = Depends(get_registry_service),
) -> None:
    """Delete a logical entity."""
    deleted = await service.delete_entity(entity_id)
    if not deleted:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Logical entity with id '{entity_id}' was not found.",
        )


# ==========================================
# Logical Fields
# ==========================================

@router.post(
    "/entities/{entity_id}/fields",
    response_model=LogicalFieldResponseDTO,
    status_code=status.HTTP_201_CREATED,
)
@router.post(
    "/models/{model_id}/entities/{entity_id}/fields",
    response_model=LogicalFieldResponseDTO,
    status_code=status.HTTP_201_CREATED,
)
async def add_logical_field(
    entity_id: str,
    dto: LogicalFieldCreateDTO,
    model_id: str | None = None,
    service: RegistryService = Depends(get_registry_service),
) -> LogicalFieldResponseDTO:
    """Add a logical field to an entity."""
    try:
        field = await service.add_field(
            entity_id=entity_id,
            name=dto.name,
            data_type=StandardDataType(dto.data_type.upper()),
            is_primary_key=dto.is_primary_key,
            nullable=dto.nullable,
        )
        return LogicalFieldResponseDTO.from_domain(field)
    except LogicalEntityNotFoundError as e:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=e.message) from e
    except AltrStreamError as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=e.message) from e


@router.get("/fields/{field_id}", response_model=LogicalFieldResponseDTO)
async def get_logical_field(
    field_id: str,
    service: RegistryService = Depends(get_registry_service),
) -> LogicalFieldResponseDTO:
    """Get a logical field by ID."""
    try:
        field = await service.get_field(field_id)
        return LogicalFieldResponseDTO.from_domain(field)
    except LogicalFieldNotFoundError as e:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=e.message) from e


@router.put("/fields/{field_id}", response_model=LogicalFieldResponseDTO)
@router.put(
    "/models/{model_id}/entities/{entity_id}/fields/{field_id}",
    response_model=LogicalFieldResponseDTO,
)
async def update_logical_field(
    field_id: str,
    dto: LogicalFieldUpdateDTO,
    entity_id: str | None = None,
    model_id: str | None = None,
    service: RegistryService = Depends(get_registry_service),
) -> LogicalFieldResponseDTO:
    """Update a logical field."""
    try:
        data_type = StandardDataType(dto.data_type.upper()) if dto.data_type else None
        field = await service.update_field(
            field_id=field_id,
            name=dto.name,
            data_type=data_type,
            is_primary_key=dto.is_primary_key,
            nullable=dto.nullable,
        )
        return LogicalFieldResponseDTO.from_domain(field)
    except LogicalFieldNotFoundError as e:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=e.message) from e


@router.delete("/fields/{field_id}", status_code=status.HTTP_204_NO_CONTENT)
@router.delete(
    "/models/{model_id}/entities/{entity_id}/fields/{field_id}",
    status_code=status.HTTP_204_NO_CONTENT,
)
async def delete_logical_field(
    field_id: str,
    entity_id: str | None = None,
    model_id: str | None = None,
    service: RegistryService = Depends(get_registry_service),
) -> None:
    """Delete a logical field."""
    deleted = await service.delete_field(field_id)
    if not deleted:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Logical field with id '{field_id}' was not found.",
        )


# ==========================================
# Source Mappings
# ==========================================

@router.post("/mappings", response_model=SourceMappingResponseDTO, status_code=status.HTTP_201_CREATED)
async def create_source_mapping(
    dto: SourceMappingCreateDTO,
    service: RegistryService = Depends(get_registry_service),
) -> SourceMappingResponseDTO:
    """Create a new source mapping association."""
    try:
        entity_mappings: list[EntityMapping] = []
        for em_dto in dto.entity_mappings:
            field_mappings: list[FieldMapping] = []
            for fm_dto in em_dto.field_mappings:
                field_mappings.append(
                    FieldMapping(
                        entity_mapping_id="",
                        logical_field_id=fm_dto.logical_field_id,
                        logical_field_name=fm_dto.logical_field_name or "",
                        physical_field_name=fm_dto.physical_field_name,
                        transformation_rule=fm_dto.transformation_rule,
                    )
                )
            entity_mappings.append(
                EntityMapping(
                    source_mapping_id="",
                    logical_entity_id=em_dto.logical_entity_id,
                    logical_entity_name=em_dto.logical_entity_name or "",
                    physical_entity_name=em_dto.physical_entity_name,
                    physical_namespace=em_dto.physical_namespace,
                    field_mappings=field_mappings,
                )
            )

        mapping = await service.create_source_mapping(
            logical_model_id=dto.logical_model_id,
            source_id=dto.source_id,
            version=dto.version,
            status=MappingStatus(dto.status.upper()),
            provenance=MappingProvenance(dto.provenance.upper()),
            entity_mappings=entity_mappings,
        )
        return SourceMappingResponseDTO.from_domain(mapping)
    except (LogicalModelNotFoundError, SourceNotFoundError) as e:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=e.message) from e
    except DuplicateMappingError as e:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=e.message) from e
    except MappingValidationError as e:
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail=e.message) from e
    except AltrStreamError as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=e.message) from e


@router.get("/mappings", response_model=list[SourceMappingResponseDTO])
async def list_source_mappings(
    logical_model_id: str | None = Query(default=None, description="Filter by logical model ID"),
    source_id: str | None = Query(default=None, description="Filter by physical source ID"),
    service: RegistryService = Depends(get_registry_service),
) -> list[SourceMappingResponseDTO]:
    """List source mappings with optional filters."""
    mappings = await service.list_source_mappings(
        logical_model_id=logical_model_id, source_id=source_id
    )
    return [SourceMappingResponseDTO.from_domain(m) for m in mappings]


@router.get("/mappings/{mapping_id}", response_model=SourceMappingResponseDTO)
async def get_source_mapping(
    mapping_id: str,
    service: RegistryService = Depends(get_registry_service),
) -> SourceMappingResponseDTO:
    """Retrieve a single source mapping by ID."""
    try:
        mapping = await service.get_source_mapping(mapping_id)
        return SourceMappingResponseDTO.from_domain(mapping)
    except SourceMappingNotFoundError as e:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=e.message) from e


@router.put("/mappings/{mapping_id}", response_model=SourceMappingResponseDTO)
async def update_source_mapping(
    mapping_id: str,
    dto: SourceMappingUpdateDTO,
    service: RegistryService = Depends(get_registry_service),
) -> SourceMappingResponseDTO:
    """Update source mapping status or properties."""
    try:
        status_val = MappingStatus(dto.status.upper()) if dto.status else None
        prov_val = MappingProvenance(dto.provenance.upper()) if dto.provenance else None

        entity_mappings: list[EntityMapping] | None = None
        if dto.entity_mappings is not None:
            entity_mappings = []
            for em_dto in dto.entity_mappings:
                field_mappings: list[FieldMapping] = []
                for fm_dto in em_dto.field_mappings:
                    field_mappings.append(
                        FieldMapping(
                            entity_mapping_id="",
                            logical_field_id=fm_dto.logical_field_id,
                            logical_field_name=fm_dto.logical_field_name or "",
                            physical_field_name=fm_dto.physical_field_name,
                            transformation_rule=fm_dto.transformation_rule,
                        )
                    )
                entity_mappings.append(
                    EntityMapping(
                        source_mapping_id=mapping_id,
                        logical_entity_id=em_dto.logical_entity_id,
                        logical_entity_name=em_dto.logical_entity_name or "",
                        physical_entity_name=em_dto.physical_entity_name,
                        physical_namespace=em_dto.physical_namespace,
                        field_mappings=field_mappings,
                    )
                )

        mapping = await service.update_source_mapping(
            mapping_id=mapping_id,
            version=dto.version,
            status=status_val,
            provenance=prov_val,
            error_message=dto.error_message,
            entity_mappings=entity_mappings,
        )
        return SourceMappingResponseDTO.from_domain(mapping)
    except SourceMappingNotFoundError as e:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=e.message) from e
    except MappingValidationError as e:
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail=e.message) from e


@router.delete("/mappings/{mapping_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_source_mapping(
    mapping_id: str,
    service: RegistryService = Depends(get_registry_service),
) -> None:
    """Delete a source mapping."""
    deleted = await service.delete_source_mapping(mapping_id)
    if not deleted:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Source mapping with id '{mapping_id}' was not found.",
        )


@router.post(
    "/mappings/{mapping_id}/entities",
    response_model=EntityMappingResponseDTO,
    status_code=status.HTTP_201_CREATED,
)
async def add_entity_mapping(
    mapping_id: str,
    dto: EntityMappingCreateDTO,
    service: RegistryService = Depends(get_registry_service),
) -> EntityMappingResponseDTO:
    """Add an entity mapping to a source mapping."""
    try:
        field_mappings: list[FieldMapping] = []
        for fm_dto in dto.field_mappings:
            field_mappings.append(
                FieldMapping(
                    entity_mapping_id="",
                    logical_field_id=fm_dto.logical_field_id,
                    logical_field_name="",
                    physical_field_name=fm_dto.physical_field_name,
                    transformation_rule=fm_dto.transformation_rule,
                )
            )
        em = await service.add_entity_mapping(
            source_mapping_id=mapping_id,
            logical_entity_id=dto.logical_entity_id,
            physical_entity_name=dto.physical_entity_name,
            physical_namespace=dto.physical_namespace,
            field_mappings=field_mappings,
        )
        return EntityMappingResponseDTO.from_domain(em)
    except (SourceMappingNotFoundError, LogicalEntityNotFoundError) as e:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=e.message) from e
    except AltrStreamError as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=e.message) from e


@router.delete(
    "/mappings/{mapping_id}/entities/{entity_mapping_id}",
    status_code=status.HTTP_204_NO_CONTENT,
)
async def delete_entity_mapping(
    mapping_id: str,
    entity_mapping_id: str,
    service: RegistryService = Depends(get_registry_service),
) -> None:
    """Delete an entity mapping."""
    deleted = await service.delete_entity_mapping(entity_mapping_id)
    if not deleted:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Entity mapping with id '{entity_mapping_id}' was not found.",
        )


@router.post(
    "/mappings/{mapping_id}/entities/{entity_mapping_id}/fields",
    response_model=FieldMappingResponseDTO,
    status_code=status.HTTP_201_CREATED,
)
async def add_field_mapping(
    mapping_id: str,
    entity_mapping_id: str,
    dto: FieldMappingCreateDTO,
    service: RegistryService = Depends(get_registry_service),
) -> FieldMappingResponseDTO:
    """Add a field mapping to an entity mapping."""
    try:
        fm = await service.add_field_mapping(
            entity_mapping_id=entity_mapping_id,
            logical_field_id=dto.logical_field_id,
            physical_field_name=dto.physical_field_name,
            transformation_rule=dto.transformation_rule,
        )
        return FieldMappingResponseDTO.from_domain(fm)
    except LogicalFieldNotFoundError as e:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=e.message) from e
    except AltrStreamError as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=e.message) from e


@router.delete(
    "/mappings/{mapping_id}/entities/{entity_mapping_id}/fields/{field_mapping_id}",
    status_code=status.HTTP_204_NO_CONTENT,
)
async def delete_field_mapping(
    mapping_id: str,
    entity_mapping_id: str,
    field_mapping_id: str,
    service: RegistryService = Depends(get_registry_service),
) -> None:
    """Delete a field mapping."""
    deleted = await service.delete_field_mapping(field_mapping_id)
    if not deleted:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Field mapping with id '{field_mapping_id}' was not found.",
        )


@router.post("/mappings/{mapping_id}/validate", response_model=MappingValidationResponseDTO)
async def validate_source_mapping(
    mapping_id: str,
    service: RegistryService = Depends(get_registry_service),
) -> MappingValidationResponseDTO:
    """Validate a source mapping against latest physical schema discovery snapshot."""
    try:
        is_valid, err, mapping = await service.validate_source_mapping(mapping_id)
        return MappingValidationResponseDTO(
            is_valid=is_valid,
            error=err,
            mapping=SourceMappingResponseDTO.from_domain(mapping),
        )
    except SourceMappingNotFoundError as e:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=e.message) from e
    except AltrStreamError as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=e.message) from e


@router.post("/mappings/{mapping_id}/activate", response_model=SourceMappingResponseDTO)
async def activate_source_mapping(
    mapping_id: str,
    service: RegistryService = Depends(get_registry_service),
) -> SourceMappingResponseDTO:
    """Validate and set a source mapping to ACTIVE."""
    try:
        mapping = await service.activate_source_mapping(mapping_id)
        return SourceMappingResponseDTO.from_domain(mapping)
    except SourceMappingNotFoundError as e:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=e.message) from e
    except MappingValidationError as e:
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail=e.message) from e
    except AltrStreamError as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=e.message) from e
