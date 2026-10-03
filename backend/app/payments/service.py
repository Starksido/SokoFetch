"""
Payments Service
================
Orchestrates the full payment lifecycle:
  - Initiate M-Pesa STK Push or verify Flutterwave card charge
  - Handle gateway callbacks / webhooks
  - Mark order as PAID and update Payment record
  - Issue refunds on cancellations
  - Track merchant payout totals
"""
import logging
from decimal import Decimal
from datetime import datetime, timezone

from sqlalchemy.ext.asyncio import AsyncSession
import redis.asyncio as aioredis

from app.models.order import Order, PaymentStatus, PaymentMethod
from app.models.payment import Payment, PaymentGateway, TransactionStatus
from app.models.merchant import Merchant
from app.core.repository import OrderRepo, PaymentRepo, MerchantRepo, CourierRepo
from app.core.exceptions import SokoFetchException, NotFoundError, PaymentBlockedError
from app.payments import mpesa as mpesa_client
from app.payments import flutterwave as flw_client
from app.orders.fraud import check_fraud

log = logging.getLogger("alphabet.payments.service")


# ── Initiate M-Pesa payment ───────────────────────────────────────────────────
async def initiate_mpesa_payment(
    order_id: str,
    customer_phone: str,
    customer_user_id: str,
    db: AsyncSession,
    redis: aioredis.Redis,
) -> dict:
    """
    Start an M-Pesa STK Push for an order.
    Creates a Payment record in PENDING state.
    Returns the Daraja response for the client to show the "Check your phone" screen.
    """
    order_repo = OrderRepo(db)
    order = await order_repo.get_or_404(order_id, "Order")

    if str(order.customer_id) != customer_user_id:
        from app.core.exceptions import ObjectAccessDeniedError
        raise ObjectAccessDeniedError()

    if order.payment_status == PaymentStatus.paid:
        raise SokoFetchException(409, "ALREADY_PAID", "This order has already been paid.")

    # Create a Payment record (initiated state)
    payment_repo = PaymentRepo(db)
    payment = await payment_repo.create(
        order_id    = order_id,
        customer_id = customer_user_id,
        gateway     = PaymentGateway.mpesa,
        amount      = order.total,
        currency    = "KES",
        status      = TransactionStatus.initiated,
    )

    # Call Daraja
    try:
        daraja_resp = await mpesa_client.initiate_stk_push(
            phone    = customer_phone,
            amount   = int(order.total),
            order_id = order_id,
            redis    = redis,
        )
    except Exception as exc:
        await payment_repo.update(payment,
            status=TransactionStatus.failed,
            failure_reason=str(exc),
        )
        raise SokoFetchException(502, "MPESA_ERROR", f"M-Pesa request failed: {exc}")

    # Store checkout ID on the payment record for callback matching
    checkout_id = daraja_resp.get("CheckoutRequestID", "")
    await payment_repo.update(payment,
        gateway_ref = checkout_id,
        status      = TransactionStatus.pending,
    )

    log.info("M-Pesa STK initiated | order=%s | checkout=%s", order_id, checkout_id)
    return {
        "message":            "STK Push sent. Please check your phone.",
        "checkout_request_id": checkout_id,
        "payment_id":         str(payment.id),
    }


# ── Handle M-Pesa callback ────────────────────────────────────────────────────
async def handle_mpesa_callback(
    body: dict,
    db: AsyncSession,
    redis: aioredis.Redis,
) -> dict:
    """
    Process the Daraja STK callback.
    Called by the webhook endpoint after signature verification.
    """
    parsed = mpesa_client.parse_stk_callback(body)
    checkout_id = parsed["checkout_request_id"]
    result_code = parsed["result_code"]

    # Look up the payment record
    payment_repo = PaymentRepo(db)
    payment = await payment_repo.get_by(gateway_ref=checkout_id)

    if not payment:
        log.warning("M-Pesa callback for unknown checkout: %s", checkout_id)
        return {"status": "ignored"}

    if result_code == 0:
        # SUCCESS
        await payment_repo.update(payment,
            status          = TransactionStatus.success,
            gateway_ref     = parsed.get("mpesa_receipt") or checkout_id,
            gateway_payload = parsed,
            completed_at    = datetime.now(timezone.utc),
        )
        await _mark_order_paid(str(payment.order_id), parsed.get("mpesa_receipt"), db)
        log.info("M-Pesa payment SUCCESS | order=%s | receipt=%s",
                 payment.order_id, parsed.get("mpesa_receipt"))
    else:
        # FAILURE (user cancelled, timeout, wrong PIN, etc.)
        await payment_repo.update(payment,
            status         = TransactionStatus.failed,
            failure_reason = parsed["result_desc"],
            gateway_payload = parsed,
        )
        log.info("M-Pesa payment FAILED | order=%s | reason=%s",
                 payment.order_id, parsed["result_desc"])

    return {"status": "processed"}


# ── Verify Flutterwave card payment ───────────────────────────────────────────
async def verify_card_payment(
    order_id: str,
    transaction_id: str,
    customer_user_id: str,
    db: AsyncSession,
) -> dict:
    """
    Customer calls this after Flutterwave SDK confirms on-device payment.
    We verify server-side with Flutterwave before marking order as paid.
    """
    order_repo = OrderRepo(db)
    order = await order_repo.get_or_404(order_id, "Order")

    if str(order.customer_id) != customer_user_id:
        from app.core.exceptions import ObjectAccessDeniedError
        raise ObjectAccessDeniedError()

    if order.payment_status == PaymentStatus.paid:
        raise SokoFetchException(409, "ALREADY_PAID", "This order has already been paid.")

    # Verify with Flutterwave
    try:
        tx = await flw_client.verify_payment(transaction_id)
    except Exception as exc:
        raise SokoFetchException(402, "PAYMENT_VERIFICATION_FAILED", str(exc))

    # Verify amount matches order total (anti-tampering check)
    paid_amount = Decimal(str(tx.get("amount", 0)))
    if paid_amount < order.total:
        raise SokoFetchException(
            402, "AMOUNT_MISMATCH",
            f"Payment amount KES {paid_amount} does not match order total KES {order.total}."
        )

    # Record payment
    payment_repo = PaymentRepo(db)
    payment = await payment_repo.create(
        order_id        = order_id,
        customer_id     = customer_user_id,
        gateway         = PaymentGateway.flutterwave,
        gateway_ref     = tx.get("flw_ref"),
        gateway_payload = tx,
        amount          = paid_amount,
        currency        = tx.get("currency", "KES"),
        status          = TransactionStatus.success,
        completed_at    = datetime.now(timezone.utc),
    )

    await _mark_order_paid(order_id, tx.get("flw_ref"), db)

    log.info("FLW payment verified | order=%s | tx=%s", order_id, transaction_id)
    return {
        "message":    "Payment verified. Order confirmed.",
        "payment_id": str(payment.id),
        "order_id":   order_id,
    }


# ── Handle Flutterwave webhook ────────────────────────────────────────────────
async def handle_flw_webhook(body: dict, db: AsyncSession) -> dict:
    """Process Flutterwave charge.completed webhook."""
    parsed = flw_client.parse_flw_webhook(body)

    if parsed["event"] != "charge.completed":
        return {"status": "ignored"}

    if parsed["status"] != "successful":
        log.info("FLW webhook non-success | status=%s | tx_ref=%s",
                 parsed["status"], parsed["tx_ref"])
        return {"status": "ignored"}

    # tx_ref is our order_id (set when customer initiates payment)
    order_id = parsed["tx_ref"]
    await _mark_order_paid(order_id, parsed["flw_ref"], db)

    log.info("FLW webhook processed | order=%s", order_id)
    return {"status": "processed"}


# ── Shared: mark order as PAID ────────────────────────────────────────────────
async def _mark_order_paid(order_id: str, payment_ref: str | None, db: AsyncSession):
    """Update order payment status and credit merchant pending payout."""
    order_repo = OrderRepo(db)
    order = await order_repo.get(order_id)
    if not order or order.payment_status == PaymentStatus.paid:
        return

    await order_repo.update(order,
        payment_status = PaymentStatus.paid,
        payment_ref    = payment_ref,
    )

    # Credit merchant pending payout (net of commission)
    net_merchant = order.subtotal - order.merchant_commission
    merchant_repo = MerchantRepo(db)
    merchant = await merchant_repo.get(str(order.merchant_id))
    if merchant:
        new_pending = Decimal(str(merchant.rating)) # placeholder — use actual pending field
        # Update merchant pending payout
        await db.execute(
            __import__("sqlalchemy").text(
                "UPDATE merchants SET pending_payout = COALESCE(pending_payout, 0) + :amount "
                "WHERE id = :mid"
            ),
            {"amount": float(net_merchant), "mid": str(merchant.id)},
        )

    # Credit courier pending payout
    if order.courier_id and order.courier_payout:
        await db.execute(
            __import__("sqlalchemy").text(
                "UPDATE couriers SET pending_payout = COALESCE(pending_payout, 0) + :amount, "
                "total_earned = COALESCE(total_earned, 0) + :amount "
                "WHERE id = :cid"
            ),
            {"amount": float(order.courier_payout), "cid": str(order.courier_id)},
        )

    log.info("Order marked PAID | id=%s | ref=%s", order_id, payment_ref)


# ── Refund ────────────────────────────────────────────────────────────────────
async def refund_order(
    order_id: str,
    reason: str,
    db: AsyncSession,
) -> dict:
    """
    Issue a refund for a cancelled paid order.
    Finds the successful payment record and triggers gateway refund.
    """
    payment_repo = PaymentRepo(db)

    # Find the successful payment for this order
    from sqlalchemy import select
    from app.models.payment import Payment
    stmt = (
        select(Payment)
        .where(
            Payment.order_id == order_id,
            Payment.status   == TransactionStatus.success,
        )
        .limit(1)
    )
    result = await db.execute(stmt)
    payment = result.scalar_one_or_none()

    if not payment:
        log.info("No paid payment found for order %s — no refund needed", order_id)
        return {"message": "No refund required"}

    try:
        if payment.gateway == PaymentGateway.flutterwave:
            await flw_client.initiate_refund(payment.gateway_ref, float(payment.amount))
        else:
            # M-Pesa refunds are manual via Safaricom Business Reversal API
            # Log for manual processing
            log.warning(
                "M-Pesa refund required | order=%s | amount=%s | receipt=%s",
                order_id, payment.amount, payment.gateway_ref
            )

        await payment_repo.update(payment, status=TransactionStatus.refunded)
        log.info("Refund initiated | order=%s | gateway=%s", order_id, payment.gateway.value)
        return {"message": "Refund initiated", "order_id": order_id}

    except Exception as exc:
        log.error("Refund failed | order=%s | error=%s", order_id, exc)
        raise SokoFetchException(502, "REFUND_FAILED", f"Refund could not be initiated: {exc}")


# ── Payout summary ────────────────────────────────────────────────────────────
async def get_merchant_earnings(merchant_user_id: str, db: AsyncSession) -> dict:
    """
    Summarise today's earnings for a merchant dashboard.
    """
    from sqlalchemy import select, func
    from app.models.order import Order, PaymentStatus as PS
    from datetime import date

    merchant_repo = MerchantRepo(db)
    merchant = await merchant_repo.get_by_or_404("Merchant", user_id=merchant_user_id)

    today = datetime.now(timezone.utc).replace(hour=0, minute=0, second=0, microsecond=0)

    stmt = (
        select(
            func.count(Order.id).label("total_orders"),
            func.coalesce(func.sum(Order.subtotal), 0).label("gross_revenue"),
            func.coalesce(func.sum(Order.merchant_commission), 0).label("commission"),
        )
        .where(
            Order.merchant_id    == str(merchant.id),
            Order.payment_status == PS.paid,
            Order.created_at     >= today,
        )
    )
    result = await db.execute(stmt)
    row = result.one()

    gross      = Decimal(str(row.gross_revenue))
    commission = Decimal(str(row.commission))
    net        = gross - commission

    return {
        "date":               today.date().isoformat(),
        "total_orders":       row.total_orders,
        "gross_revenue":      gross,
        "commission_deducted": commission,
        "net_payout":         net,
    }


async def get_courier_earnings(courier_user_id: str, db: AsyncSession) -> dict:
    """Today's earnings for a courier."""
    from sqlalchemy import select, func
    from app.models.order import Order, PaymentStatus as PS, OrderStatus

    courier_repo = CourierRepo(db)
    courier = await courier_repo.get_by_or_404("Courier", user_id=courier_user_id)

    today = datetime.now(timezone.utc).replace(hour=0, minute=0, second=0, microsecond=0)

    stmt = (
        select(
            func.count(Order.id).label("deliveries"),
            func.coalesce(func.sum(Order.courier_payout), 0).label("earned"),
        )
        .where(
            Order.courier_id     == str(courier.id),
            Order.status         == OrderStatus.delivered,
            Order.delivered_at   >= today,
        )
    )
    result = await db.execute(stmt)
    row = result.one()

    return {
        "date":       today.date().isoformat(),
        "deliveries": row.deliveries,
        "earned":     Decimal(str(row.earned)),
        "pending_payout": Decimal(str(courier.pending_payout or 0)),
        "total_earned":   Decimal(str(courier.total_earned or 0)),
    }
