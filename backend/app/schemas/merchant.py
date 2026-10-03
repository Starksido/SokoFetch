from __future__ import annotations
from pydantic import BaseModel, Field, model_validator
from typing import Optional, List
from decimal import Decimal
from datetime import datetime
from uuid import UUID


# ── Menu Item ─────────────────────────────────────────────────────────────────
class MenuItemCreate(BaseModel):
    name:         str        = Field(..., min_length=1, max_length=255)
    description:  Optional[str] = None
    category:     str        = Field(..., min_length=1, max_length=128)
    price:        Decimal    = Field(..., gt=0)
    discount_pct: Decimal    = Field(0, ge=0, le=100)
    prep_minutes: int        = Field(15, ge=1, le=180)
    is_available: bool       = True
    sort_order:   int        = 0


class MenuItemUpdate(BaseModel):
    name:         Optional[str]     = None
    description:  Optional[str]     = None
    category:     Optional[str]     = None
    price:        Optional[Decimal] = Field(None, gt=0)
    discount_pct: Optional[Decimal] = Field(None, ge=0, le=100)
    prep_minutes: Optional[int]     = Field(None, ge=1, le=180)
    is_available: Optional[bool]    = None
    sort_order:   Optional[int]     = None


class MenuItemResponse(BaseModel):
    id:            UUID
    merchant_id:   UUID
    name:          str
    description:   Optional[str]
    category:      str
    photo_url:     Optional[str]
    price:         Decimal
    discount_pct:  Decimal
    effective_price: float
    prep_minutes:  int
    is_available:  bool
    sort_order:    int
    created_at:    datetime
    updated_at:    datetime

    model_config = {"from_attributes": True}


# ── Merchant ──────────────────────────────────────────────────────────────────
class MerchantOnboardRequest(BaseModel):
    shop_name:        str     = Field(..., min_length=2, max_length=255)
    description:      Optional[str] = None
    category:         str
    address:          str     = Field(..., min_length=5)
    city:             str     = Field("Nairobi", max_length=128)
    latitude:         Optional[Decimal] = None
    longitude:        Optional[Decimal] = None
    avg_prep_minutes: int     = Field(20, ge=5, le=120)
    min_order_amount: Decimal = Field(0, ge=0)
    payout_phone:     Optional[str] = None
    operating_hours:  Optional[dict] = None


class MerchantUpdateRequest(BaseModel):
    shop_name:        Optional[str]     = Field(None, min_length=2, max_length=255)
    description:      Optional[str]     = None
    address:          Optional[str]     = None
    avg_prep_minutes: Optional[int]     = Field(None, ge=5, le=120)
    min_order_amount: Optional[Decimal] = Field(None, ge=0)
    payout_phone:     Optional[str]     = None
    operating_hours:  Optional[dict]    = None
    is_open:          Optional[bool]    = None


class MerchantSummary(BaseModel):
    """Lightweight — used in customer-facing merchant list."""
    id:               UUID
    shop_name:        str
    category:         str
    logo_url:         Optional[str]
    banner_url:       Optional[str]
    address:          str
    city:             str
    latitude:         Optional[Decimal]
    longitude:        Optional[Decimal]
    rating:           Decimal
    rating_count:     int
    avg_prep_minutes: int
    min_order_amount: Decimal
    is_open:          bool
    status:           str

    model_config = {"from_attributes": True}


class MerchantDetail(MerchantSummary):
    """Full detail — includes menu and financial info for the merchant themselves."""
    commission_rate:  Decimal
    payout_phone:     Optional[str]
    operating_hours:  Optional[dict]
    menu_items:       List[MenuItemResponse] = []
    created_at:       datetime

    model_config = {"from_attributes": True}


class MerchantEarningsSummary(BaseModel):
    date:               str
    total_orders:       int
    gross_revenue:      Decimal
    commission_deducted: Decimal
    net_payout:         Decimal

