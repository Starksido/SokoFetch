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


# ── Delivery code ─────────────────────────────────────────────────────────────
class DeliveryCodeResponse(BaseModel):
    """Customer-only: the code to give the courier at handover."""
    order_id:      str
    delivery_code: str


class OrderTrackingResponse(BaseModel):
    """Polled by the customer app while an order is on its way."""
    order_id:              str
    status:                str
    courier_assigned:      bool
    courier_name:          Optional[str] = None     # First name only
    vehicle_type:          Optional[str] = None
    latitude:              Optional[float] = None   # Only while the delivery is live
    longitude:             Optional[float] = None
    location_updated_at:   Optional[str] = None
    estimated_delivery_at: Optional[datetime] = None
    picked_up_at:          Optional[datetime] = None
    delivered_at:          Optional[datetime] = None


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

    @field_validator("id", "merchant_id", mode="before")
    @classmethod
    def _stringify_uuid(cls, v):
        return str(v) if v is not None else v

    merchant_name:   Optional[str] = None
    status:          str
    total:           Decimal
    item_count:      int
    payment_method:  str
    payment_status:  str
    customer_rating: Optional[int] = None
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


class CourierActiveOrder(OrderDetail):
    """The courier's current order plus where to pick it up."""
    merchant_name:    Optional[str] = None
    merchant_address: Optional[str] = None
    merchant_lat:     Optional[Decimal] = None
    merchant_lon:     Optional[Decimal] = None
