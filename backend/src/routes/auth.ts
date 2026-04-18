import { Router, type Response } from 'express';
import { authMiddleware, type AuthRequest } from '../middleware/auth';
import { requireSupabase } from '../config/supabase';

const router = Router();

router.post('/create-profile', authMiddleware, async (req: AuthRequest, res: Response) => {
  try {
    const userId = req.user!.id;
    const client = requireSupabase();
    const { username, display_name, avatar_url } = req.body as Record<string, unknown>;

    const payload = {
      id: userId,
      username: typeof username === 'string' ? username : `zinemo_${userId.slice(0, 8)}`,
      display_name: typeof display_name === 'string' ? display_name : null,
      avatar_url: typeof avatar_url === 'string' ? avatar_url : null,
      updated_at: new Date().toISOString(),
    };

    const { data, error } = await client
      .from('profiles')
      .upsert(payload, { onConflict: 'id' })
      .select()
      .single();

    if (error) {
      throw error;
    }

    res.json({ profile: data });
  } catch (error) {
    res.status(500).json({ error: (error as Error).message });
  }
});

router.post('/preferences', authMiddleware, async (req: AuthRequest, res: Response) => {
  try {
    const userId = req.user!.id;
    const client = requireSupabase();
    const { genres, initialRatings } = req.body as {
      genres?: unknown;
      initialRatings?: unknown;
    };

    const preferences = {
      genres: Array.isArray(genres) ? genres : [],
      initial_ratings: Array.isArray(initialRatings) ? initialRatings : [],
      updated_from: 'onboarding',
    };

    const { data, error } = await client
      .from('profiles')
      .update({
        preferences,
        updated_at: new Date().toISOString(),
      })
      .eq('id', userId)
      .select('id, preferences')
      .single();

    if (error) {
      throw error;
    }

    res.json({ profile: data });
  } catch (error) {
    res.status(500).json({ error: (error as Error).message });
  }
});

router.get('/me', authMiddleware, async (req: AuthRequest, res: Response) => {
  try {
    const client = requireSupabase();
    const { data, error } = await client
      .from('profiles')
      .select('*')
      .eq('id', req.user!.id)
      .single();

    if (error) {
      throw error;
    }

    res.json({ profile: data });
  } catch (error) {
    res.status(500).json({ error: (error as Error).message });
  }
});

export default router;
