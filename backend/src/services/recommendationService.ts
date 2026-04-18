import { requireSupabase, supabase } from '../config/supabase';
import { tmdbService, type CatalogItem } from './tmdbService';

const ML_SERVICE_URL = process.env.ML_SERVICE_URL ?? 'http://localhost:8000';
const RAW_RECOMMENDATION_MODE = process.env.RECOMMENDATION_MODE ?? 'scratch';

type RecommendationMode = 'scratch' | 'mode_a' | 'mode_b';

function normalizeRecommendationMode(mode: string): RecommendationMode {
  const normalized = mode.trim().toLowerCase();
  if (normalized === 'mode_a' || normalized === 'a' || normalized === 'tmdb') {
    return 'mode_a';
  }
  if (
    normalized === 'mode_b' ||
    normalized === 'b' ||
    normalized === 'hybrid'
  ) {
    return 'mode_b';
  }
  return 'scratch';
}

const RECOMMENDATION_MODE = normalizeRecommendationMode(RAW_RECOMMENDATION_MODE);

export interface RecommendationResult extends Partial<CatalogItem> {
  tmdb_id: number;
  media_type: 'movie' | 'tv';
  score: number;
  reason: string;
  algorithm: string;
}

type ActivityClient = {
  from: (table: string) => {
    insert: (payload: Record<string, unknown>) => Promise<{ error?: { message?: string } | null }>;
  };
};

function getActivityClient(clientOverride?: ActivityClient | null): ActivityClient | null {
  if (clientOverride) {
    return clientOverride;
  }

  if (supabase) {
    return supabase as unknown as ActivityClient;
  }

  try {
    return requireSupabase() as unknown as ActivityClient;
  } catch {
    return null;
  }
}

export async function trackRecommendationBehaviorEvent(
  userId: string,
  activityType: string,
  metadata: Record<string, unknown> = {},
  clientOverride?: ActivityClient | null,
): Promise<boolean> {
  const client = getActivityClient(clientOverride);
  if (!client) {
    return false;
  }

  try {
    const payload = {
      user_id: userId,
      activity_type: activityType,
      metadata: {
        ...metadata,
        recommendation_mode: RECOMMENDATION_MODE,
      },
      created_at: new Date().toISOString(),
    };

    const { error } = await client.from('activity').insert(payload);
    if (error) {
      throw error;
    }
    return true;
  } catch (error) {
    console.warn('Failed to persist recommendation behavior event:', error);
    return false;
  }
}

async function fetchJson<T>(url: string, options?: RequestInit): Promise<T> {
  const response = await fetch(url, options);
  if (!response.ok) {
    throw new Error(`Request failed (${response.status} ${response.statusText})`);
  }
  return (await response.json()) as T;
}

type RecommendationSeed = {
  tmdb_id: number;
  media_type: 'movie' | 'tv';
  weight: number;
};

type RecommendationServiceContract = {
  getForUser: (
    userId: string,
    genre?: string,
    limit?: number,
  ) => Promise<RecommendationResult[]>;
  getSimilar: (tmdbId: number, limit?: number) => Promise<RecommendationResult[]>;
  triggerTraining: () => Promise<boolean>;
};

function clamp(value: number, min: number, max: number): number {
  return Math.min(Math.max(value, min), max);
}

function getRankScore(index: number, total: number): number {
  if (total <= 1) {
    return 1;
  }
  return clamp(1 - index / total, 0, 1);
}

function normalizeGenreFilter(genre?: string): string | undefined {
  if (!genre) {
    return undefined;
  }
  const trimmed = genre.trim();
  if (!trimmed || trimmed.toLowerCase() === 'top 10') {
    return undefined;
  }
  return trimmed;
}

async function inferMediaTypeForTmdbId(tmdbId: number): Promise<'movie' | 'tv'> {
  if (!supabase) {
    return 'movie';
  }

  try {
    const { data, error } = await supabase
      .from('content')
      .select('media_type')
      .eq('tmdb_id', tmdbId)
      .single();

    if (!error && data?.media_type === 'tv') {
      return 'tv';
    }
  } catch {
    // Ignore content lookup failures and default to movie.
  }

  return 'movie';
}

async function getUserSeenIds(userId: string): Promise<number[]> {
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

async function enrichFromContentCache(
  recommendations: RecommendationResult[],
): Promise<RecommendationResult[]> {
  if (!supabase || recommendations.length === 0) {
    return recommendations;
  }

  try {
    const { data, error } = await supabase
      .from('content')
      .select(
        'tmdb_id, media_type, title, overview, poster_path, backdrop_path, release_date, vote_average, vote_count, popularity, genres',
      )
      .in(
        'tmdb_id',
        recommendations.map((recommendation) => recommendation.tmdb_id),
      );

    if (error) {
      throw error;
    }

    const cache = new Map<number, Record<string, unknown>>();
    (data ?? []).forEach((row) => cache.set(Number(row.tmdb_id), row));

    return recommendations.map((recommendation) => {
      const row = cache.get(recommendation.tmdb_id);
      if (!row) {
        return recommendation;
      }

      return {
        ...recommendation,
        title:
          typeof row.title === 'string' ? row.title : recommendation.title,
        overview:
          typeof row.overview === 'string' ? row.overview : recommendation.overview,
        poster_path:
          typeof row.poster_path === 'string'
            ? row.poster_path
            : recommendation.poster_path ?? null,
        backdrop_path:
          typeof row.backdrop_path === 'string'
            ? row.backdrop_path
            : recommendation.backdrop_path ?? null,
        release_date:
          typeof row.release_date === 'string'
            ? row.release_date
            : recommendation.release_date ?? null,
        vote_average:
          typeof row.vote_average === 'number'
            ? row.vote_average
            : recommendation.vote_average ?? 0,
        vote_count:
          typeof row.vote_count === 'number'
            ? row.vote_count
            : recommendation.vote_count ?? 0,
        popularity:
          typeof row.popularity === 'number'
            ? row.popularity
            : recommendation.popularity ?? 0,
        genres: Array.isArray(row.genres)
          ? (row.genres as Array<{ id: number; name: string }>)
          : recommendation.genres ?? [],
      };
    });
  } catch (error) {
    console.warn('Failed to enrich recommendations from content cache:', error);
    return recommendations;
  }
}

export class ModeARecommendationService {
  async getForUser(
    userId: string,
    genre?: string,
    limit: number = 30,
  ): Promise<RecommendationResult[]> {
    const normalizedGenre = normalizeGenreFilter(genre);
    const [seenIds, seeds, genreCandidates] = await Promise.all([
      getUserSeenIds(userId),
      this.getSeedsForUser(userId, 4),
      normalizedGenre
        ? tmdbService.discoverByGenre(normalizedGenre, Math.max(limit * 2, 24), 'movie')
        : Promise.resolve([]),
    ]);

    const seenSet = new Set(seenIds);
    const scoreMap = new Map<number, RecommendationResult>();

    const mergeCandidate = (candidate: RecommendationResult, blendFactor: number = 0.35): void => {
      if (seenSet.has(candidate.tmdb_id)) {
        return;
      }

      const existing = scoreMap.get(candidate.tmdb_id);
      if (!existing) {
        scoreMap.set(candidate.tmdb_id, candidate);
        return;
      }

      const candidateDominates = candidate.score >= existing.score;
      scoreMap.set(candidate.tmdb_id, {
        ...(candidateDominates ? candidate : existing),
        score: existing.score + candidate.score * blendFactor,
        algorithm:
          existing.algorithm === candidate.algorithm
            ? existing.algorithm
            : 'tmdb_mode_a_hybrid',
        reason: candidateDominates ? candidate.reason : existing.reason,
      });
    };

    const seedResponses = await Promise.all(
      seeds.map(async (seed) => {
        const [recommendationsResult, similarResult] = await Promise.allSettled([
          tmdbService.getRecommendations(
            seed.tmdb_id,
            seed.media_type,
            Math.max(limit * 2, 24),
          ),
          tmdbService.getSimilar(
            seed.tmdb_id,
            seed.media_type,
            Math.max(limit * 2, 24),
          ),
        ]);

        return {
          seed,
          recommendations:
            recommendationsResult.status === 'fulfilled'
              ? recommendationsResult.value
              : [],
          similar: similarResult.status === 'fulfilled' ? similarResult.value : [],
        };
      }),
    );

    seedResponses.forEach(({ seed, recommendations, similar }) => {
      recommendations.forEach((item, index) => {
        const rankScore = getRankScore(index, recommendations.length);
        const score = seed.weight * 0.7 + rankScore * 0.3;
        mergeCandidate(
          {
            ...item,
            score,
            reason: 'TMDB recommendations from your recent activity',
            algorithm: 'tmdb_recommendations',
          },
          0.33,
        );
      });

      similar.forEach((item, index) => {
        const rankScore = getRankScore(index, similar.length);
        const score = seed.weight * 0.55 + rankScore * 0.25;
        mergeCandidate(
          {
            ...item,
            score,
            reason: 'TMDB similar to titles you interacted with',
            algorithm: 'tmdb_similar',
          },
          0.25,
        );
      });
    });

    genreCandidates.forEach((item, index) => {
      const rankScore = getRankScore(index, genreCandidates.length);
      mergeCandidate(
        {
          ...item,
          score: 0.25 + rankScore * 0.2,
          reason: `TMDB genre match for ${normalizedGenre}`,
          algorithm: 'tmdb_genre',
        },
        0.2,
      );
    });

    if (scoreMap.size === 0) {
      const fallback = (await tmdbService.getTrending({ genre: normalizedGenre, limit })).map(
        (item, index): RecommendationResult => ({
          ...item,
          score: 1 - index / Math.max(1, limit),
          reason: 'TMDB trending fallback for your current profile',
          algorithm: 'tmdb_trending',
        }),
      );
      return enrichFromContentCache(fallback);
    }

    const ranked = [...scoreMap.values()]
      .sort((left, right) => right.score - left.score)
      .slice(0, limit);

    return enrichFromContentCache(ranked);
  }

  async getSimilar(tmdbId: number, limit: number = 20): Promise<RecommendationResult[]> {
    const mediaType = await inferMediaTypeForTmdbId(tmdbId);
    const [recommendationsResult, similarResult] = await Promise.allSettled([
      tmdbService.getRecommendations(tmdbId, mediaType, Math.max(limit * 2, 20)),
      tmdbService.getSimilar(tmdbId, mediaType, Math.max(limit * 2, 20)),
    ]);

    const scoreMap = new Map<number, RecommendationResult>();

    const mergeCandidate = (candidate: RecommendationResult, blendFactor: number = 0.3): void => {
      if (candidate.tmdb_id === tmdbId) {
        return;
      }

      const existing = scoreMap.get(candidate.tmdb_id);
      if (!existing) {
        scoreMap.set(candidate.tmdb_id, candidate);
        return;
      }

      scoreMap.set(candidate.tmdb_id, {
        ...(candidate.score >= existing.score ? candidate : existing),
        score: existing.score + candidate.score * blendFactor,
        algorithm:
          existing.algorithm === candidate.algorithm
            ? existing.algorithm
            : 'tmdb_mode_a_hybrid',
      });
    };

    if (recommendationsResult.status === 'fulfilled') {
      recommendationsResult.value.forEach((item, index) => {
        mergeCandidate({
          ...item,
          score: 0.7 * getRankScore(index, recommendationsResult.value.length),
          reason: 'TMDB recommendations for this title',
          algorithm: 'tmdb_recommendations',
        });
      });
    }

    if (similarResult.status === 'fulfilled') {
      similarResult.value.forEach((item, index) => {
        mergeCandidate(
          {
            ...item,
            score: 0.5 * getRankScore(index, similarResult.value.length),
            reason: 'TMDB similar titles',
            algorithm: 'tmdb_similar',
          },
          0.25,
        );
      });
    }

    if (scoreMap.size === 0) {
      return (await tmdbService.getTrending({ limit })).map(
        (item, index): RecommendationResult => ({
          ...item,
          score: 1 - index / Math.max(1, limit),
          reason: 'TMDB trending fallback',
          algorithm: 'tmdb_trending',
        }),
      );
    }

    return [...scoreMap.values()]
      .sort((left, right) => right.score - left.score)
      .slice(0, limit);
  }

  async triggerTraining(): Promise<boolean> {
    return false;
  }

  private async getSeedsForUser(userId: string, maxSeeds: number): Promise<RecommendationSeed[]> {
    if (!supabase) {
      return [];
    }

    try {
      const { data, error } = await supabase
        .from('logs')
        .select('tmdb_id, media_type, status, rating, liked, rewatch, created_at')
        .eq('user_id', userId)
        .order('created_at', { ascending: false })
        .limit(250);

      if (error || !Array.isArray(data)) {
        return [];
      }

      const seedMap = new Map<string, RecommendationSeed>();

      data.forEach((rawRow) => {
        const row = rawRow as Record<string, unknown>;
        const tmdbId = Number(row.tmdb_id);
        if (!Number.isFinite(tmdbId) || tmdbId <= 0) {
          return;
        }

        const mediaType = row.media_type === 'tv' ? 'tv' : 'movie';
        const ratingValue =
          typeof row.rating === 'number' ? row.rating : Number(row.rating ?? Number.NaN);
        let weight = Number.isFinite(ratingValue)
          ? clamp(ratingValue / 5, 0.1, 1)
          : this.statusToWeight(typeof row.status === 'string' ? row.status : null);

        if (row.liked === true) {
          weight += 0.2;
        }
        if (row.rewatch === true) {
          weight += 0.15;
        }

        if (typeof row.created_at === 'string') {
          const timestamp = Date.parse(row.created_at);
          if (Number.isFinite(timestamp)) {
            const daysAgo = (Date.now() - timestamp) / (1000 * 60 * 60 * 24);
            weight += clamp(1 - daysAgo / 180, 0, 1) * 0.15;
          }
        }

        weight = clamp(weight, 0.1, 1.4);
        const key = `${mediaType}:${tmdbId}`;
        const existing = seedMap.get(key);
        if (!existing || weight > existing.weight) {
          seedMap.set(key, {
            tmdb_id: tmdbId,
            media_type: mediaType,
            weight,
          });
        }
      });

      return [...seedMap.values()]
        .sort((left, right) => right.weight - left.weight)
        .slice(0, maxSeeds);
    } catch (error) {
      console.warn('Mode A seed generation failed:', error);
      return [];
    }
  }

  private statusToWeight(status: string | null): number {
    if (!status) {
      return 0.45;
    }
    switch (status) {
      case 'watched':
        return 0.65;
      case 'watching':
        return 0.5;
      case 'watchlist':
      case 'plan_to_watch':
        return 0.35;
      case 'dropped':
        return 0.2;
      default:
        return 0.4;
    }
  }
}

export class ScratchRecommendationService {
  async getForUser(
    userId: string,
    genre?: string,
    limit: number = 30,
  ): Promise<RecommendationResult[]> {
    const data = await fetchJson<RecommendationResult[]>(
      `${ML_SERVICE_URL}/recommend/${userId}?genre_filter=${encodeURIComponent(
        genre ?? '',
      )}&limit=${limit}`,
    );
    return enrichFromContentCache(data);
  }

  async getSimilar(tmdbId: number, limit: number = 20): Promise<RecommendationResult[]> {
    return fetchJson<RecommendationResult[]>(
      `${ML_SERVICE_URL}/similar/${tmdbId}?limit=${limit}`,
    );
  }

  async triggerTraining(): Promise<boolean> {
    await fetchJson(`${ML_SERVICE_URL}/train`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
    });
    return true;
  }
}

export class ModeBRecommendationService {
  async getForUser(
    userId: string,
    genre?: string,
    limit: number = 30,
  ): Promise<RecommendationResult[]> {
    const [seenIds, preferenceCandidates, vectorCandidates, trending] =
      await Promise.all([
        getUserSeenIds(userId),
        this.getPreferenceCandidates(userId, genre, limit),
        this.getVectorCandidates(userId, genre, limit),
        tmdbService.getTrending({ genre, limit }),
      ]);

    return this.mergeAndRank(
      {
        preference: preferenceCandidates,
        vector: vectorCandidates,
        trending,
      },
      seenIds,
      limit,
    );
  }

  async getSimilar(tmdbId: number, limit: number = 20): Promise<RecommendationResult[]> {
    if (supabase) {
      try {
        const { data, error } = await supabase
          .from('content')
          .select('embedding')
          .eq('tmdb_id', tmdbId)
          .single();

        if (!error && data?.embedding) {
          const { data: matches, error: rpcError } = await supabase.rpc(
            'match_content_by_embedding',
            {
              query_embedding: data.embedding,
              match_threshold: 0.3,
              match_count: limit,
              exclude_tmdb_ids: [tmdbId],
              genre_filter: null,
            },
          );

          if (!rpcError && Array.isArray(matches)) {
            return matches.map((match, index) => ({
              tmdb_id: Number(match.tmdb_id),
              media_type: match.media_type === 'tv' ? 'tv' : 'movie',
              title: String(match.title ?? 'Untitled'),
              poster_path:
                typeof match.poster_path === 'string' ? match.poster_path : null,
              score: Number(match.similarity ?? 0.5),
              reason: 'Semantically close to the title you opened',
              algorithm: 'pgvector',
            }));
          }
        }
      } catch (error) {
        console.warn('Hybrid similar lookup failed:', error);
      }
    }

    return (await tmdbService.getSimilar(tmdbId, 'movie', limit)).map(
      (item, index): RecommendationResult => ({
        ...item,
        score: 1 - index / limit,
        reason: 'TMDB similarity fallback',
        algorithm: 'tmdb',
      }),
    );
  }

  async triggerTraining(): Promise<boolean> {
    return false;
  }

  private async getPreferenceCandidates(
    userId: string,
    genre?: string,
    limit: number = 30,
  ): Promise<RecommendationResult[]> {
    if (!supabase) {
      return [];
    }

    try {
      const { data: profile } = await supabase
        .from('profiles')
        .select('preferences')
        .eq('id', userId)
        .single();

      const rawPreferences = profile?.preferences as
        | { genres?: unknown[]; initial_ratings?: Array<{ tmdb_id: number }> }
        | undefined;

      const preferredGenres = Array.isArray(rawPreferences?.genres)
        ? rawPreferences.genres.filter((value): value is string => typeof value === 'string')
        : [];

      const targetGenre = genre && genre !== 'Top 10' ? genre : preferredGenres[0] ?? null;

      const { data, error } = await supabase
        .from('content')
        .select(
          'tmdb_id, media_type, title, overview, poster_path, backdrop_path, release_date, vote_average, vote_count, popularity, genres',
        )
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
        .map(
          (row, index): RecommendationResult => ({
            tmdb_id: Number(row.tmdb_id),
            media_type: row.media_type === 'tv' ? 'tv' : 'movie',
            title: String(row.title),
            overview: String(row.overview ?? ''),
            poster_path:
              typeof row.poster_path === 'string' ? row.poster_path : null,
            backdrop_path:
              typeof row.backdrop_path === 'string' ? row.backdrop_path : null,
            release_date:
              typeof row.release_date === 'string' ? row.release_date : null,
            vote_average: Number(row.vote_average ?? 0),
            vote_count: Number(row.vote_count ?? 0),
            popularity: Number(row.popularity ?? 0),
            genres: Array.isArray(row.genres)
              ? (row.genres as Array<{ id: number; name: string }>)
              : [],
            score: 0.75 - index / (limit * 2),
            reason: targetGenre
              ? `Preference match for your ${targetGenre} onboarding picks`
              : 'Preference-driven content match',
            algorithm: 'preferences',
          }),
        );
    } catch (error) {
      console.warn('Preference candidate generation failed:', error);
      return [];
    }
  }

  private async getVectorCandidates(
    userId: string,
    genre?: string,
    limit: number = 30,
  ): Promise<RecommendationResult[]> {
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

      return data.map(
        (row, index): RecommendationResult => ({
          tmdb_id: Number(row.tmdb_id),
          media_type: row.media_type === 'tv' ? 'tv' : 'movie',
          title: String(row.title ?? 'Untitled'),
          poster_path:
            typeof row.poster_path === 'string' ? row.poster_path : null,
          score: 0.85 - index / (limit * 1.4),
          reason: 'Vector match against the things you rate and rewatch',
          algorithm: 'pgvector',
        }),
      );
    } catch (error) {
      console.warn('Vector candidate generation failed:', error);
      return [];
    }
  }

  private async buildUserEmbedding(userId: string): Promise<number[] | null> {
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

    let sum: number[] | null = null;
    let totalWeight = 0;
    for (const row of embeddings) {
      const vector = Array.isArray(row.embedding)
        ? row.embedding
        : typeof row.embedding === 'string'
          ? JSON.parse(row.embedding) as number[]
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
        sum![index] += value * weight;
      });
      totalWeight += weight;
    }

    if (!sum || totalWeight === 0) {
      return null;
    }

    return sum.map((value) => value / totalWeight);
  }

  private mergeAndRank(
    sources: {
      preference: RecommendationResult[];
      vector: RecommendationResult[];
      trending: CatalogItem[];
    },
    seenIds: number[],
    limit: number,
  ): RecommendationResult[] {
    const scoreMap = new Map<number, RecommendationResult>();

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
      } else {
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
      } else {
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

// Backward-compatibility alias for previous imports.
export class HybridRecommendationService extends ModeBRecommendationService {}

function createRecommendationService(): RecommendationServiceContract {
  switch (RECOMMENDATION_MODE) {
    case 'mode_a':
      return new ModeARecommendationService();
    case 'mode_b':
      return new ModeBRecommendationService();
    case 'scratch':
    default:
      return new ScratchRecommendationService();
  }
}

export function getRecommendationMode(): string {
  return RECOMMENDATION_MODE;
}

export async function getRecommendationsForUser(
  userId: string,
  genre?: string,
  limit: number = 30,
): Promise<RecommendationResult[]> {
  const service = createRecommendationService();

  try {
    const recommendations = await service.getForUser(userId, genre, limit);
    await trackRecommendationBehaviorEvent(userId, 'recommendation_foryou_served', {
      genre_filter: genre ?? null,
      limit,
      result_count: recommendations.length,
      fallback: false,
    });
    return recommendations;
  } catch (error) {
    console.warn('Recommendation service failed, using TMDB fallback:', error);
    const fallbackRecommendations = (await tmdbService.getTrending({ genre, limit })).map(
      (item, index): RecommendationResult => ({
        ...item,
        score: 1 - index / Math.max(1, limit),
        reason: 'Graceful TMDB fallback while recommendation infrastructure recovers',
        algorithm: 'tmdb_fallback',
      }),
    );

    await trackRecommendationBehaviorEvent(userId, 'recommendation_foryou_served', {
      genre_filter: genre ?? null,
      limit,
      result_count: fallbackRecommendations.length,
      fallback: true,
    });

    return fallbackRecommendations;
  }
}

export async function getSimilarTitles(
  tmdbId: number,
  limit: number = 20,
  userId?: string,
): Promise<RecommendationResult[]> {
  const service = createRecommendationService();

  try {
    const recommendations = await service.getSimilar(tmdbId, limit);
    if (userId) {
      await trackRecommendationBehaviorEvent(userId, 'recommendation_similar_served', {
        tmdb_id: tmdbId,
        limit,
        result_count: recommendations.length,
        fallback: false,
      });
    }
    return recommendations;
  } catch (error) {
    console.warn('Similar service failed, using TMDB fallback:', error);
    const fallbackRecommendations = (await tmdbService.getSimilar(tmdbId, 'movie', limit)).map(
      (item, index): RecommendationResult => ({
        ...item,
        score: 1 - index / Math.max(1, limit),
        reason: 'TMDB similarity fallback',
        algorithm: 'tmdb_fallback',
      }),
    );

    if (userId) {
      await trackRecommendationBehaviorEvent(userId, 'recommendation_similar_served', {
        tmdb_id: tmdbId,
        limit,
        result_count: fallbackRecommendations.length,
        fallback: true,
      });
    }

    return fallbackRecommendations;
  }
}

export async function triggerRetraining(): Promise<boolean> {
  if (RECOMMENDATION_MODE !== 'scratch') {
    return false;
  }
  const service = new ScratchRecommendationService();
  return service.triggerTraining();
}
