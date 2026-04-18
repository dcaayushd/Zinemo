from __future__ import annotations

from datetime import datetime
from pathlib import Path

import joblib


class ModelStore:
    def __init__(self, root: Path):
        self.root = Path(root)
        self.root.mkdir(parents=True, exist_ok=True)
        self.latest_file = self.root / "latest.txt"

    def save_all(
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
    ) -> Path:
        version = datetime.utcnow().strftime("%Y%m%dT%H%M%SZ")
        version_dir = self.root / version
        version_dir.mkdir(parents=True, exist_ok=True)

        lightfm.save(str(version_dir / "lightfm.pkl"))
        als.save(str(version_dir / "als.pkl"))
        content_model.save(str(version_dir / "content_model.pkl"))

        joblib.dump(
            {
                "dataset": dataset,
                "feature_builder": feature_builder,
                "interaction_feature_matrix": interaction_feature_matrix,
                "full_feature_matrix": full_feature_matrix,
                "content_items": content_items,
            },
            version_dir / "artifacts.pkl",
        )

        self.latest_file.write_text(version, encoding="utf-8")
        return version_dir

    def load_all(self) -> dict:
        if not self.latest_file.exists():
            raise FileNotFoundError("No saved model version found")

        version = self.latest_file.read_text(encoding="utf-8").strip()
        version_dir = self.root / version
        if not version_dir.exists():
            raise FileNotFoundError(f"Saved model directory {version_dir} is missing")

        from app.models.als_model import ALSRecommender
        from app.models.content_model import ContentBasedRecommender
        from app.models.lightfm_model import LightFMRecommender

        artifacts = joblib.load(version_dir / "artifacts.pkl")
        return {
            "lightfm": LightFMRecommender.load(str(version_dir / "lightfm.pkl")),
            "als": ALSRecommender.load(str(version_dir / "als.pkl")),
            "content_model": ContentBasedRecommender.load(
                str(version_dir / "content_model.pkl")
            ),
            "dataset": artifacts["dataset"],
            "feature_builder": artifacts["feature_builder"],
            "interaction_feature_matrix": artifacts["interaction_feature_matrix"],
            "full_feature_matrix": artifacts["full_feature_matrix"],
            "content_items": artifacts["content_items"],
        }
