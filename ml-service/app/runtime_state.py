from __future__ import annotations

from fastapi import HTTPException, Request

from app.inference.recommender import Recommender


def get_recommender_from_request(request: Request) -> Recommender:
    recommender = getattr(request.app.state, "recommender", None)
    if recommender is None:
        raise HTTPException(status_code=503, detail="Models not loaded yet")
    return recommender
