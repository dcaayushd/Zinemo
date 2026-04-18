from __future__ import annotations

import random
from typing import Optional


class RecommendationExplainer:
    TEMPLATES = {
        "lightfm": [
            "Because people who loved {seed} also loved this",
            "Fans of {seed} consistently rate this highly",
            "Popular among viewers with your taste in {genre}",
        ],
        "als": [
            "Trending among viewers who watched {seed}",
            "People with similar watchlists keep coming back to this",
            "A favourite among {genre} enthusiasts like you",
        ],
        "content": [
            "Similar themes to {seed}",
            "Same {genre} energy as {seed}",
            "Directed with the same tone as {seed}",
            "If you liked the world of {seed}, you'll feel at home here",
        ],
        "popularity": [
            "Everyone's talking about this right now",
            "One of the most-watched {genre} titles this month",
            "Critically acclaimed and trending in your region",
        ],
        "cold_start": [
            "Strong early fit for your onboarding taste profile",
            "A clean cold-start pick for your first few logs",
            "Trending now in the genres you selected",
        ],
    }

    def generate(
        self,
        algorithm: str,
        seed_title: Optional[str] = None,
        genre: Optional[str] = None,
    ) -> str:
        templates = self.TEMPLATES.get(algorithm, self.TEMPLATES["content"])
        template = random.choice(templates)
        return template.format(
            seed=seed_title or "your recent watches",
            genre=genre or "this genre",
        )
