import redis.asyncio as aioredis
from app.core.config import settings

# ── Async Redis client ────────────────────────────────────────────────────────
# Single connection pool shared across the app
redis_client: aioredis.Redis = aioredis.from_url(
    settings.REDIS_URL,
    encoding="utf-8",
    decode_responses=True,     # Always return str, not bytes
    max_connections=20,
)


async def get_redis() -> aioredis.Redis:
    """FastAPI dependency — Depends(get_redis)"""
    return redis_client


async def close_redis():
    """Call on app shutdown."""
    await redis_client.aclose()
