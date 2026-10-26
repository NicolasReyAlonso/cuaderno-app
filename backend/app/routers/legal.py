from functools import lru_cache
from html import escape
from pathlib import Path

from fastapi import APIRouter
from fastapi.responses import HTMLResponse

from ..config import get_settings

router = APIRouter(tags=["sistema"])

_PAGE = Path(__file__).parent.parent / "data" / "privacidad.html"


@lru_cache
def _template() -> str:
    return _PAGE.read_text(encoding="utf-8")


@router.get("/privacidad", response_class=HTMLResponse)
def privacy_policy():
    """Política de privacidad: es la URL pública que pide Google Play."""
    email = get_settings().contact_email.strip()
    contact = f'<a href="mailto:{escape(email, quote=True)}">{escape(email)}</a>' if email else "escribe a quien te dio acceso a la app."
    return HTMLResponse(_template().replace("{{contacto}}", contact))
