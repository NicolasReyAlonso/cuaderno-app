import uuid

from fastapi.testclient import TestClient

from app.main import app


def _op(entity, id_, base, data=None, delete=False, op_id=None):
    return {"op_id": op_id or str(uuid.uuid4()), "entity": entity, "id": id_, "base_version": base, "data": data, "delete": delete}


def _push(client, *changes):
    r = client.post("/sync/push", json={"changes": list(changes)})
    assert r.status_code == 200, r.text
    return r.json()["results"]


def _pull(client, since):
    r = client.get("/sync/pull", params={"since": since})
    assert r.status_code == 200, r.text
    return r.json()


def _by_key(changes):
    return {(c["entity"], c["id"]): c for c in changes}


def _body(w=None, waist=None, kcal=None, prot=None):
    return {"weight_kg": w, "waist_cm": waist, "kcal": kcal, "protein_g": prot}


def test_first_pull_is_a_snapshot_then_only_changes(auth):
    first = _pull(auth, 0)
    me = _by_key(first["changes"])[("profile", "me")]
    assert me["version"] == 1 and me["data"]["kcal_target"] == 2000 and first["more"] is False
    assert first["cursor"] > 0  # crear la cuenta queda anotado: si no, cada descarga sería completa

    # Lo que entra por los endpoints de siempre también llega a la sincronización
    auth.put("/body/2026-10-20", json={"weight_kg": 98.1})
    auth.patch("/me", json={"kcal_target": 2100})
    nxt = _pull(auth, first["cursor"])
    got = _by_key(nxt["changes"])
    assert got[("body_entry", "2026-10-20")]["data"]["weight_kg"] == 98.1
    assert got[("profile", "me")]["version"] == 2 and got[("profile", "me")]["data"]["kcal_target"] == 2100
    assert _pull(auth, nxt["cursor"])["changes"] == []  # nada nuevo
    # Asignar los mismos valores no cuenta como cambio
    auth.patch("/me", json={"kcal_target": 2100})
    assert _pull(auth, nxt["cursor"])["changes"] == []


def test_push_applies_once_and_detects_conflicts(auth):
    op = _op("body_entry", "2026-10-21", 0, _body(97.7, 104))
    r = _push(auth, op)[0]
    assert (r["status"], r["version"]) == ("applied", 1)
    assert r["server"]["data"] == {"date": "2026-10-21", "weight_kg": 97.7, "waist_cm": 104.0, "kcal": None, "protein_g": None,
                                   "weight_source": "manual"}
    # Reenviar el mismo cambio (se cortó la red) no lo aplica dos veces
    assert _push(auth, op)[0] == r

    # Otro dispositivo lo cambia (versión 2) mientras este seguía en la 1
    auth.put("/body/2026-10-21", json={"weight_kg": 97.5})
    c = _push(auth, _op("body_entry", "2026-10-21", 1, _body(97.6, 104)))[0]
    assert c["status"] == "conflict" and c["server"]["version"] == 2 and c["server"]["data"]["weight_kg"] == 97.5
    # Si lo que manda la app ya es lo que hay, no hay nada que elegir
    same = _push(auth, _op("body_entry", "2026-10-21", 1, _body(97.5, 104)))[0]
    assert (same["status"], same["version"]) == ("applied", 2)
    # El usuario elige «lo mío»: se reenvía sobre la versión del servidor
    mine = _push(auth, _op("body_entry", "2026-10-21", 2, _body(97.6, 104)))[0]
    assert (mine["status"], mine["version"]) == ("applied", 3)


def test_delete_tombstone_and_recreate(auth):
    _push(auth, _op("body_entry", "2026-10-22", 0, _body(97.2)))
    cursor = _pull(auth, 0)["cursor"]
    d = _push(auth, _op("body_entry", "2026-10-22", 1, delete=True))[0]
    assert (d["status"], d["version"], d["server"]["deleted"]) == ("applied", 2, True)
    tomb = _by_key(_pull(auth, cursor)["changes"])[("body_entry", "2026-10-22")]
    assert (tomb["deleted"], tomb["version"], tomb["data"]) == (True, 2, None)
    # Borrar lo ya borrado no es un error
    assert _push(auth, _op("body_entry", "2026-10-22", 1, delete=True))[0]["status"] == "applied"

    # Editar algo que otro dispositivo borró: conflicto (borrado contra cambio)
    gone = _push(auth, _op("body_entry", "2026-10-22", 1, _body(97.0)))[0]
    assert gone["status"] == "conflict" and gone["server"]["deleted"]
    # Crear de cero ese día (la app no lo conocía) sí vale, y sigue la numeración
    again = _push(auth, _op("body_entry", "2026-10-22", 0, _body(97.0)))[0]
    assert (again["status"], again["version"]) == ("applied", 3)


def test_rejections(auth):
    res = _push(
        auth,
        _op("body_entry", "2026-10-23", 0, _body(10)),
        _op("body_entry", "no-es-fecha", 0, _body(97)),
        _op("health_day", "2026-10-23", 0, {"steps": 1}),
        _op("nada", "x", 0, {}),
        _op("profile", "me", 1, {"kcal_target": 2000, "protein_target_g": 160, "program_id": "no-existe"}),
        _op("profile", "me", 1, delete=True),
    )
    assert [r["status"] for r in res] == ["rejected"] * 6
    assert res[0]["detail"].startswith("Revisa «weight_kg»")
    assert res[1]["detail"] == "«no-es-fecha» no es una fecha (AAAA-MM-DD)."
    assert "salud" in res[2]["detail"] and "no se sincroniza" in res[3]["detail"]
    assert res[4]["detail"].startswith("Ese plan no existe")
    # Un rechazo no deshace los demás cambios del mismo envío
    ok = _push(auth, _op("body_entry", "2026-10-23", 0, _body(10)), _op("body_entry", "2026-10-24", 0, _body(96.9)))
    assert [r["status"] for r in ok] == ["rejected", "applied"]


def test_profile_and_isolation(auth):
    p = _push(auth, _op("profile", "me", 1, {"name": "Nico", "start_date": "2026-10-19", "start_weight_kg": 99, "start_body_fat_pct": 30.7,
                                             "kcal_target": 2050, "protein_target_g": 170, "program_id": "definicion-5d",
                                             "program_started_on": "2026-10-19"}))[0]
    assert p["status"] == "applied" and p["version"] == 2
    assert auth.get("/me").json()["kcal_target"] == 2050

    other = TestClient(app)
    tok = other.post("/auth/register", json={"email": f"{uuid.uuid4().hex[:10]}@example.com", "password": "contraseña-larga"})
    other.headers["Authorization"] = f"Bearer {tok.json()['access_token']}"
    _push(auth, _op("body_entry", "2026-10-25", 0, _body(96.8)))
    seen = _pull(other, 0)["changes"]
    assert [c["entity"] for c in seen] == ["profile"] and seen[0]["data"]["kcal_target"] == 2000
    # El mismo op_id de otro usuario es otra operación
    op_id = str(uuid.uuid4())
    _push(auth, _op("body_entry", "2026-10-26", 0, _body(96.7), op_id=op_id))
    assert _push(other, _op("body_entry", "2026-10-26", 0, _body(80), op_id=op_id))[0]["server"]["data"]["weight_kg"] == 80


def test_health_data_and_paging(auth):
    cursor = _pull(auth, 0)["cursor"]
    auth.post("/health/sync", json={"days": [{"date": "2026-10-20", "steps": 9000, "weight_kg": 97.9}], "activities": [
        {"external_id": "hc-9", "kind": "WALKING", "started_at": "2026-10-20T10:00:00Z", "ended_at": "2026-10-20T10:40:00Z"}]})
    page = auth.get("/sync/pull", params={"since": cursor, "limit": 2}).json()
    assert page["more"] is True and len(page["changes"]) == 2
    rest = _pull(auth, page["cursor"])
    kinds = {c["entity"] for c in page["changes"] + rest["changes"]}
    assert kinds == {"health_day", "body_entry", "activity"}
    weight = next(c for c in page["changes"] + rest["changes"] if c["entity"] == "body_entry")
    assert weight["data"]["weight_source"] == "health"

    # Desconectar la pulsera borra: llegan como borrados
    auth.delete("/health")
    gone = _pull(auth, rest["cursor"])["changes"]
    assert {c["entity"] for c in gone} == {"health_day", "activity", "body_entry"} and all(c["deleted"] for c in gone)


def test_bulk_writes_on_synced_tables_fail():
    import pytest
    from sqlalchemy import delete, update

    from app.db import SessionLocal
    from app.models import BodyEntry

    with SessionLocal() as db:
        for stmt in (delete(BodyEntry), update(BodyEntry).values(kcal=1)):
            with pytest.raises(RuntimeError, match="registro a registro"):
                db.execute(stmt)
