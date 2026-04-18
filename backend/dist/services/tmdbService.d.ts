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
    genres: Array<{
        id: number;
        name: string;
    }>;
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
export declare class TMDBService {
    getTrending(options?: {
        genre?: string;
        limit?: number;
        mediaType?: TmdbMediaType;
    }): Promise<CatalogItem[]>;
    getTopRated(limit?: number, mediaType?: TmdbMediaType): Promise<CatalogItem[]>;
    getNewReleases(limit?: number, mediaType?: TmdbMediaType): Promise<CatalogItem[]>;
    getGenres(): Promise<Array<{
        id: number;
        name: string;
    }>>;
    discoverByGenre(genreName: string, limit?: number, mediaType?: TmdbMediaType): Promise<CatalogItem[]>;
    search(query: string, limit?: number): Promise<CatalogItem[]>;
    getDetails(tmdbId: number, mediaType?: TmdbMediaType): Promise<CatalogItem>;
    getSimilar(tmdbId: number, mediaType?: TmdbMediaType, limit?: number): Promise<CatalogItem[]>;
    getCredits(tmdbId: number, mediaType?: TmdbMediaType): Promise<{
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
    }>;
    getPerson(personId: number): Promise<{
        id: number;
        name: string;
        biography: string | null;
        birthday: string | null;
        deathday: string | null;
        place_of_birth: string | null;
        profile_path: string | null;
        popularity: number;
    }>;
    getPersonFilmography(personId: number, mediaType?: TmdbFilmographyMediaType): Promise<CatalogItem[]>;
    getTvSeasonDetails(tmdbId: number, seasonNumber: number): Promise<{
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
    }>;
}
export declare const tmdbService: TMDBService;
export {};
//# sourceMappingURL=tmdbService.d.ts.map