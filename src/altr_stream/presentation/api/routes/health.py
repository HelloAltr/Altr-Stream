"""Health check API endpoint."""

from fastapi import APIRouter
from altr_stream.config import settings
from altr_stream.presentation.api.dtos import HealthResponseDTO

router = APIRouter(tags=["Health"])


@router.get("/health", response_model=HealthResponseDTO)
async def health_check() -> HealthResponseDTO:
    """Return basic health status of Altr Stream service."""
    return HealthResponseDTO(
        status="healthy",
        version=settings.app_version,
        service=settings.app_name,
    )
