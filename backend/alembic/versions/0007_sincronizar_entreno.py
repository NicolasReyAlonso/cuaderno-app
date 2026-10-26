"""sincronizar entreno: versión en sesiones, ejercicios y planes

Revision ID: 0007
Revises: 0006
Create Date: 2026-10-27 10:00:00
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = '0007'
down_revision: Union[str, None] = '0006'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def _add(table: str, column: sa.Column) -> None:
    # server_default solo para rellenar lo existente; luego se quita (el modelo pone el valor)
    op.add_column(table, column)
    op.alter_column(table, column.name, server_default=None)


def upgrade() -> None:
    for table in ('workout_sessions', 'exercises', 'programs'):
        _add(table, sa.Column('version', sa.Integer(), server_default='1', nullable=False))
    for table in ('exercises', 'programs'):  # workout_sessions ya tenía updated_at
        _add(table, sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False))


def downgrade() -> None:
    for table in ('exercises', 'programs'):
        op.drop_column(table, 'updated_at')
    for table in ('workout_sessions', 'exercises', 'programs'):
        op.drop_column(table, 'version')
