"""FastAPI security dependencies and authentication helpers for API keys."""

from __future__ import annotations

from typing import Annotated, Callable
from fastapi import Depends, Header, HTTPException, Security, status
from fastapi.security import APIKeyHeader
from sqlalchemy.ext.asyncio import AsyncSession

from altr_stream.application.api_key_service import ApiKeyService
from altr_stream.config import settings
from altr_stream.infrastructure.database.models import ApiKeyModel
from altr_stream.infrastructure.database.session import get_session

api_key_header_scheme = APIKeyHeader(name="X-Altr-API-Key", auto_error=False)


async def get_api_key_service(session: Annotated[AsyncSession, Depends(get_session)]) -> ApiKeyService:
    """Dependency yielding ApiKeyService."""
    return ApiKeyService(session)


def require_scope(scope: str = "read") -> Callable:
    """Dependency factory requiring a specific API key scope (read, write, admin)."""

    async def _verify(
        api_key_header: Annotated[str | None, Security(api_key_header_scheme)] = None,
        authorization: Annotated[str | None, Header(alias="Authorization")] = None,
        altr_client: Annotated[str | None, Header(alias="X-Altr-Client")] = None,
        service: Annotated[ApiKeyService, Depends(get_api_key_service)] = None,
    ) -> ApiKeyModel | None:
        raw_key = api_key_header or authorization
        if raw_key and raw_key.lower().startswith("bearer "):
            raw_key = raw_key[7:].strip()

        # 1. If an API key was provided, strictly authenticate and authorize it
        if raw_key:
            active_key = await service.get_active_key(raw_key)
            if not active_key:
                raise HTTPException(
                    status_code=status.HTTP_401_UNAUTHORIZED,
                    detail="Invalid, expired, or revoked API key.",
                    headers={"WWW-Authenticate": "ApiKey"},
                )

            # Validate scopes
            active_scopes = [s.strip().lower() for s in active_key.scopes.split(",") if s.strip()]
            if "admin" not in active_scopes:
                req = scope.strip().lower()
                has_scope = False
                if req == "read" and ("read" in active_scopes or "write" in active_scopes):
                    has_scope = True
                elif req == "write" and ("write" in active_scopes):
                    has_scope = True
                elif req == "admin":
                    has_scope = False

                if not has_scope:
                    raise HTTPException(
                        status_code=status.HTTP_403_FORBIDDEN,
                        detail=f"API key lacks required scope '{scope}'.",
                    )

            await service.repository.record_usage(active_key.id)
            return active_key

        # 2. No API key was provided:
        # Permitted only for internal Web Dashboard console requests
        if altr_client == "web-dashboard":
            return None

        # 3. All external callers (Postman, curl, SDKs) MUST supply a valid API key
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing API key. Provide 'X-Altr-API-Key' or 'Authorization: Bearer <key>' header.",
            headers={"WWW-Authenticate": "ApiKey"},
        )

    return _verify


# Preconfigured standard dependencies
require_read_access = require_scope("read")
require_write_access = require_scope("write")
require_admin_access = require_scope("admin")
