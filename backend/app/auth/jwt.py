import secrets
import logging
from datetime import datetime, timedelta, timezone

from jose import jwt, JWTError
import redis.asyncio as aioredis

from app.core.config import settings
from app.core.exceptions import InvalidTokenError, RevokedTokenError

logger = logging.getLogger("alphabet.auth.jwt")

ROLES = {"customer", "merchant", "courier", "admin"}


# ── Token creation ────────────────────────────────────────────────────────────
def create_access_token(user_id: str, role: str) -> str:
    """30-minute access token with role claim."""
    return _build_token(user_id, role, "access", settings.ACCESS_TOKEN_EXPIRE_MINUTES)


def create_refresh_token(user_id: str, role: str) -> str:
    """30-day refresh token."""
    return _build_token(
        user_id, role, "refresh",
        settings.REFRESH_TOKEN_EXPIRE_DAYS * 24 * 60
    )


def _build_token(user_id: str, role: str, token_type: str, expire_minutes: int) -> str:
    if role not in ROLES:
        raise ValueError(f"Invalid role: {role}")

    now = datetime.now(timezone.utc)
    payload = {
        "sub":  user_id,
        "role": role,
        "type": token_type,
        "iat":  now,
        "exp":  now + timedelta(minutes=expire_minutes),
        "jti":  secrets.token_urlsafe(16),   # Unique token ID for revocation
    }
    return jwt.encode(payload, settings.JWT_SECRET, algorithm=settings.JWT_ALGORITHM)


# ── Token decoding ────────────────────────────────────────────────────────────
async def decode_token(
    token: str,
    redis: aioredis.Redis,
    expected_type: str = "access",
) -> dict:
    """
    Decode and validate a JWT.
    Checks: signature, expiry, token type, revocation list.
    """
    try:
        payload = jwt.decode(
            token,
            settings.JWT_SECRET,
            algorithms=[settings.JWT_ALGORITHM],
        )
    except JWTError as exc:
        logger.warning("JWT decode failed: %s", exc)
        raise InvalidTokenError()

    # Verify token type
    if payload.get("type") != expected_type:
        raise InvalidTokenError()

    # Check revocation list
    jti = payload.get("jti")
    if jti and await redis.get(f"revoked_token:{jti}"):
        raise RevokedTokenError()

    # Tokens issued at or before a session-wide revocation are dead
    cutoff = await redis.get(_valid_after_key(payload.get("sub", "")))
    if cutoff and int(payload.get("iat", 0)) <= int(cutoff):
        raise RevokedTokenError()

    return payload


def _valid_after_key(user_id: str) -> str:
    return f"tokens_valid_after:{user_id}"


async def revoke_all_user_tokens(user_id: str, redis: aioredis.Redis) -> None:
    """Invalidate every token issued to this user up to now."""
    now = int(datetime.now(timezone.utc).timestamp())
    ttl = settings.REFRESH_TOKEN_EXPIRE_DAYS * 24 * 3600
    await redis.setex(_valid_after_key(user_id), ttl, str(now))
    logger.warning("All tokens revoked | user=%s", user_id)


async def claim_refresh_token(payload: dict, redis: aioredis.Redis) -> bool:
    """
    Mark a refresh token as used. Returns False if it was already used,
    which means the token was replayed (stolen or duplicated).
    """
    remaining = int(payload["exp"]) - int(datetime.now(timezone.utc).timestamp())
    return bool(await redis.set(
        f"used_refresh:{payload['jti']}", "1", nx=True, ex=max(remaining, 1),
    ))


# ── Token revocation ──────────────────────────────────────────────────────────
async def revoke_token(token: str, redis: aioredis.Redis) -> None:
    """
    Add token JTI to Redis revocation set.
    TTL is set to remaining token lifetime so Redis auto-cleans.
    """
    try:
        # Decode without checking revocation (we're revoking it)
        payload = jwt.decode(
            token,
            settings.JWT_SECRET,
            algorithms=[settings.JWT_ALGORITHM],
        )
    except JWTError:
        return  # Already invalid — nothing to revoke

    jti = payload.get("jti")
    exp = payload.get("exp")
    if not jti or not exp:
        return

    # Calculate remaining lifetime
    remaining = exp - int(datetime.now(timezone.utc).timestamp())
    if remaining > 0:
        await redis.setex(f"revoked_token:{jti}", remaining, "1")
        logger.info("Token revoked | jti=%s | user=%s", jti, payload.get("sub"))


# ── Token pair helper ─────────────────────────────────────────────────────────
def create_token_pair(user_id: str, role: str) -> dict:
    """Create both access and refresh tokens in one call."""
    return {
        "access_token":  create_access_token(user_id, role),
        "refresh_token": create_refresh_token(user_id, role),
        "token_type":    "bearer",
    }
