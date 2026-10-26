import uuid

from .test_sync import _by_key, _op, _pull, _push


def _uid() -> str:
    return "u:" + uuid.uuid4().hex[:12]


def _exercise(name="Remo en máquina"):
    return {"name": name, "muscle_group": "Espalda", "cue": "", "unit": "reps", "load_mode": "kg", "is_compound": True,
            "default_rep_min": None, "default_rep_max": None}


def _plan(ex_id="remo_barra", rep_max=12, weeks=1):
    return {"name": "Mío sin conexión", "weeks": weeks, "days": [
        {"week": 1, "key": "espalda", "position": 0, "weekday": 2, "name": "Espalda", "short": "", "focus": "", "color": "blue",
         "slots": [{"exercise_id": ex_id, "sets": 3, "rep_min": 8, "rep_max": rep_max, "rest": "2 min", "is_core": False}]}]}


def test_exercise_plan_activation_and_session_all_created_offline(auth):
    ex, prog = _uid(), _uid()
    profile = {**auth.get("/sync/pull", params={"since": 0}).json()["changes"][0]["data"], "program_id": prog, "program_started_on": "2026-10-19"}
    session = {"date": "2026-10-20", "day_key": "espalda", "program_id": prog, "week": 1,
               "slots": [{"slot_exercise_id": ex, "exercise_id": ex, "sets": [{"load_kg": 50, "reps": 10}]}]}
    # En el orden en que se hicieron: ejercicio → plan que lo usa → activarlo → entrenar
    res = _push(auth, _op("exercise", ex, 0, _exercise()), _op("program", prog, 0, _plan(ex)), _op("profile", "me", 1, profile),
                _op("workout_session", "2026-10-20/espalda", 0, session))
    assert [r["status"] for r in res] == ["applied"] * 4, res
    assert "a" in res[0]["server"]["data"]["figure"]  # la figura genérica la pone el servidor
    assert res[1]["server"]["data"]["days"][0]["position"] == 0

    # El servidor lo trata como si se hubiera hecho online
    assert auth.get("/me").json()["program_id"] == prog
    assert auth.get("/workouts/2026-10-27/today").json()["day_key"] == "espalda"
    nxt = auth.get("/workouts/2026-10-27/espalda/plan").json()["slots"][0]
    assert (nxt["exercise_id"], nxt["last"]["date"], nxt["hint"]["kind"]) == (ex, "2026-10-20", "rep")


def test_edit_conflict_and_validation(auth):
    prog = _uid()
    _push(auth, _op("program", prog, 0, _plan()))
    auth.put(f"/programs/{prog}", json=_plan(rep_max=15))  # otro dispositivo, online
    c = _push(auth, _op("program", prog, 1, _plan(rep_max=10)))[0]
    assert c["status"] == "conflict" and c["server"]["data"]["days"][0]["slots"][0]["rep_max"] == 15
    mine = _push(auth, _op("program", prog, 2, _plan(rep_max=10)))[0]
    assert (mine["status"], mine["version"]) == ("applied", 3)

    bad_week = {**_plan(), "days": [{**_plan()["days"][0], "week": 2}]}
    res = _push(auth, _op("program", prog, 3, bad_week), _op("program", _uid(), 0, _plan("no_existe")),
                _op("program", "definicion-5d", 0, _plan()), _op("program", "sin-prefijo", 0, _plan()))
    assert [r["status"] for r in res] == ["rejected"] * 4
    assert res[0]["detail"].startswith("«Espalda» está en la semana 2, pero el plan tiene 1 semana")
    assert res[1]["detail"].startswith("El ejercicio «no_existe» no existe")
    assert "u:" in res[2]["detail"] and "u:" in res[3]["detail"]  # una plantilla no se puede pisar desde la app
    assert auth.get("/programs/definicion-5d").json()["mine"] is False


def test_delete_plan_and_exercise_rules(auth):
    prog = _uid()
    me = auth.get("/sync/pull", params={"since": 0}).json()["changes"][0]
    _push(auth, _op("program", prog, 0, _plan()), _op("profile", "me", me["version"], {**me["data"], "program_id": prog}))
    active = _push(auth, _op("program", prog, 1, delete=True))[0]
    assert (active["status"], active["detail"]) == ("rejected", "Es tu plan activo. Activa otro antes de borrarlo.")
    # Activar otro y luego borrarlo, en orden en el mismo envío
    res = _push(auth, _op("profile", "me", me["version"] + 1, {**me["data"], "program_id": "definicion-5d"}), _op("program", prog, 1, delete=True))
    assert [r["status"] for r in res] == ["applied", "applied"]
    assert auth.get(f"/programs/{prog}").status_code == 404

    ex = _uid()
    _push(auth, _op("exercise", ex, 0, _exercise()))
    gone = _push(auth, _op("exercise", ex, 1, delete=True))[0]
    assert gone["status"] == "rejected" and "no se borran" in gone["detail"]


def test_exercise_edit_keeps_figure_and_media(auth):
    ex = _uid()
    created = _push(auth, _op("exercise", ex, 0, _exercise()))[0]["server"]["data"]
    cursor = _pull(auth, 0)["cursor"]
    edited = _push(auth, _op("exercise", ex, 1, {**_exercise("Remo en polea"), "figure": {"x": 1}, "media": [{"id": "falso"}]}))[0]
    data = edited["server"]["data"]
    assert (data["name"], data["figure"], data["media"]) == ("Remo en polea", created["figure"], [])
    assert _by_key(_pull(auth, cursor)["changes"])[("exercise", ex)]["version"] == 2
    assert any(e["id"] == ex and e["name"] == "Remo en polea" for e in auth.get("/catalog").json()["exercises"])


def test_deleting_an_account_with_own_exercises_in_plans_and_history(auth):
    """Al borrar la cuenta, sus ejercicios propios se van a la vez que los planes y series que los usan."""
    from sqlalchemy import select

    from app.db import SessionLocal
    from app.models import Exercise, User

    ex, prog = _uid(), _uid()
    me = auth.get("/sync/pull", params={"since": 0}).json()["changes"][0]
    session = {"date": "2026-10-20", "day_key": "espalda", "program_id": prog, "week": 1,
               "slots": [{"slot_exercise_id": ex, "exercise_id": ex, "sets": [{"load_kg": 50, "reps": 10}]}]}
    res = _push(auth, _op("exercise", ex, 0, _exercise()), _op("program", prog, 0, _plan(ex)),
                _op("profile", "me", me["version"], {**me["data"], "program_id": prog}), _op("workout_session", "2026-10-20/espalda", 0, session))
    assert [r["status"] for r in res] == ["applied"] * 4
    email = auth.get("/me").json()["email"]
    with SessionLocal() as db:
        db.delete(db.scalar(select(User).where(User.email == email)))
        db.commit()
        assert db.get(Exercise, ex) is None
