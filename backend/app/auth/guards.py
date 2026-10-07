from fastapi import Depends
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
import redis.asyncio as aioredis

from app.auth.jwt import CLIENT_ADMIN, CLIENT_APP, decode_token, token_client
from app.core.database import get_db
from app.core.redis import get_redis
from app.core.exceptions import (
    AccountDisabledError, InsufficientRoleError, InvalidTokenError, UseAdminPanelError,
)
from app.models.user import User

bearer_scheme = HTTPBearer(auto_error=True)


# ── Base user extraction ──────────────────────────────────────────────────────
async def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(bearer_scheme),
    redis: aioredis.Redis = Depends(get_redis),
    db: AsyncSession = Depends(get_db),
) -> dict:
    """
    Extract and validate the JWT from the Authorization header,
    and make sure the account still exists and is active.
    Returns the decoded payload dict: {sub, role, type, jti, ...}

    Usage:
        @router.get("/me")
        async def me(user: dict = Depends(get_current_user)):
            return {"user_id": user["sub"], "role": user["role"]}
    """
    user = await decode_token(credentials.credentials, redis, expected_type="access")
    # The public API never serves the admin panel or admin accounts
    if token_client(user) != CLIENT_APP or user.get("role") == "admin":
        raise UseAdminPanelError()
    await _require_active(user["sub"], db)
    return user


async def _require_active(user_id: str, db: AsyncSession) -> None:
    is_active = (await db.execute(
        select(User.is_active).where(User.id == user_id)
    )).scalar_one_or_none()
    if is_active is None:
        raise InvalidTokenError()
    if not is_active:
        raise AccountDisabledError()


# ── Admin panel ───────────────────────────────────────────────────────────────
async def get_current_admin(
    credentials: HTTPAuthorizationCredentials = Depends(bearer_scheme),
    redis: aioredis.Redis = Depends(get_redis),
    db: AsyncSession = Depends(get_db),
) -> dict:
    """
    Admin routes only accept tokens issued by the admin login (/admin/auth),
    so an admin role inside a public-app token is not enough.
    """
    user = await decode_token(credentials.credentials, redis, expected_type="access")
    if token_client(user) != CLIENT_ADMIN or user.get("role") != "admin":
        raise InsufficientRoleError("admin")
    await _require_active(user["sub"], db)
    return user


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
    async def guard(user: dict = Depends(get_current_user)) -> dict:
        if user["role"] not in roles:
            raise InsufficientRoleError(list(roles))
        return user

    return guard


# ── Convenience shorthands ────────────────────────────────────────────────────
CurrentUser     = Depends(get_current_user)
RequireCustomer = require_role("customer")
RequireMerchant = require_role("merchant")
RequireCourier  = require_role("courier")
RequireAdmin    = get_current_admin

# Shared routes — e.g. viewing order detail
RequireOrderParty = require_role("customer", "merchant", "courier")


