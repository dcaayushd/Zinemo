-- Fix the logs table constraint to match the upsert logic
-- Drop the old constraint and create the correct one

ALTER TABLE public.logs
DROP CONSTRAINT IF EXISTS logs_user_id_content_id_rewatch_count_key;

-- Create the new constraint that matches the upsert logic
ALTER TABLE public.logs
ADD CONSTRAINT logs_user_id_tmdb_id_media_type_key UNIQUE (user_id, tmdb_id, media_type);
