from uuid import UUID

from fastapi import APIRouter, Depends, Query, UploadFile, File
from sqlalchemy.ext.asyncio import AsyncSession
import redis.asyncio as aioredis

from app.core.database import get_db
from app.core.redis import get_redis
from app.auth.guards import require_role
from app.courier import service
from app.schemas.courier import (
    CourierJob,
    CourierProfileResponse,
    CourierProfileUpdate,
    CourierLocationUpdate,
    DocumentUploadResponse,
    CourierEarningsDay,
)
from app.schemas.order import CourierActiveOrder
from app.schemas.common import MessageResponse
from app.schemas.courier import CourierOnboardRequest

router = APIRouter()


# ─────────────────────────────────────────────────────────────────────────────
# GET /courier/me
# ─────────────────────────────────────────────────────────────────────────────
@router.get(
    "/me",
    response_model=CourierProfileResponse,
    summary="Get my courier profile",
)
async def get_profile(
    user: dict        = Depends(require_role("courier")),
    db:   AsyncSession = Depends(get_db),
):
    return await service.get_profile_with_documents(user_id=user["sub"], db=db)


# ─────────────────────────────────────────────────────────────────────────────
# PUT /courier/me
# ─────────────────────────────────────────────────────────────────────────────
@router.put(
    "/me",
    response_model=CourierProfileResponse,
    summary="Update profile (name, vehicle, payout phone, FCM token)",
)
async def update_profile(
    body: CourierProfileUpdate,
    user: dict        = Depends(require_role("courier")),
    db:   AsyncSession = Depends(get_db),
):
    return await service.update_profile(user_id=user["sub"], payload=body, db=db)


# ─────────────────────────────────────────────────────────────────────────────
# POST /courier/documents/upload
# ─────────────────────────────────────────────────────────────────────────────
@router.post(
    "/documents/upload",
    response_model=DocumentUploadResponse,
    summary="Upload a verification document",
    description=(
        "Upload one of the 5 required documents: "
        "national_id_front, national_id_back, driving_license, vehicle_photo, selfie_with_id. "
        "When all 5 are uploaded the account moves to 'documents_submitted' for admin review."
    ),
)
async def upload_document(
    doc_type: str,
    file:     UploadFile = File(...),
    user:     dict       = Depends(require_role("courier")),
    db:       AsyncSession = Depends(get_db),
):
    file_bytes = await file.read()

    # Guard: max 5MB per file
    if len(file_bytes) > 5 * 1024 * 1024:
        from app.core.exceptions import SokoFetchException
        raise SokoFetchException(413, "FILE_TOO_LARGE", "Maximum file size is 5MB.")

    return await service.upload_document(
        user_id      = user["sub"],
        doc_type     = doc_type,
        file_bytes   = file_bytes,
        content_type = file.content_type or "application/octet-stream",
        db           = db,
    )


# ─────────────────────────────────────────────────────────────────────────────
# PUT /courier/online
# ─────────────────────────────────────────────────────────────────────────────
@router.put(
    "/online",
    response_model=CourierProfileResponse,
    summary="Go online (ready to receive orders)",
)
async def go_online(
    user:  dict           = Depends(require_role("courier")),
    db:    AsyncSession   = Depends(get_db),
    redis: aioredis.Redis = Depends(get_redis),
):
    return await service.set_online_status(
        user_id=user["sub"], is_online=True, db=db, redis=redis
    )


# ─────────────────────────────────────────────────────────────────────────────
# PUT /courier/offline
# ─────────────────────────────────────────────────────────────────────────────
@router.put(
    "/offline",
    response_model=CourierProfileResponse,
    summary="Go offline (stop receiving orders)",
)
async def go_offline(
    user:  dict           = Depends(require_role("courier")),
    db:    AsyncSession   = Depends(get_db),
    redis: aioredis.Redis = Depends(get_redis),
):
    return await service.set_online_status(
        user_id=user["sub"], is_online=False, db=db, redis=redis
    )


# ─────────────────────────────────────────────────────────────────────────────
# PUT /courier/location
# ─────────────────────────────────────────────────────────────────────────────
@router.put(
    "/location",
    summary="Update GPS location",
    description=(
        "Called every 5 seconds by the courier app while online. "
        "Stores in Redis with 5-minute TTL and publishes to order tracking channel."
    ),
)
async def update_location(
    body:  CourierLocationUpdate,
    user:  dict           = Depends(require_role("courier")),
    db:    AsyncSession   = Depends(get_db),
    redis: aioredis.Redis = Depends(get_redis),
):
    return await service.update_location(
        user_id   = user["sub"],
        latitude  = body.latitude,
        longitude = body.longitude,
        order_id  = body.order_id,
        db        = db,
        redis     = redis,
    )


# ─────────────────────────────────────────────────────────────────────────────
# GET /courier/order/active
# ─────────────────────────────────────────────────────────────────────────────
@router.get(
    "/order/active",
    response_model=CourierActiveOrder | None,
    summary="Get my active delivery",
    description=(
        "Returns the courier's current order, or null if none, with the shop's "
        "name, address and position for pick-up. Includes orders accepted while "
        "the shop is still preparing them."
    ),
)
async def get_active_order(
    user: dict        = Depends(require_role("courier")),
    db:   AsyncSession = Depends(get_db),
):
    return await service.get_active_order(user_id=user["sub"], db=db)


# ─────────────────────────────────────────────────────────────────────────────
# GET /courier/jobs
# ─────────────────────────────────────────────────────────────────────────────
@router.get(
    "/jobs",
    response_model=list[CourierJob],
    summary="Available jobs",
    description=(
        "Paid orders no courier has taken yet, nearest shop first (max 20). "
        "Only for approved couriers who are online; empty while the courier "
        "already has an active delivery. Poll every ~15 seconds."
    ),
)
async def list_jobs(
    user: dict         = Depends(require_role("courier")),
    db:   AsyncSession = Depends(get_db),
):
    return await service.list_jobs(user_id=user["sub"], db=db)


# ─────────────────────────────────────────────────────────────────────────────
# POST /courier/jobs/{order_id}/accept
# ─────────────────────────────────────────────────────────────────────────────
@router.post(
    "/jobs/{order_id}/accept",
    response_model=CourierActiveOrder,
    summary="Accept a job",
    description=(
        "Claim an available job. If another courier got there first the "
        "response is 409 JOB_TAKEN. A courier can only have one active delivery."
    ),
)
async def accept_job(
    order_id: UUID,
    user:  dict           = Depends(require_role("courier")),
    db:    AsyncSession   = Depends(get_db),
    redis: aioredis.Redis = Depends(get_redis),
):
    return await service.accept_job(user_id=user["sub"], order_id=str(order_id), db=db, redis=redis)


# ─────────────────────────────────────────────────────────────────────────────
# GET /courier/earnings
# ─────────────────────────────────────────────────────────────────────────────
@router.get(
    "/earnings",
    response_model=list[CourierEarningsDay],
    summary="Earnings history",
    description="Daily delivery earnings for the last N days (default: 7).",
)
async def earnings_history(
    days: int         = Query(7, ge=1, le=90),
    user: dict        = Depends(require_role("courier")),
    db:   AsyncSession = Depends(get_db),
):
    return await service.get_earnings_history(
        user_id=user["sub"], days=days, db=db
    )


@router.post(
    "/onboard",
    response_model=CourierProfileResponse,
    status_code=201,
    summary="Create courier profile (first login)",
)
async def onboard(
    payload: CourierOnboardRequest,
    user:    dict        = Depends(require_role("courier")),
    db:      AsyncSession = Depends(get_db),
):
    await service.ensure_courier_profile(user_id=user["sub"], db=db)
    await service.update_profile(user_id=user["sub"], payload=payload, db=db)
    return await service.get_profile_with_documents(user_id=user["sub"], db=db)
