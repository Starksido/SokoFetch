"""
Fraud Detection Engine
======================
Runs five checks before any order is accepted.
All checks are async and use the DB + Redis.

Returns (is_fraud: bool, reason: str).
Calling code should block the order if is_fraud is True.
"""
import logging
from decimal import Decimal
from datetime import datetime, timezone, timedelta

from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func
import redis.asyncio as aioredis

from app.models.order import Order, OrderStatus, PaymentStatus

log = logging.getLogger("alphabet.orders.fraud")

# ── Thresholds ────────────────────────────────────────────────────────────────
MAX_ORDERS_PER_HOUR      = 10
MAX_SINGLE_ORDER_KES     = Decimal("50000")
MAX_DAILY_SPEND_KES      = Decimal("200000")
NEW_ACCOUNT_MAX_KES      = Decimal("5000")    # accounts < 24h old
NEW_ACCOUNT_HOURS        = 24
MAX_DELIVERY_DISTANCE_KM = 50.0               # suspicious if far outside zone


async def check_fraud(
    customer_id: str,
    amount: Decimal,
    account_created_at: datetime,
    delivery_distance_km: float,
    db: AsyncSession,
    redis: aioredis.Redis,
) -> tuple[bool, str]:
    """
    Run all fraud checks. Returns (True, reason) if order should be blocked.
    Returns (False, "") if order is clean.
    """

    # ── Rule 1: Single transaction amount cap ─────────────────────────────────
    if amount > MAX_SINGLE_ORDER_KES:
        reason = f"Order amount KES {amount} exceeds single-transaction limit of KES {MAX_SINGLE_ORDER_KES}"
        log.warning("FRAUD blocked | rule=amount_cap | customer=%s | amount=%s", customer_id, amount)
        return True, reason

    # ── Rule 2: New account order cap ─────────────────────────────────────────
    account_age_hours = (datetime.now(timezone.utc) - account_created_at).total_seconds() / 3600
    if account_age_hours < NEW_ACCOUNT_HOURS and amount > NEW_ACCOUNT_MAX_KES:
        reason = (
            f"New account (age {account_age_hours:.1f}h) order amount "
            f"KES {amount} exceeds new-account limit of KES {NEW_ACCOUNT_MAX_KES}"
        )
        log.warning("FRAUD blocked | rule=new_account | customer=%s", customer_id)
        return True, reason

    # ── Rule 3: Order velocity — too many orders in 1 hour ────────────────────
    one_hour_ago = datetime.now(timezone.utc) - timedelta(hours=1)
    velocity_stmt = (
        select(func.count())
        .select_from(Order)
        .where(
            Order.customer_id == customer_id,
            Order.created_at  >= one_hour_ago,
            Order.payment_status != PaymentStatus.failed,
        )
    )
    recent_count = (await db.execute(velocity_stmt)).scalar_one()
    if recent_count >= MAX_ORDERS_PER_HOUR:
        reason = f"Order velocity exceeded: {recent_count} orders in the last hour"
        log.warning("FRAUD blocked | rule=velocity | customer=%s | count=%d", customer_id, recent_count)
        return True, reason

    # ── Rule 4: Daily spend cap ───────────────────────────────────────────────
    today_start = datetime.now(timezone.utc).replace(hour=0, minute=0, second=0, microsecond=0)
    daily_stmt = (
        select(func.coalesce(func.sum(Order.total), 0))
        .where(
            Order.customer_id    == customer_id,
            Order.created_at     >= today_start,
            Order.payment_status == PaymentStatus.paid,
        )
    )
    daily_spend = Decimal(str((await db.execute(daily_stmt)).scalar_one()))
    if daily_spend + amount > MAX_DAILY_SPEND_KES:
        reason = (
            f"Daily spend cap reached: already spent KES {daily_spend}, "
            f"adding KES {amount} would exceed KES {MAX_DAILY_SPEND_KES}"
        )
        log.warning("FRAUD blocked | rule=daily_cap | customer=%s | daily=%s", customer_id, daily_spend)
        return True, reason

    # ── Rule 5: Suspicious delivery distance ──────────────────────────────────
    if delivery_distance_km > MAX_DELIVERY_DISTANCE_KM:
        reason = f"Delivery distance {delivery_distance_km:.1f}km exceeds maximum {MAX_DELIVERY_DISTANCE_KM}km"
        log.warning("FRAUD blocked | rule=distance | customer=%s | km=%.1f", customer_id, delivery_distance_km)
        return True, reason

    return False, ""
