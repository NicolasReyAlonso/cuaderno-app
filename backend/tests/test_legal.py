from app.config import get_settings


def test_privacy_policy_is_public_html(client):
    r = client.get("/privacidad")  # sin token: Google Play y Health Connect abren la URL sin sesión
    assert r.status_code == 200
    assert r.headers["content-type"].startswith("text/html")
    assert "Política de privacidad" in r.text
    assert "Borrar cuenta" in r.text  # lo que dice que hace la app es lo que hace
    assert "{{" not in r.text


def test_privacy_policy_contact(client, monkeypatch):
    monkeypatch.setattr(get_settings(), "contact_email", "")
    assert "mailto:" not in client.get("/privacidad").text

    monkeypatch.setattr(get_settings(), "contact_email", 'yo@example.com"><script>')
    page = client.get("/privacidad").text
    assert "<script>" not in page
    monkeypatch.setattr(get_settings(), "contact_email", "yo@example.com")
    assert 'href="mailto:yo@example.com"' in client.get("/privacidad").text
