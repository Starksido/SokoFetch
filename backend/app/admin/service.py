"""
Admin Service
=============
Approving or rejecting new shops and riders.
"""
import logging
from datetime import datetime, timezone

import boto3
from botocore.exceptions import BotoCoreError, ClientError
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.core.config import settings
from app.core.encryption import decrypt_document
from app.core.exceptions import NotFoundError, SokoFetchException
from app.core.repository import MerchantRepo
from app.models.courier import Courier, CourierDocument, CourierStatus, DocumentType, REQUIRED_DOCUMENTS
from app.models.merchant import Merchant, MerchantStatus

log = logging.getLogger("alphabet.admin.service")

# Riders an admin still has to look at
COURIER_REVIEW_STATUSES = (CourierStatus.documents_submitted, CourierStatus.under_review)


def _invalid_state(what: str, status: str) -> SokoFetchException:
    return SokoFetchException(409, "INVALID_STATE", f"Cannot {what} while status is '{status}'.")


# ── Shops ─────────────────────────────────────────────────────────────────────
async def list_merchants(
    status: MerchantStatus, db: AsyncSession, offset: int = 0, limit: int = 50,
) -> list[Merchant]:
    return await MerchantRepo(db).list(
        Merchant.status == status,
        order_by=Merchant.created_at,
        offset=offset,
        limit=limit,
    )


async def approve_merchant(merchant_id: str, admin_id: str, db: AsyncSession) -> Merchant:
    repo = MerchantRepo(db)
    merchant = await repo.get_or_404(merchant_id, "Merchant")
    if merchant.status not in (MerchantStatus.pending_review, MerchantStatus.suspended):
        raise _invalid_state("approve this shop", merchant.status.value)
    merchant = await repo.update(merchant, status=MerchantStatus.active)
    log.info("Merchant approved | merchant=%s | admin=%s", merchant_id, admin_id)
    return merchant


async def reject_merchant(merchant_id: str, reason: str, admin_id: str, db: AsyncSession) -> Merchant:
    repo = MerchantRepo(db)
    merchant = await repo.get_or_404(merchant_id, "Merchant")
    if merchant.status != MerchantStatus.pending_review:
        raise _invalid_state("reject this shop", merchant.status.value)
    merchant = await repo.update(merchant, status=MerchantStatus.deactivated)
    # merchants has no column for the reason; keep it in the audit log
    log.info("Merchant rejected | merchant=%s | admin=%s | reason=%s", merchant_id, admin_id, reason)
    return merchant


# ── Riders ────────────────────────────────────────────────────────────────────
async def list_couriers(
    statuses: tuple[CourierStatus, ...], db: AsyncSession, offset: int = 0, limit: int = 50,
) -> list[Courier]:
    stmt = (
        select(Courier)
        .where(Courier.status.in_(statuses))
        .options(selectinload(Courier.documents))
        .order_by(Courier.created_at)
        .offset(offset)
        .limit(limit)
    )
    return list((await db.execute(stmt)).scalars().all())


async def get_courier(courier_id: str, db: AsyncSession) -> Courier:
    stmt = select(Courier).where(Courier.id == courier_id).options(selectinload(Courier.documents))
    courier = (await db.execute(stmt)).scalar_one_or_none()
    if courier is None:
        raise NotFoundError("Courier")
    return courier


async def approve_courier(courier_id: str, admin_id: str, db: AsyncSession) -> Courier:
    courier = await get_courier(courier_id, db)
    if courier.status not in (*COURIER_REVIEW_STATUSES, CourierStatus.rejected,
                              CourierStatus.resubmit_requested):
        raise _invalid_state("approve this rider", courier.status.value)

    uploaded = {doc.doc_type for doc in courier.documents}
    missing = REQUIRED_DOCUMENTS - uploaded
    if missing:
        raise SokoFetchException(
            422, "DOCUMENTS_MISSING",
            "Missing documents: " + ", ".join(sorted(d.value for d in missing)),
        )

    now = datetime.now(timezone.utc)
    for doc in courier.documents:
        doc.is_verified = True
        doc.verified_at = now
        doc.verified_by = admin_id
    courier.status = CourierStatus.active
    courier.documents_verified_at = now
    courier.rejection_reason = None
    await db.flush()
    log.info("Courier approved | courier=%s | admin=%s", courier_id, admin_id)
    return courier


async def reject_courier(courier_id: str, reason: str, admin_id: str, db: AsyncSession) -> Courier:
    courier = await get_courier(courier_id, db)
    if courier.status not in (*COURIER_REVIEW_STATUSES, CourierStatus.registered):
        raise _invalid_state("reject this rider", courier.status.value)
    courier.status = CourierStatus.rejected
    courier.rejection_reason = reason
    await db.flush()
    log.info("Courier rejected | courier=%s | admin=%s", courier_id, admin_id)
    return courier


# ── Rider documents ───────────────────────────────────────────────────────────
def _sniff_content_type(data: bytes) -> str:
    if data.startswith(b"\xff\xd8\xff"):
        return "image/jpeg"
    if data.startswith(b"\x89PNG\r\n\x1a\n"):
        return "image/png"
    if data[:4] == b"RIFF" and data[8:12] == b"WEBP":
        return "image/webp"
    if data.startswith(b"%PDF"):
        return "application/pdf"
    return "application/octet-stream"


def _download(s3_key: str) -> bytes:
    s3 = boto3.client(
        "s3",
        aws_access_key_id     = settings.AWS_ACCESS_KEY_ID,
        aws_secret_access_key = settings.AWS_SECRET_ACCESS_KEY,
        region_name           = settings.AWS_REGION,
    )
    return s3.get_object(Bucket=settings.DOCUMENTS_BUCKET, Key=s3_key)["Body"].read()


async def get_courier_document(courier_id: str, doc_type: str, db: AsyncSession) -> tuple[bytes, str]:
    """
    Documents are encrypted before they go to S3, so a presigned URL would
    only give ciphertext. Download, decrypt and hand back the file itself.
    """
    try:
        dt = DocumentType(doc_type)
    except ValueError:
        raise NotFoundError("Document")
    stmt = select(CourierDocument).where(
        CourierDocument.courier_id == courier_id,
        CourierDocument.doc_type == dt,
    )
    doc = (await db.execute(stmt)).scalar_one_or_none()
    if doc is None:
        raise NotFoundError("Document")

    try:
        encrypted = _download(doc.s3_key)
    except (BotoCoreError, ClientError) as exc:
        log.error("S3 download failed | courier=%s | type=%s | error=%s", courier_id, doc_type, exc)
        raise SokoFetchException(502, "DOWNLOAD_FAILED", "Could not fetch the document. Please retry.")
    try:
        data = decrypt_document(encrypted)
    except ValueError:
        log.error("Document decrypt failed | courier=%s | type=%s", courier_id, doc_type)
        raise SokoFetchException(500, "DOCUMENT_UNREADABLE", "The stored document could not be decrypted.")
    return data, _sniff_content_type(data)
