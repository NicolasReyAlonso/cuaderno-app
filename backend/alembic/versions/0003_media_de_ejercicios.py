"""fotos y vídeos de los ejercicios propios

Revision ID: 0003
Revises: 0002
Create Date: 2026-10-23 19:00:00
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = '0003'
down_revision: Union[str, None] = '0002'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table('exercise_media',
    sa.Column('id', sa.Uuid(), nullable=False),
    sa.Column('exercise_id', sa.String(length=64), nullable=False),
    sa.Column('owner_id', sa.Uuid(), nullable=False),
    sa.Column('position', sa.Integer(), nullable=False),
    sa.Column('kind', sa.String(length=10), nullable=False),
    sa.Column('content_type', sa.String(length=40), nullable=False),
    sa.Column('size_bytes', sa.Integer(), nullable=False),
    sa.Column('path', sa.String(length=120), nullable=False),
    sa.Column('created_at', sa.DateTime(timezone=True), nullable=False),
    sa.CheckConstraint("kind in ('image','video')", name=op.f('ck_exercise_media_exercise_media_kind')),
    sa.ForeignKeyConstraint(['exercise_id'], ['exercises.id'], name=op.f('fk_exercise_media_exercise_id_exercises'), ondelete='CASCADE'),
    sa.ForeignKeyConstraint(['owner_id'], ['users.id'], name=op.f('fk_exercise_media_owner_id_users'), ondelete='CASCADE'),
    sa.PrimaryKeyConstraint('id', name=op.f('pk_exercise_media'))
    )
    op.create_index(op.f('ix_exercise_media_exercise_id'), 'exercise_media', ['exercise_id'], unique=False)
    op.create_index(op.f('ix_exercise_media_owner_id'), 'exercise_media', ['owner_id'], unique=False)


def downgrade() -> None:
    # Los archivos en disco no se borran: quedan en media_dir
    op.drop_index(op.f('ix_exercise_media_owner_id'), table_name='exercise_media')
    op.drop_index(op.f('ix_exercise_media_exercise_id'), table_name='exercise_media')
    op.drop_table('exercise_media')
