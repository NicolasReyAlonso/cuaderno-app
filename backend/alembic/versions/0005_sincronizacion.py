"""sincronización: versión en los registros, registro de cambios y operaciones aplicadas

Revision ID: 0005
Revises: 0004
Create Date: 2026-10-26 12:00:00

Los registros que ya existen empiezan en la versión 1. sync_log empieza vacío: la app
hace su primera descarga con since=0, que lee las tablas directamente.
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = '0005'
down_revision: Union[str, None] = '0004'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

_VERSIONED = ('users', 'body_entries', 'daily_metrics', 'activities')


def upgrade() -> None:
    for table in _VERSIONED:
        # server_default solo para rellenar lo existente; luego se quita (el modelo pone el valor)
        op.add_column(table, sa.Column('version', sa.Integer(), server_default='1', nullable=False))
        op.alter_column(table, 'version', server_default=None)
    for table in ('users', 'body_entries', 'activities'):  # daily_metrics ya tenía updated_at
        op.add_column(table, sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False))
        op.alter_column(table, 'updated_at', server_default=None)

    op.create_table('sync_log',
    sa.Column('seq', sa.BigInteger(), autoincrement=True, nullable=False),
    sa.Column('user_id', sa.Uuid(), nullable=False),
    sa.Column('entity', sa.String(length=30), nullable=False),
    sa.Column('entity_id', sa.String(length=80), nullable=False),
    sa.Column('version', sa.Integer(), nullable=False),
    sa.Column('deleted', sa.Boolean(), nullable=False),
    sa.Column('at', sa.DateTime(timezone=True), nullable=False),
    sa.ForeignKeyConstraint(['user_id'], ['users.id'], name=op.f('fk_sync_log_user_id_users'), ondelete='CASCADE'),
    sa.PrimaryKeyConstraint('seq', name=op.f('pk_sync_log'))
    )
    op.create_index('ix_sync_log_user_seq', 'sync_log', ['user_id', 'seq'], unique=False)
    op.create_table('sync_ops',
    sa.Column('user_id', sa.Uuid(), nullable=False),
    sa.Column('op_id', sa.Uuid(), nullable=False),
    sa.Column('result', sa.JSON(), nullable=False),
    sa.Column('at', sa.DateTime(timezone=True), nullable=False),
    sa.ForeignKeyConstraint(['user_id'], ['users.id'], name=op.f('fk_sync_ops_user_id_users'), ondelete='CASCADE'),
    sa.PrimaryKeyConstraint('user_id', 'op_id', name=op.f('pk_sync_ops'))
    )


def downgrade() -> None:
    op.drop_table('sync_ops')
    op.drop_index('ix_sync_log_user_seq', table_name='sync_log')
    op.drop_table('sync_log')
    for table in ('users', 'body_entries', 'activities'):
        op.drop_column(table, 'updated_at')
    for table in _VERSIONED:
        op.drop_column(table, 'version')
