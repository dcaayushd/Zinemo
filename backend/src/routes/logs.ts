import { Router, type Request, type Response } from 'express';
import { authMiddleware, type AuthRequest } from '../middleware/auth';
import { requireSupabase } from '../config/supabase';
import { onNewLog } from '../workers/retrainWorker';
import { trackRecommendationBehaviorEvent } from '../services/recommendationService';

const router = Router();

// POST /api/logs - Create a new log entry
router.post('/', authMiddleware, async (req: AuthRequest, res: Response) => {
  try {
    const userId = req.user!.id;
    const client = requireSupabase();
    const {
      tmdbId,
      mediaType,
      status,
      rating,
      liked,
      rewatch,
      watchedDate,
      review,
      tags,
      isPrivate,
    } = req.body as Record<string, unknown>;

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
      rating:
        typeof rating === 'number' && rating >= 0.5 && rating <= 5.0 ? rating : null,
      liked: liked === true,
      rewatch: rewatch === true,
      watched_date:
        typeof watchedDate === 'string' ? watchedDate : new Date().toISOString().split('T')[0],
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

    const normalizedTmdbId = Number(tmdbId);
    const normalizedMediaType = String(mediaType);
    const normalizedStatus = String(status || 'watched');
    const normalizedRating =
      typeof logPayload.rating === 'number' ? logPayload.rating : null;

    await trackRecommendationBehaviorEvent(userId, 'recommendation_log_created', {
      tmdb_id: Number.isNaN(normalizedTmdbId) ? null : normalizedTmdbId,
      media_type: normalizedMediaType,
      status: normalizedStatus,
      rating: normalizedRating,
      liked: logPayload.liked,
      rewatch: logPayload.rewatch,
    });

    if (normalizedRating !== null) {
      await trackRecommendationBehaviorEvent(userId, 'recommendation_add_rating', {
        tmdb_id: Number.isNaN(normalizedTmdbId) ? null : normalizedTmdbId,
        media_type: normalizedMediaType,
        rating: normalizedRating,
      });
    }

    if (normalizedStatus === 'watchlist' || normalizedStatus === 'plan_to_watch') {
      await trackRecommendationBehaviorEvent(userId, 'recommendation_add_bookmark', {
        tmdb_id: Number.isNaN(normalizedTmdbId) ? null : normalizedTmdbId,
        media_type: normalizedMediaType,
      });
    } else {
      await trackRecommendationBehaviorEvent(userId, 'recommendation_add_detail_view', {
        tmdb_id: Number.isNaN(normalizedTmdbId) ? null : normalizedTmdbId,
        media_type: normalizedMediaType,
      });
    }

    res.json({ log: data, created: true });
  } catch (error) {
    res.status(500).json({ error: (error as Error).message });
  }
});

// GET /api/logs - Get user's logs with filters
router.get('/', authMiddleware, async (req: AuthRequest, res: Response) => {
  try {
    const userId = req.user!.id;
    const client = requireSupabase();
    const status = typeof req.query.status === 'string' ? req.query.status : undefined;
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
      .from('logs')
      .select('*, content:content_id(tmdb_id, media_type, title, poster_path)', {
        count: hasOffsetPagination ? 'exact' : undefined,
      })
      .eq('user_id', userId)
      .order('created_at', { ascending: false });

    if (status) {
      query = query.eq('status', status);
    }

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

    const logs = data ?? [];
    const lastLog = logs.length > 0 ? (logs[logs.length - 1] as Record<string, unknown>) : null;
    const nextCursor =
      logs.length === limit && typeof lastLog?.created_at === 'string'
        ? String(lastLog.created_at)
        : null;

    if (hasOffsetPagination) {
      res.json({
        logs,
        count,
        limit,
        offset,
      });
      return;
    }

    res.json({
      logs,
      limit,
      cursor: cursor ?? null,
      nextCursor,
    });
  } catch (error) {
    res.status(500).json({ error: (error as Error).message });
  }
});

// GET /api/logs/:id - Get specific log
router.get('/:id', authMiddleware, async (req: AuthRequest, res: Response) => {
  try {
    const userId = req.user!.id;
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
  } catch (error) {
    res.status(500).json({ error: (error as Error).message });
  }
});

// PATCH /api/logs/:id - Update log entry
router.patch('/:id', authMiddleware, async (req: AuthRequest, res: Response) => {
  try {
    const userId = req.user!.id;
    const client = requireSupabase();
    const { rating, liked, rewatch, status, review, tags } = req.body as Record<
      string,
      unknown
    >;

    const updatePayload: Record<string, unknown> = {
      updated_at: new Date().toISOString(),
    };

    if (typeof rating === 'number') updatePayload.rating = rating;
    if (typeof liked === 'boolean') updatePayload.liked = liked;
    if (typeof rewatch === 'boolean') updatePayload.rewatch = rewatch;
    if (typeof status === 'string') updatePayload.status = status;
    if (typeof review === 'string') updatePayload.review = review;
    if (Array.isArray(tags)) updatePayload.tags = tags;

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
  } catch (error) {
    res.status(500).json({ error: (error as Error).message });
  }
});

// DELETE /api/logs/:id - Delete log entry
router.delete('/:id', authMiddleware, async (req: AuthRequest, res: Response) => {
  try {
    const userId = req.user!.id;
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
  } catch (error) {
    res.status(500).json({ error: (error as Error).message });
  }
});

// GET /api/logs/stats/user-stats - Get user stats
router.get('/stats/user-stats', authMiddleware, async (req: AuthRequest, res: Response) => {
  try {
    const userId = req.user!.id;
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
  } catch (error) {
    res.status(500).json({ error: (error as Error).message });
  }
});

export default router;
