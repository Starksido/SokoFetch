from fastapi import APIRouter, Depends, Query
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.auth.guards import get_current_user, require_role
from app.merchant import service
from app.schemas.merchant import (
    MerchantOnboardRequest,
    MerchantUpdateRequest,
    MerchantDetail,
    MerchantPublicDetail,
    MerchantSummary,
    MenuItemCreate,
    MenuItemUpdate,
    MenuItemResponse,
    MerchantEarningsSummary,
)
from app.schemas.order import OrderDetail
from app.schemas.common import MessageResponse

router = APIRouter()


# ═════════════════════════════════════════════════════════════════════════════
# MERCHANT SELF-SERVICE (requires merchant role)
# ═════════════════════════════════════════════════════════════════════════════

# ── POST /merchant/onboard ────────────────────────────────────────────────────
@router.post(
    "/onboard",
    response_model=MerchantDetail,
    status_code=201,
    summary="Register a new merchant shop",
)
async def onboard(
    body: MerchantOnboardRequest,
    user: dict        = Depends(require_role("merchant")),
    db:   AsyncSession = Depends(get_db),
):
    return await service.onboard_merchant(user_id=user["sub"], payload=body, db=db)


# ── GET /merchant/me ──────────────────────────────────────────────────────────
@router.get(
    "/me",
    response_model=MerchantDetail,
    summary="Get my shop profile",
)
async def get_my_profile(
    user: dict        = Depends(require_role("merchant")),
    db:   AsyncSession = Depends(get_db),
):
    return await service.get_my_merchant(user_id=user["sub"], db=db)


# ── PUT /merchant/me ──────────────────────────────────────────────────────────
@router.put(
    "/me",
    response_model=MerchantDetail,
    summary="Update shop profile",
)
async def update_profile(
    body: MerchantUpdateRequest,
    user: dict        = Depends(require_role("merchant")),
    db:   AsyncSession = Depends(get_db),
):
    return await service.update_merchant(user_id=user["sub"], payload=body, db=db)


# ── PUT /merchant/me/open ─────────────────────────────────────────────────────
@router.put(
    "/me/open",
    response_model=MerchantDetail,
    summary="Toggle shop open/closed",
)
async def set_open(
    is_open: bool,
    user:    dict        = Depends(require_role("merchant")),
    db:      AsyncSession = Depends(get_db),
):
    return await service.toggle_open(user_id=user["sub"], is_open=is_open, db=db)


# ─────────────────────────────────────────────────────────────────────────────
# MENU MANAGEMENT
# ─────────────────────────────────────────────────────────────────────────────

# ── GET /merchant/menu ────────────────────────────────────────────────────────
@router.get(
    "/menu",
    response_model=list[MenuItemResponse],
    summary="Get full menu (including unavailable items)",
)
async def get_menu(
    user: dict        = Depends(require_role("merchant")),
    db:   AsyncSession = Depends(get_db),
):
    return await service.list_menu(user_id=user["sub"], db=db)


# ── POST /merchant/menu ───────────────────────────────────────────────────────
@router.post(
    "/menu",
    response_model=MenuItemResponse,
    status_code=201,
    summary="Add a new menu item",
)
async def add_item(
    body: MenuItemCreate,
    user: dict        = Depends(require_role("merchant")),
    db:   AsyncSession = Depends(get_db),
):
    return await service.add_menu_item(user_id=user["sub"], payload=body, db=db)


# ── PUT /merchant/menu/{item_id} ──────────────────────────────────────────────
@router.put(
    "/menu/{item_id}",
    response_model=MenuItemResponse,
    summary="Update a menu item",
)
async def update_item(
    item_id: str,
    body:    MenuItemUpdate,
    user:    dict        = Depends(require_role("merchant")),
    db:      AsyncSession = Depends(get_db),
):
    return await service.update_menu_item(
        user_id=user["sub"], item_id=item_id, payload=body, db=db
    )


# ── PUT /merchant/menu/{item_id}/availability ─────────────────────────────────
@router.put(
    "/menu/{item_id}/availability",
    response_model=MenuItemResponse,
    summary="Toggle item availability",
    description="Instantly mark an item as available or unavailable. Takes effect on next order.",
)
async def toggle_availability(
    item_id:      str,
    is_available: bool,
    user:         dict        = Depends(require_role("merchant")),
    db:           AsyncSession = Depends(get_db),
):
    return await service.toggle_item_availability(
        user_id=user["sub"], item_id=item_id, is_available=is_available, db=db
    )


# ── DELETE /merchant/menu/{item_id} ───────────────────────────────────────────
@router.delete(
    "/menu/{item_id}",
    response_model=MessageResponse,
    summary="Delete a menu item",
)
async def delete_item(
    item_id: str,
    user:    dict        = Depends(require_role("merchant")),
    db:      AsyncSession = Depends(get_db),
):
    await service.delete_menu_item(user_id=user["sub"], item_id=item_id, db=db)
    return {"message": "Menu item deleted"}


# ─────────────────────────────────────────────────────────────────────────────
# ORDER MANAGEMENT
# ─────────────────────────────────────────────────────────────────────────────

# ── GET /merchant/orders/live ─────────────────────────────────────────────────
@router.get(
    "/orders/live",
    response_model=list[OrderDetail],
    summary="Live order queue",
    description="All active (non-terminal) orders. Poll this every 10s or use WebSocket.",
)
async def live_orders(
    user: dict        = Depends(require_role("merchant")),
    db:   AsyncSession = Depends(get_db),
):
    return await service.get_live_orders(user_id=user["sub"], db=db)


# ─────────────────────────────────────────────────────────────────────────────
# EARNINGS
# ─────────────────────────────────────────────────────────────────────────────

# ── GET /merchant/earnings/weekly ─────────────────────────────────────────────
@router.get(
    "/earnings/weekly",
    response_model=list[MerchantEarningsSummary],
    summary="Weekly earnings breakdown",
    description="Daily breakdown for the last 7 days — orders, revenue, commission, net payout.",
)
async def weekly_earnings(
    user: dict        = Depends(require_role("merchant")),
    db:   AsyncSession = Depends(get_db),
):
    return await service.get_weekly_earnings(user_id=user["sub"], db=db)


# ═════════════════════════════════════════════════════════════════════════════
# CUSTOMER-FACING (public — requires only authentication)
# ═════════════════════════════════════════════════════════════════════════════

# ── GET /merchant/browse ──────────────────────────────────────────────────────
@router.get(
    "/browse",
    response_model=list[MerchantSummary],
    summary="Browse active merchants",
    description="Customer-facing merchant listing. Filtered by category and sorted by rating.",
)
async def browse_merchants(
    category: str | None = Query(None),
    offset:   int        = Query(0, ge=0),
    limit:    int        = Query(20, ge=1, le=100),
    user:     dict       = Depends(get_current_user),
    db:       AsyncSession = Depends(get_db),
):
    return await service.list_active_merchants(
        db=db, offset=offset, limit=limit, category=category
    )


# ── GET /merchant/{merchant_id}/menu ─────────────────────────────────────────
@router.get(
    "/{merchant_id}/menu",
    response_model=MerchantPublicDetail,
    summary="Get merchant menu",
    description="Returns merchant profile and all available menu items. Customer-facing.",
)
async def merchant_menu(
    merchant_id: str,
    user:        dict        = Depends(get_current_user),
    db:          AsyncSession = Depends(get_db),
):
    merchant, items = await service.get_merchant_menu(merchant_id=merchant_id, db=db)
    return {**merchant.__dict__, "menu_items": items}
