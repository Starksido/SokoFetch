from __future__ import annotations
from pydantic import BaseModel, Field, field_validator
from typing import Optional, List
from decimal import Decimal
from datetime import datetime


# ── Line item ─────────────────────────────────────────────────────────────────
class OrderItemRequest(BaseModel):
    item_id:  str
    quantity: int = Field(..., ge=1, le=50)


class OrderItemSnapshot(BaseModel):
    """Immutable snapshot stored on the order — preserves prices at order time."""
    item_id:    str
    name:       str
    qty:        int
    unit_price: Decimal
    subtotal:   Decimal


# ── Create ────────────────────────────────────────────────────────────────────
class OrderCreateRequest(BaseModel):
    merchant_id:          str
    items:                List[OrderItemRequest] = Field(..., min_length=1)
    delivery_address:     str = Field(..., min_length=5)
    delivery_latitude:    Optional[Decimal] = None
    delivery_longitude:   Optional[Decimal] = None
    delivery_notes:       Optional[str]     = None
    special_instructions: Optional[str]     = None
    payment_method:       str               = Field(..., pattern="^(mpesa|card|wallet)$")


# ── Status update ─────────────────────────────────────────────────────────────
class OrderStatusUpdate(BaseModel):
    status:               str
    cancellation_reason:  Optional[str] = None

    @field_validator("status")
    @classmethod
    def valid_status(cls, v: str) -> str:
        from app.models.order import OrderStatus
        try:
            OrderStatus(v)
        except ValueError:
            raise ValueError(f"Invalid order status: {v}")
        return v


# ── Proof of delivery ─────────────────────────────────────────────────────────
class ProofOfDeliveryRequest(BaseModel):
    proof_type:  str = Field(..., pattern="^(photo|otp)$")
    otp_code:    Optional[str] = Field(None, min_length=4, max_length=6)
    # photo is uploaded as multipart — not in JSON body


# ── Rating ────────────────────────────────────────────────────────────────────
class OrderRatingRequest(BaseModel):
    courier_rating:  Optional[int] = Field(None, ge=1, le=5)
    merchant_rating: Optional[int] = Field(None, ge=1, le=5)
    review:          Optional[str] = Field(None, max_length=500)


# ── Responses ─────────────────────────────────────────────────────────────────
class OrderSummary(BaseModel):
    """Lightweight — for list views."""
    id:              str
    merchant_id:     str
    merchant_name:   Optional[str] = None
    status:          str
    total:           Decimal
    item_count:      int
    payment_method:  str
    payment_status:  str
    created_at:      datetime

    model_config = {"from_attributes": True}


class OrderDetail(BaseModel):
    """Full order — for detail views."""
    id:                   str
    customer_id:          str
    merchant_id:          str
    courier_id:           Optional[str]

    @field_validator("id", "customer_id", "merchant_id", "courier_id", mode="before")
    @classmethod
    def _stringify_uuid(cls, v):
        return str(v) if v is not None else v

    items:                list
    item_count:           int
    subtotal:             Decimal
    delivery_fee:         Decimal
    surge_multiplier:     Decimal
    platform_fee:         Decimal
    merchant_commission:  Decimal
    courier_payout:       Optional[Decimal]
    total:                Decimal
    payment_method:       str
    payment_status:       str
    payment_ref:          Optional[str]
    delivery_address:     str
    delivery_latitude:    Optional[Decimal]
    delivery_longitude:   Optional[Decimal]
    delivery_notes:       Optional[str]
    special_instructions: Optional[str]
    status:               str
    cancellation_reason:  Optional[str]
    proof_type:           Optional[str]
    estimated_pickup_at:  Optional[datetime]
    estimated_delivery_at: Optional[datetime]
    picked_up_at:         Optional[datetime]
    delivered_at:         Optional[datetime]
    customer_rating:      Optional[int]
    merchant_rating:      Optional[int]
    created_at:           datetime
    updated_at:           datetime

    model_config = {"from_attributes": True}


class CourierLocationResponse(BaseModel):
    """Real-time courier location pushed to customer during tracking."""
    latitude:     Decimal
    longitude:    Decimal
    eta_minutes:  Optional[int]
    updated_at:   str
