CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgvector";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";

CREATE TABLE public.profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  username TEXT UNIQUE NOT NULL,
  display_name TEXT,
  avatar_url TEXT,
  bio TEXT,
  preferences JSONB DEFAULT '{}',
  is_private BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE public.content (
  id SERIAL PRIMARY KEY,
  tmdb_id INTEGER NOT NULL,
  media_type TEXT NOT NULL CHECK (media_type IN ('movie', 'tv')),
  title TEXT NOT NULL,
  original_title TEXT,
  overview TEXT,
  poster_path TEXT,
  backdrop_path TEXT,
  release_date DATE,
  genres JSONB DEFAULT '[]',
  runtime INTEGER,
  status TEXT,
  vote_average DECIMAL(3,1),
  vote_count INTEGER,
  popularity DECIMAL(10,3),
  imdb_id TEXT,
  tmdb_data JSONB,
  embedding vector(552),
  last_synced_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(tmdb_id, media_type)
);

CREATE TABLE public.logs (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  content_id INTEGER NOT NULL REFERENCES public.content(id),
  tmdb_id INTEGER NOT NULL,
  media_type TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'watched'
    CHECK (status IN ('watched', 'watching', 'watchlist', 'dropped', 'plan_to_watch')),
  rating DECIMAL(2,1) CHECK (rating >= 0.5 AND rating <= 5.0),
  liked BOOLEAN DEFAULT false,
  rewatch BOOLEAN DEFAULT false,
  rewatch_count INTEGER DEFAULT 0,
  watched_date DATE,
  review TEXT,
  tags TEXT[] DEFAULT '{}',
  is_private BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(user_id, tmdb_id, media_type)
);

CREATE TABLE public.reviews (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  log_id UUID UNIQUE REFERENCES public.logs(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES public.profiles(id),
  content_id INTEGER NOT NULL REFERENCES public.content(id),
  body TEXT NOT NULL,
  contains_spoilers BOOLEAN DEFAULT false,
  like_count INTEGER DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE public.review_likes (
  user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
  review_id UUID REFERENCES public.reviews(id) ON DELETE CASCADE,
  PRIMARY KEY (user_id, review_id)
);

CREATE TABLE public.lists (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  description TEXT,
  is_public BOOLEAN DEFAULT true,
  is_ranked BOOLEAN DEFAULT false,
  cover_tmdb_id INTEGER,
  tags TEXT[] DEFAULT '{}',
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE public.list_items (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  list_id UUID NOT NULL REFERENCES public.lists(id) ON DELETE CASCADE,
  content_id INTEGER NOT NULL REFERENCES public.content(id),
  tmdb_id INTEGER NOT NULL,
  media_type TEXT NOT NULL,
  position INTEGER,
  note TEXT,
  added_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(list_id, content_id)
);

CREATE TABLE public.follows (
  follower_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
  following_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
  PRIMARY KEY (follower_id, following_id)
);

CREATE TABLE public.recommendations (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  content_id INTEGER NOT NULL REFERENCES public.content(id),
  tmdb_id INTEGER NOT NULL,
  media_type TEXT NOT NULL,
  score DECIMAL(6,4) NOT NULL,
  reason TEXT,
  reason_content_ids INTEGER[] DEFAULT '{}',
  algorithm TEXT NOT NULL,
  genre_filter TEXT,
  computed_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(user_id, content_id)
);

CREATE TABLE public.user_vectors (
  user_id UUID PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
  vector vector(552),
  computed_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE public.activity (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  activity_type TEXT NOT NULL,
  target_id UUID,
  content_id INTEGER REFERENCES public.content(id),
  metadata JSONB DEFAULT '{}',
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes
CREATE INDEX ON public.content USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100);
CREATE INDEX ON public.content (tmdb_id, media_type);
CREATE INDEX ON public.content USING GIN (genres);

CREATE INDEX ON public.logs (user_id, created_at DESC);
CREATE INDEX ON public.logs (user_id, status);
CREATE INDEX ON public.logs (content_id);

CREATE INDEX ON public.recommendations (user_id, score DESC);
CREATE INDEX ON public.recommendations (user_id, genre_filter, score DESC);

CREATE INDEX ON public.lists (user_id);
CREATE INDEX ON public.list_items (list_id);

CREATE INDEX ON public.activity (user_id, created_at DESC);
CREATE INDEX ON public.follows (follower_id);
CREATE INDEX ON public.follows (following_id);

-- RLS Policies
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reviews ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.lists ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.recommendations ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Public profiles" ON public.profiles FOR SELECT USING (true);
CREATE POLICY "Own profile update" ON public.profiles FOR UPDATE USING (auth.uid() = id);

CREATE POLICY "View logs" ON public.logs FOR SELECT USING (auth.uid() = user_id OR is_private = false);
CREATE POLICY "Manage own logs" ON public.logs FOR ALL USING (auth.uid() = user_id);

CREATE POLICY "Own recommendations" ON public.recommendations FOR SELECT USING (auth.uid() = user_id);

-- Function: pgvector match content by embedding
CREATE OR REPLACE FUNCTION match_content_by_embedding(
  query_embedding vector(552),
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
