"""Sincronización con la app sin conexión.

- GET /sync/pull?since=N: lo que cambió desde N (con since=0, todo). La app guarda el cursor.
- POST /sync/push: cambios hechos sin conexión, en orden. Cada uno lleva la versión que
  tenía la app; si en el servidor cambió entre medias, vuelve como conflicto con lo que
  hay en el servidor, y la app pregunta al usuario qué conservar.
"""
import hashlib
import json

from fastapi import APIRouter, HTTPException, Query
from pydantic import ValidationError
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from ..models import Exercise, ExerciseAlternative, Food, Program, SyncLog, SyncOp, User
from ..schemas import PullOut, PushChangeIn, PushIn, PushOut, PushResult, SyncRecord
from ..security import DB, CurrentUser
from ..sync.entities import REGISTRY, Entity, exercise_json, program_json
from ..sync.tracking import TRACKED, last_logged_version

router = APIRouter(prefix="/sync", tags=["sincronización"])


def _record(db: Session, user: User, ent: Entity, entity_id: str) -> SyncRecord:
    obj = ent.load(db, user, entity_id)
    if obj is None:
        return SyncRecord(entity=ent.name, id=entity_id, version=last_logged_version(db, user.id, ent.name, entity_id), deleted=True)
    return SyncRecord(entity=ent.name, id=entity_id, version=obj.version, data=ent.to_json(obj))


def _max_seq(db: Session, user: User) -> int:
    return db.scalar(select(func.max(SyncLog.seq)).where(SyncLog.user_id == user.id)) or 0


@router.get("/reference")
def reference(user: CurrentUser, db: DB, known: str | None = None):
    """Datos de consulta comunes a todos, para usar la app sin conexión: alimentos y ejercicios del
    catálogo, alternativas de cada ejercicio y plantillas de planes.

    Con known=<hash> que coincide devuelve solo {"hash", "unchanged": true}.
    """
    foods = [{"id": f.id, "name": f.name, "category": f.category, "kcal": float(f.kcal), "protein": float(f.protein),
              "carbs": float(f.carbs), "fat": float(f.fat), "default_portion_g": f.default_portion_g}
             for f in db.scalars(select(Food).where(Food.owner_id.is_(None)).order_by(Food.id))]
    exercises = [{"id": e.id, **exercise_json(e)} for e in db.scalars(select(Exercise).where(Exercise.owner_id.is_(None)).order_by(Exercise.id))]
    alternatives: dict[str, list[str]] = {}
    for a in db.scalars(select(ExerciseAlternative).order_by(ExerciseAlternative.exercise_id, ExerciseAlternative.position)):
        alternatives.setdefault(a.exercise_id, []).append(a.alternative_id)
    templates = [{"id": p.id, **program_json(p)} for p in db.scalars(select(Program).where(Program.owner_id.is_(None)).order_by(Program.id))]
    body = {"foods": foods, "exercises": exercises, "alternatives": alternatives, "templates": templates}
    h = hashlib.sha1(json.dumps(body, sort_keys=True).encode()).hexdigest()
    if known == h:
        return {"hash": h, "unchanged": True}
    return {"hash": h, "unchanged": False, **body}


@router.get("/pull", response_model=PullOut)
def pull(user: CurrentUser, db: DB, since: int = Query(0, ge=0), limit: int = Query(500, ge=1, le=2000)):
    if since == 0:
        # Primera vez (o tras borrar la base local): todo lo actual, sin borrados
        cursor = _max_seq(db, user)  # antes de leer: lo que cambie mientras tanto llega en la siguiente
        changes = [SyncRecord(entity=ent.name, id=_key(ent, obj), version=obj.version, data=ent.to_json(obj))
                   for ent in REGISTRY.values() for obj in ent.snapshot(db, user)]
        return PullOut(cursor=cursor, more=False, changes=changes)

    last = func.max(SyncLog.seq).label("last")
    rows = db.execute(select(SyncLog.entity, SyncLog.entity_id, last)
                      .where(SyncLog.user_id == user.id, SyncLog.seq > since)
                      .group_by(SyncLog.entity, SyncLog.entity_id).order_by(last).limit(limit)).all()
    changes = [_record(db, user, REGISTRY[r.entity], r.entity_id) for r in rows if r.entity in REGISTRY]
    return PullOut(cursor=rows[-1].last if rows else since, more=len(rows) == limit, changes=changes)


def _key(ent: Entity, obj) -> str:
    return TRACKED[type(obj)].key(obj)


def _detail(e: Exception) -> str:
    if isinstance(e, HTTPException):
        return str(e.detail)
    if isinstance(e, ValidationError):
        err = e.errors()[0]
        field = ".".join(str(x) for x in err["loc"])
        return f"Revisa «{field}»: {err['msg']}" if field else err["msg"]
    return str(e)


def _apply(db: Session, user: User, c: PushChangeIn) -> PushResult:
    ent = REGISTRY.get(c.entity)
    if ent is None:
        return PushResult(op_id=c.op_id, status="rejected", detail=f"«{c.entity}» no se sincroniza.")
    if ent.apply is None:
        return PushResult(op_id=c.op_id, status="rejected", detail=ent.readonly_detail)
    try:
        with db.begin_nested():
            obj = ent.load(db, user, c.id)
            current = obj.version if obj is not None else last_logged_version(db, user.id, ent.name, c.id)
            if c.delete:
                if obj is None:  # ya estaba borrado
                    return PushResult(op_id=c.op_id, status="applied", version=current, server=_record(db, user, ent, c.id))
                if c.base_version != current:
                    return PushResult(op_id=c.op_id, status="conflict", server=_record(db, user, ent, c.id))
                ent.delete(db, user, obj)
                db.flush()
                return PushResult(op_id=c.op_id, status="applied", version=obj.version,
                                  server=SyncRecord(entity=ent.name, id=c.id, version=obj.version, deleted=True))

            data = ent.normalize(c.data or {})
            # Crear algo que la app no conocía (base 0) sobre un hueco vacío no pisa nada: no es conflicto.
            # Sí lo es editar algo que otro dispositivo borró entretanto.
            stale = c.base_version != current and (obj is not None or c.base_version > 0)
            if stale:
                if obj is not None and ent.same(obj, data):
                    return PushResult(op_id=c.op_id, status="applied", version=current, server=_record(db, user, ent, c.id))
                return PushResult(op_id=c.op_id, status="conflict", server=_record(db, user, ent, c.id))
            obj = ent.apply(db, user, c.id, data)
            db.flush()
            return PushResult(op_id=c.op_id, status="applied", version=obj.version, server=_record(db, user, ent, c.id))
    except (HTTPException, ValidationError, ValueError) as e:
        return PushResult(op_id=c.op_id, status="rejected", detail=_detail(e))


@router.post("/push", response_model=PushOut)
def push(body: PushIn, user: CurrentUser, db: DB):
    results = []
    for c in body.changes:
        done = db.get(SyncOp, (user.id, c.op_id))
        if done is not None:
            results.append(PushResult.model_validate(done.result))
            continue
        r = _apply(db, user, c)
        db.add(SyncOp(user_id=user.id, op_id=c.op_id, result=r.model_dump(mode="json")))
        db.flush()
        results.append(r)
    db.commit()
    return PushOut(results=results)
