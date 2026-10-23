import uuid
from datetime import date

from fastapi.testclient import TestClient

from app.main import app
from app.services.schedule import current_week


def _new_user() -> TestClient:
    c = TestClient(app)
    r = c.post("/auth/register", json={"email": f"{uuid.uuid4().hex[:10]}@example.com", "password": "contraseña-larga"})
    c.headers["Authorization"] = f"Bearer {r.json()['access_token']}"
    return c


def _slot(ex, sets=3, rmin=8, rmax=12):
    return {"exercise_id": ex, "sets": sets, "rep_min": rmin, "rep_max": rmax, "rest": "2 min"}


def _two_weeks():
    return {"name": "Fuerza y volumen", "weeks": 2, "days": [
        {"week": 2, "key": "torsoA", "weekday": 1, "name": "Torso A", "slots": [_slot("press_banca", 3, 10, 12), _slot("remo_barra")]},
        {"week": 1, "key": "torsoA", "weekday": 1, "name": "Torso A", "slots": [_slot("press_banca", 4, 5, 6), _slot("remo_barra")]},
        {"week": 2, "key": "pierna", "weekday": 3, "name": "Pierna", "slots": [_slot("sentadilla_smith")]},
    ]}


def test_current_week():
    monday = date(2026, 10, 19)
    assert current_week(None, 2, date(2026, 11, 30)) == 1
    assert current_week(monday, 1, date(2026, 11, 30)) == 1
    assert [current_week(monday, 2, date(2026, 10, n)) for n in (19, 25, 26)] == [1, 1, 2]
    assert current_week(monday, 2, date(2026, 11, 2)) == 1
    assert current_week(monday, 3, date(2026, 11, 9)) == 1  # tres semanas después vuelve a la 1
    assert current_week(monday, 2, date(2026, 10, 18)) == 2  # antes del inicio sigue el bucle hacia atrás


def test_program_crud_and_permissions(auth):
    template = next(p for p in auth.get("/programs").json() if p["id"] == "definicion-5d")
    assert template == {"id": "definicion-5d", "name": template["name"], "weeks": 1, "days_per_week": 5, "mine": False, "active": True}

    r = auth.post("/programs", json=_two_weeks())
    assert r.status_code == 201, r.text
    p = r.json()
    assert p["mine"] and p["weeks"] == 2 and p["id"].startswith("u:")
    # Ordenados por semana y, dentro de cada una, en el orden enviado
    assert [(d["week"], d["key"], d["position"]) for d in p["days"]] == [(1, "torsoA", 0), (2, "torsoA", 0), (2, "pierna", 1)]
    assert auth.get(f"/programs/{p['id']}").json() == p
    listed = next(x for x in auth.get("/programs").json() if x["id"] == p["id"])
    assert listed["days_per_week"] == 2 and not listed["active"]
    assert auth.get("/programs").json()[0]["mine"]  # los tuyos primero

    one_week = {"name": "Solo semana 1", "weeks": 1, "days": [_two_weeks()["days"][1]]}
    up = auth.put(f"/programs/{p['id']}", json=one_week).json()
    assert up["name"] == "Solo semana 1" and up["weeks"] == 1 and len(up["days"]) == 1

    assert auth.put("/programs/definicion-5d", json=one_week).status_code == 403
    assert auth.delete("/programs/definicion-5d").status_code == 403
    other = _new_user()
    assert other.get(f"/programs/{p['id']}").status_code == 404
    assert other.put(f"/programs/{p['id']}", json=one_week).status_code == 404
    assert other.delete(f"/programs/{p['id']}").status_code == 404
    assert p["id"] not in {x["id"] for x in other.get("/programs").json()}


def test_program_validation(auth):
    def detail(body):
        r = auth.post("/programs", json=body)
        assert r.status_code == 422, r.text
        d = r.json()["detail"]
        return d if isinstance(d, str) else d[0]["msg"]

    base = _two_weeks()
    assert detail({**base, "weeks": 1}).startswith("«Torso A» está en la semana 2, pero el plan tiene 1 semana")
    assert detail({**base, "weeks": 5}) and detail({**base, "weeks": 0})
    rep = {**base, "days": [{**base["days"][0], "slots": [_slot("press_banca"), _slot("press_banca")]}]}
    assert detail(rep) == "«press_banca» está dos veces en «Torso A». Cada ejercicio, una vez por día."
    assert "mínimo del rango" in detail({**base, "days": [{**base["days"][0], "slots": [_slot("press_banca", 3, 12, 8)]}]})
    assert detail({**base, "days": [base["days"][0], base["days"][0]]}) == "La clave «torsoA» se repite en la semana 2."
    same_weekday = {**base["days"][2], "key": "otro", "weekday": 1}
    assert detail({**base, "days": [base["days"][0], same_weekday]}).startswith("En la semana 2 hay dos días")
    assert detail({**base, "days": [{**base["days"][0], "key": "today"}]}).startswith("«today» está reservado")
    unknown = {**base, "days": [{**base["days"][0], "slots": [_slot("no_existe")]}]}
    assert detail(unknown).startswith("El ejercicio «no_existe» no existe")


def test_duplicate_activate_delete(auth):
    template = auth.get("/programs/definicion-5d").json()
    r = auth.post("/programs/definicion-5d/duplicate")
    assert r.status_code == 201
    dup = r.json()
    assert dup["mine"] and dup["name"] == template["name"] + " (copia)" and dup["id"] != template["id"]
    assert dup["days"] == template["days"]

    me = auth.post(f"/programs/{dup['id']}/activate", json={"started_on": "2026-10-19"}).json()
    assert me["program_id"] == dup["id"] and me["program_started_on"] == "2026-10-19"
    assert auth.get("/catalog").json()["program"]["id"] == dup["id"]
    assert auth.delete(f"/programs/{dup['id']}").status_code == 409

    auth.post("/programs/definicion-5d/activate", json={"started_on": "2026-10-19"})
    assert auth.delete(f"/programs/{dup['id']}").status_code == 204
    assert auth.get(f"/programs/{dup['id']}").status_code == 404
    assert auth.post("/programs/no-existe/activate", json={"started_on": "2026-10-19"}).status_code == 404
    # El plan ya no se cambia por PATCH /me (no comprobaba que fuera tuyo)
    auth.patch("/me", json={"program_id": dup["id"]})
    assert auth.get("/me").json()["program_id"] == "definicion-5d"


def test_own_exercises(auth):
    r = auth.post("/exercises", json={"name": "Remo en máquina", "muscle_group": "Espalda", "is_compound": True})
    assert r.status_code == 201, r.text
    ex = r.json()
    assert ex["id"].startswith("u:") and ex["mine"] and "a" in ex["figure"] and "b" in ex["figure"]
    bad = auth.post("/exercises", json={"name": "X", "muscle_group": "Y", "default_rep_min": 8})
    assert bad.status_code == 422 and bad.json()["detail"][0]["msg"].startswith("Pon el rango completo")

    mine = {e["id"]: e for e in auth.get("/catalog").json()["exercises"]}
    assert mine[ex["id"]]["mine"] and not mine["press_banca"]["mine"]
    other = _new_user()
    assert ex["id"] not in {e["id"] for e in other.get("/catalog").json()["exercises"]}

    plan = {"name": "Con máquina", "weeks": 1, "days": [{"key": "espalda", "weekday": 2, "name": "Espalda", "slots": [_slot(ex["id"])]}]}
    assert other.post("/programs", json=plan).status_code == 422
    p = auth.post("/programs", json=plan).json()
    auth.post(f"/programs/{p['id']}/activate", json={"started_on": "2026-10-19"})
    body = {"slots": [{"slot_exercise_id": ex["id"], "exercise_id": ex["id"], "sets": [{"load_kg": 50, "reps": 10}]}]}
    assert auth.put("/workouts/2026-10-20/espalda", json=body).status_code == 200
    nxt = auth.get("/workouts/2026-10-27/espalda/plan").json()["slots"][0]
    assert nxt["last"]["date"] == "2026-10-20" and nxt["hint"]["kind"] == "rep"


def test_weeks_in_workouts(auth):
    p = auth.post("/programs", json=_two_weeks()).json()
    auth.post(f"/programs/{p['id']}/activate", json={"started_on": "2026-10-19"})

    t = auth.get("/workouts/2026-10-26/today").json()  # lunes de la semana 2
    assert (t["program_id"], t["weeks"], t["week"], t["day_key"]) == (p["id"], 2, 2, "torsoA")
    assert [d["key"] for d in t["days"]] == ["torsoA", "pierna"]
    sunday = auth.get("/workouts/2026-10-25/today").json()
    assert sunday["week"] == 1 and sunday["day_key"] is None
    assert auth.get("/workouts/2026-11-02/today").json()["week"] == 1

    def press(plan):
        s = next(x for x in plan["slots"] if x["slot_exercise_id"] == "press_banca")
        return s["sets"], s["rep_min"], s["rep_max"]

    plan = auth.get("/workouts/2026-10-26/torsoA/plan").json()
    assert plan["week"] == 2 and press(plan) == (3, 10, 12)
    assert press(auth.get("/workouts/2026-10-26/torsoA/plan", params={"week": 1}).json()) == (4, 5, 6)
    assert auth.get("/workouts/2026-10-26/torsoA/plan", params={"week": 3}).json()["detail"].startswith("Tu plan tiene 2 semanas")
    assert auth.get("/workouts/2026-10-19/pierna/plan").status_code == 404  # pierna solo está en la semana 2

    body = {"slots": [{"slot_exercise_id": "press_banca", "exercise_id": "press_banca", "sets": [{"load_kg": 70, "reps": 10}] * 3}]}
    s = auth.put("/workouts/2026-10-26/torsoA", json=body).json()
    assert (s["program_id"], s["week"]) == (p["id"], 2)
    # Se puede hacer la semana 1 en una fecha de la semana 2; luego el plan de ese día recuerda la semana guardada
    assert auth.put("/workouts/2026-10-27/torsoA", params={"week": 1}, json=body).json()["week"] == 1
    again = auth.get("/workouts/2026-10-27/torsoA/plan").json()
    assert again["saved"] and again["week"] == 1 and press(again) == (4, 5, 6)
    slot = auth.get("/workouts/2026-11-02/torsoA/slots/press_banca").json()
    assert (slot["rep_min"], slot["rep_max"]) == (5, 6) and slot["last"]["date"] == "2026-10-27"
    assert [x["week"] for x in auth.get("/workouts").json()] == [1, 2]
