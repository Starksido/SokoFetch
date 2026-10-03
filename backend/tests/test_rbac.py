"""
RBAC test suite — verifies role enforcement and object-level authorization.

Run with:
    cd backend && pytest tests/test_rbac.py -v
"""
import pytest
from unittest.mock import AsyncMock, MagicMock, patch
from uuid import uuid4

from app.core import rbac as rbac_module
from app.core.rbac import (
    assert_owns_order,
    get_caller_profile_id,
    assert_owns_merchant,
    assert_owns_courier,
    assert_owns_customer,
    assert_can_transition,
    TRANSITION_PERMISSIONS,
)
from app.core.exceptions import ObjectAccessDeniedError


# ── Helpers ───────────────────────────────────────────────────────────────────
def make_user(role: str, user_id: str | None = None) -> dict:
    return {"sub": user_id or str(uuid4()), "role": role}


def make_order(customer_id=None, merchant_id=None, courier_id=None):
    o = MagicMock()
    o.customer_id = customer_id or uuid4()
    o.merchant_id = merchant_id or uuid4()
    o.courier_id  = courier_id
    return o


def make_merchant(user_id=None):
    m = MagicMock()
    m.user_id = user_id or uuid4()
    return m


def make_courier(user_id=None):
    c = MagicMock()
    c.user_id = user_id or uuid4()
    return c


def make_customer(user_id=None):
    c = MagicMock()
    c.user_id = user_id or uuid4()
    return c


# ── Order ownership ───────────────────────────────────────────────────────────
# Orders store PROFILE ids (customers/merchants/couriers.id); the JWT "sub" is
# the users.id. assert_owns_order must compare against the resolved profile id.
class TestOrderOwnership:
    def test_customer_owns_own_order(self):
        profile_id = str(uuid4())
        user  = make_user("customer")
        order = make_order(customer_id=profile_id)
        assert_owns_order(user, order, profile_id)   # Should not raise

    def test_customer_cannot_access_other_order(self):
        user  = make_user("customer")
        order = make_order(customer_id=str(uuid4()))   # Different customer
        with pytest.raises(ObjectAccessDeniedError):
            assert_owns_order(user, order, str(uuid4()))

    def test_customer_account_id_is_not_profile_id(self):
        # Regression: comparing the order against users.id must not grant access
        user  = make_user("customer")
        order = make_order(customer_id=user["sub"])
        with pytest.raises(ObjectAccessDeniedError):
            assert_owns_order(user, order, str(uuid4()))

    def test_merchant_owns_own_order(self):
        profile_id = str(uuid4())
        user  = make_user("merchant")
        order = make_order(merchant_id=profile_id)
        assert_owns_order(user, order, profile_id)

    def test_merchant_cannot_access_other_merchant_order(self):
        user  = make_user("merchant")
        order = make_order(merchant_id=str(uuid4()))
        with pytest.raises(ObjectAccessDeniedError):
            assert_owns_order(user, order, str(uuid4()))

    def test_courier_owns_assigned_order(self):
        profile_id = str(uuid4())
        user  = make_user("courier")
        order = make_order(courier_id=profile_id)
        assert_owns_order(user, order, profile_id)

    def test_courier_cannot_access_unassigned_order(self):
        user  = make_user("courier")
        order = make_order(courier_id=str(uuid4()))   # Different courier
        with pytest.raises(ObjectAccessDeniedError):
            assert_owns_order(user, order, str(uuid4()))

    def test_courier_cannot_access_order_with_no_courier(self):
        user  = make_user("courier")
        order = make_order(courier_id=None)
        with pytest.raises(ObjectAccessDeniedError):
            assert_owns_order(user, order, str(uuid4()))

    def test_missing_profile_is_denied(self):
        user  = make_user("customer")
        order = make_order()
        with pytest.raises(ObjectAccessDeniedError):
            assert_owns_order(user, order, None)

    def test_admin_can_access_any_order(self):
        user  = make_user("admin")
        order = make_order()
        assert_owns_order(user, order, None)   # Should not raise


# ── Caller profile resolution ─────────────────────────────────────────────────
class TestCallerProfileId:
    @pytest.mark.parametrize("role,repo_name", [
        ("customer", "CustomerRepo"),
        ("merchant", "MerchantRepo"),
        ("courier",  "CourierRepo"),
    ])
    async def test_resolves_profile_id_for_role(self, role, repo_name):
        user    = make_user(role)
        profile = MagicMock(id=uuid4())
        repo    = MagicMock()
        repo.get_by_user_id = AsyncMock(return_value=profile)
        with patch.dict(rbac_module._PROFILE_REPOS, {role: MagicMock(return_value=repo)}):
            result = await get_caller_profile_id(user, db=MagicMock())
        assert result == str(profile.id)
        repo.get_by_user_id.assert_awaited_once_with(user["sub"])

    async def test_admin_has_no_profile(self):
        assert await get_caller_profile_id(make_user("admin"), db=MagicMock()) is None

    async def test_missing_profile_is_denied(self):
        repo = MagicMock()
        repo.get_by_user_id = AsyncMock(return_value=None)
        with patch.dict(rbac_module._PROFILE_REPOS, {"customer": MagicMock(return_value=repo)}):
            with pytest.raises(ObjectAccessDeniedError):
                await get_caller_profile_id(make_user("customer"), db=MagicMock())


# ── Merchant ownership ────────────────────────────────────────────────────────
class TestMerchantOwnership:
    def test_merchant_owns_own_shop(self):
        uid      = str(uuid4())
        user     = make_user("merchant", uid)
        merchant = make_merchant(user_id=uid)
        assert_owns_merchant(user, merchant)

    def test_merchant_cannot_modify_other_shop(self):
        user     = make_user("merchant")
        merchant = make_merchant(user_id=str(uuid4()))
        with pytest.raises(ObjectAccessDeniedError):
            assert_owns_merchant(user, merchant)

    def test_customer_cannot_modify_merchant(self):
        user     = make_user("customer")
        merchant = make_merchant()
        with pytest.raises(ObjectAccessDeniedError):
            assert_owns_merchant(user, merchant)

    def test_courier_cannot_modify_merchant(self):
        user     = make_user("courier")
        merchant = make_merchant()
        with pytest.raises(ObjectAccessDeniedError):
            assert_owns_merchant(user, merchant)

    def test_admin_can_modify_any_merchant(self):
        user     = make_user("admin")
        merchant = make_merchant()
        assert_owns_merchant(user, merchant)


# ── Courier ownership ─────────────────────────────────────────────────────────
class TestCourierOwnership:
    def test_courier_owns_own_profile(self):
        uid     = str(uuid4())
        user    = make_user("courier", uid)
        courier = make_courier(user_id=uid)
        assert_owns_courier(user, courier)

    def test_courier_cannot_access_other_profile(self):
        user    = make_user("courier")
        courier = make_courier(user_id=str(uuid4()))
        with pytest.raises(ObjectAccessDeniedError):
            assert_owns_courier(user, courier)

    def test_customer_cannot_access_courier_profile(self):
        user    = make_user("customer")
        courier = make_courier()
        with pytest.raises(ObjectAccessDeniedError):
            assert_owns_courier(user, courier)

    def test_admin_can_access_any_courier(self):
        user    = make_user("admin")
        courier = make_courier()
        assert_owns_courier(user, courier)


# ── Status transition permissions ─────────────────────────────────────────────
class TestTransitionPermissions:
    def test_merchant_can_confirm(self):
        assert_can_transition(make_user("merchant"), "confirmed")

    def test_merchant_can_prepare(self):
        assert_can_transition(make_user("merchant"), "preparing")

    def test_merchant_can_mark_ready(self):
        assert_can_transition(make_user("merchant"), "ready_for_pickup")

    def test_courier_can_pick_up(self):
        assert_can_transition(make_user("courier"), "picked_up")

    def test_courier_can_mark_in_transit(self):
        assert_can_transition(make_user("courier"), "in_transit")

    def test_courier_can_deliver(self):
        assert_can_transition(make_user("courier"), "delivered")

    def test_customer_can_cancel(self):
        assert_can_transition(make_user("customer"), "cancelled")

    def test_merchant_can_cancel(self):
        assert_can_transition(make_user("merchant"), "cancelled")

    def test_customer_cannot_confirm(self):
        with pytest.raises(ObjectAccessDeniedError):
            assert_can_transition(make_user("customer"), "confirmed")

    def test_customer_cannot_deliver(self):
        with pytest.raises(ObjectAccessDeniedError):
            assert_can_transition(make_user("customer"), "delivered")

    def test_courier_cannot_confirm_order(self):
        with pytest.raises(ObjectAccessDeniedError):
            assert_can_transition(make_user("courier"), "confirmed")

    def test_merchant_cannot_deliver(self):
        with pytest.raises(ObjectAccessDeniedError):
            assert_can_transition(make_user("merchant"), "delivered")

    def test_admin_can_do_anything(self):
        for status in TRANSITION_PERMISSIONS:
            assert_can_transition(make_user("admin"), status)


# ── Order state machine ───────────────────────────────────────────────────────
class TestOrderStateMachine:
    def _make_order(self, status: str):
        from app.models.order import Order, OrderStatus
        order = MagicMock(spec=Order)
        order.status = OrderStatus(status)
        order.can_transition_to = Order.can_transition_to.__get__(order)
        return order

    def test_pending_can_go_to_confirmed(self):
        from app.models.order import OrderStatus
        order = self._make_order("pending")
        assert order.can_transition_to(OrderStatus.confirmed)

    def test_pending_can_go_to_cancelled(self):
        from app.models.order import OrderStatus
        order = self._make_order("pending")
        assert order.can_transition_to(OrderStatus.cancelled)

    def test_pending_cannot_skip_to_delivered(self):
        from app.models.order import OrderStatus
        order = self._make_order("pending")
        assert not order.can_transition_to(OrderStatus.delivered)

    def test_delivered_is_terminal(self):
        from app.models.order import OrderStatus
        order = self._make_order("delivered")
        for status in OrderStatus:
            assert not order.can_transition_to(status)

    def test_cancelled_is_terminal(self):
        from app.models.order import OrderStatus
        order = self._make_order("cancelled")
        for status in OrderStatus:
            assert not order.can_transition_to(status)
