import uuid
import enum
from datetime import datetime, timezone
from sqlalchemy import (
    Column, String, Boolean, DateTime, ForeignKey,
    Numeric, Text, Integer, Enum as SAEnum
)
from sqlalchemy.dialects.postgresql import UUID, JSONB
from sqlalchemy.orm import relationship

from app.core.database import Base


class OrderStatus(str, enum.Enum):
    """
    Full order lifecycle state machine:

    PENDING
      → CONFIRMED (merchant accepts)
      → CANCELLED (merchant declines, or customer cancels pre-pickup)

    CONFIRMED
      → PREPARING (merchant starts preparing)

    PREPARING
      → READY_FOR_PICKUP (merchant marks ready)

    READY_FOR_PICKUP
      → PICKED_UP (courier confirms pickup)

    PICKED_UP
      → IN_TRANSIT (courier en route to customer)

    IN_TRANSIT
      → DELIVERED (courier confirms delivery with proof)
      → DELIVERY_FAILED (courier unable to deliver)
    """
    pending           = "pending"
    confirmed         = "confirmed"
    preparing         = "preparing"
    ready_for_pickup  = "ready_for_pickup"
    picked_up         = "picked_up"
    in_transit        = "in_transit"
    delivered         = "delivered"
    cancelled         = "cancelled"
    delivery_failed   = "delivery_failed"


# Valid transitions — enforced in the service layer
VALID_TRANSITIONS: dict[OrderStatus, set[OrderStatus]] = {
    OrderStatus.pending:          {OrderStatus.confirmed, OrderStatus.cancelled},
    OrderStatus.confirmed:        {OrderStatus.preparing, OrderStatus.cancelled},
    OrderStatus.preparing:        {OrderStatus.ready_for_pickup},
    OrderStatus.ready_for_pickup: {OrderStatus.picked_up},
    OrderStatus.picked_up:        {OrderStatus.in_transit},
    OrderStatus.in_transit:       {OrderStatus.delivered, OrderStatus.delivery_failed},
    OrderStatus.delivered:        set(),
    OrderStatus.cancelled:        set(),
    OrderStatus.delivery_failed:  set(),
}


class PaymentMethod(str, enum.Enum):
    mpesa   = "mpesa"
    card    = "card"
    wallet  = "wallet"


class PaymentStatus(str, enum.Enum):
    pending   = "pending"
    paid      = "paid"
    failed    = "failed"
    refunded  = "refunded"


class Order(Base):
    """
    Central order record linking customer, merchant, and courier.
    """
    __tablename__ = "orders"

    id          = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)

    # ── Parties ───────────────────────────────────────────────────────────────
    customer_id = Column(UUID(as_uuid=True), ForeignKey("customers.id"), nullable=False, index=True)
    merchant_id = Column(UUID(as_uuid=True), ForeignKey("merchants.id"), nullable=False, index=True)
    courier_id  = Column(UUID(as_uuid=True), ForeignKey("couriers.id"),  nullable=True,  index=True)

    # ── Line items ────────────────────────────────────────────────────────────
    # Stored as snapshot of prices at order time — not live FK to menu
    # [{"item_id": "uuid", "name": "Beef Burger", "qty": 2, "unit_price": 450.00}]
    items       = Column(JSONB, nullable=False)
    item_count  = Column(Integer, nullable=False, default=1)

    # ── Amounts ───────────────────────────────────────────────────────────────
    subtotal          = Column(Numeric(12, 2), nullable=False)  # Sum of items
    delivery_fee      = Column(Numeric(10, 2), nullable=False)  # Charged to customer
    surge_multiplier  = Column(Numeric(4, 2), default=1.00)     # 1.0 = no surge
    platform_fee      = Column(Numeric(10, 2), nullable=False)  # Retainer from delivery fee
    merchant_commission = Column(Numeric(10, 2), nullable=False) # % of subtotal
    courier_payout    = Column(Numeric(10, 2), nullable=True)   # Delivery fee - platform_fee
    total             = Column(Numeric(12, 2), nullable=False)  # subtotal + delivery_fee

    # ── Payment ───────────────────────────────────────────────────────────────
    payment_method  = Column(SAEnum(PaymentMethod, name="paymentmethod"), nullable=False)
    payment_status  = Column(SAEnum(PaymentStatus, name="paymentstatus"),
                             default=PaymentStatus.pending, nullable=False)
    payment_ref     = Column(String(255), nullable=True)   # Daraja/Flutterwave reference

    # ── Delivery ──────────────────────────────────────────────────────────────
    delivery_address    = Column(Text, nullable=False)
    delivery_latitude   = Column(Numeric(10, 7), nullable=True)
    delivery_longitude  = Column(Numeric(10, 7), nullable=True)
    delivery_notes      = Column(Text, nullable=True)       # "Ring bell, 3rd floor"

    # ── Proof of delivery ─────────────────────────────────────────────────────
    proof_type          = Column(String(16), nullable=True)  # "photo" | "otp"
    proof_photo_url     = Column(String(512), nullable=True)
    proof_otp           = Column(String(6), nullable=True)   # Hashed in service
    proof_submitted_at  = Column(DateTime(timezone=True), nullable=True)

    # ── Status & timing ───────────────────────────────────────────────────────
    status          = Column(
        SAEnum(OrderStatus, name="orderstatus"),
        default=OrderStatus.pending,
        nullable=False,
        index=True,
    )
    cancellation_reason = Column(Text, nullable=True)
    special_instructions = Column(Text, nullable=True)

    # ETA tracking
    estimated_pickup_at   = Column(DateTime(timezone=True), nullable=True)
    estimated_delivery_at = Column(DateTime(timezone=True), nullable=True)
    picked_up_at          = Column(DateTime(timezone=True), nullable=True)
    delivered_at          = Column(DateTime(timezone=True), nullable=True)

    # ── Ratings ───────────────────────────────────────────────────────────────
    customer_rating   = Column(Integer, nullable=True)  # 1-5 stars for courier
    merchant_rating   = Column(Integer, nullable=True)  # 1-5 stars for merchant
    customer_review   = Column(Text, nullable=True)

    # ── Timestamps ────────────────────────────────────────────────────────────
    created_at  = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), index=True)
    updated_at  = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc),
                         onupdate=lambda: datetime.now(timezone.utc))

    # ── Relationships ─────────────────────────────────────────────────────────
    customer = relationship("Customer", back_populates="orders")
    merchant = relationship("Merchant", back_populates="orders")
    courier  = relationship("Courier",  back_populates="orders")

    def can_transition_to(self, new_status: OrderStatus) -> bool:
        """Check if this status transition is valid."""
        return new_status in VALID_TRANSITIONS.get(self.status, set())

    def __repr__(self):
        return f"<Order id={self.id} status={self.status} total={self.total}>"
