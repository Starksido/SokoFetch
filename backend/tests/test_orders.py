"""
Orders test suite — pricing, fraud detection, state machine, and service logic.

Run with:
    cd backend && pytest tests/test_orders.py -v
"""
import pytest
from decimal import Decimal
from datetime import datetime, timezone, timedelta
from unittest.mock import AsyncMock, MagicMock, patch
from uuid import uuid4


# ══════════════════════════════════════════════════════════════════════════════
# PRICING TESTS
# ══════════════════════════════════════════════════════════════════════════════
class TestPricing:

    def test_base_fee_minimum(self):
        from app.orders.pricing import calculate_base_fee
        fee = calculate_base_fee(0.0)
        assert fee == Decimal("60.00")

    def test_base_fee_1km(self):
        from app.orders.pricing import calculate_base_fee
        # 60 + 15*1 = 75
        fee = calculate_base_fee(1.0)
        assert fee == Decimal("75.00")

    def test_base_fee_5km(self):
        from app.orders.pricing import calculate_base_fee
        # 60 + 15*5 = 135
        fee = calculate_base_fee(5.0)
        assert fee == Decimal("135.00")

    def test_base_fee_caps_at_300(self):
        from app.orders.pricing import calculate_base_fee
        # Very long distance should cap at 300
        fee = calculate_base_fee(100.0)
        assert fee == Decimal("300.00")

    def test_platform_retainer_split(self):
        from app.orders.pricing import split_delivery_fee
        platform, courier = split_delivery_fee(Decimal("100.00"))
        assert platform == Decimal("18.00")   # 18%
        assert courier  == Decimal("82.00")   # 82%

    def test_split_adds_up(self):
        from app.orders.pricing import split_delivery_fee
        for amount in ["60.00", "120.00", "135.50", "300.00"]:
            p, c = split_delivery_fee(Decimal(amount))
            assert p + c == Decimal(amount)

    def test_haversine_nairobi_cbd_to_westlands(self):
        """Nairobi CBD (-1.2864, 36.8172) to Westlands (-1.2673, 36.8062) ≈ 2.4km"""
        from app.orders.pricing import _haversine_km
        dist = _haversine_km(-1.2864, 36.8172, -1.2673, 36.8062)
        assert 2.0 < dist < 3.0

    def test_haversine_same_point_is_zero(self):
        from app.orders.pricing import _haversine_km
        dist = _haversine_km(-1.2864, 36.8172, -1.2864, 36.8172)
        assert dist == 0.0

    @pytest.mark.asyncio
    async def test_no_surge_when_no_flags(self):
        from app.orders.pricing import get_surge_multiplier
        redis = AsyncMock()
        redis.get = AsyncMock(return_value=None)
        multiplier = await get_surge_multiplier(redis)
        assert multiplier == Decimal("1.0")

    @pytest.mark.asyncio
    async def test_high_demand_surge(self):
        from app.orders.pricing import get_surge_multiplier
        redis = AsyncMock()

        async def fake_get(key):
            return "1" if key == "surge:high_demand" else None

        redis.get = fake_get
        multiplier = await get_surge_multiplier(redis)
        assert multiplier == Decimal("1.3")

    @pytest.mark.asyncio
    async def test_multiple_surges_picks_highest(self):
        from app.orders.pricing import get_surge_multiplier
        redis = AsyncMock()
        redis.get = AsyncMock(return_value="1")  # All surges active
        multiplier = await get_surge_multiplier(redis)
        assert multiplier == Decimal("1.8")      # low_couriers is highest

    @pytest.mark.asyncio
    async def test_surge_caps_at_2x(self):
        """Even if somehow 3 surges overlap, cap at 2.0."""
        from app.orders.pricing import get_surge_multiplier, MAX_SURGE
        redis = AsyncMock()
        redis.get = AsyncMock(return_value="1")
        multiplier = await get_surge_multiplier(redis)
        assert multiplier <= MAX_SURGE

    @pytest.mark.asyncio
    async def test_full_pricing_calculation(self):
        from app.orders.pricing import calculate_order_pricing
        redis = AsyncMock()
        redis.get = AsyncMock(return_value=None)  # No surge

        result = await calculate_order_pricing(
            merchant_lat=-1.2864,
            merchant_lon=36.8172,
            delivery_lat=-1.2673,
            delivery_lon=36.8062,
            subtotal=Decimal("850.00"),
            commission_rate=Decimal("20.00"),
            redis=redis,
        )

        assert result["subtotal"]           == Decimal("850.00")
        assert result["merchant_commission"]== Decimal("170.00")   # 20% of 850
        assert result["surge_multiplier"]   == Decimal("1.0")
        assert result["total"]              == result["subtotal"] + result["delivery_fee"]
        assert result["platform_fee"] + result["courier_payout"] == result["delivery_fee"]
        assert result["distance_km"] > 0


# ══════════════════════════════════════════════════════════════════════════════
# FRAUD DETECTION TESTS
# ══════════════════════════════════════════════════════════════════════════════
class TestFraud:

    def _make_db(self, order_count=0, daily_spend=0):
        """Mock DB that returns fixed values for fraud queries."""
        db = AsyncMock()
        execute_result = MagicMock()
        execute_result.scalar_one = MagicMock(side_effect=[order_count, daily_spend])
        db.execute = AsyncMock(return_value=execute_result)
        return db

    @pytest.mark.asyncio
    async def test_clean_order_passes(self):
        from app.orders.fraud import check_fraud
        db    = self._make_db(order_count=0, daily_spend=0)
        redis = AsyncMock()
        is_fraud, reason = await check_fraud(
            customer_id=str(uuid4()),
            amount=Decimal("500.00"),
            account_created_at=datetime.now(timezone.utc) - timedelta(days=7),
            delivery_distance_km=3.5,
            db=db,
            redis=redis,
        )
        assert is_fraud is False
        assert reason == ""

    @pytest.mark.asyncio
    async def test_amount_cap_blocks(self):
        from app.orders.fraud import check_fraud, MAX_SINGLE_ORDER_KES
        db    = self._make_db()
        redis = AsyncMock()
        is_fraud, reason = await check_fraud(
            customer_id=str(uuid4()),
            amount=MAX_SINGLE_ORDER_KES + Decimal("1"),
            account_created_at=datetime.now(timezone.utc) - timedelta(days=30),
            delivery_distance_km=2.0,
            db=db,
            redis=redis,
        )
        assert is_fraud is True
        assert "limit" in reason.lower()

    @pytest.mark.asyncio
    async def test_new_account_high_value_blocked(self):
        from app.orders.fraud import check_fraud, NEW_ACCOUNT_MAX_KES
        db    = self._make_db()
        redis = AsyncMock()
        is_fraud, reason = await check_fraud(
            customer_id=str(uuid4()),
            amount=NEW_ACCOUNT_MAX_KES + Decimal("1"),
            account_created_at=datetime.now(timezone.utc) - timedelta(hours=2),  # New account
            delivery_distance_km=2.0,
            db=db,
            redis=redis,
        )
        assert is_fraud is True
        assert "new account" in reason.lower()

    @pytest.mark.asyncio
    async def test_old_account_high_value_allowed(self):
        """Accounts older than 24h don't hit the new-account cap."""
        from app.orders.fraud import check_fraud, NEW_ACCOUNT_MAX_KES
        db    = self._make_db(order_count=0, daily_spend=0)
        redis = AsyncMock()
        is_fraud, _ = await check_fraud(
            customer_id=str(uuid4()),
            amount=NEW_ACCOUNT_MAX_KES + Decimal("1"),
            account_created_at=datetime.now(timezone.utc) - timedelta(hours=25),
            delivery_distance_km=2.0,
            db=db,
            redis=redis,
        )
        assert is_fraud is False

    @pytest.mark.asyncio
    async def test_velocity_block(self):
        from app.orders.fraud import check_fraud, MAX_ORDERS_PER_HOUR
        db    = self._make_db(order_count=MAX_ORDERS_PER_HOUR, daily_spend=0)
        redis = AsyncMock()
        is_fraud, reason = await check_fraud(
            customer_id=str(uuid4()),
            amount=Decimal("500.00"),
            account_created_at=datetime.now(timezone.utc) - timedelta(days=30),
            delivery_distance_km=2.0,
            db=db,
            redis=redis,
        )
        assert is_fraud is True
        assert "velocity" in reason.lower()

    @pytest.mark.asyncio
    async def test_daily_cap_block(self):
        from app.orders.fraud import check_fraud, MAX_DAILY_SPEND_KES
        db    = self._make_db(order_count=0, daily_spend=int(MAX_DAILY_SPEND_KES))
        redis = AsyncMock()
        is_fraud, reason = await check_fraud(
            customer_id=str(uuid4()),
            amount=Decimal("500.00"),
            account_created_at=datetime.now(timezone.utc) - timedelta(days=30),
            delivery_distance_km=2.0,
            db=db,
            redis=redis,
        )
        assert is_fraud is True
        assert "daily" in reason.lower()

    @pytest.mark.asyncio
    async def test_distance_block(self):
        from app.orders.fraud import check_fraud, MAX_DELIVERY_DISTANCE_KM
        db    = self._make_db(order_count=0, daily_spend=0)
        redis = AsyncMock()
        is_fraud, reason = await check_fraud(
            customer_id=str(uuid4()),
            amount=Decimal("500.00"),
            account_created_at=datetime.now(timezone.utc) - timedelta(days=30),
            delivery_distance_km=MAX_DELIVERY_DISTANCE_KM + 1,
            db=db,
            redis=redis,
        )
        assert is_fraud is True
        assert "distance" in reason.lower()


# ══════════════════════════════════════════════════════════════════════════════
# ORDER STATE MACHINE (service-level)
# ══════════════════════════════════════════════════════════════════════════════
class TestOrderStateTransitions:

    def _make_order(self, status: str, customer_id=None, merchant_id=None, courier_id=None):
        from app.models.order import Order, OrderStatus
        order = MagicMock(spec=Order)
        order.id          = uuid4()
        order.status      = OrderStatus(status)
        order.customer_id = customer_id or uuid4()
        order.merchant_id = merchant_id or uuid4()
        order.courier_id  = courier_id
        order.courier_payout = Decimal("82.00")
        order.item_count  = 2
        order.can_transition_to = Order.can_transition_to.__get__(order)
        return order

    def test_merchant_can_confirm_pending(self):
        from app.models.order import OrderStatus
        order = self._make_order("pending")
        assert order.can_transition_to(OrderStatus.confirmed)

    def test_cannot_skip_preparing_to_delivered(self):
        from app.models.order import OrderStatus
        order = self._make_order("preparing")
        assert not order.can_transition_to(OrderStatus.delivered)

    def test_cannot_reopen_delivered(self):
        from app.models.order import OrderStatus
        order = self._make_order("delivered")
        for s in OrderStatus:
            assert not order.can_transition_to(s)

    def test_cannot_cancel_after_in_transit(self):
        from app.models.order import OrderStatus
        order = self._make_order("in_transit")
        assert not order.can_transition_to(OrderStatus.cancelled)

    def test_can_cancel_from_confirmed(self):
        from app.models.order import OrderStatus
        order = self._make_order("confirmed")
        assert order.can_transition_to(OrderStatus.cancelled)


# ══════════════════════════════════════════════════════════════════════════════
# NOTIFICATION DISPATCH
# ══════════════════════════════════════════════════════════════════════════════
class TestNotifications:

    @pytest.mark.asyncio
    async def test_no_crash_without_firebase(self):
        """Notifications should fail silently when Firebase is not configured."""
        from app.orders.notifications import notify_merchant_new_order
        # Should not raise even without Firebase
        await notify_merchant_new_order("fake_token", str(uuid4()), 3)

    @pytest.mark.asyncio
    async def test_no_crash_with_null_token(self):
        from app.orders.notifications import notify_customer_confirmed
        # None token should be a no-op
        await notify_customer_confirmed(None, str(uuid4()), 20)


# ══════════════════════════════════════════════════════════════════════════════
# RATING SYSTEM
# ══════════════════════════════════════════════════════════════════════════════
class TestRatingCalculation:

    def test_rating_average_first_rating(self):
        """First rating: average = the rating itself."""
        from decimal import Decimal
        current_avg   = Decimal("0.00")
        current_count = 0
        new_rating    = 4

        new_count = current_count + 1
        new_avg   = (current_avg * current_count + Decimal(str(new_rating))) / new_count
        assert new_avg == Decimal("4")

    def test_rating_average_multiple(self):
        """After 4 ratings of 5,4,3,4 → avg = 4.0"""
        from decimal import Decimal
        ratings = [5, 4, 3, 4]
        avg     = Decimal("0")
        count   = 0
        for r in ratings:
            count += 1
            avg = (avg * (count - 1) + Decimal(str(r))) / count
        assert avg == Decimal("4.0")

    def test_rating_out_of_bounds_caught_by_schema(self):
        from app.schemas.order import OrderRatingRequest
        import pydantic
        with pytest.raises(pydantic.ValidationError):
            OrderRatingRequest(courier_rating=6)   # Max is 5

        with pytest.raises(pydantic.ValidationError):
            OrderRatingRequest(courier_rating=0)   # Min is 1
