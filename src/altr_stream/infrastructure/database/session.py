"""Database session and engine management for local metadata SQLite store."""

from collections.abc import AsyncGenerator
from pathlib import Path
from sqlalchemy.ext.asyncio import (
    AsyncEngine,
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)
from sqlalchemy.orm import declarative_base

from sqlalchemy.engine import make_url

from altr_stream.config import settings

Base = declarative_base()

_engine: AsyncEngine | None = None
_session_factory: async_sessionmaker[AsyncSession] | None = None


def get_engine() -> AsyncEngine:
    """Get or create the async SQLAlchemy engine."""
    global _engine
    if _engine is None:
        # Ensure data directory exists
        # Ensure SQLite data directory exists
        if settings.database_url.startswith("sqlite"):
            url = make_url(settings.database_url)

            if url.database and url.database != ":memory:":
                db_path = Path(url.database)
                db_path.parent.mkdir(parents=True, exist_ok=True)

        _engine = create_async_engine(
            settings.database_url,
            echo=settings.debug,
            future=True,
        )
    return _engine


def get_session_factory() -> async_sessionmaker[AsyncSession]:
    """Get or create the async session factory."""
    global _session_factory
    if _session_factory is None:
        _session_factory = async_sessionmaker(
            bind=get_engine(),
            class_=AsyncSession,
            expire_on_commit=False,
        )
    return _session_factory


async def init_db(engine: AsyncEngine | None = None) -> None:
    """Initialize database tables and apply any pending schema migrations."""
    target_engine = engine or get_engine()
    # Import models to ensure they are registered with Base metadata
    import altr_stream.infrastructure.database.models  # noqa: F401
    from altr_stream.infrastructure.database.migrations import run_migrations

    async with target_engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
        await conn.run_sync(run_migrations)


async def get_session() -> AsyncGenerator[AsyncSession, None]:
    """FastAPI dependency for yielding async database sessions."""
    factory = get_session_factory()
    async with factory() as session:
        try:
            yield session
            await session.commit()
        except Exception:
            await session.rollback()
            raise
