"""Tests for app-level Supabase storage client behavior."""

from __future__ import annotations

from types import SimpleNamespace

import app.storage.supabase_client as supabase_client_module


class FakeTable:
    def __init__(self):
        self.upsert_call: tuple[list[dict], dict] | None = None

    def upsert(self, payload: list[dict], **kwargs):
        self.upsert_call = (payload, kwargs)
        return self

    def execute(self):
        return SimpleNamespace(data=[])


class FakeClient:
    def __init__(self):
        self.table_name: str | None = None
        self.table_obj = FakeTable()

    def table(self, name: str):
        self.table_name = name
        return self.table_obj


def build_client(monkeypatch) -> tuple[supabase_client_module.SupabaseClient, FakeClient]:
    fake_client = FakeClient()
    monkeypatch.setattr(
        supabase_client_module,
        "get_settings",
        lambda: SimpleNamespace(
            supabase_url="https://example.supabase.co",
            supabase_service_key="service-key",
        ),
    )
    monkeypatch.setattr(
        supabase_client_module,
        "create_client",
        lambda _url, _key: fake_client,
    )
    return supabase_client_module.SupabaseClient(), fake_client


def test_write_recommendations_uses_explicit_conflict_target(monkeypatch):
    client, fake_client = build_client(monkeypatch)

    client.write_recommendations(
        user_id="user-1",
        recommendations=[
            {
                "tmdb_id": 101,
                "media_type": "movie",
                "score": 0.88,
                "reason": "Strong match",
                "algorithm": "content",
            }
        ],
        genre_filter="Action",
    )

    assert fake_client.table_name == "recommendations"
    assert fake_client.table_obj.upsert_call is not None

    payload, kwargs = fake_client.table_obj.upsert_call
    assert payload[0]["user_id"] == "user-1"
    assert kwargs["on_conflict"] == "user_id,tmdb_id"


def test_write_recommendations_skips_empty_payload(monkeypatch):
    client, fake_client = build_client(monkeypatch)

    client.write_recommendations(user_id="user-1", recommendations=[])

    assert fake_client.table_obj.upsert_call is None
