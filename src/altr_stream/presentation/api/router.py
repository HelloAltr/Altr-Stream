"""API v1 master router."""

from fastapi import APIRouter
from altr_stream.presentation.api.routes import altrql, health, queries, sources

api_v1_router = APIRouter(prefix="/api/v1")
api_v1_router.include_router(health.router)
api_v1_router.include_router(sources.router)
api_v1_router.include_router(queries.router)
api_v1_router.include_router(altrql.router)

