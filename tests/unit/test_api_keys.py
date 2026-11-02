"""Unit tests for API key generation, hashing, verification, and management routes."""

import pytest
from httpx import ASGITransport, AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

from altr_stream.application.api_key_service import ApiKeyService, hash_api_key
from altr_stream.infrastructure.database.models import Base
from altr_stream.main import create_app
from altr_stream.presentation.api.security import get_session


@pytest.fixture
async def async_test_session():
    """Create in-memory SQLite database session for unit testing."""
    engine = create_async_engine("sqlite+aiosqlite:///:memory:", echo=False)
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)

    session_maker = async_sessionmaker(bind=engine, class_=AsyncSession, expire_on_commit=False)
    async with session_maker() as session:
        yield session

    await engine.dispose()


@pytest.mark.asyncio
async def test_api_key_service_crud_and_scopes(async_test_session: AsyncSession):
    service = ApiKeyService(async_test_session)

    # 1. Generate Key
    raw_key, model = await service.generate_key(
        name="Developer Laptop",
        scopes=["read", "write"],
        expires_in_days=30,
    )
    assert raw_key.startswith("altr_live_")
    assert model.name == "Developer Laptop"
    assert model.is_active is True
    assert "read" in model.scopes
    assert "write" in model.scopes
    assert model.key_hash == hash_api_key(raw_key)

    # 2. Verify Key
    verified = await service.verify_key(raw_key, required_scope="read")
    assert verified is not None
    assert verified.id == model.id

    # 3. Verify Key Scope Denied (admin required but key only has read, write)
    denied = await service.verify_key(raw_key, required_scope="admin")
    assert denied is None

    # 4. List Keys
    keys = await service.list_keys()
    assert len(keys) == 1
    assert keys[0].id == model.id

    # 5. Revoke Key
    revoked = await service.revoke_key(model.id)
    assert revoked is True

    # 6. Verify Revoked Key Fails
    verified_after_revoke = await service.verify_key(raw_key)
    assert verified_after_revoke is None


@pytest.mark.asyncio
async def test_api_key_endpoints(async_test_session: AsyncSession):
    app = create_app()

    # Override get_session dependency to use test session
    async def override_get_session():
        yield async_test_session

    app.dependency_overrides[get_session] = override_get_session

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        # 1. List keys initially empty
        res = await client.get("/api/v1/auth/keys")
        assert res.status_code == 200
        assert res.json() == []

        # 2. Create new key
        create_res = await client.post(
            "/api/v1/auth/keys",
            json={
                "name": "Integration Test Key",
                "scopes": ["read", "write"],
                "expires_in_days": 7,
            },
        )
        assert create_res.status_code == 201
        data = create_res.json()
        assert "raw_key" in data
        assert data["raw_key"].startswith("altr_live_")
        key_id = data["id"]
        raw_key = data["raw_key"]

        # 3. Verify Key endpoint
        verify_res = await client.post(
            "/api/v1/auth/keys/verify",
            json={"key": raw_key},
        )
        assert verify_res.status_code == 200
        assert verify_res.json()["valid"] is True
        assert verify_res.json()["name"] == "Integration Test Key"

        # 4. List keys shows 1 key
        list_res = await client.get("/api/v1/auth/keys")
        assert list_res.status_code == 200
        assert len(list_res.json()) == 1

        # 5. Revoke key
        del_res = await client.delete(f"/api/v1/auth/keys/{key_id}")
        assert del_res.status_code == 200
        assert del_res.json()["status"] == "revoked"

        # 6. Verify Key endpoint returns false now
        verify_after = await client.post(
            "/api/v1/auth/keys/verify",
            json={"key": raw_key},
        )
        assert verify_after.status_code == 200
        assert verify_after.json()["valid"] is False


@pytest.mark.asyncio
async def test_altrql_and_queries_require_api_key_when_active_keys_exist(async_test_session: AsyncSession):
    app = create_app()

    async def override_get_session():
        yield async_test_session

    app.dependency_overrides[get_session] = override_get_session

    service = ApiKeyService(async_test_session)
    read_key, _ = await service.generate_key(name="ReadOnly Token", scopes=["read"])
    write_key, _ = await service.generate_key(name="Write Token", scopes=["read", "write"])

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        # 1. Unauthenticated request to /api/v1/altrql/execute is rejected with 401
        res_no_auth = await client.post(
            "/api/v1/altrql/execute",
            json={"query": "GET users;", "source_id": None},
        )
        assert res_no_auth.status_code == 401
        assert "Missing API key" in res_no_auth.json()["detail"]

        # 2. Invalid API key is rejected with 403
        res_bad_key = await client.post(
            "/api/v1/altrql/execute",
            json={"query": "GET users;", "source_id": None},
            headers={"X-Altr-API-Key": "altr_live_sec_invalid_key_123"},
        )
        assert res_bad_key.status_code == 403

        # 3. Valid read key passes auth on read query (returns 200 with result/parsing structure)
        res_valid_read = await client.post(
            "/api/v1/altrql/execute",
            json={"query": "GET users;", "source_id": None},
            headers={"X-Altr-API-Key": read_key},
        )
        assert res_valid_read.status_code == 200

        # 4. Bearer authorization header also works
        res_bearer = await client.post(
            "/api/v1/altrql/execute",
            json={"query": "GET users;", "source_id": None},
            headers={"Authorization": f"Bearer {read_key}"},
        )
        assert res_bearer.status_code == 200

        # 5. Native /queries/execute also requires API key
        query_no_auth = await client.post(
            "/api/v1/queries/execute",
            json={"query": "SELECT 1;", "source_id": "non_existent"},
        )
        assert query_no_auth.status_code == 401

        # 6. Dashboard console requests with X-Altr-Client header execute without API key
        res_dashboard = await client.post(
            "/api/v1/altrql/execute",
            json={"query": "GET users;", "source_id": None},
            headers={"X-Altr-Client": "web-dashboard"},
        )
        assert res_dashboard.status_code == 200


