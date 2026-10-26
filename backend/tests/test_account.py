import pytest
from sqlalchemy import func, select

from app.config import get_settings
from app.db import SessionLocal
from app.models import BodyEntry, Exercise, ExerciseMedia, User

PNG = b"\x89PNG\r\n\x1a\n" + b"\0" * 64
PASSWORD = "contraseña-larga"


@pytest.fixture(autouse=True)
def media_dir(tmp_path, monkeypatch):
    monkeypatch.setattr(get_settings(), "media_dir", str(tmp_path))
    return tmp_path


def _delete(client, password):
    return client.request("DELETE", "/me", json={"password": password})


def test_wrong_password_keeps_the_account(auth):
    r = _delete(auth, "otra-contraseña")
    assert r.status_code == 403
    assert "contraseña" in r.json()["detail"]
    assert auth.get("/me").status_code == 200


def test_delete_requires_a_token(client):
    assert _delete(client, PASSWORD).status_code == 401


def test_delete_account_removes_data_and_files(auth, client, media_dir):
    me = auth.get("/me").json()
    ex = auth.post("/exercises", json={"name": "Remo en máquina", "muscle_group": "Espalda"}).json()["id"]
    up = auth.post(f"/exercises/{ex}/media", files={"file": ("foto.png", PNG, "image/png")})
    assert up.status_code == 201, up.text
    assert auth.put("/body/2026-10-20", json={"weight_kg": 80}).status_code == 200
    assert (media_dir / me["id"]).is_dir()

    # Otra cuenta con su propia foto: no se toca
    other = client.post("/auth/register", json={"email": "otra@example.com", "password": PASSWORD, "name": "Otra"}).json()
    other_headers = {"Authorization": f"Bearer {other['access_token']}"}
    other_id = client.get("/me", headers=other_headers).json()["id"]
    other_ex = client.post("/exercises", headers=other_headers, json={"name": "Press", "muscle_group": "Pecho"}).json()["id"]
    client.post(f"/exercises/{other_ex}/media", headers=other_headers, files={"file": ("f.png", PNG, "image/png")})

    assert _delete(auth, PASSWORD).status_code == 204

    assert auth.get("/me").status_code == 401  # el token ya no vale
    login = client.post("/auth/login", data={"username": me["email"], "password": PASSWORD})
    assert login.status_code == 401
    assert not (media_dir / me["id"]).exists()
    assert (media_dir / other_id).is_dir()
    with SessionLocal() as db:
        assert db.get(User, me["id"]) is None
        assert db.get(Exercise, ex) is None
        assert db.scalar(select(func.count()).select_from(ExerciseMedia).where(ExerciseMedia.owner_id == me["id"])) == 0
        assert db.scalar(select(func.count()).select_from(BodyEntry).where(BodyEntry.user_id == me["id"])) == 0
        assert db.get(Exercise, other_ex) is not None
