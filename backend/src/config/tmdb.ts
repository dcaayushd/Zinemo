export const TMDB_API_BASE_URL = 'https://api.themoviedb.org/3';
export const TMDB_IMAGE_BASE_URL = 'https://image.tmdb.org/t/p';
export const TMDB_ACCESS_TOKEN = process.env.TMDB_ACCESS_TOKEN;
export const TMDB_API_KEY = process.env.TMDB_API_KEY;

export function assertTmdbConfigured(): void {
  if (!TMDB_ACCESS_TOKEN && !TMDB_API_KEY) {
    throw new Error(
      'TMDB credentials missing. Set TMDB_ACCESS_TOKEN or TMDB_API_KEY in the backend environment.',
    );
  }
}
