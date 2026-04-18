import { Router, type Request, type Response } from 'express';
import { tmdbService } from '../services/tmdbService';
import { trackContentAccess } from '../utils/supabase';

const router = Router();

router.get('/:id', async (req: Request, res: Response) => {
  try {
    const data = await tmdbService.getPerson(Number(req.params.id));
    await trackContentAccess(`person_detail_${req.params.id}`, 1);
    res.json({ data });
  } catch (error) {
    res.status(500).json({ error: (error as Error).message });
  }
});

router.get('/:id/filmography', async (req: Request, res: Response) => {
  try {
    const rawMediaType =
      typeof req.query.media_type === 'string'
        ? req.query.media_type.toLowerCase()
        : 'all';

    const mediaType =
      rawMediaType === 'tv' || rawMediaType === 'movie' ? rawMediaType : 'all';

    const data = await tmdbService.getPersonFilmography(Number(req.params.id), mediaType);
    await trackContentAccess(`person_filmography_${req.params.id}`, data.length);
    res.json({ data });
  } catch (error) {
    res.status(500).json({ error: (error as Error).message });
  }
});

export default router;
