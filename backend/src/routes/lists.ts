import { Router, type Request, type Response } from 'express';
import { authMiddleware, type AuthRequest } from '../middleware/auth';
import { requireSupabase } from '../config/supabase';

const router = Router();

// POST /api/lists - Create a new list
router.post('/', authMiddleware, async (req: AuthRequest, res: Response) => {
  try {
    const userId = req.user!.id;
    const client = requireSupabase();
    const { name, description, isPublic, isRanked } = req.body as Record<string, unknown>;

    if (!name || typeof name !== 'string') {
      res.status(400).json({ error: 'List name is required' });
      return;
    }

    const { data, error } = await client
      .from('lists')
      .insert({
        user_id: userId,
        name,
        description: typeof description === 'string' ? description : null,
        is_public: isPublic === true,
        is_ranked: isRanked === true,
      })
      .select()
      .single();

    if (error) {
      throw error;
    }

    res.json({ list: data, created: true });
  } catch (error) {
    res.status(500).json({ error: (error as Error).message });
  }
});

// GET /api/lists - Get user's lists
router.get('/', authMiddleware, async (req: AuthRequest, res: Response) => {
  try {
    const userId = req.user!.id;
    const client = requireSupabase();
    const parsedLimit = Number(req.query.limit ?? 50);
    const limit = Number.isFinite(parsedLimit)
      ? Math.min(Math.max(Math.trunc(parsedLimit), 1), 100)
      : 50;
    const cursor =
      typeof req.query.cursor === 'string' && req.query.cursor.trim().length > 0
        ? req.query.cursor.trim()
        : undefined;
    const hasOffsetPagination = req.query.offset !== undefined && !cursor;
    const parsedOffset = Number(req.query.offset ?? 0);
    const offset = Number.isFinite(parsedOffset)
      ? Math.max(Math.trunc(parsedOffset), 0)
      : 0;

    let query = client
      .from('lists')
      .select('*', { count: hasOffsetPagination ? 'exact' : undefined })
      .eq('user_id', userId)
      .order('created_at', { ascending: false });

    if (cursor) {
      query = query.lt('created_at', cursor).limit(limit);
    } else if (hasOffsetPagination) {
      query = query.range(offset, offset + limit - 1);
    } else {
      query = query.limit(limit);
    }

    const { data, error, count } = await query;

    if (error) {
      throw error;
    }

    const lists = data ?? [];
    const lastList =
      lists.length > 0 ? (lists[lists.length - 1] as Record<string, unknown>) : null;
    const nextCursor =
      lists.length === limit && typeof lastList?.created_at === 'string'
        ? String(lastList.created_at)
        : null;

    if (hasOffsetPagination) {
      res.json({
        lists,
        count,
        limit,
        offset,
      });
      return;
    }

    res.json({
      lists,
      limit,
      cursor: cursor ?? null,
      nextCursor,
    });
  } catch (error) {
    res.status(500).json({ error: (error as Error).message });
  }
});

// GET /api/lists/:id - Get list details with items
router.get('/:id', authMiddleware, async (req: AuthRequest, res: Response) => {
  try {
    const userId = req.user!.id;
    const client = requireSupabase();

    const { data: list, error: listError } = await client
      .from('lists')
      .select('*')
      .eq('id', req.params.id)
      .eq('user_id', userId)
      .single();

    if (listError) {
      throw listError;
    }

    const { data: items, error: itemsError } = await client
      .from('list_items')
      .select('*, content:content_id(tmdb_id, media_type, title, poster_path)')
      .eq('list_id', req.params.id)
      .order('position', { ascending: true });

    if (itemsError) {
      throw itemsError;
    }

    res.json({ list, items });
  } catch (error) {
    res.status(500).json({ error: (error as Error).message });
  }
});

// PATCH /api/lists/:id - Update list details
router.patch('/:id', authMiddleware, async (req: AuthRequest, res: Response) => {
  try {
    const userId = req.user!.id;
    const client = requireSupabase();
    const { name, description, isPublic, isRanked } = req.body as Record<string, unknown>;

    const updatePayload: Record<string, unknown> = {};
    if (typeof name === 'string') updatePayload.name = name;
    if (typeof description === 'string') updatePayload.description = description;
    if (typeof isPublic === 'boolean') updatePayload.is_public = isPublic;
    if (typeof isRanked === 'boolean') updatePayload.is_ranked = isRanked;

    const { data, error } = await client
      .from('lists')
      .update(updatePayload)
      .eq('id', req.params.id)
      .eq('user_id', userId)
      .select()
      .single();

    if (error) {
      throw error;
    }

    res.json({ list: data });
  } catch (error) {
    res.status(500).json({ error: (error as Error).message });
  }
});

// DELETE /api/lists/:id - Delete list
router.delete('/:id', authMiddleware, async (req: AuthRequest, res: Response) => {
  try {
    const userId = req.user!.id;
    const client = requireSupabase();

    const { error } = await client
      .from('lists')
      .delete()
      .eq('id', req.params.id)
      .eq('user_id', userId);

    if (error) {
      throw error;
    }

    res.json({ deleted: true });
  } catch (error) {
    res.status(500).json({ error: (error as Error).message });
  }
});

// POST /api/lists/:id/items - Add item to list
router.post('/:id/items', authMiddleware, async (req: AuthRequest, res: Response) => {
  try {
    const userId = req.user!.id;
    const client = requireSupabase();
    const { tmdbId, mediaType, position, note } = req.body as Record<string, unknown>;

    if (!tmdbId || !mediaType) {
      res.status(400).json({ error: 'tmdbId and mediaType are required' });
      return;
    }

    // Get or create content
    const { data: contentData } = await client
      .from('content')
      .select('id')
      .eq('tmdb_id', tmdbId)
      .eq('media_type', mediaType)
      .single();

    let contentId = contentData?.id;
    if (!contentId) {
      const { data: newContent } = await client
        .from('content')
        .insert({
          tmdb_id: tmdbId,
          media_type: mediaType,
          title: 'Unknown',
          overview: '',
          genres: [],
        })
        .select('id')
        .single();

      if (!newContent) {
        res.status(500).json({ error: 'Failed to create content entry' });
        return;
      }
      contentId = newContent.id;
    }

    // Add to list
    const { data, error } = await client
      .from('list_items')
      .insert({
        list_id: req.params.id,
        content_id: contentId,
        tmdb_id: tmdbId,
        media_type: mediaType,
        position: typeof position === 'number' ? position : 0,
        note: typeof note === 'string' ? note : null,
      })
      .select()
      .single();

    if (error) {
      throw error;
    }

    res.json({ item: data, created: true });
  } catch (error) {
    res.status(500).json({ error: (error as Error).message });
  }
});

// DELETE /api/lists/:id/items/:itemId - Remove item from list
router.delete('/:id/items/:itemId', authMiddleware, async (req: AuthRequest, res: Response) => {
  try {
    const client = requireSupabase();

    const { error } = await client
      .from('list_items')
      .delete()
      .eq('id', req.params.itemId)
      .eq('list_id', req.params.id);

    if (error) {
      throw error;
    }

    res.json({ deleted: true });
  } catch (error) {
    res.status(500).json({ error: (error as Error).message });
  }
});

export default router;
