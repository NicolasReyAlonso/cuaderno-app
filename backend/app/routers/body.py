from datetime import date

from fastapi import APIRouter, Response, status
from sqlalchemy import func, select

from ..models import BodyEntry, DiaryItem
from ..schemas import BodyIn, BodyOut, BodySummaryOut, WeekOut
from ..security import DB, CurrentUser
from ..services import body as svc

router = APIRouter(prefix="/body", tags=["peso y medidas"])


def _f(v):
    return float(v) if v is not None else None


def _rows(db, user) -> list[BodyOut]:
    entries = {e.date: e for e in db.scalars(select(BodyEntry).where(BodyEntry.user_id == user.id))}
    diary = {r.date: r for r in db.execute(
        select(DiaryItem.date, func.sum(DiaryItem.kcal).label("kcal"), func.sum(DiaryItem.protein).label("protein"))
        .where(DiaryItem.user_id == user.id).group_by(DiaryItem.date))}
    out = []
    for d in sorted(set(entries) | set(diary)):
        e, di = entries.get(d), diary.get(d)
        out.append(BodyOut(date=d, weight_kg=_f(e.weight_kg) if e else None, waist_cm=_f(e.waist_cm) if e else None,
                           kcal=round(float(di.kcal)) if di else (e.kcal if e else None),
                           protein_g=round(float(di.protein)) if di else (e.protein_g if e else None),
                           from_diary=di is not None))
    return out


@router.put("/{d}", response_model=BodyOut)
def upsert(d: date, body: BodyIn, user: CurrentUser, db: DB):
    e = db.get(BodyEntry, (user.id, d)) or BodyEntry(user_id=user.id, date=d)
    for k, v in body.model_dump(exclude_unset=True).items():
        setattr(e, k, v)
    db.add(e)
    db.commit()
    return next(r for r in _rows(db, user) if r.date == d)


@router.delete("/{d}", status_code=status.HTTP_204_NO_CONTENT)
def delete(d: date, user: CurrentUser, db: DB):
    e = db.get(BodyEntry, (user.id, d))
    if e is not None:
        db.delete(e)
        db.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.get("/summary", response_model=BodySummaryOut)
def summary(user: CurrentUser, db: DB):
    rows = _rows(db, user)
    weights = [(r.date, r.weight_kg) for r in rows if r.weight_kg is not None]
    current = svc.rolling_avg(weights, weights[-1][0]) if weights else None
    sw = _f(user.start_weight_kg)
    sbf = _f(user.start_body_fat_pct)
    lbm = svc.lean_mass(sw, sbf) if sw and sbf else None
    ref = current or sw
    weeks = svc.weekly([{"date": r.date, "weight": r.weight_kg, "waist": r.waist_cm, "kcal": r.kcal, "protein": r.protein_g}
                        for r in rows], sw, user.start_date)
    return BodySummaryOut(
        current_weight=round(current, 2) if current else None,
        current_weight_date=weights[-1][0] if weights else None,
        body_fat_est=round(svc.bf_at(lbm, ref), 1) if lbm and ref else None,
        lean_mass=round(lbm, 1) if lbm else None,
        goal_25_weight=round(svc.weight_for_bf(lbm, 25), 1) if lbm else None,
        goal_20_weight=round(svc.weight_for_bf(lbm, 20), 1) if lbm else None,
        weeks=[WeekOut(**w.__dict__) for w in weeks],
        entries=rows,
    )
