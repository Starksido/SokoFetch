import uuid
from datetime import datetime, timezone
from sqlalchemy import (
    Column, String, Boolean, DateTime, ForeignKey,
    Numeric, Text, Integer
)
from sqlalchemy.dialects.postgresql import UUID, JSONB
from sqlalchemy.orm import relationship

from app.core.database import Base
from app.core.encryption import EncryptedString


class Customer(Base):
    """
    Extended profile for users with role='customer'.
    One-to-one with User via user_id.
    """
    __tablename__ = "customers"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        unique=True,
        nullable=False,
        index=True,
    )

    # ── Profile ───────────────────────────────────────────────────────────────
    full_name    = Column(EncryptedString(512), nullable=True)
    email        = Column(EncryptedString(512), nullable=True)
    avatar_url   = Column(String(512), nullable=True)
    google_id    = Column(String(128), unique=True, nullable=True, index=True)
    google_verified_at = Column(DateTime(timezone=True), nullable=True)

    # ── Wallet / loyalty ──────────────────────────────────────────────────────
    wallet_balance = Column(Numeric(12, 2), default=0.00, nullable=False)

    # ── Timestamps ────────────────────────────────────────────────────────────
    created_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
    updated_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc),
                        onupdate=lambda: datetime.now(timezone.utc))

    # ── Relationships ─────────────────────────────────────────────────────────
    addresses = relationship("DeliveryAddress", back_populates="customer",
                             cascade="all, delete-orphan")
    orders    = relationship("Order", back_populates="customer")

    def __repr__(self):
        return f"<Customer id={self.id}>"


class DeliveryAddress(Base):
    """
    Saved delivery addresses for a customer.
    Customers can store multiple addresses (home, work, etc.).
    """
    __tablename__ = "delivery_addresses"

    id          = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    customer_id = Column(
        UUID(as_uuid=True),
        ForeignKey("customers.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )

    # ── Location ──────────────────────────────────────────────────────────────
    label       = Column(String(64), nullable=False)      # "Home", "Work", "Other"
    address_line = Column(EncryptedString(512), nullable=False)
    city        = Column(String(128), nullable=False, default="Nairobi")
    latitude    = Column(Numeric(10, 7), nullable=True)
    longitude   = Column(Numeric(10, 7), nullable=True)
    instructions = Column(Text, nullable=True)             # "Green gate, 2nd floor"

    is_default  = Column(Boolean, default=False, nullable=False)

    created_at  = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))

    # ── Relationships ─────────────────────────────────────────────────────────
    customer    = relationship("Customer", back_populates="addresses")

    def __repr__(self):
        return f"<DeliveryAddress id={self.id} label={self.label}>"
