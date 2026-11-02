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
        # Interactive Web Dashboard console requests do not require manual API keys
        if altr_client == "web-dashboard":
            return None

        raw_key = api_key_header or authorization
        if raw_key and raw_key.lower().startswith("bearer "):
            raw_key = raw_key[7:].strip()

        has_keys = await service.has_active_keys()

        # If no keys have ever been registered and strict enforcement is not explicitly toggled,
        # allow bootstrap/development requests.
        if not has_keys and not getattr(settings, "require_api_key", False):
            return None

        if not raw_key:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Missing API key. Provide 'X-Altr-API-Key' or 'Authorization: Bearer <key>' header.",
                headers={"WWW-Authenticate": "ApiKey"},
            )

        key_model = await service.verify_key(raw_key, required_scope=scope)
        if not key_model:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=f"Invalid or unauthorized API key for scope '{scope}'.",
            )
        return key_model

    return _verify


# Preconfigured standard dependencies
require_read_access = require_scope("read")
require_write_access = require_scope("write")
require_admin_access = require_scope("admin")
