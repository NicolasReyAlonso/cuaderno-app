"""Anota en sync_log cada cambio de un registro sincronizable, venga de donde venga.

Funciona con un gancho de SQLAlchemy, así que da igual que el cambio llegue por
/sync/push, por los endpoints de siempre (PUT /body, PATCH /me…) o por /health/sync:
la versión sube y la app lo recibe en el siguiente /sync/pull.

- before_flush: sube version y updated_at de cada registro tocado. Si lo que cambia es
  un hijo (p. ej. una serie de una sesión), se considera cambiado el padre.
- after_flush: escribe una fila en sync_log por registro (los id ya están asignados).
"""
from collections.abc import Callable
from dataclasses import dataclass

from sqlalchemy import event, func, insert, select
from sqlalchemy.orm import Session

from ..models import Activity, BodyEntry, DailyMetric, DiaryItem, Dish, DishIngredient, Food, SyncLog, User, now_utc


@dataclass(frozen=True)
class Tracked:
    entity: str  # nombre en la API de sincronización
    key: Callable[[object], str]  # id del registro como texto
    owner: Callable[[object], object]  # user_id dueño (en un registro nuevo puede no estar asignado hasta el flush)
    syncs: Callable[[object], bool] = lambda o: True  # False: este registro no es de nadie (catálogo)


# Modelo → cómo se anota. Los pasos siguientes añaden comidas, entreno y planes.
TRACKED: dict[type, Tracked] = {
    BodyEntry: Tracked("body_entry", lambda o: o.date.isoformat(), lambda o: o.user_id),
    User: Tracked("profile", lambda o: "me", lambda o: o.id),
    DailyMetric: Tracked("health_day", lambda o: o.date.isoformat(), lambda o: o.user_id),
    Activity: Tracked("activity", lambda o: str(o.id), lambda o: o.user_id),
    Food: Tracked("food", lambda o: o.id, lambda o: o.owner_id, syncs=lambda o: o.owner_id is not None),
    Dish: Tracked("dish", lambda o: str(o.id), lambda o: o.owner_id),
    DiaryItem: Tracked("diary_item", lambda o: str(o.id), lambda o: o.user_id),
}

# Hijo → su padre sincronizable (el padre lleva a los hijos dentro de su JSON).
# Un hijo quitado de la lista ya no apunta a su padre: se busca por la clave ajena.
PARENTS: dict[type, Callable[[Session, object], object | None]] = {
    DishIngredient: lambda s, o: o.dish or (s.get(Dish, o.dish_id) if o.dish_id else None),
}


def last_logged_version(session: Session, user_id, entity: str, entity_id: str) -> int:
    """Versión más alta anotada (sirve cuando el registro ya no existe: borrado)."""
    with session.no_autoflush:
        return session.scalar(select(func.max(SyncLog.version)).where(
            SyncLog.user_id == user_id, SyncLog.entity == entity, SyncLog.entity_id == entity_id)) or 0


def _root(session: Session, obj):
    seen = set()
    while type(obj) in PARENTS and id(obj) not in seen:
        seen.add(id(obj))
        with session.no_autoflush:
            obj = PARENTS[type(obj)](session, obj)
        if obj is None:
            return None
    return obj if type(obj) in TRACKED else None


@event.listens_for(Session, "before_flush")
def _bump_versions(session: Session, _ctx, _instances):
    deleted = {id(o) for o in session.deleted}
    roots: dict[int, tuple[object, bool]] = {}

    def touch(obj, is_deleted: bool):
        r = obj if type(obj) in TRACKED else _root(session, obj)
        if r is None or not TRACKED[type(r)].syncs(r):
            return
        if id(r) in deleted and not is_deleted:
            return  # el padre se borra entero: basta con anotar su borrado
        roots[id(r)] = (r, is_deleted or roots.get(id(r), (None, False))[1])

    for o in session.new:
        touch(o, False)
    for o in session.dirty:
        if session.is_modified(o, include_collections=False):  # asignar el mismo valor no cuenta
            touch(o, False)
    for o in session.deleted:
        touch(o, type(o) in TRACKED)

    now = now_utc()
    for obj, is_deleted in roots.values():
        t = TRACKED[type(obj)]
        if obj in session.new:
            # Un registro con la misma clave pudo existir y borrarse: sigue su numeración
            key = _safe_key(t, obj)
            prev = last_logged_version(session, t.owner(obj), t.entity, key) if key else 0
            obj.version = prev + 1
        else:
            obj.version = (obj.version or 0) + 1
        if not is_deleted:
            obj.updated_at = now
    session.info["_sync_roots"] = list(roots.values())


def _safe_key(t: Tracked, obj) -> str | None:
    try:
        return t.key(obj)
    except (AttributeError, TypeError):
        return None  # id aún sin asignar (uuid por defecto): no puede tener historial


@event.listens_for(Session, "after_flush")
def _write_log(session: Session, _ctx):
    roots = session.info.pop("_sync_roots", [])
    if not roots:
        return
    rows = []
    for obj, is_deleted in roots:
        t = TRACKED[type(obj)]
        rows.append({"user_id": t.owner(obj), "entity": t.entity, "entity_id": t.key(obj), "version": obj.version,
                     "deleted": is_deleted, "at": now_utc()})
    session.connection().execute(insert(SyncLog), rows)


@event.listens_for(Session, "do_orm_execute")
def _no_bulk_writes(state):
    """Un DELETE/UPDATE masivo no pasa por before_flush: la app nunca se enteraría. Mejor fallar."""
    mapper = state.bind_mapper
    if (state.is_delete or state.is_update) and mapper is not None and (mapper.class_ in TRACKED or mapper.class_ in PARENTS):
        raise RuntimeError(f"{mapper.class_.__name__} se sincroniza: cambia o borra registro a registro (db.delete), "
                           "no con un DELETE/UPDATE masivo.")
