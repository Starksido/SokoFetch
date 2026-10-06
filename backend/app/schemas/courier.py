from __future__ import annotations
from pydantic import BaseModel, Field, field_validator
from typing import Optional, List
from decimal import Decimal
from datetime import datetime


class CourierOnboardRequest(BaseModel):
    full_name:     str = Field(..., min_length=2, max_length=128)
    vehicle_type:  str = Field(..., pattern="^(motorcycle|bicycle|on_foot)$")
    vehicle_plate: Optional[str] = Field(None, max_length=20)


class CourierProfileUpdate(BaseModel):
    full_name:    Optional[str] = Field(None, min_length=2, max_length=128)
    vehicle_type: Optional[str] = None
    vehicle_plate: Optional[str] = Field(None, max_length=20)
    payout_phone:  Optional[str] = None
    fcm_token:     Optional[str] = None


class CourierDocumentResponse(BaseModel):
    id:          str
    doc_type:    str
    is_verified: bool
    verified_at: Optional[datetime]
    uploaded_at: datetime
    model_config = {"from_attributes": True}


class CourierProfileResponse(BaseModel):
    id:                  str
    user_id:             str

    @field_validator("id", "user_id", mode="before")
    @classmethod
    def _stringify_uuid(cls, v):
        return str(v) if v is not None else v

    full_name:           Optional[str]
    vehicle_type:        str
    vehicle_plate:       Optional[str]
    status:              str
    is_online:           bool
    rating:              Decimal
    rating_count:        int
    total_deliveries:    int
    total_earned:        Decimal
    pending_payout:      Decimal
    documents:           List[CourierDocumentResponse] = []
    documents_verified_at: Optional[datetime]
    created_at:          datetime
    model_config = {"from_attributes": True}


class CourierLocationUpdate(BaseModel):
    latitude:  Decimal = Field(..., ge=-90,  le=90)
    longitude: Decimal = Field(..., ge=-180, le=180)
    order_id:  Optional[str] = None


class CourierEarningsDay(BaseModel):
    date:        str
    deliveries:  int
    earned:      Decimal


class DocumentUploadResponse(BaseModel):
    doc_type:   str
    message:    str
    status:     str

class CourierJob(BaseModel):
    """An unassigned, paid order a courier can accept."""
    order_id:             str
    status:               str
    merchant_name:        str
    merchant_address:     str
    merchant_latitude:    Optional[Decimal]
    merchant_longitude:   Optional[Decimal]
    item_count:           int
    courier_payout:       Optional[Decimal]
    pickup_distance_km:   Optional[float]   # Courier → shop
    delivery_distance_km: Optional[float]   # Shop → customer
    created_at:           datetime
