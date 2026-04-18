"""Startup safety tests for app.main."""

from __future__ import annotations

import asyncio
import sys
import types


class _DummyScheduler:
    def add_job(self, *args, **kwargs):
        return None

    def start(self):
        return None


class _DummyIntervalTrigger:
    def __init__(self, *args, **kwargs):
        pass


sys.modules.setdefault("apscheduler", types.ModuleType("apscheduler"))
sys.modules.setdefault("apscheduler.schedulers", types.ModuleType("apscheduler.schedulers"))
sys.modules.setdefault("apscheduler.triggers", types.ModuleType("apscheduler.triggers"))

asyncio_scheduler_module = types.ModuleType("apscheduler.schedulers.asyncio")
asyncio_scheduler_module.AsyncIOScheduler = _DummyScheduler
sys.modules.setdefault("apscheduler.schedulers.asyncio", asyncio_scheduler_module)

interval_trigger_module = types.ModuleType("apscheduler.triggers.interval")
interval_trigger_module.IntervalTrigger = _DummyIntervalTrigger
sys.modules.setdefault("apscheduler.triggers.interval", interval_trigger_module)

trainer_module = types.ModuleType("app.training.trainer")


class _DummyTrainingPipeline:
    def run(self):
        return None


trainer_module.TrainingPipeline = _DummyTrainingPipeline
sys.modules.setdefault("app.training.trainer", trainer_module)

import app.main as main_module


def test_initialize_recommender_bootstraps_when_dataset_is_empty(monkeypatch):
    sentinel_recommender = object()

    class DummyPipeline:
        def run(self):
            return None

    monkeypatch.setattr(main_module, "TrainingPipeline", DummyPipeline)
    monkeypatch.setattr(
        main_module.Recommender,
        "load_from_disk",
        staticmethod(lambda: (_ for _ in ()).throw(FileNotFoundError())),
    )
    monkeypatch.setattr(
        main_module.Recommender,
        "bootstrap_without_models",
        staticmethod(lambda: sentinel_recommender),
    )

    async def fake_to_thread(_func, *args, **kwargs):
        raise ValueError("No interaction data available for training")

    monkeypatch.setattr(main_module.asyncio, "to_thread", fake_to_thread)

    result = asyncio.run(main_module._initialize_recommender())

    assert result is sentinel_recommender
