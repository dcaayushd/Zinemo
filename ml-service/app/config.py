from __future__ import annotations

import os
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path


@dataclass(frozen=True)
class Settings:
    supabase_url: str = os.getenv("SUPABASE_URL", "")
    supabase_service_key: str = os.getenv("SUPABASE_SERVICE_KEY", "")
    model_dir: Path = Path(os.getenv("MODEL_DIR", "/tmp/zinemo_models"))
    node_api_url: str = os.getenv("NODE_API_URL", "*")
    recommendation_mode: str = os.getenv("RECOMMENDATION_MODE", "scratch")
    port: int = int(os.getenv("PORT", "8000"))


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    return Settings()
