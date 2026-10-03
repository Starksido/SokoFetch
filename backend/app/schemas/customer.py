from __future__ import annotations
from pydantic import BaseModel, Field
from typing import Optional, List
from decimal import Decimal
from datetime import datetime
from uuid import UUID


# -- Customer profile --------------------------------------------------------
class CustomerOnboardRequest(BaseModel):
    full_name: str = Field(..., min_length=2, max_length=255)
    email:     Optional[str] = None


class GoogleVerifyRequest(BaseModel):
    id_token: str = Field(..., min_length=10)


class CustomerUpdateRequest(BaseModel):
    full_name: Optional[str] = Field(None, min_length=2, max_length=255)
    email:     Optional[str] = None


class CustomerProfile(BaseModel):
    id:                 UUID
    full_name:          Optional[str]
    email:              Optional[str]
    avatar_url:         Optional[str]
    wallet_balance:     Decimal
    google_verified:    bool = False
    created_at:         datetime
    model_config = {"from_attributes": True}

    @classmethod
    def from_customer(cls, customer):
        return cls(
            id=customer.id,
            full_name=customer.full_name,
            email=customer.email,
            avatar_url=customer.avatar_url,
            wallet_balance=customer.wallet_balance,
            google_verified=customer.google_id is not None,
            created_at=customer.created_at,
        )


# -- Delivery addresses ------------------------------------------------------
class DeliveryAddressCreate(BaseModel):
    label:        str            = Field(..., min_length=1, max_length=64)
    address_line: str            = Field(..., min_length=5, max_length=512)
    city:         str            = Field("Nairobi", max_length=128)
    latitude:     Optional[Decimal] = None
    longitude:    Optional[Decimal] = None
    instructions: Optional[str]  = None
    is_default:   bool           = False


class DeliveryAddressResponse(BaseModel):
    id:           UUID
    label:        str
    address_line: str
    city:         str
    latitude:     Optional[Decimal]
    longitude:    Optional[Decimal]
    instructions: Optional[str]
    is_default:   bool
    created_at:   datetime
    model_config = {"from_attributes": True}