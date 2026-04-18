-- pgvector is pre-enabled on Supabase, no need to create it here
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
  vote_average DECIMAL(3, 1),
  vote_count INTEGER,
  popularity DECIMAL(10, 3),
  imdb_id TEXT,
  tmdb_data JSONB,
  embedding extensions.vector(552),
  last_synced_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE (tmdb_id, media_type)
);

CREATE TABLE public.logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  content_id INTEGER REFERENCES public.content(id),
  tmdb_id INTEGER NOT NULL,
  media_type TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'watched'
    CHECK (status IN ('watched', 'watching', 'watchlist', 'dropped', 'plan_to_watch')),
  rating DECIMAL(2, 1) CHECK (rating >= 0.5 AND rating <= 5.0),
  liked BOOLEAN DEFAULT false,
  rewatch BOOLEAN DEFAULT false,
  rewatch_count INTEGER DEFAULT 0,
  watched_date DATE,
  review TEXT,
  tags TEXT[] DEFAULT '{}',
  is_private BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE (user_id, content_id, rewatch_count)
);

CREATE TABLE public.reviews (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
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
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
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
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  list_id UUID NOT NULL REFERENCES public.lists(id) ON DELETE CASCADE,
  content_id INTEGER NOT NULL REFERENCES public.content(id),
  tmdb_id INTEGER NOT NULL,
  media_type TEXT NOT NULL,
  position INTEGER,
  note TEXT,
  added_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE (list_id, content_id)
);

CREATE TABLE public.follows (
  follower_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
  following_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
  PRIMARY KEY (follower_id, following_id)
);

CREATE TABLE public.recommendations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  content_id INTEGER REFERENCES public.content(id),
  tmdb_id INTEGER NOT NULL,
  media_type TEXT NOT NULL,
  score DECIMAL(6, 4) NOT NULL,
  reason TEXT,
  reason_content_ids INTEGER[] DEFAULT '{}',
  algorithm TEXT NOT NULL,
  genre_filter TEXT,
  computed_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE (user_id, tmdb_id)
);

CREATE TABLE public.user_vectors (
  user_id UUID PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
  vector extensions.vector(552),
  computed_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE public.activity (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
  activity_type TEXT NOT NULL,
  target_id UUID,
  content_id INTEGER REFERENCES public.content(id),
  metadata JSONB DEFAULT '{}',
  created_at TIMESTAMPTZ DEFAULT NOW()
);
