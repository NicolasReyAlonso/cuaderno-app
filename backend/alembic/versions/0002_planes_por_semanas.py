"""planes por semanas y ejercicios propios

Revision ID: 0002
Revises: 0001
Create Date: 2026-10-23 17:30:00

- programs.weeks (1–4); program_days.week, único por (programa, semana, key)
- users.program_started_on
- workout_sessions.program_id y workout_sessions.week
- exercises.owner_id (nulo = catálogo)

Lo existente queda en la semana 1, y las sesiones, con el programa por defecto.
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = '0002'
down_revision: Union[str, None] = '0001'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

DEFAULT_PROGRAM = "definicion-5d"  # copia de app.seed: la migración no debe depender del código de la app


def _add_week_column(table: str, name: str) -> None:
    # server_default solo para rellenar las filas que ya existen; luego se quita (el modelo pone default=1)
    op.add_column(table, sa.Column(name, sa.Integer(), server_default="1", nullable=False))
    op.alter_column(table, name, server_default=None)


def upgrade() -> None:
    _add_week_column('programs', 'weeks')
    op.create_check_constraint(op.f('ck_programs_program_weeks'), 'programs', 'weeks between 1 and 4')

    _add_week_column('program_days', 'week')
    op.create_check_constraint(op.f('ck_program_days_program_day_week'), 'program_days', 'week >= 1')
    # La convención de nombres da el mismo nombre a la restricción nueva: primero se borra la vieja
    op.drop_constraint(op.f('uq_program_days_program_id'), 'program_days', type_='unique')
    op.create_unique_constraint(op.f('uq_program_days_program_id'), 'program_days', ['program_id', 'week', 'key'])

    op.add_column('users', sa.Column('program_started_on', sa.Date(), nullable=True))

    op.add_column('workout_sessions', sa.Column('program_id', sa.String(length=64), nullable=True))
    op.create_foreign_key(op.f('fk_workout_sessions_program_id_programs'), 'workout_sessions', 'programs',
                          ['program_id'], ['id'], ondelete='SET NULL')
    _add_week_column('workout_sessions', 'week')
    op.execute(sa.text("UPDATE workout_sessions SET program_id = :p WHERE program_id IS NULL "
                       "AND EXISTS (SELECT 1 FROM programs WHERE id = :p)").bindparams(p=DEFAULT_PROGRAM))

    op.add_column('exercises', sa.Column('owner_id', sa.Uuid(), nullable=True))
    op.create_foreign_key(op.f('fk_exercises_owner_id_users'), 'exercises', 'users', ['owner_id'], ['id'], ondelete='CASCADE')
    op.create_index(op.f('ix_exercises_owner_id'), 'exercises', ['owner_id'], unique=False)


def downgrade() -> None:
    # Los ejercicios propios se quedan como si fueran del catálogo: las series los siguen usando
    op.drop_index(op.f('ix_exercises_owner_id'), table_name='exercises')
    op.drop_constraint(op.f('fk_exercises_owner_id_users'), 'exercises', type_='foreignkey')
    op.drop_column('exercises', 'owner_id')

    op.drop_column('workout_sessions', 'week')
    op.drop_constraint(op.f('fk_workout_sessions_program_id_programs'), 'workout_sessions', type_='foreignkey')
    op.drop_column('workout_sessions', 'program_id')

    op.drop_column('users', 'program_started_on')

    # Sin semanas, (programa, key) vuelve a ser único: se pierden los días de la semana 2 en adelante
    op.execute("DELETE FROM program_days WHERE week > 1")
    op.drop_constraint(op.f('uq_program_days_program_id'), 'program_days', type_='unique')
    op.create_unique_constraint(op.f('uq_program_days_program_id'), 'program_days', ['program_id', 'key'])
    op.drop_constraint(op.f('ck_program_days_program_day_week'), 'program_days', type_='check')
    op.drop_column('program_days', 'week')

    op.drop_constraint(op.f('ck_programs_program_weeks'), 'programs', type_='check')
    op.drop_column('programs', 'weeks')
