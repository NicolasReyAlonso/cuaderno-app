import json
from pathlib import Path

from app.services.progression import SetResult, suggest

EXPORT = Path(__file__).resolve().parents[2] / "datos" / "cuaderno_export.json"


def test_register_login_me(client):
    r = client.post("/auth/register", json={"email": "Login@Example.com", "password": "contraseña-larga"})
    assert r.status_code == 201
    assert client.post("/auth/register", json={"email": "login@example.com", "password": "contraseña-larga"}).status_code == 409
    bad = client.post("/auth/login", data={"username": "login@example.com", "password": "otra-cosa-123"})
    assert bad.status_code == 401
    tok = client.post("/auth/login", data={"username": "login@example.com", "password": "contraseña-larga"}).json()["access_token"]
    me = client.get("/me", headers={"Authorization": f"Bearer {tok}"}).json()
    assert me["email"] == "login@example.com" and me["program_id"] == "definicion-5d"


def test_requires_auth(client):
    assert client.get("/catalog").status_code == 401
    assert client.get("/catalog", headers={"Authorization": "Bearer basura"}).status_code == 401


def test_catalog(auth):
    c = auth.get("/catalog").json()
    ids = {e["id"] for e in c["exercises"]}
    assert len(c["program"]["days"]) == 5
    torso = c["program"]["days"][0]
    assert torso["key"] == "torsoA" and torso["slots"][0]["exercise_id"] == "dominadas"
    assert "dominadas_negativas" in torso["slots"][0]["alternatives"]
    for d in c["program"]["days"]:
        for s in d["slots"]:
            assert s["exercise_id"] in ids and set(s["alternatives"]) <= ids
    assert all("a" in e["figure"] and "b" in e["figure"] for e in c["exercises"])


def test_progression_rules():
    full = [SetResult(80, 8)] * 4
    assert suggest(sets_planned=4, rep_min=6, rep_max=8, unit="reps", load_mode="kg", is_compound=True, last=full).text == "Sube 2,5 kg"
    assert suggest(sets_planned=3, rep_min=10, rep_max=12, unit="reps", load_mode="kg", is_compound=False,
                   last=[SetResult(77, 12)] * 3).text == "Sube 1–2 kg"
    assert suggest(sets_planned=4, rep_min=6, rep_max=10, unit="reps", load_mode="extra", is_compound=True,
                   last=[SetResult(0, 10)] * 4).text == "Añade 2,5 kg de lastre"
    assert suggest(sets_planned=4, rep_min=6, rep_max=8, unit="reps", load_mode="kg", is_compound=True,
                   last=[SetResult(80, 8), SetResult(80, 5)]).kind == "hold"
    assert suggest(sets_planned=4, rep_min=6, rep_max=8, unit="reps", load_mode="kg", is_compound=True,
                   last=[SetResult(80, 7)] * 4).kind == "rep"
    assert suggest(sets_planned=3, rep_min=40, rep_max=60, unit="seconds", load_mode="extra", is_compound=False,
                   last=[SetResult(None, 60)] * 3).text == "Añade 10 s o lastre"
    assert suggest(sets_planned=3, rep_min=8, rep_max=10, unit="reps", load_mode="kg", is_compound=False, last=None).kind == "new"


def test_session_with_swap_and_plan(auth):
    body = {"slots": [
        {"slot_exercise_id": "sentadilla_smith", "exercise_id": "sentadilla_smith", "sets": [{"load_kg": 60, "reps": 10}] * 4},
        {"slot_exercise_id": "crunch_polea", "exercise_id": "crunch", "sets": [{"load_kg": 0, "reps": 15}] * 3 + [{}]},
    ]}
    r = auth.put("/workouts/2026-10-20/piernaA", json=body)
    assert r.status_code == 200, r.text
    crunch = next(s for s in r.json()["slots"] if s["slot_exercise_id"] == "crunch_polea")
    assert crunch["exercise_id"] == "crunch" and len(crunch["sets"]) == 3

    # La semana siguiente propone la misma alternativa y sugiere progresar
    plan = auth.get("/workouts/2026-10-27/piernaA/plan").json()
    assert plan["saved"] is False
    by_slot = {s["slot_exercise_id"]: s for s in plan["slots"]}
    assert by_slot["crunch_polea"]["exercise_id"] == "crunch"
    assert by_slot["crunch_polea"]["last"]["date"] == "2026-10-20"
    assert by_slot["crunch_polea"]["hint"]["kind"] == "up"  # 3×15 en rango 12–15 → lastre
    assert by_slot["sentadilla_smith"]["hint"]["text"] == "Sube 2,5 kg"
    assert by_slot["haka"]["hint"]["kind"] == "new"

    # Al cambiar de alternativa se pide el hueco con el nuevo ejercicio
    sl = auth.get("/workouts/2026-10-27/piernaA/slots/crunch_polea", params={"exercise_id": "elevacion_piernas"}).json()
    assert sl["exercise_id"] == "elevacion_piernas" and sl["hint"]["kind"] == "new" and sl["last"] is None
    # Rueda (repeticiones) → plancha (segundos) usa el rango propio de la plancha
    pl = auth.get("/workouts/2026-10-31/piernaB/slots/rueda", params={"exercise_id": "plancha"}).json()
    assert (pl["rep_min"], pl["rep_max"]) == (40, 60)
    assert auth.get("/workouts/2026-10-27/piernaA/slots/crunch_polea", params={"exercise_id": "press_banca"}).status_code == 422

    # El plan del mismo día devuelve lo guardado
    same = auth.get("/workouts/2026-10-20/piernaA/plan").json()
    assert same["saved"] and len({s["slot_exercise_id"]: s for s in same["slots"]}["sentadilla_smith"]["logged"]) == 4


def test_session_validation(auth):
    bad_alt = {"slots": [{"slot_exercise_id": "press_banca", "exercise_id": "crunch", "sets": [{"load_kg": 1, "reps": 1}]}]}
    assert auth.put("/workouts/2026-10-19/torsoA", json=bad_alt).status_code == 422
    wrong_day = {"slots": [{"slot_exercise_id": "haka", "exercise_id": "haka", "sets": [{"load_kg": 1, "reps": 1}]}]}
    assert auth.put("/workouts/2026-10-19/torsoA", json=wrong_day).status_code == 422
    empty = {"slots": [{"slot_exercise_id": "press_banca", "exercise_id": "press_banca", "sets": [{}]}]}
    assert auth.put("/workouts/2026-10-19/torsoA", json=empty).status_code == 422
    assert auth.get("/workouts/2026-10-19/nada/plan").status_code == 404


def test_nutrition_flow(auth):
    mine = auth.post("/foods", json={"name": "Skyr natural marca X", "kcal": 63, "protein": 11, "default_portion_g": 150}).json()
    found = auth.get("/foods", params={"q": "skyr"}).json()
    assert found[0]["id"] == mine["id"] and found[0]["mine"] is True
    assert any(f["id"] == "b:skyr" for f in found)

    dish = auth.post("/dishes", json={"name": "Arroz marisco", "servings": 3, "cooked_weight_g": 1200, "ingredients": [
        {"food_id": "b:arroz_crudo", "grams": 300}, {"food_id": "b:gambas", "grams": 300}]}).json()
    assert dish["total_kcal"] == 1377.0 and dish["serving_g"] == 400
    assert abs(dish["per100_kcal"] - 114.8) < 0.1

    a = auth.post("/diary/2026-10-20/items", json={"meal": "almuerzo", "dish_id": dish["id"], "grams": 407})
    b = auth.post("/diary/2026-10-20/items", json={"meal": "desayuno", "food_id": "b:platano", "grams": 120})
    assert a.status_code == 201 and b.status_code == 201
    day = auth.get("/diary/2026-10-20").json()
    assert round(day["kcal"]) == round(467.2 + 106.8)
    assert auth.post("/diary/2026-10-20/items", json={"meal": "cena", "grams": 10}).status_code == 422

    # El diario manda sobre las kcal manuales en el resumen
    auth.put("/body/2026-10-20", json={"weight_kg": 98.1, "kcal": 9999})
    s = auth.get("/body/summary").json()
    row = next(e for e in s["entries"] if e["date"] == "2026-10-20")
    assert row["from_diary"] and row["kcal"] == round(day["kcal"])


def test_body_summary(auth):
    auth.patch("/me", json={"start_date": "2026-10-19", "start_weight_kg": 99, "start_body_fat_pct": 30.7})
    for d, w in [("2026-10-20", 98.1), ("2026-10-21", 97.7), ("2026-10-22", 98.2), ("2026-10-27", 97.4), ("2026-10-28", 97.2)]:
        assert auth.put(f"/body/{d}", json={"weight_kg": w}).status_code == 200
    s = auth.get("/body/summary").json()
    assert s["lean_mass"] == 68.6 and s["goal_25_weight"] == 91.5 and s["goal_20_weight"] == 85.8
    assert s["current_weight"] == 97.6  # media 7 días: 98,2 · 97,4 · 97,2
    w2 = s["weeks"][1]
    assert w2["pace"] == "on_track" and w2["delta_kg"] < 0


def test_import_export(auth):
    payload = json.loads(EXPORT.read_text(encoding="utf-8"))
    payload["inicio"] = {"fecha": "2026-10-19", "peso": 99, "grasa": 30.7}
    r1 = auth.post("/import/cuaderno", json=payload).json()
    assert r1["sessions"] == len(payload["sesiones"]) and r1["skipped"] == []
    r2 = auth.post("/import/cuaderno", json=payload).json()  # idempotente
    assert r2["sets"] == r1["sets"]
    sessions = auth.get("/workouts").json()
    assert len(sessions) == len(payload["sesiones"])
    legs = next(s for s in sessions if s["day_key"] == "piernaA")
    crunch = next(s for s in legs["slots"] if s["exercise_id"] == "crunch")
    assert crunch["slot_exercise_id"] == "crunch_polea"
    items = auth.get("/diary/2026-10-20").json()["items"]
    assert len(items) == len(payload["diario"]["2026-10-20"]["items"])
    assert auth.get("/me").json()["start_weight_kg"] == 99
    assert auth.post("/import/cuaderno", json={"formato": "otro"}).status_code == 422
