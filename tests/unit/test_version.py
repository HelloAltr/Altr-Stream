"""Unit tests for Phase 1 unified versioning."""

import importlib.metadata
import pytest
from httpx import ASGITransport, AsyncClient

import altr_stream
from altr_stream.__version__ import VERSION, __version__
from altr_stream.config import settings
from altr_stream.main import app


def test_canonical_version_constant():
    """Verify the canonical version string matches 0.13.4-alpha across definitions."""
    assert __version__ == "0.13.4-alpha"
    assert VERSION == "0.13.4-alpha"
    assert altr_stream.__version__ == "0.13.4-alpha"


def test_package_metadata_version():
    """Verify package metadata derived via Hatchling matches canonical version."""
    metadata_version = importlib.metadata.version("altr-stream")
    assert metadata_version == "0.13.4-alpha"


def test_settings_app_version():
    """Verify application configuration settings consume canonical version."""
    assert settings.app_version == "0.13.4-alpha"


@pytest.mark.asyncio
async def test_api_version_endpoints():
    """Verify FastAPI root and health endpoints expose canonical version."""
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        # Root endpoint
        root_res = await client.get("/")
        assert root_res.status_code == 200
        root_data = root_res.json()
        assert root_data["version"] == "0.13.4-alpha"

        # Health endpoint
        health_res = await client.get("/api/v1/health")
        assert health_res.status_code == 200
        health_data = health_res.json()
        assert health_data["version"] == "0.13.4-alpha"
        assert health_data["status"] == "healthy"


def test_settings_version_override_explicit_and_env(monkeypatch):
    """Verify Settings supports explicit app_version and simulated_version overrides."""
    from altr_stream.config import Settings

    # Case 1: Empty string or whitespace in app_version safely defaults to __version__
    s_empty = Settings(app_version="   ")
    assert s_empty.app_version == "0.13.4-alpha"

    # Case 2: Explicit app_version override
    s_app = Settings(app_version="0.13.2-alpha")
    assert s_app.app_version == "0.13.2-alpha"

    # Case 3: Explicit simulated_version override
    s_sim = Settings(simulated_version="0.13.2-alpha")
    assert s_sim.app_version == "0.13.2-alpha"

    # Case 4: Environment variable ALTR_STREAM_APP_VERSION
    monkeypatch.setenv("ALTR_STREAM_APP_VERSION", "0.13.2-alpha")
    monkeypatch.delenv("ALTR_STREAM_SIMULATED_VERSION", raising=False)
    s_env_app = Settings()
    assert s_env_app.app_version == "0.13.2-alpha"

    # Case 5: Environment variable ALTR_STREAM_SIMULATED_VERSION
    monkeypatch.delenv("ALTR_STREAM_APP_VERSION", raising=False)
    monkeypatch.setenv("ALTR_STREAM_SIMULATED_VERSION", "0.13.2-alpha")
    s_env_sim = Settings()
    assert s_env_sim.app_version == "0.13.2-alpha"

    # Case 6: Empty string from environment (e.g. docker compose unset default)
    monkeypatch.setenv("ALTR_STREAM_APP_VERSION", "")
    monkeypatch.setenv("ALTR_STREAM_SIMULATED_VERSION", "")
    s_env_empty = Settings()
    assert s_env_empty.app_version == "0.13.4-alpha"


@pytest.mark.asyncio
async def test_health_endpoint_and_update_service_simulation(monkeypatch, tmp_path):
    """Verify that when simulated as 0.13.2-alpha, health returns 0.13.2-alpha and update discovery finds 0.13.3-alpha."""
    from altr_stream.application.update_service import UpdateService
    from altr_stream.domain.semver import ReleaseInfo, SemVer

    # Override settings.app_version to simulate 0.13.2-alpha
    monkeypatch.setattr(settings, "app_version", "0.13.2-alpha")

    # 1. Health endpoint must report simulated 0.13.2-alpha
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        health_res = await client.get("/api/v1/health")
        assert health_res.status_code == 200
        health_data = health_res.json()
        assert health_data["version"] == "0.13.2-alpha"
        assert health_data["status"] == "healthy"

    # 2. Update service must discover 0.13.3-alpha
    update_svc = UpdateService(updates_dir=tmp_path / "updates")
    assert update_svc.current_semver == SemVer.parse("0.13.2-alpha")

    # Mock release fetch matching current GitHub releases (where 0.13.3-alpha is the latest published release)
    sample_releases = [
        ReleaseInfo(
            version=SemVer.parse("0.13.2-alpha"),
            tag_name="v0.13.2-alpha",
            name="Altr Stream 0.13.2-alpha",
            published_at="2026-09-24T06:00:00Z",
            body="v0.13.2",
            prerelease=True,
            html_url="https://github.com/helloaltr/altr-stream/releases/tag/v0.13.2-alpha",
        ),
        ReleaseInfo(
            version=SemVer.parse("0.13.3-alpha"),
            tag_name="v0.13.3-alpha",
            name="Altr Stream 0.13.3-alpha",
            published_at="2026-09-24T12:00:00Z",
            body="v0.13.3",
            prerelease=True,
            html_url="https://github.com/helloaltr/altr-stream/releases/tag/v0.13.3-alpha",
        ),
    ]
    async def mock_fetch(force_refresh=False):
        return sample_releases

    monkeypatch.setattr(update_svc, "fetch_releases", mock_fetch)

    plan = await update_svc.check_for_updates()
    assert plan.update_available is True
    assert plan.target_version == SemVer.parse("0.13.3-alpha")
