"""Edge-case tests for content feature construction."""

from __future__ import annotations

import numpy as np

import app.data.feature_builder as feature_builder_module
from app.data.feature_builder import ContentFeatureBuilder, EXPECTED_FEATURE_DIM


class _DummySentenceModel:
    def encode(
        self,
        overviews,
        batch_size=64,
        show_progress_bar=True,
        normalize_embeddings=True,
    ):
        return np.zeros((len(overviews), 384), dtype=np.float32)


def test_build_features_handles_empty_tfidf_vocabulary(monkeypatch):
    monkeypatch.setattr(
        feature_builder_module,
        "SentenceTransformer",
        lambda _model: _DummySentenceModel(),
    )

    builder = ContentFeatureBuilder()
    content_items = [
        {
            "tmdb_id": 1,
            "overview": "the and of",
            "genres": [],
            "runtime": 95,
            "media_type": "movie",
            "vote_count": 10,
            "popularity": 0.0,
            "vote_average": 0.0,
            "release_date": None,
        },
        {
            "tmdb_id": 2,
            "overview": "",
            "genres": [],
            "runtime": 42,
            "media_type": "tv",
            "vote_count": 0,
            "popularity": 0.0,
            "vote_average": 0.0,
            "release_date": None,
        },
    ]

    features = builder.build_features(content_items)

    assert features.shape == (2, EXPECTED_FEATURE_DIM)
    assert np.isfinite(features).all()
