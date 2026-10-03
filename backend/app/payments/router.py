import json
import logging

from fastapi import APIRouter, Depends, Request, Header
from sqlalchemy.ext.asyncio import AsyncSession
import redis.asyncio as aioredis

from app.core.database import get_db
from app.core.redis import get_redis
from app.core.exceptions import SokoFetchException
from app.auth.guards import get_current_user, require_role
from app.payments import service
from app.payments.mpesa import verify_callback_signature
from app.payments.flutterwave import verify_webhook_signature
from app.schemas.payment import (
    MpesaInitiateRequest,
    MpesaInitiateResponse,
    FlutterwaveVerifyRequest,
    PaymentVerifyResponse,
    EarningsSummary,
    CourierEarningsSummary,
)

router = APIRouter()
log = logging.getLogger("alphabet.payments.router")


# ─────────────────────────────────────────────────────────────────────────────
# POST /payments/mpesa/initiate
# Customer initiates M-Pesa STK Push
# ─────────────────────────────────────────────────────────────────────────────
@router.post(
    "/mpesa/initiate",
    response_model=MpesaInitiateResponse,
    summary="Initiate M-Pesa STK Push",
    description=(
        "Sends an M-Pesa payment prompt to the customer's phone. "
        "Customer enters their PIN to complete payment. "
        "Result arrives asynchronously via /mpesa/callback."
    ),
)
async def initiate_mpesa(
    body:  MpesaInitiateRequest,
    user:  dict           = Depends(require_role("customer")),
    db:    AsyncSession   = Depends(get_db),
    redis: aioredis.Redis = Depends(get_redis),
):
    return await service.initiate_mpesa_payment(
        order_id         = body.order_id,
        customer_phone   = body.phone,
        customer_user_id = user["sub"],
        db=db,
        redis=redis,
    )


# ─────────────────────────────────────────────────────────────────────────────
# POST /payments/mpesa/callback
# Safaricom webhook — no auth (verified by HMAC signature)
# ─────────────────────────────────────────────────────────────────────────────
@router.post(
    "/mpesa/callback",
    include_in_schema=False,   # Hide from Swagger — internal webhook only
)
async def mpesa_callback(
    request: Request,
    db:      AsyncSession   = Depends(get_db),
    redis:   aioredis.Redis = Depends(get_redis),
):
    raw_body = await request.body()
    body_str = raw_body.decode("utf-8")

    # Verify Safaricom signature (skip in sandbox/dev)
    from app.core.config import settings
    if settings.is_production:
        sig = request.headers.get("X-Mpesa-Signature", "")
        if not verify_callback_signature(body_str, sig):
            log.warning("M-Pesa callback signature verification failed")
            raise SokoFetchException(401, "INVALID_SIGNATURE", "Callback signature invalid.")

    try:
        body = json.loads(body_str)
    except json.JSONDecodeError:
        raise SokoFetchException(400, "INVALID_JSON", "Callback body is not valid JSON.")

    return await service.handle_mpesa_callback(body, db, redis)


# ─────────────────────────────────────────────────────────────────────────────
# POST /payments/card/verify
# Customer verifies a completed Flutterwave card charge
# ─────────────────────────────────────────────────────────────────────────────
@router.post(
    "/card/verify",
    response_model=PaymentVerifyResponse,
    summary="Verify Flutterwave card payment",
    description=(
        "After the Flutterwave Flutter SDK confirms payment on-device, "
        "the app calls this endpoint to verify server-side before the order is confirmed."
    ),
)
async def verify_card(
    body:  FlutterwaveVerifyRequest,
    user:  dict         = Depends(require_role("customer")),
    db:    AsyncSession = Depends(get_db),
):
    return await service.verify_card_payment(
        order_id         = body.order_id,
        transaction_id   = body.transaction_id,
        customer_user_id = user["sub"],
        db=db,
    )


# ─────────────────────────────────────────────────────────────────────────────
# POST /payments/flutterwave/webhook
# Flutterwave webhook — no auth (verified by hash header)
# ─────────────────────────────────────────────────────────────────────────────
@router.post(
    "/flutterwave/webhook",
    include_in_schema=False,
)
async def flw_webhook(
    request: Request,
    verif_hash: str | None = Header(None, alias="verif-hash"),
    db: AsyncSession = Depends(get_db),
):
    raw_body = await request.body()
    body_str = raw_body.decode("utf-8")

    from app.core.config import settings
    if settings.is_production and verif_hash:
        if not verify_webhook_signature(body_str, verif_hash):
            log.warning("Flutterwave webhook signature failed")
            raise SokoFetchException(401, "INVALID_SIGNATURE", "Webhook signature invalid.")

    try:
        body = json.loads(body_str)
    except json.JSONDecodeError:
        raise SokoFetchException(400, "INVALID_JSON", "Webhook body is not valid JSON.")

    return await service.handle_flw_webhook(body, db)


# ─────────────────────────────────────────────────────────────────────────────
# POST /payments/refund
# Admin-initiated refund for a cancelled order
# ─────────────────────────────────────────────────────────────────────────────
@router.post(
    "/refund",
    summary="Initiate refund",
    description="Trigger a refund for a paid, cancelled order. Admin or system use.",
)
async def refund(
    order_id: str,
    reason:   str | None = None,
    user:     dict       = Depends(require_role("admin")),
    db:       AsyncSession = Depends(get_db),
):
    return await service.refund_order(order_id=order_id, reason=reason, db=db)


# ─────────────────────────────────────────────────────────────────────────────
# GET /payments/earnings/merchant
# Merchant's today earnings summary
# ─────────────────────────────────────────────────────────────────────────────
@router.get(
    "/earnings/merchant",
    response_model=EarningsSummary,
    summary="Merchant earnings today",
)
async def merchant_earnings(
    user: dict        = Depends(require_role("merchant")),
    db:   AsyncSession = Depends(get_db),
):
    return await service.get_merchant_earnings(
        merchant_user_id=user["sub"], db=db
    )


# ─────────────────────────────────────────────────────────────────────────────
# GET /payments/earnings/courier
# Courier's today earnings summary
# ─────────────────────────────────────────────────────────────────────────────
@router.get(
    "/earnings/courier",
    response_model=CourierEarningsSummary,
    summary="Courier earnings today",
)
async def courier_earnings(
    user: dict        = Depends(require_role("courier")),
    db:   AsyncSession = Depends(get_db),
):
    return await service.get_courier_earnings(
        courier_user_id=user["sub"], db=db
    )
