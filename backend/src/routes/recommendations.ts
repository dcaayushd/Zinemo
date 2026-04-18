import { Router, type Response } from 'express';
import { authMiddleware, type AuthRequest } from '../middleware/auth';
import {
  getRecommendationMode,
  getRecommendationsForUser,
  getSimilarTitles,
  triggerRetraining,
} from '../services/recommendationService';

const router = Router();

router.get('/foryou', authMiddleware, async (req: AuthRequest, res: Response) => {
  try {
    const genre = typeof req.query.genre === 'string' ? req.query.genre : undefined;
    const rawLimit = Number(req.query.limit ?? 30);
    const limit = Number.isFinite(rawLimit)
      ? Math.min(Math.max(Math.trunc(rawLimit), 1), 100)
      : 30;
    const rawPage = Number(req.query.page ?? 1);
    const page = Number.isFinite(rawPage) ? Math.max(Math.trunc(rawPage), 1) : 1;

    const recommendations = await getRecommendationsForUser(
      req.user!.id,
      genre,
      limit,
    );

    res.json({
      recommendations,
      page,
      mode: getRecommendationMode(),
      fallback: recommendations.some(
        (recommendation) => recommendation.algorithm === 'tmdb_fallback',
      ),
    });
  } catch (error) {
    res.status(500).json({ error: (error as Error).message });
  }
});

router.get('/similar/:tmdbId', authMiddleware, async (req: AuthRequest, res: Response) => {
  try {
    const rawLimit = Number(req.query.limit ?? 20);
    const limit = Number.isFinite(rawLimit)
      ? Math.min(Math.max(Math.trunc(rawLimit), 1), 100)
      : 20;
    const recommendations = await getSimilarTitles(
      Number(req.params.tmdbId),
      limit,
      req.user?.id,
    );
    res.json({ recommendations, mode: getRecommendationMode() });
  } catch (error) {
    res.status(500).json({ error: (error as Error).message });
  }
});

router.post('/retrain', authMiddleware, async (_req: AuthRequest, res: Response) => {
  try {
    const started = await triggerRetraining();
    res.json({
      status: started ? 'retraining_triggered' : 'skipped',
      mode: getRecommendationMode(),
    });
  } catch (error) {
    res.status(500).json({ error: (error as Error).message });
  }
});

export default router;
