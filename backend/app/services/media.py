"""Fotos, GIF y vídeos de los ejercicios propios: tipo, límites y URL firmadas.

El tipo se decide por los primeros bytes del archivo, no por el nombre ni por la
cabecera que manda el cliente. Las URL llevan una firma temporal (?sig=) porque
el reproductor de vídeo en web no puede mandar la cabecera Authorization.
"""
import time
import uuid
from dataclasses import dataclass
from pathlib import Path

import jwt

from ..config import get_settings

MB = 1024 * 1024
MAX_IMAGE_BYTES = 10 * MB
MAX_VIDEO_BYTES = 50 * MB
MAX_PER_EXERCISE = 6
_WINDOW = 6 * 3600  # la firma no cambia durante esta ventana: la app puede cachear


@dataclass(frozen=True)
class MediaType:
    kind: str  # 'image' | 'video'
    content_type: str
    ext: str


_HEIF_BRANDS = {b"heic", b"heix", b"heim", b"heis", b"hevc", b"hevx", b"mif1", b"msf1", b"avif"}


def sniff(head: bytes) -> MediaType | None:
    """Tipo según la cabecera del archivo; None si no es un formato que la app sepa mostrar."""
    if head.startswith(b"\xff\xd8\xff"):
        return MediaType("image", "image/jpeg", "jpg")
    if head.startswith(b"\x89PNG\r\n\x1a\n"):
        return MediaType("image", "image/png", "png")
    if head[:6] in (b"GIF87a", b"GIF89a"):
        return MediaType("image", "image/gif", "gif")
    if head[:4] == b"RIFF" and head[8:12] == b"WEBP":
        return MediaType("image", "image/webp", "webp")
    if head[4:8] == b"ftyp":
        brand = head[8:12]
        if brand in _HEIF_BRANDS:  # fotos HEIC del iPhone: Android y web no las muestran
            return None
        if brand == b"qt  ":
            return MediaType("video", "video/quicktime", "mov")
        return MediaType("video", "video/mp4", "mp4")
    return None


def max_bytes(kind: str) -> int:
    return MAX_VIDEO_BYTES if kind == "video" else MAX_IMAGE_BYTES


def media_root() -> Path:
    return Path(get_settings().media_dir)


def relative_path(owner_id: uuid.UUID, media_id: uuid.UUID, ext: str) -> str:
    return f"{owner_id}/{media_id}.{ext}"


def signed_url(media_id: uuid.UUID, now: float | None = None) -> str:
    s = get_settings()
    now = time.time() if now is None else now
    exp = (int(now) // _WINDOW + 1) * _WINDOW + s.media_url_hours * 3600
    sig = jwt.encode({"m": str(media_id), "exp": exp}, s.jwt_secret, algorithm=s.jwt_algorithm)
    return f"/media/{media_id}?sig={sig}"


def check_signature(media_id: uuid.UUID, sig: str) -> bool:
    s = get_settings()
    try:
        payload = jwt.decode(sig, s.jwt_secret, algorithms=[s.jwt_algorithm])
    except jwt.PyJWTError:
        return False
    return payload.get("m") == str(media_id)
