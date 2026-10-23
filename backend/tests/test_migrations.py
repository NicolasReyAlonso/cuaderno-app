"""Migraciones contra PostgreSQL real, en un esquema aparte para no tocar las tablas de los demás tests."""
import uuid
from pathlib import Path

import pytest
from alembic import command
from alembic.autogenerate import compare_metadata
from alembic.config import Config
from alembic.migration import MigrationContext
from sqlalchemy import create_engine, text
from sqlalchemy.exc import IntegrityError

from app.db import Base, engine

BACKEND = Path(__file__).resolve().parents[1]
SCHEMA = "test_migraciones"


@pytest.fixture
def migrations():
    """Conexión con search_path en un esquema vacío y la config de Alembic que la usa."""
    with engine.begin() as c:
        c.execute(text(f"DROP SCHEMA IF EXISTS {SCHEMA} CASCADE"))
        c.execute(text(f"CREATE SCHEMA {SCHEMA}"))
    eng = create_engine(engine.url, connect_args={"options": f"-csearch_path={SCHEMA}"})
    try:
        with eng.connect() as conn:
            cfg = Config(str(BACKEND / "alembic.ini"))
            cfg.set_main_option("script_location", str(BACKEND / "alembic"))
            cfg.attributes["connection"] = conn

            def run(fn, rev):
                fn(cfg, rev)
                conn.commit()

            yield conn, run
    finally:
        eng.dispose()
        with engine.begin() as c:
            c.execute(text(f"DROP SCHEMA IF EXISTS {SCHEMA} CASCADE"))


def _insert_day(conn, week: int | None, key: str = "torsoA"):
    cols = "program_id, key, position, name, short, focus, color" + (", week" if week else "")
    vals = "'definicion-5d', :k, 1, 'Torso A', 'TA', '', 'blue'" + (", :w" if week else "")
    conn.execute(text(f"INSERT INTO program_days ({cols}) VALUES ({vals})"), {"k": key, "w": week})


def test_0002_moves_existing_data_to_week_1(migrations):
    conn, run = migrations
    run(command.upgrade, "0001")
    uid = uuid.uuid4()
    conn.execute(text("INSERT INTO programs (id, name) VALUES ('definicion-5d', 'Definición 5 días')"))
    _insert_day(conn, None)
    conn.execute(text("INSERT INTO users (id, email, password_hash, name, created_at, kcal_target, protein_target_g, program_id) "
                      "VALUES (:u, 'nico@example.com', 'x', 'Nico', now(), 2000, 160, 'definicion-5d')"), {"u": uid})
    conn.execute(text("INSERT INTO workout_sessions (id, user_id, date, day_key, updated_at) "
                      "VALUES (:s, :u, '2026-10-20', 'torsoA', now())"), {"s": uuid.uuid4(), "u": uid})
    conn.execute(text("INSERT INTO exercises (id, name, muscle_group, cue, unit, load_mode, is_compound, figure) "
                      "VALUES ('press_banca', 'Press banca', 'Pecho', '', 'reps', 'kg', true, '{}')"))
    conn.commit()

    run(command.upgrade, "0002")

    assert conn.execute(text("SELECT weeks FROM programs")).scalar_one() == 1
    assert conn.execute(text("SELECT week FROM program_days")).scalar_one() == 1
    assert conn.execute(text("SELECT program_started_on FROM users")).scalar_one() is None
    assert conn.execute(text("SELECT program_id, week FROM workout_sessions")).one() == ("definicion-5d", 1)
    assert conn.execute(text("SELECT owner_id FROM exercises")).scalar_one() is None

    # La misma key puede estar en otra semana, pero no dos veces en la misma
    _insert_day(conn, 2)
    with pytest.raises(IntegrityError), conn.begin_nested():
        _insert_day(conn, 2)
    for bad in ("UPDATE programs SET weeks = 5", "UPDATE programs SET weeks = 0", "UPDATE program_days SET week = 0"):
        with pytest.raises(IntegrityError), conn.begin_nested():
            conn.execute(text(bad))
    conn.commit()

    # Borrar el plan no borra el historial
    conn.execute(text("UPDATE users SET program_id = NULL"))
    conn.execute(text("DELETE FROM programs"))
    assert conn.execute(text("SELECT program_id FROM workout_sessions")).scalar_one() is None
    conn.commit()


def test_head_matches_models_and_downgrades(migrations):
    conn, run = migrations
    run(command.upgrade, "head")
    diff = compare_metadata(MigrationContext.configure(conn, opts={"compare_type": True}), Base.metadata)
    assert diff == [], "models.py y las migraciones no coinciden: falta una migración o hay que revisarla"
    run(command.downgrade, "0001")
    run(command.upgrade, "head")
