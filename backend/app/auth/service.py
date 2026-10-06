import hashlib
import logging
from datetime import datetime, timezone

from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
import redis.asyncio as aioredis

from app.models.user import User, UserRole
from app.auth.otp import generate_otp, verify_otp, check_rate_limit, validate_phone
from app.auth.sms import send_otp_sms
from app.auth.jwt import (
    create_token_pair, decode_token, revoke_token,
    claim_refresh_token, revoke_all_user_tokens,
)
from app.schemas.auth import UserProfile, TokenResponse
from app.core.exceptions import AccountDisabledError, InvalidTokenError, RevokedTokenError

from app.core.config import settings
from app.core.exceptions import SokoFetchException
from app.schemas.auth import GoogleUserProfile, GoogleTokenResponse

logger = logging.getLogger("alphabet.auth.service")


def _phone_hash(phone: str) -> str:
    """Consistent SHA-256 hash used to look up users without decrypting."""
    return hashlib.sha256(phone.encode()).hexdigest()


# ── Request OTP ───────────────────────────────────────────────────────────────
async def request_otp(
    phone: str,
    role: str,
    db: AsyncSession,
    redis: aioredis.Redis,
) -> dict:
    """Generate OTP and send via SMS. Returns expiry info."""
    phone = validate_phone(phone)
    await check_rate_limit(phone, redis)

    code = await generate_otp(phone, role, redis)
    await send_otp_sms(phone, code)

    return {"message": "OTP sent successfully", "expires_in": 300}


# ── Verify OTP & issue tokens ─────────────────────────────────────────────────
async def verify_and_authenticate(
    phone: str,
    code: str,
    role: str,
    db: AsyncSession,
    redis: aioredis.Redis,
) -> TokenResponse:
    """
    Verify OTP, create user if first time, issue JWT pair.
    """
    phone = validate_phone(phone)
    await verify_otp(phone, code, role, redis)   # Raises InvalidOTPError on failure

    # Find or create user
    ph = _phone_hash(phone)
    result = await db.execute(select(User).where(User.phone_hash == ph))
    user: User | None = result.scalar_one_or_none()
    is_new = False

    if user is None:
        # First-time login — create account
        user = User(
            phone=phone,
            phone_hash=ph,
            role=UserRole(role),
            is_verified=True,
        )
        db.add(user)
        await db.flush()   # Get the generated UUID
        is_new = True
        logger.info("New user created | role=%s", role)
    else:
        # Existing user — verify role matches
        if user.role.value != role:
            # A courier trying to log in as a customer, etc. — reject
            from app.core.exceptions import InsufficientRoleError
            raise InsufficientRoleError(role)
        if not user.is_active:
            raise AccountDisabledError()

    # Update last login
    user.last_login = datetime.now(timezone.utc)
    await db.flush()

    # Issue tokens
    user_id = str(user.id)
    tokens = create_token_pair(user_id, role)

    profile = UserProfile(
        user_id=user_id,
        phone=phone,
        role=role,
        is_new=is_new,
        created_at=user.created_at.isoformat(),
    )

    return TokenResponse(**tokens, expires_in=1800, user=profile)


# ── Refresh access token ──────────────────────────────────────────────────────
async def refresh_access_token(
    refresh_token: str,
    db: AsyncSession,
    redis: aioredis.Redis,
) -> dict:
    """
    Rotate a refresh token: the old one is single-use and a new pair is issued.
    Replaying an already-used refresh token revokes the whole session.
    """
    payload = await decode_token(refresh_token, redis, expected_type="refresh")

    if not await claim_refresh_token(payload, redis):
        await revoke_all_user_tokens(payload["sub"], redis)
        raise RevokedTokenError()

    user: User | None = await db.get(User, payload["sub"])
    if user is None:
        raise InvalidTokenError()
    if not user.is_active:
        raise AccountDisabledError()

    # Role comes from the database, not the old token
    return create_token_pair(str(user.id), user.role.value)


# ── Logout ────────────────────────────────────────────────────────────────────
async def logout(
    access_token: str | None,
    refresh_token: str | None,
    redis: aioredis.Redis,
) -> None:
    """Revoke whichever tokens were supplied."""
    if access_token:
        await revoke_token(access_token, redis)
    if refresh_token:
        await revoke_token(refresh_token, redis)
    logger.info("User logged out")

# ── Google Sign-In: verify token, find-or-create user, issue tokens ─────────
async def verify_google_and_authenticate(
    id_token_str: str,
    role: str,
    db: AsyncSession,
) -> GoogleTokenResponse:
    """
    Verify a Google ID token, find or create a User by google_sub,
    and issue the same JWT pair the OTP flow issues.
    """
    from google.oauth2 import id_token as google_id_token
    from google.auth.transport import requests as google_requests

    try:
        idinfo = google_id_token.verify_oauth2_token(
            id_token_str,
            google_requests.Request(),
            settings.GOOGLE_OAUTH_CLIENT_ID,
        )
    except ValueError as exc:
        raise SokoFetchException(401, "INVALID_GOOGLE_TOKEN", f"Google token verification failed: {exc}")

    google_sub   = idinfo["sub"]
    google_email = idinfo.get("email")

    result = await db.execute(select(User).where(User.google_sub == google_sub))
    user: User | None = result.scalar_one_or_none()
    is_new = False

    if user is None:
        # First-time Google login — create account
        user = User(
            google_sub=google_sub,
            email=google_email,
            role=UserRole(role),
            is_verified=True,
        )
        db.add(user)
        await db.flush()
        is_new = True
        logger.info("New Google user created | role=%s", role)

        # merchant/courier profiles are created separately by their own
        # onboarding endpoints, entering at status=pending_review /
        # registered — same as phone-based signup. Nothing extra to do here.
    else:
        if user.role.value != role:
            from app.core.exceptions import InsufficientRoleError
            raise InsufficientRoleError(role)
        if not user.is_active:
            raise AccountDisabledError()

    user.last_login = datetime.now(timezone.utc)
    await db.flush()

    user_id = str(user.id)
    tokens = create_token_pair(user_id, role)

    profile = GoogleUserProfile(
        user_id=user_id,
        email=user.email,
        role=role,
        is_new=is_new,
        created_at=user.created_at.isoformat(),
    )

    return GoogleTokenResponse(**tokens, expires_in=1800, user=profile)