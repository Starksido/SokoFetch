from fastapi import Depends
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
import redis.asyncio as aioredis

from app.auth.jwt import decode_token
from app.core.redis import get_redis
from app.core.exceptions import InsufficientRoleError

bearer_scheme = HTTPBearer(auto_error=True)


# ── Base user extraction ──────────────────────────────────────────────────────
async def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(bearer_scheme),
    redis: aioredis.Redis = Depends(get_redis),
) -> dict:
    """
    Extract and validate the JWT from the Authorization header.
    Returns the decoded payload dict: {sub, role, type, jti, ...}

    Usage:
        @router.get("/me")
        async def me(user: dict = Depends(get_current_user)):
            return {"user_id": user["sub"], "role": user["role"]}
    """
    return await decode_token(credentials.credentials, redis, expected_type="access")


# ── Role enforcement factory ──────────────────────────────────────────────────
def require_role(*roles: str):
    """
    Returns a FastAPI Depends() that enforces role membership.

    Usage:
        @router.get("/merchant/orders")
        async def get_orders(merchant = Depends(require_role("merchant"))):
            ...

        @router.put("/orders/{id}/status")
        async def update_status(user = Depends(require_role("merchant", "courier"))):
            ...
    """
    async def guard(
        credentials: HTTPAuthorizationCredentials = Depends(bearer_scheme),
        redis: aioredis.Redis = Depends(get_redis),
    ) -> dict:
        user = await decode_token(credentials.credentials, redis, expected_type="access")
        if user["role"] not in roles:
            raise InsufficientRoleError(list(roles))
        return user

    return guard


# ── Convenience shorthands ────────────────────────────────────────────────────
CurrentUser     = Depends(get_current_user)
RequireCustomer = require_role("customer")
RequireMerchant = require_role("merchant")
RequireCourier  = require_role("courier")
RequireAdmin    = require_role("admin")

# Shared routes — e.g. viewing order detail
RequireOrderParty = require_role("customer", "merchant", "courier")


