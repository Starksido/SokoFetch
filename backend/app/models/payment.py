import uuid
import enum
from datetime import datetime, timezone
from sqlalchemy import (
    Column, String, DateTime, ForeignKey,
    Numeric, Text, Boolean, Enum as SAEnum
)
from sqlalchemy.dialects.postgresql import UUID, JSONB
from sqlalchemy.orm import relationship

from app.core.database import Base


class PaymentGateway(str, enum.Enum):
    mpesa        = "mpesa"
    flutterwave  = "flutterwave"
    wallet       = "wallet"


class TransactionStatus(str, enum.Enum):
    initiated  = "initiated"
    pending    = "pending"
    success    = "success"
    failed     = "failed"
    refunded   = "refunded"
    cancelled  = "cancelled"


class Payment(Base):
    """
    Immutable payment transaction record.
    Created when a payment is initiated; updated via webhook callbacks.
    """
    __tablename__ = "payments"

    id          = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    order_id    = Column(
        UUID(as_uuid=True),
        ForeignKey("orders.id", ondelete="SET NULL"),
        nullable=True,
        index=True,
    )
    customer_id = Column(UUID(as_uuid=True), nullable=False, index=True)

    # ── Gateway ───────────────────────────────────────────────────────────────
    gateway         = Column(SAEnum(PaymentGateway, name="paymentgateway"), nullable=False)
    gateway_ref     = Column(String(255), nullable=True, index=True)   # Daraja / FLW reference
    gateway_payload = Column(JSONB, nullable=True)                     # Raw callback body (for audits)

    # ── Amount ────────────────────────────────────────────────────────────────
    amount          = Column(Numeric(12, 2), nullable=False)
    currency        = Column(String(3), default="KES", nullable=False)

    # ── Status ────────────────────────────────────────────────────────────────
    status          = Column(
        SAEnum(TransactionStatus, name="transactionstatus"),
        default=TransactionStatus.initiated,
        nullable=False,
        index=True,
    )
    failure_reason  = Column(Text, nullable=True)

    # ── Fraud ─────────────────────────────────────────────────────────────────
    fraud_checked   = Column(Boolean, default=False, nullable=False)
    fraud_signals   = Column(JSONB, nullable=True)   # Flags triggered during fraud check

    # ── Timestamps ────────────────────────────────────────────────────────────
    created_at      = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
    updated_at      = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc),
                             onupdate=lambda: datetime.now(timezone.utc))
    completed_at    = Column(DateTime(timezone=True), nullable=True)

    def __repr__(self):
        return f"<Payment id={self.id} gateway={self.gateway} amount={self.amount} status={self.status}>"
