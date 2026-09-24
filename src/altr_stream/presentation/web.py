"""Static asset and Flutter Web SPA routing handler."""

from pathlib import Path
from fastapi import FastAPI, Request, Response
from fastapi.responses import FileResponse, JSONResponse

from altr_stream.config import settings


def register_static_and_spa(app: FastAPI, static_dir: Path | None = None) -> None:
    """Register static asset serving and SPA fallback routes for Flutter Admin UI.

    In unified production packaging, compiled Flutter assets are placed in /app/static.
    FastAPI serves static assets directly at / while ensuring /api/v1/* and API docs
    are never intercepted by the SPA fallback.
    """
    resolved_dir = static_dir or settings.static_dir
    dir_path = Path(resolved_dir).resolve() if resolved_dir else None

    # Check if directory exists and has files
    has_static = dir_path is not None and dir_path.is_dir()

    @app.get("/", include_in_schema=False)
    async def root_endpoint(request: Request) -> Response:
        accept = request.headers.get("accept", "")
        if has_static:
            index_file = dir_path / "index.html"
            if "text/html" in accept and index_file.is_file():
                return FileResponse(
                    index_file,
                    media_type="text/html",
                    headers={"Cache-Control": "no-cache, no-store, must-revalidate"},
                )

        # Default to JSON service metadata for API callers or when static assets are absent
        return JSONResponse(
            {
                "service": settings.app_name,
                "version": settings.app_version,
                "status": "healthy",
                "docs_url": "/docs",
                "api_v1_prefix": "/api/v1",
            }
        )

    if not has_static:
        return

    # Catch-all route for static assets and SPA client-side routes.
    # Registered LAST so all FastAPI API routes, /docs, /redoc, etc. take precedence.
    @app.get("/{full_path:path}", include_in_schema=False)
    async def spa_fallback(request: Request, full_path: str) -> Response:
        # Critical security & routing invariant:
        # Never intercept API routes with SPA HTML - return standard 404 JSON
        if full_path.startswith("api/") or full_path == "api":
            return JSONResponse({"detail": "Not Found"}, status_code=404)

        # Attempt to serve exact static file if it exists inside static_dir
        target_file = (dir_path / full_path).resolve()

        # Security: protect against path traversal outside dir_path
        if str(target_file).startswith(str(dir_path)) and target_file.is_file():
            headers: dict[str, str] = {}
            if full_path in (
                "index.html",
                "flutter_bootstrap.js",
                "flutter_service_worker.js",
                "version.json",
                "manifest.json",
            ):
                headers["Cache-Control"] = "no-cache, no-store, must-revalidate"
            else:
                headers["Cache-Control"] = "public, max-age=31536000, immutable"

            return FileResponse(target_file, headers=headers)

        # If requesting a subroute (e.g. /sources, /registry, /settings) without file extension,
        # serve index.html for client-side SPA routing.
        index_file = dir_path / "index.html"
        if index_file.is_file() and not Path(full_path).suffix:
            return FileResponse(
                index_file,
                media_type="text/html",
                headers={"Cache-Control": "no-cache, no-store, must-revalidate"},
            )

        return JSONResponse({"detail": "Not Found"}, status_code=404)
