"""Altr Stream main FastAPI application entry point."""

from collections.abc import AsyncGenerator
from contextlib import asynccontextmanager
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from altr_stream.application.usage_tracker import usage_tracker
from altr_stream.config import settings
from altr_stream.infrastructure.database.session import init_db
from altr_stream.presentation.api.router import api_v1_router
from altr_stream.presentation.web import register_static_and_spa


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncGenerator[None, None]:
    """Application lifespan context manager for startup and shutdown hooks."""
    # Initialize metadata database
    await init_db()
    # Load persisted cumulative read/write telemetry
    await usage_tracker.load_from_db()
    yield
    # Save final cumulative read/write telemetry on shutdown
    await usage_tracker.save_to_db()


def create_app() -> FastAPI:
    """Create and configure the FastAPI application instance."""
    app = FastAPI(
        title=settings.app_name,
        version=settings.app_version,
        description="Physical source abstraction and data infrastructure service for the Altr Mesh.",
        lifespan=lifespan,
    )

    # Enable CORS for local mesh and Flutter Web development
    app.add_middleware(
        CORSMiddleware,
        allow_origins=["*"],
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    # Master API v1 Router
    app.include_router(api_v1_router)

    # Static assets and Flutter Web SPA routing
    register_static_and_spa(app)

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
