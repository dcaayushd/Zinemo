"""Tests for the FastAPI app recommender layer."""

from __future__ import annotations

import app.inference.recommender as recommender_module
from app.inference.recommender import Recommender
from app.models.hybrid_ranker import RankedRecommendation


CONTENT_ITEMS = [
    {
        "tmdb_id": 101,
        "media_type": "movie",
        "title": "Action One",
        "genres": [{"id": 28, "name": "Action"}],
        "vote_average": 8.2,
        "popularity": 500.0,
    },
    {
        "tmdb_id": 202,
        "media_type": "movie",
        "title": "Drama Two",
        "genres": [{"id": 18, "name": "Drama"}],
        "vote_average": 7.1,
        "popularity": 300.0,
    },
]


class FakeDb:
    def __init__(self, logs: list[dict] | None = None):
        self.logs = logs or []
        self.writes: list[tuple[str, list[dict], str | None]] = []

    def fetch_user_logs(self, _user_id: str) -> list[dict]:
        return self.logs

    def fetch_user_profile(self, _user_id: str) -> dict:
        return {"preferences": {"genres": [28]}}

    def write_recommendations(
        self,
        user_id: str,
        recommendations: list[dict],
        genre_filter: str | None = None,
    ) -> None:
        self.writes.append((user_id, recommendations, genre_filter))

    def fetch_all_content(self) -> list[dict]:
        return CONTENT_ITEMS


def test_bootstrap_without_models_loads_catalog(monkeypatch):
    monkeypatch.setattr(recommender_module, "SupabaseClient", FakeDb)

    recommender = Recommender.bootstrap_without_models()

    assert recommender.models_ready is False
    assert len(recommender.content_items) == 2


def test_recommend_for_user_uses_cold_start_when_models_unavailable():
    db = FakeDb(
        logs=[
            {
                "tmdb_id": 101,
                "status": "watched",
                "rating": 4.5,
                "liked": True,
                "rewatch": False,
            }
            for _ in range(6)
        ]
    )

    recommender = Recommender(
        lightfm=None,
        als=None,
        content_model=None,
        dataset=None,
        feature_builder=None,
        interaction_feature_matrix=None,
        full_feature_matrix=None,
        content_items=CONTENT_ITEMS,
        db=db,
    )

    recommendations = recommender.recommend_for_user("user-1", top_n=5)

    assert recommendations
    assert all(item["algorithm"] == "cold_start" for item in recommendations)
    assert db.writes == []


class _FakeDataset:
    user_id_map = {"user-1": 0}
    item_id_map = {303: 0}
    reverse_item_map = {0: 303}
    n_items = 1


class _FakeLightFM:
    def predict_for_user(self, **_kwargs):
        return [(0, 0.9)]


class _FakeALS:
    def predict_for_user(self, **_kwargs):
        return [(0, 0.8)]


class _FakeContentModel:
    _is_fitted = True

    def predict_for_user(self, **_kwargs):
        return [(303, 0.7)]

    def find_similar_to_item(self, *_args, **_kwargs):
        return [(303, 0.6)]


class _FakeRanker:
    def rank(self, **_kwargs):
        return [
            RankedRecommendation(
                tmdb_id=303,
                media_type="movie",
                final_score=0.99,
                lightfm_score=1.0,
                als_score=0.8,
                content_score=0.7,
                popularity_score=0.2,
                reason="",
                algorithm="content",
            )
        ]


def test_recommend_for_user_handles_items_without_genres():
    content_items = [
        {
            "tmdb_id": 101,
            "media_type": "movie",
            "title": "Seed",
            "genres": [{"id": 18, "name": "Drama"}],
            "popularity": 100.0,
        },
        {
            "tmdb_id": 303,
            "media_type": "movie",
            "title": "Genreless Pick",
            "genres": [],
            "popularity": 50.0,
        },
    ]

    db = FakeDb(
        logs=[
            {
                "tmdb_id": 101,
                "status": "watched",
                "rating": 4.5,
                "liked": True,
                "rewatch": False,
            }
            for _ in range(6)
        ]
    )

    recommender = Recommender(
        lightfm=_FakeLightFM(),
        als=_FakeALS(),
        content_model=_FakeContentModel(),
        dataset=_FakeDataset(),
        feature_builder=None,
        interaction_feature_matrix=[[0.0]],
        full_feature_matrix=None,
        content_items=content_items,
        db=db,
    )
    recommender.ranker = _FakeRanker()

    recommendations = recommender.recommend_for_user("user-1", top_n=5)

    assert recommendations
    assert recommendations[0]["tmdb_id"] == 303
    assert recommendations[0]["reason"]
    assert db.writes


def test_find_similar_handles_items_without_genres():
    content_items = [
        {
            "tmdb_id": 101,
            "media_type": "movie",
            "title": "Seed",
            "genres": [{"id": 18, "name": "Drama"}],
            "popularity": 100.0,
        },
        {
            "tmdb_id": 303,
            "media_type": "movie",
            "title": "Genreless Similar",
            "genres": [],
            "popularity": 50.0,
        },
    ]

    recommender = Recommender(
        lightfm=_FakeLightFM(),
        als=_FakeALS(),
        content_model=_FakeContentModel(),
        dataset=_FakeDataset(),
        feature_builder=None,
        interaction_feature_matrix=[[0.0]],
        full_feature_matrix=None,
        content_items=content_items,
        db=FakeDb(),
    )

    similar = recommender.find_similar(101, top_n=5)

    assert similar
    assert similar[0]["tmdb_id"] == 303
    assert similar[0]["reason"]
