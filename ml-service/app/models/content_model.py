from __future__ import annotations

import joblib
import numpy as np
from sklearn.metrics.pairwise import cosine_similarity


class ContentBasedRecommender:
    def __init__(self):
        self.feature_matrix: np.ndarray | None = None
        self.item_index_map: dict[int, int] = {}
        self._is_fitted = False

    def fit(self, feature_matrix: np.ndarray, item_index_map: dict[int, int]):
        self.feature_matrix = feature_matrix
        self.item_index_map = item_index_map
        self._is_fitted = True

    def build_user_taste_profile(
        self,
        liked_tmdb_ids: list[int],
        ratings: dict[int, float],
    ) -> np.ndarray:
        vectors: list[np.ndarray] = []
        weights: list[float] = []

        for tmdb_id in liked_tmdb_ids:
            index = self.item_index_map.get(tmdb_id)
            if index is None or self.feature_matrix is None:
                continue
            weight = ratings.get(tmdb_id, 3.0) / 5.0
            vectors.append(self.feature_matrix[index] * weight)
            weights.append(weight)

        if not vectors or self.feature_matrix is None:
            return np.zeros(self.feature_matrix.shape[1] if self.feature_matrix is not None else 0)

        profile = np.sum(vectors, axis=0) / (sum(weights) + 1e-9)
        norm = np.linalg.norm(profile)
        return profile / (norm + 1e-9)

    def predict_for_user(
        self,
        liked_tmdb_ids: list[int],
        ratings: dict[int, float],
        already_seen_tmdb_ids: list[int],
        top_n: int = 50,
    ) -> list[tuple[int, float]]:
        assert self._is_fitted
        assert self.feature_matrix is not None
        if top_n <= 0 or self.feature_matrix.shape[0] == 0:
            return []

        top_n = min(top_n, int(self.feature_matrix.shape[0]))

        profile = self.build_user_taste_profile(liked_tmdb_ids, ratings)
        sims = cosine_similarity(profile.reshape(1, -1), self.feature_matrix)[0]

        seen_indices = {
            self.item_index_map[tmdb_id]
            for tmdb_id in already_seen_tmdb_ids
            if tmdb_id in self.item_index_map
        }
        if seen_indices:
            sims[list(seen_indices)] = -1.0

        if top_n == self.feature_matrix.shape[0]:
            top_indices = np.argsort(sims)[::-1]
        else:
            top_indices = np.argpartition(sims, -top_n)[-top_n:]
            top_indices = top_indices[np.argsort(sims[top_indices])[::-1]]
        reverse_item_map = {value: key for key, value in self.item_index_map.items()}

        return [
            (reverse_item_map[int(index)], float(sims[index]))
            for index in top_indices
            if int(index) in reverse_item_map
        ]

    def find_similar_to_item(self, tmdb_id: int, top_n: int = 20) -> list[tuple[int, float]]:
        assert self._is_fitted
        assert self.feature_matrix is not None
        if top_n <= 0 or self.feature_matrix.shape[0] == 0:
            return []

        top_n = min(top_n, int(self.feature_matrix.shape[0]))

        index = self.item_index_map.get(tmdb_id)
        if index is None:
            return []

        item_vector = self.feature_matrix[index].reshape(1, -1)
        sims = cosine_similarity(item_vector, self.feature_matrix)[0]
        sims[index] = -1.0

        if top_n == self.feature_matrix.shape[0]:
            top_indices = np.argsort(sims)[::-1]
        else:
            top_indices = np.argpartition(sims, -top_n)[-top_n:]
            top_indices = top_indices[np.argsort(sims[top_indices])[::-1]]
        reverse_item_map = {value: key for key, value in self.item_index_map.items()}

        return [
            (reverse_item_map[int(candidate)], float(sims[candidate]))
            for candidate in top_indices
            if int(candidate) in reverse_item_map
        ]

    def save(self, path: str):
        joblib.dump(
            {
                "feature_matrix": self.feature_matrix,
                "item_index_map": self.item_index_map,
            },
            path,
        )

    @classmethod
    def load(cls, path: str) -> "ContentBasedRecommender":
        payload = joblib.load(path)
        instance = cls()
        instance.fit(payload["feature_matrix"], payload["item_index_map"])
        return instance
