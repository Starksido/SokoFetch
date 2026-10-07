"""
Create test shops and riders waiting for admin review (development only).

    cd backend
    poetry run python -m scripts.seed_review_accounts

Creates two shops pending review and two riders: one with all documents
(can be approved) and one missing documents (approval is refused). Numbers
that already have an account are skipped, so it is safe to re-run. Each
account can also log in: request an OTP for its number and read the code
from the backend log (DEV MODE).

Each rider document gets a placeholder image (a coloured card per document
type), encrypted and saved through the document store like a real upload, so
the admin screen can show it. Re-running fills in any that are missing.
"""
import asyncio
import struct
import sys
import zlib
from decimal import Decimal

from sqlalchemy import select

from app.auth.otp import validate_phone
from app.auth.service import _phone_hash
from app.core import document_store
from app.core.config import settings
from app.core.document_store import DocumentStoreError
from app.core.encryption import encrypt_document
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


# Card colour per document type, so the placeholders are easy to tell apart
_DOC_COLOURS = {
    DocumentType.national_id_front: (0x00, 0x6A, 0x62),
    DocumentType.national_id_back:  (0x00, 0x4F, 0x49),
    DocumentType.driving_license:   (0xAB, 0x35, 0x00),
    DocumentType.vehicle_photo:     (0xF5, 0xA6, 0x23),
    DocumentType.selfie_with_id:    (0x59, 0x41, 0x39),
}


def _placeholder_png(colour: tuple[int, int, int], w: int = 480, h: int = 300) -> bytes:
    """An ID-card-like image: coloured card, light photo box, text lines."""
    def pixel(x: int, y: int) -> tuple[int, int, int]:
        if 30 <= x < 150 and 60 <= y < 220:                         # Photo box
            return (0xF3, 0xF4, 0xF5)
        if 180 <= x < 440 and any(y0 <= y < y0 + 14 for y0 in (70, 110, 150, 190)):
            return (0xFF, 0xFF, 0xFF)                                # Text lines
        if y < 36:                                                   # Header band
            return tuple(c // 2 for c in colour)
        return colour

    rows = b"".join(
        b"\x00" + b"".join(bytes(pixel(x, y)) for x in range(w)) for y in range(h)
    )

    def chunk(kind: bytes, data: bytes) -> bytes:
        return (struct.pack(">I", len(data)) + kind + data
                + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF))

    return (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(rows, 9))
            + chunk(b"IEND", b""))


async def _store_placeholders(db) -> int:
    """Give every seeded document an image if it doesn't have one yet."""
    docs = (await db.execute(
        select(CourierDocument).where(CourierDocument.s3_key.like("seed/%"))
    )).scalars().all()
    stored = 0
    for doc in docs:
        try:
            document_store.get(doc.s3_key)
            continue
        except DocumentStoreError:
            pass
        png = _placeholder_png(_DOC_COLOURS[doc.doc_type])
        document_store.put(doc.s3_key, encrypt_document(png))
        stored += 1
    return stored


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

        stored = await _store_placeholders(db)
        print(f"images {stored} placeholder document(s) saved "
              f"({settings.document_storage} storage)")
    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
