"""Application service for generating, hashing, verifying, and managing API keys."""

from __future__ import annotations

from datetime import datetime, timedelta, timezone
import hashlib
import secrets
from sqlalchemy.ext.asyncio import AsyncSession

from altr_stream.infrastructure.database.api_key_repository import SqliteApiKeyRepository
from altr_stream.infrastructure.database.models import ApiKeyModel

KEY_PREFIX = "altr_live_"


def hash_api_key(raw_key: str) -> str:
    """Compute constant-time friendly SHA-256 digest of an API key secret."""
    return hashlib.sha256(raw_key.strip().encode("utf-8")).hexdigest()


class ApiKeyService:
    """Service encapsulating API key cryptographic operations and authorization checks."""

    def __init__(self, session: AsyncSession) -> None:
        self.session = session
        self.repository = SqliteApiKeyRepository(session)

    async def generate_key(
        self,
        name: str,
        scopes: list[str] | None = None,
        expires_in_days: int | None = None,
        expires_in_hours: int | None = None,
        expires_at: datetime | None = None,
    ) -> tuple[str, ApiKeyModel]:
        """Generate a cryptographically secure API key.

        Returns a tuple of (raw_secret, ApiKeyModel).
        The raw_secret is only accessible once during this invocation and is never persisted.
        """
        resolved_scopes = scopes or ["read", "write"]
        entropy = secrets.token_urlsafe(32)
        raw_key = f"{KEY_PREFIX}{entropy}"
        key_prefix = raw_key[:14] + "..."
        key_hash = hash_api_key(raw_key)

        resolved_expires_at = expires_at
        if resolved_expires_at is None and expires_in_hours and expires_in_hours > 0:
            resolved_expires_at = datetime.now(timezone.utc) + timedelta(hours=expires_in_hours)
        elif resolved_expires_at is None and expires_in_days and expires_in_days > 0:
            resolved_expires_at = datetime.now(timezone.utc) + timedelta(days=expires_in_days)

        model = await self.repository.create(
            name=name,
            key_prefix=key_prefix,
            key_hash=key_hash,
            scopes=resolved_scopes,
            expires_at=resolved_expires_at,
        )
        return raw_key, model

    async def get_active_key(self, raw_key: str) -> ApiKeyModel | None:
        """Fetch active, non-expired key by raw key secret."""
        if not raw_key or not isinstance(raw_key, str):
            return None

        clean_key = raw_key.strip()
        if clean_key.lower().startswith("bearer "):
            clean_key = clean_key[7:].strip()

        key_hash = hash_api_key(clean_key)
        return await self.repository.get_by_hash(key_hash)

    async def verify_key(
        self,
        raw_key: str,
        required_scope: str | None = None,
    ) -> ApiKeyModel | None:
        """Verify raw API key and validate scope access.

        Returns ApiKeyModel if valid and authorized, None otherwise.
        """
        key_model = await self.get_active_key(raw_key)
        if not key_model:
            return None

        # Check scopes if required
        if required_scope:
            active_scopes = [s.strip().lower() for s in key_model.scopes.split(",") if s.strip()]
            # Admin scope grants all privileges
            if "admin" not in active_scopes:
                req = required_scope.strip().lower()
                if req == "read" and ("read" not in active_scopes and "write" not in active_scopes):
                    return None
                elif req == "write" and ("write" not in active_scopes):
                    return None
                elif req == "admin":
                    return None

        # Record usage timestamp in background
        await self.repository.record_usage(key_model.id)
        return key_model

    async def list_keys(self) -> list[ApiKeyModel]:
        """List all registered API keys without exposing secrets."""
        return await self.repository.list_all()

    async def has_active_keys(self) -> bool:
        """Check if any active API keys exist."""
        count = await self.repository.count_active()
        return count > 0

    async def revoke_key(self, key_id: str) -> bool:
        """Revoke an active key."""
        return await self.repository.revoke(key_id)

    async def delete_key(self, key_id: str) -> bool:
        """Delete an API key."""
        return await self.repository.delete(key_id)
