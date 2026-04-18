import { Router } from 'express';
import { authMiddleware } from '../middleware/auth';
import { requireSupabase } from '../config/supabase';
const router = Router();
// POST /api/lists - Create a new list
router.post('/', authMiddleware, async (req, res) => {
    try {
        const userId = req.user.id;
        const client = requireSupabase();
        const { name, description, isPublic, isRanked } = req.body;
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
    }
    catch (error) {
        res.status(500).json({ error: error.message });
    }
});
// GET /api/lists - Get user's lists
router.get('/', authMiddleware, async (req, res) => {
    try {
        const userId = req.user.id;
        const client = requireSupabase();
        const limit = Number(req.query.limit ?? 50);
        const offset = Number(req.query.offset ?? 0);
        const { data, error, count } = await client
            .from('lists')
            .select('*', { count: 'exact' })
            .eq('user_id', userId)
            .order('created_at', { ascending: false })
            .range(offset, offset + limit - 1);
        if (error) {
            throw error;
        }
        res.json({
            lists: data,
            count,
            limit,
            offset,
        });
    }
    catch (error) {
        res.status(500).json({ error: error.message });
    }
});
// GET /api/lists/:id - Get list details with items
router.get('/:id', authMiddleware, async (req, res) => {
    try {
        const userId = req.user.id;
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
    }
    catch (error) {
        res.status(500).json({ error: error.message });
    }
});
// PATCH /api/lists/:id - Update list details
router.patch('/:id', authMiddleware, async (req, res) => {
    try {
        const userId = req.user.id;
        const client = requireSupabase();
        const { name, description, isPublic, isRanked } = req.body;
        const updatePayload = {};
        if (typeof name === 'string')
            updatePayload.name = name;
        if (typeof description === 'string')
            updatePayload.description = description;
        if (typeof isPublic === 'boolean')
            updatePayload.is_public = isPublic;
        if (typeof isRanked === 'boolean')
            updatePayload.is_ranked = isRanked;
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
    }
    catch (error) {
        res.status(500).json({ error: error.message });
    }
});
// DELETE /api/lists/:id - Delete list
router.delete('/:id', authMiddleware, async (req, res) => {
    try {
        const userId = req.user.id;
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
    }
    catch (error) {
        res.status(500).json({ error: error.message });
    }
});
// POST /api/lists/:id/items - Add item to list
router.post('/:id/items', authMiddleware, async (req, res) => {
    try {
        const userId = req.user.id;
        const client = requireSupabase();
        const { tmdbId, mediaType, position, note } = req.body;
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
    }
    catch (error) {
        res.status(500).json({ error: error.message });
    }
});
// DELETE /api/lists/:id/items/:itemId - Remove item from list
router.delete('/:id/items/:itemId', authMiddleware, async (req, res) => {
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
    }
    catch (error) {
        res.status(500).json({ error: error.message });
    }
});
export default router;
