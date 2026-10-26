from datetime import date, datetime, time, timedelta, timezone

from fastapi import APIRouter, HTTPException, Query, Response, status
from sqlalchemy import delete, select

from ..models import Activity, BodyEntry, DailyMetric
from ..schemas import ActivityOut, HealthDayOut, HealthSyncIn, HealthSyncOut
from ..security import DB, CurrentUser

router = APIRouter(prefix="/health", tags=["salud"])

_METRICS = ("steps", "active_kcal", "sleep_minutes", "resting_hr", "hrv_ms")


def _range(date_from: date | None, date_to: date | None) -> tuple[date, date]:
    to = date_to or date.today()
    return (date_from or to - timedelta(days=29)), to


@router.post("/sync", response_model=HealthSyncOut)
def sync(body: HealthSyncIn, user: CurrentUser, db: DB):
    """Guarda lo leído de Health Connect / Salud. Se puede repetir: actualiza sin duplicar.

    El peso de la báscula rellena Peso solo si ese día no hay un peso apuntado a mano.
    """
    tomorrow = date.today() + timedelta(days=1)  # margen por la zona horaria del móvil
    if any(d.date > tomorrow for d in body.days):
        raise HTTPException(422, "Hay datos con fecha futura. Revisa la fecha del móvil.")
    out = HealthSyncOut(days=0, activities_new=0, activities_updated=0, weights_set=0, weights_kept_manual=0)

    for d in body.days:
        m = db.get(DailyMetric, (user.id, d.date)) or DailyMetric(user_id=user.id, date=d.date)
        for k in _METRICS:
            if getattr(d, k) is not None:
                setattr(m, k, getattr(d, k))
        db.add(m)
        out.days += 1
        if d.weight_kg is not None:
            e = db.get(BodyEntry, (user.id, d.date)) or BodyEntry(user_id=user.id, date=d.date)
            if e.weight_kg is not None and e.weight_source != "health":
                out.weights_kept_manual += 1
            else:
                e.weight_kg, e.weight_source = d.weight_kg, "health"
                db.add(e)
                out.weights_set += 1

    existing = {a.external_id: a for a in db.scalars(select(Activity).where(
        Activity.user_id == user.id, Activity.external_id.in_([a.external_id for a in body.activities])))}
    for a in body.activities:
        row = existing.get(a.external_id)
        if row is None:
            row = Activity(user_id=user.id, external_id=a.external_id)
            existing[a.external_id] = row
            db.add(row)
            out.activities_new += 1
        else:
            out.activities_updated += 1
        row.kind, row.started_at, row.ended_at = a.kind, a.started_at, a.ended_at
        row.kcal, row.distance_m, row.source = a.kcal, a.distance_m, a.source

    db.commit()
    return out


@router.get("/days", response_model=list[HealthDayOut])
def days(user: CurrentUser, db: DB, date_from: date | None = Query(None, alias="from"), date_to: date | None = Query(None, alias="to")):
    """Resumen por día. Sin fechas: los últimos 30 días."""
    a, b = _range(date_from, date_to)
    return db.scalars(select(DailyMetric).where(DailyMetric.user_id == user.id, DailyMetric.date >= a, DailyMetric.date <= b)
                      .order_by(DailyMetric.date)).all()


@router.get("/activities", response_model=list[ActivityOut])
def activities(user: CurrentUser, db: DB, date_from: date | None = Query(None, alias="from"),
               date_to: date | None = Query(None, alias="to")):
    """Actividades que empiezan entre esas fechas (UTC), la más reciente primero. Sin fechas: los últimos 30 días."""
    a, b = _range(date_from, date_to)
    start = datetime.combine(a, time.min, tzinfo=timezone.utc)
    end = datetime.combine(b + timedelta(days=1), time.min, tzinfo=timezone.utc)
    return db.scalars(select(Activity).where(Activity.user_id == user.id, Activity.started_at >= start, Activity.started_at < end)
                      .order_by(Activity.started_at.desc())).all()


@router.delete("", status_code=status.HTTP_204_NO_CONTENT)
def forget(user: CurrentUser, db: DB):
    """Borra todo lo que vino de Health Connect / Salud, incluidos los pesos de la báscula. Lo apuntado a mano se queda."""
    db.execute(delete(DailyMetric).where(DailyMetric.user_id == user.id))
    db.execute(delete(Activity).where(Activity.user_id == user.id))
    for e in db.scalars(select(BodyEntry).where(BodyEntry.user_id == user.id, BodyEntry.weight_source == "health")):
        e.weight_kg, e.weight_source = None, None
        if e.waist_cm is None and e.kcal is None and e.protein_g is None:
            db.delete(e)
    db.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)
