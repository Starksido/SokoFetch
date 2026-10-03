"""
Delivery code
=============
A 4-digit code created when an order is paid. The customer reads it from the
app and gives it to the courier at handover; the courier must submit it as
proof of delivery. Wrong guesses are rate limited per order because 4 digits
are otherwise easy to brute-force.
"""
import secrets

import redis.asyncio as aioredis

from app.core.exceptions import RateLimitError, SokoFetchException

MAX_WRONG_ATTEMPTS = 5
LOCKOUT_SECONDS    = 15 * 60


def new_delivery_code() -> str:
    return f"{secrets.randbelow(10_000):04d}"


def _fail_key(order_id: str) -> str:
    return f"delivery_code_fail:{order_id}"


async def check_delivery_code(
    order_id: str,
    expected: str | None,
    submitted: str,
    redis: aioredis.Redis,
) -> None:
    """Raise unless `submitted` matches the order's code and the order is not locked out."""
    key   = _fail_key(order_id)
    fails = int(await redis.get(key) or 0)
    if fails >= MAX_WRONG_ATTEMPTS:
        raise RateLimitError("Too many incorrect delivery codes. Try again in 15 minutes.")

    if expected and secrets.compare_digest(expected, submitted.strip()):
        await redis.delete(key)
        return

    fails = await redis.incr(key)
    if fails == 1:
        await redis.expire(key, LOCKOUT_SECONDS)
    raise SokoFetchException(400, "INVALID_DELIVERY_CODE", "Delivery code is incorrect.")
