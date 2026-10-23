import uuid

import pytest
from fastapi.testclient import TestClient

from app.config import get_settings
from app.main import app
from app.services import media as m

PNG = b"\x89PNG\r\n\x1a\n" + b"\0" * 64
GIF = b"GIF89a" + b"\0" * 64
MP4 = b"\0\0\0\x18ftypisom" + b"\0" * 64
MOV = b"\0\0\0\x14ftypqt  " + b"\0" * 64
HEIC = b"\0\0\0\x18ftypheic" + b"\0" * 64


@pytest.fixture(autouse=True)
def media_dir(tmp_path, monkeypatch):
    monkeypatch.setattr(get_settings(), "media_dir", str(tmp_path))
    return tmp_path


def _exercise(client) -> str:
    return client.post("/exercises", json={"name": "Remo en máquina", "muscle_group": "Espalda"}).json()["id"]


def _upload(client, ex_id, data, name="archivo", ctype="application/octet-stream"):
    return client.post(f"/exercises/{ex_id}/media", files={"file": (name, data, ctype)})


def test_sniff():
    assert m.sniff(PNG).content_type == "image/png"
    assert m.sniff(GIF).content_type == "image/gif"
    assert m.sniff(b"\xff\xd8\xff\xe0" + b"\0" * 8).ext == "jpg"
    assert m.sniff(b"RIFF\0\0\0\0WEBPVP8 ").content_type == "image/webp"
    assert (m.sniff(MP4).kind, m.sniff(MP4).ext) == ("video", "mp4")
    assert m.sniff(MOV).content_type == "video/quicktime"
    assert m.sniff(HEIC) is None and m.sniff(b"hola, soy un texto") is None


def test_signed_url_is_stable_and_expires():
    mid = uuid.uuid4()
    start = 1_800_000_000 // (6 * 3600) * (6 * 3600)
    assert m.signed_url(mid, now=start) == m.signed_url(mid, now=start + 3600)  # cacheable unas horas
    old = m.signed_url(mid, now=0).split("sig=")[1]
    assert not m.check_signature(mid, old)
    fresh = m.signed_url(mid).split("sig=")[1]
    assert m.check_signature(mid, fresh) and not m.check_signature(uuid.uuid4(), fresh)


def test_upload_view_delete(auth, media_dir):
    ex = _exercise(auth)
    r = _upload(auth, ex, PNG, "foto.png", "image/png")
    assert r.status_code == 201, r.text
    photo = r.json()
    assert (photo["kind"], photo["content_type"], photo["size_bytes"]) == ("image", "image/png", len(PNG))
    assert [x["kind"] for x in (_upload(auth, ex, MP4).json(), _upload(auth, ex, MOV).json(), _upload(auth, ex, GIF).json())] == \
        ["video", "video", "image"]

    # La URL firmada funciona sin token, y admite Range (el iPhone lo necesita para los vídeos)
    anon = TestClient(app)
    got = anon.get(photo["url"])
    assert got.status_code == 200 and got.content == PNG and got.headers["content-type"] == "image/png"
    part = anon.get(photo["url"], headers={"Range": "bytes=0-3"})
    assert part.status_code == 206 and part.content == PNG[:4]
    assert anon.get(f"/media/{photo['id']}", params={"sig": "basura"}).status_code == 403
    assert anon.get(f"/media/{photo['id']}").status_code == 422

    mine = next(e for e in auth.get("/catalog").json()["exercises"] if e["id"] == ex)
    assert [x["id"] for x in mine["media"]][0] == photo["id"] and len(mine["media"]) == 4

    assert auth.delete(f"/media/{photo['id']}").status_code == 204
    assert anon.get(photo["url"]).status_code == 404
    assert len(list(media_dir.rglob("*.*"))) == 3


def test_upload_rejections(auth, monkeypatch):
    ex = _exercise(auth)
    fake = _upload(auth, ex, b"esto es texto", "foto.jpg", "image/jpeg")
    assert fake.status_code == 415 and fake.json()["detail"].startswith("Ese archivo no es una foto")
    assert _upload(auth, ex, HEIC, "IMG_0001.HEIC").status_code == 415
    assert auth.post(f"/exercises/{ex}/media", data={"otro": "campo"}).status_code == 422
    assert _upload(auth, "press_banca", PNG).json()["detail"] == "Solo puedes añadir fotos o vídeos a tus ejercicios propios."

    other = TestClient(app)
    tok = other.post("/auth/register", json={"email": f"{uuid.uuid4().hex[:10]}@example.com", "password": "contraseña-larga"})
    other.headers["Authorization"] = f"Bearer {tok.json()['access_token']}"
    assert _upload(other, ex, PNG).status_code == 404
    mine = _upload(auth, ex, PNG).json()
    assert other.delete(f"/media/{mine['id']}").status_code == 404

    monkeypatch.setattr(m, "MAX_IMAGE_BYTES", 10)
    big = _upload(auth, ex, PNG)
    assert big.status_code == 413 and big.json()["detail"].startswith("La foto pasa de")
    monkeypatch.setattr(m, "MAX_IMAGE_BYTES", 10 * m.MB)
    monkeypatch.setattr(m, "MAX_PER_EXERCISE", 2)
    assert _upload(auth, ex, GIF).status_code == 201
    assert _upload(auth, ex, GIF).json()["detail"] == "Ya tiene 2 fotos o vídeos. Borra alguno para añadir otro."
