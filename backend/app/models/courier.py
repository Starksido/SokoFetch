import uuid
import enum
from datetime import datetime, timezone
from sqlalchemy import (
    Column, String, Boolean, DateTime, ForeignKey,
    Numeric, Text, Integer, Enum as SAEnum
)
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import relationship

from app.core.database import Base
from app.core.encryption import EncryptedString


class CourierStatus(str, enum.Enum):
    """
    Five-state courier account lifecycle:
    registered → documents_submitted → under_review → approved → active
                                                    → rejected → resubmit_requested
    active → suspended (auto: low rating or fraud signal)
    active → deactivated (manual admin action)
    """
    registered            = "registered"
    documents_submitted   = "documents_submitted"
    under_review          = "under_review"
    approved              = "approved"
    active                = "active"
    suspended             = "suspended"
    deactivated           = "deactivated"
    rejected              = "rejected"
    resubmit_requested    = "resubmit_requested"


class VehicleType(str, enum.Enum):
    motorcycle = "motorcycle"
    bicycle    = "bicycle"
    on_foot    = "on_foot"


class DocumentType(str, enum.Enum):
    national_id_front = "national_id_front"
    national_id_back  = "national_id_back"
    driving_license   = "driving_license"
    vehicle_photo     = "vehicle_photo"
    selfie_with_id    = "selfie_with_id"

REQUIRED_DOCUMENTS = {
    DocumentType.national_id_front,
    DocumentType.national_id_back,
    DocumentType.driving_license,
    DocumentType.vehicle_photo,
    DocumentType.selfie_with_id,
}


class Courier(Base):
    """
    Rider profile. One-to-one with User via user_id.
    """
    __tablename__ = "couriers"

    id      = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        unique=True,
        nullable=False,
        index=True,
    )

    # ── Profile ───────────────────────────────────────────────────────────────
    full_name    = Column(EncryptedString(512), nullable=True)
    vehicle_type = Column(SAEnum(VehicleType, name="vehicletype"),
                          default=VehicleType.motorcycle, nullable=False)
    vehicle_plate = Column(String(20), nullable=True)

    # ── Status ────────────────────────────────────────────────────────────────
    status = Column(
        SAEnum(CourierStatus, name="courierstatus"),
        default=CourierStatus.registered,
        nullable=False,
        index=True,
    )
    suspension_reason       = Column(Text, nullable=True)
    rejection_reason        = Column(Text, nullable=True)
    documents_verified_at   = Column(DateTime(timezone=True), nullable=True)

    # ── Online state ──────────────────────────────────────────────────────────
    is_online    = Column(Boolean, default=False, nullable=False)
    last_seen_at = Column(DateTime(timezone=True), nullable=True)

    # ── Current location (also mirrored in Redis for real-time) ───────────────
    last_latitude  = Column(Numeric(10, 7), nullable=True)
    last_longitude = Column(Numeric(10, 7), nullable=True)

    # ── Ratings & performance ─────────────────────────────────────────────────
    rating              = Column(Numeric(3, 2), default=5.00, nullable=False)
    rating_count        = Column(Integer, default=0, nullable=False)
    total_deliveries    = Column(Integer, default=0, nullable=False)

    # ── Earnings ──────────────────────────────────────────────────────────────
    payout_phone        = Column(EncryptedString(512), nullable=True)  # M-Pesa
    total_earned        = Column(Numeric(12, 2), default=0.00, nullable=False)
    pending_payout      = Column(Numeric(12, 2), default=0.00, nullable=False)

    # ── Timestamps ────────────────────────────────────────────────────────────
    created_at  = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
    updated_at  = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc),
                         onupdate=lambda: datetime.now(timezone.utc))

    # ── Relationships ─────────────────────────────────────────────────────────
    documents = relationship("CourierDocument", back_populates="courier",
                             cascade="all, delete-orphan")
    orders    = relationship("Order", back_populates="courier")

    @property
    def is_dispatchable(self) -> bool:
        """Only fully approved, active, online couriers receive orders."""
        return (
            self.status == CourierStatus.active
            and self.is_online
            and self.documents_verified_at is not None
        )

    def __repr__(self):
        return f"<Courier id={self.id} status={self.status}>"


class CourierDocument(Base):
    """
    Encrypted document uploaded during courier verification.
    Actual file bytes are stored in S3 — only the S3 key is here.
    """
    __tablename__ = "courier_documents"

    id          = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    courier_id  = Column(
        UUID(as_uuid=True),
        ForeignKey("couriers.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )

    doc_type    = Column(SAEnum(DocumentType, name="documenttype"), nullable=False)
    s3_key      = Column(String(512), nullable=False)       # Reference to encrypted S3 object
    is_verified = Column(Boolean, default=False, nullable=False)
    verified_at = Column(DateTime(timezone=True), nullable=True)
    verified_by = Column(String(128), nullable=True)        # Admin user ID

    uploaded_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))

    # ── Relationships ─────────────────────────────────────────────────────────
    courier     = relationship("Courier", back_populates="documents")

    def __repr__(self):
        return f"<CourierDocument courier={self.courier_id} type={self.doc_type}>"
