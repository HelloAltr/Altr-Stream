"""Altr Stream main FastAPI application entry point."""

from collections.abc import AsyncGenerator
from contextlib import asynccontextmanager
from pathlib import Path
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from altr_stream.config import settings
from altr_stream.infrastructure.database.session import init_db
from altr_stream.presentation.api.router import api_v1_router
from altr_stream.presentation.web.router import web_router


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncGenerator[None, None]:
    """Application lifespan context manager for startup and shutdown hooks."""
    # Initialize metadata database
    await init_db()
    yield
    # Shutdown logic (if any)


def create_app() -> FastAPI:
    """Create and configure the FastAPI application instance."""
    app = FastAPI(
        title=settings.app_name,
        version=settings.app_version,
        description="Physical source abstraction and data infrastructure service for the Altr Mesh.",
        lifespan=lifespan,
    )

    # Enable CORS for local mesh development
    app.add_middleware(
        CORSMiddleware,
        allow_origins=["*"],
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    # Static assets for Admin UI
    static_dir = Path(__file__).parent / "presentation" / "web" / "static"
    static_dir.mkdir(parents=True, exist_ok=True)
    app.mount("/static", StaticFiles(directory=str(static_dir)), name="static")

    # Master API v1 Router
    app.include_router(api_v1_router)

    # Admin UI Web Router
    app.include_router(web_router)

    return app


app = create_app()

if __name__ == "__main__":
    import uvicorn

    uvicorn.run(
        "altr_stream.main:app",
        host=settings.host,
        port=settings.port,
        reload=settings.debug,
    )
