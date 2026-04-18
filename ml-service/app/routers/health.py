from __future__ import annotations

from fastapi import APIRouter, Request

from app.config import get_settings

router = APIRouter()


@router.get("/health")
async def health(request: Request):
    settings = get_settings()
    recommender = getattr(request.app.state, "recommender", None)
    models_ready = bool(recommender and recommender.models_ready)
    return {
        "status": "ok",
        "models_loaded": models_ready,
        "bootstrap_mode": bool(recommender and not models_ready),
        "mode": settings.recommendation_mode,
    }
