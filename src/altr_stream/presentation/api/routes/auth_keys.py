"""API routes for managing and verifying API keys."""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Annotated
from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field

from altr_stream.application.api_key_service import ApiKeyService
from altr_stream.presentation.api.security import get_api_key_service

router = APIRouter(prefix="/auth/keys", tags=["Authentication & API Keys"])


def _to_utc(dt: datetime | None) -> datetime | None:
    if dt is None:
        return None
    if dt.tzinfo is None:
        return dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(timezone.utc)


class CreateApiKeyRequest(BaseModel):
    name: str = Field(..., min_length=1, max_length=255, description="Friendly label for the API key")
    scopes: list[str] = Field(default_factory=lambda: ["read", "write"], description="Allowed scopes (read, write, admin)")
    expires_in_days: int | None = Field(default=None, ge=1, le=365, description="Optional key expiration in days")
    expires_in_hours: int | None = Field(default=None, ge=1, le=8760, description="Optional key expiration in hours")
    expires_at: datetime | None = Field(default=None, description="Optional explicit datetime expiration")


class ApiKeyResponse(BaseModel):
    id: str
    name: str
    key_prefix: str
    scopes: list[str]
    is_active: bool
    created_at: datetime
    last_used_at: datetime | None = None
    expires_at: datetime | None = None


class CreatedApiKeyResponse(ApiKeyResponse):
    raw_key: str = Field(..., description="The unhashed raw secret. Displayed only once upon creation.")


class VerifyKeyRequest(BaseModel):
    key: str


class VerifyKeyResponse(BaseModel):
    valid: bool
    name: str | None = None
    scopes: list[str] | None = None
    key_prefix: str | None = None


@router.get("", response_model=list[ApiKeyResponse])
async def list_api_keys(
    service: Annotated[ApiKeyService, Depends(get_api_key_service)],
    include_revoked: bool = False,
) -> list[ApiKeyResponse]:
    """List registered API keys without exposing secrets."""
    keys = await service.list_keys()
    if not include_revoked:
        keys = [k for k in keys if k.is_active]
    return [
        ApiKeyResponse(
            id=k.id,
            name=k.name,
            key_prefix=k.key_prefix,
            scopes=[s.strip() for s in k.scopes.split(",") if s.strip()],
            is_active=k.is_active,
            created_at=_to_utc(k.created_at),
            last_used_at=_to_utc(k.last_used_at),
            expires_at=_to_utc(k.expires_at),
        )
        for k in keys
    ]


@router.post("", response_model=CreatedApiKeyResponse, status_code=status.HTTP_201_CREATED)
async def create_api_key(
    request: CreateApiKeyRequest,
    service: Annotated[ApiKeyService, Depends(get_api_key_service)],
) -> CreatedApiKeyResponse:
    """Create a new API key. The unhashed raw secret is returned ONLY in this response."""
    raw_key, model = await service.generate_key(
        name=request.name,
        scopes=request.scopes,
        expires_in_days=request.expires_in_days,
        expires_in_hours=request.expires_in_hours,
        expires_at=request.expires_at,
    )
    return CreatedApiKeyResponse(
        id=model.id,
        name=model.name,
        key_prefix=model.key_prefix,
        scopes=[s.strip() for s in model.scopes.split(",") if s.strip()],
        is_active=model.is_active,
        created_at=_to_utc(model.created_at),
        last_used_at=_to_utc(model.last_used_at),
        expires_at=_to_utc(model.expires_at),
        raw_key=raw_key,
    )


@router.delete("/{key_id}", status_code=status.HTTP_200_OK)
async def revoke_api_key(
    key_id: str,
    service: Annotated[ApiKeyService, Depends(get_api_key_service)],
) -> dict[str, str]:
    """Revoke an active API key."""
    success = await service.revoke_key(key_id)
    if not success:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="API key not found")
    return {"status": "revoked", "key_id": key_id}


@router.post("/verify", response_model=VerifyKeyResponse)
async def verify_api_key(
    request: VerifyKeyRequest,
    service: Annotated[ApiKeyService, Depends(get_api_key_service)],
) -> VerifyKeyResponse:
    """Verify if a given API key is valid and active."""
    model = await service.verify_key(request.key)
    if not model:
        return VerifyKeyResponse(valid=False)
    return VerifyKeyResponse(
        valid=True,
        name=model.name,
        scopes=[s.strip() for s in model.scopes.split(",") if s.strip()],
        key_prefix=model.key_prefix,
    )
