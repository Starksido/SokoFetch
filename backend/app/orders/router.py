from fastapi import APIRouter, Depends, Query, UploadFile, File
from sqlalchemy.ext.asyncio import AsyncSession
import redis.asyncio as aioredis

from app.core.database import get_db
from app.core.redis import get_redis
from app.auth.guards import get_current_user, require_role
from app.orders import service
from app.schemas.order import (
    OrderCreateRequest,
    OrderStatusUpdate,
    OrderRatingRequest,
    ProofOfDeliveryRequest,
    OrderDetail,
    OrderSummary,
)
from app.schemas.common import MessageResponse

router = APIRouter()


# ─────────────────────────────────────────────────────────────────────────────
# POST /orders
# Customer creates a new order
# ─────────────────────────────────────────────────────────────────────────────
@router.post(
    "",
    response_model=OrderDetail,
    status_code=201,
    summary="Place a new order",
)
async def create_order(
    body:  OrderCreateRequest,
    user:  dict           = Depends(require_role("customer")),
    db:    AsyncSession   = Depends(get_db),
    redis: aioredis.Redis = Depends(get_redis),
):
    order = await service.create_order(
        customer_user_id=user["sub"],
        payload=body,
        db=db,
        redis=redis,
    )
    return order


# ─────────────────────────────────────────────────────────────────────────────
# GET /orders
# Returns orders relevant to the caller's role
# ─────────────────────────────────────────────────────────────────────────────
@router.get(
    "",
    response_model=list[OrderSummary],
    summary="List my orders",
    description=(
        "Returns orders for the authenticated user. "
        "Customers see their own orders. "
        "Merchants see orders for their shop. "
        "Couriers see orders assigned to them."
    ),
)
async def list_orders(
    offset: int         = Query(0,  ge=0),
    limit:  int         = Query(20, ge=1, le=100),
    user:   dict        = Depends(get_current_user),
    db:     AsyncSession = Depends(get_db),
):
    return await service.list_orders(user=user, db=db, offset=offset, limit=limit)


# ─────────────────────────────────────────────────────────────────────────────
# GET /orders/{order_id}
# Full order detail — accessible by customer, merchant, or courier for this order
# ─────────────────────────────────────────────────────────────────────────────
@router.get(
    "/{order_id}",
    response_model=OrderDetail,
    summary="Get order detail",
)
async def get_order(
    order_id: str,
    user:     dict        = Depends(get_current_user),
    db:       AsyncSession = Depends(get_db),
):
    return await service.get_order(order_id=order_id, user=user, db=db)


# ─────────────────────────────────────────────────────────────────────────────
# PUT /orders/{order_id}/status
# Drive the order state machine (merchant and courier only)
# ─────────────────────────────────────────────────────────────────────────────
@router.put(
    "/{order_id}/status",
    response_model=OrderDetail,
    summary="Update order status",
    description=(
        "Drive the order state machine. "
        "Merchants can confirm, prepare, and mark ready. "
        "Couriers can mark picked up, in transit, and delivered. "
        "Customers and merchants can cancel pre-pickup."
    ),
)
async def update_status(
    order_id: str,
    body:     OrderStatusUpdate,
    user:     dict           = Depends(get_current_user),
    db:       AsyncSession   = Depends(get_db),
    redis:    aioredis.Redis = Depends(get_redis),
):
    return await service.update_order_status(
        order_id=order_id,
        payload=body,
        user=user,
        db=db,
        redis=redis,
    )


# ─────────────────────────────────────────────────────────────────────────────
# POST /orders/{order_id}/cancel
# Convenience cancel endpoint (same as PUT status=cancelled)
# ─────────────────────────────────────────────────────────────────────────────
@router.post(
    "/{order_id}/cancel",
    response_model=OrderDetail,
    summary="Cancel an order",
)
async def cancel_order(
    order_id: str,
    reason:   str | None  = Query(None),
    user:     dict        = Depends(get_current_user),
    db:       AsyncSession = Depends(get_db),
    redis:    aioredis.Redis = Depends(get_redis),
):
    body = OrderStatusUpdate(status="cancelled", cancellation_reason=reason)
    return await service.update_order_status(
        order_id=order_id,
        payload=body,
        user=user,
        db=db,
        redis=redis,
    )


# ─────────────────────────────────────────────────────────────────────────────
# POST /orders/{order_id}/proof
# Courier submits proof of delivery (OTP or photo)
# ─────────────────────────────────────────────────────────────────────────────
@router.post(
    "/{order_id}/proof",
    response_model=OrderDetail,
    summary="Submit proof of delivery",
)
async def submit_proof(
    order_id:  str,
    body:      ProofOfDeliveryRequest,
    photo:     UploadFile | None = File(None),
    user:      dict              = Depends(require_role("courier")),
    db:        AsyncSession      = Depends(get_db),
):
    photo_url = None
    if photo:
        # In production: upload to S3 and return URL
        # For now: use filename as placeholder
        photo_url = f"proof/{order_id}/{photo.filename}"

    return await service.submit_proof_of_delivery(
        order_id=order_id,
        proof_type=body.proof_type,
        courier_user_id=user["sub"],
        otp_code=body.otp_code,
        photo_url=photo_url,
        db=db,
    )


# ─────────────────────────────────────────────────────────────────────────────
# POST /orders/{order_id}/rate
# Customer rates courier and merchant after delivery
# ─────────────────────────────────────────────────────────────────────────────
@router.post(
    "/{order_id}/rate",
    response_model=OrderDetail,
    summary="Rate a delivered order",
)
async def rate_order(
    order_id: str,
    body:     OrderRatingRequest,
    user:     dict           = Depends(require_role("customer")),
    db:       AsyncSession   = Depends(get_db),
):
    return await service.rate_order(
        order_id=order_id,
        customer_user_id=user["sub"],
        payload=body,
        db=db,
    )
