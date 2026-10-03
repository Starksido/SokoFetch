from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.auth.guards import require_role
from app.customer import service
from app.schemas.customer import (
    CustomerOnboardRequest,
    CustomerUpdateRequest,
    CustomerProfile,
    DeliveryAddressCreate,
    DeliveryAddressResponse,
    GoogleVerifyRequest,
)
from app.schemas.common import MessageResponse

router = APIRouter()


# -- POST /customer/onboard --------------------------------------------------
@router.post(
    "/onboard",
    response_model=CustomerProfile,
    status_code=201,
    summary="Create customer profile",
)
async def onboard(
    body: CustomerOnboardRequest,
    user: dict        = Depends(require_role("customer")),
    db:   AsyncSession = Depends(get_db),
):
    customer = await service.onboard_customer(user_id=user["sub"], payload=body, db=db)
    return CustomerProfile.from_customer(customer)


# -- GET /customer/me ---------------------------------------------------------
@router.get(
    "/me",
    response_model=CustomerProfile,
    summary="Get my profile",
)
async def get_my_profile(
    user: dict        = Depends(require_role("customer")),
    db:   AsyncSession = Depends(get_db),
):
    customer = await service.get_my_profile(user_id=user["sub"], db=db)
    return CustomerProfile.from_customer(customer)


# -- PUT /customer/me ---------------------------------------------------------
@router.put(
    "/me",
    response_model=CustomerProfile,
    summary="Update my profile",
)
async def update_profile(
    body: CustomerUpdateRequest,
    user: dict        = Depends(require_role("customer")),
    db:   AsyncSession = Depends(get_db),
):
    customer = await service.update_profile(user_id=user["sub"], payload=body, db=db)
    return CustomerProfile.from_customer(customer)


# -- POST /customer/addresses ------------------------------------------------
@router.post(
    "/addresses",
    response_model=DeliveryAddressResponse,
    status_code=201,
    summary="Add a delivery address",
)
async def add_address(
    body: DeliveryAddressCreate,
    user: dict        = Depends(require_role("customer")),
    db:   AsyncSession = Depends(get_db),
):
    return await service.add_address(user_id=user["sub"], payload=body, db=db)


# -- GET /customer/addresses -------------------------------------------------
@router.get(
    "/addresses",
    response_model=list[DeliveryAddressResponse],
    summary="List my delivery addresses",
)
async def list_addresses(
    user: dict        = Depends(require_role("customer")),
    db:   AsyncSession = Depends(get_db),
):
    return await service.list_addresses(user_id=user["sub"], db=db)


# -- DELETE /customer/addresses/{address_id} ---------------------------------
@router.delete(
    "/addresses/{address_id}",
    response_model=MessageResponse,
    summary="Delete a delivery address",
)
async def delete_address(
    address_id: str,
    user:       dict        = Depends(require_role("customer")),
    db:         AsyncSession = Depends(get_db),
):
    await service.delete_address(user_id=user["sub"], address_id=address_id, db=db)
    return {"message": "Address deleted"}


# -- POST /customer/verify-google --------------------------------------------
@router.post(
    "/verify-google",
    response_model=CustomerProfile,
    summary="Verify Google account and link to profile",
)
async def verify_google(
    body: GoogleVerifyRequest,
    user: dict        = Depends(require_role("customer")),
    db:   AsyncSession = Depends(get_db),
):
    customer = await service.verify_google_account(user_id=user["sub"], id_token_str=body.id_token, db=db)
    return CustomerProfile.from_customer(customer)
