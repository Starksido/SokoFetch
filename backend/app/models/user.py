import uuid
from datetime import datetime, timezone
from sqlalchemy import Column, String, Boolean, DateTime, Enum as SAEnum
from sqlalchemy.dialects.postgresql import UUID
import enum

from app.core.database import Base
from app.core.encryption import EncryptedString


class UserRole(str, enum.Enum):
    customer = "customer"
    merchant = "merchant"
    courier  = "courier"
    admin    = "admin"


class User(Base):
    __tablename__ = "users"

    # -- Identity --------------------------------------------------------
    id = Column(
        UUID(as_uuid=True),
        primary_key=True,
        default=uuid.uuid4,
        index=True,
    )
    phone = Column(
        EncryptedString(512),   # Encrypted at application layer
        unique=True,
        nullable=True,
        index=False,             # Can't index encrypted values - use phone_hash
    )
    phone_hash = Column(
        String(64),              # SHA-256 of phone - used for lookups
        unique=True,
        nullable=True,
        index=True,
    )
    email = Column(
        String(320),
        unique=True,
        nullable=True,
        index=True,
    )
    google_sub = Column(
        String(255),
        unique=True,
        nullable=True,
        index=True,
    )

    # -- Role --------------------------------------------------------
    role = Column(
        SAEnum(UserRole, name="userrole"),
        nullable=False,
    )

    # -- Profile --------------------------------------------------------
    full_name = Column(EncryptedString(512), nullable=True)
    fcm_token = Column(String(512), nullable=True)   # Firebase push token

    # -- Status --------------------------------------------------------
    is_active   = Column(Boolean, default=True, nullable=False)
    is_verified = Column(Boolean, default=False, nullable=False)

    # -- Timestamps --------------------------------------------------------
    created_at   = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
    updated_at   = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc),
                          onupdate=lambda: datetime.now(timezone.utc))
    last_login   = Column(DateTime(timezone=True), nullable=True)

    def __repr__(self):
        return f"<User id={self.id} role={self.role}>"
