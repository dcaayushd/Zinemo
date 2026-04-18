CREATE OR REPLACE FUNCTION match_content_by_embedding(
  query_embedding extensions.vector(552),
  match_threshold float,
  match_count int,
  exclude_tmdb_ids int[],
  genre_filter text DEFAULT NULL
)
RETURNS TABLE (
  tmdb_id int,
  media_type text,
  title text,
  poster_path text,
  similarity float
)
LANGUAGE plpgsql
AS $$
BEGIN
  RETURN QUERY
  SELECT
    c.tmdb_id,
    c.media_type,
    c.title,
    c.poster_path,
    1 - (c.embedding <=> query_embedding) AS similarity
  FROM public.content c
  WHERE
    c.embedding IS NOT NULL
    AND NOT (c.tmdb_id = ANY(exclude_tmdb_ids))
    AND (genre_filter IS NULL OR c.genres::text ILIKE '%' || genre_filter || '%')
    AND 1 - (c.embedding <=> query_embedding) > match_threshold
  ORDER BY c.embedding <=> query_embedding
  LIMIT match_count;
END;
$$;
