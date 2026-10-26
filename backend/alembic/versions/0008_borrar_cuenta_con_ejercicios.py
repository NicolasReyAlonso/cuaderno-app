"""claves a ejercicios comprobadas al confirmar (para poder borrar una cuenta)

Revision ID: 0008
Revises: 0007
Create Date: 2026-10-27 18:00:00

Al borrar un usuario, Postgres borra en cascada sus ejercicios propios y, por otro camino,
sus planes (con sus huecos) y sus sesiones (con sus series). Si la clave de un hueco o una
serie al ejercicio se comprueba en el momento, puede saltar antes de que se borre el hueco.
Comprobándola al confirmar la transacción, ya está todo borrado.
"""
from typing import Sequence, Union

from alembic import op


revision: str = '0008'
down_revision: Union[str, None] = '0007'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

_FKS = [
    ('fk_program_slots_exercise_id_exercises', 'program_slots', 'exercise_id'),
    ('fk_workout_sets_exercise_id_exercises', 'workout_sets', 'exercise_id'),
    ('fk_workout_sets_slot_exercise_id_exercises', 'workout_sets', 'slot_exercise_id'),
]


def _recreate(deferred: bool) -> None:
    for name, table, column in _FKS:
        op.drop_constraint(op.f(name), table, type_='foreignkey')
        op.create_foreign_key(op.f(name), table, 'exercises', [column], ['id'],
                              deferrable=True if deferred else None, initially='DEFERRED' if deferred else None)


def upgrade() -> None:
    _recreate(True)


def downgrade() -> None:
    _recreate(False)
