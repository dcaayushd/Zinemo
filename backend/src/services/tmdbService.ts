import { getCached } from '../config/cache';
import {
  assertTmdbConfigured,
  TMDB_ACCESS_TOKEN,
  TMDB_API_BASE_URL,
  TMDB_API_KEY,
  TMDB_IMAGE_BASE_URL,
} from '../config/tmdb';

export type TmdbMediaType = 'movie' | 'tv';
type TmdbFilmographyMediaType = TmdbMediaType | 'all';

export interface CatalogItem {
  tmdb_id: number;
  media_type: TmdbMediaType;
  title: string;
  overview: string;
  poster_path: string | null;
  backdrop_path: string | null;
  release_date: string | null;
  vote_average: number;
  vote_count: number;
  popularity: number;
  genres: Array<{ id: number; name: string }>;
  total_seasons?: number;
  total_episodes?: number;
  next_air_date?: string | null;
  next_episode_name?: string | null;
  next_season_number?: number | null;
  next_episode_number?: number | null;
  last_season_number?: number | null;
  last_episode_number?: number | null;
  runtime?: number;
  trailer_urls?: string[];
  availability?: string;
}

type TmdbListResponse = {
  results: Array<Record<string, unknown>>;
};

type TmdbGenresResponse = {
  genres: Array<{ id: number; name: string }>;
};

function withImage(path: unknown, size: string): string | null {
  if (!path || typeof path !== 'string') {
    return null;
  }
  return `${TMDB_IMAGE_BASE_URL}/${size}${path}`;
}

function getQueryParam(params: Record<string, string | number | undefined>): string {
  const search = new URLSearchParams();
  Object.entries(params).forEach(([key, value]) => {
    if (value !== undefined) {
      search.set(key, String(value));
    }
  });
  if (!TMDB_ACCESS_TOKEN && TMDB_API_KEY) {
    search.set('api_key', TMDB_API_KEY);
  }
  return search.toString();
}

async function requestTmdb<T>(
  path: string,
  params: Record<string, string | number | undefined> = {},
): Promise<T> {
  assertTmdbConfigured();

  const query = getQueryParam(params);
  const response = await fetch(`${TMDB_API_BASE_URL}${path}?${query}`, {
    headers: TMDB_ACCESS_TOKEN
      ? {
          Authorization: `Bearer ${TMDB_ACCESS_TOKEN}`,
          Accept: 'application/json',
        }
      : {
          Accept: 'application/json',
        },
  });

  if (!response.ok) {
    throw new Error(`TMDB request failed (${response.status} ${response.statusText})`);
  }

  return (await response.json()) as T;
}

function normalizeItem(item: Record<string, unknown>, mediaType?: TmdbMediaType): CatalogItem {
  const inferredType = (mediaType ??
    ((item.media_type as TmdbMediaType | undefined) === 'tv' ? 'tv' : 'movie')) as TmdbMediaType;

  const nextEpisode =
    item.next_episode_to_air && typeof item.next_episode_to_air === 'object'
      ? (item.next_episode_to_air as Record<string, unknown>)
      : null;
  const lastEpisode =
    item.last_episode_to_air && typeof item.last_episode_to_air === 'object'
      ? (item.last_episode_to_air as Record<string, unknown>)
      : null;

  const runtime =
    typeof item.runtime === 'number'
      ? Number(item.runtime)
      : inferredType === 'tv' &&
            Array.isArray(item.episode_run_time) &&
            item.episode_run_time.length > 0
        ? Number(item.episode_run_time[0])
        : undefined;

  const videos =
    item.videos &&
        typeof item.videos === 'object' &&
        Array.isArray((item.videos as Record<string, unknown>)['results'])
      ? ((item.videos as Record<string, unknown>)['results'] as Array<
          Record<string, unknown>
        >)
      : [];

  const trailerUrls = Array.from(
    new Set(
      videos
        .filter((video) => {
          const site = String(video.site ?? '').toLowerCase();
          const type = String(video.type ?? '').toLowerCase();
          return site === 'youtube' && (type === 'trailer' || type === 'teaser');
        })
        .map((video) => String(video.key ?? '').trim())
        .filter((key: string) => key.length > 0)
        .map((key) => `https://www.youtube.com/watch?v=${key}`),
    ),
  );

  return {
    tmdb_id: Number(item.id),
    media_type: inferredType,
    title: String(item.title ?? item.name ?? 'Untitled'),
    overview: String(item.overview ?? ''),
    poster_path: withImage(item.poster_path, 'w500'),
    backdrop_path: withImage(item.backdrop_path, 'w1280'),
    release_date: String(
      item.release_date ?? item.first_air_date ?? '',
    ).trim() || null,
    vote_average: Number(item.vote_average ?? 0),
    vote_count: Number(item.vote_count ?? 0),
    popularity: Number(item.popularity ?? 0),
    genres: Array.isArray(item.genres)
      ? (item.genres as Array<{ id: number; name: string }>)
      : Array.isArray(item.genre_ids)
        ? (item.genre_ids as number[]).map((id) => ({ id, name: `Genre ${id}` }))
        : [],
    total_seasons:
      inferredType === 'tv' && typeof item.number_of_seasons === 'number'
        ? Number(item.number_of_seasons)
        : undefined,
    total_episodes:
      inferredType === 'tv' && typeof item.number_of_episodes === 'number'
        ? Number(item.number_of_episodes)
        : undefined,
    next_air_date:
      inferredType === 'tv' && nextEpisode && typeof nextEpisode.air_date === 'string'
        ? String(nextEpisode.air_date)
        : null,
    next_episode_name:
      inferredType === 'tv' && nextEpisode && typeof nextEpisode.name === 'string'
        ? String(nextEpisode.name)
        : null,
    next_season_number:
      inferredType === 'tv' && nextEpisode && typeof nextEpisode.season_number === 'number'
        ? Number(nextEpisode.season_number)
        : null,
    next_episode_number:
      inferredType === 'tv' && nextEpisode && typeof nextEpisode.episode_number === 'number'
        ? Number(nextEpisode.episode_number)
        : null,
    last_season_number:
      inferredType === 'tv' && lastEpisode && typeof lastEpisode.season_number === 'number'
        ? Number(lastEpisode.season_number)
        : null,
    last_episode_number:
      inferredType === 'tv' && lastEpisode && typeof lastEpisode.episode_number === 'number'
        ? Number(lastEpisode.episode_number)
        : null,
    runtime,
    trailer_urls: trailerUrls.length > 0 ? trailerUrls : undefined,
  };
}

export class TMDBService {
  async getTrending(options: {
    genre?: string;
    limit?: number;
    mediaType?: TmdbMediaType;
  } = {}): Promise<CatalogItem[]> {
    const mediaType = options.mediaType ?? 'movie';
    if (options.genre && options.genre !== 'Top 10') {
      return this.discoverByGenre(options.genre, options.limit ?? 20, mediaType);
    }

    const cacheKey = `tmdb:trending:${mediaType}:${options.limit ?? 20}`;
    return getCached(cacheKey, async () => {
      const data = await requestTmdb<TmdbListResponse>(`/trending/${mediaType}/week`, {
        language: 'en-US',
      });

      return data.results
        .map((item) => normalizeItem(item, mediaType))
        .slice(0, options.limit ?? 20);
    });
  }

  async getTopRated(limit: number = 20, mediaType: TmdbMediaType = 'movie'): Promise<CatalogItem[]> {
    return getCached(`tmdb:top-rated:${mediaType}:${limit}`, async () => {
      const data = await requestTmdb<TmdbListResponse>(`/${mediaType}/top_rated`, {
        language: 'en-US',
        page: 1,
      });

      return data.results.map((item) => normalizeItem(item, mediaType)).slice(0, limit);
    });
  }

  async getNewReleases(limit: number = 20, mediaType: TmdbMediaType = 'movie'): Promise<CatalogItem[]> {
    const endpoint = mediaType === 'tv' ? '/tv/on_the_air' : '/movie/now_playing';

    return getCached(`tmdb:new-releases:${mediaType}:${limit}`, async () => {
      const data = await requestTmdb<TmdbListResponse>(endpoint, {
        language: 'en-US',
        page: 1,
      });

      return data.results.map((item) => normalizeItem(item, mediaType)).slice(0, limit);
    });
  }

  async getGenres(): Promise<Array<{ id: number; name: string }>> {
    return getCached('tmdb:genres', async () => {
      const data = await requestTmdb<TmdbGenresResponse>('/genre/movie/list', {
        language: 'en-US',
      });
      return data.genres;
    });
  }

  async discoverByGenre(
    genreName: string,
    limit: number = 20,
    mediaType: TmdbMediaType = 'movie',
  ): Promise<CatalogItem[]> {
    const genres = await this.getGenres();
    const genreMatch = genres.find(
      (genre) => genre.name.toLowerCase() === genreName.toLowerCase(),
    );
    if (!genreMatch) {
      return this.getTrending({ limit, mediaType });
    }

    return getCached(`tmdb:discover:${mediaType}:${genreMatch.id}:${limit}`, async () => {
      const data = await requestTmdb<TmdbListResponse>(`/discover/${mediaType}`, {
        with_genres: genreMatch.id,
        sort_by: 'popularity.desc',
        include_adult: 'false',
        language: 'en-US',
        page: 1,
      });

      return data.results.map((item) => normalizeItem(item, mediaType)).slice(0, limit);
    });
  }

  async search(query: string, limit: number = 20): Promise<CatalogItem[]> {
    return getCached(`tmdb:search:${query}:${limit}`, async () => {
      const data = await requestTmdb<TmdbListResponse>('/search/multi', {
        query,
        include_adult: 'false',
        language: 'en-US',
        page: 1,
      });

      return data.results
        .filter((item) => item.media_type === 'movie' || item.media_type === 'tv')
        .map((item) => normalizeItem(item))
        .slice(0, limit);
    });
  }

  async getDetails(tmdbId: number, mediaType: TmdbMediaType = 'movie'): Promise<CatalogItem> {
    return getCached(`tmdb:details:${mediaType}:${tmdbId}`, async () => {
      const data = await requestTmdb<Record<string, unknown>>(`/${mediaType}/${tmdbId}`, {
        language: 'en-US',
        append_to_response: 'videos',
      });
      return normalizeItem(data, mediaType);
    });
  }

  async getSimilar(
    tmdbId: number,
    mediaType: TmdbMediaType = 'movie',
    limit: number = 20,
  ): Promise<CatalogItem[]> {
    return getCached(`tmdb:similar:${mediaType}:${tmdbId}:${limit}`, async () => {
      const data = await requestTmdb<TmdbListResponse>(`/${mediaType}/${tmdbId}/similar`, {
        language: 'en-US',
        page: 1,
      });
      return data.results.map((item) => normalizeItem(item, mediaType)).slice(0, limit);
    });
  }

  async getRecommendations(
    tmdbId: number,
    mediaType: TmdbMediaType = 'movie',
    limit: number = 20,
  ): Promise<CatalogItem[]> {
    return getCached(`tmdb:recommendations:${mediaType}:${tmdbId}:${limit}`, async () => {
      const data = await requestTmdb<TmdbListResponse>(
        `/${mediaType}/${tmdbId}/recommendations`,
        {
          language: 'en-US',
          page: 1,
        },
      );
      return data.results.map((item) => normalizeItem(item, mediaType)).slice(0, limit);
    });
  }

  async getCredits(
    tmdbId: number,
    mediaType: TmdbMediaType = 'movie',
  ): Promise<{
    cast: Array<{
      id: number;
      name: string;
      character: string;
      profile_path: string | null;
      popularity: number;
    }>;
    crew: Array<{
      id: number;
      name: string;
      job: string;
      department: string;
      profile_path: string | null;
      popularity: number;
    }>;
  }> {
    return getCached(`tmdb:credits:${mediaType}:${tmdbId}`, async () => {
      const data = await requestTmdb<{
        cast: Array<Record<string, unknown>>;
        crew: Array<Record<string, unknown>>;
      }>(`/${mediaType}/${tmdbId}/credits`, {
        language: 'en-US',
      });

      return {
        cast: (data.cast || [])
          .map((item) => ({
            id: Number(item.id),
            name: String(item.name || ''),
            character: String(item.character || ''),
            profile_path: item.profile_path ? String(item.profile_path) : null,
            popularity: Number(item.popularity || 0),
          }))
          .sort((a, b) => b.popularity - a.popularity)
          .slice(0, 50),
        crew: (data.crew || [])
          .map((item) => ({
            id: Number(item.id),
            name: String(item.name || ''),
            job: String(item.job || ''),
            department: String(item.department || ''),
            profile_path: item.profile_path ? String(item.profile_path) : null,
            popularity: Number(item.popularity || 0),
          }))
          .slice(0, 50),
      };
    });
  }

  async getPerson(personId: number): Promise<{
    id: number;
    name: string;
    biography: string | null;
    birthday: string | null;
    deathday: string | null;
    place_of_birth: string | null;
    profile_path: string | null;
    popularity: number;
  }> {
    return getCached(`tmdb:person:${personId}`, async () => {
      const data = await requestTmdb<Record<string, unknown>>(`/person/${personId}`, {
        language: 'en-US',
      });

      return {
        id: Number(data.id),
        name: String(data.name || ''),
        biography: data.biography ? String(data.biography) : null,
        birthday: data.birthday ? String(data.birthday) : null,
        deathday: data.deathday ? String(data.deathday) : null,
        place_of_birth: data.place_of_birth ? String(data.place_of_birth) : null,
        profile_path: data.profile_path ? String(data.profile_path) : null,
        popularity: Number(data.popularity || 0),
      };
    });
  }

  async getPersonFilmography(
    personId: number,
    mediaType: TmdbFilmographyMediaType = 'all',
  ): Promise<CatalogItem[]> {
    return getCached(`tmdb:person-filmography:${personId}:${mediaType}`, async () => {
      // If mediaType is 'all', combine both movie and tv credits.
      let allCredits: Array<Record<string, unknown>> = [];

      if (mediaType === 'all') {
        // Fetch both movie and tv credits
        const [movieData, tvData] = await Promise.all([
          requestTmdb<{
            cast: Array<Record<string, unknown>>;
          }>(`/person/${personId}/movie_credits`, {
            language: 'en-US',
          }),
          requestTmdb<{
            cast: Array<Record<string, unknown>>;
          }>(`/person/${personId}/tv_credits`, {
            language: 'en-US',
          }),
        ]);

        allCredits = [
          ...(movieData.cast || []).map((item) => ({
            ...item,
            media_type: 'movie',
          })),
          ...(tvData.cast || []).map((item) => ({
            ...item,
            media_type: 'tv',
          })),
        ];
      } else {
        const data = await requestTmdb<{
          cast: Array<Record<string, unknown>>;
        }>(`/person/${personId}/${mediaType}_credits`, {
          language: 'en-US',
        });

        allCredits = (data.cast || []).map((item) => ({
          ...item,
          media_type: mediaType,
        }));
      }

      // Normalize items with their media types
      const normalized = allCredits
        .map((item) => {
          const itemMediaType =
            (item.media_type as 'movie' | 'tv' | undefined) ?? 'movie';
          return normalizeItem(item, itemMediaType);
        })
        .sort((a, b) => {
          const aDate = a.release_date ? new Date(a.release_date).getTime() : 0;
          const bDate = b.release_date ? new Date(b.release_date).getTime() : 0;
          return bDate - aDate;
        })
        .slice(0, 200);

      return normalized;
    });
  }

  async getTvSeasonDetails(
    tmdbId: number,
    seasonNumber: number,
  ): Promise<{
    id: number;
    name: string;
    overview: string;
    season_number: number;
    air_date: string | null;
    vote_average: number;
    poster_path: string | null;
    episodes: Array<{
      id: number;
      episode_number: number;
      name: string;
      overview: string;
      air_date: string | null;
      vote_average: number;
      still_path: string | null;
      runtime: number | null;
    }>;
  }> {
    return getCached(`tmdb:tv-season:${tmdbId}:${seasonNumber}`, async () => {
      const data = await requestTmdb<Record<string, unknown>>(
        `/tv/${tmdbId}/season/${seasonNumber}`,
        {
          language: 'en-US',
        },
      );

      const episodesRaw = Array.isArray(data.episodes)
        ? (data.episodes as Array<Record<string, unknown>>)
        : [];

      const episodes = episodesRaw
        .map((episode) => ({
          id: Number(episode.id ?? 0),
          episode_number: Number(episode.episode_number ?? 0),
          name: String(episode.name ?? 'Untitled Episode'),
          overview: String(episode.overview ?? ''),
          air_date: episode.air_date ? String(episode.air_date) : null,
          vote_average: Number(episode.vote_average ?? 0),
          still_path: withImage(episode.still_path, 'w500'),
          runtime:
            typeof episode.runtime === 'number' ? Number(episode.runtime) : null,
        }))
        .sort((a, b) => a.episode_number - b.episode_number);

      return {
        id: Number(data.id ?? 0),
        name: String(data.name ?? `Season ${seasonNumber}`),
        overview: String(data.overview ?? ''),
        season_number: Number(data.season_number ?? seasonNumber),
        air_date: data.air_date ? String(data.air_date) : null,
        vote_average: Number(data.vote_average ?? 0),
        poster_path: withImage(data.poster_path, 'w500'),
        episodes,
      };
    });
  }
}

export const tmdbService = new TMDBService();
