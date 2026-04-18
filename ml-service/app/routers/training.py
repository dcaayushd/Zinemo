from __future__ import annotations

from fastapi import APIRouter, BackgroundTasks

router = APIRouter()


async def _dispatch_training_from_main() -> None:
    # Import lazily to avoid circular imports during app bootstrap.
    from app.main import _run_training

    await _run_training()


@router.post("/train")
async def trigger_training(background_tasks: BackgroundTasks):
    background_tasks.add_task(_dispatch_training_from_main)
    return {"status": "training_started"}
