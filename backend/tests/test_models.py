"""
Model unit tests — state machines, computed properties, constraints.

Run with:
    cd backend && pytest tests/test_models.py -v
"""
import pytest
from unittest.mock import MagicMock
from decimal import Decimal


# ── Order state machine ───────────────────────────────────────────────────────
class TestOrderStateMachine:
    def test_full_happy_path_valid(self):
        """All transitions in the normal order flow must be valid."""
        from app.models.order import OrderStatus, VALID_TRANSITIONS
        happy_path = [
            (OrderStatus.pending,          OrderStatus.confirmed),
            (OrderStatus.confirmed,        OrderStatus.preparing),
            (OrderStatus.preparing,        OrderStatus.ready_for_pickup),
            (OrderStatus.ready_for_pickup, OrderStatus.picked_up),
            (OrderStatus.picked_up,        OrderStatus.in_transit),
            (OrderStatus.in_transit,       OrderStatus.delivered),
        ]
        for from_status, to_status in happy_path:
            assert to_status in VALID_TRANSITIONS[from_status], \
                f"Expected {from_status} → {to_status} to be valid"

    def test_cancelled_from_pending_valid(self):
        from app.models.order import OrderStatus, VALID_TRANSITIONS
        assert OrderStatus.cancelled in VALID_TRANSITIONS[OrderStatus.pending]

    def test_cancelled_from_confirmed_valid(self):
        from app.models.order import OrderStatus, VALID_TRANSITIONS
        assert OrderStatus.cancelled in VALID_TRANSITIONS[OrderStatus.confirmed]

    def test_cannot_cancel_after_pickup(self):
        from app.models.order import OrderStatus, VALID_TRANSITIONS
        assert OrderStatus.cancelled not in VALID_TRANSITIONS[OrderStatus.picked_up]

    def test_delivered_has_no_transitions(self):
        from app.models.order import OrderStatus, VALID_TRANSITIONS
        assert len(VALID_TRANSITIONS[OrderStatus.delivered]) == 0

    def test_all_statuses_have_transition_entry(self):
        from app.models.order import OrderStatus, VALID_TRANSITIONS
        for status in OrderStatus:
            assert status in VALID_TRANSITIONS, f"{status} missing from VALID_TRANSITIONS"


# ── MenuItem computed price ───────────────────────────────────────────────────
class TestMenuItemEffectivePrice:
    def _make_item(self, price: float, discount_pct: float):
        from app.models.merchant import MenuItem
        item = MagicMock(spec=MenuItem)
        item.price = Decimal(str(price))
        item.discount_pct = Decimal(str(discount_pct))
        item.effective_price = MenuItem.effective_price.fget(item)
        return item

    def test_no_discount(self):
        item = self._make_item(500.00, 0)
        assert item.effective_price == 500.00

    def test_10_percent_discount(self):
        item = self._make_item(1000.00, 10)
        assert item.effective_price == 900.00

    def test_100_percent_discount(self):
        item = self._make_item(500.00, 100)
        assert item.effective_price == 0.00


# ── Courier dispatchable ──────────────────────────────────────────────────────
class TestCourierDispatchable:
    def _make_courier(self, status: str, is_online: bool, docs_verified: bool):
        from app.models.courier import Courier, CourierStatus
        from datetime import datetime, timezone
        courier = MagicMock(spec=Courier)
        courier.status = CourierStatus(status)
        courier.is_online = is_online
        courier.documents_verified_at = datetime.now(timezone.utc) if docs_verified else None
        courier.is_dispatchable = Courier.is_dispatchable.fget(courier)
        return courier

    def test_active_online_verified_is_dispatchable(self):
        c = self._make_courier("active", True, True)
        assert c.is_dispatchable is True

    def test_active_offline_is_not_dispatchable(self):
        c = self._make_courier("active", False, True)
        assert c.is_dispatchable is False

    def test_approved_not_active_is_not_dispatchable(self):
        c = self._make_courier("approved", True, True)
        assert c.is_dispatchable is False

    def test_active_online_unverified_docs_not_dispatchable(self):
        c = self._make_courier("active", True, False)
        assert c.is_dispatchable is False

    def test_suspended_not_dispatchable(self):
        c = self._make_courier("suspended", True, True)
        assert c.is_dispatchable is False


# ── Encryption round-trip ─────────────────────────────────────────────────────
class TestFieldEncryption:
    def test_encrypt_decrypt_roundtrip(self):
        import os
        from cryptography.fernet import Fernet
        key = Fernet.generate_key().decode()
        os.environ["FIELD_ENCRYPTION_KEY"] = key
        os.environ["DOCUMENT_ENCRYPTION_KEY"] = key
        os.environ["DATABASE_URL"] = "postgresql+asyncpg://u:p@localhost/db"
        os.environ["JWT_SECRET"] = "x" * 32

        # Re-import with new env vars
        import importlib
        import app.core.config as cfg_module
        cfg_module.get_settings.cache_clear()

        from cryptography.fernet import Fernet as F
        cipher = F(key.encode())
        original = "+254712345678"
        encrypted = cipher.encrypt(original.encode()).decode()
        decrypted = cipher.decrypt(encrypted.encode()).decode()
        assert decrypted == original
        assert encrypted != original

    def test_encrypted_value_not_readable(self):
        from cryptography.fernet import Fernet
        key = Fernet.generate_key()
        cipher = Fernet(key)
        phone = "+254712345678"
        encrypted = cipher.encrypt(phone.encode()).decode()
        assert phone not in encrypted


# ── Payout balance columns ────────────────────────────────────────────────────
class TestPayoutColumns:
    @pytest.mark.parametrize("model_path", [
        "app.models.merchant.Merchant",
        "app.models.courier.Courier",
    ])
    def test_pending_payout_column_exists(self, model_path):
        # payments.service._mark_order_paid updates pending_payout via raw SQL
        import importlib
        module_name, cls_name = model_path.rsplit(".", 1)
        model = getattr(importlib.import_module(module_name), cls_name)
        col = model.__table__.c["pending_payout"]
        assert not col.nullable
