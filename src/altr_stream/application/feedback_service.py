"""Application service orchestrating user feedback processing and submission."""

from __future__ import annotations

import logging
from typing import Any

from altr_stream.config import settings
from altr_stream.domain.feedback import (
    FeedbackCategory,
    FeedbackSubmission,
    sanitize_diagnostics,
    sanitize_text,
)
from altr_stream.infrastructure.feedback_client import AltrFeedbackClient

logger = logging.getLogger(__name__)


class FeedbackService:
    """Application service for sanitizing, formatting, and dispatching user feedback to Altr Feedback."""

    def __init__(
        self,
        feedback_client: AltrFeedbackClient | None = None,
    ) -> None:
        self.feedback_client = feedback_client or AltrFeedbackClient(
            api_key=settings.feedback_api_key,
            service_url=settings.feedback_service_url,
        )

    async def submit_feedback(
        self,
        submission: FeedbackSubmission,
        client_platform: str | None = None,
    ) -> dict[str, Any]:
        """Process, sanitize, and dispatch user feedback to Altr Feedback service."""
        # 1. Local text sanitization
        clean_title = submission.clean_title
        clean_message = submission.clean_message
        clean_contact = (
            sanitize_text(submission.contact.strip())
            if submission.contact and submission.contact.strip()
            else None
        )

        # 2. Build context
        context: dict[str, Any] = {}
        if clean_contact:
            context["contact"] = clean_contact
        if client_platform and client_platform.strip():
            context["client_platform"] = sanitize_text(client_platform.strip())

        # 3. Handle diagnostics consent
        if submission.include_diagnostics and submission.diagnostics:
            context["diagnostics"] = sanitize_diagnostics(submission.diagnostics)

        # 4. Construct payload for Altr Feedback
        payload: dict[str, Any] = {
            "service": "altr-stream",
            "environment": "production" if not settings.debug else "development",
            "category": submission.category.api_slug,
            "severity": "medium",
            "title": clean_title,
            "message": clean_message,
            "source": {
                "component": "node",
                "version": settings.app_version,
            },
            "context": context,
        }

        logger.info(
            "Dispatching feedback to Altr Feedback service: category=%s, diagnostics=%s, mode=%s",
            payload["category"],
            submission.include_diagnostics,
            "priority" if self.feedback_client.is_priority_mode else "public-beta",
        )

        result = await self.feedback_client.submit_feedback(payload)

        issue_num = result.get("issue_number")
        issue_url = result.get("url")

        return {
            "status": "submitted",
            "issue_number": issue_num,
            "issue_url": issue_url,
            "html_url": issue_url,
            "message": f"Feedback submitted as Issue #{issue_num}." if issue_num else "Feedback submitted successfully.",
        }
