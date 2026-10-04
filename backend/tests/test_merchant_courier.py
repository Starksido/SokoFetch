"""
Merchant & courier service tests — response loading and public data exposure.

Run with:
    cd backend && pytest tests/test_merchant_courier.py -v
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


def _db():
    db = MagicMock()
    db.refresh = AsyncMock()
    return db


# ── Relationship loading before serialisation ─────────────────────────────────
# MerchantDetail / CourierProfileResponse serialise relationships; a lazy load
# during response serialisation raises MissingGreenlet (→ 500) under
# AsyncSession, so services must load them explicitly before returning.
class TestRelationshipsLoadedBeforeReturn:
    async def test_onboard_merchant_loads_menu(self):
        from app.merchant import service
        merchant = MagicMock(id=uuid4(), shop_name="Mama Mboga")
        payload = MagicMock(category="grocery")
        db = _db()
        with patch("app.merchant.service.MerchantRepo", return_value=_repo(get_by=None, create=merchant)):
            await service.onboard_merchant(str(uuid4()), payload, db)
        db.refresh.assert_awaited_once_with(merchant, attribute_names=["menu_items"])

    async def test_update_merchant_loads_menu(self):
        from app.merchant import service
        merchant = MagicMock(id=uuid4())
        payload = MagicMock()
        payload.model_dump.return_value = {"shop_name": "New name"}
        db = _db()
        with patch("app.merchant.service.MerchantRepo",
                   return_value=_repo(get_by_or_404=merchant, update=merchant)):
            await service.update_merchant(str(uuid4()), payload, db)
        db.refresh.assert_awaited_once_with(merchant, attribute_names=["menu_items"])

    async def test_toggle_open_loads_menu(self):
        from app.merchant import service
        merchant = MagicMock(id=uuid4())
        db = _db()
        with patch("app.merchant.service.MerchantRepo",
                   return_value=_repo(get_by_or_404=merchant, update=merchant)):
            await service.toggle_open(str(uuid4()), False, db)
        db.refresh.assert_awaited_once_with(merchant, attribute_names=["menu_items"])

    async def test_update_courier_profile_loads_documents(self):
        from app.courier import service
        courier = MagicMock(id=uuid4())
        payload = MagicMock()
        payload.model_dump.return_value = {"vehicle_plate": "KMAB123C"}
        db = _db()
        with patch("app.courier.service.CourierRepo",
                   return_value=_repo(get_by_or_404=courier, update=courier)):
            await service.update_profile(str(uuid4()), payload, db)
        db.refresh.assert_awaited_once_with(courier, attribute_names=["documents"])

    @pytest.mark.parametrize("is_online", [True, False])
    async def test_online_toggle_loads_documents(self, is_online):
        from app.courier import service
        from app.models.courier import CourierStatus
        courier = MagicMock(id=uuid4(), status=CourierStatus.active)
        db = _db()
        redis = MagicMock()
        redis.delete = AsyncMock()
        with patch("app.courier.service.CourierRepo",
                   return_value=_repo(get_by_or_404=courier, update=courier)):
            await service.set_online_status(str(uuid4()), is_online, db, redis)
        db.refresh.assert_awaited_once_with(courier, attribute_names=["documents"])


# ── Customer-facing merchant page ─────────────────────────────────────────────
class TestPublicMerchantMenu:
    def _merchant_dict(self):
        now = datetime.now(timezone.utc)
        return {
            "id": uuid4(), "shop_name": "Mama Mboga", "category": "grocery",
            "logo_url": None, "banner_url": None, "address": "Kenyatta Ave",
            "city": "Nairobi", "latitude": None, "longitude": None,
            "rating": Decimal("4.5"), "rating_count": 10, "avg_prep_minutes": 15,
            "min_order_amount": Decimal("0"), "is_open": True, "status": "active",
            "description": "Fresh veg", "operating_hours": None,
            # Private fields that must never reach customers:
            "payout_phone": "+254712345678", "commission_rate": Decimal("20.00"),
            "created_at": now, "menu_items": [],
        }

    def test_public_detail_excludes_payout_and_commission(self):
        # Regression: GET /merchant/{id}/menu returned the decrypted payout phone
        from app.schemas.merchant import MerchantPublicDetail
        out = MerchantPublicDetail.model_validate(self._merchant_dict()).model_dump()
        assert "payout_phone" not in out
        assert "commission_rate" not in out
        assert out["shop_name"] == "Mama Mboga"

    def test_menu_endpoint_uses_public_schema(self):
        from app.main import app
        resp = app.openapi()["paths"]["/merchant/{merchant_id}/menu"]["get"]["responses"]["200"]
        ref = resp["content"]["application/json"]["schema"]["$ref"].split("/")[-1]
        props = app.openapi()["components"]["schemas"][ref]["properties"]
        assert "payout_phone" not in props
        assert "commission_rate" not in props

    @pytest.mark.parametrize("status", ["pending_review", "suspended", "deactivated"])
    async def test_inactive_merchant_hidden_from_customers(self, status):
        from app.merchant import service
        from app.models.merchant import MerchantStatus
        from app.core.exceptions import NotFoundError
        merchant = MagicMock(id=uuid4(), status=MerchantStatus(status))
        with patch("app.merchant.service.MerchantRepo", return_value=_repo(get_or_404=merchant)), \
             pytest.raises(NotFoundError):
            await service.get_merchant_menu(str(merchant.id), MagicMock())
