from __future__ import annotations

from dataclasses import dataclass
from typing import Dict

import numpy as np
from scipy.sparse import csr_matrix
from supabase import create_client


@dataclass
class InteractionDataset:
    interaction_matrix: csr_matrix
    user_id_map: Dict[str, int]
    item_id_map: Dict[int, int]
    reverse_user_map: Dict[int, str]
    reverse_item_map: Dict[int, int]
    n_users: int
    n_items: int


class DatasetBuilder:
    def __init__(self, supabase_url: str, supabase_key: str):
        self.supabase = create_client(supabase_url, supabase_key)

    def build_interaction_dataset(self) -> InteractionDataset:
        response = (
            self.supabase.table("logs")
            .select("user_id, tmdb_id, media_type, status, rating, liked, rewatch, is_private")
            .eq("is_private", False)
            .execute()
        )

        logs = response.data or []
        if not logs:
            raise ValueError("No interaction data available for training")

        unique_users = list({log["user_id"] for log in logs})
        unique_items = list({int(log["tmdb_id"]) for log in logs})

        user_id_map = {uid: index for index, uid in enumerate(unique_users)}
        item_id_map = {iid: index for index, iid in enumerate(unique_items)}
        reverse_user_map = {index: uid for uid, index in user_id_map.items()}
        reverse_item_map = {index: iid for iid, index in item_id_map.items()}

        rows: list[int] = []
        cols: list[int] = []
        data: list[float] = []

        for log in logs:
            row_index = user_id_map[log["user_id"]]
            col_index = item_id_map[int(log["tmdb_id"])]

            score = 0.0
            status = log.get("status", "watched")
            rating = log.get("rating")
            liked = bool(log.get("liked", False))
            rewatch = bool(log.get("rewatch", False))

            if status == "watched":
                score = float(rating) * 2.0 if rating else 3.0
            elif status == "watching":
                score = 2.0
            elif status == "dropped":
                score = 0.5
            elif status in ("watchlist", "plan_to_watch"):
                score = 1.0

            if liked:
                score += 2.0
            if rewatch:
                score += 1.5

            rows.append(row_index)
            cols.append(col_index)
            data.append(max(0.1, score))

        matrix = csr_matrix(
            (data, (rows, cols)),
            shape=(len(unique_users), len(unique_items)),
            dtype=np.float32,
        )

        return InteractionDataset(
            interaction_matrix=matrix,
            user_id_map=user_id_map,
            item_id_map=item_id_map,
            reverse_user_map=reverse_user_map,
            reverse_item_map=reverse_item_map,
            n_users=len(unique_users),
            n_items=len(unique_items),
        )
