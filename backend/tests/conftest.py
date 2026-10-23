import os

os.environ.setdefault("CUADERNO_DATABASE_URL", "postgresql+psycopg://postgres@localhost:5432/cuaderno_test")
os.environ["CUADERNO_SEED_ON_STARTUP"] = "false"

import pytest  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402

from app.db import Base, SessionLocal, engine  # noqa: E402
from app.main import app  # noqa: E402
from app.seed import seed  # noqa: E402


@pytest.fixture(scope="session", autouse=True)
def database():
    Base.metadata.drop_all(engine)
    Base.metadata.create_all(engine)
    with SessionLocal() as db:
        seed(db)
    yield
    Base.metadata.drop_all(engine)


@pytest.fixture
def client():
    return TestClient(app)


_counter = 0


@pytest.fixture
def auth(client):
    """Cliente con un usuario nuevo y su cabecera de autorización."""
    global _counter
    _counter += 1
    r = client.post("/auth/register", json={"email": f"nico{_counter}@example.com", "password": "contraseña-larga", "name": "Nico"})
    assert r.status_code == 201, r.text
    client.headers["Authorization"] = f"Bearer {r.json()['access_token']}"
    return client
