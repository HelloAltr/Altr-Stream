"""User feedback submission API routes."""

from __future__ import annotations

import logging
from typing import Any
from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field

from altr_stream.application.feedback_service import FeedbackService
from altr_stream.domain.feedback import FeedbackCategory, FeedbackSubmission
from altr_stream.infrastructure.feedback_client import (
    FeedbackAuthError,
    FeedbackBadRequestError,
    FeedbackDuplicateError,
    FeedbackNotConfiguredError,
    FeedbackRateLimitError,
    FeedbackTimeoutError,
    FeedbackUnavailableError,
    FeedbackUpstreamError,
)

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/feedback", tags=["Feedback"])


class FeedbackRequestDTO(BaseModel):
    """Payload for submitting user feedback."""

    category: str = Field(
        ...,
        description="Feedback category (Bug, Feature Request, Usability / UX, General)",
        examples=["Bug", "Feature Request"],
    )
    summary: str = Field(
        ...,
        min_length=3,
        max_length=200,
        description="Concise summary of the feedback",
        examples=["Query editor fails on complex group-by"],
    )
    message: str = Field(
        ...,
        min_length=3,
        max_length=10000,
        description="Detailed feedback message",
    )
    contact: str | None = Field(
        default=None,
        max_length=200,
        description="Optional contact handle or email for responses",
    )
    include_diagnostics: bool = Field(
        default=False,
        description="Explicit user consent to include sanitized system telemetry",
    )
    diagnostics: dict[str, Any] | None = Field(
        default=None,
        description="Optional sanitized diagnostic state from the client",
    )
    client_platform: str | None = Field(
        default=None,
        max_length=100,
        description="Client runtime platform (e.g. Web, macOS, Linux, Windows)",
    )


class FeedbackResponseDTO(BaseModel):
    """Response returned upon feedback dispatch."""

    status: str = Field(default="submitted", description="Submission outcome")
    issue_number: int | None = Field(default=None, description="GitHub issue number if created")
    issue_url: str | None = Field(default=None, description="GitHub REST API URL for the issue")
    html_url: str | None = Field(default=None, description="Public GitHub issue web URL")
    message: str = Field(..., description="User-facing status message")


def get_feedback_service() -> FeedbackService:
    """Dependency provider for FeedbackService."""
    return FeedbackService()


@router.post(
    "",
    response_model=FeedbackResponseDTO,
    status_code=status.HTTP_201_CREATED,
    summary="Submit user feedback",
    description="Submits user feedback to the external Altr Feedback service.",
)
async def submit_feedback(
    payload: FeedbackRequestDTO,
    service: FeedbackService = Depends(get_feedback_service),
) -> FeedbackResponseDTO:
    """Process and dispatch feedback to Altr Feedback service."""
    try:
        category = FeedbackCategory.from_string(payload.category)
    except ValueError as exc:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(exc),
        )

    try:
        submission = FeedbackSubmission(
            category=category,
            summary=payload.summary,
            message=payload.message,
            contact=payload.contact,
            include_diagnostics=payload.include_diagnostics,
            diagnostics=payload.diagnostics,
        )
        result = await service.submit_feedback(
            submission=submission,
            client_platform=payload.client_platform,
        )
        return FeedbackResponseDTO(
            status=result["status"],
            issue_number=result.get("issue_number"),
            issue_url=result.get("issue_url"),
            html_url=result.get("html_url"),
            message=result["message"],
        )
    except ValueError as exc:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(exc),
        )
    except FeedbackNotConfiguredError:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Feedback service is not configured on this node.",
        )
    except FeedbackAuthError:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Feedback service authentication failed.",
        )
    except FeedbackDuplicateError:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Duplicate feedback submission detected. Please wait before resubmitting.",
        )
    except FeedbackRateLimitError:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="Feedback submission limit reached. Please try again later.",
        )
    except FeedbackBadRequestError as exc:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(exc) if str(exc) else "Invalid feedback request. Please verify your message.",
        )
    except FeedbackUpstreamError:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="Unable to submit feedback right now. Please try again later.",
        )
    except FeedbackUnavailableError:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Feedback service is temporarily unavailable. Please try again shortly.",
        )
    except FeedbackTimeoutError:
        raise HTTPException(
            status_code=status.HTTP_504_GATEWAY_TIMEOUT,
            detail="Feedback service is unreachable. Please check your connection and try again.",
        )
