import os
import platform
import time

from fastapi import APIRouter
from altr_stream.config import settings
from altr_stream.presentation.api.dtos import HealthResponseDTO

router = APIRouter(tags=["Health"])

_NODE_START_TIME = time.time()


@router.get("/health", response_model=HealthResponseDTO)
async def health_check() -> HealthResponseDTO:
    """Return live health and telemetry status of Altr Stream service."""
    now = time.time()
    uptime_sec = max(0.0, round(now - _NODE_START_TIME, 1))
    hours = int(uptime_sec // 3600)
    minutes = int((uptime_sec % 3600) // 60)
    seconds = int(uptime_sec % 60)
    uptime_str = f"{hours}h {minutes}m {seconds}s" if hours > 0 else f"{minutes}m {seconds}s"

    memory_mb = None
    try:
        import psutil
        process = psutil.Process(os.getpid())
        memory_mb = round(process.memory_info().rss / (1024 * 1024), 1)
    except Exception:
        try:
            import resource
            rss = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
            # On Linux ru_maxrss is in KB, on macOS it is in bytes
            memory_mb = round(rss / 1024.0 if platform.system() == "Linux" else rss / (1024.0 * 1024.0), 1)
        except Exception:
            memory_mb = None

    return HealthResponseDTO(
        status="healthy",
        version=settings.app_version,
        service=settings.app_name,
        engine=f"uvicorn / Python {platform.python_version()} / asyncio",
        uptime=uptime_str,
        uptime_seconds=uptime_sec,
        memory_mb=memory_mb,
        role="standalone leader",
    )
