"""
Recombee Integration for Mode B
Content-based recommendation using recombee Python SDK
"""
import logging
from typing import List, Dict, Optional
from recombee_python import Client as RecombeeClient

logger = logging.getLogger(__name__)


class RecombeeClient:
    """
    Recombee recommendation engine wrapper.

    Mode B: Content-based recommendations using machine learning features
    """

    def __init__(
        self,
        app_id: str,
        app_token: str,
        host: str = "https://api.recombee.io",
    ):
        """Initialize Recombee client."""
        self.client = RecombeeClient(host=host, app_id=app_id, app_token=app_token)
        self.app_id = app_id
        self.app_token = app_token
        self._users_cache = {}
        self._items_cache = {}

    def get_recommendations(
        self,
        user_id: str,
        num_recommendations: int = 10,
        exclude_currently_viewed: List[str] = None,
    ) -> List[Dict]:
        """
        Get recommendations for a user.

        Args:
            user_id: User identifier in our system
            num_recommendations: Number of recommendations to return
            exclude_currently_viewed: Item IDs to exclude

        Returns:
            List of recommended items with metadata
        """
        try:
            # Ensure user exists
            self._ensure_user(user_id)

            # Get recommendations from Recombee
            recommendations = self.client.get_recommendations(
                user_id=user_id,
                num_recommendations=num_recommendations,
            )

            # Format results
            results = []
            for rec in recommendations:
                item = self._get_item_by_id(rec.get("item_id"))
                if item:
                    results.append({
                        "item": item,
                        "relevance_score": rec.get("relevance_score", 0),
                    })

            return results

        except Exception as e:
            logger.error(f"Failed to get recommendations for user {user_id}: {e}")
            return []

    def get_recommendations_for_new_user(
        self,
        user_id: str,
        context_features: Dict,
        num_recommendations: int = 10,
    ) -> List[Dict]:
        """
        Get cold-start recommendations for new users.

        Args:
            user_id: User identifier
            context_features: User context features (age, location, preferences)
            num_recommendations: Number of recommendations

        Returns:
            List of recommended items
        """
        try:
            # Create new user with context features
            self.client.create_user(
                user_id=user_id,
                features=[
                    {"feature_name": "age", "value": context_features.get("age", 25)},
                    {"feature_name": "location", "value": context_features.get("location", "global")},
                    {"feature_name": "preferences", "value": context_features.get("preferences", "")},
                ],
            )

            # Get recommendations
            recommendations = self.client.get_recommendations(
                user_id=user_id,
                num_recommendations=num_recommendations,
            )

            results = []
            for rec in recommendations:
                item = self._get_item_by_id(rec.get("item_id"))
                if item:
                    results.append({
                        "item": item,
                        "relevance_score": rec.get("relevance_score", 0),
                    })

            return results

        except Exception as e:
            logger.error(f"Failed to get cold-start recommendations for {user_id}: {e}")
            return []

    def add_interactions(
        self,
        user_id: str,
        interactions: List[Dict],
    ) -> bool:
        """
        Add user interactions to update recommendations.

        Args:
            user_id: User identifier
            interactions: List of {item_id, type, relevance} interactions

        Returns:
            Success status
        """
        try:
            for interaction in interactions:
                self.client.add_interaction(
                    user_id=user_id,
                    item_id=interaction["item_id"],
                    type=interaction.get("type", "watch"),
                    relevance=interaction.get("relevance", 1),
                )

            logger.info(f"Added {len(interactions)} interactions for user {user_id}")
            return True

        except Exception as e:
            logger.error(f"Failed to add interactions for {user_id}: {e}")
            return False

    def rate_item(self, user_id: str, item_id: str, rating: float):
        """Rate an item."""
        try:
            self.client.add_interaction(
                user_id=user_id,
                item_id=item_id,
                type="rate",
                relevance=rating,
            )
            logger.info(f"Rated item {item_id} with rating {rating}")
        except Exception as e:
            logger.error(f"Failed to rate item {item_id}: {e}")

    def remove_item(self, user_id: str, item_id: str):
        """Remove an item from user's view history."""
        try:
            self.client.remove_interaction(
                user_id=user_id,
                item_id=item_id,
            )
            logger.info(f"Removed item {item_id} from user {user_id}")
        except Exception as e:
            logger.error(f"Failed to remove item {item_id}: {e}")

    def _ensure_user(self, user_id: str):
        """Ensure user exists in Recombee."""
        try:
            if user_id not in self._users_cache:
                # Check if user exists
                users = self.client.get_users(limit=1)
                user_ids = [u["id"] for u in users]

                if user_id not in user_ids:
                    # Create new user
                    self.client.create_user(user_id=user_id)
                    self._users_cache[user_id] = True
                    logger.info(f"Created user {user_id}")

            return True
        except Exception as e:
            logger.error(f"Failed to ensure user {user_id}: {e}")
            return False

    def _get_item_by_id(self, item_id: str) -> Optional[Dict]:
        """Get item details from cache or Supabase."""
        if item_id in self._items_cache:
            return self._items_cache[item_id]

        try:
            # Fetch from Supabase if not in cache
            from src.db import SupabaseClient
            supabase = SupabaseClient()
            item = supabase.get_content_by_tmdb_id(int(item_id))

            if item:
                self._items_cache[item_id] = item
                return item
        except Exception as e:
            logger.error(f"Failed to fetch item {item_id}: {e}")

        return None

    def update_user_preferences(self, user_id: str, preferences: Dict):
        """Update user preferences."""
        try:
            features = [
                {"feature_name": "preferred_genres", "value": preferences.get("preferred_genres", "")},
                {"feature_name": "preferred_content_types", "value": preferences.get("preferred_content_types", "")},
                {"feature_name": "max_runtime", "value": preferences.get("max_runtime", 120)},
                {"feature_name": "min_rating", "value": preferences.get("min_rating", 6.0)},
            ]

            self.client.add_interaction(
                user_id=user_id,
                item_id="__metadata",
                type="update_metadata",
                relevance=1,
                extra_data=features,
            )

            logger.info(f"Updated preferences for user {user_id}")
            return True
        except Exception as e:
            logger.error(f"Failed to update preferences for {user_id}: {e}")
            return False

    def search_items(
        self,
        query: str,
        limit: int = 10,
    ) -> List[Dict]:
        """Search for items."""
        try:
            from src.db import SupabaseClient
            supabase = SupabaseClient()
            return supabase.search_content(query, limit=limit)
        except Exception as e:
            logger.error(f"Failed to search items: {e}")
            return []

    def get_trending_items(self, limit: int = 10) -> List[Dict]:
        """Get trending items based on popularity."""
        try:
            from src.db import SupabaseClient
            supabase = SupabaseClient()
            events = supabase.get_content_access_events()

            if events:
                counts = {}
                for event in events[-1000:]:
                    item_id = event.get("content_accessed_item_id")
                    if item_id:
                        counts[item_id] = counts.get(item_id, 0) + 1

                trending = []
                for item_id, count in sorted(counts.items(), key=lambda x: x[1], reverse=True)[:limit]:
                    item = supabase.get_content_by_tmdb_id(int(item_id))
                    if item:
                        trending.append({
                            "item": item,
                            "popularity": count,
                        })

                return trending
        except Exception as e:
            logger.error(f"Failed to get trending items: {e}")

        return []

    def batch_add_interactions(
        self,
        user_id: str,
        interactions: List[Dict],
    ) -> bool:
        """Batch add multiple interactions."""
        try:
            for interaction in interactions:
                self.add_interactions(
                    user_id=user_id,
                    interactions=[interaction],
                )
            return True
        except Exception as e:
            logger.error(f"Failed to batch add interactions: {e}")
            return False

    def get_user_history(self, user_id: str) -> List[Dict]:
        """Get user's watch history."""
        try:
            from src.db import SupabaseClient
            supabase = SupabaseClient()
            events = supabase.get_content_access_events()

            user_events = [e for e in events if e.get("user_id") == user_id]
            return user_events[-50:]
        except Exception as e:
            logger.error(f"Failed to get user history for {user_id}: {e}")
            return []

    def get_similar_items(self, item_id: str, limit: int = 5) -> List[Dict]:
        """Get similar items to a given item."""
        try:
            # Get item genres
            from src.db import SupabaseClient
            supabase = SupabaseClient()
            item = supabase.get_content_by_tmdb_id(int(item_id))

            if item:
                similar = []
                genre_ids = item.get("genre_ids", [])

                for genre_id in genre_ids[:3]:
                    genre_items = supabase.search_content_by_genre(genre_id, limit=limit)
                    for other in genre_items:
                        if other["id"] != item_id and other["id"] not in [s["id"] for s in similar]:
                            similar.append({
                                "item": other,
                                "similarity": 0.7,
                            })

                return similar[:limit]
        except Exception as e:
            logger.error(f"Failed to get similar items: {e}")
            return []
