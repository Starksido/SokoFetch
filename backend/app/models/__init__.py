# Import all models here so Alembic's autogenerate detects them
# and so relationships resolve correctly at startup.

from app.models.user import User, UserRole          # noqa: F401
from app.models.customer import Customer, DeliveryAddress  # noqa: F401
from app.models.merchant import Merchant, MenuItem, MerchantStatus, MerchantCategory  # noqa: F401
from app.models.courier import Courier, CourierDocument, CourierStatus, DocumentType  # noqa: F401
from app.models.order import Order, OrderStatus, VALID_TRANSITIONS  # noqa: F401
from app.models.payment import Payment  # noqa: F401

__all__ = [
    "User", "UserRole",
    "Customer", "DeliveryAddress",
    "Merchant", "MenuItem", "MerchantStatus", "MerchantCategory",
    "Courier", "CourierDocument", "CourierStatus", "DocumentType",
    "Order", "OrderStatus", "VALID_TRANSITIONS",
    "Payment",
]
