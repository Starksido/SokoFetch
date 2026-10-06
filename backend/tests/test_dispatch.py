"""
Dispatch tests — couriers see available jobs and accept them.

Run with:
    cd backend && pytest tests/test_dispatch.py -v
"""
import pytest
from datetime import datetime, timezone
from decimal import Decimal
from unittest.mock import AsyncMock, MagicMock, patch
from uuid import uuid4


def _repo(**methods):
    r = MagicMock()
    for name, value in methods.items():
        setattr(r, name, AsyncMock(return_value=value))
    return r


def _result(scalar=None, rows=None):
    r = MagicMock()
    r.scalar_one_or_none.return_value = scalar
    r.all.return_value = rows or []
    return r


def _db(*results):
    db = MagicMock()
    db.execute = AsyncMock(side_effect=list(results))
    db.refresh = AsyncMock()
    return db


def _courier(approved=True, online=True, lat=-1.2864, lon=36.8172):
    from app.models.courier import CourierStatus
    c = MagicMock(id=uuid4(), is_online=online, last_latitude=lat, last_longitude=lon)
    c.status = CourierStatus.active if approved else CourierStatus.documents_submitted
    c.documents_verified_at = datetime.now(timezone.utc) if approved else None
    c.is_dispatchable = approved and online
    return c


def _job(lat, lon, name="Shop"):
    from app.models.order import OrderStatus
    order = MagicMock(id=uuid4(), status=OrderStatus.preparing, item_count=2,
                      courier_payout=Decimal("82.00"), delivery_latitude=-1.30,
                      delivery_longitude=36.80, created_at=datetime.now(timezone.utc))
    merchant = MagicMock(shop_name=name, address=f"{name} St", latitude=lat, longitude=lon)
    return order, merchant


# ── Claiming an order ─────────────────────────────────────────────────────────
class TestAssignCourier:
    async def _assign(self, courier, claimed_id):
        from app.orders import service
        order = MagicMock(id=uuid4())
        db = _db(_result(scalar=claimed_id))
        with patch("app.orders.service.CourierRepo", return_value=_repo(get_or_404=courier)), \
             patch("app.orders.service.OrderRepo", return_value=_repo(get_or_404=order)):
            result = await service.assign_courier(str(order.id), str(courier.id), db)
        return result, db

    async def test_claim_succeeds(self):
        result, db = await self._assign(_courier(), uuid4())
        db.refresh.assert_awaited_once_with(result)

    async def test_claim_is_a_single_conditional_update(self):
        # The WHERE clause is what makes two simultaneous accepts safe
        _, db = await self._assign(_courier(), uuid4())
        sql = str(db.execute.await_args.args[0])
        assert sql.startswith("UPDATE orders")
        assert "orders.courier_id IS NULL" in sql
        assert "orders.payment_status" in sql
        assert "orders.status IN" in sql

    async def test_already_taken_is_409(self):
        from app.core.exceptions import SokoFetchException
        with pytest.raises(SokoFetchException) as exc:
            await self._assign(_courier(), None)
        assert exc.value.status_code == 409
        assert exc.value.detail["code"] == "JOB_TAKEN"

    async def test_unapproved_courier_refused(self):
        from app.core.exceptions import CourierNotApprovedError
        with pytest.raises(CourierNotApprovedError):
            await self._assign(_courier(approved=False), uuid4())


# ── Job board ─────────────────────────────────────────────────────────────────
class TestListJobs:
    async def _list(self, courier, db):
        from app.courier import service
        with patch("app.courier.service.CourierRepo", return_value=_repo(get_by_or_404=courier)):
            return await service.list_jobs("u", db)

    async def test_nearest_shop_first_unknown_distance_last(self):
        far   = _job(-1.2000, 36.9000, "Far")
        near  = _job(-1.2870, 36.8180, "Near")
        nowhere = _job(None, None, "Unknown")
        db = _db(_result(scalar=None), _result(rows=[far, nowhere, near]))
        jobs = await self._list(_courier(), db)
        assert [j["merchant_name"] for j in jobs] == ["Near", "Far", "Unknown"]
        assert jobs[0]["pickup_distance_km"] < jobs[1]["pickup_distance_km"]
        assert jobs[2]["pickup_distance_km"] is None

    async def test_customer_address_not_shown_before_accepting(self):
        db = _db(_result(scalar=None), _result(rows=[_job(-1.287, 36.818)]))
        jobs = await self._list(_courier(), db)
        assert "delivery_address" not in jobs[0]
        assert jobs[0]["delivery_distance_km"] is not None

    async def test_only_unassigned_paid_orders_queried(self):
        db = _db(_result(scalar=None), _result(rows=[]))
        await self._list(_courier(), db)
        sql = str(db.execute.await_args_list[1].args[0])
        assert "orders.courier_id IS NULL" in sql
        assert "orders.payment_status" in sql

    async def test_empty_while_on_a_delivery(self):
        db = _db(_result(scalar=MagicMock()))   # Has an active order
        assert await self._list(_courier(), db) == []
        assert db.execute.await_count == 1

    async def test_unapproved_courier_refused(self):
        from app.core.exceptions import CourierNotApprovedError
        with pytest.raises(CourierNotApprovedError):
            await self._list(_courier(approved=False), _db())

    async def test_offline_courier_refused(self):
        from app.core.exceptions import SokoFetchException
        with pytest.raises(SokoFetchException) as exc:
            await self._list(_courier(online=False), _db())
        assert exc.value.detail["code"] == "OFFLINE"


# ── Accepting ─────────────────────────────────────────────────────────────────
class TestAcceptJob:
    def _redis(self, locked=False):
        store = {"courier_accept_lock:x": "1"} if locked else {}
        r = MagicMock()

        async def set_(key, value, nx=False, ex=None):
            if nx and store:
                return None
            store[key] = value
            return True

        async def delete(key):
            store.pop(key, None)

        r.set, r.delete = set_, delete
        return r, store

    async def _accept(self, courier, db, redis, assign=None):
        from app.courier import service
        assign = assign or AsyncMock()
        with patch("app.courier.service.CourierRepo", return_value=_repo(get_by_or_404=courier)), \
             patch("app.courier.service.assign_courier", new=assign), \
             patch("app.courier.service.get_active_order", new=AsyncMock(return_value={"id": "o"})):
            return await service.accept_job("u", str(uuid4()), db, redis), assign

    async def test_accept_assigns_and_releases_lock(self):
        redis, store = self._redis()
        courier = _courier()
        result, assign = await self._accept(courier, _db(_result(scalar=None)), redis)
        assert result == {"id": "o"}
        assert assign.await_args.args[1] == str(courier.id)
        assert store == {}

    async def test_second_job_refused_while_on_a_delivery(self):
        from app.core.exceptions import SokoFetchException
        redis, store = self._redis()
        with pytest.raises(SokoFetchException) as exc:
            await self._accept(_courier(), _db(_result(scalar=MagicMock())), redis)
        assert exc.value.detail["code"] == "ALREADY_ON_A_JOB"
        assert store == {}   # Lock released on failure too

    async def test_double_tap_refused(self):
        from app.core.exceptions import SokoFetchException
        redis, _ = self._redis(locked=True)
        assign = AsyncMock()
        with pytest.raises(SokoFetchException) as exc:
            await self._accept(_courier(), _db(), redis, assign)
        assert exc.value.detail["code"] == "ACCEPT_IN_PROGRESS"
        assign.assert_not_awaited()

    async def test_lock_released_when_job_taken(self):
        from app.core.exceptions import SokoFetchException
        redis, store = self._redis()
        taken = AsyncMock(side_effect=SokoFetchException(409, "JOB_TAKEN", "gone"))
        with pytest.raises(SokoFetchException):
            await self._accept(_courier(), _db(_result(scalar=None)), redis, taken)
        assert store == {}


# ── Active order now carries the pick-up details ──────────────────────────────
class TestActiveOrder:
    def _order(self, status):
        from app.models.order import OrderStatus, PaymentStatus
        now = datetime.now(timezone.utc)
        return MagicMock(
            id=uuid4(), customer_id=uuid4(), merchant_id=uuid4(), courier_id=uuid4(),
            items=[], item_count=1, subtotal=Decimal("100"), delivery_fee=Decimal("60"),
            surge_multiplier=Decimal("1"), platform_fee=Decimal("10"),
            merchant_commission=Decimal("20"), courier_payout=Decimal("50"),
            total=Decimal("160"), payment_method="mpesa", payment_status=PaymentStatus.paid.value,
            payment_ref=None, delivery_address="Westlands", delivery_latitude=None,
            delivery_longitude=None, delivery_notes=None, special_instructions=None,
            status=OrderStatus(status).value, cancellation_reason=None, proof_type=None,
            estimated_pickup_at=None, estimated_delivery_at=None, picked_up_at=None,
            delivered_at=None, customer_rating=None, merchant_rating=None,
            created_at=now, updated_at=now,
        )

    async def test_includes_shop_pickup_details(self):
        # Regression: the courier app reads merchant_name/address/lat/lon but
        # the endpoint never sent them, so riders had no pick-up address
        from app.courier import service
        merchant = MagicMock(shop_name="Mama Mboga", address="Moi Ave",
                             latitude=Decimal("-1.28"), longitude=Decimal("36.82"))
        db = _db(_result(scalar=self._order("preparing")))
        with patch("app.courier.service.CourierRepo", return_value=_repo(get_by_or_404=_courier())), \
             patch("app.courier.service.MerchantRepo", return_value=_repo(get=merchant)):
            active = await service.get_active_order("u", db)
        assert active["merchant_name"] == "Mama Mboga"
        assert active["merchant_address"] == "Moi Ave"
        assert active["merchant_lat"] == Decimal("-1.28")

    def test_accepted_while_preparing_counts_as_active(self):
        from app.courier.service import ACTIVE_ORDER_STATUSES
        from app.models.order import OrderStatus
        assert OrderStatus.confirmed in ACTIVE_ORDER_STATUSES
        assert OrderStatus.preparing in ACTIVE_ORDER_STATUSES
        assert OrderStatus.delivered not in ACTIVE_ORDER_STATUSES

    def test_routes_registered(self):
        from app.main import app
        paths = app.openapi()["paths"]
        assert "get" in paths["/courier/jobs"]
        assert "post" in paths["/courier/jobs/{order_id}/accept"]
