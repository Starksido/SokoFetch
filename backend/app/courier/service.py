"""
Courier Service
===============
Business logic for the courier app:
  - Profile management and document upload
  - Online/offline toggle
  - Real-time location updates
  - Active order tracking
  - Earnings history
"""
import logging
import secrets
from datetime import datetime, timezone, timedelta
from decimal import Decimal
from uuid import UUID

import boto3
from botocore.exceptions import BotoCoreError, ClientError
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func, cast
from sqlalchemy.orm import selectinload
import redis.asyncio as aioredis

from app.models.courier import (
    Courier, CourierDocument, CourierStatus,
    DocumentType, REQUIRED_DOCUMENTS, VehicleType,
)
from app.models.merchant import Merchant
from app.models.order import Order, OrderStatus, PaymentStatus
from app.core.repository import CourierRepo, MerchantRepo, OrderRepo
from app.core.exceptions import SokoFetchException, ObjectAccessDeniedError, CourierNotApprovedError
from app.orders.pricing import _haversine_km
from app.orders.service import ASSIGNABLE_STATUSES, assign_courier
from app.schemas.order import OrderDetail
from app.core.config import settings
from app.core.encryption import encrypt_document

log = logging.getLogger("alphabet.courier.service")


# ── Eager-load documents for CourierProfileResponse ───────────────────────────
async def _with_documents(courier: Courier, db: AsyncSession) -> Courier:
    """
    CourierProfileResponse serialises documents. A lazy load during response
    serialisation raises MissingGreenlet under AsyncSession (→ 500), so load it
    explicitly before returning.
    """
    await db.refresh(courier, attribute_names=["documents"])
    return courier


# ── Get profile ───────────────────────────────────────────────────────────────
async def get_my_profile(user_id: str, db: AsyncSession) -> Courier:
    repo = CourierRepo(db)
    return await repo.get_by_or_404("Courier", user_id=user_id)


# ── Create profile (called on first OTP login for courier role) ───────────────
async def ensure_courier_profile(user_id: str, db: AsyncSession) -> Courier:
    """Find or create courier profile after OTP login."""
    repo    = CourierRepo(db)
    courier = await repo.get_by(user_id=user_id)
    if not courier:
        courier = await repo.create(
            user_id      = user_id,
            status       = CourierStatus.registered,
            is_online    = False,
            vehicle_type = VehicleType.motorcycle,
        )
        log.info("Courier profile created | user=%s", user_id)
    return courier


# ── Update profile ────────────────────────────────────────────────────────────
async def update_profile(user_id: str, payload, db: AsyncSession) -> Courier:
    repo    = CourierRepo(db)
    courier = await repo.get_by_or_404("Courier", user_id=user_id)

    updates = {k: v for k, v in payload.model_dump().items() if v is not None}

    # FCM token lives on the User model
    fcm_token = updates.pop("fcm_token", None)
    if fcm_token:
        from app.core.repository import UserRepo
        user_repo = UserRepo(db)
        user = await user_repo.get(user_id)
        if user:
            await user_repo.update(user, fcm_token=fcm_token)

    courier = await repo.update(courier, **updates)
    return await _with_documents(courier, db)


# ── Document upload ───────────────────────────────────────────────────────────
async def upload_document(
    user_id: str,
    doc_type: str,
    file_bytes: bytes,
    content_type: str,
    db: AsyncSession,
) -> dict:
    """
    Encrypt and upload a courier verification document to S3.
    Updates courier status to DOCUMENTS_SUBMITTED when all 5 are uploaded.
    """
    repo    = CourierRepo(db)
    courier = await repo.get_by_or_404("Courier", user_id=user_id)

    if courier.status == CourierStatus.deactivated:
        raise SokoFetchException(403, "ACCOUNT_DEACTIVATED", "Account is deactivated.")

    # Validate doc_type
    try:
        dt = DocumentType(doc_type)
    except ValueError:
        raise SokoFetchException(400, "INVALID_DOC_TYPE",
                                f"Document type must be one of: {[d.value for d in DocumentType]}")

    # Encrypt
    encrypted_bytes = encrypt_document(file_bytes)

    # Upload to S3
    s3_key = f"courier-docs/{courier.id}/{doc_type}/{secrets.token_urlsafe(12)}"
    try:
        s3 = boto3.client(
            "s3",
            aws_access_key_id     = settings.AWS_ACCESS_KEY_ID,
            aws_secret_access_key = settings.AWS_SECRET_ACCESS_KEY,
            region_name           = settings.AWS_REGION,
        )
        s3.put_object(
            Bucket               = settings.DOCUMENTS_BUCKET,
            Key                  = s3_key,
            Body                 = encrypted_bytes,
            ContentType          = "application/octet-stream",
            ServerSideEncryption = "AES256",
        )
    except (BotoCoreError, ClientError) as exc:
        log.error("S3 upload failed | courier=%s | type=%s | error=%s", courier.id, doc_type, exc)
        raise SokoFetchException(502, "UPLOAD_FAILED", "Document upload failed. Please retry.")

    # Upsert CourierDocument record
    from sqlalchemy import select as sa_select
    existing_stmt = sa_select(CourierDocument).where(
        CourierDocument.courier_id == str(courier.id),
        CourierDocument.doc_type   == dt,
    )
    result   = await db.execute(existing_stmt)
    existing = result.scalar_one_or_none()

    if existing:
        existing.s3_key      = s3_key
        existing.is_verified = False
        existing.uploaded_at = datetime.now(timezone.utc)
        await db.flush()
    else:
        doc = CourierDocument(
            courier_id  = str(courier.id),
            doc_type    = dt,
            s3_key      = s3_key,
            is_verified = False,
            uploaded_at = datetime.now(timezone.utc),
        )
        db.add(doc)
        await db.flush()

    # Check if all 5 required docs are now uploaded
    count_stmt = sa_select(func.count()).select_from(CourierDocument).where(
        CourierDocument.courier_id == str(courier.id),
    )
    uploaded_count = (await db.execute(count_stmt)).scalar_one()

    if uploaded_count >= len(REQUIRED_DOCUMENTS):
        if courier.status == CourierStatus.registered:
            await repo.update(courier, status=CourierStatus.documents_submitted)
            log.info("All docs uploaded → status=documents_submitted | courier=%s", courier.id)

    return {
        "doc_type": doc_type,
        "message":  "Document uploaded successfully",
        "status":   courier.status.value,
    }


# ── Online/Offline toggle ─────────────────────────────────────────────────────
async def set_online_status(
    user_id: str,
    is_online: bool,
    db: AsyncSession,
    redis: aioredis.Redis,
) -> Courier:
    repo    = CourierRepo(db)
    courier = await repo.get_by_or_404("Courier", user_id=user_id)

    if courier.status != CourierStatus.active:
        raise SokoFetchException(
            403, "NOT_ACTIVE",
            f"Cannot go online: account status is '{courier.status.value}'. "
            "Wait for your documents to be verified."
        )

    courier = await repo.update(courier,
        is_online    = is_online,
        last_seen_at = datetime.now(timezone.utc),
    )

    if not is_online:
        # Clear location from Redis when going offline
        await redis.delete(f"location:courier:{courier.id}")

    log.info("Courier %s | id=%s", "online" if is_online else "offline", courier.id)
    return await _with_documents(courier, db)


# ── Location update ───────────────────────────────────────────────────────────
async def _is_assigned_order(order_id: str, courier: Courier, db: AsyncSession) -> bool:
    try:
        UUID(order_id)
    except ValueError:
        return False
    order = await OrderRepo(db).get(order_id)
    return order is not None and order.courier_id is not None \
        and str(order.courier_id) == str(courier.id)


async def update_location(
    user_id: str,
    latitude: Decimal,
    longitude: Decimal,
    order_id: str | None,
    db: AsyncSession,
    redis: aioredis.Redis,
) -> dict:
    """
    Update courier GPS position.
    Stores in Redis (TTL 5 min) for real-time tracking.
    Broadcasts to active order tracking channel.
    """
    repo    = CourierRepo(db)
    courier = await repo.get_by_or_404("Courier", user_id=user_id)

    if not courier.is_online:
        raise SokoFetchException(422, "OFFLINE", "Cannot update location while offline.")

    # Redis key — TTL 5 minutes
    location_key = f"location:courier:{courier.id}"
    import json
    location_data = json.dumps({
        "latitude":   float(latitude),
        "longitude":  float(longitude),
        "updated_at": datetime.now(timezone.utc).isoformat(),
    })
    await redis.setex(location_key, 300, location_data)

    # If courier has an active order, publish to order tracking channel —
    # only for an order actually assigned to this courier
    if order_id and await _is_assigned_order(order_id, courier, db):
        tracking_channel = f"tracking:order:{order_id}"
        eta_minutes      = 15  # TODO: calculate from Google Maps Directions API
        tracking_payload = json.dumps({
            "latitude":    float(latitude),
            "longitude":   float(longitude),
            "eta_minutes": eta_minutes,
            "updated_at":  datetime.now(timezone.utc).isoformat(),
        })
        await redis.publish(tracking_channel, tracking_payload)

    # Persist last known location to DB (less frequently via background task in prod)
    await repo.update(courier,
        last_latitude  = latitude,
        last_longitude = longitude,
        last_seen_at   = datetime.now(timezone.utc),
    )

    return {"status": "ok", "latitude": float(latitude), "longitude": float(longitude)}


# ── Get active order ──────────────────────────────────────────────────────────
# A courier can accept a job while the shop is still preparing it
ACTIVE_ORDER_STATUSES = (
    OrderStatus.confirmed,
    OrderStatus.preparing,
    OrderStatus.ready_for_pickup,
    OrderStatus.picked_up,
    OrderStatus.in_transit,
)


def _active_order_stmt(courier: Courier):
    return (
        select(Order)
        .where(
            Order.courier_id == courier.id,
            Order.status.in_(ACTIVE_ORDER_STATUSES),
        )
        .order_by(Order.updated_at.desc())
        .limit(1)
    )


async def get_active_order(user_id: str, db: AsyncSession) -> dict | None:
    """
    The courier's current order (if any), with the shop's name, address and
    position so the rider knows where to pick it up.
    """
    repo    = CourierRepo(db)
    courier = await repo.get_by_or_404("Courier", user_id=user_id)

    order = (await db.execute(_active_order_stmt(courier))).scalar_one_or_none()
    if order is None:
        return None

    merchant = await MerchantRepo(db).get(str(order.merchant_id))
    active = OrderDetail.model_validate(order).model_dump()
    if merchant is not None:
        active.update(
            merchant_name    = merchant.shop_name,
            merchant_address = merchant.address,
            merchant_lat     = merchant.latitude,
            merchant_lon     = merchant.longitude,
        )
    return active


# ── Job board: couriers pick up unassigned orders ─────────────────────────────
JOB_LIST_LIMIT = 20


async def _dispatchable_courier(user_id: str, db: AsyncSession) -> Courier:
    courier = await CourierRepo(db).get_by_or_404("Courier", user_id=user_id)
    if courier.status != CourierStatus.active or courier.documents_verified_at is None:
        raise CourierNotApprovedError()
    if not courier.is_online:
        raise SokoFetchException(422, "OFFLINE", "Go online to see and accept jobs.")
    return courier


async def _has_active_order(courier: Courier, db: AsyncSession) -> bool:
    return (await db.execute(_active_order_stmt(courier))).scalar_one_or_none() is not None


def _km(lat1, lon1, lat2, lon2) -> float | None:
    if None in (lat1, lon1, lat2, lon2):
        return None
    return round(_haversine_km(float(lat1), float(lon1), float(lat2), float(lon2)), 1)


async def list_jobs(user_id: str, db: AsyncSession) -> list[dict]:
    """
    Paid orders nobody has taken yet, nearest shop first. Empty while the
    courier is already on a delivery. The customer's exact address is only
    shown after accepting; before that the rider sees the trip distance.
    """
    courier = await _dispatchable_courier(user_id, db)
    if await _has_active_order(courier, db):
        return []

    rows = (await db.execute(
        select(Order, Merchant)
        .join(Merchant, Order.merchant_id == Merchant.id)
        .where(
            Order.courier_id.is_(None),
            Order.status.in_(ASSIGNABLE_STATUSES),
            Order.payment_status == PaymentStatus.paid,
        )
        .order_by(Order.created_at)
        .limit(100)
    )).all()

    jobs = []
    for order, merchant in rows:
        jobs.append({
            "order_id":             str(order.id),
            "status":               order.status.value,
            "merchant_name":        merchant.shop_name,
            "merchant_address":     merchant.address,
            "merchant_latitude":    merchant.latitude,
            "merchant_longitude":   merchant.longitude,
            "item_count":           order.item_count,
            "courier_payout":       order.courier_payout,
            "pickup_distance_km":   _km(courier.last_latitude, courier.last_longitude,
                                        merchant.latitude, merchant.longitude),
            "delivery_distance_km": _km(merchant.latitude, merchant.longitude,
                                        order.delivery_latitude, order.delivery_longitude),
            "created_at":           order.created_at,
        })
    # Nearest first; jobs with an unknown distance go last, oldest first
    jobs.sort(key=lambda j: (j["pickup_distance_km"] is None, j["pickup_distance_km"] or 0))
    return jobs[:JOB_LIST_LIMIT]


async def accept_job(
    user_id: str,
    order_id: str,
    db: AsyncSession,
    redis: aioredis.Redis,
) -> dict:
    """Claim a job. One active delivery per courier."""
    courier = await _dispatchable_courier(user_id, db)

    # Serialise this courier's accepts so a double tap cannot claim two jobs
    lock_key = f"courier_accept_lock:{courier.id}"
    if not await redis.set(lock_key, "1", nx=True, ex=10):
        raise SokoFetchException(409, "ACCEPT_IN_PROGRESS", "Already accepting a job. Please wait.")
    try:
        if await _has_active_order(courier, db):
            raise SokoFetchException(409, "ALREADY_ON_A_JOB", "Finish your current delivery first.")
        await assign_courier(order_id, str(courier.id), db)
    finally:
        await redis.delete(lock_key)

    return await get_active_order(user_id, db)


# ── Earnings history ──────────────────────────────────────────────────────────
async def get_earnings_history(
    user_id: str,
    days: int,
    db: AsyncSession,
) -> list[dict]:
    """Daily earnings breakdown for the last N days."""
    from sqlalchemy import Date
    repo    = CourierRepo(db)
    courier = await repo.get_by_or_404("Courier", user_id=user_id)

    since = datetime.now(timezone.utc) - timedelta(days=days)

    stmt = (
        select(
            cast(Order.delivered_at, Date).label("date"),
            func.count(Order.id).label("deliveries"),
            func.coalesce(func.sum(Order.courier_payout), 0).label("earned"),
        )
        .where(
            Order.courier_id   == str(courier.id),
            Order.status       == OrderStatus.delivered,
            Order.delivered_at >= since,
        )
        .group_by(cast(Order.delivered_at, Date))
        .order_by(cast(Order.delivered_at, Date).desc())
    )
    result = await db.execute(stmt)

    return [
        {
            "date":       str(row.date),
            "deliveries": row.deliveries,
            "earned":     Decimal(str(row.earned)),
        }
        for row in result.all()
    ]


# -- Get profile with documents eager-loaded (fixes DetachedInstanceError on serialization) --
async def get_profile_with_documents(user_id: str, db: AsyncSession) -> Courier:
    result = await db.execute(
        select(Courier)
        .options(selectinload(Courier.documents))
        .where(Courier.user_id == user_id)
    )
    courier = result.scalar_one_or_none()
    if not courier:
        raise SokoFetchException(404, "NOT_FOUND", "Courier profile not found.")
    return courier
