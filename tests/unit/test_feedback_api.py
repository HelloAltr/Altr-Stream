"""Unit and integration tests for Feedback API routes, AltrFeedbackClient, and configuration."""

import json
import logging
from pathlib import Path
from typing import Any

import httpx
import pytest
from httpx import ASGITransport, AsyncClient, MockTransport, Response

from altr_stream.application.feedback_service import FeedbackService
from altr_stream.config import Settings, settings
from altr_stream.infrastructure.feedback_client import (
    AltrFeedbackClient,
    FeedbackAuthError,
    FeedbackBadRequestError,
    FeedbackDuplicateError,
    FeedbackNotConfiguredError,
    FeedbackRateLimitError,
    FeedbackTimeoutError,
    FeedbackUnavailableError,
    FeedbackUpstreamError,
)
from altr_stream.main import app
from altr_stream.presentation.api.routes.feedback import get_feedback_service


# ==============================================================================
# CONFIGURATION & SECRET SAFETY TESTS
# ==============================================================================

def test_config_loads_feedback_defaults():
    """Verify default feedback service URL and None api key when not configured."""
    custom_settings = Settings(
        db_user="test",
        db_password="password",
        secret_key="test_secret",
        feedback_service_url="https://altr-feedback.onrender.com",
        feedback_api_key=None,
    )
    assert custom_settings.feedback_service_url == "https://altr-feedback.onrender.com"
    assert custom_settings.feedback_api_key is None


def test_config_loads_altr_feedback_api_key(monkeypatch):
    """Verify ALTR_FEEDBACK_API_KEY environment variable is loaded."""
    monkeypatch.setenv("ALTR_FEEDBACK_API_KEY", "test-key-12345")
    custom_settings = Settings(
        db_user="test",
        db_password="password",
        secret_key="test_secret",
    )
    assert custom_settings.feedback_api_key == "test-key-12345"


def test_config_loads_feedback_service_url(monkeypatch):
    """Verify ALTR_STREAM_FEEDBACK_SERVICE_URL environment variable is loaded."""
    monkeypatch.setenv("ALTR_STREAM_FEEDBACK_SERVICE_URL", "https://custom-feedback.internal")
    custom_settings = Settings(
        db_user="test",
        db_password="password",
        secret_key="test_secret",
    )
    assert custom_settings.feedback_service_url == "https://custom-feedback.internal"


def test_env_example_contains_no_real_secrets():
    """Verify that .env.example exists and contains no real secrets or tokens."""
    repo_root = Path(__file__).resolve().parent.parent.parent
    env_example = repo_root / ".env.example"
    assert env_example.exists(), ".env.example must exist at repository root"

    content = env_example.read_text(encoding="utf-8")
    assert "ALTR_STREAM_FEEDBACK_SERVICE_URL" in content
    assert "ALTR_FEEDBACK_API_KEY" in content

    # Ensure no actual key value is populated
    for line in content.splitlines():
        if line.startswith("ALTR_FEEDBACK_API_KEY"):
            val = line.split("=", 1)[1].strip()
            assert val == "", f".env.example has a non-empty API key: {val}"


# ==============================================================================
# ALTR FEEDBACK CLIENT TESTS
# ==============================================================================

@pytest.mark.asyncio
async def test_client_unconfigured_raises_error():
    """Verify AltrFeedbackClient raises FeedbackNotConfiguredError when service URL is empty."""
    client = AltrFeedbackClient(service_url="")
    assert not client.is_configured
    with pytest.raises(FeedbackNotConfiguredError, match="not configured"):
        await client.submit_feedback({"title": "Test", "message": "Test"})


@pytest.mark.asyncio
async def test_client_public_beta_without_api_key_submits_without_authorization_header():
    """Verify Public Beta mode submits without Authorization and without X-Installation-ID."""
    captured_requests = []

    def mock_handler(request: httpx.Request) -> Response:
        captured_requests.append(request)
        return Response(
            201,
            json={
                "success": True,
                "repository": "HelloAltr/Altr-Stream",
                "issue_number": 88,
                "url": "https://github.com/HelloAltr/Altr-Stream/issues/88",
            },
        )

    mock_http = httpx.AsyncClient(transport=MockTransport(mock_handler))
    client = AltrFeedbackClient(
        api_key=None,
        service_url="https://altr-feedback.onrender.com",
        http_client=mock_http,
        timeout=30.0,
    )

    payload = {"service": "altr-stream", "category": "bug", "title": "T", "message": "M"}
    result = await client.submit_feedback(payload)

    assert result["success"] is True
    assert result["issue_number"] == 88
    assert result["url"] == "https://github.com/HelloAltr/Altr-Stream/issues/88"

    assert len(captured_requests) == 1
    req = captured_requests[0]
    assert req.url == "https://altr-feedback.onrender.com/api/v1/feedback"
    assert "Authorization" not in req.headers
    assert "X-Installation-ID" not in req.headers
    assert req.headers["Content-Type"] == "application/json"

    sent_body = json.loads(req.content.decode("utf-8"))
    assert "installation_id" not in sent_body
    assert client.timeout == 30.0

    await mock_http.aclose()


@pytest.mark.asyncio
async def test_client_priority_mode_successful_dispatch():
    """Verify Priority mode sends Authorization Bearer header when api_key is configured."""
    captured_requests = []

    def mock_handler(request: httpx.Request) -> Response:
        captured_requests.append(request)
        return Response(
            201,
            json={
                "success": True,
                "repository": "HelloAltr/Altr-Stream",
                "issue_number": 99,
                "url": "https://github.com/HelloAltr/Altr-Stream/issues/99",
            },
        )

    mock_http = httpx.AsyncClient(transport=MockTransport(mock_handler))
    client = AltrFeedbackClient(
        api_key="secret-api-key-xyz",
        service_url="https://altr-feedback.onrender.com",
        http_client=mock_http,
    )

    payload = {"service": "altr-stream", "category": "bug", "title": "T", "message": "M"}
    result = await client.submit_feedback(payload)

    assert result["success"] is True
    assert len(captured_requests) == 1
    req = captured_requests[0]
    assert req.headers["Authorization"] == "Bearer secret-api-key-xyz"
    await mock_http.aclose()


@pytest.mark.asyncio
async def test_client_upstream_error_mappings():
    """Verify HTTP status codes map to specific typed exceptions."""
    cases = [
        (400, FeedbackBadRequestError),
        (401, FeedbackAuthError),
        (409, FeedbackDuplicateError),
        (429, FeedbackRateLimitError),
        (502, FeedbackUpstreamError),
        (503, FeedbackUnavailableError),
    ]

    for status_code, exc_type in cases:
        def handler(request: httpx.Request) -> Response:
            return Response(status_code, text="error occurred")

        mock_http = httpx.AsyncClient(transport=MockTransport(handler))
        client = AltrFeedbackClient(api_key="key", http_client=mock_http)
        with pytest.raises(exc_type):
            await client.submit_feedback({"title": "T", "message": "M"})
        await mock_http.aclose()


@pytest.mark.asyncio
async def test_client_timeout_raises_timeout_error():
    """Verify timeout and network errors raise FeedbackTimeoutError."""
    def handler(request: httpx.Request) -> Response:
        raise httpx.ConnectTimeout("Connection timed out")

    mock_http = httpx.AsyncClient(transport=MockTransport(handler))
    client = AltrFeedbackClient(api_key="key", http_client=mock_http)
    with pytest.raises(FeedbackTimeoutError, match="timed out"):
        await client.submit_feedback({"title": "T", "message": "M"})
    await mock_http.aclose()


# ==============================================================================
# API ROUTE TESTS (POST /api/v1/feedback)
# ==============================================================================

@pytest.mark.asyncio
async def test_feedback_submit_unconfigured_service_url_returns_503(monkeypatch):
    """Verify endpoint returns 503 when service URL is empty."""
    monkeypatch.setattr(settings, "feedback_service_url", "")
    custom_service = FeedbackService(feedback_client=AltrFeedbackClient(service_url=""))

    app.dependency_overrides[get_feedback_service] = lambda: custom_service

    try:
        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
            payload = {
                "category": "Bug",
                "summary": "Source connection drops on heavy load",
                "message": "When running high concurrency queries, the PostgreSQL pool drops connections.",
            }
            res = await client.post("/api/v1/feedback", json=payload)
            assert res.status_code == 503
            data = res.json()
            assert "Feedback service is not configured on this node." in data["detail"]
    finally:
        app.dependency_overrides.pop(get_feedback_service, None)


@pytest.mark.asyncio
async def test_feedback_submit_validation_errors():
    """Verify validation on empty fields, short summary, and invalid categories."""
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        # Invalid category
        res = await client.post("/api/v1/feedback", json={
            "category": "InvalidUnknownCategory",
            "summary": "Valid summary",
            "message": "Valid message",
        })
        assert res.status_code == 400

        # Short summary (<3 chars)
        res = await client.post("/api/v1/feedback", json={
            "category": "Bug",
            "summary": "ab",
            "message": "Valid message",
        })
        assert res.status_code == 422


@pytest.mark.asyncio
async def test_feedback_submit_public_beta_successful_dispatch():
    """Verify Public Beta dispatch is stateless, constructs expected payload, and sends no auth header."""
    captured_payloads = []
    captured_requests = []

    def mock_handler(request: httpx.Request) -> Response:
        captured_requests.append(request)
        body = json.loads(request.content.decode("utf-8"))
        captured_payloads.append(body)
        return Response(
            201,
            json={
                "success": True,
                "repository": "HelloAltr/Altr-Stream",
                "issue_number": 42,
                "url": "https://github.com/HelloAltr/Altr-Stream/issues/42",
            },
        )

    mock_client = httpx.AsyncClient(transport=MockTransport(mock_handler))
    fb_client = AltrFeedbackClient(
        api_key=None,
        http_client=mock_client,
    )
    custom_service = FeedbackService(feedback_client=fb_client)

    app.dependency_overrides[get_feedback_service] = lambda: custom_service

    try:
        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
            payload = {
                "category": "Bug",
                "summary": "UI rendering issue on Safari with postgresql://user:mypassword@db:5432/test",
                "message": "The live metrics cards overflow on Safari 17. Token=ghp_secrettokenhere1234567890abcdef",
                "contact": "@tester",
                "include_diagnostics": True,
                "diagnostics": {"browser": "Safari 17", "db_password": "supersecretpassword"},
                "client_platform": "Web",
            }
            res = await client.post("/api/v1/feedback", json=payload)
            assert res.status_code == 201
            data = res.json()
            assert data["status"] == "submitted"
            assert data["issue_number"] == 42
            assert data["issue_url"] == "https://github.com/HelloAltr/Altr-Stream/issues/42"
            assert data["html_url"] == "https://github.com/HelloAltr/Altr-Stream/issues/42"
            assert "Issue #42" in data["message"]

            # Verify external contract received by Altr Feedback
            assert len(captured_payloads) == 1
            ext_payload = captured_payloads[0]
            assert ext_payload["service"] == "altr-stream"
            assert ext_payload["category"] == "bug"
            assert ext_payload["severity"] == "medium"
            assert ext_payload["source"]["component"] == "node"
            assert ext_payload["source"]["version"] == settings.app_version
            assert "installation_id" not in ext_payload

            req = captured_requests[0]
            assert "Authorization" not in req.headers
            assert "X-Installation-ID" not in req.headers

            # Verify sanitization
            assert "mypassword" not in ext_payload["title"]
            assert "postgresql://user:********@db:5432/test" in ext_payload["title"]
            assert "ghp_secrettokenhere" not in ext_payload["message"]
            assert "[REDACTED_SECRET]" in ext_payload["message"]

            # Verify context and diagnostics
            assert ext_payload["context"]["contact"] == "@tester"
            assert ext_payload["context"]["client_platform"] == "Web"
            assert ext_payload["context"]["diagnostics"]["browser"] == "Safari 17"
            assert ext_payload["context"]["diagnostics"]["db_password"] == "********"
            assert "supersecretpassword" not in json.dumps(ext_payload)
    finally:
        app.dependency_overrides.pop(get_feedback_service, None)
        await mock_client.aclose()


@pytest.mark.asyncio
async def test_feedback_submit_diagnostics_omitted_when_not_consented():
    """Verify diagnostics are strictly omitted from context when include_diagnostics is False."""
    captured_payloads = []

    def mock_handler(request: httpx.Request) -> Response:
        body = json.loads(request.content.decode("utf-8"))
        captured_payloads.append(body)
        return Response(201, json={"success": True, "issue_number": 99, "url": "https://issue/99"})

    mock_client = httpx.AsyncClient(transport=MockTransport(mock_handler))
    fb_client = AltrFeedbackClient(api_key=None, http_client=mock_client)
    custom_service = FeedbackService(feedback_client=fb_client)

    app.dependency_overrides[get_feedback_service] = lambda: custom_service

    try:
        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
            payload = {
                "category": "Feature Request",
                "summary": "Add Parquet export support",
                "message": "Exporting query results directly to Apache Parquet would be faster.",
                "include_diagnostics": False,
                "diagnostics": {"os": "Linux", "secret_token": "leak"},
            }
            res = await client.post("/api/v1/feedback", json=payload)
            assert res.status_code == 201

            ext_payload = captured_payloads[0]
            assert ext_payload["category"] == "feature_request"
            assert "diagnostics" not in ext_payload["context"]
    finally:
        app.dependency_overrides.pop(get_feedback_service, None)
        await mock_client.aclose()


@pytest.mark.asyncio
async def test_feedback_submit_upstream_error_codes():
    """Verify upstream status codes are translated to expected local HTTP codes and messages."""
    error_mappings = [
        (400, 400, "Invalid feedback request. Please verify your message."),
        (401, 503, "Feedback service authentication failed."),
        (409, 409, "Duplicate feedback submission detected. Please wait before resubmitting."),
        (429, 429, "Feedback submission limit reached. Please try again later."),
        (502, 502, "Unable to submit feedback right now. Please try again later."),
        (503, 503, "Feedback service is temporarily unavailable. Please try again shortly."),
    ]

    for upstream_code, expected_status, expected_msg in error_mappings:
        def handler(request: httpx.Request) -> Response:
            return Response(upstream_code, text="upstream error detail")

        mock_client = httpx.AsyncClient(transport=MockTransport(handler))
        fb_client = AltrFeedbackClient(api_key=None, http_client=mock_client)
        custom_service = FeedbackService(feedback_client=fb_client)
        app.dependency_overrides[get_feedback_service] = lambda: custom_service

        try:
            async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
                res = await client.post("/api/v1/feedback", json={
                    "category": "General",
                    "summary": "Testing error responses",
                    "message": "Detailed test message for status code mappings.",
                })
                assert res.status_code == expected_status
                assert res.json()["detail"] == expected_msg
        finally:
            app.dependency_overrides.pop(get_feedback_service, None)
            await mock_client.aclose()


@pytest.mark.asyncio
async def test_feedback_submit_timeout_returns_504():
    """Verify network timeout returns 504 with clear message."""
    def timeout_handler(request: httpx.Request) -> Response:
        raise httpx.TimeoutException("Connection timed out")

    mock_client = httpx.AsyncClient(transport=MockTransport(timeout_handler))
    fb_client = AltrFeedbackClient(api_key=None, http_client=mock_client)
    custom_service = FeedbackService(feedback_client=fb_client)

    app.dependency_overrides[get_feedback_service] = lambda: custom_service

    try:
        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
            res = await client.post("/api/v1/feedback", json={
                "category": "Usability / UX",
                "summary": "Navigation could be faster",
                "message": "Consider adding keyboard shortcuts for tab navigation.",
            })
            assert res.status_code == 504
            assert res.json()["detail"] == "Feedback service is unreachable. Please check your connection and try again."
    finally:
        app.dependency_overrides.pop(get_feedback_service, None)
        await mock_client.aclose()
