"""
Order event notifications.
Sends FCM push notifications to the relevant party on every status change.
Falls back gracefully if Firebase is not configured.
"""
import logging
from typing import Optional

log = logging.getLogger("alphabet.orders.notifications")


def _get_messaging():
    """Lazy Firebase init — only fails if actually used without config."""
    try:
        import firebase_admin
        from firebase_admin import messaging
        return messaging
    except ImportError:
        return None


async def _send(token: Optional[str], title: str, body: str, data: dict = {}):
    if not token:
        return
    messaging = _get_messaging()
    if not messaging:
        log.warning("Firebase not configured — skipping push: %s", title)
        return
    try:
        import firebase_admin
        from firebase_admin import messaging as fb_msg
        msg = fb_msg.Message(
            notification=fb_msg.Notification(title=title, body=body),
            data={k: str(v) for k, v in data.items()},
            token=token,
        )
        fb_msg.send(msg)
        log.info("Push sent | title=%s", title)
    except Exception as exc:
        log.error("Push failed | title=%s | error=%s", title, exc)


# ── One function per order event ──────────────────────────────────────────────
async def notify_merchant_new_order(merchant_token: str, order_id: str, item_count: int):
    await _send(
        merchant_token,
        title="🔔 New Order!",
        body=f"You have a new order — {item_count} item(s). Tap to accept.",
        data={"order_id": order_id, "event": "new_order"},
    )


async def notify_customer_confirmed(customer_token: str, order_id: str, prep_minutes: int):
    await _send(
        customer_token,
        title="✅ Order Confirmed",
        body=f"Your order has been accepted! Ready in about {prep_minutes} minutes.",
        data={"order_id": order_id, "event": "confirmed"},
    )


async def notify_customer_cancelled(customer_token: str, order_id: str, reason: str):
    await _send(
        customer_token,
        title="❌ Order Cancelled",
        body=reason or "Your order was cancelled.",
        data={"order_id": order_id, "event": "cancelled"},
    )


async def notify_courier_dispatch(courier_token: str, order_id: str, merchant_name: str, earnings: str):
    await _send(
        courier_token,
        title="🛵 New Delivery",
        body=f"Pickup from {merchant_name}. Earn KES {earnings}. 45s to accept.",
        data={"order_id": order_id, "event": "dispatch"},
    )


async def notify_customer_picked_up(customer_token: str, order_id: str):
    await _send(
        customer_token,
        title="🛵 Order Picked Up",
        body="Your order is on the way! Track it live.",
        data={"order_id": order_id, "event": "picked_up"},
    )


async def notify_customer_delivered(customer_token: str, order_id: str):
    await _send(
        customer_token,
        title="🎉 Delivered!",
        body="Your order has arrived. Enjoy! Please rate your experience.",
        data={"order_id": order_id, "event": "delivered"},
    )


async def notify_merchant_ready_for_pickup(merchant_token: str, order_id: str):
    await _send(
        merchant_token,
        title="📦 Rider Arriving",
        body="A rider is heading your way for order pickup.",
        data={"order_id": order_id, "event": "rider_arriving"},
    )
