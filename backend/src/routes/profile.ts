import { Router, type Response } from 'express';
import { requireSupabase } from '../config/supabase';
import { authMiddleware, type AuthRequest } from '../middleware/auth';

const router = Router();

router.get('/', authMiddleware, async (req: AuthRequest, res: Response) => {
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

router.put('/', authMiddleware, async (req: AuthRequest, res: Response) => {
  try {
    const client = requireSupabase();
    const { username, display_name, avatar_url, bio, preferences, is_private } = req.body as {
      username?: string;
      display_name?: string;
      avatar_url?: string;
      bio?: string;
      preferences?: Record<string, unknown>;
      is_private?: boolean;
    };

    const updates = {
      ...(username !== undefined ? { username } : {}),
      ...(display_name !== undefined ? { display_name } : {}),
      ...(avatar_url !== undefined ? { avatar_url } : {}),
      ...(bio !== undefined ? { bio } : {}),
      ...(preferences !== undefined ? { preferences } : {}),
      ...(is_private !== undefined ? { is_private } : {}),
      updated_at: new Date().toISOString(),
    };

    const { data, error } = await client
      .from('profiles')
      .update(updates)
      .eq('id', req.user!.id)
      .select('*')
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
