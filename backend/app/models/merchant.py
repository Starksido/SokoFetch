import uuid
import enum
from datetime import datetime, timezone
from sqlalchemy import (
    Column, String, Boolean, DateTime, ForeignKey,
    Numeric, Text, Integer, Enum as SAEnum
)
from sqlalchemy.dialects.postgresql import UUID, JSONB, ARRAY
from sqlalchemy.orm import relationship

from app.core.database import Base
from app.core.encryption import EncryptedString


class MerchantStatus(str, enum.Enum):
    pending_review = "pending_review"   # Submitted, awaiting admin approval
    active         = "active"           # Live on the platform
    suspended      = "suspended"        # Temporarily suspended
    deactivated    = "deactivated"      # Permanently removed


class MerchantCategory(str, enum.Enum):
    restaurant    = "restaurant"
    grocery       = "grocery"
    pharmacy      = "pharmacy"
    bakery        = "bakery"
    fast_food     = "fast_food"
    beverages     = "beverages"
    general       = "general"


class Merchant(Base):
    """
    Shop / restaurant registered on Soko Fetch.
    One-to-one with User via user_id.
    """
    __tablename__ = "merchants"

    id      = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        unique=True,
        nullable=False,
        index=True,
    )

    # ── Business details ──────────────────────────────────────────────────────
    shop_name    = Column(String(255), nullable=False)
    description  = Column(Text, nullable=True)
    category     = Column(SAEnum(MerchantCategory, name="merchantcategory"), nullable=False)
    logo_url     = Column(String(512), nullable=True)
    banner_url   = Column(String(512), nullable=True)

    # ── Location ──────────────────────────────────────────────────────────────
    address      = Column(String(512), nullable=False)
    city         = Column(String(128), nullable=False, default="Nairobi")
    latitude     = Column(Numeric(10, 7), nullable=True)
    longitude    = Column(Numeric(10, 7), nullable=True)

    # ── Operations ────────────────────────────────────────────────────────────
    # JSONB: {"mon": {"open": "08:00", "close": "22:00"}, "tue": {...}, ...}
    operating_hours = Column(JSONB, nullable=True)
    avg_prep_minutes = Column(Integer, default=20, nullable=False)
    min_order_amount = Column(Numeric(10, 2), default=0, nullable=False)
    is_open          = Column(Boolean, default=True, nullable=False)   # Manual override

    # ── Commercial ────────────────────────────────────────────────────────────
    commission_rate   = Column(Numeric(5, 2), default=20.00, nullable=False)
    payout_phone      = Column(EncryptedString(512), nullable=True)   # M-Pesa number
    payout_bank_name  = Column(String(128), nullable=True)
    payout_account    = Column(EncryptedString(512), nullable=True)   # Bank account
    pending_payout    = Column(Numeric(12, 2), default=0.00, nullable=False)  # Net owed, credited on payment

    # ── Status ────────────────────────────────────────────────────────────────
    status     = Column(
        SAEnum(MerchantStatus, name="merchantstatus"),
        default=MerchantStatus.pending_review,
        nullable=False,
    )
    approved_at = Column(DateTime(timezone=True), nullable=True)

    # ── Ratings ───────────────────────────────────────────────────────────────
    rating        = Column(Numeric(3, 2), default=0.00, nullable=False)
    rating_count  = Column(Integer, default=0, nullable=False)

    # ── Timestamps ────────────────────────────────────────────────────────────
    created_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
    updated_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc),
                        onupdate=lambda: datetime.now(timezone.utc))

    # ── Relationships ─────────────────────────────────────────────────────────
    menu_items = relationship("MenuItem", back_populates="merchant",
                              cascade="all, delete-orphan")
    orders     = relationship("Order", back_populates="merchant")

    def __repr__(self):
        return f"<Merchant id={self.id} name={self.shop_name}>"


class MenuItem(Base):
    """
    A single item on a merchant's menu.
    """
    __tablename__ = "menu_items"

    id          = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    merchant_id = Column(
        UUID(as_uuid=True),
        ForeignKey("merchants.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )

    # ── Content ───────────────────────────────────────────────────────────────
    name         = Column(String(255), nullable=False)
    description  = Column(Text, nullable=True)
    category     = Column(String(128), nullable=False)     # "Mains", "Sides", "Drinks"
    photo_url    = Column(String(512), nullable=True)

    # ── Pricing ───────────────────────────────────────────────────────────────
    price        = Column(Numeric(10, 2), nullable=False)
    discount_pct = Column(Numeric(5, 2), default=0, nullable=False)

    # ── Availability ──────────────────────────────────────────────────────────
    is_available    = Column(Boolean, default=True, nullable=False)
    prep_minutes    = Column(Integer, default=15, nullable=False)
    sort_order      = Column(Integer, default=0, nullable=False)

    # ── Timestamps ────────────────────────────────────────────────────────────
    created_at  = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
    updated_at  = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc),
                         onupdate=lambda: datetime.now(timezone.utc))

    # ── Relationships ─────────────────────────────────────────────────────────
    merchant    = relationship("Merchant", back_populates="menu_items")

    @property
    def effective_price(self) -> float:
        """Price after discount."""
        return float(self.price) * (1 - float(self.discount_pct) / 100)

    def __repr__(self):
        return f"<MenuItem id={self.id} name={self.name} price={self.price}>"
