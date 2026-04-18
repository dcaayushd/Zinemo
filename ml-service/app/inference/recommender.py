from __future__ import annotations

from pathlib import Path
from typing import Any

from app.config import get_settings
from app.data.interaction_matrix import map_seen_tmdb_ids_to_item_indices
from app.inference.cold_start import ColdStartHandler
from app.inference.explainer import RecommendationExplainer
from app.models.hybrid_ranker import HybridRanker
from app.storage.model_store import ModelStore
from app.storage.supabase_client import SupabaseClient


class Recommender:
    def __init__(
        self,
        *,
        lightfm,
        als,
        content_model,
        dataset,
        feature_builder,
        interaction_feature_matrix,
        full_feature_matrix,
        content_items: list[dict],
        db: SupabaseClient | None = None,
    ):
        self.lightfm = lightfm
        self.als = als
        self.content_model = content_model
        self.dataset = dataset
        self.feature_builder = feature_builder
        self.interaction_feature_matrix = interaction_feature_matrix
        self.full_feature_matrix = full_feature_matrix
        self.content_items = content_items
        self.models_ready = (
            self.lightfm is not None
            and self.als is not None
            and self.content_model is not None
            and self.dataset is not None
            and self.interaction_feature_matrix is not None
        )
        self.cold_start = ColdStartHandler()
        self.ranker = HybridRanker()
        self.explainer = RecommendationExplainer()
        self.db = db or SupabaseClient()

        self.content_by_tmdb = {
            int(item["tmdb_id"]): item for item in content_items if "tmdb_id" in item
        }
        self.genre_map = {
            tmdb_id: [
                str(genre.get("name", "")).strip()
                for genre in (item.get("genres") or [])
                if isinstance(genre, dict)
                and isinstance(genre.get("name"), str)
                and str(genre.get("name", "")).strip()
            ]
            for tmdb_id, item in self.content_by_tmdb.items()
        }

    @classmethod
    def load_from_disk(cls) -> "Recommender":
        settings = get_settings()
        store = ModelStore(settings.model_dir)
        artifacts = store.load_all()
        return cls(**artifacts)

    @classmethod
    def bootstrap_without_models(cls) -> "Recommender":
        db = SupabaseClient()
        return cls(
            lightfm=None,
            als=None,
            content_model=None,
            dataset=None,
            feature_builder=None,
            interaction_feature_matrix=None,
            full_feature_matrix=None,
            content_items=db.fetch_all_content(),
            db=db,
        )

    def recommend_for_user(
        self,
        user_id: str,
        genre_filter: str | None = None,
        top_n: int = 30,
        exclude_tmdb_ids: list[int] | None = None,
    ) -> list[dict]:
        if top_n <= 0:
            return []

        excluded = {int(tmdb_id) for tmdb_id in (exclude_tmdb_ids or [])}
        logs = self.db.fetch_user_logs(user_id)
        profile = self.db.fetch_user_profile(user_id) or {}
        all_content = list(self.content_by_tmdb.values())
        already_seen_ids = [int(log["tmdb_id"]) for log in logs]
        already_seen_ids.extend(excluded)
        preferred_genres = self._extract_preferred_genres(profile)

        if len(logs) < 5 or not self.models_ready:
            return self.cold_start.get_cold_start_recs(
                preferred_genres=preferred_genres,
                all_content=all_content,
                already_seen=already_seen_ids,
                genre_filter=genre_filter,
                top_n=top_n,
            )

        ratings = {
            int(log["tmdb_id"]): float(log.get("rating") or 3.0) for log in logs
        }
        liked_tmdb_ids = [
            int(log["tmdb_id"])
            for log in logs
            if bool(log.get("liked")) or float(log.get("rating") or 0) >= 3.5
        ]

        user_index = self.dataset.user_id_map.get(user_id)
        seen_interaction_indices = map_seen_tmdb_ids_to_item_indices(
            already_seen_ids,
            self.dataset.item_id_map,
        )

        lightfm_scores: dict[int, float] = {}
        als_scores: dict[int, float] = {}

        try:
            if user_index is not None:
                lightfm_scores = {
                    self.dataset.reverse_item_map[item_index]: score
                    for item_index, score in self.lightfm.predict_for_user(
                        user_index=user_index,
                        item_features=self.interaction_feature_matrix,
                        n_items=self.dataset.n_items,
                        already_seen_indices=seen_interaction_indices,
                        top_n=top_n * 3,
                    )
                }

                als_scores = {
                    self.dataset.reverse_item_map[item_index]: score
                    for item_index, score in self.als.predict_for_user(
                        user_index=user_index,
                        already_seen_indices=seen_interaction_indices,
                        top_n=top_n * 3,
                    )
                }
        except Exception as error:
            print(f"Collaborative scoring unavailable, using cold-start fallback: {error}")
            return self.cold_start.get_cold_start_recs(
                preferred_genres=preferred_genres,
                all_content=all_content,
                already_seen=already_seen_ids,
                genre_filter=genre_filter,
                top_n=top_n,
            )

        content_scores: dict[int, float] = {}
        if self.content_model is not None and getattr(self.content_model, "_is_fitted", False):
            content_scores = {
                tmdb_id: score
                for tmdb_id, score in self.content_model.predict_for_user(
                    liked_tmdb_ids=liked_tmdb_ids,
                    ratings=ratings,
                    already_seen_tmdb_ids=already_seen_ids,
                    top_n=top_n * 4,
                )
            }

        popularity_scores = self._build_popularity_scores(already_seen_ids)
        ranked = self.ranker.rank(
            lightfm_scores=lightfm_scores,
            als_scores=als_scores,
            content_scores=content_scores,
            popularity_scores=popularity_scores,
            n_interactions=len(logs),
            genre_filter=genre_filter,
            content_genre_map=self.genre_map,
            top_n=top_n,
        )

        seed_title = self._best_seed_title(ratings)
        recommendations: list[dict] = []
        for ranked_item in ranked:
            content = self.content_by_tmdb.get(ranked_item.tmdb_id)
            if not content:
                continue

            genre_name = self._primary_genre_name(ranked_item.tmdb_id)
            recommendations.append(
                {
                    "tmdb_id": ranked_item.tmdb_id,
                    "media_type": content.get("media_type", ranked_item.media_type),
                    "score": ranked_item.final_score,
                    "reason": self.explainer.generate(
                        ranked_item.algorithm,
                        seed_title=seed_title,
                        genre=genre_name,
                    ),
                    "algorithm": ranked_item.algorithm,
                }
            )

        self.db.write_recommendations(user_id, recommendations, genre_filter)
        return recommendations

    def find_similar(self, tmdb_id: int, top_n: int = 20) -> list[dict]:
        if top_n <= 0:
            return []

        if self.content_model is None or not getattr(self.content_model, "_is_fitted", False):
            return []

        seed_title = self.content_by_tmdb.get(tmdb_id, {}).get("title")
        recommendations: list[dict] = []
        for similar_tmdb_id, score in self.content_model.find_similar_to_item(tmdb_id, top_n):
            content = self.content_by_tmdb.get(similar_tmdb_id)
            if not content:
                continue
            genre_name = self._primary_genre_name(similar_tmdb_id)
            recommendations.append(
                {
                    "tmdb_id": similar_tmdb_id,
                    "media_type": content.get("media_type", "movie"),
                    "score": round(score, 6),
                    "reason": self.explainer.generate(
                        "content",
                        seed_title=str(seed_title) if seed_title else None,
                        genre=genre_name,
                    ),
                    "algorithm": "content",
                }
            )
        return recommendations

    def _build_popularity_scores(self, already_seen_ids: list[int]) -> dict[int, float]:
        scores: dict[int, float] = {}
        for tmdb_id, item in self.content_by_tmdb.items():
            if tmdb_id in already_seen_ids:
                continue
            scores[tmdb_id] = float(item.get("popularity") or 0.0)
        return scores

    def _best_seed_title(self, ratings: dict[int, float]) -> str | None:
        if not ratings:
            return None
        best_tmdb_id = max(ratings, key=ratings.get)
        best_item = self.content_by_tmdb.get(best_tmdb_id)
        return str(best_item.get("title")) if best_item else None

    def _primary_genre_name(self, tmdb_id: int) -> str:
        genres = self.genre_map.get(tmdb_id) or []
        for genre_name in genres:
            if isinstance(genre_name, str) and genre_name.strip():
                return genre_name.strip()

        content_item = self.content_by_tmdb.get(tmdb_id) or {}
        for raw_genre in (content_item.get("genres") or []):
            if isinstance(raw_genre, dict):
                name = raw_genre.get("name")
                if isinstance(name, str) and name.strip():
                    return name.strip()
            elif isinstance(raw_genre, str) and raw_genre.strip():
                return raw_genre.strip()

        return "this genre"

    def _extract_preferred_genres(self, profile: dict[str, Any]) -> list[int | str]:
        preferences = profile.get("preferences") or {}
        if isinstance(preferences, str):
            try:
                import json

                preferences = json.loads(preferences)
            except Exception:
                preferences = {}

        genres = preferences.get("genres", []) if isinstance(preferences, dict) else []
        extracted: list[int | str] = []
        for genre in genres:
            if isinstance(genre, str):
                extracted.append(genre)
            elif isinstance(genre, (int, float)):
                extracted.append(int(genre))
        return extracted
