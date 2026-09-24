"""Unit and integration tests for UpdateService and /api/v1/updates REST API."""

from pathlib import Path
import pytest
from httpx import ASGITransport, AsyncClient, Response
from fastapi import FastAPI

from altr_stream.application.update_service import UpdateService, get_update_service
from altr_stream.domain.semver import SemVer
from altr_stream.domain.updates import UpdateStatus, UpdateStatusState
from altr_stream.presentation.api.router import api_v1_router


@pytest.fixture
def mock_updates_dir(tmp_path: Path) -> Path:
    up_dir = tmp_path / "updates"
    up_dir.mkdir(parents=True, exist_ok=True)
    return up_dir


@pytest.fixture
def mock_github_releases():
    return [
        {
            "tag_name": "v0.13.1-alpha",
            "name": "Altr Stream 0.13.1-alpha",
            "published_at": "2026-09-24T00:00:00Z",
            "body": "Patch release with unified container",
            "prerelease": True,
            "html_url": "https://github.com/helloaltr/altr-stream/releases/tag/v0.13.1-alpha",
        },
        {
            "tag_name": "v0.13.2-alpha",
            "name": "Altr Stream 0.13.2-alpha",
            "published_at": "2026-09-24T06:00:00Z",
            "body": "Update system release",
            "prerelease": True,
            "html_url": "https://github.com/helloaltr/altr-stream/releases/tag/v0.13.2-alpha",
        },
        {
            "tag_name": "v1.0.0-beta",
            "name": "Altr Stream 1.0.0-beta",
            "published_at": "2026-09-25T00:00:00Z",
            "body": "First beta release",
            "prerelease": True,
            "html_url": "https://github.com/helloaltr/altr-stream/releases/tag/v1.0.0-beta",
        },
        {
            "tag_name": "v1.0.0",
            "name": "Altr Stream 1.0.0 GA",
            "published_at": "2026-10-01T00:00:00Z",
            "body": "Production General Availability",
            "prerelease": False,
            "html_url": "https://github.com/helloaltr/altr-stream/releases/tag/v1.0.0",
        },
    ]


@pytest.fixture
def update_service(mock_updates_dir: Path, mock_github_releases) -> UpdateService:
    # Custom mock transport to simulate GitHub Releases API
    def handler(request):
        if "releases" in str(request.url):
            return Response(200, json=mock_github_releases)
        return Response(404)

    mock_client = AsyncClient(transport=ASGITransport(app=FastAPI()))
    mock_client.get = lambda url, headers=None, timeout=None: AsyncClient(
        transport=httpx_transport_from_handler(handler)
    ).get(url, headers=headers, timeout=timeout)

    return UpdateService(
        updates_dir=mock_updates_dir,
        cache_ttl_sec=60.0,
    )


def httpx_transport_from_handler(handler):
    from httpx import MockTransport
    return MockTransport(handler)


@pytest.fixture
def app(mock_updates_dir: Path, mock_github_releases) -> FastAPI:
    test_app = FastAPI()
    test_app.include_router(api_v1_router)

    from httpx import MockTransport

    def handler(request):
        if "releases" in str(request.url):
            return Response(200, json=mock_github_releases)
        return Response(404)

    mock_transport = MockTransport(handler)
    mock_client = AsyncClient(transport=mock_transport)

    svc = UpdateService(
        updates_dir=mock_updates_dir,
        http_client=mock_client,
    )

    test_app.dependency_overrides[get_update_service] = lambda: svc
    return test_app


@pytest.fixture
async def client(app: FastAPI) -> AsyncClient:
    async with AsyncClient(
        transport=ASGITransport(app=app),
        base_url="http://testserver",
    ) as ac:
        yield ac


@pytest.mark.asyncio
async def test_update_check_endpoint_returns_direct_upgrade(client: AsyncClient):
    response = await client.get("/api/v1/updates/check")
    assert response.status_code == 200
    data = response.json()

    assert "current_version" in data
    assert data["update_available"] is True
    # In alpha channel, highest available release is 1.0.0 GA
    assert data["latest_version"] == "1.0.0"
    assert data["release"] is not None
    assert data["release"]["tag_name"] == "v1.0.0"


@pytest.mark.asyncio
async def test_update_check_with_channel_filter(client: AsyncClient):
    # If filtered to beta, must accept 1.0.0-beta and 1.0.0
    res_beta = await client.get("/api/v1/updates/check?channel=beta")
    assert res_beta.status_code == 200
    assert res_beta.json()["latest_version"] == "1.0.0"

    # Invalid channel returns 400
    res_bad = await client.get("/api/v1/updates/check?channel=nonexistent")
    assert res_bad.status_code == 400
    assert "Invalid channel" in res_bad.json()["detail"]


@pytest.mark.asyncio
async def test_update_apply_dispatches_intent_and_updates_status(client: AsyncClient, mock_updates_dir: Path):
    payload = {
        "target_version": "0.13.3-alpha",
        "channel": "alpha",
    }
    response = await client.post("/api/v1/updates/apply", json=payload)
    assert response.status_code == 202
    data = response.json()

    assert data["state"] == "requested"
    assert data["target_version"] == "0.13.3-alpha"
    assert data["request_id"] is not None

    # Verify atomic update-request.json file exists on disk
    req_file = mock_updates_dir / "update-request.json"
    assert req_file.is_file()

    # Verify atomic update-status.json file exists on disk
    status_file = mock_updates_dir / "update-status.json"
    assert status_file.is_file()

    # Query status endpoint
    status_res = await client.get("/api/v1/updates/status")
    assert status_res.status_code == 200
    status_data = status_res.json()
    assert status_data["state"] == "requested"
    assert status_data["target_version"] == "0.13.3-alpha"


@pytest.mark.asyncio
async def test_update_apply_rejects_downgrades_and_duplicates(client: AsyncClient):
    # Downgrade attempt
    payload_downgrade = {"target_version": "0.12.0"}
    res_downgrade = await client.post("/api/v1/updates/apply", json=payload_downgrade)
    assert res_downgrade.status_code == 400
    assert "must be strictly greater" in res_downgrade.json()["detail"]

    # Valid apply
    res_ok = await client.post("/api/v1/updates/apply", json={"target_version": "1.0.0"})
    assert res_ok.status_code == 202

    # Second apply while workflow is active should be rejected
    res_dup = await client.post("/api/v1/updates/apply", json={"target_version": "1.0.1"})
    assert res_dup.status_code == 400
    assert "already active" in res_dup.json()["detail"]
