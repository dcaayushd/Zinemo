import { Router } from 'express';
import { tmdbService } from '../services/tmdbService';
import { trackContentAccess } from '../utils/supabase';
const router = Router();
router.get('/trending', async (req, res) => {
    try {
        const genre = typeof req.query.genre === 'string' ? req.query.genre : undefined;
        const mediaType = req.query.media_type === 'tv' ? 'tv' : 'movie';
        const limit = Number(req.query.limit ?? 20);
        const data = await tmdbService.getTrending({ genre, limit, mediaType });
        await trackContentAccess('content_trending', data.length);
        res.json({ data });
    }
    catch (error) {
        res.status(500).json({ error: error.message });
    }
});
router.get('/top-rated', async (req, res) => {
    try {
        const mediaType = req.query.media_type === 'tv' ? 'tv' : 'movie';
        const limit = Number(req.query.limit ?? 20);
        const data = await tmdbService.getTopRated(limit, mediaType);
        await trackContentAccess('content_top_rated', data.length);
        res.json({ data });
    }
    catch (error) {
        res.status(500).json({ error: error.message });
    }
});
router.get('/new-releases', async (req, res) => {
    try {
        const mediaType = req.query.media_type === 'tv' ? 'tv' : 'movie';
        const limit = Number(req.query.limit ?? 20);
        const data = await tmdbService.getNewReleases(limit, mediaType);
        await trackContentAccess('content_new_releases', data.length);
        res.json({ data });
    }
    catch (error) {
        res.status(500).json({ error: error.message });
    }
});
router.get('/genres', async (_req, res) => {
    try {
        const data = await tmdbService.getGenres();
        res.json({ data });
    }
    catch (error) {
        res.status(500).json({ error: error.message });
    }
});
router.get('/genre/:name', async (req, res) => {
    try {
        const genreName = Array.isArray(req.params.name)
            ? req.params.name[0]
            : req.params.name;
        if (!genreName) {
            res.status(400).json({ error: 'Missing genre name' });
            return;
        }
        const limit = Number(req.query.limit ?? 20);
        const data = await tmdbService.discoverByGenre(genreName, limit);
        await trackContentAccess(`content_genre_${genreName}`, data.length);
        res.json({ data });
    }
    catch (error) {
        res.status(500).json({ error: error.message });
    }
});
router.get('/search', async (req, res) => {
    if (typeof req.query.query !== 'string' || !req.query.query.trim()) {
        res.status(400).json({ error: 'Missing query parameter' });
        return;
    }
    try {
        const limit = Number(req.query.limit ?? 20);
        const data = await tmdbService.search(req.query.query, limit);
        await trackContentAccess('content_search', data.length);
        res.json({ data });
    }
    catch (error) {
        res.status(500).json({ error: error.message });
    }
});
router.get('/detail/:id', async (req, res) => {
    try {
        const mediaType = req.query.media_type === 'tv' ? 'tv' : 'movie';
        const data = await tmdbService.getDetails(Number(req.params.id), mediaType);
        await trackContentAccess(`content_detail_${req.params.id}`, 1);
        res.json({ data });
    }
    catch (error) {
        res.status(500).json({ error: error.message });
    }
});
router.get('/tv/:id/season/:seasonNumber', async (req, res) => {
    try {
        const tmdbId = Number(req.params.id);
        const seasonNumber = Number(req.params.seasonNumber);
        const data = await tmdbService.getTvSeasonDetails(tmdbId, seasonNumber);
        await trackContentAccess(`content_tv_season_${tmdbId}_${seasonNumber}`, 1);
        res.json({ data });
    }
    catch (error) {
        res.status(500).json({ error: error.message });
    }
});
router.get('/similar/:id', async (req, res) => {
    try {
        const mediaType = req.query.media_type === 'tv' ? 'tv' : 'movie';
        const limit = Number(req.query.limit ?? 20);
        const data = await tmdbService.getSimilar(Number(req.params.id), mediaType, limit);
        await trackContentAccess(`content_similar_${req.params.id}`, data.length);
        res.json({ data });
    }
    catch (error) {
        res.status(500).json({ error: error.message });
    }
});
router.get('/credits/:id', async (req, res) => {
    try {
        const mediaType = req.query.media_type === 'tv' ? 'tv' : 'movie';
        const data = await tmdbService.getCredits(Number(req.params.id), mediaType);
        await trackContentAccess(`content_credits_${req.params.id}`, 1);
        res.json({ data });
    }
    catch (error) {
        res.status(500).json({ error: error.message });
    }
});
export default router;
