from __future__ import annotations

from typing import Dict, List

import numpy as np
from sentence_transformers import SentenceTransformer
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.preprocessing import MultiLabelBinarizer, normalize

EMBEDDING_MODEL = "all-MiniLM-L6-v2"
TFIDF_DIM = 110
EXPECTED_FEATURE_DIM = 552

TMDB_GENRE_IDS = [
    28,
    12,
    16,
    35,
    80,
    99,
    18,
    10751,
    14,
    36,
    27,
    10402,
    9648,
    10749,
    878,
    10770,
    53,
    10752,
    37,
]


class ContentFeatureBuilder:
    def __init__(self):
        self.tfidf = TfidfVectorizer(
            max_features=500,
            stop_words="english",
            ngram_range=(1, 2),
        )
        self.genre_binarizer = MultiLabelBinarizer(classes=TMDB_GENRE_IDS)
        self.sentence_model = SentenceTransformer(EMBEDDING_MODEL)
        self._is_fitted = False

    def build_features(self, content_items: List[Dict]) -> np.ndarray:
        if not content_items:
            raise ValueError("ContentFeatureBuilder received no content items")

        overviews = [item.get("overview", "") or "" for item in content_items]
        genres_list = [
            [genre["id"] for genre in (item.get("genres") or []) if "id" in genre]
            for item in content_items
        ]

        embeddings = self.sentence_model.encode(
            overviews,
            batch_size=64,
            show_progress_bar=True,
            normalize_embeddings=True,
        ).astype(np.float32)

        genre_features = self.genre_binarizer.fit_transform(genres_list).astype(np.float32)

        decade_features = np.zeros((len(content_items), 10), dtype=np.float32)
        runtime_features = np.zeros((len(content_items), 3), dtype=np.float32)
        media_features = np.zeros((len(content_items), 3), dtype=np.float32)
        vote_features = np.zeros((len(content_items), 3), dtype=np.float32)

        for index, item in enumerate(content_items):
            year = self._extract_year(item)
            if year:
                decade_index = min(max((year - 1920) // 10, 0), 9)
                decade_features[index, decade_index] = 1.0

            runtime = item.get("runtime") or 0
            if runtime < 60:
                runtime_features[index, 0] = 1.0
            elif runtime <= 150:
                runtime_features[index, 1] = 1.0
            else:
                runtime_features[index, 2] = 1.0

            media_type = item.get("media_type", "movie")
            if media_type == "movie":
                media_features[index, 0] = 1.0
            elif media_type == "tv":
                media_features[index, 1] = 1.0
            else:
                media_features[index, 2] = 1.0

            vote_count = item.get("vote_count") or 0
            if vote_count < 100:
                vote_features[index, 0] = 1.0
            elif vote_count < 1000:
                vote_features[index, 1] = 1.0
            else:
                vote_features[index, 2] = 1.0

        popularities = np.array([item.get("popularity") or 0.0 for item in content_items])
        ratings = np.array([float(item.get("vote_average") or 0.0) for item in content_items])
        popularity_deciles = self._to_decile_features(popularities, 10)
        rating_deciles = self._to_decile_features(ratings, 10)

        try:
            if not self._is_fitted:
                tfidf_matrix = self.tfidf.fit_transform(overviews).toarray()
                self._is_fitted = True
            else:
                tfidf_matrix = self.tfidf.transform(overviews).toarray()
        except ValueError as error:
            if "empty vocabulary" not in str(error):
                raise
            # Catalog overviews can be empty or stop-word-only during bootstrap.
            tfidf_matrix = np.zeros((len(content_items), 0), dtype=np.float32)

        tfidf_reduced = self._to_fixed_width_tfidf(tfidf_matrix, TFIDF_DIM)

        feature_matrix = np.hstack(
            [
                embeddings,
                genre_features,
                decade_features,
                runtime_features,
                media_features,
                vote_features,
                popularity_deciles,
                rating_deciles,
                tfidf_reduced,
            ]
        )

        if feature_matrix.shape[1] != EXPECTED_FEATURE_DIM:
            raise ValueError(
                "Feature dimension mismatch: "
                f"expected {EXPECTED_FEATURE_DIM}, got {feature_matrix.shape[1]}"
            )

        return normalize(feature_matrix, norm="l2")

    def _extract_year(self, item: Dict) -> int | None:
        date = item.get("release_date") or item.get("first_air_date") or ""
        try:
            return int(str(date)[:4]) if date else None
        except (ValueError, TypeError):
            return None

    def _to_decile_features(self, values: np.ndarray, n_bins: int) -> np.ndarray:
        result = np.zeros((len(values), n_bins), dtype=np.float32)
        if values.max(initial=0) == 0:
            return result

        normalized = values / (values.max() + 1e-9)
        bin_indices = (normalized * (n_bins - 1)).astype(int).clip(0, n_bins - 1)
        for index, bin_index in enumerate(bin_indices):
            result[index, bin_index] = 1.0
        return result

    def _to_fixed_width_tfidf(self, matrix: np.ndarray, width: int) -> np.ndarray:
        tfidf = matrix.astype(np.float32)
        if tfidf.shape[1] >= width:
            return tfidf[:, :width]

        padding = np.zeros((tfidf.shape[0], width - tfidf.shape[1]), dtype=np.float32)
        return np.hstack([tfidf, padding])
