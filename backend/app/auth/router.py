from fastapi import APIRouter, Depends, Request
from sqlalchemy.ext.asyncio import AsyncSession
import redis.asyncio as aioredis

from app.core.database import get_db
from app.core.redis import get_redis
from app.auth import service
from app.auth.guards import get_current_user
from app.schemas.auth import (
    OTPRequestSchema,
    OTPVerifySchema,
    TokenRefreshSchema,
    OTPRequestResponse,
    TokenResponse,
    LogoutResponse,
    GoogleLoginSchema,
    GoogleTokenResponse,
)

router = APIRouter()


# ─────────────────────────────────────────────────────────────────────────────
# POST /auth/otp/request
# ─────────────────────────────────────────────────────────────────────────────
@router.post(
    "/otp/request",
    response_model=OTPRequestResponse,
    summary="Request OTP",
    description=(
        "Send a 6-digit OTP to the given phone number. "
        "Rate limited to 5 requests per phone per hour."
    ),
)
async def request_otp(
    body: OTPRequestSchema,
    db:    AsyncSession       = Depends(get_db),
    redis: aioredis.Redis     = Depends(get_redis),
):
    result = await service.request_otp(
        phone=body.phone,
        role=body.role,
        db=db,
        redis=redis,
    )
    return result


# ─────────────────────────────────────────────────────────────────────────────
# POST /auth/otp/verify
# ─────────────────────────────────────────────────────────────────────────────
@router.post(
    "/otp/verify",
    response_model=TokenResponse,
    summary="Verify OTP and authenticate",
    description=(
        "Verify the 6-digit OTP. Creates a new user account if first login. "
        "Returns a JWT access token (30 min) and refresh token (30 days)."
    ),
)
async def verify_otp(
    body: OTPVerifySchema,
    db:    AsyncSession   = Depends(get_db),
    redis: aioredis.Redis = Depends(get_redis),
):
    return await service.verify_and_authenticate(
        phone=body.phone,
        code=body.otp_code,
        role=body.role,
        db=db,
        redis=redis,
    )

# ──────────────────────────────────────────────────────────────
# POST /auth/google-login
# ──────────────────────────────────────────────────────────────
@router.post(
    "/google-login",
    response_model=GoogleTokenResponse,
    summary="Sign in with Google",
    description=(
        "Verify a Google ID token. Creates a new user account if first login. "
        "Returns a JWT access token (30 min) and refresh token (30 days)."
    ),
)
async def google_login(
    body: GoogleLoginSchema,
    db: AsyncSession = Depends(get_db),
):
    return await service.verify_google_and_authenticate(
        id_token_str=body.id_token,
        role=body.role,
        db=db,
    )

# ─────────────────────────────────────────────────────────────────────────────
# POST /auth/token/refresh
# ─────────────────────────────────────────────────────────────────────────────
@router.post(
    "/token/refresh",
    response_model=dict,
    summary="Refresh access token",
    description="Exchange a valid refresh token for a new access token.",
)
async def refresh_token(
    body: TokenRefreshSchema,
    redis: aioredis.Redis = Depends(get_redis),
):
    return await service.refresh_access_token(
        refresh_token=body.refresh_token,
        redis=redis,
    )


# ─────────────────────────────────────────────────────────────────────────────
# POST /auth/logout
# ─────────────────────────────────────────────────────────────────────────────
@router.post(
    "/logout",
    response_model=LogoutResponse,
    summary="Log out",
    description="Revoke the current access token (and optionally the refresh token).",
)
async def logout(
    request: Request,
    body:    TokenRefreshSchema | None = None,
    user:    dict                      = Depends(get_current_user),
    redis:   aioredis.Redis            = Depends(get_redis),
):
    # Extract raw access token from Authorization header
    auth_header = request.headers.get("Authorization", "")
    access_token = auth_header.replace("Bearer ", "").strip()

    refresh_token = body.refresh_token if body else None

    await service.logout(
        access_token=access_token,
        refresh_token=refresh_token,
        redis=redis,
    )
    return {"message": "Logged out successfully"}


# ─────────────────────────────────────────────────────────────────────────────
# GET /auth/me
# ─────────────────────────────────────────────────────────────────────────────
@router.get(
    "/me",
    summary="Get current user identity",
    description="Returns the decoded JWT payload for the authenticated user.",
)
async def me(user: dict = Depends(get_current_user)):
    return {
        "user_id": user["sub"],
        "role":    user["role"],
    }
