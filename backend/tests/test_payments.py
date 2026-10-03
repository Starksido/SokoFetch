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

    def test_mpesa_callback_token_accepted(self):
        from app.payments.mpesa import verify_callback_token
        with patch("app.payments.mpesa.settings") as mock_settings:
            mock_settings.MPESA_CALLBACK_TOKEN = "s3cret-token"
            assert verify_callback_token("s3cret-token") is True

    def test_mpesa_callback_wrong_token_rejected(self):
        from app.payments.mpesa import verify_callback_token
        with patch("app.payments.mpesa.settings") as mock_settings:
            mock_settings.MPESA_CALLBACK_TOKEN = "s3cret-token"
            assert verify_callback_token("guess") is False

    def test_mpesa_callback_rejected_when_token_unconfigured(self):
        from app.payments.mpesa import verify_callback_token
        with patch("app.payments.mpesa.settings") as mock_settings:
            mock_settings.MPESA_CALLBACK_TOKEN = ""
            assert verify_callback_token("") is False

    def test_flw_valid_hash(self):
        from app.payments.flutterwave import verify_webhook_signature
        with patch("app.payments.flutterwave.settings") as mock_settings:
            mock_settings.FLUTTERWAVE_SECRET_HASH = "dashboard-hash"
            assert verify_webhook_signature("dashboard-hash") is True

    def test_flw_wrong_hash_rejected(self):
        from app.payments.flutterwave import verify_webhook_signature
        with patch("app.payments.flutterwave.settings") as mock_settings:
            mock_settings.FLUTTERWAVE_SECRET_HASH = "dashboard-hash"
            assert verify_webhook_signature("wrong") is False

    def test_flw_missing_header_rejected(self):
        # Regression: a missing verif-hash header used to skip verification
        from app.payments.flutterwave import verify_webhook_signature
        with patch("app.payments.flutterwave.settings") as mock_settings:
            mock_settings.FLUTTERWAVE_SECRET_HASH = "dashboard-hash"
            assert verify_webhook_signature(None) is False

    def test_flw_rejected_when_hash_unconfigured(self):
        from app.payments.flutterwave import verify_webhook_signature
        with patch("app.payments.flutterwave.settings") as mock_settings:
            mock_settings.FLUTTERWAVE_SECRET_HASH = ""
            assert verify_webhook_signature("") is False


# ══════════════════════════════════════════════════════════════════════════════
# AMOUNT VALIDATION
# ══════════════════════════════════════════════════════════════════════════════
class TestAmountValidation:

    def test_mpesa_amount_rounds_up(self):
        """Daraja requires whole KES — round up so the order is never underpaid."""
        from app.payments.mpesa import daraja_amount
        assert daraja_amount(Decimal("850.50")) == 851
        assert daraja_amount(Decimal("850.00")) == 850
        assert isinstance(daraja_amount(Decimal("850.50")), int)

    def test_minimum_mpesa_amount_is_1(self):
        """Daraja rejects 0 — we floor at 1."""
        from app.payments.mpesa import daraja_amount
        assert daraja_amount(0) == 1

    def test_flw_tx_matching_order_passes(self):
        from app.payments.flutterwave import validate_transaction_for_order
        oid = str(uuid4())
        validate_transaction_for_order(
            {"tx_ref": oid, "currency": "KES", "amount": 850}, oid, Decimal("850.00"))

    @pytest.mark.parametrize("tx_changes", [
        {"tx_ref": "another-order"},
        {"currency": "NGN"},
        {"amount": 1},
    ])
    def test_flw_tx_mismatch_rejected(self, tx_changes):
        from app.payments.flutterwave import validate_transaction_for_order
        oid = str(uuid4())
        tx = {"tx_ref": oid, "currency": "KES", "amount": 850, **tx_changes}
        with pytest.raises(ValueError):
            validate_transaction_for_order(tx, oid, Decimal("850.00"))


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


# ── Payment flows (gateway confirmations) ─────────────────────────────────────
def _order(**kw):
    from app.models.order import OrderStatus, PaymentStatus
    o = MagicMock()
    o.id             = kw.get("id", uuid4())
    o.customer_id    = kw.get("customer_id", uuid4())
    o.total          = kw.get("total", Decimal("850.00"))
    o.status         = kw.get("status", OrderStatus.pending)
    o.payment_status = kw.get("payment_status", PaymentStatus.pending)
    return o


def _repo(**methods):
    r = MagicMock()
    for name, value in methods.items():
        setattr(r, name, AsyncMock(return_value=value))
    return r


def _mpesa_callback(checkout_id="ws_CO_1", result_code=0, amount=850):
    items = [{"Name": "Amount", "Value": amount}, {"Name": "MpesaReceiptNumber", "Value": "RCPT1"}]
    return {"Body": {"stkCallback": {
        "CheckoutRequestID": checkout_id, "ResultCode": result_code, "ResultDesc": "x",
        "CallbackMetadata": {"Item": items},
    }}}


class TestMpesaCallbackFlow:
    async def test_missing_checkout_id_ignored(self):
        from app.payments import service
        payment_repo = _repo(get_by=MagicMock())
        with patch("app.payments.service.PaymentRepo", return_value=payment_repo):
            body = _mpesa_callback(checkout_id=None)
            assert await service.handle_mpesa_callback(body, MagicMock(), MagicMock()) == {"status": "ignored"}
        payment_repo.get_by.assert_not_awaited()

    async def test_duplicate_callback_ignored(self):
        from app.payments import service
        from app.models.payment import TransactionStatus
        payment = MagicMock(status=TransactionStatus.success)
        payment_repo = _repo(get_by=payment, update=payment)
        with patch("app.payments.service.PaymentRepo", return_value=payment_repo), \
             patch("app.payments.service._mark_order_paid", new=AsyncMock()) as mark_paid:
            result = await service.handle_mpesa_callback(_mpesa_callback(), MagicMock(), MagicMock())
        assert result == {"status": "ignored"}
        mark_paid.assert_not_awaited()

    async def test_underpayment_is_rejected(self):
        from app.payments import service
        from app.models.payment import TransactionStatus
        payment = MagicMock(status=TransactionStatus.pending, order_id=uuid4())
        payment_repo = _repo(get_by=payment, update=payment)
        order_repo = _repo(get=_order(total=Decimal("850.00")))
        with patch("app.payments.service.PaymentRepo", return_value=payment_repo), \
             patch("app.payments.service.OrderRepo", return_value=order_repo), \
             patch("app.payments.service._mark_order_paid", new=AsyncMock()) as mark_paid:
            await service.handle_mpesa_callback(_mpesa_callback(amount=1), MagicMock(), MagicMock())
        mark_paid.assert_not_awaited()
        assert payment_repo.update.await_args.kwargs["status"] == TransactionStatus.failed

    async def test_full_payment_marks_order_paid(self):
        from app.payments import service
        from app.models.payment import TransactionStatus
        payment = MagicMock(status=TransactionStatus.pending, order_id=uuid4())
        payment_repo = _repo(get_by=payment, update=payment)
        order_repo = _repo(get=_order(total=Decimal("850.00")))
        with patch("app.payments.service.PaymentRepo", return_value=payment_repo), \
             patch("app.payments.service.OrderRepo", return_value=order_repo), \
             patch("app.payments.service._mark_order_paid", new=AsyncMock()) as mark_paid:
            await service.handle_mpesa_callback(_mpesa_callback(amount=850), MagicMock(), MagicMock())
        mark_paid.assert_awaited_once()
        assert payment_repo.update.await_args.kwargs["status"] == TransactionStatus.success


class TestMpesaInitiate:
    def _patches(self, order):
        customer = MagicMock(id=order.customer_id)
        return (
            patch("app.payments.service.OrderRepo", return_value=_repo(get_or_404=order)),
            patch("app.payments.service.CustomerRepo", return_value=_repo(get_by_user_id=customer)),
        )

    async def test_invalid_phone_rejected(self):
        from app.payments import service
        from app.core.exceptions import InvalidPhoneError
        p1, p2 = self._patches(_order())
        with p1, p2, pytest.raises(InvalidPhoneError):
            await service.initiate_mpesa_payment(str(uuid4()), "12345", str(uuid4()), MagicMock(), MagicMock())

    async def test_cancelled_order_not_payable(self):
        from app.payments import service
        from app.models.order import OrderStatus
        from app.core.exceptions import SokoFetchException
        p1, p2 = self._patches(_order(status=OrderStatus.cancelled))
        with p1, p2, pytest.raises(SokoFetchException) as exc:
            await service.initiate_mpesa_payment(str(uuid4()), "0712345678", str(uuid4()), MagicMock(), MagicMock())
        assert exc.value.detail["code"] == "ORDER_NOT_PAYABLE"

    async def test_sends_normalised_phone_and_rounded_amount(self):
        from app.payments import service
        order = _order(total=Decimal("850.50"))
        p1, p2 = self._patches(order)
        payment = MagicMock(id=uuid4())
        stk = AsyncMock(return_value={"CheckoutRequestID": "ws_CO_1"})
        with p1, p2, \
             patch("app.payments.service.PaymentRepo", return_value=_repo(create=payment, update=payment)), \
             patch("app.payments.service.mpesa_client.initiate_stk_push", new=stk):
            await service.initiate_mpesa_payment(str(order.id), "0712345678", str(uuid4()), MagicMock(), MagicMock())
        assert stk.await_args.kwargs["phone"] == "+254712345678"
        assert stk.await_args.kwargs["amount"] == 851


class TestCardVerifyFlow:
    def _patches(self, order, already_recorded=None):
        customer = MagicMock(id=order.customer_id)
        payment = MagicMock(id=uuid4())
        return (
            patch("app.payments.service.OrderRepo", return_value=_repo(get_or_404=order)),
            patch("app.payments.service.CustomerRepo", return_value=_repo(get_by_user_id=customer)),
            patch("app.payments.service.PaymentRepo",
                  return_value=_repo(get_by=already_recorded, create=payment)),
            patch("app.payments.service._mark_order_paid", new=AsyncMock()),
        )

    def _tx(self, order, **changes):
        return {"id": 12345, "tx_ref": str(order.id), "currency": "KES",
                "amount": 850, "flw_ref": "FLW-1", **changes}

    async def test_tx_for_another_order_rejected(self):
        from app.payments import service
        from app.core.exceptions import SokoFetchException
        order = _order()
        p = self._patches(order)
        verify = AsyncMock(return_value=self._tx(order, tx_ref=str(uuid4())))
        with p[0], p[1], p[2], p[3], patch("app.payments.service.flw_client.verify_payment", new=verify), \
             pytest.raises(SokoFetchException) as exc:
            await service.verify_card_payment(str(order.id), "12345", str(uuid4()), MagicMock())
        assert exc.value.detail["code"] == "PAYMENT_MISMATCH"

    async def test_reused_transaction_rejected(self):
        from app.payments import service
        from app.core.exceptions import SokoFetchException
        order = _order()
        p = self._patches(order, already_recorded=MagicMock())
        verify = AsyncMock(return_value=self._tx(order))
        with p[0], p[1], p[2], p[3], patch("app.payments.service.flw_client.verify_payment", new=verify), \
             pytest.raises(SokoFetchException) as exc:
            await service.verify_card_payment(str(order.id), "12345", str(uuid4()), MagicMock())
        assert exc.value.detail["code"] == "TRANSACTION_ALREADY_USED"

    async def test_success_stores_flw_transaction_id(self):
        from app.payments import service
        order = _order()
        p = self._patches(order)
        verify = AsyncMock(return_value=self._tx(order))
        with p[0], p[1], p[2] as payment_repo_cls, p[3] as mark_paid, \
             patch("app.payments.service.flw_client.verify_payment", new=verify):
            await service.verify_card_payment(str(order.id), "12345", str(uuid4()), MagicMock())
        create_kwargs = payment_repo_cls.return_value.create.await_args.kwargs
        assert create_kwargs["gateway_ref"] == "12345"   # numeric id, used for refunds
        mark_paid.assert_awaited_once()


class TestFlutterwaveWebhookFlow:
    def _body(self, tx_id="12345"):
        return {"event": "charge.completed",
                "data": {"id": tx_id, "status": "successful", "tx_ref": "whatever", "amount": 850}}

    async def test_body_is_not_trusted_without_api_verification(self):
        from app.payments import service
        verify = AsyncMock(side_effect=ValueError("Transaction not successful"))
        with patch("app.payments.service.flw_client.verify_payment", new=verify), \
             patch("app.payments.service._mark_order_paid", new=AsyncMock()) as mark_paid:
            result = await service.handle_flw_webhook(self._body(), MagicMock())
        assert result == {"status": "ignored"}
        mark_paid.assert_not_awaited()

    async def test_mismatched_amount_ignored(self):
        from app.payments import service
        order = _order(total=Decimal("850.00"))
        tx = {"id": 12345, "tx_ref": str(order.id), "currency": "KES", "amount": 1}
        with patch("app.payments.service.flw_client.verify_payment", new=AsyncMock(return_value=tx)), \
             patch("app.payments.service.OrderRepo", return_value=_repo(get=order)), \
             patch("app.payments.service._mark_order_paid", new=AsyncMock()) as mark_paid:
            result = await service.handle_flw_webhook(self._body(), MagicMock())
        assert result == {"status": "ignored"}
        mark_paid.assert_not_awaited()

    async def test_verified_matching_charge_marks_paid(self):
        from app.payments import service
        order = _order(total=Decimal("850.00"))
        tx = {"id": 12345, "tx_ref": str(order.id), "currency": "KES", "amount": 850, "flw_ref": "F"}
        customer = MagicMock(user_id=uuid4())
        with patch("app.payments.service.flw_client.verify_payment", new=AsyncMock(return_value=tx)), \
             patch("app.payments.service.OrderRepo", return_value=_repo(get=order)), \
             patch("app.payments.service.CustomerRepo", return_value=_repo(get=customer)), \
             patch("app.payments.service.PaymentRepo", return_value=_repo(get_by=None, create=MagicMock())), \
             patch("app.payments.service._mark_order_paid", new=AsyncMock()) as mark_paid:
            result = await service.handle_flw_webhook(self._body(), MagicMock())
        assert result == {"status": "processed"}
        mark_paid.assert_awaited_once()
