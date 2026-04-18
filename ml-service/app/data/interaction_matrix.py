from __future__ import annotations

from typing import Iterable


def map_seen_tmdb_ids_to_item_indices(
    seen_tmdb_ids: Iterable[int],
    item_id_map: dict[int, int],
) -> list[int]:
    return [item_id_map[tmdb_id] for tmdb_id in seen_tmdb_ids if tmdb_id in item_id_map]
