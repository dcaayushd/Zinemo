-- Zinemo Database Schema
-- Supabase/PostgreSQL with Row Level Security (RLS)

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Profiles table (extends auth.users)
CREATE TABLE IF NOT EXISTS profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  full_name TEXT,
  avatar_url TEXT,
  email TEXT NOT NULL,
  subscription_tier TEXT DEFAULT 'free',
  preferences TEXT DEFAULT '{}',
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Content items (movies, TV shows, episodes)
CREATE TABLE IF NOT EXISTS content_items (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  type TEXT NOT NULL CHECK (type IN ('movie', 'tv', 'episode')),
  tmdb_id INTEGER NOT NULL,
  title TEXT NOT NULL,
  original_title TEXT,
  overview TEXT,
  poster_path TEXT,
  backdrop_path TEXT,
  release_date DATE,
  runtime INTEGER,
  genre_ids INTEGER[],
  vote_average DECIMAL(3,2),
  vote_count INTEGER,
  tmdb_metadata JSONB DEFAULT '{}',
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE (type, tmdb_id)
);

-- Content access events (Mode C)
CREATE TABLE IF NOT EXISTS content_access_events (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID REFERENCES profiles(id) ON DELETE SET NULL,
  content_accessed_item_id UUID REFERENCES content_items(id) ON DELETE CASCADE,
  event_type TEXT NOT NULL CHECK (event_type IN ('view', 'search', 'detail', 'similar')),
  item_count INTEGER DEFAULT 1,
  event_date TIMESTAMPTZ DEFAULT NOW(),
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ML predictions table (for LightFM/other models)
CREATE TABLE IF NOT EXISTS ml_predictions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
  predicted_items JSONB NOT NULL,
  prediction_date TIMESTAMPTZ DEFAULT NOW(),
  model_version TEXT DEFAULT 'v1',
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- User ratings
CREATE TABLE IF NOT EXISTS ratings (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
  content_item_id UUID REFERENCES content_items(id) ON DELETE CASCADE,
  rating DECIMAL(3,2) CHECK (rating >= 0 AND rating <= 10),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE (user_id, content_item_id)
);

-- Create indexes
CREATE INDEX idx_profiles_subscription ON profiles(subscription_tier);
CREATE INDEX idx_content_items_type ON content_items(type);
CREATE INDEX idx_content_items_tmdb ON content_items(tmdb_id, type);
CREATE INDEX idx_content_items_genres ON content_items USING GIN(genre_ids);
CREATE INDEX idx_content_access_user ON content_access_events(user_id);
CREATE INDEX idx_content_access_event_type ON content_access_events(event_type);
CREATE INDEX idx_content_access_date ON content_access_events(event_date);
CREATE INDEX idx_ml_predictions_user ON ml_predictions(user_id);
CREATE INDEX idx_ratings_user ON ratings(user_id);
CREATE INDEX idx_ratings_content ON ratings(content_item_id);

-- Enable RLS on all tables
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE content_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE content_access_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE ml_predictions ENABLE ROW LEVEL SECURITY;
ALTER TABLE ratings ENABLE ROW LEVEL SECURITY;

-- Profiles RLS policies
CREATE POLICY "Users can view own profile"
  ON profiles FOR SELECT USING (auth.uid() = id);

CREATE POLICY "Users can update own profile"
  ON profiles FOR UPDATE USING (auth.uid() = id);

-- Content items RLS policies (public read for Mode A)
CREATE POLICY "Anyone can view content items"
  ON content_items FOR SELECT USING (true);

-- Content access events RLS policies
CREATE POLICY "Users can view own access history"
  ON content_access_events FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own access events"
  ON content_access_events FOR INSERT WITH CHECK (auth.uid() = user_id);

-- ML predictions RLS policies
CREATE POLICY "Users can view own predictions"
  ON ml_predictions FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own predictions"
  ON ml_predictions FOR INSERT WITH CHECK (auth.uid() = user_id);

-- Ratings RLS policies
CREATE POLICY "Users can view own ratings"
  ON ratings FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own ratings"
  ON ratings FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own ratings"
  ON ratings FOR UPDATE USING (auth.uid() = user_id);

-- Create trigger to create profile on auth signup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger AS $$
BEGIN
  INSERT INTO public.profiles (id, email, full_name)
  VALUES (
    NEW.id,
    NEW.email,
    COALESCE(NEW.raw_user_meta_data->>'full_name', NULL)
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- Function to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_profiles_updated_at
  BEFORE UPDATE ON profiles
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

COMMENT ON FUNCTION update_updated_at_column IS 'Generic trigger function for updated_at columns';
