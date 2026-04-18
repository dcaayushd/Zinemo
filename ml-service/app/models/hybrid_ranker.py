from __future__ import annotations

from dataclasses import dataclass
import math
from typing import Optional


@dataclass
class RankedRecommendation:
    tmdb_id: int
    media_type: str
    final_score: float
    lightfm_score: float
    als_score: float
    content_score: float
    popularity_score: float
    reason: str
    algorithm: str


class HybridRanker:
    WEIGHT_TIERS = {
        "cold": {"lightfm": 0.05, "als": 0.00, "content": 0.60, "popularity": 0.35},
        "warm": {"lightfm": 0.30, "als": 0.10, "content": 0.45, "popularity": 0.15},
        "active": {"lightfm": 0.45, "als": 0.25, "content": 0.25, "popularity": 0.05},
        "power": {"lightfm": 0.45, "als": 0.35, "content": 0.15, "popularity": 0.05},
    }

    def get_user_tier(self, n_interactions: int) -> str:
        if n_interactions < 5:
            return "cold"
        if n_interactions < 20:
            return "warm"
        if n_interactions < 100:
            return "active"
        return "power"

    def rank(
        self,
        lightfm_scores: dict[int, float],
        als_scores: dict[int, float],
        content_scores: dict[int, float],
        popularity_scores: dict[int, float],
        n_interactions: int,
        genre_filter: Optional[str] = None,
        content_genre_map: dict[int, list[str]] | None = None,
        top_n: int = 50,
    ) -> list[RankedRecommendation]:
        tier = self.get_user_tier(n_interactions)
        weights = self.WEIGHT_TIERS[tier]

        all_items = (
            set(lightfm_scores)
            | set(als_scores)
            | set(content_scores)
            | set(popularity_scores)
        )

        def normalize(score_dict: dict[int, float]) -> dict[int, float]:
            if not score_dict:
                return {}

            finite_scores = {
                key: float(value)
                for key, value in score_dict.items()
                if isinstance(value, (int, float)) and math.isfinite(float(value))
            }
            if not finite_scores:
                return {}

            max_value = max(finite_scores.values())
            min_value = min(finite_scores.values())
            range_value = max_value - min_value
            if range_value <= 1e-12:
                return {key: 1.0 for key in finite_scores}
            return {
                key: (value - min_value) / range_value
                for key, value in finite_scores.items()
            }

        lf_norm = normalize(lightfm_scores)
        als_norm = normalize(als_scores)
        content_norm = normalize(content_scores)
        popularity_norm = normalize(popularity_scores)

        ranked: list[RankedRecommendation] = []
        for tmdb_id in all_items:
            if genre_filter and content_genre_map:
                item_genres = content_genre_map.get(tmdb_id, [])
                if genre_filter.lower() not in [genre.lower() for genre in item_genres]:
                    continue

            lf = lf_norm.get(tmdb_id, 0.0)
            als = als_norm.get(tmdb_id, 0.0)
            content = content_norm.get(tmdb_id, 0.0)
            popularity = popularity_norm.get(tmdb_id, 0.0)

            final_score = (
                weights["lightfm"] * lf
                + weights["als"] * als
                + weights["content"] * content
                + weights["popularity"] * popularity
            )

            scores_by_algorithm = {
                "lightfm": lf * weights["lightfm"],
                "als": als * weights["als"],
                "content": content * weights["content"],
                "popularity": popularity * weights["popularity"],
            }
            dominant_algorithm = max(scores_by_algorithm, key=scores_by_algorithm.get)

            ranked.append(
                RankedRecommendation(
                    tmdb_id=tmdb_id,
                    media_type="movie",
                    final_score=round(final_score, 6),
                    lightfm_score=round(lf, 6),
                    als_score=round(als, 6),
                    content_score=round(content, 6),
                    popularity_score=round(popularity, 6),
                    reason="",
                    algorithm=dominant_algorithm,
                )
            )

        ranked.sort(key=lambda recommendation: recommendation.final_score, reverse=True)
        return ranked[:top_n]
