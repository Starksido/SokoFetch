"""
Create test shops and riders waiting for admin review (development only).

    cd backend
    poetry run python -m scripts.seed_review_accounts

Creates two shops pending review and two riders: one with all documents
(can be approved) and one missing documents (approval is refused). Numbers
that already have an account are skipped, so it is safe to re-run. Each
account can also log in: request an OTP for its number and read the code
from the backend log (DEV MODE).

Document records point at S3 keys that don't exist unless S3 is set up, so
the admin screen shows "Could not fetch the document" for their images.
"""
import asyncio
import sys
from decimal import Decimal

from sqlalchemy import select

from app.auth.otp import validate_phone
from app.auth.service import _phone_hash
from app.core.config import settings
from app.core.database import AsyncSessionLocal
from app.models.courier import (
    Courier, CourierDocument, CourierStatus, DocumentType, VehicleType,
)
from app.models.merchant import Merchant, MerchantCategory, MerchantStatus
from app.models.user import User, UserRole

SHOPS = [
    dict(phone="0700000101", shop_name="Test Shop · Mama Mboga Greens",
         category=MerchantCategory.grocery, address="Stall 12, Westlands Market",
         latitude=Decimal("-1.2676"), longitude=Decimal("36.8108"),
         description="Fresh vegetables and fruit, delivered daily."),
    dict(phone="0700000102", shop_name="Test Shop · Kibanda Grill",
         category=MerchantCategory.restaurant, address="Moi Avenue, opposite Hilton",
         latitude=Decimal("-1.2849"), longitude=Decimal("36.8228"),
         description="Nyama choma, chips and soda."),
]

ALL_DOCS = list(DocumentType)
RIDERS = [
    dict(phone="0700000201", full_name="Test Rider · Juma Otieno",
         vehicle_type=VehicleType.motorcycle, vehicle_plate="KMDA 123A",
         status=CourierStatus.documents_submitted, docs=ALL_DOCS),
    dict(phone="0700000202", full_name="Test Rider · Wanjiru Kamau (missing docs)",
         vehicle_type=VehicleType.bicycle, vehicle_plate=None,
         status=CourierStatus.under_review,
         docs=[DocumentType.national_id_front, DocumentType.national_id_back,
               DocumentType.vehicle_photo]),
]


async def _new_user(db, phone: str, role: UserRole) -> User | None:
    phone = validate_phone(phone)
    existing = (await db.execute(
        select(User).where(User.phone_hash == _phone_hash(phone))
    )).scalar_one_or_none()
    if existing is not None:
        print(f"skip   {phone}: already has a {existing.role.value} account")
        return None
    user = User(phone=phone, phone_hash=_phone_hash(phone), role=role, is_verified=True)
    db.add(user)
    await db.flush()
    return user


async def main() -> int:
    if settings.ENVIRONMENT == "production":
        print("Refusing to seed test accounts in production.")
        return 1

    async with AsyncSessionLocal() as db:
        for s in SHOPS:
            user = await _new_user(db, s["phone"], UserRole.merchant)
            if user is None:
                continue
            db.add(Merchant(
                user_id=user.id, shop_name=s["shop_name"], category=s["category"],
                address=s["address"], city="Nairobi", latitude=s["latitude"],
                longitude=s["longitude"], description=s["description"],
                payout_phone=user.phone, status=MerchantStatus.pending_review,
            ))
            print(f"shop   {user.phone}: {s['shop_name']} (pending review)")

        for r in RIDERS:
            user = await _new_user(db, r["phone"], UserRole.courier)
            if user is None:
                continue
            courier = Courier(
                user_id=user.id, full_name=r["full_name"], vehicle_type=r["vehicle_type"],
                vehicle_plate=r["vehicle_plate"], status=r["status"], payout_phone=user.phone,
            )
            db.add(courier)
            await db.flush()
            for doc_type in r["docs"]:
                db.add(CourierDocument(
                    courier_id=courier.id, doc_type=doc_type,
                    s3_key=f"seed/{courier.id}/{doc_type.value}",
                ))
            print(f"rider  {user.phone}: {r['full_name']} "
                  f"({r['status'].value}, {len(r['docs'])}/{len(ALL_DOCS)} documents)")

        await db.commit()
    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
