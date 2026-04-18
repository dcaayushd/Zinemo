import { Router } from 'express';
import { authMiddleware } from '../middleware/auth';
import { requireSupabase } from '../config/supabase';
import { onNewLog } from '../workers/retrainWorker';
const router = Router();
// POST /api/logs - Create a new log entry
router.post('/', authMiddleware, async (req, res) => {
    try {
        const userId = req.user.id;
        const client = requireSupabase();
        const { tmdbId, mediaType, status, rating, liked, rewatch, watchedDate, review, tags, isPrivate, } = req.body;
        // Validate required fields
        if (!tmdbId || !mediaType || !status) {
            res.status(400).json({
                error: 'Missing required fields: tmdbId, mediaType, status',
            });
            return;
        }
        // Get or create content entry
        const { data: contentData } = await client
            .from('content')
            .select('id')
            .eq('tmdb_id', tmdbId)
            .eq('media_type', mediaType)
            .single();
        let contentId = contentData?.id;
        if (!contentId) {
            // If content doesn't exist, create it
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
        // Create log entry
        const logPayload = {
            user_id: userId,
            content_id: contentId,
            tmdb_id: tmdbId,
            media_type: mediaType,
            status: status || 'watched',
            rating: typeof rating === 'number' && rating >= 0.5 && rating <= 5.0 ? rating : null,
            liked: liked === true,
            rewatch: rewatch === true,
            watched_date: typeof watchedDate === 'string' ? watchedDate : new Date().toISOString().split('T')[0],
            review: typeof review === 'string' ? review : null,
            tags: Array.isArray(tags) ? tags : [],
            is_private: isPrivate === true,
        };
        const { data, error } = await client
            .from('logs')
            .insert(logPayload)
            .select()
            .single();
        if (error) {
            throw error;
        }
        // Trigger retrain worker if using mode=scratch
        await onNewLog();
        res.json({ log: data, created: true });
    }
    catch (error) {
        res.status(500).json({ error: error.message });
    }
});
// GET /api/logs - Get user's logs with filters
router.get('/', authMiddleware, async (req, res) => {
    try {
        const userId = req.user.id;
        const client = requireSupabase();
        const status = typeof req.query.status === 'string' ? req.query.status : undefined;
        const limit = Number(req.query.limit ?? 50);
        const offset = Number(req.query.offset ?? 0);
        let query = client
            .from('logs')
            .select('*, content:content_id(tmdb_id, media_type, title, poster_path)')
            .eq('user_id', userId)
            .order('created_at', { ascending: false })
            .range(offset, offset + limit - 1);
        if (status) {
            query = query.eq('status', status);
        }
        const { data, error, count } = await query;
        if (error) {
            throw error;
        }
        res.json({
            logs: data,
            count,
            limit,
            offset,
        });
    }
    catch (error) {
        res.status(500).json({ error: error.message });
    }
});
// GET /api/logs/:id - Get specific log
router.get('/:id', authMiddleware, async (req, res) => {
    try {
        const userId = req.user.id;
        const client = requireSupabase();
        const { data, error } = await client
            .from('logs')
            .select('*')
            .eq('id', req.params.id)
            .eq('user_id', userId)
            .single();
        if (error) {
            throw error;
        }
        res.json({ log: data });
    }
    catch (error) {
        res.status(500).json({ error: error.message });
    }
});
// PATCH /api/logs/:id - Update log entry
router.patch('/:id', authMiddleware, async (req, res) => {
    try {
        const userId = req.user.id;
        const client = requireSupabase();
        const { rating, liked, rewatch, status, review, tags } = req.body;
        const updatePayload = {
            updated_at: new Date().toISOString(),
        };
        if (typeof rating === 'number')
            updatePayload.rating = rating;
        if (typeof liked === 'boolean')
            updatePayload.liked = liked;
        if (typeof rewatch === 'boolean')
            updatePayload.rewatch = rewatch;
        if (typeof status === 'string')
            updatePayload.status = status;
        if (typeof review === 'string')
            updatePayload.review = review;
        if (Array.isArray(tags))
            updatePayload.tags = tags;
        const { data, error } = await client
            .from('logs')
            .update(updatePayload)
            .eq('id', req.params.id)
            .eq('user_id', userId)
            .select()
            .single();
        if (error) {
            throw error;
        }
        res.json({ log: data });
    }
    catch (error) {
        res.status(500).json({ error: error.message });
    }
});
// DELETE /api/logs/:id - Delete log entry
router.delete('/:id', authMiddleware, async (req, res) => {
    try {
        const userId = req.user.id;
        const client = requireSupabase();
        const { error } = await client
            .from('logs')
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
// GET /api/logs/stats/user-stats - Get user stats
router.get('/stats/user-stats', authMiddleware, async (req, res) => {
    try {
        const userId = req.user.id;
        const client = requireSupabase();
        const { count: totalLogs } = await client
            .from('logs')
            .select('id', { count: 'exact', head: true })
            .eq('user_id', userId);
        const { count: watchedCount } = await client
            .from('logs')
            .select('id', { count: 'exact', head: true })
            .eq('user_id', userId)
            .eq('status', 'watched');
        const { count: watchlistCount } = await client
            .from('logs')
            .select('id', { count: 'exact', head: true })
            .eq('user_id', userId)
            .eq('status', 'watchlist');
        const { data: avgRating } = await client.rpc('get_user_avg_rating', { user_id: userId });
        res.json({
            totalLogs: totalLogs ?? 0,
            watchedCount: watchedCount ?? 0,
            watchlistCount: watchlistCount ?? 0,
            avgRating: avgRating ?? 0,
        });
    }
    catch (error) {
        res.status(500).json({ error: error.message });
    }
});
export default router;
