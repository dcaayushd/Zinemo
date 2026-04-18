# Zinemo Backend

Node.js backend service for Zinemo platform with TMDB integration.

## Features

- **TMDB Integration**: Proxy endpoints with caching for movies, TV shows, and more
- **Authentication**: Supabase Auth with JWT tokens
- **Caching**: Redis + LRU cache with 5-minute TTL
- **Tracking**: Content access tracking with Supabase
- **Recommendation Modes**:
	- **Mode A**: TMDB `/recommendations` + `/similar` driven personalization
	- **Mode B**: Hybrid personalization (preferences + pgvector + TMDB blending)
	- **Legacy scratch**: Python ML microservice integration

## Setup

```bash
# Install dependencies
npm install

# Configure environment
cp .env.example .env
# Edit .env with your credentials

# Run development server
npm run dev

# Run tests
npm test
```

## API Endpoints

### Content (Mode A)
- `GET /api/content/trending` - Get trending content
- `GET /api/content/top-rated` - Get top-rated movies
- `GET /api/content/genres` - Get genre list
- `GET /api/content/genre/:id` - Get content by genre
- `GET /api/content/search` - Search content
- `GET /api/content/detail/:id` - Get content detail
- `GET /api/content/similar/:id` - Get similar content

### Recommendations
- `GET /api/recommendations/foryou` - Personalized feed (uses active recommendation mode)
- `GET /api/recommendations/similar/:tmdbId` - Similar titles for detail page
- `POST /api/recommendations/retrain` - Retraining trigger (legacy scratch mode only)

### Profile
- `GET /api/profile` - Get current user profile
- `PUT /api/profile` - Update profile

### Auth
- `POST /api/auth/create-profile` - Create profile on login

## Deployment

### Local Development

```bash
npm run dev
```

### Docker

```bash
docker build -t zinemo-backend .
docker run -p 3000:3000 zinemo-backend
```

### Render.com

See the main project README for Render.com deployment instructions.

## Architecture

- **Express** for HTTP server
- **Supabase** for database and auth
- **Redis** + **node-cached** for LRU caching
- **node-cached** for local LRU cache (fallback)
- **TMDB API** for content data

## Caching Strategy

- Local LRU cache (node-cached) with file-based storage
- Redis-backed cache for distributed deployments
- 5-minute TTL for most content endpoints
- Max 500 entries to comply with spec
