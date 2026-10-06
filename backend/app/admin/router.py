from typing import Optional
from uuid import UUID

from fastapi import APIRouter, Depends, Query
from fastapi.responses import Response
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.auth.guards import RequireAdmin
from app.admin import service
from app.models.courier import CourierStatus
from app.models.merchant import MerchantStatus
from app.schemas.admin import AdminCourier, AdminMerchant, RejectRequest

# Every route here is admin-only
router = APIRouter(dependencies=[Depends(RequireAdmin)])


# ─────────────────────────────────────────────────────────────────────────────
# Shops
# ─────────────────────────────────────────────────────────────────────────────
@router.get(
    "/merchants",
    response_model=list[AdminMerchant],
    summary="List shops by status",
    description="Defaults to shops waiting for approval (pending_review), oldest first.",
)
async def list_merchants(
    status: MerchantStatus = Query(MerchantStatus.pending_review),
    offset: int            = Query(0, ge=0),
    limit:  int            = Query(50, ge=1, le=100),
    db:     AsyncSession   = Depends(get_db),
):
    return await service.list_merchants(status, db, offset, limit)


@router.post("/merchants/{merchant_id}/approve", response_model=AdminMerchant, summary="Approve a shop")
async def approve_merchant(
    merchant_id: UUID,
    admin: dict         = Depends(RequireAdmin),
    db:    AsyncSession = Depends(get_db),
):
    return await service.approve_merchant(merchant_id, admin["sub"], db)


@router.post("/merchants/{merchant_id}/reject", response_model=AdminMerchant, summary="Reject a shop")
async def reject_merchant(
    merchant_id: UUID,
    body:  RejectRequest,
    admin: dict         = Depends(RequireAdmin),
    db:    AsyncSession = Depends(get_db),
):
    return await service.reject_merchant(merchant_id, body.reason, admin["sub"], db)


# ─────────────────────────────────────────────────────────────────────────────
# Riders
# ─────────────────────────────────────────────────────────────────────────────
@router.get(
    "/couriers",
    response_model=list[AdminCourier],
    summary="List riders by status",
    description=(
        "Without a status, lists riders waiting for review "
        "(documents_submitted and under_review), oldest first."
    ),
)
async def list_couriers(
    status: Optional[CourierStatus] = Query(None),
    offset: int                     = Query(0, ge=0),
    limit:  int                     = Query(50, ge=1, le=100),
    db:     AsyncSession            = Depends(get_db),
):
    statuses = (status,) if status else service.COURIER_REVIEW_STATUSES
    return await service.list_couriers(statuses, db, offset, limit)


@router.get("/couriers/{courier_id}", response_model=AdminCourier, summary="Rider detail with documents")
async def get_courier(courier_id: UUID, db: AsyncSession = Depends(get_db)):
    return await service.get_courier(courier_id, db)


@router.get(
    "/couriers/{courier_id}/documents/{doc_type}",
    summary="View a rider's document",
    description="Returns the decrypted file (image or PDF).",
    response_class=Response,
)
async def get_courier_document(courier_id: UUID, doc_type: str, db: AsyncSession = Depends(get_db)):
    data, content_type = await service.get_courier_document(courier_id, doc_type, db)
    return Response(content=data, media_type=content_type, headers={"Cache-Control": "no-store"})


@router.post(
    "/couriers/{courier_id}/approve",
    response_model=AdminCourier,
    summary="Approve a rider",
    description="Requires all five documents. Marks them verified and makes the rider active.",
)
async def approve_courier(
    courier_id: UUID,
    admin: dict         = Depends(RequireAdmin),
    db:    AsyncSession = Depends(get_db),
):
    return await service.approve_courier(courier_id, admin["sub"], db)


@router.post("/couriers/{courier_id}/reject", response_model=AdminCourier, summary="Reject a rider")
async def reject_courier(
    courier_id: UUID,
    body:  RejectRequest,
    admin: dict         = Depends(RequireAdmin),
    db:    AsyncSession = Depends(get_db),
):
    return await service.reject_courier(courier_id, body.reason, admin["sub"], db)
