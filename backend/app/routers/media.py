import uuid

from fastapi import APIRouter, HTTPException, Request, Response, status
from fastapi.concurrency import run_in_threadpool
from fastapi.responses import FileResponse
from sqlalchemy import func, select
from sqlalchemy.orm import Session
from starlette.datastructures import UploadFile

from ..models import Exercise, ExerciseMedia, User
from ..schemas import MediaOut
from ..security import DB, CurrentUser
from ..services import media as m
from .catalog import media_out

router = APIRouter(tags=["fotos y vídeos"])

_UPLOAD_DOC = {"requestBody": {"required": True, "content": {"multipart/form-data": {"schema": {
    "type": "object", "required": ["file"], "properties": {"file": {"type": "string", "format": "binary"}}}}}}}


def _own_exercise(db: Session, user: User, exercise_id: str) -> Exercise:
    ex = db.get(Exercise, exercise_id)
    if ex is None or ex.owner_id not in (None, user.id):
        raise HTTPException(404, "Ejercicio no encontrado.")
    if ex.owner_id is None:
        raise HTTPException(403, "Solo puedes añadir fotos o vídeos a tus ejercicios propios.")
    return ex


def _too_big(kind: str) -> HTTPException:
    if kind == "video":
        return HTTPException(413, f"El vídeo pasa de {m.MAX_VIDEO_BYTES // m.MB} MB. Recórtalo o grábalo con menos calidad.")
    return HTTPException(413, f"La foto pasa de {m.MAX_IMAGE_BYTES // m.MB} MB. Prueba con una más pequeña.")


def _store(db: Session, user: User, exercise_id: str, data: bytes) -> MediaOut:
    ex = _own_exercise(db, user, exercise_id)
    mt = m.sniff(data[:32])
    if mt is None:
        raise HTTPException(415, "Ese archivo no es una foto, un GIF o un vídeo que la app sepa mostrar. "
                                 "Usa JPG, PNG, GIF, WebP, MP4 o MOV.")
    if len(data) > m.max_bytes(mt.kind):
        raise _too_big(mt.kind)
    count = db.scalar(select(func.count()).where(ExerciseMedia.exercise_id == ex.id))
    if count >= m.MAX_PER_EXERCISE:
        raise HTTPException(409, f"Ya tiene {m.MAX_PER_EXERCISE} fotos o vídeos. Borra alguno para añadir otro.")

    media_id = uuid.uuid4()
    rel = m.relative_path(user.id, media_id, mt.ext)
    path = m.media_root() / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)
    row = ExerciseMedia(id=media_id, exercise_id=ex.id, owner_id=user.id, position=count, kind=mt.kind,
                        content_type=mt.content_type, size_bytes=len(data), path=rel)
    db.add(row)
    try:
        db.commit()
    except Exception:
        path.unlink(missing_ok=True)
        raise
    return media_out(row)


@router.post("/exercises/{exercise_id}/media", response_model=MediaOut, status_code=status.HTTP_201_CREATED,
             openapi_extra=_UPLOAD_DOC)
async def upload_media(exercise_id: str, request: Request, user: CurrentUser, db: DB):
    """Sube una foto, un GIF o un vídeo (campo «file»). Hasta 6 por ejercicio; fotos ≤ 10 MB, vídeos ≤ 50 MB."""
    # Se mira el tamaño antes de leer el cuerpo para no recibir archivos enormes
    length = int(request.headers.get("content-length") or 0)
    if length > m.MAX_VIDEO_BYTES + m.MB:
        raise _too_big("video")
    form = await request.form(max_files=1, max_fields=1)
    file = form.get("file")
    if not isinstance(file, UploadFile):
        raise HTTPException(422, "Elige un archivo para subir.")
    data = await file.read()
    await form.close()
    return await run_in_threadpool(_store, db, user, exercise_id, data)


@router.delete("/media/{media_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_media(media_id: uuid.UUID, user: CurrentUser, db: DB):
    row = db.get(ExerciseMedia, media_id)
    if row is None or row.owner_id != user.id:
        raise HTTPException(404, "Esa foto o vídeo ya no existe.")
    path = m.media_root() / row.path
    db.delete(row)
    db.commit()
    path.unlink(missing_ok=True)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.get("/media/{media_id}", response_class=FileResponse)
def get_media(media_id: uuid.UUID, sig: str, db: DB):
    """El archivo. No pide token: la firma de la URL caduca a las pocas horas."""
    if not m.check_signature(media_id, sig):
        raise HTTPException(403, "El enlace ha caducado. Vuelve a abrir el ejercicio.")
    row = db.get(ExerciseMedia, media_id)
    path = m.media_root() / row.path if row else None
    if path is None or not path.is_file():
        raise HTTPException(404, "Esa foto o vídeo ya no existe.")
    return FileResponse(path, media_type=row.content_type, headers={"Cache-Control": "private, max-age=3600"})
