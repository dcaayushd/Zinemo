from __future__ import annotations

import joblib
import numpy as np
from implicit.als import AlternatingLeastSquares
from scipy.sparse import csr_matrix


class ALSRecommender:
    def __init__(
        self,
        factors: int = 64,
        iterations: int = 20,
        regularization: float = 0.01,
        alpha: float = 40.0,
        random_state: int = 42,
    ):
        self.model = AlternatingLeastSquares(
            factors=factors,
            iterations=iterations,
            regularization=regularization,
            random_state=random_state,
            use_gpu=False,
        )
        self.alpha = alpha
        self._is_trained = False
        self._user_items: csr_matrix | None = None

    def train(self, interactions: csr_matrix) -> dict:
        confidence_matrix = (interactions * self.alpha).astype(np.float32)
        self._user_items = confidence_matrix.tocsr()
        self.model.fit(confidence_matrix.T.tocsr())
        self._is_trained = True
        return {
            "model": "ALS",
            "factors": self.model.factors,
            "iterations": self.model.iterations,
            "n_users": interactions.shape[0],
            "n_items": interactions.shape[1],
        }

    def predict_for_user(
        self,
        user_index: int,
        already_seen_indices: list[int],
        top_n: int = 50,
    ) -> list[tuple[int, float]]:
        assert self._is_trained
        assert self._user_items is not None
        if top_n <= 0:
            return []

        n_items = int(self._user_items.shape[1])
        if n_items <= 0:
            return []

        request_n = min(n_items, top_n + len(already_seen_indices))
        if request_n <= 0:
            return []

        item_ids, scores = self.model.recommend(
            userid=user_index,
            user_items=self._user_items,
            N=request_n,
            filter_already_liked_items=False,
        )

        seen = set(already_seen_indices)
        results = [
            (int(item_id), float(score))
            for item_id, score in zip(item_ids, scores)
            if int(item_id) not in seen
        ]
        return results[:top_n]

    def save(self, path: str):
        joblib.dump(
            {
                "model": self.model,
                "alpha": self.alpha,
                "user_items": self._user_items,
            },
            path,
        )

    @classmethod
    def load(cls, path: str) -> "ALSRecommender":
        payload = joblib.load(path)
        instance = cls(alpha=payload["alpha"])
        instance.model = payload["model"]
        instance._user_items = payload["user_items"]
        instance._is_trained = True
        return instance
