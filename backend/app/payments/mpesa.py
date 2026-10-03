"""
M-Pesa Daraja API Integration
==============================
Handles:
  - OAuth token generation (cached in Redis)
  - STK Push initiation (payment prompt on customer phone)
  - Callback signature verification
  - Payment status polling
"""
import base64
import hashlib
import hmac
import logging
from datetime import datetime, timezone

import httpx
import redis.asyncio as aioredis

from app.core.config import settings

log = logging.getLogger("alphabet.payments.mpesa")

# ── Endpoints ─────────────────────────────────────────────────────────────────
_SANDBOX = "https://sandbox.safaricom.co.ke"
_PROD    = "https://api.safaricom.co.ke"

def _base() -> str:
    return _PROD if settings.MPESA_ENVIRONMENT == "production" else _SANDBOX

OAUTH_URL    = lambda: f"{_base()}/oauth/v1/generate?grant_type=client_credentials"
STK_URL      = lambda: f"{_base()}/mpesa/stkpush/v1/processrequest"
QUERY_URL    = lambda: f"{_base()}/mpesa/stkpushquery/v1/query"


# ── OAuth token (cached 55 min in Redis) ──────────────────────────────────────
async def get_access_token(redis: aioredis.Redis) -> str:
    cached = await redis.get("mpesa:access_token")
    if cached:
        return cached

    credentials = base64.b64encode(
        f"{settings.MPESA_CONSUMER_KEY}:{settings.MPESA_CONSUMER_SECRET}".encode()
    ).decode()

    async with httpx.AsyncClient(timeout=15.0) as client:
        resp = await client.get(
            OAUTH_URL(),
            headers={"Authorization": f"Basic {credentials}"},
        )
        resp.raise_for_status()
        token = resp.json()["access_token"]

    # Cache for 55 minutes (Daraja tokens expire at 60 min)
    await redis.setex("mpesa:access_token", 55 * 60, token)
    log.debug("M-Pesa OAuth token refreshed")
    return token


# ── Password generation ───────────────────────────────────────────────────────
def _stk_password(timestamp: str) -> str:
    """Base64(ShortCode + PassKey + Timestamp)"""
    raw = f"{settings.MPESA_SHORTCODE}{settings.MPESA_PASSKEY}{timestamp}"
    return base64.b64encode(raw.encode()).decode()


# ── STK Push ──────────────────────────────────────────────────────────────────
async def initiate_stk_push(
    phone: str,
    amount: int,           # Always integer KES — no decimals to Daraja
    order_id: str,
    redis: aioredis.Redis,
) -> dict:
    """
    Send an STK Push payment prompt to the customer's phone.
    Customer sees a PIN prompt on their device.

    Returns the raw Daraja response dict.
    Raises httpx.HTTPError on network/API failure.
    """
    timestamp = datetime.now(timezone.utc).strftime("%Y%m%d%H%M%S")
    token     = await get_access_token(redis)

    # Normalise phone: +254712345678 → 254712345678
    mpesa_phone = phone.lstrip("+")

    payload = {
        "BusinessShortCode": settings.MPESA_SHORTCODE,
        "Password":          _stk_password(timestamp),
        "Timestamp":         timestamp,
        "TransactionType":   "CustomerPayBillOnline",
        "Amount":            max(1, int(amount)),      # Daraja minimum is 1 KES
        "PartyA":            mpesa_phone,
        "PartyB":            settings.MPESA_SHORTCODE,
        "PhoneNumber":       mpesa_phone,
        "CallBackURL":       f"{settings.BASE_URL}/payments/mpesa/callback",
        "AccountReference":  order_id[:12],            # Max 12 chars
        "TransactionDesc":   f"Soko Fetch order",
    }

    log.info("STK Push initiated | order=%s | phone_tail=%s | amount=%d",
             order_id, phone[-4:], amount)

    async with httpx.AsyncClient(timeout=30.0) as client:
        resp = await client.post(
            STK_URL(),
            json=payload,
            headers={
                "Authorization": f"Bearer {token}",
                "Content-Type":  "application/json",
            },
        )
        resp.raise_for_status()
        data = resp.json()

    if data.get("ResponseCode") != "0":
        log.error("STK Push failed | response=%s", data)
        raise ValueError(f"M-Pesa STK Push failed: {data.get('ResponseDescription')}")

    # Store CheckoutRequestID → order_id mapping in Redis (TTL: 10 min)
    checkout_id = data.get("CheckoutRequestID", "")
    if checkout_id:
        await redis.setex(f"mpesa:checkout:{checkout_id}", 600, order_id)

    return data


# ── Callback verification ─────────────────────────────────────────────────────
def verify_callback_signature(payload_str: str, signature: str) -> bool:
    """
    Verify Safaricom's HMAC-SHA256 signature on webhook callbacks.
    The signature header is 'X-Mpesa-Signature'.
    """
    expected = hmac.new(
        settings.MPESA_PASSKEY.encode(),
        payload_str.encode(),
        hashlib.sha256,
    ).hexdigest()
    return hmac.compare_digest(expected, signature)


# ── Parse callback ────────────────────────────────────────────────────────────
def parse_stk_callback(body: dict) -> dict:
    """
    Extract key fields from the STK callback body.

    Returns:
        {
            "checkout_request_id": str,
            "result_code":         int,   # 0 = success
            "result_desc":         str,
            "mpesa_receipt":       str | None,
            "amount":              float | None,
            "phone":               str | None,
            "transaction_date":    str | None,
        }
    """
    stk_cb = body.get("Body", {}).get("stkCallback", {})
    result_code = int(stk_cb.get("ResultCode", -1))
    metadata    = {}

    if result_code == 0:
        items = stk_cb.get("CallbackMetadata", {}).get("Item", [])
        metadata = {item["Name"]: item.get("Value") for item in items}

    return {
        "checkout_request_id": stk_cb.get("CheckoutRequestID"),
        "result_code":         result_code,
        "result_desc":         stk_cb.get("ResultDesc", ""),
        "mpesa_receipt":       metadata.get("MpesaReceiptNumber"),
        "amount":              metadata.get("Amount"),
        "phone":               str(metadata.get("PhoneNumber", "")),
        "transaction_date":    str(metadata.get("TransactionDate", "")),
    }


# ── Status query ──────────────────────────────────────────────────────────────
async def query_stk_status(
    checkout_request_id: str,
    redis: aioredis.Redis,
) -> dict:
    """Poll Daraja to check whether an STK Push was completed."""
    timestamp = datetime.now(timezone.utc).strftime("%Y%m%d%H%M%S")
    token     = await get_access_token(redis)

    async with httpx.AsyncClient(timeout=15.0) as client:
        resp = await client.post(
            QUERY_URL(),
            json={
                "BusinessShortCode": settings.MPESA_SHORTCODE,
                "Password":          _stk_password(timestamp),
                "Timestamp":         timestamp,
                "CheckoutRequestID": checkout_request_id,
            },
            headers={"Authorization": f"Bearer {token}"},
        )
        resp.raise_for_status()
        return resp.json()
