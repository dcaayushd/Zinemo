from __future__ import annotations

import asyncio
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.config import get_settings
from app.inference.recommender import Recommender
from app.routers import health_router, recommendations_router, training_router
from app.training.scheduler import start_scheduler
from app.training.trainer import TrainingPipeline

settings = get_settings()

_recommender: Recommender | None = None
_scheduler = None


async def _initialize_recommender() -> Recommender:
    pipeline = TrainingPipeline()

    try:
        recommender = Recommender.load_from_disk()
        print("Loaded existing recommendation models from disk")
        return recommender
    except FileNotFoundError:
        print("No saved models found — running initial training")

    try:
        await asyncio.to_thread(pipeline.run)
        return Recommender.load_from_disk()
    except ValueError as error:
        if "No interaction data available for training" in str(error):
            print("No interaction data yet — starting in cold-start bootstrap mode")
            return Recommender.bootstrap_without_models()
        raise
    except Exception as error:
        print(f"Initial training failed, using cold-start bootstrap mode: {error}")
        return Recommender.bootstrap_without_models()


@asynccontextmanager
async def lifespan(app_obj: FastAPI):
    global _recommender, _scheduler
    _recommender = await _initialize_recommender()
    app_obj.state.recommender = _recommender

    pipeline = TrainingPipeline()
    _scheduler = start_scheduler(pipeline)

    try:
        yield
    finally:
        if _scheduler is not None and hasattr(_scheduler, "shutdown"):
            _scheduler.shutdown(wait=False)


async def _run_training() -> None:
    global _recommender
    pipeline = TrainingPipeline()
    try:
        await asyncio.to_thread(pipeline.run)
        _recommender = Recommender.load_from_disk()
        app.state.recommender = _recommender
    except ValueError as error:
        if "No interaction data available for training" in str(error):
            if _recommender is None:
                _recommender = Recommender.bootstrap_without_models()
                app.state.recommender = _recommender
            print("Skipped retraining because there is no interaction data yet")
            return
        raise


app = FastAPI(title="zinemo ML Service", version="1.0.0", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=[settings.node_api_url] if settings.node_api_url != "*" else ["*"],
    allow_methods=["GET", "POST"],
    allow_headers=["Authorization", "Content-Type"],
)


app.include_router(recommendations_router)
app.include_router(training_router)
app.include_router(health_router)
