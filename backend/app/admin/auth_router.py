"""
Admin panel login. Separate from /auth so admin accounts never sign in
through the public app: only admins get codes here, nothing is ever created,
and the tokens issued only work on /admin.
"""
from fastapi import APIRouter, Depends
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.ext.asyncio import AsyncSession
import redis.asyncio as aioredis

from app.auth import service
from app.auth.jwt import CLIENT_ADMIN
from app.core.database import get_db
from app.core.exceptions import InvalidTokenError
from app.core.redis import get_redis
from app.schemas.auth import (
    AdminOTPVerifySchema, LogoutResponse, OTPRequestResponse, OTPRequestSchema,
    TokenRefreshSchema, TokenResponse,
)

router = APIRouter()

_optional_bearer = HTTPBearer(auto_error=False)


@router.post(
    "/otp/request",
    response_model=OTPRequestResponse,
    summary="Request an admin login code",
    description=(
        "Sends a code to the number if it belongs to an active admin. The "
        "response is the same either way, so it can't be used to find admins."
    ),
)
async def request_otp(
    body:  OTPRequestSchema,
    db:    AsyncSession   = Depends(get_db),
    redis: aioredis.Redis = Depends(get_redis),
):
    return await service.request_admin_otp(phone=body.phone, db=db, redis=redis)


@router.post(
    "/otp/verify",
    response_model=TokenResponse,
    summary="Log in to the admin panel",
    description="Verify the code and get admin-panel tokens (valid only on /admin).",
)
async def verify_otp(
    body:  AdminOTPVerifySchema,
    db:    AsyncSession   = Depends(get_db),
    redis: aioredis.Redis = Depends(get_redis),
):
    return await service.verify_admin_otp(
        phone=body.phone, code=body.otp_code, db=db, redis=redis,
    )


@router.post(
    "/token/refresh",
    response_model=dict,
    summary="Refresh admin-panel tokens",
    description="Single-use refresh tokens, as on /auth/token/refresh.",
)
async def refresh_token(
    body:  TokenRefreshSchema,
    db:    AsyncSession   = Depends(get_db),
    redis: aioredis.Redis = Depends(get_redis),
):
    return await service.refresh_access_token(
        refresh_token=body.refresh_token, db=db, redis=redis, client=CLIENT_ADMIN,
    )


@router.post("/logout", response_model=LogoutResponse, summary="Log out of the admin panel")
async def logout(
    body:        TokenRefreshSchema | None           = None,
    credentials: HTTPAuthorizationCredentials | None = Depends(_optional_bearer),
    redis:       aioredis.Redis                      = Depends(get_redis),
):
    access_token  = credentials.credentials if credentials else None
    refresh_token = body.refresh_token if body else None
    if not access_token and not refresh_token:
        raise InvalidTokenError()
    await service.logout(access_token=access_token, refresh_token=refresh_token, redis=redis)
    return {"message": "Logged out successfully"}
