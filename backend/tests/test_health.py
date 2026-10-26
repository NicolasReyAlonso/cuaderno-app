import uuid
from datetime import date, timedelta

from fastapi.testclient import TestClient

from app.main import app


def _other() -> TestClient:
    c = TestClient(app)
    r = c.post("/auth/register", json={"email": f"{uuid.uuid4().hex[:10]}@example.com", "password": "contraseña-larga"})
    c.headers["Authorization"] = f"Bearer {r.json()['access_token']}"
    return c


def _run(ext="hc-1", start="2026-10-20T07:00:00+02:00", end="2026-10-20T07:35:00+02:00", **kw):
    return {"external_id": ext, "kind": "RUNNING", "started_at": start, "ended_at": end, "kcal": 320, "distance_m": 5200,
            "source": "Zepp", **kw}


def test_sync_days_and_activities_is_idempotent(auth):
    body = {"days": [
        {"date": "2026-10-20", "steps": 9500, "active_kcal": 480, "sleep_minutes": 412, "resting_hr": 58, "hrv_ms": 41.5},
        {"date": "2026-10-21", "steps": 7200},
    ], "activities": [_run(), _run("hc-2", "2026-10-21T18:00:00Z", "2026-10-21T19:00:00Z", kind="WALKING", distance_m=None)]}
    r = auth.post("/health/sync", json=body)
    assert r.status_code == 200, r.text
    assert r.json() == {"days": 2, "activities_new": 2, "activities_updated": 0, "weights_set": 0, "weights_kept_manual": 0}

    # Repetir no duplica; lo que llega como null no borra lo guardado
    again = auth.post("/health/sync", json={"days": [{"date": "2026-10-20", "steps": 9800}], "activities": [_run(kcal=330)]}).json()
    assert (again["activities_new"], again["activities_updated"]) == (0, 1)
    days = auth.get("/health/days", params={"from": "2026-10-19", "to": "2026-10-22"}).json()
    assert [d["date"] for d in days] == ["2026-10-20", "2026-10-21"]
    assert days[0] | {} == {"date": "2026-10-20", "steps": 9800, "active_kcal": 480, "sleep_minutes": 412, "resting_hr": 58, "hrv_ms": 41.5}

    acts = auth.get("/health/activities", params={"from": "2026-10-20", "to": "2026-10-21"}).json()
    assert [a["kind"] for a in acts] == ["WALKING", "RUNNING"]  # la más reciente primero
    assert acts[1]["kcal"] == 330 and acts[1]["source"] == "Zepp"
    assert _other().get("/health/activities", params={"from": "2026-10-20", "to": "2026-10-21"}).json() == []


def test_scale_weight_never_overwrites_manual(auth):
    auth.put("/body/2026-10-20", json={"weight_kg": 98.1})  # a mano
    r = auth.post("/health/sync", json={"days": [{"date": "2026-10-20", "weight_kg": 97.9},
                                                 {"date": "2026-10-21", "weight_kg": 97.7}]}).json()
    assert (r["weights_set"], r["weights_kept_manual"]) == (1, 1)
    entries = {e["date"]: e for e in auth.get("/body/summary").json()["entries"]}
    assert (entries["2026-10-20"]["weight_kg"], entries["2026-10-20"]["weight_from_health"]) == (98.1, False)
    assert (entries["2026-10-21"]["weight_kg"], entries["2026-10-21"]["weight_from_health"]) == (97.7, True)

    # Un peso de la báscula se actualiza en la siguiente sincronización…
    auth.post("/health/sync", json={"days": [{"date": "2026-10-21", "weight_kg": 97.6}]})
    assert {e["date"]: e for e in auth.get("/body/summary").json()["entries"]}["2026-10-21"]["weight_kg"] == 97.6
    # …hasta que lo corriges a mano
    auth.put("/body/2026-10-21", json={"weight_kg": 97.5})
    assert auth.post("/health/sync", json={"days": [{"date": "2026-10-21", "weight_kg": 97.0}]}).json()["weights_kept_manual"] == 1
    row = {e["date"]: e for e in auth.get("/body/summary").json()["entries"]}["2026-10-21"]
    assert (row["weight_kg"], row["weight_from_health"]) == (97.5, False)


def test_weekly_summary_averages_wristband_data(auth):
    auth.post("/health/sync", json={"days": [
        {"date": "2026-10-19", "steps": 8000, "active_kcal": 400, "sleep_minutes": 420, "resting_hr": 60},
        {"date": "2026-10-20", "steps": 10000, "sleep_minutes": 360},
        {"date": "2026-10-26", "steps": 12000},
    ]})
    auth.put("/body/2026-10-20", json={"weight_kg": 98})
    weeks = {w["monday"]: w for w in auth.get("/body/summary").json()["weeks"]}
    w1 = weeks["2026-10-19"]
    assert (w1["avg_steps"], w1["avg_active_kcal"], w1["avg_sleep_minutes"], w1["avg_resting_hr"]) == (9000, 400, 390, 60)
    assert w1["avg_weight"] == 98
    assert weeks["2026-10-26"]["avg_steps"] == 12000 and weeks["2026-10-26"]["avg_weight"] is None
    # Un día solo con datos de la pulsera no aparece en los registros de peso
    assert "2026-10-19" not in {e["date"] for e in auth.get("/body/summary").json()["entries"]}


def test_sync_validation(auth):
    def detail(body):
        r = auth.post("/health/sync", json=body)
        assert r.status_code == 422, r.text
        d = r.json()["detail"]
        return d if isinstance(d, str) else d[0]["msg"]

    future = (date.today() + timedelta(days=3)).isoformat()
    assert detail({"days": [{"date": future, "steps": 1}]}).startswith("Hay datos con fecha futura")
    assert detail({"days": [{"date": "2026-10-20"}, {"date": "2026-10-20"}]}) == "Hay dos resúmenes del mismo día."
    backwards = _run(start="2026-10-20T08:00:00Z", end="2026-10-20T07:00:00Z")
    assert detail({"activities": [backwards]}).startswith("Una actividad termina antes de empezar")
    assert detail({"activities": [_run(start="2026-10-20T07:00:00")]})  # sin zona horaria: no se sabe qué hora es
    assert detail({"days": [{"date": "2026-10-20", "resting_hr": 5}]})


def test_forget_health_data_keeps_manual(auth):
    auth.put("/body/2026-10-20", json={"weight_kg": 98.1})
    auth.put("/body/2026-10-22", json={"waist_cm": 104})
    auth.post("/health/sync", json={"days": [{"date": "2026-10-21", "steps": 5000, "weight_kg": 97.7},
                                             {"date": "2026-10-22", "weight_kg": 97.5}], "activities": [_run()]})
    assert auth.delete("/health").status_code == 204
    assert auth.get("/health/days", params={"from": "2026-10-01", "to": "2026-10-31"}).json() == []
    assert auth.get("/health/activities", params={"from": "2026-10-01", "to": "2026-10-31"}).json() == []
    entries = {e["date"]: e for e in auth.get("/body/summary").json()["entries"]}
    assert entries["2026-10-20"]["weight_kg"] == 98.1  # el manual se queda
    assert "2026-10-21" not in entries  # solo tenía el peso de la báscula
    assert (entries["2026-10-22"]["weight_kg"], entries["2026-10-22"]["waist_cm"]) == (None, 104)
