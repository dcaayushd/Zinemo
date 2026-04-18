from __future__ import annotations


class ColdStartHandler:
    def get_cold_start_recs(
        self,
        preferred_genres: list[int | str],
        all_content: list[dict],
        already_seen: list[int],
        genre_filter: str | None = None,
        top_n: int = 30,
    ) -> list[dict]:
        if top_n <= 0:
            return []

        seen_ids = set(already_seen)
        normalized_genre_filter = genre_filter.lower() if genre_filter else None

        candidates = [
            content
            for content in all_content
            if int(content["tmdb_id"]) not in seen_ids
            and (
                not preferred_genres
                or any(
                    genre["id"] in preferred_genres
                    or genre.get("name") in preferred_genres
                    for genre in (content.get("genres") or [])
                    if isinstance(genre, dict) and "id" in genre
                )
            )
            and (
                normalized_genre_filter is None
                or any(
                    isinstance(genre, dict)
                    and str(genre.get("name", "")).lower() == normalized_genre_filter
                    for genre in (content.get("genres") or [])
                )
            )
        ]

        if not candidates:
            candidates = [
                content
                for content in all_content
                if int(content["tmdb_id"]) not in seen_ids
                and (
                    normalized_genre_filter is None
                    or any(
                        isinstance(genre, dict)
                        and str(genre.get("name", "")).lower() == normalized_genre_filter
                        for genre in (content.get("genres") or [])
                    )
                )
            ]

        if not candidates:
            return []

        max_popularity = max((content.get("popularity") or 0.0) for content in candidates) + 1e-9
        scored_candidates = []
        for content in candidates:
            normalized_popularity = (content.get("popularity") or 0.0) / max_popularity
            normalized_rating = float(content.get("vote_average") or 0.0) / 10.0
            score = normalized_rating * 0.6 + normalized_popularity * 0.4
            scored_candidates.append((content, score))

        scored_candidates.sort(key=lambda pair: pair[1], reverse=True)

        return [
            {
                "tmdb_id": int(content["tmdb_id"]),
                "media_type": content.get("media_type", "movie"),
                "score": round(score, 4),
                "reason": f"Trending in {self._pick_reason_genre(content)}",
                "algorithm": "cold_start",
            }
            for content, score in scored_candidates[:top_n]
        ]

    def _pick_reason_genre(self, content: dict) -> str:
        genres = content.get("genres") or []
        if genres and isinstance(genres[0], dict):
            return genres[0].get("name", "this genre")
        return "this genre"
