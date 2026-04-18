CREATE INDEX IF NOT EXISTS content_tmdb_media_idx
  ON public.content (tmdb_id, media_type);

CREATE INDEX IF NOT EXISTS content_genres_idx
  ON public.content USING GIN (genres);

CREATE INDEX IF NOT EXISTS logs_user_created_idx
  ON public.logs (user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS logs_user_status_idx
  ON public.logs (user_id, status);

CREATE INDEX IF NOT EXISTS recommendations_user_score_idx
  ON public.recommendations (user_id, score DESC);

CREATE INDEX IF NOT EXISTS recommendations_user_genre_score_idx
  ON public.recommendations (user_id, genre_filter, score DESC);

-- Run this after bulk-loading content rows into the table.
CREATE INDEX IF NOT EXISTS content_embedding_idx
  ON public.content USING ivfflat (embedding)
  WITH (lists = 100);
