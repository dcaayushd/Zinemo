import { Router } from 'express';
import { authMiddleware } from '../middleware/auth';
import { getRecommendationMode, getRecommendationsForUser, getSimilarTitles, triggerRetraining, } from '../services/recommendationService';
const router = Router();
router.get('/foryou', authMiddleware, async (req, res) => {
    try {
        const genre = typeof req.query.genre === 'string' ? req.query.genre : undefined;
        const limit = Number(req.query.limit ?? 30);
        const page = Number(req.query.page ?? 1);
        const recommendations = await getRecommendationsForUser(req.user.id, genre, limit);
        res.json({
            recommendations,
            page,
            mode: getRecommendationMode(),
            fallback: recommendations.some((recommendation) => recommendation.algorithm === 'tmdb_fallback'),
        });
    }
    catch (error) {
        res.status(500).json({ error: error.message });
    }
});
router.get('/similar/:tmdbId', authMiddleware, async (req, res) => {
    try {
        const limit = Number(req.query.limit ?? 20);
        const recommendations = await getSimilarTitles(Number(req.params.tmdbId), limit);
        res.json({ recommendations, mode: getRecommendationMode() });
    }
    catch (error) {
        res.status(500).json({ error: error.message });
    }
});
router.post('/retrain', authMiddleware, async (_req, res) => {
    try {
        const started = await triggerRetraining();
        res.json({
            status: started ? 'retraining_triggered' : 'skipped',
            mode: getRecommendationMode(),
        });
    }
    catch (error) {
        res.status(500).json({ error: error.message });
    }
});
export default router;
