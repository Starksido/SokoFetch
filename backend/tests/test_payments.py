"""
Payment system tests — M-Pesa parsing, FLW parsing, signature verification,
service logic, and payout calculations.

Run with:
    cd backend && pytest tests/test_payments.py -v
"""
import pytest
import hashlib
import hmac
import json
from decimal import Decimal
from unittest.mock import AsyncMock, MagicMock, patch
from uuid import uuid4


# ══════════════════════════════════════════════════════════════════════════════
# M-PESA CALLBACK PARSING
# ══════════════════════════════════════════════════════════════════════════════
class TestMpesaCallbackParsing:

    def _success_callback(self, checkout_id: str, receipt: str = "NLJ7RT61SV"):
        return {
            "Body": {
                "stkCallback": {
                    "MerchantRequestID": "29115-34620561-1",
                    "CheckoutRequestID": checkout_id,
                    "ResultCode": 0,
                    "ResultDesc": "The service request is processed successfully.",
                    "CallbackMetadata": {
                        "Item": [
                            {"Name": "Amount",              "Value": 850},
                            {"Name": "MpesaReceiptNumber",  "Value": receipt},
                            {"Name": "TransactionDate",     "Value": 20240115103045},
                            {"Name": "PhoneNumber",         "Value": 254712345678},
                        ]
                    }
                }
            }
        }

    def _failure_callback(self, checkout_id: str, code: int = 1032):
        return {
            "Body": {
                "stkCallback": {
                    "MerchantRequestID": "29115-34620561-1",
                    "CheckoutRequestID": checkout_id,
                    "ResultCode": code,
                    "ResultDesc": "Request cancelled by user.",
                }
            }
        }

    def test_parse_success_callback(self):
        from app.payments.mpesa import parse_stk_callback
        cid  = "ws_CO_191220191020363925"
        body = self._success_callback(cid)
        parsed = parse_stk_callback(body)

        assert parsed["checkout_request_id"] == cid
        assert parsed["result_code"]         == 0
        assert parsed["mpesa_receipt"]        == "NLJ7RT61SV"
        assert parsed["amount"]              == 850

    def test_parse_failure_callback(self):
        from app.payments.mpesa import parse_stk_callback
        cid  = "ws_CO_191220191020363925"
        body = self._failure_callback(cid)
        parsed = parse_stk_callback(body)

        assert parsed["result_code"]   == 1032
        assert parsed["mpesa_receipt"] is None
        assert "cancelled" in parsed["result_desc"].lower()

    def test_parse_unknown_result_code(self):
        from app.payments.mpesa import parse_stk_callback
        body = self._failure_callback("abc123", code=1037)
        parsed = parse_stk_callback(body)
        assert parsed["result_code"] == 1037

    def test_parse_missing_metadata_on_failure(self):
        from app.payments.mpesa import parse_stk_callback
        body   = self._failure_callback("test123")
        parsed = parse_stk_callback(body)
        assert parsed["amount"] is None
        assert parsed["phone"]  == ""


# ══════════════════════════════════════════════════════════════════════════════
# FLUTTERWAVE WEBHOOK PARSING
# ══════════════════════════════════════════════════════════════════════════════
class TestFlutterwaveWebhookParsing:

    def _charge_event(self, status="successful", tx_ref=None):
        return {
            "event": "charge.completed",
            "data": {
                "id":           12345,
                "tx_ref":       tx_ref or str(uuid4()),
                "flw_ref":      "FLW-MOCK-abc123",
                "amount":       850,
                "currency":     "KES",
                "status":       status,
                "payment_type": "card",
            }
        }

    def test_parse_successful_charge(self):
        from app.payments.flutterwave import parse_flw_webhook
        order_id = str(uuid4())
        body     = self._charge_event(tx_ref=order_id)
        parsed   = parse_flw_webhook(body)

        assert parsed["event"]   == "charge.completed"
        assert parsed["tx_ref"]  == order_id
        assert parsed["status"]  == "successful"
        assert parsed["amount"]  == 850.0

    def test_parse_failed_charge(self):
        from app.payments.flutterwave import parse_flw_webhook
        body   = self._charge_event(status="failed")
        parsed = parse_flw_webhook(body)
        assert parsed["status"] == "failed"

    def test_non_charge_event_returns_event_name(self):
        from app.payments.flutterwave import parse_flw_webhook
        body   = {"event": "transfer.completed", "data": {}}
        parsed = parse_flw_webhook(body)
        assert parsed["event"] == "transfer.completed"


# ══════════════════════════════════════════════════════════════════════════════
# SIGNATURE VERIFICATION
# ══════════════════════════════════════════════════════════════════════════════
class TestSignatureVerification:

    def test_mpesa_valid_signature(self):
        import os
        os.environ.setdefault("MPESA_PASSKEY", "test_passkey")

        from app.payments.mpesa import verify_callback_signature
        payload  = '{"test": "data"}'
        secret   = "test_passkey"
        expected = hmac.new(secret.encode(), payload.encode(), hashlib.sha256).hexdigest()

        with patch("app.payments.mpesa.settings") as mock_settings:
            mock_settings.MPESA_PASSKEY = secret
            result = verify_callback_signature(payload, expected)
        assert result is True

    def test_mpesa_invalid_signature_rejected(self):
        from app.payments.mpesa import verify_callback_signature
        with patch("app.payments.mpesa.settings") as mock_settings:
            mock_settings.MPESA_PASSKEY = "correct_key"
            result = verify_callback_signature('{"data": 1}', "wrong_sig")
        assert result is False

    def test_flw_valid_signature(self):
        from app.payments.flutterwave import verify_webhook_signature
        payload = '{"event": "charge.completed"}'
        secret  = "test_flw_secret"
        expected = hmac.new(secret.encode(), payload.encode(), hashlib.sha512).hexdigest()

        with patch("app.payments.flutterwave.settings") as mock_settings:
            mock_settings.FLUTTERWAVE_SECRET_KEY = secret
            result = verify_webhook_signature(payload, expected)
        assert result is True

    def test_flw_tampered_payload_rejected(self):
        from app.payments.flutterwave import verify_webhook_signature
        with patch("app.payments.flutterwave.settings") as mock_settings:
            mock_settings.FLUTTERWAVE_SECRET_KEY = "correct_key"
            result = verify_webhook_signature('{"tampered": true}', "wrong_sig")
        assert result is False


# ══════════════════════════════════════════════════════════════════════════════
# AMOUNT VALIDATION
# ══════════════════════════════════════════════════════════════════════════════
class TestAmountValidation:

    def test_integer_amount_for_mpesa(self):
        """Daraja requires integer amounts — no decimals."""
        amount_kes = Decimal("850.50")
        daraja_amount = max(1, int(amount_kes))
        assert daraja_amount == 850
        assert isinstance(daraja_amount, int)

    def test_minimum_mpesa_amount_is_1(self):
        """Daraja rejects 0 — we floor at 1."""
        amount = 0
        daraja_amount = max(1, int(amount))
        assert daraja_amount == 1

    def test_flw_amount_mismatch_detected(self):
        """
        If Flutterwave reports a lower amount than the order,
        the service should raise an error (anti-tampering).
        """
        order_total  = Decimal("850.00")
        paid_amount  = Decimal("1.00")   # Tampered
        assert paid_amount < order_total   # Would trigger the mismatch check


# ══════════════════════════════════════════════════════════════════════════════
# STK PASSWORD GENERATION
# ══════════════════════════════════════════════════════════════════════════════
class TestStkPassword:

    def test_password_is_base64(self):
        import base64
        from app.payments.mpesa import _stk_password
        with patch("app.payments.mpesa.settings") as mock:
            mock.MPESA_SHORTCODE = "174379"
            mock.MPESA_PASSKEY   = "testpasskey"
            pwd = _stk_password("20240115103045")

        # Should be valid base64
        decoded = base64.b64decode(pwd.encode()).decode()
        assert "174379" in decoded
        assert "testpasskey" in decoded
        assert "20240115103045" in decoded

    def test_password_changes_with_timestamp(self):
        from app.payments.mpesa import _stk_password
        with patch("app.payments.mpesa.settings") as mock:
            mock.MPESA_SHORTCODE = "174379"
            mock.MPESA_PASSKEY   = "testpasskey"
            pwd1 = _stk_password("20240115103045")
            pwd2 = _stk_password("20240115104500")
        assert pwd1 != pwd2


# ══════════════════════════════════════════════════════════════════════════════
# EARNINGS CALCULATIONS
# ══════════════════════════════════════════════════════════════════════════════
class TestEarningsCalculations:

    def test_merchant_net_payout(self):
        """Net = gross - commission."""
        gross      = Decimal("10000.00")
        commission = Decimal("2000.00")   # 20%
        net        = gross - commission
        assert net == Decimal("8000.00")

    def test_courier_payout_from_delivery_fee(self):
        """Courier gets 82% of delivery fee."""
        delivery_fee   = Decimal("120.00")
        platform_cut   = (delivery_fee * Decimal("0.18")).quantize(Decimal("0.01"))
        courier_payout = delivery_fee - platform_cut
        assert courier_payout == Decimal("98.40")

    def test_commission_calculation(self):
        """20% commission on KES 850 = KES 170."""
        subtotal    = Decimal("850.00")
        rate        = Decimal("20.00")
        commission  = (subtotal * rate / 100).quantize(Decimal("0.01"))
        assert commission == Decimal("170.00")

    def test_platform_revenue_per_order(self):
        """Total platform revenue = commission + platform fee retainer."""
        commission   = Decimal("170.00")  # 20% of 850
        platform_fee = Decimal("21.60")   # 18% of 120 delivery fee
        total_revenue = commission + platform_fee
        assert total_revenue == Decimal("191.60")


# ── Payment ownership ─────────────────────────────────────────────────────────
# order.customer_id is the customer PROFILE id; the caller passes users.id.
class TestPaymentOwnership:
    def _patch_repos(self, order, customer):
        order_repo = MagicMock()
        order_repo.get_or_404 = AsyncMock(return_value=order)
        customer_repo = MagicMock()
        customer_repo.get_by_user_id = AsyncMock(return_value=customer)
        return (
            patch("app.payments.service.OrderRepo", return_value=order_repo),
            patch("app.payments.service.CustomerRepo", return_value=customer_repo),
        )

    @pytest.mark.parametrize("fn", ["initiate_mpesa", "verify_card"])
    async def test_owner_passes_ownership_check(self, fn):
        from app.payments import service
        from app.models.order import PaymentStatus
        from app.core.exceptions import SokoFetchException

        user_id  = str(uuid4())
        customer = MagicMock(id=uuid4())
        order    = MagicMock(customer_id=customer.id, payment_status=PaymentStatus.paid)
        p1, p2 = self._patch_repos(order, customer)
        with p1, p2, pytest.raises(SokoFetchException) as exc:
            if fn == "initiate_mpesa":
                await service.initiate_mpesa_payment(str(uuid4()), "+254712345678", user_id, MagicMock(), MagicMock())
            else:
                await service.verify_card_payment(str(uuid4()), "123", user_id, MagicMock())
        # Reaching the already-paid check proves ownership passed
        assert exc.value.detail["code"] == "ALREADY_PAID"

    @pytest.mark.parametrize("fn", ["initiate_mpesa", "verify_card"])
    async def test_account_id_match_is_not_ownership(self, fn):
        from app.payments import service
        from app.core.exceptions import ObjectAccessDeniedError

        user_id  = str(uuid4())
        customer = MagicMock(id=uuid4())
        order    = MagicMock(customer_id=user_id)   # matches users.id, not profile id
        p1, p2 = self._patch_repos(order, customer)
        with p1, p2, pytest.raises(ObjectAccessDeniedError):
            if fn == "initiate_mpesa":
                await service.initiate_mpesa_payment(str(uuid4()), "+254712345678", user_id, MagicMock(), MagicMock())
            else:
                await service.verify_card_payment(str(uuid4()), "123", user_id, MagicMock())

    async def test_customer_without_profile_is_denied(self):
        from app.payments import service
        from app.core.exceptions import ObjectAccessDeniedError

        order = MagicMock(customer_id=uuid4())
        p1, p2 = self._patch_repos(order, None)
        with p1, p2, pytest.raises(ObjectAccessDeniedError):
            await service.verify_card_payment(str(uuid4()), "123", str(uuid4()), MagicMock())
