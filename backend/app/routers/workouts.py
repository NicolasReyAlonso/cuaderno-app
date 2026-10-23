from datetime import date

from fastapi import APIRouter, HTTPException, Query, Response, status
from sqlalchemy import select
from sqlalchemy.orm import Session, selectinload

from ..models import Exercise, ProgramDay, User, WorkoutSession, WorkoutSet
from ..schemas import (DayPlanOut, HintOut, LastPerformance, PlannedSlot, SessionIn, SessionOut, SetOut,
                       SlotLogOut)
from ..security import DB, CurrentUser
from ..seed import DEFAULT_PROGRAM
from ..services.progression import SetResult, effective_range, suggest
from .catalog import alternatives_map

router = APIRouter(prefix="/workouts", tags=["entreno"])


def _day(db: Session, user: User, day_key: str) -> ProgramDay:
    day = db.scalar(select(ProgramDay).where(ProgramDay.program_id == (user.program_id or DEFAULT_PROGRAM), ProgramDay.key == day_key)
                    .options(selectinload(ProgramDay.slots)))
    if day is None:
        raise HTTPException(404, f"El día «{day_key}» no está en tu programa.")
    return day


def _session(db: Session, user: User, d: date, day_key: str) -> WorkoutSession | None:
    return db.scalar(select(WorkoutSession).where(WorkoutSession.user_id == user.id, WorkoutSession.date == d,
                                                  WorkoutSession.day_key == day_key).options(selectinload(WorkoutSession.sets)))


def _session_out(s: WorkoutSession) -> SessionOut:
    slots: dict[str, SlotLogOut] = {}
    for st in s.sets:
        so = slots.setdefault(st.slot_exercise_id, SlotLogOut(slot_exercise_id=st.slot_exercise_id, exercise_id=st.exercise_id, sets=[]))
        so.sets.append(SetOut(load_kg=_f(st.load_kg), reps=st.reps))
    return SessionOut(date=s.date, day_key=s.day_key, slots=list(slots.values()))


def _f(v):
    return float(v) if v is not None else None


def _last_performance(db: Session, user: User, exercise_id: str, before: date) -> LastPerformance | None:
    row = db.execute(
        select(WorkoutSession.id, WorkoutSession.date).join(WorkoutSet)
        .where(WorkoutSession.user_id == user.id, WorkoutSession.date < before, WorkoutSet.exercise_id == exercise_id)
        .order_by(WorkoutSession.date.desc()).limit(1)
    ).first()
    if row is None:
        return None
    sets = db.scalars(select(WorkoutSet).where(WorkoutSet.session_id == row.id, WorkoutSet.exercise_id == exercise_id)
                      .order_by(WorkoutSet.set_index)).all()
    return LastPerformance(date=row.date, sets=[SetOut(load_kg=_f(s.load_kg), reps=s.reps) for s in sets])


def _planned(db: Session, user: User, d: date, slot, alts: dict[str, list[str]], ex_id: str, logged: list[SetOut]) -> PlannedSlot:
    options = alts.get(slot.exercise_id, [])
    if ex_id != slot.exercise_id and ex_id not in options:
        ex_id = slot.exercise_id
    ex = db.get(Exercise, ex_id)
    slot_ex = db.get(Exercise, slot.exercise_id)
    rmin, rmax = effective_range(slot_ex.unit, slot.rep_min, slot.rep_max, ex.unit, ex.default_rep_min, ex.default_rep_max,
                                 ex_id == slot.exercise_id)
    last = _last_performance(db, user, ex_id, d)
    hint = suggest(sets_planned=slot.sets, rep_min=rmin, rep_max=rmax, unit=ex.unit, load_mode=ex.load_mode,
                   is_compound=ex.is_compound, last=[SetResult(s.load_kg, s.reps) for s in last.sets] if last else None)
    return PlannedSlot(slot_exercise_id=slot.exercise_id, exercise_id=ex_id, sets=slot.sets, rep_min=rmin, rep_max=rmax,
                       rest=slot.rest, is_core=slot.is_core, alternatives=options, last=last,
                       hint=HintOut(kind=hint.kind, text=hint.text) if hint else None, logged=logged)


@router.get("/{d}/{day_key}/slots/{slot_exercise_id}", response_model=PlannedSlot)
def slot_plan(d: date, day_key: str, slot_exercise_id: str, user: CurrentUser, db: DB, exercise_id: str | None = None):
    """Un hueco con el ejercicio indicado: sirve para refrescar historial y sugerencia al cambiar de alternativa."""
    day = _day(db, user, day_key)
    slot = next((s for s in day.slots if s.exercise_id == slot_exercise_id), None)
    if slot is None:
        raise HTTPException(404, f"«{slot_exercise_id}» no es un ejercicio de este día.")
    alts = alternatives_map(db)
    target = exercise_id or slot_exercise_id
    if target != slot_exercise_id and target not in alts.get(slot_exercise_id, []):
        raise HTTPException(422, f"«{target}» no es una alternativa de «{slot_exercise_id}».")
    return _planned(db, user, d, slot, alts, target, [])


@router.get("/{d}/{day_key}/plan", response_model=DayPlanOut)
def day_plan(d: date, day_key: str, user: CurrentUser, db: DB):
    """Lo que toca hoy: ejercicio de cada hueco, lo que hiciste la última vez y la sugerencia."""
    day = _day(db, user, day_key)
    alts = alternatives_map(db)
    saved = _session(db, user, d, day_key)

    choice: dict[str, str] = {}
    logged: dict[str, list[SetOut]] = {}
    if saved:
        for st in saved.sets:
            choice[st.slot_exercise_id] = st.exercise_id
            logged.setdefault(st.slot_exercise_id, []).append(SetOut(load_kg=_f(st.load_kg), reps=st.reps))
    else:
        prev = db.scalar(select(WorkoutSession).where(WorkoutSession.user_id == user.id, WorkoutSession.day_key == day_key,
                                                      WorkoutSession.date < d).order_by(WorkoutSession.date.desc()).limit(1)
                         .options(selectinload(WorkoutSession.sets)))
        if prev:
            for st in prev.sets:
                if st.exercise_id != st.slot_exercise_id:
                    choice[st.slot_exercise_id] = st.exercise_id

    out = [_planned(db, user, d, slot, alts, choice.get(slot.exercise_id, slot.exercise_id), logged.get(slot.exercise_id, []))
           for slot in day.slots]
    return DayPlanOut(date=d, day_key=day_key, saved=saved is not None, slots=out)


@router.put("/{d}/{day_key}", response_model=SessionOut)
def save_session(d: date, day_key: str, body: SessionIn, user: CurrentUser, db: DB):
    day = _day(db, user, day_key)
    alts = alternatives_map(db)
    slot_ids = {s.exercise_id for s in day.slots}
    performed: set[str] = set()
    rows: list[WorkoutSet] = []
    for sl in body.slots:
        if sl.slot_exercise_id not in slot_ids:
            raise HTTPException(422, f"«{sl.slot_exercise_id}» no es un ejercicio de este día.")
        if sl.exercise_id != sl.slot_exercise_id and sl.exercise_id not in alts.get(sl.slot_exercise_id, []):
            raise HTTPException(422, f"«{sl.exercise_id}» no es una alternativa de «{sl.slot_exercise_id}».")
        if sl.exercise_id in performed:
            raise HTTPException(422, f"«{sl.exercise_id}» aparece dos veces en la sesión.")
        performed.add(sl.exercise_id)
        for i, s in enumerate(x for x in sl.sets if x.load_kg is not None or x.reps is not None):
            rows.append(WorkoutSet(slot_exercise_id=sl.slot_exercise_id, exercise_id=sl.exercise_id, set_index=i,
                                   load_kg=s.load_kg, reps=s.reps))
    if not rows:
        raise HTTPException(422, "Apunta al menos una serie antes de guardar.")

    session = _session(db, user, d, day_key)
    if session is None:
        session = WorkoutSession(user_id=user.id, date=d, day_key=day_key)
        db.add(session)
    session.sets.clear()
    session.sets.extend(rows)
    db.commit()
    db.refresh(session)
    return _session_out(session)


@router.get("/{d}/{day_key}", response_model=SessionOut)
def get_session(d: date, day_key: str, user: CurrentUser, db: DB):
    s = _session(db, user, d, day_key)
    if s is None:
        raise HTTPException(404, "No hay sesión guardada ese día.")
    return _session_out(s)


@router.delete("/{d}/{day_key}", status_code=status.HTTP_204_NO_CONTENT)
def delete_session(d: date, day_key: str, user: CurrentUser, db: DB):
    s = _session(db, user, d, day_key)
    if s is not None:
        db.delete(s)
        db.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.get("", response_model=list[SessionOut])
def list_sessions(user: CurrentUser, db: DB, date_from: date | None = Query(None, alias="from"),
                  date_to: date | None = Query(None, alias="to")):
    q = select(WorkoutSession).where(WorkoutSession.user_id == user.id).options(selectinload(WorkoutSession.sets))
    if date_from:
        q = q.where(WorkoutSession.date >= date_from)
    if date_to:
        q = q.where(WorkoutSession.date <= date_to)
    return [_session_out(s) for s in db.scalars(q.order_by(WorkoutSession.date.desc()))]
