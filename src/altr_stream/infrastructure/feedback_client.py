"""Altr Feedback service client adapter for feedback submission."""

from __future__ import annotations

import logging
from typing import Any
import httpx

logger = logging.getLogger(__name__)


class AltrFeedbackError(Exception):
    """Base exception for Altr Feedback service interactions."""


class FeedbackNotConfiguredError(AltrFeedbackError):
    """Raised when Altr Feedback service URL is not configured."""


class FeedbackBadRequestError(AltrFeedbackError):
    """Raised on 400 Bad Request from Altr Feedback."""


class FeedbackAuthError(AltrFeedbackError):
    """Raised on 401 Unauthorized from Altr Feedback (invalid API key or missing installation ID)."""


class FeedbackDuplicateError(AltrFeedbackError):
    """Raised on 409 Conflict from Altr Feedback (duplicate submission detected)."""


class FeedbackRateLimitError(AltrFeedbackError):
    """Raised on 429 Too Many Requests from Altr Feedback (rate limit exceeded)."""


class FeedbackUpstreamError(AltrFeedbackError):
    """Raised on 502 Bad Gateway from Altr Feedback (upstream GitHub error)."""


class FeedbackUnavailableError(AltrFeedbackError):
    """Raised on 503 Service Unavailable (rate-limit / circuit breaker / temporary overload)."""


class FeedbackTimeoutError(AltrFeedbackError):
    """Raised on network timeout or connection failure to Altr Feedback."""


class AltrFeedbackClient:
    """Async client adapter for the external Altr Feedback service."""

    def __init__(
        self,
        api_key: str | None = None,
        service_url: str = "https://altr-feedback.onrender.com",
        http_client: httpx.AsyncClient | None = None,
        timeout: float = 30.0,
    ) -> None:
        self.api_key = api_key.strip() if api_key and api_key.strip() else None
        self.service_url = service_url.rstrip("/") if service_url else ""
        self.timeout = timeout
        self._external_client = http_client

    @property
    def is_configured(self) -> bool:
        """Verify whether the feedback service URL is configured."""
        return bool(self.service_url)

    @property
    def is_priority_mode(self) -> bool:
        """Verify whether priority/internal mode with a configured API key is active."""
        return bool(self.api_key)

    async def submit_feedback(
        self,
        payload: dict[str, Any],
    ) -> dict[str, Any]:
        """Submit structured feedback to the Altr Feedback service.

        Supports two admission modes:
        1. Priority / Internal mode (when api_key is configured):
           Passes Authorization: Bearer <api_key>.
        2. Public Beta mode (when api_key is None / empty):
           Submits without Authorization header for zero-configuration public Beta.

        Expected response:
        {
            "success": true,
            "repository": "HelloAltr/Altr-Stream",
            "issue_number": 123,
            "url": "https://github.com/HelloAltr/Altr-Stream/issues/123"
        }
        """
        if not self.is_configured:
            raise FeedbackNotConfiguredError(
                "Feedback service URL is not configured on this node."
            )

        endpoint = f"{self.service_url}/api/v1/feedback"
        headers: dict[str, str] = {
            "Content-Type": "application/json",
            "User-Agent": "Altr-Stream-Node",
        }

        # Resolve admission mode
        if self.is_priority_mode:
            headers["Authorization"] = f"Bearer {self.api_key}"
        # In Public Beta mode (no api_key), do not send Authorization header.

        async def _send(client: httpx.AsyncClient) -> dict[str, Any]:
            try:
                response = await client.post(
                    endpoint,
                    json=payload,
                    headers=headers,
                    timeout=self.timeout,
                )
            except httpx.TimeoutException:
                logger.warning("Feedback service request timed out after %.1fs", self.timeout)
                raise FeedbackTimeoutError(
                    f"Connection to feedback service timed out after {self.timeout}s."
                ) from None
            except httpx.NetworkError as exc:
                logger.warning("Network error connecting to feedback service: %s", exc)
                raise FeedbackTimeoutError(
                    "Network error connecting to feedback service."
                ) from None

            if response.status_code in (200, 201):
                data = response.json()
                return {
                    "success": data.get("success", True),
                    "repository": data.get("repository"),
                    "issue_number": data.get("issue_number"),
                    "url": data.get("url"),
                }

            if response.status_code == 400:
                logger.warning("Feedback service rejected payload (400): %s", response.text)
                err_data = response.json() if response.headers.get("content-type", "").startswith("application/json") else {}
                err_msg = err_data.get("error", {}).get("message", "Invalid feedback request. Please verify your message.")
                raise FeedbackBadRequestError(err_msg)

            if response.status_code == 401:
                logger.error("Feedback service rejected request (401): %s", response.text)
                raise FeedbackAuthError(
                    "Feedback service authentication failed."
                )

            if response.status_code == 409:
                logger.info("Feedback service rejected duplicate submission (409)")
                raise FeedbackDuplicateError(
                    "Duplicate feedback submission detected. Please wait before resubmitting."
                )

            if response.status_code == 429:
                logger.warning("Feedback service reported rate limit exceeded (429)")
                raise FeedbackRateLimitError(
                    "Feedback submission limit reached. Please try again later."
                )

            if response.status_code == 502:
                logger.warning("Feedback service reported upstream failure (502): %s", response.text)
                raise FeedbackUpstreamError("Unable to submit feedback right now. Please try again later.")

            if response.status_code == 503:
                logger.warning("Feedback service is unavailable (503): %s", response.text)
                raise FeedbackUnavailableError(
                    "Feedback service is temporarily unavailable. Please try again shortly."
                )

            # Unhandled status
            logger.error("Feedback service returned unexpected status %d: %s", response.status_code, response.text)
            raise FeedbackUpstreamError(f"Unexpected response from feedback service ({response.status_code}).")

        if self._external_client:
            return await _send(self._external_client)
        else:
            async with httpx.AsyncClient() as client:
                return await _send(client)
