"""add pending_payout to merchants

Revision ID: 820f5db82417
Revises: 8464c67b6778
Create Date: 2026-10-03 00:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = '820f5db82417'
down_revision: Union[str, None] = '8464c67b6778'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # server_default backfills existing rows; dropped afterwards to match the
    # model (and couriers.pending_payout), which default in Python.
    op.add_column(
        'merchants',
        sa.Column('pending_payout', sa.Numeric(precision=12, scale=2),
                  nullable=False, server_default='0'),
    )
    op.alter_column('merchants', 'pending_payout', server_default=None)


def downgrade() -> None:
    op.drop_column('merchants', 'pending_payout')
