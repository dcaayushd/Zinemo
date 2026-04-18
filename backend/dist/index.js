import 'dotenv/config';
import cors from 'cors';
import express from 'express';
import helmet from 'helmet';
import authRoutes from './routes/auth';
import contentRoutes from './routes/content';
import personRoutes from './routes/person';
import profileRoutes from './routes/profile';
import logsRoutes from './routes/logs';
import listsRoutes from './routes/lists';
import recommendationRoutes from './routes/recommendations';
const app = express();
app.use(helmet());
app.use(cors({
    origin: process.env.NODE_ENV === 'production' ? false : '*',
    credentials: true,
}));
app.use(express.json({ limit: '1mb' }));
app.use(express.urlencoded({ extended: true, limit: '1mb' }));
app.get('/health', (_req, res) => {
    res.json({
        status: 'ok',
        timestamp: new Date().toISOString(),
        recommendation_mode: process.env.RECOMMENDATION_MODE ?? 'scratch',
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
app.use((_req, res) => {
    res.status(404).json({ error: 'Not found' });
});
app.use((error, _req, res, _next) => {
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
    console.log(`Zinemo backend listening on port ${PORT} (${process.env.RECOMMENDATION_MODE ?? 'scratch'} mode)`);
});
export default app;
