import 'dotenv/config';
import cors from 'cors';
import express, { type Application, type NextFunction, type Request, type Response } from 'express';
import helmet from 'helmet';
import morgan from 'morgan';
import rateLimit from 'express-rate-limit';
import authRoutes from './routes/auth';
import contentRoutes from './routes/content';
import personRoutes from './routes/person';
import profileRoutes from './routes/profile';
import logsRoutes from './routes/logs';
import listsRoutes from './routes/lists';
import recommendationRoutes from './routes/recommendations';
import { getRecommendationMode } from './services/recommendationService';

const app: Application = express();

const apiLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: Number(process.env.API_RATE_LIMIT_MAX ?? 300),
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'Too many requests. Please try again in a few minutes.' },
});

app.use(helmet());
app.use(
  cors({
    origin: process.env.NODE_ENV === 'production' ? false : '*',
    credentials: true,
  }),
);
app.use(express.json({ limit: '1mb' }));
app.use(express.urlencoded({ extended: true, limit: '1mb' }));
app.use(morgan(process.env.NODE_ENV === 'production' ? 'combined' : 'dev'));
app.use('/api', apiLimiter);

app.get('/health', (_req: Request, res: Response) => {
  res.json({
    status: 'ok',
    timestamp: new Date().toISOString(),
    recommendation_mode: getRecommendationMode(),
    recommendation_mode_raw: process.env.RECOMMENDATION_MODE ?? 'scratch',
    ml_service_url: process.env.ML_SERVICE_URL ?? null,
  });
});

app.use('/api/auth', authRoutes);
app.use('/api/profile', profileRoutes);
app.use('/api/content', contentRoutes);
app.use('/api/person', personRoutes);
app.use('/api/logs', logsRoutes);
app.use('/api/lists', listsRoutes);
app.use('/api/recommendations', recommendationRoutes);

app.use((_req: Request, res: Response) => {
  res.status(404).json({ error: 'Not found' });
});

app.use((error: Error, _req: Request, res: Response, _next: NextFunction) => {
  console.error(error);
  res.status(500).json({
    error: {
      message: error.message || 'Internal server error',
      ...(process.env.NODE_ENV !== 'production' ? { stack: error.stack } : {}),
    },
  });
});

const PORT = Number(process.env.PORT ?? 3000);
app.listen(PORT, () => {
  console.log(
    `Zinemo backend listening on port ${PORT} (${getRecommendationMode()} mode, raw=${process.env.RECOMMENDATION_MODE ?? 'scratch'})`,
  );
});

export default app;
