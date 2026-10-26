"""sincronizar comidas: versión en alimentos, platos y diario

Revision ID: 0006
Revises: 0005
Create Date: 2026-10-26 19:00:00
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = '0006'
down_revision: Union[str, None] = '0005'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

_TABLES = ('foods', 'dishes', 'diary_items')


def upgrade() -> None:
    for table in _TABLES:
        # server_default solo para rellenar lo existente; luego se quita (el modelo pone el valor)
        op.add_column(table, sa.Column('version', sa.Integer(), server_default='1', nullable=False))
        op.alter_column(table, 'version', server_default=None)
        op.add_column(table, sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False))
        op.alter_column(table, 'updated_at', server_default=None)


def downgrade() -> None:
    for table in _TABLES:
        op.drop_column(table, 'updated_at')
        op.drop_column(table, 'version')
