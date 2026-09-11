import asyncio
import json
from sqlalchemy.ext.asyncio import create_async_engine, async_sessionmaker, AsyncSession
from altr_stream.infrastructure.database.models import Base
from altr_stream.infrastructure.database.registry_repository import SqliteRegistryRepository
from altr_stream.infrastructure.database.repository import SqliteSourceRepository
from altr_stream.application.schema_service import SchemaService
from altr_stream.application.registry_service import RegistryService
from altr_stream.domain.logical import StandardDataType, LogicalField
from altr_stream.domain.mapping import MappingStatus, MappingProvenance, EntityMapping, FieldMapping
from altr_stream.domain.source import Source, SourceType
from altr_stream.domain.schema import SourceSchema, EntitySchema, FieldSchema
from altr_stream.presentation.api.dtos import (
    SourceMappingResponseDTO,
    MappingValidationResponseDTO,
    SourceMappingUpdateDTO,
)

async def run():
    engine = create_async_engine("sqlite+aiosqlite:///:memory:", echo=False)
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    
    factory = async_sessionmaker(engine, expire_on_commit=False, class_=AsyncSession)
    
    async with factory() as session:
        reg_repo = SqliteRegistryRepository(session)
        src_repo = SqliteSourceRepository(session)
        schema_service = SchemaService(src_repo)
        service = RegistryService(reg_repo, src_repo, schema_service)
        
        # 1. Create Source
        source = Source(
            name="Postgre Test",
            type=SourceType.POSTGRESQL,
            host="localhost",
            port=5432,
            database_name="altr_test_db",
            username="altr_test_user",
        )
        source = await src_repo.create(source)
        
        # 2. Save schema snapshot
        schema = SourceSchema(
            source_id=source.id,
            source_name="Postgre Test",
            version="1.0.0",
            entities=[
                EntitySchema(
                    name="users",
                    namespace="public",
                    fields=[
                        FieldSchema(name="id", data_type=StandardDataType.INTEGER, native_data_type="int4", is_primary_key=True),
                        FieldSchema(name="full_name", data_type=StandardDataType.STRING, native_data_type="varchar(255)"),
                        FieldSchema(name="email", data_type=StandardDataType.STRING, native_data_type="varchar(255)"),
                        FieldSchema(name="is_active", data_type=StandardDataType.BOOLEAN, native_data_type="bool"),
                        FieldSchema(name="metadata", data_type=StandardDataType.JSON, native_data_type="jsonb"),
                    ]
                )
            ]
        )
        await src_repo.save_schema_snapshot(source.id, schema)
        
        # 3. Create Logical Model
        fields = [
            LogicalField(logical_entity_id="", name="id", data_type=StandardDataType.INTEGER, is_primary_key=True, nullable=False),
            LogicalField(logical_entity_id="", name="fullName", data_type=StandardDataType.STRING, nullable=False),
            LogicalField(logical_entity_id="", name="emailAddress", data_type=StandardDataType.STRING, nullable=False),
            LogicalField(logical_entity_id="", name="Status", data_type=StandardDataType.STRING, nullable=True),
            LogicalField(logical_entity_id="", name="metadata", data_type=StandardDataType.JSON, nullable=True),
        ]
        from altr_stream.domain.logical import LogicalEntity
        student_ent = LogicalEntity(logical_model_id="", name="Student", fields=fields)
        model = await service.create_model("UniversityDomain", version="1.0.0", entities=[student_ent])
        student_entity = model.entities[0]
        
        print("Created model:", model.name, "with entity:", student_entity.name)
        for f in student_entity.fields:
            print("  Field:", f.id, f.name)
            
        # 4. Create Initial Source Mapping
        initial_fms = [
            FieldMapping(entity_mapping_id="", logical_field_id=student_entity.fields[0].id, logical_field_name="id", physical_field_name="id"),
            FieldMapping(entity_mapping_id="", logical_field_id=student_entity.fields[1].id, logical_field_name="fullName", physical_field_name="full_name"),
            FieldMapping(entity_mapping_id="", logical_field_id=student_entity.fields[2].id, logical_field_name="emailAddress", physical_field_name="email"),
            FieldMapping(entity_mapping_id="", logical_field_id=student_entity.fields[3].id, logical_field_name="Status", physical_field_name="is_active"),
            FieldMapping(entity_mapping_id="", logical_field_id=student_entity.fields[4].id, logical_field_name="metadata", physical_field_name="metadata"),
        ]
        em = EntityMapping(
            source_mapping_id="",
            logical_entity_id=student_entity.id,
            logical_entity_name=student_entity.name,
            physical_entity_name="users",
            physical_namespace="public",
            field_mappings=initial_fms,
        )
        mapping = await service.create_source_mapping(
            logical_model_id=model.id,
            source_id=source.id,
            entity_mappings=[em],
        )
        print("Created mapping:", mapping.id, "status:", mapping.status)
        
        # Activate mapping
        active_mapping = await service.activate_source_mapping(mapping.id)
        print("Activated mapping:", active_mapping.id, "status:", active_mapping.status)
        
        # 5. NOW simulate the User's Edit Action:
        # Changing mappings to ONLY `id -> id` and rest (Unmapped)
        edit_fms = [
            FieldMapping(entity_mapping_id="", logical_field_id=student_entity.fields[0].id, logical_field_name="id", physical_field_name="id"),
        ]
        edit_em = EntityMapping(
            source_mapping_id=mapping.id,
            logical_entity_id=student_entity.id,
            logical_entity_name=student_entity.name,
            physical_entity_name="users",
            physical_namespace="public",
            field_mappings=edit_fms,
        )
        
        updated_mapping = await service.update_source_mapping(
            mapping_id=mapping.id,
            entity_mappings=[edit_em],
        )
        print("\n--- After update_source_mapping ---")
        print("Status:", updated_mapping.status)
        update_dto = SourceMappingResponseDTO.from_domain(updated_mapping)
        print("PUT Response JSON:\n", json.dumps(update_dto.model_dump(mode="json"), indent=2))
        
        # 6. NOW validate
        is_valid, err, validated_m = await service.validate_source_mapping(mapping.id)
        print("\n--- After validate_source_mapping ---")
        print("is_valid:", is_valid, "err:", err, "status:", validated_m.status)
        val_dto = MappingValidationResponseDTO(
            is_valid=is_valid,
            error=err,
            mapping=SourceMappingResponseDTO.from_domain(validated_m),
        )
        print("POST /validate Response JSON:\n", json.dumps(val_dto.model_dump(mode="json"), indent=2))

if __name__ == "__main__":
    asyncio.run(run())
