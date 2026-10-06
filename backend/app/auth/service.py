import hashlib
import json
import logging
import secrets
from datetime import datetime, timezone

from sqlalchemy.exc import IntegrityError
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
from app.schemas.auth import UserProfile, TokenResponse, SignupRequiredResponse
from app.core.exceptions import (
    AccountDisabledError, AlreadyExistsError, InsufficientRoleError,
    InvalidTokenError, RevokedTokenError,
)

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
    db: AsyncSession,
    redis: aioredis.Redis,
) -> dict:
    """Generate OTP and send via SMS. Returns expiry info."""
    phone = validate_phone(phone)
    await check_rate_limit(phone, redis)

    code = await generate_otp(phone, redis)
    await send_otp_sms(phone, code)

    return {"message": "OTP sent successfully", "expires_in": 300}


# ── Shared login helpers ──────────────────────────────────────────────────────
SIGNUP_TOKEN_TTL = 600   # seconds the user has to pick a role


def _check_can_log_in(user: User, requested_role: str | None) -> None:
    if requested_role is not None and user.role.value != requested_role:
        # A courier trying to log in as a customer, etc. — reject
        raise InsufficientRoleError(requested_role)
    if not user.is_active:
        raise AccountDisabledError()


async def _start_signup(identity: dict, redis: aioredis.Redis) -> SignupRequiredResponse:
    """
    The phone/Google account is verified but has no user yet. Park the
    verified identity in Redis; POST /auth/signup turns it into an account
    once the user has picked a role.
    """
    token = secrets.token_urlsafe(32)
    await redis.setex(f"signup:{token}", SIGNUP_TOKEN_TTL, json.dumps(identity))
    return SignupRequiredResponse(signup_token=token, expires_in=SIGNUP_TOKEN_TTL)


async def _create_user(db: AsyncSession, **fields) -> User:
    user = User(is_verified=True, **fields)
    db.add(user)
    try:
        await db.flush()   # Get the generated UUID
    except IntegrityError:
        # The same phone / Google account signed up concurrently
        raise AlreadyExistsError("Account")
    logger.info("New user created | role=%s", user.role.value)
    return user


async def _token_response(
    user: User, is_new: bool, db: AsyncSession, phone: str | None = None,
) -> TokenResponse:
    user.last_login = datetime.now(timezone.utc)
    await db.flush()

    user_id = str(user.id)
    role = user.role.value
    profile = UserProfile(
        user_id=user_id,
        phone=phone,
        email=user.email,
        role=role,
        is_new=is_new,
        created_at=user.created_at.isoformat(),
    )
    return TokenResponse(**create_token_pair(user_id, role), expires_in=1800, user=profile)


# ── Verify OTP & issue tokens ─────────────────────────────────────────────────
async def verify_and_authenticate(
    phone: str,
    code: str,
    role: str | None,
    db: AsyncSession,
    redis: aioredis.Redis,
) -> TokenResponse | SignupRequiredResponse:
    """
    Verify the OTP. An existing account is logged in with its own role.
    A new number either gets an account straight away (role given) or a
    signup_token to pick a role with (role omitted).
    """
    phone = validate_phone(phone)
    await verify_otp(phone, code, redis)   # Raises InvalidOTPError on failure

    ph = _phone_hash(phone)
    result = await db.execute(select(User).where(User.phone_hash == ph))
    user: User | None = result.scalar_one_or_none()
    is_new = False

    if user is None:
        if role is None:
            return await _start_signup({"phone": phone}, redis)
        user = await _create_user(db, phone=phone, phone_hash=ph, role=UserRole(role))
        is_new = True
    else:
        _check_can_log_in(user, role)

    return await _token_response(user, is_new, db, phone=phone)


# ── Sign up: create the account once a role is picked ─────────────────────────
async def complete_signup(
    signup_token: str,
    role: str,
    db: AsyncSession,
    redis: aioredis.Redis,
) -> TokenResponse:
    raw = await redis.getdel(f"signup:{signup_token}")   # Single use
    if not raw:
        raise SokoFetchException(
            400, "INVALID_SIGNUP_TOKEN",
            "Sign-up session expired. Please verify your phone or Google account again.",
        )
    identity = json.loads(raw)

    if "phone" in identity:
        phone = identity["phone"]
        ph = _phone_hash(phone)
        if (await db.execute(select(User.id).where(User.phone_hash == ph))).first():
            raise AlreadyExistsError("Account")
        user = await _create_user(db, phone=phone, phone_hash=ph, role=UserRole(role))
        return await _token_response(user, True, db, phone=phone)

    google_sub = identity["google_sub"]
    if (await db.execute(select(User.id).where(User.google_sub == google_sub))).first():
        raise AlreadyExistsError("Account")
    user = await _create_user(
        db, google_sub=google_sub, email=identity.get("email"), role=UserRole(role),
    )
    return await _token_response(user, True, db)


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
    role: str | None,
    db: AsyncSession,
    redis: aioredis.Redis,
) -> GoogleTokenResponse | SignupRequiredResponse:
    """
    Verify a Google ID token, then behave like OTP verify: an existing
    account logs in with its own role; a new one needs a role (given here,
    or picked later through POST /auth/signup).
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
        if role is None:
            return await _start_signup({"google_sub": google_sub, "email": google_email}, redis)
        # merchant/courier profiles are created separately by their own
        # onboarding endpoints — same as phone-based signup.
        user = await _create_user(db, google_sub=google_sub, email=google_email, role=UserRole(role))
        is_new = True
    else:
        _check_can_log_in(user, role)

    user.last_login = datetime.now(timezone.utc)
    await db.flush()

    user_id = str(user.id)
    role = user.role.value
    profile = GoogleUserProfile(
        user_id=user_id,
        email=user.email,
        role=role,
        is_new=is_new,
        created_at=user.created_at.isoformat(),
    )

    return GoogleTokenResponse(**create_token_pair(user_id, role), expires_in=1800, user=profile)
