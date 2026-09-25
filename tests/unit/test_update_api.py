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
            "tag_name": "v0.13.3-alpha",
            "name": "Altr Stream 0.13.3-alpha",
            "published_at": "2026-09-24T12:00:00Z",
            "body": "Distribution validation release",
            "prerelease": True,
            "html_url": "https://github.com/helloaltr/altr-stream/releases/tag/v0.13.3-alpha",
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
        "target_version": "0.13.5-alpha",
        "channel": "alpha",
    }
    response = await client.post("/api/v1/updates/apply", json=payload)
    assert response.status_code == 202
    data = response.json()

    assert data["state"] == "requested"
    assert data["target_version"] == "0.13.5-alpha"
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
    assert status_data["target_version"] == "0.13.5-alpha"


@pytest.mark.asyncio
async def test_update_service_direct_upgrade_0_13_2_to_0_13_3_alpha(mock_updates_dir: Path):
    import json
    from altr_stream.domain.updates import UpdateRequest
    # Node running 0.13.2-alpha updating to 0.13.3-alpha
    svc = UpdateService(updates_dir=mock_updates_dir, current_version="0.13.2-alpha")
    status = await svc.request_update("0.13.3-alpha")

    assert status.state == UpdateStatusState.REQUESTED
    assert status.target_version == "0.13.3-alpha"
    assert status.current_version == "0.13.2-alpha"

    # Verify written IPC request payload
    req_data = json.loads((mock_updates_dir / "update-request.json").read_text(encoding="utf-8"))
    req = UpdateRequest.from_dict(req_data)
    assert req.target_version == "0.13.3-alpha"
    assert req.current_version == "0.13.2-alpha"
    assert req.target_image == "ghcr.io/helloaltr/altr-stream:0.13.3-alpha"


@pytest.mark.asyncio
async def test_update_service_direct_upgrade_0_13_3_to_0_13_4_alpha(mock_updates_dir: Path):
    import json
    from altr_stream.domain.updates import UpdateRequest
    # Node running 0.13.3-alpha updating to 0.13.4-alpha
    svc = UpdateService(updates_dir=mock_updates_dir, current_version="0.13.3-alpha")
    status = await svc.request_update("0.13.4-alpha")

    assert status.state == UpdateStatusState.REQUESTED
    assert status.target_version == "0.13.4-alpha"
    assert status.current_version == "0.13.3-alpha"

    # Verify written IPC request payload
    req_data = json.loads((mock_updates_dir / "update-request.json").read_text(encoding="utf-8"))
    req = UpdateRequest.from_dict(req_data)
    assert req.target_version == "0.13.4-alpha"
    assert req.current_version == "0.13.3-alpha"
    assert req.target_image == "ghcr.io/helloaltr/altr-stream:0.13.4-alpha"


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


def test_is_stale_update_status_semantics():
    from altr_stream.domain.updates import UpdateStatus, UpdateStatusState, is_stale_update_status

    # 1. IDLE is never stale
    idle_status = UpdateStatus(
        state=UpdateStatusState.IDLE,
        current_version="0.13.2-alpha",
        target_version=None,
    )
    assert not is_stale_update_status(idle_status, "0.13.4-alpha")

    # 2. Obsolete failed transition (e.g., 0.13.2-alpha -> 0.13.3-alpha failed)
    failed_status = UpdateStatus(
        state=UpdateStatusState.FAILED,
        current_version="0.13.2-alpha",
        target_version="0.13.3-alpha",
        message="Failed to pull image.",
        error="docker pull failed: unauthorized",
    )
    # Stale when running 0.13.4-alpha (running > target and running != from)
    assert is_stale_update_status(failed_status, "0.13.4-alpha")
    assert failed_status.is_stale("0.13.4-alpha")

    # Stale when running 0.13.3-alpha (running == target)
    assert is_stale_update_status(failed_status, "0.13.3-alpha")

    # NOT stale when running 0.13.2-alpha (still on the failing version before target)
    assert not is_stale_update_status(failed_status, "0.13.2-alpha")

    # 3. Completed transition (0.13.2-alpha -> 0.13.3-alpha completed)
    completed_status = UpdateStatus(
        state=UpdateStatusState.COMPLETED,
        current_version="0.13.2-alpha",
        target_version="0.13.3-alpha",
        message="Update successful.",
    )
    # NOT stale on 0.13.3-alpha (just completed, running == target)
    assert not is_stale_update_status(completed_status, "0.13.3-alpha")
    # Stale on 0.13.4-alpha (running != target)
    assert is_stale_update_status(completed_status, "0.13.4-alpha")

    # 4. Active transition (0.13.2-alpha -> 0.13.3-alpha requested/applying)
    active_status = UpdateStatus(
        state=UpdateStatusState.APPLYING,
        current_version="0.13.2-alpha",
        target_version="0.13.3-alpha",
        progress_percent=50,
    )
    # Preserved/not stale when still running 0.13.2-alpha
    assert not is_stale_update_status(active_status, "0.13.2-alpha")
    # Stale if running node has already progressed beyond target (0.13.4-alpha)
    assert is_stale_update_status(active_status, "0.13.4-alpha")


@pytest.mark.asyncio
async def test_update_service_normalizes_stale_persisted_status(mock_updates_dir: Path):
    import json
    from altr_stream.domain.updates import UpdateStatus, UpdateStatusState

    # Simulate persisted stale failed status from 0.13.2-alpha -> 0.13.3-alpha
    stale_payload = {
        "state": "failed",
        "current_version": "0.13.2-alpha",
        "target_version": "0.13.3-alpha",
        "progress_percent": 0,
        "message": "Failed to pull image.",
        "error": "docker pull failed: unauthorized",
        "rollback_performed": False,
    }
    status_file = mock_updates_dir / "update-status.json"
    status_file.write_text(json.dumps(stale_payload), encoding="utf-8")

    # Running node is 0.13.4-alpha
    svc = UpdateService(updates_dir=mock_updates_dir, current_version="0.13.4-alpha")
    status = await svc.get_status()

    # Should be normalized to IDLE for the running node
    assert status.state == UpdateStatusState.IDLE
    assert status.current_version == "0.13.4-alpha"
    assert status.target_version is None
    assert status.error is None
    assert "System is up to date" in status.message

    # Disk status should also be normalized
    disk_data = json.loads(status_file.read_text(encoding="utf-8"))
    assert disk_data["state"] == "idle"
    assert disk_data["current_version"] == "0.13.4-alpha"


@pytest.mark.asyncio
async def test_api_status_normalizes_stale_failure_to_idle(
    client: AsyncClient, mock_updates_dir: Path
):
    import json

    # Write obsolete failure from 0.13.2-alpha -> 0.13.3-alpha
    stale_payload = {
        "state": "failed",
        "current_version": "0.13.2-alpha",
        "target_version": "0.13.3-alpha",
        "progress_percent": 0,
        "message": "Failed to pull image.",
        "error": "docker pull failed (1): unauthorized",
        "rollback_performed": False,
    }
    status_file = mock_updates_dir / "update-status.json"
    status_file.write_text(json.dumps(stale_payload), encoding="utf-8")

    # Query API (test app runs 0.13.4-alpha)
    res = await client.get("/api/v1/updates/status")
    assert res.status_code == 200
    data = res.json()
    assert data["state"] == "idle"
    assert data["current_version"] == "0.13.4-alpha"
    assert data["target_version"] is None
    assert data["error"] is None


@pytest.mark.asyncio
async def test_update_check_github_200_no_newer_release(mock_updates_dir: Path):
    from httpx import MockTransport

    # Running 1.0.0, available releases only up to 1.0.0
    releases_payload = [
        {"tag_name": "v0.13.4-alpha", "name": "0.13.4", "prerelease": True, "published_at": "2026-09-24T00:00:00Z"},
        {"tag_name": "v1.0.0", "name": "1.0.0", "prerelease": False, "published_at": "2026-09-25T00:00:00Z"},
    ]

    mock_client = AsyncClient(
        transport=MockTransport(lambda req: Response(200, json=releases_payload))
    )
    svc = UpdateService(
        updates_dir=mock_updates_dir,
        current_version="1.0.0",
        http_client=mock_client,
    )
    plan = await svc.check_for_updates()
    assert plan.check_available is True
    assert plan.update_available is False
    assert plan.target_version is None
    assert plan.error_code is None


@pytest.mark.asyncio
async def test_update_check_github_403_rate_limited(mock_updates_dir: Path):
    import time
    from httpx import MockTransport

    reset_time = int(time.time()) + 1800  # 30 mins in future
    headers = {
        "x-ratelimit-remaining": "0",
        "x-ratelimit-reset": str(reset_time),
    }

    mock_client = AsyncClient(
        transport=MockTransport(
            lambda req: Response(403, headers=headers, json={"message": "API rate limit exceeded"})
        )
    )
    svc = UpdateService(
        updates_dir=mock_updates_dir,
        current_version="0.13.3-alpha",
        http_client=mock_client,
    )
    plan = await svc.check_for_updates()
    assert plan.check_available is False
    assert plan.update_available is False
    assert plan.error_code == "github_rate_limited"
    assert "rate limited" in plan.message
    assert plan.retry_after is not None
    assert plan.retry_after > 0


@pytest.mark.asyncio
async def test_update_check_github_429_rate_limited(mock_updates_dir: Path):
    from httpx import MockTransport

    headers = {"retry-after": "120"}
    mock_client = AsyncClient(
        transport=MockTransport(
            lambda req: Response(429, headers=headers, json={"message": "Too many requests"})
        )
    )
    svc = UpdateService(
        updates_dir=mock_updates_dir,
        current_version="0.13.3-alpha",
        http_client=mock_client,
    )
    plan = await svc.check_for_updates()
    assert plan.check_available is False
    assert plan.update_available is False
    assert plan.error_code == "github_rate_limited"
    assert plan.retry_after == 120


@pytest.mark.asyncio
async def test_update_check_network_timeout(mock_updates_dir: Path):
    import httpx
    from httpx import MockTransport

    def timeout_handler(req):
        raise httpx.ReadTimeout("Connection timed out")

    mock_client = AsyncClient(transport=MockTransport(timeout_handler))
    svc = UpdateService(
        updates_dir=mock_updates_dir,
        current_version="0.13.3-alpha",
        http_client=mock_client,
    )
    plan = await svc.check_for_updates()
    assert plan.check_available is False
    assert plan.update_available is False
    assert plan.error_code == "network_timeout"
    assert "timed out" in plan.message


@pytest.mark.asyncio
async def test_update_check_github_500_unavailable(mock_updates_dir: Path):
    from httpx import MockTransport

    mock_client = AsyncClient(
        transport=MockTransport(lambda req: Response(500, text="Internal Server Error"))
    )
    svc = UpdateService(
        updates_dir=mock_updates_dir,
        current_version="0.13.3-alpha",
        http_client=mock_client,
    )
    plan = await svc.check_for_updates()
    assert plan.check_available is False
    assert plan.update_available is False
    assert plan.error_code == "github_api_unavailable"
    assert "500" in plan.message


@pytest.mark.asyncio
async def test_update_check_unexpected_json(mock_updates_dir: Path):
    from httpx import MockTransport

    # Non-list response
    mock_client = AsyncClient(
        transport=MockTransport(lambda req: Response(200, json={"error": "bad format"}))
    )
    svc = UpdateService(
        updates_dir=mock_updates_dir,
        current_version="0.13.3-alpha",
        http_client=mock_client,
    )
    plan = await svc.check_for_updates()
    assert plan.check_available is False
    assert plan.update_available is False
    assert plan.error_code == "github_api_unavailable"


@pytest.mark.asyncio
async def test_update_service_caching_behavior(mock_updates_dir: Path):
    from httpx import MockTransport

    call_count = 0

    def counting_handler(req):
        nonlocal call_count
        call_count += 1
        return Response(200, json=[
            {"tag_name": "v0.13.5-alpha", "name": "0.13.5", "prerelease": True, "published_at": "2026-09-25T00:00:00Z"}
        ])

    mock_client = AsyncClient(transport=MockTransport(counting_handler))
    svc = UpdateService(
        updates_dir=mock_updates_dir,
        current_version="0.13.3-alpha",
        http_client=mock_client,
        cache_ttl_sec=60.0,
    )

    # First check: live fetch
    res1 = await svc.fetch_releases_result()
    assert res1.is_cached is False
    assert len(res1.releases) == 1
    assert call_count == 1

    # Second check: within TTL -> cached
    res2 = await svc.fetch_releases_result()
    assert res2.is_cached is True
    assert len(res2.releases) == 1
    assert call_count == 1  # No additional network call

    # Force refresh -> live fetch
    res3 = await svc.fetch_releases_result(force_refresh=True)
    assert res3.is_cached is False
    assert call_count == 2


@pytest.mark.asyncio
async def test_api_check_returns_check_available_false_on_rate_limit(mock_updates_dir: Path):
    from httpx import MockTransport
    from altr_stream.presentation.api.router import api_v1_router

    test_app = FastAPI()
    test_app.include_router(api_v1_router)

    headers = {"retry-after": "60"}
    mock_client = AsyncClient(
        transport=MockTransport(
            lambda req: Response(403, headers=headers, json={"message": "rate limit exceeded"})
        )
    )
    svc = UpdateService(
        updates_dir=mock_updates_dir,
        current_version="0.13.3-alpha",
        http_client=mock_client,
    )
    test_app.dependency_overrides[get_update_service] = lambda: svc

    async with AsyncClient(transport=ASGITransport(app=test_app), base_url="http://testserver") as ac:
        res = await ac.get("/api/v1/updates/check")
        assert res.status_code == 200
        data = res.json()
        assert data["check_available"] is False
        assert data["update_available"] is False
        assert data["error_code"] == "github_rate_limited"
        assert data["retry_after"] == 60
        assert "rate limited" in data["message"]


