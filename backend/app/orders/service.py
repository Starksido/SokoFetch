"""
Orders Service
==============
All order business logic lives here.
Routers call service functions; service functions use repositories and models.
"""
import hashlib
import logging
import secrets
from datetime import datetime, timezone, timedelta
from decimal import Decimal

from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
import redis.asyncio as aioredis

from app.models.order import Order, OrderStatus, PaymentMethod, PaymentStatus, VALID_TRANSITIONS
from app.models.merchant import Merchant, MenuItem, MerchantStatus
from app.models.customer import Customer
from app.models.courier import Courier, CourierStatus
from app.models.user import User
from app.core.repository import OrderRepo, MerchantRepo, CustomerRepo, MenuItemRepo, CourierRepo, UserRepo
from app.core.rbac import assert_owns_order, assert_can_transition, get_caller_profile_id
from app.core.exceptions import (
    NotFoundError, ObjectAccessDeniedError, SokoFetchException,
    PaymentBlockedError, CourierNotApprovedError
)
from app.orders.pricing import calculate_order_pricing
from app.orders.fraud import check_fraud
from app.orders import notifications
from app.schemas.order import OrderCreateRequest, OrderStatusUpdate, OrderRatingRequest

log = logging.getLogger("alphabet.orders.service")


# ── Create order ──────────────────────────────────────────────────────────────
async def create_order(
    customer_user_id: str,
    payload: OrderCreateRequest,
    db: AsyncSession,
    redis: aioredis.Redis,
) -> Order:
    """
    Full order creation flow:
      1. Validate merchant is active and open
      2. Validate all requested items exist and are available
      3. Calculate pricing (fees, surge, commission)
      4. Run fraud checks
      5. Create Order record (status=PENDING)
      6. Notify merchant
    """
    # ── 1. Resolve customer ───────────────────────────────────────────────────
    customer_repo = CustomerRepo(db)
    customer = await customer_repo.get_by_or_404(
        "Customer", user_id=customer_user_id
    )

    # ── 2. Validate merchant ──────────────────────────────────────────────────
    merchant_repo = MerchantRepo(db)
    merchant = await merchant_repo.get_or_404(payload.merchant_id, "Merchant")

    if merchant.status != MerchantStatus.active:
        raise SokoFetchException(422, "MERCHANT_UNAVAILABLE", "This merchant is not currently available.")
    if not merchant.is_open:
        raise SokoFetchException(422, "MERCHANT_CLOSED", "This merchant is currently closed.")
    if merchant.min_order_amount and Decimal(str(merchant.min_order_amount)) > Decimal("0"):
        # Will validate after subtotal is calculated
        pass

    # ── 3. Validate and snapshot items ────────────────────────────────────────
    item_repo = MenuItemRepo(db)
    item_snapshots = []
    subtotal = Decimal("0")

    for req_item in payload.items:
        menu_item = await item_repo.get_or_404(req_item.item_id, "Menu item")
        if str(menu_item.merchant_id) != str(merchant.id):
            raise SokoFetchException(422, "ITEM_WRONG_MERCHANT", f"Item {req_item.item_id} does not belong to this merchant.")
        if not menu_item.is_available:
            raise SokoFetchException(422, "ITEM_UNAVAILABLE", f"'{menu_item.name}' is currently unavailable.")

        unit_price  = Decimal(str(menu_item.effective_price))
        line_total  = unit_price * req_item.quantity
        subtotal   += line_total

        item_snapshots.append({
            "item_id":    str(menu_item.id),
            "name":       menu_item.name,
            "qty":        req_item.quantity,
            "unit_price": float(unit_price),
            "subtotal":   float(line_total),
        })

    # Min order check
    if subtotal < Decimal(str(merchant.min_order_amount or 0)):
        raise SokoFetchException(
            422, "BELOW_MINIMUM",
            f"Order total KES {subtotal} is below the minimum KES {merchant.min_order_amount}."
        )

    # ── 4. Pricing ────────────────────────────────────────────────────────────
    # Use merchant location and delivery location for distance calculation
    merchant_lat  = float(merchant.latitude  or -1.286389)  # Default: Nairobi CBD
    merchant_lon  = float(merchant.longitude or 36.817223)
    delivery_lat  = float(payload.delivery_latitude  or merchant_lat)
    delivery_lon  = float(payload.delivery_longitude or merchant_lon)

    pricing = await calculate_order_pricing(
        merchant_lat=merchant_lat,
        merchant_lon=merchant_lon,
        delivery_lat=delivery_lat,
        delivery_lon=delivery_lon,
        subtotal=subtotal,
        commission_rate=Decimal(str(merchant.commission_rate)),
        redis=redis,
    )

    # ── 5. Fraud check ────────────────────────────────────────────────────────
    user_repo = UserRepo(db)
    user = await user_repo.get_or_404(customer_user_id, "User")

    is_fraud, fraud_reason = await check_fraud(
        customer_id=str(customer.id),
        amount=pricing["total"],
        account_created_at=user.created_at,
        delivery_distance_km=pricing["distance_km"],
        db=db,
        redis=redis,
    )
    if is_fraud:
        raise PaymentBlockedError(fraud_reason)

    # ── 6. Create order record ────────────────────────────────────────────────
    estimated_pickup = datetime.now(timezone.utc) + timedelta(minutes=int(merchant.avg_prep_minutes))
    estimated_delivery = estimated_pickup + timedelta(minutes=25)

    order_repo = OrderRepo(db)
    order = await order_repo.create(
        customer_id           = str(customer.id),
        merchant_id           = str(merchant.id),
        items                 = item_snapshots,
        item_count            = sum(i["qty"] for i in item_snapshots),
        subtotal              = pricing["subtotal"],
        delivery_fee          = pricing["delivery_fee"],
        surge_multiplier      = pricing["surge_multiplier"],
        platform_fee          = pricing["platform_fee"],
        merchant_commission   = pricing["merchant_commission"],
        courier_payout        = pricing["courier_payout"],
        total                 = pricing["total"],
        payment_method        = PaymentMethod(payload.payment_method),
        payment_status        = PaymentStatus.pending,
        delivery_address      = payload.delivery_address,
        delivery_latitude     = payload.delivery_latitude,
        delivery_longitude    = payload.delivery_longitude,
        delivery_notes        = payload.delivery_notes,
        special_instructions  = payload.special_instructions,
        status                = OrderStatus.pending,
        estimated_pickup_at   = estimated_pickup,
        estimated_delivery_at = estimated_delivery,
    )

    log.info("Order created | id=%s | total=%s | customer=%s", order.id, order.total, customer_user_id)

    # ── 7. Notify merchant ────────────────────────────────────────────────────
    merchant_user = await user_repo.get(str(merchant.user_id))
    if merchant_user and merchant_user.fcm_token:
        await notifications.notify_merchant_new_order(
            merchant_token=merchant_user.fcm_token,
            order_id=str(order.id),
            item_count=order.item_count,
        )

    return order


# ── Get order ─────────────────────────────────────────────────────────────────
async def get_order(
    order_id: str,
    user: dict,
    db: AsyncSession,
) -> Order:
    """Fetch order by ID and enforce object-level access."""
    order_repo = OrderRepo(db)
    order = await order_repo.get_or_404(order_id, "Order")
    assert_owns_order(user, order, await get_caller_profile_id(user, db))
    return order


# ── List orders ───────────────────────────────────────────────────────────────
async def list_orders(
    user: dict,
    db: AsyncSession,
    offset: int = 0,
    limit: int = 20,
) -> list[Order]:
    """List orders relevant to the current user based on their role."""
    order_repo = OrderRepo(db)
    role = user["role"]

    if role == "customer":
        customer = await CustomerRepo(db).get_by_or_404("Customer", user_id=user["sub"])
        return await order_repo.get_for_customer(str(customer.id), offset, limit)

    elif role == "merchant":
        merchant = await MerchantRepo(db).get_by_or_404("Merchant", user_id=user["sub"])
        return await order_repo.get_for_merchant(str(merchant.id), offset, limit)

    elif role == "courier":
        courier = await CourierRepo(db).get_by_or_404("Courier", user_id=user["sub"])
        return await order_repo.get_for_courier(str(courier.id), offset, limit)

    return []


# ── Update order status ───────────────────────────────────────────────────────
async def update_order_status(
    order_id: str,
    payload: OrderStatusUpdate,
    user: dict,
    db: AsyncSession,
    redis: aioredis.Redis,
) -> Order:
    """
    Transition order to a new status.
    Validates:
      - Order exists and user has access
      - Transition is valid per state machine
      - User's role is allowed to drive this transition
    """
    order_repo = OrderRepo(db)
    order = await order_repo.get_or_404(order_id, "Order")
    assert_owns_order(user, order, await get_caller_profile_id(user, db))

    new_status = OrderStatus(payload.status)

    # Validate state machine
    if not order.can_transition_to(new_status):
        raise SokoFetchException(
            422, "INVALID_TRANSITION",
            f"Cannot transition from '{order.status.value}' to '{new_status.value}'."
        )

    # Validate role permission for this transition
    assert_can_transition(user, new_status.value)

    # Apply transition
    updates = {"status": new_status}

    if new_status == OrderStatus.cancelled:
        updates["cancellation_reason"] = payload.cancellation_reason

    if new_status == OrderStatus.picked_up:
        updates["picked_up_at"] = datetime.now(timezone.utc)

    if new_status == OrderStatus.delivered:
        updates["delivered_at"] = datetime.now(timezone.utc)

    order = await order_repo.update(order, **updates)
    log.info("Order status updated | id=%s | status=%s | by=%s", order_id, new_status.value, user["role"])

    # ── Notifications ─────────────────────────────────────────────────────────
    user_repo = UserRepo(db)
    customer  = await CustomerRepo(db).get(str(order.customer_id))
    merchant  = await MerchantRepo(db).get(str(order.merchant_id))

    if customer:
        customer_user = await user_repo.get(str(customer.user_id))
        token = customer_user.fcm_token if customer_user else None

        if new_status == OrderStatus.confirmed and token:
            await notifications.notify_customer_confirmed(
                token, order_id, int(merchant.avg_prep_minutes if merchant else 20)
            )
        elif new_status == OrderStatus.cancelled and token:
            await notifications.notify_customer_cancelled(
                token, order_id, payload.cancellation_reason or "Order was cancelled."
            )
        elif new_status == OrderStatus.picked_up and token:
            await notifications.notify_customer_picked_up(token, order_id)
        elif new_status == OrderStatus.delivered and token:
            await notifications.notify_customer_delivered(token, order_id)

    if new_status == OrderStatus.ready_for_pickup and merchant:
        merchant_user = await user_repo.get(str(merchant.user_id))
        if merchant_user and merchant_user.fcm_token:
            await notifications.notify_merchant_ready_for_pickup(
                merchant_user.fcm_token, order_id
            )

    return order


# ── Assign courier ────────────────────────────────────────────────────────────
async def assign_courier(
    order_id: str,
    courier_id: str,
    db: AsyncSession,
    redis: aioredis.Redis,
) -> Order:
    """
    Assign a courier to a READY_FOR_PICKUP order.
    Called by the dispatch engine — not directly by users.
    """
    order_repo  = OrderRepo(db)
    courier_repo = CourierRepo(db)

    order   = await order_repo.get_or_404(order_id, "Order")
    courier = await courier_repo.get_or_404(courier_id, "Courier")

    if not courier.is_dispatchable:
        raise CourierNotApprovedError()

    if order.status != OrderStatus.ready_for_pickup:
        raise SokoFetchException(422, "ORDER_NOT_READY", "Order is not ready for courier assignment.")

    order = await order_repo.update(order, courier_id=str(courier.id))

    # Notify courier
    user_repo = UserRepo(db)
    courier_user = await user_repo.get(str(courier.user_id))
    merchant = await MerchantRepo(db).get(str(order.merchant_id))

    if courier_user and courier_user.fcm_token:
        await notifications.notify_courier_dispatch(
            courier_user.fcm_token,
            order_id=order_id,
            merchant_name=merchant.shop_name if merchant else "Merchant",
            earnings=str(order.courier_payout or "0"),
        )

    log.info("Courier assigned | order=%s | courier=%s", order_id, courier_id)
    return order


# ── Proof of delivery ─────────────────────────────────────────────────────────
async def submit_proof_of_delivery(
    order_id: str,
    proof_type: str,
    courier_user_id: str,
    otp_code: str | None,
    photo_url: str | None,
    db: AsyncSession,
) -> Order:
    """Courier submits proof; triggers DELIVERED status if valid."""
    order_repo   = OrderRepo(db)
    courier_repo = CourierRepo(db)

    order   = await order_repo.get_or_404(order_id, "Order")
    courier = await courier_repo.get_by_or_404("Courier", user_id=courier_user_id)

    # Verify this courier is assigned to this order
    if str(order.courier_id) != str(courier.id):
        raise ObjectAccessDeniedError()

    if order.status != OrderStatus.in_transit:
        raise SokoFetchException(422, "ORDER_NOT_IN_TRANSIT", "Order must be IN_TRANSIT to submit proof.")

    if proof_type == "otp":
        if not otp_code:
            raise SokoFetchException(400, "OTP_REQUIRED", "OTP code is required for OTP proof.")
        # In production: compare against a hashed OTP stored when the order was placed
        # For now we store it directly (hash it in production)
        updates = {
            "proof_type":          "otp",
            "proof_otp":           hashlib.sha256(otp_code.encode()).hexdigest()[:16],
            "proof_submitted_at":  datetime.now(timezone.utc),
            "status":              OrderStatus.delivered,
            "delivered_at":        datetime.now(timezone.utc),
        }
    elif proof_type == "photo":
        if not photo_url:
            raise SokoFetchException(400, "PHOTO_REQUIRED", "Photo URL is required for photo proof.")
        updates = {
            "proof_type":          "photo",
            "proof_photo_url":     photo_url,
            "proof_submitted_at":  datetime.now(timezone.utc),
            "status":              OrderStatus.delivered,
            "delivered_at":        datetime.now(timezone.utc),
        }
    else:
        raise SokoFetchException(400, "INVALID_PROOF_TYPE", "Proof type must be 'otp' or 'photo'.")

    order = await order_repo.update(order, **updates)

    # Update courier delivery count
    await courier_repo.update(courier, total_deliveries=courier.total_deliveries + 1)

    log.info("Proof submitted | order=%s | type=%s", order_id, proof_type)
    return order


# ── Rate order ────────────────────────────────────────────────────────────────
async def rate_order(
    order_id: str,
    customer_user_id: str,
    payload: OrderRatingRequest,
    db: AsyncSession,
) -> Order:
    """Customer rates the courier and/or merchant after delivery."""
    order_repo   = OrderRepo(db)
    customer_repo = CustomerRepo(db)

    order    = await order_repo.get_or_404(order_id, "Order")
    customer = await customer_repo.get_by_or_404("Customer", user_id=customer_user_id)

    if str(order.customer_id) != str(customer.id):
        raise ObjectAccessDeniedError()

    if order.status != OrderStatus.delivered:
        raise SokoFetchException(422, "NOT_DELIVERED", "Can only rate a delivered order.")

    if order.customer_rating is not None:
        raise SokoFetchException(409, "ALREADY_RATED", "Order has already been rated.")

    order = await order_repo.update(
        order,
        customer_rating  = payload.courier_rating,
        merchant_rating  = payload.merchant_rating,
        customer_review  = payload.review,
    )

    # Update courier running average
    if payload.courier_rating and order.courier_id:
        courier_repo = CourierRepo(db)
        courier = await courier_repo.get(str(order.courier_id))
        if courier:
            total_ratings = courier.rating_count + 1
            new_avg = (
                Decimal(str(courier.rating)) * courier.rating_count
                + Decimal(str(payload.courier_rating))
            ) / total_ratings
            await courier_repo.update(
                courier,
                rating=new_avg.quantize(Decimal("0.01")),
                rating_count=total_ratings,
            )

    # Update merchant running average
    if payload.merchant_rating and order.merchant_id:
        merchant_repo = MerchantRepo(db)
        merchant = await merchant_repo.get(str(order.merchant_id))
        if merchant:
            total_ratings = merchant.rating_count + 1
            new_avg = (
                Decimal(str(merchant.rating)) * merchant.rating_count
                + Decimal(str(payload.merchant_rating))
            ) / total_ratings
            await merchant_repo.update(
                merchant,
                rating=new_avg.quantize(Decimal("0.01")),
                rating_count=total_ratings,
            )

    log.info("Order rated | id=%s | courier_rating=%s", order_id, payload.courier_rating)
    return order
