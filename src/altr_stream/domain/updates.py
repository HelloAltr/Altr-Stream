"""Domain models and state machine for Altr Stream Update System."""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime, timezone
from enum import Enum
from typing import Any
import uuid


class UpdateStatusState(str, Enum):
    """Lifecycle state machine for update execution."""

    IDLE = "idle"
    REQUESTED = "requested"
    STAGING = "staging"
    APPLYING = "applying"
    HEALTH_CHECK = "health_check"
    COMPLETED = "completed"
    FAILED = "failed"
    ROLLING_BACK = "rolling_back"
    ROLLED_BACK = "rolled_back"

    @property
    def is_active(self) -> bool:
        """Indicates if an update workflow is actively in progress."""
        return self in (
            UpdateStatusState.REQUESTED,
            UpdateStatusState.STAGING,
            UpdateStatusState.APPLYING,
            UpdateStatusState.HEALTH_CHECK,
            UpdateStatusState.ROLLING_BACK,
        )

    @property
    def is_terminal(self) -> bool:
        """Indicates if the workflow reached a terminal state."""
        return self in (
            UpdateStatusState.COMPLETED,
            UpdateStatusState.FAILED,
            UpdateStatusState.ROLLED_BACK,
            UpdateStatusState.IDLE,
        )


@dataclass
class UpdateRequest:
    """IPC intent representation written by the application for the host supervisor."""

    request_id: str
    current_version: str
    target_version: str
    target_image: str
    created_at: str
    channel: str

    @classmethod
    def create(
        cls,
        current_version: str,
        target_version: str,
        target_image: str,
        channel: str = "alpha",
    ) -> UpdateRequest:
        return cls(
            request_id=str(uuid.uuid4()),
            current_version=current_version,
            target_version=target_version,
            target_image=target_image,
            created_at=datetime.now(timezone.utc).isoformat(),
            channel=channel,
        )

    def to_dict(self) -> dict[str, Any]:
        return {
            "request_id": self.request_id,
            "current_version": self.current_version,
            "target_version": self.target_version,
            "target_image": self.target_image,
            "created_at": self.created_at,
            "channel": self.channel,
        }

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> UpdateRequest:
        return cls(
            request_id=data["request_id"],
            current_version=data["current_version"],
            target_version=data["target_version"],
            target_image=data["target_image"],
            created_at=data["created_at"],
            channel=data.get("channel", "alpha"),
        )


@dataclass
class UpdateStatus:
    """Current update progress and status representation."""

    state: UpdateStatusState
    current_version: str
    request_id: str | None = None
    target_version: str | None = None
    progress_percent: int = 0
    message: str = "System is up to date."
    error: str | None = None
    updated_at: str = field(default_factory=lambda: datetime.now(timezone.utc).isoformat())
    rollback_performed: bool = False

    def to_dict(self) -> dict[str, Any]:
        return {
            "request_id": self.request_id,
            "state": self.state.value,
            "current_version": self.current_version,
            "target_version": self.target_version,
            "progress_percent": self.progress_percent,
            "message": self.message,
            "error": self.error,
            "updated_at": self.updated_at,
            "rollback_performed": self.rollback_performed,
        }

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> UpdateStatus:
        return cls(
            request_id=data.get("request_id"),
            state=UpdateStatusState(data.get("state", "idle")),
            current_version=data.get("current_version", "unknown"),
            target_version=data.get("target_version"),
            progress_percent=int(data.get("progress_percent", 0)),
            message=data.get("message", ""),
            error=data.get("error"),
            updated_at=data.get("updated_at", datetime.now(timezone.utc).isoformat()),
            rollback_performed=bool(data.get("rollback_performed", False)),
        )
