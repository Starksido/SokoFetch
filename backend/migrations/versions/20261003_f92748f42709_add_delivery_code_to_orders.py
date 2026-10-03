"""add delivery_code to orders

Revision ID: f92748f42709
Revises: 820f5db82417
Create Date: 2026-10-03 00:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = 'f92748f42709'
down_revision: Union[str, None] = '820f5db82417'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # Encrypted at the application layer (EncryptedString) — plain VARCHAR here.
    # Existing paid orders get a code lazily on GET /orders/{id}/delivery-code.
    op.add_column('orders', sa.Column('delivery_code', sa.String(length=512), nullable=True))


def downgrade() -> None:
    op.drop_column('orders', 'delivery_code')
