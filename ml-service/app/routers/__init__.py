from app.routers.health import router as health_router
from app.routers.recommendations import router as recommendations_router
from app.routers.training import router as training_router

__all__ = ["recommendations_router", "training_router", "health_router"]
