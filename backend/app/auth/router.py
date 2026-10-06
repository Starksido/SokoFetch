from fastapi import APIRouter, Depends
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from sqlalchemy.ext.asyncio import AsyncSession
import redis.asyncio as aioredis

from app.core.database import get_db
from app.core.redis import get_redis
from app.core.exceptions import InvalidTokenError
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
    SignupSchema,
    SignupRequiredResponse,
)

router = APIRouter()

_optional_bearer = HTTPBearer(auto_error=False)


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
        db=db,
        redis=redis,
    )
    return result


# ─────────────────────────────────────────────────────────────────────────────
# POST /auth/otp/verify
# ─────────────────────────────────────────────────────────────────────────────
@router.post(
    "/otp/verify",
    response_model=TokenResponse | SignupRequiredResponse,
    summary="Verify OTP and authenticate",
    description=(
        "Verify the 6-digit OTP. An existing account is logged in with its own "
        "role and gets a JWT access token (30 min) and refresh token (30 days). "
        "For a new number: with `role` the account is created straight away; "
        "without it the response is `{needs_role: true, signup_token}` and the "
        "account is created by POST /auth/signup once the user picks a role."
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
    response_model=GoogleTokenResponse | SignupRequiredResponse,
    summary="Sign in with Google",
    description=(
        "Verify a Google ID token. Same rules as /auth/otp/verify: existing "
        "accounts log in with their own role, new ones need a role here or a "
        "role picked through POST /auth/signup."
    ),
)
async def google_login(
    body: GoogleLoginSchema,
    db:    AsyncSession   = Depends(get_db),
    redis: aioredis.Redis = Depends(get_redis),
):
    return await service.verify_google_and_authenticate(
        id_token_str=body.id_token,
        role=body.role,
        db=db,
        redis=redis,
    )


# ─────────────────────────────────────────────────────────────────────────────
# POST /auth/signup
# ─────────────────────────────────────────────────────────────────────────────
@router.post(
    "/signup",
    response_model=TokenResponse,
    status_code=201,
    summary="Create the account with the chosen role",
    description=(
        "Exchange the signup_token from /auth/otp/verify or /auth/google-login "
        "for a new account with the chosen role (customer, merchant or courier). "
        "The token is single-use and expires after 10 minutes."
    ),
)
async def signup(
    body:  SignupSchema,
    db:    AsyncSession   = Depends(get_db),
    redis: aioredis.Redis = Depends(get_redis),
):
    return await service.complete_signup(
        signup_token=body.signup_token,
        role=body.role,
        db=db,
        redis=redis,
    )

# ─────────────────────────────────────────────────────────────────────────────
# POST /auth/token/refresh
# ─────────────────────────────────────────────────────────────────────────────
@router.post(
    "/token/refresh",
    response_model=dict,
    summary="Refresh access token",
    description=(
        "Exchange a refresh token for a new token pair. Refresh tokens are "
        "single-use: store the new refresh_token from the response. Reusing "
        "an old one logs the user out everywhere."
    ),
)
async def refresh_token(
    body: TokenRefreshSchema,
    db:    AsyncSession   = Depends(get_db),
    redis: aioredis.Redis = Depends(get_redis),
):
    return await service.refresh_access_token(
        refresh_token=body.refresh_token,
        db=db,
        redis=redis,
    )


# ─────────────────────────────────────────────────────────────────────────────
# POST /auth/logout
# ─────────────────────────────────────────────────────────────────────────────
@router.post(
    "/logout",
    response_model=LogoutResponse,
    summary="Log out",
    description=(
        "Revoke the access token in the Authorization header and/or the refresh "
        "token in the body. Works even after the access token has expired, so "
        "the app can always end the session."
    ),
)
async def logout(
    body:        TokenRefreshSchema | None           = None,
    credentials: HTTPAuthorizationCredentials | None = Depends(_optional_bearer),
    redis:       aioredis.Redis                      = Depends(get_redis),
):
    access_token  = credentials.credentials if credentials else None
    refresh_token = body.refresh_token if body else None
    if not access_token and not refresh_token:
        raise InvalidTokenError()

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
