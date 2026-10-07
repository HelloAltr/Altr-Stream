"""Unit tests for Feedback domain models and privacy sanitization."""

import pytest
from altr_stream.domain.feedback import (
    FeedbackCategory,
    FeedbackSubmission,
    sanitize_diagnostics,
    sanitize_text,
)


def test_feedback_category_parsing():
    """Verify case-insensitive and alias parsing of feedback categories."""
    assert FeedbackCategory.from_string("Bug") == FeedbackCategory.BUG
    assert FeedbackCategory.from_string("bug") == FeedbackCategory.BUG
    assert FeedbackCategory.from_string("defect") == FeedbackCategory.BUG
    assert FeedbackCategory.from_string("Feature Request") == FeedbackCategory.FEATURE_REQUEST
    assert FeedbackCategory.from_string("feature") == FeedbackCategory.FEATURE_REQUEST
    assert FeedbackCategory.from_string("enhancement") == FeedbackCategory.FEATURE_REQUEST
    assert FeedbackCategory.from_string("Usability / UX") == FeedbackCategory.USABILITY
    assert FeedbackCategory.from_string("ux") == FeedbackCategory.USABILITY
    assert FeedbackCategory.from_string("General") == FeedbackCategory.GENERAL

    with pytest.raises(ValueError, match="Unknown feedback category"):
        FeedbackCategory.from_string("invalid_category_xyz")


def test_sanitize_text_strips_database_credentials():
    """Ensure database connection strings have passwords scrubbed."""
    text = "Failed connecting to postgresql://postgres:superSecretPass123@db.prod.internal:5432/mydb"
    sanitized = sanitize_text(text)
    assert "superSecretPass123" not in sanitized
    assert "postgresql://postgres:********@db.prod.internal:5432/mydb" in sanitized


def test_sanitize_text_strips_bearer_and_github_tokens():
    """Ensure bearer tokens and personal access tokens are masked."""
    text = "Auth failed with Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9 and ghp_1234567890abcdefghijklmnopqrstuvwxyz12"
    sanitized = sanitize_text(text)
    assert "ghp_1234567890abcdefghijklmnopqrstuvwxyz12" not in sanitized
    assert "[REDACTED_SECRET]" in sanitized


def test_sanitize_diagnostics_recursive_scrubbing():
    """Verify diagnostic payloads have all sensitive keys masked and URLs scrubbed."""
    raw_diagnostics = {
        "node": "node-1",
        "database_url": "mysql://app:secret123@10.0.0.1:3306/db",
        "api_key": "live-api-key-9999",
        "auth_token": "Bearer my_secret_token_abc",
        "nested": {
            "password": "p@ssword!",
            "public_metric": 42.5,
            "secret_config": "hidden",
            "connection_string": "postgres://user:mypass@localhost/altr",
        },
        "tags": ["env:prod", "token=ghp_secrettokenhere1234567890abcdef"],
    }

    scrubbed = sanitize_diagnostics(raw_diagnostics)

    assert scrubbed["node"] == "node-1"
    assert scrubbed["database_url"] == "mysql://app:********@10.0.0.1:3306/db"
    assert scrubbed["api_key"] == "********"
    assert scrubbed["auth_token"] == "********"
    assert scrubbed["nested"]["password"] == "********"
    assert scrubbed["nested"]["secret_config"] == "********"
    assert scrubbed["nested"]["public_metric"] == 42.5
    assert "mypass" not in scrubbed["nested"]["connection_string"]
    assert "ghp_secrettokenhere" not in str(scrubbed["tags"])


def test_feedback_submission_validation():
    """Verify bounds and validation on FeedbackSubmission."""
    with pytest.raises(ValueError, match="summary cannot be empty"):
        FeedbackSubmission(
            category=FeedbackCategory.BUG,
            summary="   ",
            message="Valid message",
        )

    with pytest.raises(ValueError, match="message cannot be empty"):
        FeedbackSubmission(
            category=FeedbackCategory.BUG,
            summary="Valid summary",
            message="   ",
        )

    with pytest.raises(ValueError, match="summary exceeds maximum length"):
        FeedbackSubmission(
            category=FeedbackCategory.BUG,
            summary="A" * 201,
            message="Valid message",
        )


def test_feedback_category_api_slug():
    """Verify deterministic category slug mapping to external Altr Feedback contract."""
    assert FeedbackCategory.BUG.api_slug == "bug"
    assert FeedbackCategory.FEATURE_REQUEST.api_slug == "feature_request"
    assert FeedbackCategory.USABILITY.api_slug == "usability"
    assert FeedbackCategory.GENERAL.api_slug == "general"


def test_feedback_submission_clean_title_and_message():
    """Verify clean_title and clean_message sanitize secrets and format newlines."""
    submission = FeedbackSubmission(
        category=FeedbackCategory.BUG,
        summary="DB error with postgresql://admin:secret123@localhost:5432/db\nwith extra newline",
        message="Failure when token=ghp_abcdefghijklmnopqrstuvwxyz1234567890\nDetails here.",
    )
    assert "secret123" not in submission.clean_title
    assert "\n" not in submission.clean_title
    assert "postgresql://admin:********@localhost:5432/db with extra newline" in submission.clean_title
    assert "ghp_abcdef" not in submission.clean_message
    assert "[REDACTED_SECRET]" in submission.clean_message
