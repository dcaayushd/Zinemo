from __future__ import annotations

import asyncio

from apscheduler.schedulers.asyncio import AsyncIOScheduler
from apscheduler.triggers.interval import IntervalTrigger


def start_scheduler(pipeline) -> AsyncIOScheduler:
    scheduler = AsyncIOScheduler()
    scheduler.add_job(
        func=lambda: asyncio.create_task(asyncio.to_thread(pipeline.run)),
        trigger=IntervalTrigger(hours=6),
        id="retrain_models",
        name="Retrain recommendation models",
        replace_existing=True,
    )
    scheduler.start()
    print("Scheduler started — models retrain every 6 hours")
    return scheduler
