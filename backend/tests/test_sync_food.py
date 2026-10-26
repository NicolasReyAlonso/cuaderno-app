import uuid

from fastapi.testclient import TestClient

from app.main import app

from .test_sync import _by_key, _op, _pull, _push


def _food(name="Skyr marca X", kcal=63, protein=11):
    return {"name": name, "category": "Mis alimentos", "kcal": kcal, "protein": protein, "carbs": 4, "fat": 0.2, "default_portion_g": 150}


def _other() -> TestClient:
    c = TestClient(app)
    r = c.post("/auth/register", json={"email": f"{uuid.uuid4().hex[:10]}@example.com", "password": "contraseña-larga"})
    c.headers["Authorization"] = f"Bearer {r.json()['access_token']}"
    return c


def test_food_dish_and_diary_created_offline(auth):
    fid, did, iid = "u:" + uuid.uuid4().hex[:12], str(uuid.uuid4()), str(uuid.uuid4())
    dish = {"name": "Bol de skyr", "servings": 2, "cooked_weight_g": None, "ingredients": [
        {"food_id": fid, "name": "Skyr", "grams": 300, "kcal": 1, "protein": 1},  # valores viejos: manda el alimento
        {"food_id": "b:platano", "name": "Plátano", "grams": 120, "kcal": 89, "protein": 1.1},
    ]}
    item = {"date": "2026-10-20", "meal": "desayuno", "name": "Bol de skyr", "food_id": None, "dish_id": did, "grams": 210,
            "kcal": 200.5, "protein": 17.4, "carbs": 25, "fat": 1, "created_at": "2026-10-20T07:30:00+02:00"}
    # En orden, en el mismo envío: el plato usa un alimento creado sin conexión
    res = _push(auth, _op("food", fid, 0, _food()), _op("dish", did, 0, dish), _op("diary_item", iid, 0, item))
    assert [r["status"] for r in res] == ["applied"] * 3, res
    ing = res[1]["server"]["data"]["ingredients"]
    assert (ing[0]["food_id"], ing[0]["kcal"], ing[0]["protein"]) == (fid, 63.0, 11.0)
    assert ing[1]["name"] != "Plátano" or ing[1]["food_id"] == "b:platano"

    # Lo ven los endpoints de siempre
    day = auth.get("/diary/2026-10-20").json()
    assert day["items"][0]["name"] == "Bol de skyr" and day["kcal"] == 200.5
    assert auth.get("/dishes").json()[0]["name"] == "Bol de skyr"
    assert any(f["id"] == fid and f["mine"] for f in auth.get("/foods", params={"q": "skyr marca"}).json())

    # Y el resumen de Peso usa el diario
    row = next(e for e in auth.get("/body/summary").json()["entries"] if e["date"] == "2026-10-20")
    assert row["from_diary"] and row["kcal"] == 200


def test_rest_changes_reach_the_sync(auth):
    cursor = _pull(auth, 0)["cursor"]
    f = auth.post("/foods", json={"name": "Pan de centeno", "kcal": 250, "protein": 9}).json()
    d = auth.post("/dishes", json={"name": "Tostada", "servings": 1, "ingredients": [{"food_id": f["id"], "grams": 60}]}).json()
    i = auth.post("/diary/2026-10-21/items", json={"meal": "desayuno", "dish_id": d["id"], "grams": 60}).json()
    got = _by_key(_pull(auth, cursor)["changes"])
    assert {k[0] for k in got} == {"food", "dish", "diary_item"}
    assert got[("dish", d["id"])]["version"] == 1
    assert got[("diary_item", i["id"])]["data"]["dish_id"] == d["id"]

    # Cambiar solo los ingredientes cuenta como cambio del plato
    cur2 = _pull(auth, cursor)["cursor"]
    auth.put(f"/dishes/{d['id']}", json={"name": "Tostada", "servings": 1, "ingredients": [{"food_id": f["id"], "grams": 80}]})
    after = _by_key(_pull(auth, cur2)["changes"])[("dish", d["id"])]
    assert after["version"] == 2 and after["data"]["ingredients"][0]["grams"] == 80

    auth.delete(f"/diary/items/{i['id']}")
    assert _by_key(_pull(auth, cur2)["changes"])[("diary_item", i["id"])]["deleted"]


def test_dish_keeps_copy_of_deleted_food(auth):
    f = auth.post("/foods", json={"name": "Queso batido", "kcal": 46, "protein": 8}).json()
    auth.delete(f"/foods/{f['id']}")
    did = str(uuid.uuid4())
    dish = {"name": "Con queso", "servings": 1, "ingredients": [{"food_id": f["id"], "name": "Queso batido", "grams": 250, "kcal": 46, "protein": 8}]}
    r = _push(auth, _op("dish", did, 0, dish))[0]
    ing = r["server"]["data"]["ingredients"][0]
    assert r["status"] == "applied" and (ing["food_id"], ing["name"], ing["kcal"]) == (None, "Queso batido", 46.0)


def test_ids_and_other_users(auth):
    other = _other()
    taken = "u:" + uuid.uuid4().hex[:12]
    assert _push(other, _op("food", taken, 0, _food("De otro")))[0]["status"] == "applied"
    res = _push(auth, _op("food", taken, 0, _food()), _op("food", "b:skyr", 0, _food()), _op("dish", "no-uuid", 0, {}))
    assert [r["status"] for r in res] == ["rejected"] * 3
    assert res[0]["detail"].startswith("Ese identificador ya está en uso")
    assert "u:" in res[1]["detail"]
    # Un alimento de otro usuario en el diario no se enlaza (se guarda la copia)
    iid = str(uuid.uuid4())
    item = {"date": "2026-10-22", "meal": "cena", "name": "Algo", "food_id": taken, "grams": 100, "kcal": 100, "protein": 10}
    assert _push(auth, _op("diary_item", iid, 0, item))[0]["server"]["data"]["food_id"] is None
    # Lo de otro no aparece al descargar
    assert taken not in {c["id"] for c in _pull(auth, 0)["changes"]}


def test_diary_same_values_are_not_a_conflict(auth):
    iid = str(uuid.uuid4())
    item = {"date": "2026-10-23", "meal": "cena", "name": "Tortilla", "grams": 150, "kcal": 230, "protein": 15}
    _push(auth, _op("diary_item", iid, 0, item))
    auth.patch("/me", json={"name": "otro cambio"})  # no afecta
    again = _push(auth, _op("diary_item", iid, 0, {**item, "created_at": "2026-10-23T21:00:00+02:00"}))[0]
    assert again["status"] == "applied"  # mismo contenido aunque no sabía la versión


def test_catalog_foods_reference_and_seed(auth):
    r = auth.get("/sync/reference").json()
    assert len(r["foods"]) == 90 and r["unchanged"] is False
    assert auth.get("/sync/reference", params={"known": r["hash"]}).json() == {"hash": r["hash"], "unchanged": True}
    # Los alimentos del catálogo no se descargan por usuario y volver a cargarlos no rompe la sincronización
    from app.db import SessionLocal
    from app.seed import seed

    with SessionLocal() as db:
        seed(db)
    assert not any(c["entity"] == "food" and c["id"].startswith("b:") for c in _pull(auth, 0)["changes"])
