import asyncio
import json
from httpx import AsyncClient, ASGITransport
from altr_stream.main import app
from altr_stream.domain.logical import StandardDataType, LogicalField, LogicalEntity
from altr_stream.domain.mapping import MappingStatus, MappingProvenance, EntityMapping, FieldMapping
from altr_stream.domain.source import Source, SourceType
from altr_stream.domain.schema import SourceSchema, EntitySchema, FieldSchema
from altr_stream.infrastructure.database.models import Base
from altr_stream.infrastructure.database.registry_repository import SqliteRegistryRepository
from altr_stream.infrastructure.database.repository import SqliteSourceRepository
from altr_stream.application.schema_service import SchemaService
from altr_stream.application.registry_service import RegistryService
from altr_stream.infrastructure.database.session import get_session
from sqlalchemy.ext.asyncio import create_async_engine, async_sessionmaker, AsyncSession
from sqlalchemy.pool import StaticPool

async def run():
    engine = create_async_engine(
        "sqlite+aiosqlite:///:memory:",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
        echo=False,
    )
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    
    factory = async_sessionmaker(engine, expire_on_commit=False, class_=AsyncSession)
    
    async def get_test_session():
        async with factory() as session:
            try:
                yield session
                await session.commit()
            except Exception:
                await session.rollback()
                raise
    
    app.dependency_overrides[get_session] = get_test_session
    
    async with factory() as session:
        reg_repo = SqliteRegistryRepository(session)
        src_repo = SqliteSourceRepository(session)
        schema_service = SchemaService(src_repo)
        service = RegistryService(reg_repo, src_repo, schema_service)
        
    # Session override is active
        
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
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
            
            # 3. Create Model
            fields = [
                LogicalField(logical_entity_id="", name="id", data_type=StandardDataType.INTEGER, is_primary_key=True, nullable=False),
                LogicalField(logical_entity_id="", name="fullName", data_type=StandardDataType.STRING, nullable=False),
                LogicalField(logical_entity_id="", name="emailAddress", data_type=StandardDataType.STRING, nullable=False),
                LogicalField(logical_entity_id="", name="Status", data_type=StandardDataType.STRING, nullable=True),
                LogicalField(logical_entity_id="", name="metadata", data_type=StandardDataType.JSON, nullable=True),
            ]
            student_ent = LogicalEntity(logical_model_id="", name="Student", fields=fields)
            model = await service.create_model("UniversityDomain", version="1.0.0", entities=[student_ent])
            student_entity = model.entities[0]
            id_field = student_entity.fields[0]
            
            # 4. Create initial mapping via API
            create_payload = {
                "logical_model_id": model.id,
                "source_id": source.id,
                "version": "1.0.0",
                "status": "DRAFT",
                "provenance": "USER",
                "entity_mappings": [
                    {
                        "logical_entity_id": student_entity.id,
                        "physical_entity_name": "users",
                        "physical_namespace": "public",
                        "field_mappings": [
                            {"logical_field_id": student_entity.fields[0].id, "physical_field_name": "id"},
                            {"logical_field_id": student_entity.fields[1].id, "physical_field_name": "full_name"},
                            {"logical_field_id": student_entity.fields[2].id, "physical_field_name": "email"},
                            {"logical_field_id": student_entity.fields[3].id, "physical_field_name": "is_active"},
                            {"logical_field_id": student_entity.fields[4].id, "physical_field_name": "metadata"},
                        ]
                    }
                ]
            }
            res = await client.post("/api/v1/registry/mappings", json=create_payload)
            print("POST /mappings status:", res.status_code)
            mapping_data = res.json()
            mapping_id = mapping_data["id"]
            print("Created mapping response:\n", json.dumps(mapping_data, indent=2))
            
            # 5. Send exact Flutter Edit payload to PUT /mappings/{id}
            # Notice Flutter sends `entity_mappings` with only `id -> id`
            edit_payload = {
                "version": "1.0.0",
                "entity_mappings": [
                    {
                        "logical_entity_id": student_entity.id,
                        "logical_entity_name": "Student",
                        "physical_entity_name": "users",
                        "physical_namespace": "public",
                        "field_mappings": [
                            {
                                "logical_field_id": id_field.id,
                                "logical_field_name": "id",
                                "physical_field_name": "id",
                            }
                        ]
                    }
                ]
            }
            res_put = await client.put(f"/api/v1/registry/mappings/{mapping_id}", json=edit_payload)
            print("\nPUT /mappings/{id} status:", res_put.status_code)
            put_data = res_put.json()
            print("PUT response:\n", json.dumps(put_data, indent=2))
            
            # 6. Call POST /mappings/{id}/validate
            res_val = await client.post(f"/api/v1/registry/mappings/{mapping_id}/validate")
            print("\nPOST /mappings/{id}/validate status:", res_val.status_code)
            val_data = res_val.json()
            print("Validate response:\n", json.dumps(val_data, indent=2))

if __name__ == "__main__":
    asyncio.run(run())
