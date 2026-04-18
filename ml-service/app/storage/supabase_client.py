from __future__ import annotations

from typing import Any

try:
    from supabase import Client, create_client
except ModuleNotFoundError:  # pragma: no cover - exercised only in minimal local envs.
    Client = Any

    def create_client(*_args, **_kwargs):
        raise RuntimeError("supabase package is required to create a Supabase client")

from app.config import get_settings


class SupabaseClient:
    def __init__(self):
        settings = get_settings()
        if not settings.supabase_url or not settings.supabase_service_key:
            raise RuntimeError(
                "SUPABASE_URL and SUPABASE_SERVICE_KEY must be configured for the ML service."
            )

        self.client: Client = create_client(
            settings.supabase_url, settings.supabase_service_key
        )

    def fetch_all_content(self) -> list[dict]:
        rows: list[dict] = []
        start = 0
        page_size = 1000
        while True:
            response = (
                self.client.table("content")
                .select(
                    "id, tmdb_id, media_type, title, overview, poster_path, backdrop_path, release_date, genres, runtime, vote_average, vote_count, popularity"
                )
                .range(start, start + page_size - 1)
                .execute()
            )
            batch = response.data or []
            if not batch:
                break
            rows.extend(batch)
            if len(batch) < page_size:
                break
            start += page_size
        return rows

    def fetch_user_logs(self, user_id: str) -> list[dict]:
        response = (
            self.client.table("logs")
            .select("tmdb_id, status, rating, liked, rewatch")
            .eq("user_id", user_id)
            .order("created_at", desc=True)
            .execute()
        )
        return response.data or []

    def fetch_user_profile(self, user_id: str) -> dict | None:
        try:
            response = (
                self.client.table("profiles")
                .select("id, preferences")
                .eq("id", user_id)
                .limit(1)
                .execute()
            )
            rows = response.data or []
            return rows[0] if rows else None
        except Exception:
            return None

    def write_recommendations(
        self,
        user_id: str,
        recommendations: list[dict],
        genre_filter: str | None = None,
    ) -> None:
        if not recommendations:
            return

        content_id_map = self._resolve_content_ids(recommendations)

        payload = [
            {
                "user_id": user_id,
                "tmdb_id": recommendation["tmdb_id"],
                "media_type": recommendation.get("media_type", "movie"),
                "content_id": content_id_map.get(
                    (
                        int(recommendation["tmdb_id"]),
                        str(recommendation.get("media_type", "movie")),
                    )
                ),
                "score": recommendation["score"],
                "reason": recommendation["reason"],
                "algorithm": recommendation["algorithm"],
                "genre_filter": genre_filter,
            }
            for recommendation in recommendations
        ]

        try:
            self.client.table("recommendations").upsert(
                payload,
                on_conflict="user_id,tmdb_id",
            ).execute()
        except Exception:
            # Support installations where unique index is user_id,content_id.
            try:
                if any(record.get("content_id") is not None for record in payload):
                    self.client.table("recommendations").upsert(
                        payload,
                        on_conflict="user_id,content_id",
                    ).execute()
            except Exception:
                # Recommendation writes are useful but non-critical.
                return

    def _resolve_content_ids(
        self,
        recommendations: list[dict],
    ) -> dict[tuple[int, str], int]:
        tmdb_ids = sorted({int(rec["tmdb_id"]) for rec in recommendations if "tmdb_id" in rec})
        if not tmdb_ids:
            return {}

        content_table = self.client.table("content")
        if not all(
            hasattr(content_table, method)
            for method in ("select", "in_", "execute")
        ):
            return {}

        try:
            response = (
                content_table.select("id, tmdb_id, media_type")
                .in_("tmdb_id", tmdb_ids)
                .execute()
            )
        except Exception:
            return {}

        rows = response.data or []
        mapping: dict[tuple[int, str], int] = {}
        for row in rows:
            tmdb_id = row.get("tmdb_id")
            content_id = row.get("id")
            media_type = row.get("media_type", "movie")
            if tmdb_id is None or content_id is None:
                continue
            mapping[(int(tmdb_id), str(media_type))] = int(content_id)
        return mapping
