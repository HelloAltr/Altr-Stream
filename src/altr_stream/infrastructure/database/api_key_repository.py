"""Repository for persisting and managing API key records in SQLite metadata store."""

from datetime import datetime, timezone
from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession

from altr_stream.infrastructure.database.models import ApiKeyModel


class SqliteApiKeyRepository:
    """Async repository for managing API keys in SQLite."""

    def __init__(self, session: AsyncSession) -> None:
        self.session = session

    async def create(
        self,
        name: str,
        key_prefix: str,
        key_hash: str,
        scopes: list[str],
        expires_at: datetime | None = None,
    ) -> ApiKeyModel:
        """Create and persist a new API key."""
        scopes_str = ",".join(sorted(set(s.strip().lower() for s in scopes if s.strip())))
        model = ApiKeyModel(
            name=name.strip(),
            key_prefix=key_prefix.strip(),
            key_hash=key_hash.strip(),
            scopes=scopes_str or "read",
            is_active=True,
            expires_at=expires_at,
        )
        self.session.add(model)
        await self.session.commit()
        await self.session.refresh(model)
        return model

    async def get_by_hash(self, key_hash: str) -> ApiKeyModel | None:
        """Find an active, non-expired key by its SHA-256 hash."""
        now = datetime.now(timezone.utc)
        stmt = select(ApiKeyModel).where(
            ApiKeyModel.key_hash == key_hash,
            ApiKeyModel.is_active == True,  # noqa: E712
        )
        result = await self.session.execute(stmt)
        key = result.scalar_one_or_none()
        if key and key.expires_at:
            expires_at = key.expires_at
            if expires_at.tzinfo is None:
                expires_at = expires_at.replace(tzinfo=timezone.utc)
            if expires_at < now:
                return None
        return key


    async def get_by_id(self, key_id: str) -> ApiKeyModel | None:
        """Find an API key by its unique ID."""
        stmt = select(ApiKeyModel).where(ApiKeyModel.id == key_id)
        result = await self.session.execute(stmt)
        return result.scalar_one_or_none()

    async def list_all(self) -> list[ApiKeyModel]:
        """List all registered API keys sorted by creation date."""
        stmt = select(ApiKeyModel).order_by(ApiKeyModel.created_at.desc())
        result = await self.session.execute(stmt)
        return list(result.scalars().all())

    async def count_active(self) -> int:
        """Count active, non-expired keys."""
        now = datetime.now(timezone.utc)
        stmt = select(ApiKeyModel).where(ApiKeyModel.is_active == True)  # noqa: E712
        result = await self.session.execute(stmt)
        keys = result.scalars().all()
        active_count = 0
        for k in keys:
            if k.expires_at:
                exp = k.expires_at if k.expires_at.tzinfo is not None else k.expires_at.replace(tzinfo=timezone.utc)
                if exp < now:
                    continue
            active_count += 1
        return active_count

    async def count_all(self) -> int:
        """Count total keys registered."""
        stmt = select(ApiKeyModel)
        result = await self.session.execute(stmt)
        return len(result.scalars().all())

    async def revoke(self, key_id: str) -> bool:
        """Revoke / deactivate an API key."""
        key = await self.get_by_id(key_id)
        if not key:
            return False
        key.is_active = False
        await self.session.commit()
        return True

    async def delete(self, key_id: str) -> bool:
        """Hard delete an API key."""
        key = await self.get_by_id(key_id)
        if not key:
            return False
        await self.session.delete(key)
        await self.session.commit()
        return True

    async def record_usage(self, key_id: str) -> None:
        """Update last_used_at timestamp asynchronously."""
        stmt = (
            update(ApiKeyModel)
            .where(ApiKeyModel.id == key_id)
            .values(last_used_at=datetime.now(timezone.utc))
        )
        await self.session.execute(stmt)
        await self.session.commit()
