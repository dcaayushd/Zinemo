"""Unit tests for hybrid ranking behavior in app models."""

from __future__ import annotations

import math

from app.models.hybrid_ranker import HybridRanker


def test_user_tier_thresholds_are_stable():
    ranker = HybridRanker()

    assert ranker.get_user_tier(0) == "cold"
    assert ranker.get_user_tier(5) == "warm"
    assert ranker.get_user_tier(20) == "active"
    assert ranker.get_user_tier(100) == "power"


def test_rank_filters_by_genre_and_returns_sorted_scores():
    ranker = HybridRanker()

    ranked = ranker.rank(
        lightfm_scores={101: 0.9, 202: 0.3},
        als_scores={101: 0.2, 303: 0.8},
        content_scores={202: 0.95, 303: 0.4},
        popularity_scores={101: 500.0, 202: 650.0, 303: 100.0},
        n_interactions=30,
        genre_filter="Action",
        content_genre_map={
            101: ["Action", "Thriller"],
            202: ["Drama"],
            303: ["Action"],
        },
        top_n=10,
    )

    assert {item.tmdb_id for item in ranked} == {101, 303}
    assert ranked[0].final_score >= ranked[1].final_score


def test_rank_ignores_non_finite_model_scores():
    ranker = HybridRanker()

    ranked = ranker.rank(
        lightfm_scores={101: float("-inf"), 202: 0.9},
        als_scores={101: float("nan"), 202: 0.8},
        content_scores={101: float("inf"), 202: 0.7},
        popularity_scores={101: 100.0, 202: 50.0},
        n_interactions=30,
        top_n=10,
    )

    assert ranked
    assert all(math.isfinite(item.final_score) for item in ranked)
