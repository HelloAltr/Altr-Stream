"""Altr Stream main FastAPI application entry point."""

from collections.abc import AsyncGenerator
from contextlib import asynccontextmanager
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from altr_stream.config import settings
from altr_stream.infrastructure.database.session import init_db
from altr_stream.presentation.api.router import api_v1_router


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

    # Enable CORS for local mesh and Flutter Web development
    app.add_middleware(
        CORSMiddleware,
        allow_origins=["*"],
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    # Root service metadata endpoint
    @app.get("/", include_in_schema=False)
    async def root_info() -> JSONResponse:
        return JSONResponse(
            {
                "service": settings.app_name,
                "version": settings.app_version,
                "status": "healthy",
                "docs_url": "/docs",
                "api_v1_prefix": "/api/v1",
            }
        )

    # Master API v1 Router
    app.include_router(api_v1_router)

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
