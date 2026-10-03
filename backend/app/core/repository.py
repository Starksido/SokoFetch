"""
Repository pattern — thin async wrappers around SQLAlchemy queries.
Keeps route handlers clean: they call repo methods, never raw SQL.
"""
from typing import TypeVar, Type, Optional, List, Any
from uuid import UUID

from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func

from app.core.database import Base
from app.core.exceptions import NotFoundError

ModelT = TypeVar("ModelT", bound=Base)


class BaseRepository:
    """Generic async CRUD for any SQLAlchemy model."""

    def __init__(self, model: Type[ModelT], db: AsyncSession):
        self.model = model
        self.db = db

    # ── Read ──────────────────────────────────────────────────────────────────
    async def get(self, id: str | UUID) -> Optional[ModelT]:
        return await self.db.get(self.model, id)

    async def get_or_404(self, id: str | UUID, label: str | None = None) -> ModelT:
        obj = await self.db.get(self.model, id)
        if obj is None:
            raise NotFoundError(label or self.model.__name__)
        return obj

    async def get_by(self, **kwargs) -> Optional[ModelT]:
        stmt = select(self.model).filter_by(**kwargs)
        result = await self.db.execute(stmt)
        return result.scalar_one_or_none()

    async def get_by_or_404(self, label: str | None = None, **kwargs) -> ModelT:
        obj = await self.get_by(**kwargs)
        if obj is None:
            raise NotFoundError(label or self.model.__name__)
        return obj

    async def list(
        self,
        *filters,
        order_by=None,
        offset: int = 0,
        limit: int = 20,
    ) -> List[ModelT]:
        stmt = select(self.model)
        if filters:
            stmt = stmt.where(*filters)
        if order_by is not None:
            stmt = stmt.order_by(order_by)
        stmt = stmt.offset(offset).limit(limit)
        result = await self.db.execute(stmt)
        return list(result.scalars().all())

    async def count(self, *filters) -> int:
        stmt = select(func.count()).select_from(self.model)
        if filters:
            stmt = stmt.where(*filters)
        result = await self.db.execute(stmt)
        return result.scalar_one()

    # ── Write ─────────────────────────────────────────────────────────────────
    async def create(self, **kwargs) -> ModelT:
        obj = self.model(**kwargs)
        self.db.add(obj)
        await self.db.flush()
        await self.db.refresh(obj)
        return obj

    async def update(self, obj: ModelT, **kwargs) -> ModelT:
        for key, value in kwargs.items():
            if value is not None:
                setattr(obj, key, value)
        await self.db.flush()
        await self.db.refresh(obj)
        return obj

    async def delete(self, obj: ModelT) -> None:
        await self.db.delete(obj)
        await self.db.flush()


# ── Typed repositories ────────────────────────────────────────────────────────
# Import models lazily to avoid circular imports

class UserRepo(BaseRepository):
    def __init__(self, db: AsyncSession):
        from app.models.user import User
        super().__init__(User, db)

    async def get_by_phone_hash(self, phone_hash: str):
        return await self.get_by(phone_hash=phone_hash)




class MerchantRepo(BaseRepository):
    def __init__(self, db: AsyncSession):
        from app.models.merchant import Merchant
        super().__init__(Merchant, db)

    async def get_by_user_id(self, user_id: str):
        return await self.get_by(user_id=user_id)

    async def get_active(self, offset=0, limit=20):
        from app.models.merchant import MerchantStatus
        return await self.list(
            self.model.status == MerchantStatus.active,
            order_by=self.model.rating.desc(),
            offset=offset, limit=limit,
        )








class CustomerRepo(BaseRepository):
    def __init__(self, db: AsyncSession):
        from app.models.customer import Customer
        super().__init__(Customer, db)

    async def get_by_user_id(self, user_id: str):
        return await self.get_by(user_id=user_id)


class DeliveryAddressRepo(BaseRepository):
    def __init__(self, db: AsyncSession):
        from app.models.customer import DeliveryAddress
        super().__init__(DeliveryAddress, db)

    async def get_for_customer(self, customer_id: str):
        return await self.list(
            self.model.customer_id == customer_id,
            order_by=self.model.is_default.desc(),
        )


class MenuItemRepo(BaseRepository):
    def __init__(self, db: AsyncSession):
        from app.models.merchant import MenuItem
        super().__init__(MenuItem, db)

    async def get_for_merchant(self, merchant_id: str):
        return await self.list(
            self.model.merchant_id == merchant_id,
            order_by=self.model.sort_order.asc(),
        )

    async def get_available_for_merchant(self, merchant_id: str):
        return await self.list(
            self.model.merchant_id == merchant_id,
            self.model.is_available == True,
            order_by=self.model.sort_order.asc(),
        )


class CourierRepo(BaseRepository):
    def __init__(self, db: AsyncSession):
        from app.models.courier import Courier
        super().__init__(Courier, db)

    async def get_by_user_id(self, user_id: str):
        return await self.get_by(user_id=user_id)

    async def get_available_couriers(self):
        """Online, active couriers ready to receive dispatch."""
        from app.models.courier import CourierStatus
        return await self.list(
            self.model.status == CourierStatus.active,
            self.model.is_online == True,
        )


class OrderRepo(BaseRepository):
    def __init__(self, db: AsyncSession):
        from app.models.order import Order
        super().__init__(Order, db)

    async def get_for_customer(self, customer_id: str, offset=0, limit=20):
        from app.models.order import OrderStatus
        return await self.list(
            self.model.customer_id == customer_id,
            order_by=self.model.created_at.desc(),
            offset=offset, limit=limit,
        )

    async def get_active_for_customer(self, customer_id: str):
        from app.models.order import OrderStatus
        terminal = {OrderStatus.delivered, OrderStatus.cancelled, OrderStatus.delivery_failed}
        from sqlalchemy import not_
        stmt = select(self.model).where(
            self.model.customer_id == customer_id,
            self.model.status.not_in([s.value for s in terminal])
        ).order_by(self.model.created_at.desc()).limit(1)
        result = await self.db.execute(stmt)
        return result.scalar_one_or_none()

    async def get_for_merchant(self, merchant_id: str, offset=0, limit=20):
        return await self.list(
            self.model.merchant_id == merchant_id,
            order_by=self.model.created_at.desc(),
            offset=offset, limit=limit,
        )

    async def get_pending_for_merchant(self, merchant_id: str):
        from app.models.order import OrderStatus
        return await self.list(
            self.model.merchant_id == merchant_id,
            self.model.status == OrderStatus.pending,
            order_by=self.model.created_at.asc(),
        )

    async def get_for_courier(self, courier_id: str, offset=0, limit=20):
        return await self.list(
            self.model.courier_id == courier_id,
            order_by=self.model.created_at.desc(),
            offset=offset, limit=limit,
        )


class PaymentRepo(BaseRepository):
    def __init__(self, db: AsyncSession):
        from app.models.payment import Payment
        super().__init__(Payment, db)

    async def get_by_gateway_ref(self, gateway_ref: str):
        return await self.get_by(gateway_ref=gateway_ref)
