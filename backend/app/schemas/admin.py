from __future__ import annotations
from pydantic import BaseModel, Field
from typing import Optional
from datetime import datetime

from app.schemas.merchant import MerchantSummary
from app.schemas.courier import CourierProfileResponse


class RejectRequest(BaseModel):
    reason: str = Field(..., min_length=3, max_length=500)


class AdminMerchant(MerchantSummary):
    """Shop as an admin reviews it: public info plus payout details."""
    description:     Optional[str]
    payout_phone:    Optional[str]
    operating_hours: Optional[dict]
    created_at:      datetime


class AdminCourier(CourierProfileResponse):
    """Rider as an admin reviews it, including the last rejection reason."""
    rejection_reason: Optional[str] = None
