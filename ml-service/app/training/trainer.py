from __future__ import annotations

import time
from datetime import datetime

from app.config import get_settings
from app.data.dataset_builder import DatasetBuilder
from app.data.feature_builder import ContentFeatureBuilder
from app.models.als_model import ALSRecommender
from app.models.content_model import ContentBasedRecommender
from app.models.lightfm_model import LightFMRecommender
from app.storage.model_store import ModelStore
from app.storage.supabase_client import SupabaseClient


class TrainingPipeline:
    def __init__(self):
        self.settings = get_settings()
        self.db = SupabaseClient()
        self.store = ModelStore(self.settings.model_dir)

    def run(self) -> dict:
        start = time.time()
        print(f"\n{'=' * 50}")
        print(f"Training pipeline started at {datetime.utcnow().isoformat()}")
        print(f"{'=' * 50}")

        builder = DatasetBuilder(
            self.settings.supabase_url,
            self.settings.supabase_service_key,
        )
        dataset = builder.build_interaction_dataset()
        print(
            f"[1/5] Interaction dataset: {dataset.n_users} users, {dataset.n_items} items, {dataset.interaction_matrix.nnz} interactions"
        )

        all_content = self.db.fetch_all_content()
        content_by_tmdb = {int(item["tmdb_id"]): item for item in all_content}
        for tmdb_id in dataset.item_id_map:
            if tmdb_id not in content_by_tmdb:
                placeholder = {
                    "tmdb_id": tmdb_id,
                    "media_type": "movie",
                    "title": f"TMDB {tmdb_id}",
                    "overview": "",
                    "genres": [],
                    "runtime": 0,
                    "vote_average": 0.0,
                    "vote_count": 0,
                    "popularity": 0.0,
                    "release_date": None,
                    "poster_path": None,
                    "backdrop_path": None,
                }
                all_content.append(placeholder)
                content_by_tmdb[tmdb_id] = placeholder

        interaction_content = [
            content_by_tmdb[dataset.reverse_item_map[index]]
            for index in range(dataset.n_items)
        ]

        feature_builder = ContentFeatureBuilder()
        print("[2/5] Building full catalog feature matrix...")
        full_feature_matrix = feature_builder.build_features(all_content)
        full_item_index_map = {
            int(item["tmdb_id"]): index for index, item in enumerate(all_content)
        }

        interaction_feature_matrix = full_feature_matrix[
            [full_item_index_map[int(item["tmdb_id"])] for item in interaction_content]
        ]
        print(
            f"  Full feature matrix: {full_feature_matrix.shape}; interaction-aligned matrix: {interaction_feature_matrix.shape}"
        )

        print("[3/5] Training LightFM hybrid model...")
        lightfm = LightFMRecommender(n_components=64, loss="warp")
        lightfm_metrics = lightfm.train(
            interactions=dataset.interaction_matrix,
            item_features=interaction_feature_matrix,
            n_epochs=30,
        )

        print("[4/5] Training ALS collaborative model...")
        als = ALSRecommender(factors=64, iterations=20)
        als_metrics = als.train(interactions=dataset.interaction_matrix)

        print("[5/5] Fitting full-catalog content model...")
        content_model = ContentBasedRecommender()
        content_model.fit(full_feature_matrix, full_item_index_map)

        self.store.save_all(
            lightfm=lightfm,
            als=als,
            content_model=content_model,
            dataset=dataset,
            feature_builder=feature_builder,
            interaction_feature_matrix=interaction_feature_matrix,
            full_feature_matrix=full_feature_matrix,
            content_items=all_content,
        )

        elapsed = time.time() - start
        result = {
            "status": "success",
            "trained_at": datetime.utcnow().isoformat(),
            "elapsed_seconds": round(elapsed, 2),
            "n_users": dataset.n_users,
            "n_items": dataset.n_items,
            "lightfm_metrics": lightfm_metrics,
            "als_metrics": als_metrics,
        }
        print(f"Training complete in {elapsed:.1f}s")
        print(f"LightFM P@10={lightfm_metrics['precision_at_10']:.4f}")
        print(f"LightFM AUC={lightfm_metrics['auc']:.4f}")
        return result
