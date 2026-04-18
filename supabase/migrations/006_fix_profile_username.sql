-- Fix profile creation trigger to auto-generate username
-- This resolves the foreign key error when logging movies

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
DROP FUNCTION IF EXISTS public.handle_new_user();

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger AS $$
DECLARE
  v_username TEXT;
BEGIN
  -- Generate a unique username from email or UUID
  v_username := COALESCE(
    SPLIT_PART(NEW.email, '@', 1),
    'user_' || SUBSTRING(NEW.id::TEXT, 1, 8)
  );
  
  -- Ensure uniqueness by appending random suffix if needed
  WHILE EXISTS (SELECT 1 FROM public.profiles WHERE username = v_username) LOOP
    v_username := v_username || '_' || FLOOR(RANDOM() * 9999);
  END LOOP;
  
  INSERT INTO public.profiles (id, username, display_name)
  VALUES (
    NEW.id,
    v_username,
    COALESCE(NEW.raw_user_meta_data->>'full_name', v_username)
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();
