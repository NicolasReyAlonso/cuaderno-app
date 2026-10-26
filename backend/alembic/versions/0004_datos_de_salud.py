"""datos de salud: resumen diario, actividades y origen del peso

Revision ID: 0004
Revises: 0003
Create Date: 2026-10-26 10:00:00

Los pesos que ya existen quedan con weight_source = NULL, que cuenta como manual.
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = '0004'
down_revision: Union[str, None] = '0003'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column('body_entries', sa.Column('weight_source', sa.String(length=10), nullable=True))
    op.create_table('daily_metrics',
    sa.Column('user_id', sa.Uuid(), nullable=False),
    sa.Column('date', sa.Date(), nullable=False),
    sa.Column('steps', sa.Integer(), nullable=True),
    sa.Column('active_kcal', sa.Integer(), nullable=True),
    sa.Column('sleep_minutes', sa.Integer(), nullable=True),
    sa.Column('resting_hr', sa.Integer(), nullable=True),
    sa.Column('hrv_ms', sa.Numeric(precision=5, scale=1), nullable=True),
    sa.Column('updated_at', sa.DateTime(timezone=True), nullable=False),
    sa.ForeignKeyConstraint(['user_id'], ['users.id'], name=op.f('fk_daily_metrics_user_id_users'), ondelete='CASCADE'),
    sa.PrimaryKeyConstraint('user_id', 'date', name=op.f('pk_daily_metrics'))
    )
    op.create_table('activities',
    sa.Column('id', sa.Uuid(), nullable=False),
    sa.Column('user_id', sa.Uuid(), nullable=False),
    sa.Column('external_id', sa.String(length=120), nullable=False),
    sa.Column('kind', sa.String(length=40), nullable=False),
    sa.Column('started_at', sa.DateTime(timezone=True), nullable=False),
    sa.Column('ended_at', sa.DateTime(timezone=True), nullable=False),
    sa.Column('kcal', sa.Integer(), nullable=True),
    sa.Column('distance_m', sa.Integer(), nullable=True),
    sa.Column('source', sa.String(length=80), nullable=False),
    sa.ForeignKeyConstraint(['user_id'], ['users.id'], name=op.f('fk_activities_user_id_users'), ondelete='CASCADE'),
    sa.PrimaryKeyConstraint('id', name=op.f('pk_activities')),
    sa.UniqueConstraint('user_id', 'external_id', name=op.f('uq_activities_user_id'))
    )
    op.create_index(op.f('ix_activities_started_at'), 'activities', ['started_at'], unique=False)
    op.create_index(op.f('ix_activities_user_id'), 'activities', ['user_id'], unique=False)


def downgrade() -> None:
    op.drop_index(op.f('ix_activities_user_id'), table_name='activities')
    op.drop_index(op.f('ix_activities_started_at'), table_name='activities')
    op.drop_table('activities')
    op.drop_table('daily_metrics')
    op.drop_column('body_entries', 'weight_source')
