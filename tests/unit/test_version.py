"""Unit tests for Phase 1 unified versioning."""

import importlib.metadata
import pytest
from httpx import ASGITransport, AsyncClient

import altr_stream
from altr_stream.__version__ import VERSION, __version__
from altr_stream.config import settings
from altr_stream.main import app


def test_canonical_version_constant():
    """Verify the canonical version string matches 0.13.3-alpha across definitions."""
    assert __version__ == "0.13.3-alpha"
    assert VERSION == "0.13.3-alpha"
    assert altr_stream.__version__ == "0.13.3-alpha"


def test_package_metadata_version():
    """Verify package metadata derived via Hatchling matches canonical version."""
    metadata_version = importlib.metadata.version("altr-stream")
    assert metadata_version == "0.13.3-alpha"


def test_settings_app_version():
    """Verify application configuration settings consume canonical version."""
    assert settings.app_version == "0.13.3-alpha"


@pytest.mark.asyncio
async def test_api_version_endpoints():
    """Verify FastAPI root and health endpoints expose canonical version."""
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        # Root endpoint
        root_res = await client.get("/")
        assert root_res.status_code == 200
        root_data = root_res.json()
        assert root_data["version"] == "0.13.3-alpha"

        # Health endpoint
        health_res = await client.get("/api/v1/health")
        assert health_res.status_code == 200
        health_data = health_res.json()
        assert health_data["version"] == "0.13.3-alpha"
        assert health_data["status"] == "healthy"
