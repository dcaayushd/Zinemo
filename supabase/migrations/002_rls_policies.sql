ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reviews ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.lists ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.recommendations ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Public profiles"
  ON public.profiles FOR SELECT
  USING (true);

CREATE POLICY "Own profile update"
  ON public.profiles FOR UPDATE
  USING (auth.uid() = id);

CREATE POLICY "View logs"
  ON public.logs FOR SELECT
  USING (auth.uid() = user_id OR is_private = false);

CREATE POLICY "Manage own logs"
  ON public.logs FOR ALL
  USING (auth.uid() = user_id);

CREATE POLICY "Own recommendations"
  ON public.recommendations FOR SELECT
  USING (auth.uid() = user_id);
