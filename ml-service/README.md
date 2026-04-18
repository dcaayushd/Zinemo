# ML Service

LightFM hybrid recommendation engine service for Zinemo.

## Canonical Structure

- Canonical runtime and training code lives under `app/`.
- CI coverage is measured against `app/`.

## Features

- LightFM + ALS + content-based hybrid recommendations
- Cold-start handling when user history is sparse
- Scheduled and on-demand model retraining
- FastAPI endpoints consumed by the Node backend
- Modular router structure under `app/routers` (`recommendations`, `training`, `health`)

## Quick Start

### 1) Configure Environment

Create an `.env` file in `ml-service/`:

```env
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_SERVICE_KEY=your-service-role-key
MODEL_DIR=/tmp/zinemo_models
NODE_API_URL=http://localhost:3000
RECOMMENDATION_MODE=scratch
PORT=8000
```

### Environment Variables

Required environment variables:

- `SUPABASE_URL`
- `SUPABASE_SERVICE_KEY`
- `MODEL_DIR` (optional, defaults to `/tmp/zinemo_models`)
- `NODE_API_URL` (optional, defaults to `*`)
- `PORT` (optional, defaults to `8000`)

### Install Dependencies

```bash
pip install -r requirements.txt
```

### Python Version Requirement

Use Python 3.11 for this service. `lightfm` can fail to build on newer Python versions.

If you accidentally created a venv with another interpreter, recreate it:

```bash
rm -rf .venv
python3.11 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

### Run Service (Local)

```bash
.venv/bin/python -m uvicorn --env-file .env app.main:app --host 0.0.0.0 --port 8000
```

On startup, the service will:

1. Try loading the latest saved model artifacts from `MODEL_DIR`.
2. If missing, run initial training.
3. If there is no interaction data yet, start in cold-start bootstrap mode.
4. Start APScheduler and retrain every 6 hours.

### Run With Docker

```bash
docker build -t zinemo-ml .
docker run --rm -p 8000:8000 \
	-e SUPABASE_URL="$SUPABASE_URL" \
	-e SUPABASE_SERVICE_KEY="$SUPABASE_SERVICE_KEY" \
	-e MODEL_DIR=/tmp/zinemo_models \
	-e NODE_API_URL=http://localhost:3000 \
	-e RECOMMENDATION_MODE=scratch \
	zinemo-ml
```

### Verify Endpoints

```bash
curl http://localhost:8000/health

curl "http://localhost:8000/recommend/<supabase_user_uuid>?limit=20"

curl "http://localhost:8000/recommend/<supabase_user_uuid>?genre_filter=Action&exclude_tmdb_ids=550&exclude_tmdb_ids=680"

curl "http://localhost:8000/similar/550?limit=20"

curl -X POST http://localhost:8000/train
```

## Development Validation

Run tests:

```bash
pytest -q
```

## API Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/health` | GET | Detailed health check |
| `/recommend/{user_id}` | GET | Get recommendations for a user (`genre_filter`, `limit`, repeated `exclude_tmdb_ids`) |
| `/similar/{tmdb_id}` | GET | Get content-similar items |
| `/train` | POST | Trigger model training |

Periodic retraining is handled internally by APScheduler in the canonical `app/` stack.

## Model Architecture

The service uses LightFM for hybrid recommendations:

- **User embeddings**: Learn from content preferences
- **Item embeddings**: Learn from features
- **Collaborative filtering**: Factorization Machine component

## License

MIT
