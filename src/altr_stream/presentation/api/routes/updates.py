"""REST API endpoints for Altr Stream Update System."""

from typing import Annotated
from fastapi import APIRouter, Depends, HTTPException, Query, status
from pydantic import BaseModel, Field

from altr_stream.application.update_service import UpdateService, get_update_service
from altr_stream.domain.semver import ReleaseChannel

router = APIRouter(prefix="/updates", tags=["Updates"])


class UpdateReleaseDTO(BaseModel):
    tag_name: str
    name: str
    published_at: str | None = None
    body: str | None = None
    prerelease: bool = False
    html_url: str | None = None


class UpdateCheckResponseDTO(BaseModel):
    current_version: str = Field(..., description="Current running node version")
    latest_version: str | None = Field(None, description="Latest compatible version available")
    update_available: bool = Field(..., description="Whether a direct upgrade is available")
    channel: str = Field(..., description="Active release channel (alpha, beta, stable)")
    release: UpdateReleaseDTO | None = Field(None, description="Metadata for the target release")
    check_available: bool = Field(True, description="Whether the update discovery check succeeded")
    error_code: str | None = Field(None, description="Error code if check_available is false")
    message: str | None = Field(None, description="Informational message or error description")
    retry_after: int | None = Field(None, description="Seconds until retry is permitted")


class UpdateApplyRequestDTO(BaseModel):
    target_version: str = Field(..., description="Target SemVer version string (e.g. 0.13.2-alpha)")
    channel: str | None = Field(None, description="Optional release channel override")


class UpdateStatusResponseDTO(BaseModel):
    request_id: str | None = Field(None, description="Unique update request identifier")
    state: str = Field(..., description="Current lifecycle state (idle, requested, applying, etc.)")
    current_version: str = Field(..., description="Currently active node version")
    target_version: str | None = Field(None, description="Target version being applied")
    progress_percent: int = Field(0, description="Estimated progress (0-100)")
    message: str = Field(..., description="Human-readable progress description")
    error: str | None = Field(None, description="Error details if state is failed or rolled_back")
    updated_at: str = Field(..., description="ISO 8601 timestamp of last state transition")
    rollback_performed: bool = Field(False, description="Whether automatic rollback was executed")


@router.get("/check", response_model=UpdateCheckResponseDTO)
async def check_updates(
    channel: Annotated[str | None, Query(description="Optional channel filter: alpha, beta, stable")] = None,
    force_refresh: Annotated[bool, Query(description="Bypass GitHub release cache")] = False,
    update_service: UpdateService = Depends(get_update_service),
) -> UpdateCheckResponseDTO:
    """Check for direct upgrades against official releases."""
    try:
        rel_channel = ReleaseChannel.from_string(channel) if channel else None
    except ValueError as exc:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Invalid channel: {exc}",
        )

    plan = await update_service.check_for_updates(channel=rel_channel, force_refresh=force_refresh)

    target_rel = None
    if plan.target_release:
        target_rel = UpdateReleaseDTO(
            tag_name=plan.target_release.tag_name,
            name=plan.target_release.name,
            published_at=plan.target_release.published_at,
            body=plan.target_release.body,
            prerelease=plan.target_release.prerelease,
            html_url=plan.target_release.html_url,
        )

    return UpdateCheckResponseDTO(
        current_version=str(plan.current_version),
        latest_version=str(plan.target_version) if plan.target_version else None,
        update_available=plan.update_available,
        channel=plan.channel.value,
        release=target_rel,
        check_available=plan.check_available,
        error_code=plan.error_code,
        message=plan.message,
        retry_after=plan.retry_after,
    )


@router.post("/apply", response_model=UpdateStatusResponseDTO, status_code=status.HTTP_202_ACCEPTED)
async def apply_update(
    payload: UpdateApplyRequestDTO,
    update_service: UpdateService = Depends(get_update_service),
) -> UpdateStatusResponseDTO:
    """Request an update to a specific target version.

    Dispatches an atomic update intent request for the host-level supervisor.
    """
    rel_channel = None
    if payload.channel:
        try:
            rel_channel = ReleaseChannel.from_string(payload.channel)
        except ValueError as exc:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Invalid channel: {exc}",
            )

    try:
        update_status = await update_service.request_update(
            target_version_str=payload.target_version,
            channel=rel_channel,
        )
        return UpdateStatusResponseDTO(**update_status.to_dict())
    except ValueError as exc:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(exc),
        )


@router.get("/status", response_model=UpdateStatusResponseDTO)
async def get_update_status(
    update_service: UpdateService = Depends(get_update_service),
) -> UpdateStatusResponseDTO:
    """Retrieve current update execution progress and state."""
    update_status = await update_service.get_status()
    return UpdateStatusResponseDTO(**update_status.to_dict())
