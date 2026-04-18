from __future__ import annotations

import joblib
import numpy as np
from lightfm import LightFM
from lightfm.evaluation import auc_score, precision_at_k
from scipy.sparse import csr_matrix


class LightFMRecommender:
    def __init__(
        self,
        n_components: int = 64,
        loss: str = "warp",
        learning_rate: float = 0.05,
        item_alpha: float = 1e-6,
        user_alpha: float = 1e-6,
        max_sampled: int = 10,
        random_state: int = 42,
    ):
        self.model = LightFM(
            no_components=n_components,
            loss=loss,
            learning_rate=learning_rate,
            item_alpha=item_alpha,
            user_alpha=user_alpha,
            max_sampled=max_sampled,
            random_state=random_state,
        )
        self.n_components = n_components
        self._is_trained = False

    def train(
        self,
        interactions: csr_matrix,
        item_features: np.ndarray,
        n_epochs: int = 30,
        n_jobs: int = -1,
        verbose: bool = True,
    ) -> dict:
        item_features_sparse = csr_matrix(item_features)
        binary_interactions = (interactions > 0).astype(np.float32)

        self.model.fit(
            interactions=binary_interactions,
            item_features=item_features_sparse,
            epochs=n_epochs,
            num_threads=n_jobs if n_jobs > 0 else 4,
            verbose=verbose,
        )

        self._is_trained = True

        train_precision = precision_at_k(
            self.model,
            binary_interactions,
            item_features=item_features_sparse,
            k=10,
            num_threads=4,
        ).mean()

        train_auc = auc_score(
            self.model,
            binary_interactions,
            item_features=item_features_sparse,
            num_threads=4,
        ).mean()

        return {
            "precision_at_10": float(train_precision),
            "auc": float(train_auc),
            "n_users": interactions.shape[0],
            "n_items": interactions.shape[1],
            "n_epochs": n_epochs,
        }

    def predict_for_user(
        self,
        user_index: int,
        item_features: np.ndarray,
        n_items: int,
        already_seen_indices: list[int],
        top_n: int = 50,
    ) -> list[tuple[int, float]]:
        assert self._is_trained, "Model must be trained before inference"
        if n_items <= 0 or top_n <= 0:
            return []

        top_n = min(top_n, n_items)

        scores = self.model.predict(
            user_ids=user_index,
            item_ids=np.arange(n_items),
            item_features=csr_matrix(item_features),
            num_threads=4,
        )

        if already_seen_indices:
            seen = [index for index in already_seen_indices if 0 <= index < n_items]
            scores[seen] = -np.inf

        if top_n == n_items:
            top_indices = np.argsort(scores)[::-1]
        else:
            top_indices = np.argpartition(scores, -top_n)[-top_n:]
            top_indices = top_indices[np.argsort(scores[top_indices])[::-1]]
        return [(int(index), float(scores[index])) for index in top_indices]

    def save(self, path: str):
        joblib.dump(
            {
                "model": self.model,
                "n_components": self.n_components,
                "is_trained": self._is_trained,
            },
            path,
        )

    @classmethod
    def load(cls, path: str) -> "LightFMRecommender":
        payload = joblib.load(path)
        instance = cls(n_components=payload["n_components"])
        instance.model = payload["model"]
        instance._is_trained = payload["is_trained"]
        return instance
