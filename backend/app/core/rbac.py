"""
RBAC — Object-Level Authorization
===================================
Role checks (customer / merchant / courier) are done in guards.py via JWT.
THIS file handles the second layer: "Can THIS specific user access THIS specific record?"

Rules:
  - Customer  → can only touch their own orders, their own profile, their own addresses
  - Merchant  → can only touch their own shop, their own orders, their own menu
  - Courier   → can only touch orders assigned to them, their own profile/docs/earnings
  - Admin     → no restrictions (enforced separately via require_role("admin"))

Usage in route handlers:
    from app.core.rbac import assert_owns_order, assert_owns_merchant

    @router.get("/orders/{order_id}")
    async def get_order(order_id: str, user = Depends(get_current_user), db = Depends(get_db)):
        order = await get_order_or_404(order_id, db)
        assert_owns_order(user, order)   # raises 403 if not authorised
        return order
"""

from app.core.exceptions import ObjectAccessDeniedError


# ── Order ownership ───────────────────────────────────────────────────────────
def assert_owns_order(user: dict, order) -> None:
    """
    A user can view/act on an order only if they are:
      - The customer who placed it
      - The merchant who received it
      - The courier it was assigned to
      - An admin
    """
    if user["role"] == "admin":
        return

    user_id = user["sub"]

    if user["role"] == "customer":
        if str(order.customer_id) != user_id:
            raise ObjectAccessDeniedError()

    elif user["role"] == "merchant":
        if str(order.merchant_id) != user_id:
            raise ObjectAccessDeniedError()

    elif user["role"] == "courier":
        if order.courier_id is None or str(order.courier_id) != user_id:
            raise ObjectAccessDeniedError()


# ── Merchant ownership ────────────────────────────────────────────────────────
def assert_owns_merchant(user: dict, merchant) -> None:
    """Merchant can only modify their own shop."""
    if user["role"] == "admin":
        return
    if user["role"] != "merchant":
        raise ObjectAccessDeniedError()
    if str(merchant.user_id) != user["sub"]:
        raise ObjectAccessDeniedError()


# ── Menu item ownership ───────────────────────────────────────────────────────
def assert_owns_menu_item(user: dict, item, merchant) -> None:
    """Menu item belongs to a merchant — check via merchant ownership."""
    assert_owns_merchant(user, merchant)
    if str(item.merchant_id) != str(merchant.id):
        raise ObjectAccessDeniedError()


# ── Courier profile ownership ─────────────────────────────────────────────────
def assert_owns_courier(user: dict, courier) -> None:
    """Courier can only access their own profile and documents."""
    if user["role"] == "admin":
        return
    if user["role"] != "courier":
        raise ObjectAccessDeniedError()
    if str(courier.user_id) != user["sub"]:
        raise ObjectAccessDeniedError()


# ── Customer profile ownership ────────────────────────────────────────────────
def assert_owns_customer(user: dict, customer) -> None:
    """Customer can only access their own profile and addresses."""
    if user["role"] == "admin":
        return
    if user["role"] != "customer":
        raise ObjectAccessDeniedError()
    if str(customer.user_id) != user["sub"]:
        raise ObjectAccessDeniedError()


# ── Delivery address ownership ────────────────────────────────────────────────
def assert_owns_address(user: dict, address, customer) -> None:
    """Address must belong to the authenticated customer."""
    assert_owns_customer(user, customer)
    if str(address.customer_id) != str(customer.id):
        raise ObjectAccessDeniedError()


# ── Status transition permissions ─────────────────────────────────────────────
# Who is allowed to drive which state transitions
TRANSITION_PERMISSIONS: dict[str, set[str]] = {
    # status → {roles that can trigger it}
    "confirmed":        {"merchant"},
    "preparing":        {"merchant"},
    "ready_for_pickup": {"merchant"},
    "picked_up":        {"courier"},
    "in_transit":       {"courier"},
    "delivered":        {"courier"},
    "cancelled":        {"customer", "merchant", "admin"},
    "delivery_failed":  {"courier", "admin"},
}


def assert_can_transition(user: dict, new_status: str) -> None:
    """
    Check that the user's role is permitted to drive this status change.
    Raises ObjectAccessDeniedError if not permitted.
    """
    allowed_roles = TRANSITION_PERMISSIONS.get(new_status, set())
    if user["role"] not in allowed_roles and user["role"] != "admin":
        raise ObjectAccessDeniedError()
