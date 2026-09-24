"""Unit tests for static asset serving and Flutter Web SPA routing."""

from pathlib import Path
import pytest
from fastapi.testclient import TestClient
from fastapi import FastAPI

from altr_stream.presentation.web import register_static_and_spa
from altr_stream.presentation.api.router import api_v1_router


@pytest.fixture
def mock_static_dir(tmp_path: Path) -> Path:
    """Create a temporary static assets directory mimicking compiled Flutter Web."""
    static = tmp_path / "static"
    static.mkdir()
    (static / "index.html").write_text("<!DOCTYPE html><html><body>Flutter App</body></html>")
    (static / "flutter_bootstrap.js").write_text("// bootstrap")
    (static / "main.dart.js").write_text("// main compiled js")
    assets_dir = static / "assets"
    assets_dir.mkdir()
    (assets_dir / "Font.ttf").write_text("dummy font")
    return static


@pytest.fixture
def app_with_static(mock_static_dir: Path) -> FastAPI:
    """Create a FastAPI test app with API router and static serving."""
    test_app = FastAPI()
    test_app.include_router(api_v1_router)
    register_static_and_spa(test_app, static_dir=mock_static_dir)
    return test_app


@pytest.fixture
def client_with_static(app_with_static: FastAPI) -> TestClient:
    return TestClient(app_with_static)


@pytest.fixture
def client_without_static(tmp_path: Path) -> TestClient:
    test_app = FastAPI()
    test_app.include_router(api_v1_router)
    non_existent = tmp_path / "does_not_exist"
    register_static_and_spa(test_app, static_dir=non_existent)
    return TestClient(test_app)


def test_root_returns_json_by_default(client_with_static: TestClient) -> None:
    response = client_with_static.get("/")
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "healthy"
    assert "version" in data


def test_root_returns_index_html_when_html_accepted(client_with_static: TestClient) -> None:
    response = client_with_static.get("/", headers={"Accept": "text/html,application/xhtml+xml"})
    assert response.status_code == 200
    assert "text/html" in response.headers["content-type"]
    assert "Flutter App" in response.text
    assert "no-cache" in response.headers.get("cache-control", "")


def test_serves_exact_static_files(client_with_static: TestClient) -> None:
    # Bootstrap file with no-cache
    resp1 = client_with_static.get("/flutter_bootstrap.js")
    assert resp1.status_code == 200
    assert resp1.text == "// bootstrap"
    assert "no-cache" in resp1.headers.get("cache-control", "")

    # Main js with immutable cache
    resp2 = client_with_static.get("/main.dart.js")
    assert resp2.status_code == 200
    assert resp2.text == "// main compiled js"
    assert "immutable" in resp2.headers.get("cache-control", "")

    # Subdirectory file
    resp3 = client_with_static.get("/assets/Font.ttf")
    assert resp3.status_code == 200
    assert resp3.text == "dummy font"


def test_spa_subroutes_fallback_to_index_html(client_with_static: TestClient) -> None:
    # Deep client-side routes should return index.html
    for path in ["/sources", "/registry", "/settings", "/analytics/overview"]:
        resp = client_with_static.get(path)
        assert resp.status_code == 200
        assert "text/html" in resp.headers["content-type"]
        assert "Flutter App" in resp.text


def test_api_routes_never_intercepted_by_spa(client_with_static: TestClient) -> None:
    # Existing API route
    resp = client_with_static.get("/api/v1/health")
    assert resp.status_code == 200
    assert resp.json()["status"] == "healthy"

    # Non-existent API route must return 404 JSON, NOT index.html!
    resp_404 = client_with_static.get("/api/v1/nonexistent_route")
    assert resp_404.status_code == 404
    assert resp_404.headers["content-type"] == "application/json"
    assert resp_404.json() == {"detail": "Not Found"}

    # Another api subroute
    resp_api_404 = client_with_static.get("/api/unknown")
    assert resp_api_404.status_code == 404
    assert resp_api_404.headers["content-type"] == "application/json"


def test_missing_static_file_returns_404(client_with_static: TestClient) -> None:
    # Non-existent file with extension should return 404 JSON, not index.html
    resp = client_with_static.get("/missing_script.js")
    assert resp.status_code == 404
    assert resp.headers["content-type"] == "application/json"


def test_path_traversal_protection(client_with_static: TestClient, tmp_path: Path) -> None:
    # Try to access a file outside static dir
    secret_file = tmp_path / "secret.txt"
    secret_file.write_text("super_secret")

    resp = client_with_static.get("/../secret.txt")
    # Should either be 404 or not return secret
    assert "super_secret" not in resp.text


def test_when_static_dir_missing(client_without_static: TestClient) -> None:
    # When static assets don't exist, root still returns JSON
    resp = client_without_static.get("/", headers={"Accept": "text/html"})
    assert resp.status_code == 200
    assert resp.json()["status"] == "healthy"

    # API routes still work
    resp_api = client_without_static.get("/api/v1/health")
    assert resp_api.status_code == 200
