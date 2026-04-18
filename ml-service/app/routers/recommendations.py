from __future__ import annotations

from typing import Optional

from fastapi import APIRouter, Query, Request
from pydantic import BaseModel

from app.runtime_state import get_recommender_from_request

router = APIRouter()


class RecommendationItem(BaseModel):
    tmdb_id: int
    media_type: str
    score: float
    reason: str
    algorithm: str


@router.get("/recommend/{user_id}", response_model=list[RecommendationItem])
async def get_recommendations(
    request: Request,
    user_id: str,
    genre_filter: Optional[str] = None,
    limit: int = Query(default=30, ge=1, le=100),
    exclude_tmdb_ids: Optional[list[int]] = Query(default=None),
):
    recommender = get_recommender_from_request(request)
    return recommender.recommend_for_user(
        user_id=user_id,
        genre_filter=genre_filter,
        top_n=limit,
        exclude_tmdb_ids=exclude_tmdb_ids or [],
    )


@router.get("/similar/{tmdb_id}", response_model=list[RecommendationItem])
async def get_similar(
    request: Request,
    tmdb_id: int,
    limit: int = Query(default=20, ge=1, le=100),
):
    recommender = get_recommender_from_request(request)
    return recommender.find_similar(tmdb_id=tmdb_id, top_n=limit)

