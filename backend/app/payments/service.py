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
import uuid
from decimal import Decimal
from datetime import datetime, timezone

from sqlalchemy import select, text
from sqlalchemy.ext.asyncio import AsyncSession
import redis.asyncio as aioredis

from app.models.order import Order, OrderStatus, PaymentStatus, PaymentMethod
from app.models.payment import Payment, PaymentGateway, TransactionStatus
from app.models.merchant import Merchant
from app.core.repository import OrderRepo, PaymentRepo, MerchantRepo, CourierRepo, CustomerRepo
from app.core.exceptions import (
    SokoFetchException, NotFoundError, PaymentBlockedError, ObjectAccessDeniedError,
)
from app.auth.otp import validate_phone
from app.payments import mpesa as mpesa_client
from app.payments import flutterwave as flw_client
from app.orders.fraud import check_fraud

log = logging.getLogger("alphabet.payments.service")


# ── Shared checks ─────────────────────────────────────────────────────────────
async def _assert_customer_owns_order(order: Order, customer_user_id: str, db: AsyncSession) -> None:
    """order.customer_id is the customer PROFILE id, not the users.id in the JWT."""
    customer = await CustomerRepo(db).get_by_user_id(customer_user_id)
    if customer is None or str(order.customer_id) != str(customer.id):
        raise ObjectAccessDeniedError()


def _assert_payable(order: Order) -> None:
    if order.payment_status == PaymentStatus.paid:
        raise SokoFetchException(409, "ALREADY_PAID", "This order has already been paid.")
    if order.status != OrderStatus.pending:
        raise SokoFetchException(409, "ORDER_NOT_PAYABLE",
                                 f"An order in status '{order.status.value}' cannot be paid.")


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

    await _assert_customer_owns_order(order, customer_user_id, db)
    _assert_payable(order)

    phone  = validate_phone(customer_phone)          # 0712… → +254712…
    amount = mpesa_client.daraja_amount(order.total)  # whole KES, rounded up

    # Create a Payment record (initiated state)
    payment_repo = PaymentRepo(db)
    payment = await payment_repo.create(
        order_id    = order_id,
        customer_id = customer_user_id,
        gateway     = PaymentGateway.mpesa,
        amount      = amount,
        currency    = "KES",
        status      = TransactionStatus.initiated,
    )

    # Call Daraja
    try:
        daraja_resp = await mpesa_client.initiate_stk_push(
            phone    = phone,
            amount   = amount,
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
    Called by the webhook endpoint after the callback token is verified.
    Only PENDING payments are processed, so repeated callbacks are no-ops.
    """
    parsed = mpesa_client.parse_stk_callback(body)
    checkout_id = parsed["checkout_request_id"]
    result_code = parsed["result_code"]

    if not checkout_id:
        log.warning("M-Pesa callback without CheckoutRequestID")
        return {"status": "ignored"}

    # Look up the payment record
    payment_repo = PaymentRepo(db)
    payment = await payment_repo.get_by(gateway=PaymentGateway.mpesa, gateway_ref=checkout_id)

    if not payment:
        log.warning("M-Pesa callback for unknown checkout: %s", checkout_id)
        return {"status": "ignored"}

    if payment.status != TransactionStatus.pending:
        log.info("M-Pesa duplicate callback ignored | checkout=%s | status=%s",
                 checkout_id, payment.status.value)
        return {"status": "ignored"}

    if result_code == 0:
        # SUCCESS — but only if the customer actually paid the full amount
        order = await OrderRepo(db).get(str(payment.order_id))
        paid  = parsed.get("amount")
        if order is None or paid is None or Decimal(str(paid)) < Decimal(str(order.total)):
            reason = f"Amount mismatch: paid {paid}, expected {order.total if order else 'unknown'}"
            await payment_repo.update(payment,
                status          = TransactionStatus.failed,
                failure_reason  = reason,
                gateway_payload = parsed,
            )
            log.warning("M-Pesa payment REJECTED | order=%s | %s", payment.order_id, reason)
            return {"status": "processed"}

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


# ── Flutterwave helpers ───────────────────────────────────────────────────────
async def _flw_tx_already_recorded(tx: dict, db: AsyncSession) -> bool:
    existing = await PaymentRepo(db).get_by(
        gateway=PaymentGateway.flutterwave, gateway_ref=str(tx.get("id")),
    )
    return existing is not None


async def _record_flw_payment(order: Order, tx: dict, customer_user_id: str, db: AsyncSession) -> Payment:
    """Store the verified charge (gateway_ref = FLW transaction id, needed for refunds) and mark paid."""
    payment = await PaymentRepo(db).create(
        order_id        = str(order.id),
        customer_id     = customer_user_id,
        gateway         = PaymentGateway.flutterwave,
        gateway_ref     = str(tx.get("id")),
        gateway_payload = tx,
        amount          = Decimal(str(tx.get("amount", 0))),
        currency        = tx.get("currency", "KES"),
        status          = TransactionStatus.success,
        completed_at    = datetime.now(timezone.utc),
    )
    await _mark_order_paid(str(order.id), tx.get("flw_ref"), db)
    return payment


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

    await _assert_customer_owns_order(order, customer_user_id, db)
    _assert_payable(order)

    # Verify with Flutterwave
    try:
        tx = await flw_client.verify_payment(transaction_id)
    except Exception as exc:
        raise SokoFetchException(402, "PAYMENT_VERIFICATION_FAILED", str(exc))

    # The charge must be for THIS order, in KES, for at least the order total
    try:
        flw_client.validate_transaction_for_order(tx, str(order.id), order.total)
    except ValueError as exc:
        raise SokoFetchException(402, "PAYMENT_MISMATCH", str(exc))

    # One Flutterwave transaction can only ever pay once
    if await _flw_tx_already_recorded(tx, db):
        raise SokoFetchException(409, "TRANSACTION_ALREADY_USED", "This payment has already been used.")

    payment = await _record_flw_payment(order, tx, customer_user_id, db)

    log.info("FLW payment verified | order=%s | tx=%s", order_id, transaction_id)
    return {
        "message":    "Payment verified. Order confirmed.",
        "payment_id": str(payment.id),
        "order_id":   order_id,
    }


# ── Handle Flutterwave webhook ────────────────────────────────────────────────
async def handle_flw_webhook(body: dict, db: AsyncSession) -> dict:
    """
    Process Flutterwave charge.completed webhook.
    The webhook body is never trusted: the transaction is re-verified with the
    Flutterwave API and matched to the order before anything is marked paid.
    """
    parsed = flw_client.parse_flw_webhook(body)

    if parsed["event"] != "charge.completed":
        return {"status": "ignored"}

    if parsed["status"] != "successful" or not parsed["transaction_id"]:
        log.info("FLW webhook non-success | status=%s | tx_ref=%s",
                 parsed["status"], parsed["tx_ref"])
        return {"status": "ignored"}

    # Network errors propagate (5xx) so Flutterwave retries the webhook
    try:
        tx = await flw_client.verify_payment(parsed["transaction_id"])
    except ValueError as exc:
        log.warning("FLW webhook: transaction not verified | tx=%s | %s", parsed["transaction_id"], exc)
        return {"status": "ignored"}

    # tx_ref is our order_id (set when the app starts the Flutterwave charge)
    order_id = str(tx.get("tx_ref", ""))
    try:
        uuid.UUID(order_id)
    except ValueError:
        log.warning("FLW webhook: tx_ref is not an order id | tx_ref=%s", order_id)
        return {"status": "ignored"}

    order = await OrderRepo(db).get(order_id)
    if order is None or order.payment_status == PaymentStatus.paid:
        return {"status": "ignored"}

    try:
        flw_client.validate_transaction_for_order(tx, str(order.id), order.total)
    except ValueError as exc:
        log.warning("FLW webhook: transaction does not match order | order=%s | %s", order_id, exc)
        return {"status": "ignored"}

    if await _flw_tx_already_recorded(tx, db):
        return {"status": "ignored"}

    customer = await CustomerRepo(db).get(str(order.customer_id))
    await _record_flw_payment(order, tx, str(customer.user_id), db)

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

    # Credit merchant pending payout (net of commission).
    # Couriers are credited on delivery, not payment (see orders.service).
    net_merchant = order.subtotal - order.merchant_commission
    merchant_repo = MerchantRepo(db)
    merchant = await merchant_repo.get(str(order.merchant_id))
    if merchant:
        await _adjust_merchant_pending_payout(str(merchant.id), net_merchant, db)

    log.info("Order marked PAID | id=%s | ref=%s", order_id, payment_ref)


async def _adjust_merchant_pending_payout(merchant_id: str, amount: Decimal, db: AsyncSession) -> None:
    """Atomic +/- on merchants.pending_payout (negative = merchant owes it back)."""
    await db.execute(
        text(
            "UPDATE merchants SET pending_payout = COALESCE(pending_payout, 0) + :amount "
            "WHERE id = :mid"
        ),
        {"amount": Decimal(str(amount)), "mid": merchant_id},
    )


# ── Refund ────────────────────────────────────────────────────────────────────
async def refund_order(
    order_id: str,
    reason: str | None,
    db: AsyncSession,
) -> dict:
    """
    Issue a refund for a cancelled paid order.
    Finds the successful payment record and triggers the gateway refund.

    Card (Flutterwave): refunded via the API; the order is marked REFUNDED and
    the merchant credit is reversed. M-Pesa: there is no automatic reversal, so
    nothing is marked refunded — it is logged for manual reversal instead.
    """
    payment_repo = PaymentRepo(db)

    # Find the successful payment for this order
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
        return {"message": "No refund required", "order_id": order_id}

    if payment.gateway != PaymentGateway.flutterwave:
        log.warning(
            "MANUAL M-Pesa reversal required | order=%s | amount=%s | receipt=%s | reason=%s",
            order_id, payment.amount, payment.gateway_ref, reason,
        )
        return {
            "message":  "M-Pesa payments must be reversed manually.",
            "order_id": order_id,
            "manual_action_required": True,
        }

    try:
        await flw_client.initiate_refund(payment.gateway_ref, float(payment.amount))
    except Exception as exc:
        log.error("Refund failed | order=%s | error=%s", order_id, exc)
        raise SokoFetchException(502, "REFUND_FAILED", f"Refund could not be initiated: {exc}")

    await payment_repo.update(payment, status=TransactionStatus.refunded)

    order = await OrderRepo(db).get(order_id)
    if order and order.payment_status == PaymentStatus.paid:
        await OrderRepo(db).update(order, payment_status=PaymentStatus.refunded)
        await _adjust_merchant_pending_payout(
            str(order.merchant_id), -(order.subtotal - order.merchant_commission), db,
        )

    log.info("Refund initiated | order=%s | gateway=%s", order_id, payment.gateway.value)
    return {"message": "Refund initiated", "order_id": order_id}


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
