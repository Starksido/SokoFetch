from pydantic import BaseModel, Field
from typing import Optional
from decimal import Decimal
from datetime import datetime


# ── Requests ──────────────────────────────────────────────────────────────────
class MpesaInitiateRequest(BaseModel):
    order_id: str
    phone:    str = Field(..., description="Customer M-Pesa phone: +254712345678")


class FlutterwaveVerifyRequest(BaseModel):
    order_id:       str
    transaction_id: str   # Flutterwave transaction ID from SDK callback


class RefundRequest(BaseModel):
    order_id: str
    reason:   Optional[str] = None


# ── Responses ─────────────────────────────────────────────────────────────────
class MpesaInitiateResponse(BaseModel):
    message:              str
    checkout_request_id:  str
    payment_id:           str


class PaymentVerifyResponse(BaseModel):
    message:    str
    payment_id: str
    order_id:   str


class PaymentRecord(BaseModel):
    id:           str
    order_id:     Optional[str]
    gateway:      str
    gateway_ref:  Optional[str]
    amount:       Decimal
    currency:     str
    status:       str
    created_at:   datetime
    completed_at: Optional[datetime]

    model_config = {"from_attributes": True}


class EarningsSummary(BaseModel):
    date:                str
    total_orders:        int
    gross_revenue:       Decimal
    commission_deducted: Decimal
    net_payout:          Decimal


class CourierEarningsSummary(BaseModel):
    date:          str
    deliveries:    int
    earned:        Decimal
    pending_payout: Decimal
    total_earned:  Decimal
