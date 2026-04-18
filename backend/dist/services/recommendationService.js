import { supabase } from '../config/supabase';
import { tmdbService } from './tmdbService';
const ML_SERVICE_URL = process.env.ML_SERVICE_URL ?? 'http://localhost:8000';
const RECOMMENDATION_MODE = process.env.RECOMMENDATION_MODE ?? 'scratch';
async function fetchJson(url, options) {
    const response = await fetch(url, options);
    if (!response.ok) {
        throw new Error(`Request failed (${response.status} ${response.statusText})`);
    }
    return (await response.json());
}
async function getUserSeenIds(userId) {
    if (!supabase) {
        return [];
    }
    const { data, error } = await supabase
        .from('logs')
        .select('tmdb_id')
        .eq('user_id', userId);
    if (error) {
        console.warn('Failed to fetch seen ids:', error.message);
        return [];
    }
    return (data ?? []).map((row) => Number(row.tmdb_id));
}
async function enrichFromContentCache(recommendations) {
    if (!supabase || recommendations.length === 0) {
        return recommendations;
    }
    try {
        const { data, error } = await supabase
            .from('content')
            .select('tmdb_id, media_type, title, overview, poster_path, backdrop_path, release_date, vote_average, vote_count, popularity, genres')
            .in('tmdb_id', recommendations.map((recommendation) => recommendation.tmdb_id));
        if (error) {
            throw error;
        }
        const cache = new Map();
        (data ?? []).forEach((row) => cache.set(Number(row.tmdb_id), row));
        return recommendations.map((recommendation) => {
            const row = cache.get(recommendation.tmdb_id);
            if (!row) {
                return recommendation;
            }
            return {
                ...recommendation,
                title: typeof row.title === 'string' ? row.title : recommendation.title,
                overview: typeof row.overview === 'string' ? row.overview : recommendation.overview,
                poster_path: typeof row.poster_path === 'string'
                    ? row.poster_path
                    : recommendation.poster_path ?? null,
                backdrop_path: typeof row.backdrop_path === 'string'
                    ? row.backdrop_path
                    : recommendation.backdrop_path ?? null,
                release_date: typeof row.release_date === 'string'
                    ? row.release_date
                    : recommendation.release_date ?? null,
                vote_average: typeof row.vote_average === 'number'
                    ? row.vote_average
                    : recommendation.vote_average ?? 0,
                vote_count: typeof row.vote_count === 'number'
                    ? row.vote_count
                    : recommendation.vote_count ?? 0,
                popularity: typeof row.popularity === 'number'
                    ? row.popularity
                    : recommendation.popularity ?? 0,
                genres: Array.isArray(row.genres)
                    ? row.genres
                    : recommendation.genres ?? [],
            };
        });
    }
    catch (error) {
        console.warn('Failed to enrich recommendations from content cache:', error);
        return recommendations;
    }
}
export class ScratchRecommendationService {
    async getForUser(userId, genre, limit = 30) {
        const data = await fetchJson(`${ML_SERVICE_URL}/recommend/${userId}?genre_filter=${encodeURIComponent(genre ?? '')}&limit=${limit}`);
        return enrichFromContentCache(data);
    }
    async getSimilar(tmdbId, limit = 20) {
        return fetchJson(`${ML_SERVICE_URL}/similar/${tmdbId}?limit=${limit}`);
    }
    async triggerTraining() {
        await fetchJson(`${ML_SERVICE_URL}/train`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
        });
        return true;
    }
}
export class HybridRecommendationService {
    async getForUser(userId, genre, limit = 30) {
        const [seenIds, preferenceCandidates, vectorCandidates, trending] = await Promise.all([
            getUserSeenIds(userId),
            this.getPreferenceCandidates(userId, genre, limit),
            this.getVectorCandidates(userId, genre, limit),
            tmdbService.getTrending({ genre, limit }),
        ]);
        return this.mergeAndRank({
            preference: preferenceCandidates,
            vector: vectorCandidates,
            trending,
        }, seenIds, limit);
    }
    async getSimilar(tmdbId, limit = 20) {
        if (supabase) {
            try {
                const { data, error } = await supabase
                    .from('content')
                    .select('embedding')
                    .eq('tmdb_id', tmdbId)
                    .single();
                if (!error && data?.embedding) {
                    const { data: matches, error: rpcError } = await supabase.rpc('match_content_by_embedding', {
                        query_embedding: data.embedding,
                        match_threshold: 0.3,
                        match_count: limit,
                        exclude_tmdb_ids: [tmdbId],
                        genre_filter: null,
                    });
                    if (!rpcError && Array.isArray(matches)) {
                        return matches.map((match, index) => ({
                            tmdb_id: Number(match.tmdb_id),
                            media_type: match.media_type === 'tv' ? 'tv' : 'movie',
                            title: String(match.title ?? 'Untitled'),
                            poster_path: typeof match.poster_path === 'string' ? match.poster_path : null,
                            score: Number(match.similarity ?? 0.5),
                            reason: 'Semantically close to the title you opened',
                            algorithm: 'pgvector',
                        }));
                    }
                }
            }
            catch (error) {
                console.warn('Hybrid similar lookup failed:', error);
            }
        }
        return (await tmdbService.getSimilar(tmdbId, 'movie', limit)).map((item, index) => ({
            ...item,
            score: 1 - index / limit,
            reason: 'TMDB similarity fallback',
            algorithm: 'tmdb',
        }));
    }
    async triggerTraining() {
        return false;
    }
    async getPreferenceCandidates(userId, genre, limit = 30) {
        if (!supabase) {
            return [];
        }
        try {
            const { data: profile } = await supabase
                .from('profiles')
                .select('preferences')
                .eq('id', userId)
                .single();
            const rawPreferences = profile?.preferences;
            const preferredGenres = Array.isArray(rawPreferences?.genres)
                ? rawPreferences.genres.filter((value) => typeof value === 'string')
                : [];
            const targetGenre = genre && genre !== 'Top 10' ? genre : preferredGenres[0] ?? null;
            const { data, error } = await supabase
                .from('content')
                .select('tmdb_id, media_type, title, overview, poster_path, backdrop_path, release_date, vote_average, vote_count, popularity, genres')
                .order('vote_average', { ascending: false })
                .limit(limit * 2);
            if (error) {
                throw error;
            }
            return (data ?? [])
                .filter((row) => {
                if (!targetGenre) {
                    return true;
                }
                const genresField = JSON.stringify(row.genres ?? []);
                return genresField.toLowerCase().includes(targetGenre.toLowerCase());
            })
                .slice(0, limit)
                .map((row, index) => ({
                tmdb_id: Number(row.tmdb_id),
                media_type: row.media_type === 'tv' ? 'tv' : 'movie',
                title: String(row.title),
                overview: String(row.overview ?? ''),
                poster_path: typeof row.poster_path === 'string' ? row.poster_path : null,
                backdrop_path: typeof row.backdrop_path === 'string' ? row.backdrop_path : null,
                release_date: typeof row.release_date === 'string' ? row.release_date : null,
                vote_average: Number(row.vote_average ?? 0),
                vote_count: Number(row.vote_count ?? 0),
                popularity: Number(row.popularity ?? 0),
                genres: Array.isArray(row.genres)
                    ? row.genres
                    : [],
                score: 0.75 - index / (limit * 2),
                reason: targetGenre
                    ? `Preference match for your ${targetGenre} onboarding picks`
                    : 'Preference-driven content match',
                algorithm: 'preferences',
            }));
        }
        catch (error) {
            console.warn('Preference candidate generation failed:', error);
            return [];
        }
    }
    async getVectorCandidates(userId, genre, limit = 30) {
        if (!supabase) {
            return [];
        }
        try {
            const userEmbedding = await this.buildUserEmbedding(userId);
            if (!userEmbedding) {
                return [];
            }
            const seenIds = await getUserSeenIds(userId);
            const { data, error } = await supabase.rpc('match_content_by_embedding', {
                query_embedding: userEmbedding,
                match_threshold: 0.25,
                match_count: limit,
                exclude_tmdb_ids: seenIds,
                genre_filter: genre && genre !== 'Top 10' ? genre : null,
            });
            if (error || !Array.isArray(data)) {
                return [];
            }
            return data.map((row, index) => ({
                tmdb_id: Number(row.tmdb_id),
                media_type: row.media_type === 'tv' ? 'tv' : 'movie',
                title: String(row.title ?? 'Untitled'),
                poster_path: typeof row.poster_path === 'string' ? row.poster_path : null,
                score: 0.85 - index / (limit * 1.4),
                reason: 'Vector match against the things you rate and rewatch',
                algorithm: 'pgvector',
            }));
        }
        catch (error) {
            console.warn('Vector candidate generation failed:', error);
            return [];
        }
    }
    async buildUserEmbedding(userId) {
        if (!supabase) {
            return null;
        }
        const { data: logs, error } = await supabase
            .from('logs')
            .select('tmdb_id, rating, liked')
            .eq('user_id', userId)
            .limit(200);
        if (error || !logs || logs.length < 3) {
            return null;
        }
        const ids = logs.map((log) => Number(log.tmdb_id));
        const { data: embeddings, error: embeddingError } = await supabase
            .from('content')
            .select('tmdb_id, embedding')
            .in('tmdb_id', ids)
            .not('embedding', 'is', null);
        if (embeddingError || !embeddings?.length) {
            return null;
        }
        let sum = null;
        let totalWeight = 0;
        for (const row of embeddings) {
            const vector = Array.isArray(row.embedding)
                ? row.embedding
                : typeof row.embedding === 'string'
                    ? JSON.parse(row.embedding)
                    : null;
            if (!vector) {
                continue;
            }
            const log = logs.find((entry) => Number(entry.tmdb_id) === Number(row.tmdb_id));
            const weight = ((Number(log?.rating ?? 3) / 5) + (log?.liked ? 0.4 : 0));
            if (!sum) {
                sum = new Array(vector.length).fill(0);
            }
            vector.forEach((value, index) => {
                sum[index] += value * weight;
            });
            totalWeight += weight;
        }
        if (!sum || totalWeight === 0) {
            return null;
        }
        return sum.map((value) => value / totalWeight);
    }
    mergeAndRank(sources, seenIds, limit) {
        const scoreMap = new Map();
        sources.preference.forEach((item, index) => {
            if (seenIds.includes(item.tmdb_id)) {
                return;
            }
            scoreMap.set(item.tmdb_id, {
                ...item,
                score: item.score + (1 - index / Math.max(1, sources.preference.length)) * 0.35,
            });
        });
        sources.vector.forEach((item, index) => {
            if (seenIds.includes(item.tmdb_id)) {
                return;
            }
            const existing = scoreMap.get(item.tmdb_id);
            const bonus = (1 - index / Math.max(1, sources.vector.length)) * 0.4;
            if (existing) {
                scoreMap.set(item.tmdb_id, {
                    ...existing,
                    ...item,
                    score: existing.score + bonus,
                    algorithm: 'hybrid',
                    reason: existing.reason,
                });
            }
            else {
                scoreMap.set(item.tmdb_id, { ...item, score: item.score + bonus });
            }
        });
        sources.trending.forEach((item, index) => {
            if (seenIds.includes(item.tmdb_id)) {
                return;
            }
            const bonus = (1 - index / Math.max(1, sources.trending.length)) * 0.2;
            const existing = scoreMap.get(item.tmdb_id);
            if (existing) {
                scoreMap.set(item.tmdb_id, {
                    ...existing,
                    ...item,
                    score: existing.score + bonus,
                });
            }
            else {
                scoreMap.set(item.tmdb_id, {
                    ...item,
                    score: bonus,
                    reason: 'Trending right now',
                    algorithm: 'tmdb',
                });
            }
        });
        return [...scoreMap.values()]
            .sort((left, right) => right.score - left.score)
            .slice(0, limit);
    }
}
export function getRecommendationMode() {
    return RECOMMENDATION_MODE;
}
export async function getRecommendationsForUser(userId, genre, limit = 30) {
    const service = RECOMMENDATION_MODE === 'hybrid'
        ? new HybridRecommendationService()
        : new ScratchRecommendationService();
    try {
        return await service.getForUser(userId, genre, limit);
    }
    catch (error) {
        console.warn('Recommendation service failed, using TMDB fallback:', error);
        return (await tmdbService.getTrending({ genre, limit })).map((item, index) => ({
            ...item,
            score: 1 - index / Math.max(1, limit),
            reason: 'Graceful TMDB fallback while recommendation infrastructure recovers',
            algorithm: 'tmdb_fallback',
        }));
    }
}
export async function getSimilarTitles(tmdbId, limit = 20) {
    const service = RECOMMENDATION_MODE === 'hybrid'
        ? new HybridRecommendationService()
        : new ScratchRecommendationService();
    try {
        return await service.getSimilar(tmdbId, limit);
    }
    catch (error) {
        console.warn('Similar service failed, using TMDB fallback:', error);
        return (await tmdbService.getSimilar(tmdbId, 'movie', limit)).map((item, index) => ({
            ...item,
            score: 1 - index / Math.max(1, limit),
            reason: 'TMDB similarity fallback',
            algorithm: 'tmdb_fallback',
        }));
    }
}
export async function triggerRetraining() {
    if (RECOMMENDATION_MODE !== 'scratch') {
        return false;
    }
    const service = new ScratchRecommendationService();
    return service.triggerTraining();
}
