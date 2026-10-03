"""
Customer Service
================
Business logic for the customer portal:
  - Profile onboarding and management
  - Saved delivery addresses
"""
import logging
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.customer import Customer, DeliveryAddress
from app.core.repository import CustomerRepo, DeliveryAddressRepo
from app.core.exceptions import NotFoundError, AlreadyExistsError

log = logging.getLogger("alphabet.customer.service")


# -- Onboard customer ---------------------------------------------------------
async def onboard_customer(
    user_id: str,
    payload,
    db: AsyncSession,
) -> Customer:
    """
    Create the customer profile for a user who just signed up.
    One profile per user.
    """
    repo = CustomerRepo(db)

    existing = await repo.get_by_user_id(user_id)
    if existing:
        raise AlreadyExistsError("Customer profile")

    customer = await repo.create(
        user_id=user_id,
        full_name=payload.full_name,
        email=payload.email,
    )
    await db.commit()
    log.info("Customer onboarded user_id=%s", user_id)
    return customer


# -- Get my profile -----------------------------------------------------------
async def get_my_profile(user_id: str, db: AsyncSession) -> Customer:
    repo = CustomerRepo(db)
    return await repo.get_by_or_404("Customer profile", user_id=user_id)


# -- Update profile -----------------------------------------------------------
async def update_profile(
    user_id: str,
    payload,
    db: AsyncSession,
) -> Customer:
    repo = CustomerRepo(db)
    customer = await repo.get_by_or_404("Customer profile", user_id=user_id)

    updates = {k: v for k, v in payload.model_dump().items() if v is not None}
    customer = await repo.update(customer, **updates)
    await db.commit()
    return customer


# -- Delivery addresses -------------------------------------------------------
async def add_address(
    user_id: str,
    payload,
    db: AsyncSession,
) -> DeliveryAddress:
    customer_repo = CustomerRepo(db)
    customer = await customer_repo.get_by_or_404("Customer profile", user_id=user_id)

    address_repo = DeliveryAddressRepo(db)

    # If this is marked default, unset any existing default first
    if payload.is_default:
        existing_addresses = await address_repo.get_for_customer(str(customer.id))
        for addr in existing_addresses:
            if addr.is_default:
                await address_repo.update(addr, is_default=False)

    address = await address_repo.create(
        customer_id=customer.id,
        label=payload.label,
        address_line=payload.address_line,
        city=payload.city,
        latitude=payload.latitude,
        longitude=payload.longitude,
        instructions=payload.instructions,
        is_default=payload.is_default,
    )
    await db.commit()
    return address


async def list_addresses(user_id: str, db: AsyncSession) -> list[DeliveryAddress]:
    customer_repo = CustomerRepo(db)
    customer = await customer_repo.get_by_or_404("Customer profile", user_id=user_id)

    address_repo = DeliveryAddressRepo(db)
    return await address_repo.get_for_customer(str(customer.id))


async def delete_address(user_id: str, address_id: str, db: AsyncSession) -> None:
    customer_repo = CustomerRepo(db)
    customer = await customer_repo.get_by_or_404("Customer profile", user_id=user_id)

    address_repo = DeliveryAddressRepo(db)
    address = await address_repo.get_or_404(address_id, label="Delivery address")

    if str(address.customer_id) != str(customer.id):
        raise NotFoundError("Delivery address")

    await address_repo.delete(address)
    await db.commit()



# -- Google account verification -----------------------------------------------
async def verify_google_account(user_id: str, id_token_str: str, db: AsyncSession) -> Customer:
    """
    Verify a Google ID token and link the Google account to this customer.
    Stores the verified email and Google subject ID.
    """
    from google.oauth2 import id_token as google_id_token
    from google.auth.transport import requests as google_requests
    from app.core.config import settings
    from app.core.exceptions import SokoFetchException
    from sqlalchemy import select

    try:
        idinfo = google_id_token.verify_oauth2_token(
            id_token_str,
            google_requests.Request(),
            settings.GOOGLE_OAUTH_CLIENT_ID,
        )
    except ValueError as exc:
        raise SokoFetchException(401, "INVALID_GOOGLE_TOKEN", f"Google token verification failed: {exc}")

    google_sub = idinfo["sub"]
    google_email = idinfo.get("email")

    repo = CustomerRepo(db)
    customer = await repo.get_by_or_404("Customer profile", user_id=user_id)

    # Prevent another account from claiming the same Google identity
    existing = await db.execute(select(Customer).where(Customer.google_id == google_sub))
    other = existing.scalar_one_or_none()
    if other and str(other.id) != str(customer.id):
        raise SokoFetchException(409, "GOOGLE_ACCOUNT_LINKED", "This Google account is already linked to another profile.")

    from datetime import datetime, timezone
    updates = {"google_id": google_sub, "google_verified_at": datetime.now(timezone.utc)}
    if google_email and not customer.email:
        updates["email"] = google_email

    customer = await repo.update(customer, **updates)
    await db.commit()
    log.info("Google account verified | user_id=%s | google_sub=%s", user_id, google_sub)
    return customer
