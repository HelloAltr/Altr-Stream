"""Feedback domain models, category enums, and privacy sanitization utilities."""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from enum import Enum
from typing import Any


class FeedbackCategory(str, Enum):
    """Categorization for user feedback."""

    BUG = "Bug"
    FEATURE_REQUEST = "Feature Request"
    USABILITY = "Usability / UX"
    GENERAL = "General"

    @classmethod
    def from_string(cls, val: str) -> FeedbackCategory:
        """Parse category case-insensitively, defaulting to GENERAL."""
        normalized = val.strip().lower()
        for member in cls:
            if member.value.lower() == normalized or member.name.lower() == normalized:
                return member
            # Common shorthands
            if normalized in ("bug", "defect", "error"):
                return cls.BUG
            if normalized in ("feature", "enhancement", "feature request", "fr"):
                return cls.FEATURE_REQUEST
            if normalized in ("ux", "usability", "ui"):
                return cls.USABILITY
        raise ValueError(f"Unknown feedback category: '{val}'")

    @property
    def api_slug(self) -> str:
        """Map to Altr Feedback service category slug."""
        mapping = {
            FeedbackCategory.BUG: "bug",
            FeedbackCategory.FEATURE_REQUEST: "feature_request",
            FeedbackCategory.USABILITY: "usability",
            FeedbackCategory.GENERAL: "general",
        }
        return mapping[self]


# Regex to sanitize database URIs: scheme://user:password@host:port/dbname
_URI_PASSWORD_PATTERN = re.compile(r"([a-zA-Z][a-zA-Z0-9+.-]*://[^:]+:)([^@]+)(@.+)")

# Sensitive key substring patterns
_SENSITIVE_KEY_PATTERN = re.compile(
    r"(pass(word)?|secret|token|api_?key|auth|bearer|cred(ential)?|private_?key|private)",
    re.IGNORECASE,
)

# Common secret/token patterns in text
_SECRET_VALUE_PATTERNS = [
    re.compile(r"(ghp_[a-zA-Z0-9]+)"),  # GitHub Personal Access Token
    re.compile(r"(gho_[a-zA-Z0-9]+)"),  # GitHub OAuth Token
    re.compile(r"(github_pat_[a-zA-Z0-9_]+)"),  # Fine-grained token
    re.compile(r"(Bearer\s+)[a-zA-Z0-9._~+/-]+", re.IGNORECASE),  # Bearer tokens
    re.compile(r"((?:token|secret|password|key)\s*[:=]\s*)[^\s,;\"'\]\}]+", re.IGNORECASE),
]


def sanitize_text(text: str) -> str:
    """Mask known secret patterns and sanitize sensitive connection strings within freeform text."""
    if not text:
        return text

    # Sanitize database URLs
    sanitized = _URI_PASSWORD_PATTERN.sub(r"\1********\3", text)

    # Sanitize bearer tokens and GitHub PATs
    for pattern in _SECRET_VALUE_PATTERNS:
        sanitized = pattern.sub(r"[REDACTED_SECRET]", sanitized)

    return sanitized


def sanitize_diagnostics(data: Any) -> Any:
    """Recursively scrub sensitive keys and credential patterns from diagnostic payloads."""
    if isinstance(data, dict):
        sanitized_dict: dict[str, Any] = {}
        for k, v in data.items():
            k_str = str(k)
            if _SENSITIVE_KEY_PATTERN.search(k_str):
                sanitized_dict[k_str] = "********"
            else:
                sanitized_dict[k_str] = sanitize_diagnostics(v)
        return sanitized_dict
    elif isinstance(data, list):
        return [sanitize_diagnostics(item) for item in data]
    elif isinstance(data, str):
        return sanitize_text(data)
    return data


@dataclass(frozen=True)
class FeedbackSubmission:
    """Encapsulates validated and sanitized feedback intent."""

    category: FeedbackCategory
    summary: str
    message: str
    contact: str | None = None
    include_diagnostics: bool = False
    environment: dict[str, str] = field(default_factory=dict)
    diagnostics: dict[str, Any] | None = None

    def __post_init__(self) -> None:
        """Validate input invariants."""
        if not self.summary or not self.summary.strip():
            raise ValueError("Feedback summary cannot be empty.")
        if not self.message or not self.message.strip():
            raise ValueError("Feedback message cannot be empty.")
        if len(self.summary.strip()) > 200:
            raise ValueError("Feedback summary exceeds maximum length of 200 characters.")
        if len(self.message.strip()) > 10000:
            raise ValueError("Feedback message exceeds maximum length of 10000 characters.")

    @property
    def clean_title(self) -> str:
        """Sanitized title for submission."""
        return sanitize_text(self.summary.strip().replace("\n", " "))

    @property
    def clean_message(self) -> str:
        """Sanitized message for submission."""
        return sanitize_text(self.message.strip())
