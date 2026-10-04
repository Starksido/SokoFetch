"""
Merchant Service
================
Business logic for the merchant portal:
  - Shop onboarding and profile management
  - Menu catalog CRUD
  - Live order queue (pending orders)
  - Earnings and payout history
"""
import logging
from datetime import datetime, timezone
from decimal import Decimal

from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func
from sqlalchemy.orm import selectinload

from app.models.merchant import Merchant, MenuItem, MerchantStatus, MerchantCategory
from app.models.order import Order, OrderStatus, PaymentStatus
from app.core.repository import MerchantRepo, MenuItemRepo, OrderRepo
from app.core.rbac import assert_owns_merchant, assert_owns_menu_item
from app.core.exceptions import SokoFetchException, NotFoundError, AlreadyExistsError

log = logging.getLogger("alphabet.merchant.service")


# ── Onboard merchant ──────────────────────────────────────────────────────────
async def onboard_merchant(
    user_id: str,
    payload,
    db: AsyncSession,
) -> Merchant:
    """
    Register a new merchant shop.
    Starts in pending_review status until admin approves.
    """
    repo = MerchantRepo(db)

    # One shop per user
    existing = await repo.get_by(user_id=user_id)
    if existing:
        raise AlreadyExistsError("Merchant account")

    merchant = await repo.create(
        user_id          = user_id,
        shop_name        = payload.shop_name,
        description      = payload.description,
        category         = MerchantCategory(payload.category),
        address          = payload.address,
        city             = payload.city,
        latitude         = payload.latitude,
        longitude        = payload.longitude,
        avg_prep_minutes = payload.avg_prep_minutes,
        min_order_amount = payload.min_order_amount,
        payout_phone     = payload.payout_phone,
        operating_hours  = payload.operating_hours,
        status           = MerchantStatus.pending_review,
    )

    log.info("Merchant onboarded | id=%s | name=%s", merchant.id, merchant.shop_name)
    return await _with_menu(merchant, db)


# ── Eager-load menu for MerchantDetail responses ──────────────────────────────
async def _with_menu(merchant: Merchant, db: AsyncSession) -> Merchant:
    """
    MerchantDetail serialises menu_items. A lazy load during response
    serialisation raises MissingGreenlet under AsyncSession (→ 500), so load it
    explicitly before returning.
    """
    await db.refresh(merchant, attribute_names=["menu_items"])
    return merchant


# ── Get my merchant profile ───────────────────────────────────────────────────
async def get_my_merchant(user_id: str, db: AsyncSession) -> Merchant:
    result = await db.execute(
        select(Merchant)
        .options(selectinload(Merchant.menu_items))
        .where(Merchant.user_id == user_id)
    )
    merchant = result.scalar_one_or_none()
    if merchant is None:
        raise NotFoundError("Merchant")
    return merchant


# ── Update merchant profile ───────────────────────────────────────────────────
async def update_merchant(
    user_id: str,
    payload,
    db: AsyncSession,
) -> Merchant:
    repo     = MerchantRepo(db)
    merchant = await repo.get_by_or_404("Merchant", user_id=user_id)

    updates = {k: v for k, v in payload.model_dump().items() if v is not None}
    merchant = await repo.update(merchant, **updates)

    log.info("Merchant updated | id=%s", merchant.id)
    return await _with_menu(merchant, db)


# ── Toggle open/closed ────────────────────────────────────────────────────────
async def toggle_open(user_id: str, is_open: bool, db: AsyncSession) -> Merchant:
    repo     = MerchantRepo(db)
    merchant = await repo.get_by_or_404("Merchant", user_id=user_id)
    merchant = await repo.update(merchant, is_open=is_open)
    log.info("Merchant %s | id=%s", "opened" if is_open else "closed", merchant.id)
    return await _with_menu(merchant, db)


# ── Menu: list all items ──────────────────────────────────────────────────────
async def list_menu(user_id: str, db: AsyncSession) -> list[MenuItem]:
    merchant_repo = MerchantRepo(db)
    merchant      = await merchant_repo.get_by_or_404("Merchant", user_id=user_id)
    item_repo     = MenuItemRepo(db)
    return await item_repo.get_for_merchant(str(merchant.id))


# ── Menu: add item ────────────────────────────────────────────────────────────
async def add_menu_item(
    user_id: str,
    payload,
    db: AsyncSession,
) -> MenuItem:
    merchant_repo = MerchantRepo(db)
    merchant      = await merchant_repo.get_by_or_404("Merchant", user_id=user_id)

    if merchant.status == MerchantStatus.deactivated:
        raise SokoFetchException(422, "MERCHANT_DEACTIVATED", "Cannot add items to a deactivated merchant.")

    item_repo = MenuItemRepo(db)
    item = await item_repo.create(
        merchant_id  = str(merchant.id),
        name         = payload.name,
        description  = payload.description,
        category     = payload.category,
        price        = payload.price,
        discount_pct = payload.discount_pct,
        prep_minutes = payload.prep_minutes,
        is_available = payload.is_available,
        sort_order   = payload.sort_order,
    )

    log.info("Menu item added | merchant=%s | item=%s", merchant.id, item.name)
    return item


# ── Menu: update item ─────────────────────────────────────────────────────────
async def update_menu_item(
    user_id: str,
    item_id: str,
    payload,
    db: AsyncSession,
) -> MenuItem:
    merchant_repo = MerchantRepo(db)
    merchant      = await merchant_repo.get_by_or_404("Merchant", user_id=user_id)
    item_repo     = MenuItemRepo(db)
    item          = await item_repo.get_or_404(item_id, "Menu item")

    # Verify item belongs to this merchant
    if str(item.merchant_id) != str(merchant.id):
        from app.core.exceptions import ObjectAccessDeniedError
        raise ObjectAccessDeniedError()

    updates = {k: v for k, v in payload.model_dump().items() if v is not None}
    item    = await item_repo.update(item, **updates)

    log.info("Menu item updated | id=%s | merchant=%s", item_id, merchant.id)
    return item


# ── Menu: toggle availability ─────────────────────────────────────────────────
async def toggle_item_availability(
    user_id: str,
    item_id: str,
    is_available: bool,
    db: AsyncSession,
) -> MenuItem:
    merchant_repo = MerchantRepo(db)
    merchant      = await merchant_repo.get_by_or_404("Merchant", user_id=user_id)
    item_repo     = MenuItemRepo(db)
    item          = await item_repo.get_or_404(item_id, "Menu item")

    if str(item.merchant_id) != str(merchant.id):
        from app.core.exceptions import ObjectAccessDeniedError
        raise ObjectAccessDeniedError()

    item = await item_repo.update(item, is_available=is_available)
    return item


# ── Menu: delete item ─────────────────────────────────────────────────────────
async def delete_menu_item(
    user_id: str,
    item_id: str,
    db: AsyncSession,
) -> None:
    merchant_repo = MerchantRepo(db)
    merchant      = await merchant_repo.get_by_or_404("Merchant", user_id=user_id)
    item_repo     = MenuItemRepo(db)
    item          = await item_repo.get_or_404(item_id, "Menu item")

    if str(item.merchant_id) != str(merchant.id):
        from app.core.exceptions import ObjectAccessDeniedError
        raise ObjectAccessDeniedError()

    await item_repo.delete(item)
    log.info("Menu item deleted | id=%s", item_id)


# ── Live order queue ──────────────────────────────────────────────────────────
async def get_live_orders(user_id: str, db: AsyncSession) -> list[Order]:
    """
    All active (non-terminal) orders for the merchant.
    Used by the merchant portal real-time dashboard.
    """
    merchant_repo = MerchantRepo(db)
    merchant      = await merchant_repo.get_by_or_404("Merchant", user_id=user_id)

    terminal = {
        OrderStatus.delivered,
        OrderStatus.cancelled,
        OrderStatus.delivery_failed,
    }
    stmt = (
        select(Order)
        .where(
            Order.merchant_id == str(merchant.id),
            Order.status.not_in([s.value for s in terminal]),
        )
        .order_by(Order.created_at.asc())
    )
    result = await db.execute(stmt)
    return list(result.scalars().all())


# ── Weekly earnings breakdown ─────────────────────────────────────────────────
async def get_weekly_earnings(user_id: str, db: AsyncSession) -> list[dict]:
    """Daily earnings for the last 7 days."""
    from sqlalchemy import cast, Date
    merchant_repo = MerchantRepo(db)
    merchant      = await merchant_repo.get_by_or_404("Merchant", user_id=user_id)

    stmt = (
        select(
            cast(Order.created_at, Date).label("date"),
            func.count(Order.id).label("orders"),
            func.coalesce(func.sum(Order.subtotal), 0).label("gross"),
            func.coalesce(func.sum(Order.merchant_commission), 0).label("commission"),
        )
        .where(
            Order.merchant_id    == str(merchant.id),
            Order.payment_status == PaymentStatus.paid,
        )
        .group_by(cast(Order.created_at, Date))
        .order_by(cast(Order.created_at, Date).desc())
        .limit(7)
    )
    result = await db.execute(stmt)
    rows   = result.all()

    return [
        {
            "date":               str(row.date),
            "total_orders":       row.orders,
            "gross_revenue":      Decimal(str(row.gross)),
            "commission_deducted": Decimal(str(row.commission)),
            "net_payout":         Decimal(str(row.gross)) - Decimal(str(row.commission)),
        }
        for row in rows
    ]


# ── Customer-facing: list active merchants ────────────────────────────────────
async def list_active_merchants(
    db: AsyncSession,
    offset: int = 0,
    limit:  int = 20,
    category: str | None = None,
) -> list[Merchant]:
    repo    = MerchantRepo(db)
    filters = [Merchant.status == MerchantStatus.active]
    if category:
        filters.append(Merchant.category == MerchantCategory(category))
    return await repo.list(*filters, order_by=Merchant.rating.desc(),
                           offset=offset, limit=limit)


# ── Customer-facing: get merchant menu ───────────────────────────────────────
async def get_merchant_menu(merchant_id: str, db: AsyncSession) -> tuple[Merchant, list[MenuItem]]:
    merchant_repo = MerchantRepo(db)
    merchant      = await merchant_repo.get_or_404(merchant_id, "Merchant")
    if merchant.status != MerchantStatus.active:
        # Pending/suspended shops are not visible to customers
        raise NotFoundError("Merchant")
    item_repo     = MenuItemRepo(db)
    items         = await item_repo.get_available_for_merchant(str(merchant.id))
    return merchant, items


