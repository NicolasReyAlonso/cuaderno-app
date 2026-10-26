import uuid

from fastapi.testclient import TestClient

from app.main import app

from .test_media import PNG
from .test_sync import _by_key, _op, _pull, _push


def _session(d="2026-10-20", day="piernaA", crunch_reps=15):
    return {"date": d, "day_key": day, "program_id": "definicion-5d", "week": 1, "slots": [
        {"slot_exercise_id": "sentadilla_smith", "exercise_id": "sentadilla_smith", "sets": [{"load_kg": 60, "reps": 10}] * 4},
        {"slot_exercise_id": "crunch_polea", "exercise_id": "crunch", "sets": [{"load_kg": 0, "reps": crunch_reps}] * 3 + [{}]},
    ]}


def test_session_saved_offline_is_the_same_as_online(auth):
    r = _push(auth, _op("workout_session", "2026-10-20/piernaA", 0, _session()))[0]
    assert r["status"] == "applied", r
    crunch = r["server"]["data"]["slots"][1]
    assert (crunch["exercise_id"], len(crunch["sets"])) == ("crunch", 3)  # las series vacías no se guardan

    # El servidor la usa igual que una guardada online: plan de la semana siguiente y sugerencias
    plan = auth.get("/workouts/2026-10-27/piernaA/plan").json()
    by_slot = {s["slot_exercise_id"]: s for s in plan["slots"]}
    assert by_slot["crunch_polea"]["exercise_id"] == "crunch" and by_slot["sentadilla_smith"]["hint"]["text"] == "Sube 2,5 kg"
    assert auth.get("/workouts/2026-10-20/piernaA").json()["week"] == 1


def test_same_day_on_two_devices_is_a_conflict_not_a_duplicate(auth):
    _push(auth, _op("workout_session", "2026-10-21/torsoA", 0, _session("2026-10-21", "torsoA")))
    other_device = _push(auth, _op("workout_session", "2026-10-21/torsoA", 0, _session("2026-10-21", "torsoA", crunch_reps=12)))[0]
    assert other_device["status"] == "conflict" and other_device["server"]["version"] == 1
    assert len([s for s in auth.get("/workouts").json() if s["date"] == "2026-10-21"]) == 1


def test_rest_sessions_reach_the_sync(auth):
    cursor = _pull(auth, 0)["cursor"]
    body = {"slots": [{"slot_exercise_id": "press_banca", "exercise_id": "press_banca", "sets": [{"load_kg": 70, "reps": 8}]}]}
    auth.put("/workouts/2026-10-19/torsoA", json=body)
    got = _by_key(_pull(auth, cursor)["changes"])[("workout_session", "2026-10-19/torsoA")]
    assert got["version"] == 1 and got["data"]["slots"][0]["sets"] == [{"load_kg": 70.0, "reps": 8}]
    # Cambiar solo las series cuenta como cambio de la sesión
    body["slots"][0]["sets"].append({"load_kg": 70, "reps": 7})
    auth.put("/workouts/2026-10-19/torsoA", json=body)
    assert _by_key(_pull(auth, cursor)["changes"])[("workout_session", "2026-10-19/torsoA")]["version"] == 2
    auth.delete("/workouts/2026-10-19/torsoA")
    assert _by_key(_pull(auth, cursor)["changes"])[("workout_session", "2026-10-19/torsoA")]["deleted"]


def test_session_validation(auth):
    dup = _session("2026-10-22")
    dup["slots"][1]["exercise_id"] = "sentadilla_smith"
    empty = {**_session("2026-10-22"), "slots": [{"slot_exercise_id": "crunch_polea", "exercise_id": "crunch", "sets": [{}]}]}
    unknown = {**_session("2026-10-22"), "slots": [{"slot_exercise_id": "no_existe", "exercise_id": "no_existe", "sets": [{"reps": 1}]}]}
    res = _push(auth, _op("workout_session", "2026-10-22/piernaA", 0, dup), _op("workout_session", "2026-10-22/piernaA", 0, empty),
                _op("workout_session", "2026-10-22/piernaA", 0, unknown), _op("workout_session", "2026-10-23/piernaA", 0, _session()),
                _op("workout_session", "sin-barra", 0, _session()))
    assert [r["status"] for r in res] == ["rejected"] * 5
    assert "dos veces" in res[0]["detail"] and res[1]["detail"] == "Apunta al menos una serie antes de guardar."
    assert res[2]["detail"].startswith("El ejercicio «no_existe» no existe")
    assert "no coinciden" in res[3]["detail"] and "AAAA-MM-DD/día" in res[4]["detail"]


def test_own_exercises_and_programs_are_downloaded(auth):
    cursor = _pull(auth, 0)["cursor"]
    ex = auth.post("/exercises", json={"name": "Remo en máquina", "muscle_group": "Espalda"}).json()
    plan = {"name": "Mío", "weeks": 1, "days": [{"key": "espalda", "weekday": 2, "name": "Espalda", "slots": [
        {"exercise_id": ex["id"], "sets": 3, "rep_min": 8, "rep_max": 12}]}]}
    p = auth.post("/programs", json=plan).json()
    got = _by_key(_pull(auth, cursor)["changes"])
    assert got[("exercise", ex["id"])]["data"]["name"] == "Remo en máquina"
    assert got[("program", p["id"])]["data"]["days"][0]["slots"][0]["exercise_id"] == ex["id"]

    # Cambiar un hueco del plan o subir una foto cuenta como cambio del plan o del ejercicio
    cur2 = _pull(auth, cursor)["cursor"]
    plan["days"][0]["slots"][0]["rep_max"] = 15
    auth.put(f"/programs/{p['id']}", json=plan)
    media = auth.post(f"/exercises/{ex['id']}/media", files={"file": ("f.png", PNG, "image/png")}).json()
    got = _by_key(_pull(auth, cur2)["changes"])
    assert got[("program", p["id"])]["data"]["days"][0]["slots"][0]["rep_max"] == 15
    assert got[("exercise", ex["id"])]["data"]["media"] == [{"id": media["id"], "kind": "image", "content_type": "image/png", "size_bytes": len(PNG)}]

    # Las URL se piden aparte (caducan); solo las tuyas
    other = TestClient(app)
    tok = other.post("/auth/register", json={"email": f"{uuid.uuid4().hex[:10]}@example.com", "password": "contraseña-larga"})
    other.headers["Authorization"] = f"Bearer {tok.json()['access_token']}"
    urls = auth.post("/media/urls", json={"ids": [media["id"]]}).json()
    assert urls[media["id"]].startswith(f"/media/{media['id']}?sig=")
    assert other.post("/media/urls", json={"ids": [media["id"]]}).json() == {}



def test_reference_has_exercises_alternatives_and_templates(auth):
    r = auth.get("/sync/reference").json()
    assert len(r["exercises"]) == 61 and all("figure" in e for e in r["exercises"])
    assert "dominadas_negativas" in r["alternatives"]["dominadas"]
    t = next(t for t in r["templates"] if t["id"] == "definicion-5d")
    assert len(t["days"]) == 5 and t["days"][0]["slots"][0]["exercise_id"] == "dominadas"
    # Las plantillas y el catálogo no se descargan por usuario
    assert not {c["entity"] for c in _pull(auth, 0)["changes"]} & {"exercise", "program"}
