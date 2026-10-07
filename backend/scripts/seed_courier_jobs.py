"""
Create paid, unassigned orders that show up as courier jobs (development only).

    cd backend
    poetry run python -m scripts.seed_courier_jobs

Uses the test shop "Mama Mboga Greens" (0700000101, from seed_review_accounts),
which must be approved first. Creates the test customer 0700000301 if needed,
gives the shop a small menu if it has none, then places three orders through
the real order and payment code (pricing, delivery code, shop payout) at
different stages: confirmed, preparing and ready for pickup. Each run adds
three more jobs.

A courier sees them once approved and online (e.g. the test rider 0700000201,
approved in the admin panel).
"""
import asyncio
import secrets
import sys
from decimal import Decimal

from sqlalchemy import select

from app.auth.otp import validate_phone
from app.auth.service import _phone_hash
from app.core.config import settings
from app.core.database import AsyncSessionLocal
from app.core.redis import redis_client
from app.models.customer import Customer
from app.models.merchant import Merchant, MenuItem, MerchantStatus
from app.models.order import OrderStatus
from app.models.user import User, UserRole
from app.orders.service import create_order
from app.payments.service import _mark_order_paid
from app.schemas.order import OrderCreateRequest, OrderItemRequest

CUSTOMER_PHONE = "0700000301"
CUSTOMER_NAME = "Test Customer · Amina Wanjiku"
SHOP_PHONE = "0700000101"

MENU = [
    ("Sukuma wiki (bunch)", "Vegetables", Decimal("30")),
    ("Tomatoes (1 kg)", "Vegetables", Decimal("120")),
    ("Avocados (4 pcs)", "Fruit", Decimal("100")),
    ("Bananas (dozen)", "Fruit", Decimal("150")),
]

# (address, latitude, longitude, notes, status the shop has moved it to)
ORDERS = [
    ("Kileleshwa, Othaya Road, Apt 4B", Decimal("-1.2789"), Decimal("36.7848"),
     "Call on arrival", OrderStatus.confirmed),
    ("Kilimani, Argwings Kodhek Rd, Gate 2", Decimal("-1.2921"), Decimal("36.7856"),
     None, OrderStatus.preparing),
    ("Parklands, 3rd Avenue, House 12", Decimal("-1.2620"), Decimal("36.8180"),
     "Leave with the guard", OrderStatus.ready_for_pickup),
]


async def _user_by_phone(db, phone: str) -> User | None:
    return (await db.execute(
        select(User).where(User.phone_hash == _phone_hash(validate_phone(phone)))
    )).scalar_one_or_none()


async def _customer(db) -> User:
    user = await _user_by_phone(db, CUSTOMER_PHONE)
    if user is None:
        phone = validate_phone(CUSTOMER_PHONE)
        user = User(phone=phone, phone_hash=_phone_hash(phone),
                    role=UserRole.customer, is_verified=True)
        db.add(user)
        await db.flush()
        print(f"customer {phone}: created")
    elif user.role != UserRole.customer:
        raise SystemExit(f"{CUSTOMER_PHONE} already has a {user.role.value} account.")

    profile = (await db.execute(
        select(Customer).where(Customer.user_id == user.id)
    )).scalar_one_or_none()
    if profile is None:
        db.add(Customer(user_id=user.id, full_name=CUSTOMER_NAME))
        await db.flush()
    return user


async def _shop(db) -> Merchant:
    user = await _user_by_phone(db, SHOP_PHONE)
    merchant = None if user is None else (await db.execute(
        select(Merchant).where(Merchant.user_id == user.id)
    )).scalar_one_or_none()
    if merchant is None:
        raise SystemExit("Test shop not found. Run scripts.seed_review_accounts first.")
    if merchant.status != MerchantStatus.active:
        raise SystemExit(f"{merchant.shop_name} is {merchant.status.value}. "
                         "Approve it in the admin panel first.")
    merchant.is_open = True
    return merchant


async def _menu(db, merchant: Merchant) -> list[MenuItem]:
    items = (await db.execute(
        select(MenuItem).where(MenuItem.merchant_id == merchant.id, MenuItem.is_available)
    )).scalars().all()
    if items:
        return list(items)
    items = [
        MenuItem(merchant_id=merchant.id, name=name, category=category, price=price,
                 sort_order=i)
        for i, (name, category, price) in enumerate(MENU)
    ]
    db.add_all(items)
    await db.flush()
    print(f"menu     {merchant.shop_name}: added {len(items)} items")
    return items


async def main() -> int:
    if settings.ENVIRONMENT == "production":
        print("Refusing to seed test orders in production.")
        return 1

    async with AsyncSessionLocal() as db:
        customer = await _customer(db)
        merchant = await _shop(db)
        menu = await _menu(db, merchant)

        for n, (address, lat, lon, notes, status) in enumerate(ORDERS):
            picks = [menu[(n + k) % len(menu)] for k in range(2)]
            order = await create_order(
                customer_user_id=str(customer.id),
                payload=OrderCreateRequest(
                    merchant_id=str(merchant.id),
                    items=[OrderItemRequest(item_id=str(i.id), quantity=1 + k)
                           for k, i in enumerate(picks)],
                    delivery_address=address,
                    delivery_latitude=lat,
                    delivery_longitude=lon,
                    delivery_notes=notes,
                    payment_method="mpesa",
                ),
                db=db,
                redis=redis_client,
            )
            await _mark_order_paid(str(order.id), f"SEED{secrets.token_hex(4).upper()}", db)
            order.status = status
            await db.flush()
            print(f"order    {order.id} | {status.value:<16} | {address} | "
                  f"total KES {order.total} | rider gets KES {order.courier_payout}")

        await db.commit()
    await redis_client.aclose()
    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
