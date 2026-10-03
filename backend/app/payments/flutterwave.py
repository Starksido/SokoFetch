"""
Flutterwave Integration
========================
Card payments are tokenised client-side by the Flutterwave Flutter SDK.
The backend only ever sees tx_ref and flw_ref — never raw card data.

Handles:
  - Payment verification (confirm a completed charge)
  - Refund initiation
  - Webhook signature verification
"""
import hashlib
import hmac
import logging

import httpx

from app.core.config import settings

log = logging.getLogger("alphabet.payments.flutterwave")

_BASE = "https://api.flutterwave.com/v3"


def _headers() -> dict:
    return {
        "Authorization": f"Bearer {settings.FLUTTERWAVE_SECRET_KEY}",
        "Content-Type":  "application/json",
    }


# ── Verify payment ────────────────────────────────────────────────────────────
async def verify_payment(transaction_id: str) -> dict:
    """
    Verify a completed Flutterwave transaction by its transaction ID.

    Returns the full transaction object on success.
    Raises ValueError if the payment is not successful.
    """
    async with httpx.AsyncClient(timeout=20.0) as client:
        resp = await client.get(
            f"{_BASE}/transactions/{transaction_id}/verify",
            headers=_headers(),
        )
        resp.raise_for_status()
        data = resp.json()

    if data.get("status") != "success":
        raise ValueError(f"Flutterwave verification failed: {data.get('message')}")

    tx = data.get("data", {})
    if tx.get("status") != "successful":
        raise ValueError(f"Transaction not successful: {tx.get('status')}")

    log.info("FLW payment verified | tx_id=%s | amount=%s %s",
             transaction_id, tx.get("amount"), tx.get("currency"))
    return tx


# ── Initiate refund ───────────────────────────────────────────────────────────
async def initiate_refund(transaction_id: str, amount: float | None = None) -> dict:
    """
    Initiate a full or partial refund.
    If amount is None, the full transaction amount is refunded.
    """
    body = {"id": transaction_id}
    if amount is not None:
        body["amount"] = amount

    async with httpx.AsyncClient(timeout=20.0) as client:
        resp = await client.post(
            f"{_BASE}/transactions/{transaction_id}/refund",
            json=body,
            headers=_headers(),
        )
        resp.raise_for_status()
        data = resp.json()

    log.info("FLW refund initiated | tx_id=%s | amount=%s", transaction_id, amount)
    return data


# ── Webhook signature verification ───────────────────────────────────────────
def verify_webhook_signature(payload_str: str, signature: str) -> bool:
    """
    Verify the 'verif-hash' header sent by Flutterwave on webhooks.
    The secret hash is configured in the Flutterwave dashboard.
    """
    expected = hmac.new(
        settings.FLUTTERWAVE_SECRET_KEY.encode(),
        payload_str.encode(),
        hashlib.sha512,
    ).hexdigest()
    return hmac.compare_digest(expected, signature)


# ── Parse webhook ─────────────────────────────────────────────────────────────
def parse_flw_webhook(body: dict) -> dict:
    """
    Extract key fields from a Flutterwave webhook payload.

    Returns:
        {
            "event":          str,   # "charge.completed" etc.
            "tx_ref":         str,   # Our order_id reference
            "flw_ref":        str,   # Flutterwave reference
            "transaction_id": str,
            "amount":         float,
            "currency":       str,
            "status":         str,   # "successful" | "failed"
            "payment_type":   str,   # "card" | "mpesa" etc.
        }
    """
    data = body.get("data", {})
    return {
        "event":          body.get("event", ""),
        "tx_ref":         data.get("tx_ref", ""),
        "flw_ref":        data.get("flw_ref", ""),
        "transaction_id": str(data.get("id", "")),
        "amount":         float(data.get("amount", 0)),
        "currency":       data.get("currency", "KES"),
        "status":         data.get("status", ""),
        "payment_type":   data.get("payment_type", ""),
    }
