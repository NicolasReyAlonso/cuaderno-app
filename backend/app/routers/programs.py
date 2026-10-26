import uuid
from collections import Counter

from fastapi import APIRouter, HTTPException, Response, status
from sqlalchemy import or_, select
from sqlalchemy.orm import Session, selectinload

from ..models import Exercise, Program, ProgramDay, ProgramSlot, User
from ..schemas import ActivateIn, ProgramIn, ProgramOut, ProgramSummaryOut, UserOut
from ..security import DB, CurrentUser
from .catalog import alternatives_map, load_program, program_out, visible_exercises

router = APIRouter(prefix="/programs", tags=["planes"])


def _visible(db: Session, user: User, program_id: str) -> Program:
    prog = load_program(db, program_id)
    if prog.owner_id not in (None, user.id):
        raise HTTPException(404, "Programa no encontrado.")
    return prog


def _own(db: Session, user: User, program_id: str) -> Program:
    prog = _visible(db, user, program_id)
    if prog.owner_id is None:
        raise HTTPException(403, "Las plantillas no se cambian. Duplícala y edita la copia.")
    return prog


def check_exercises(db: Session, user: User, body: ProgramIn) -> None:
    ids = {s.exercise_id for d in body.days for s in d.slots}
    found = set(db.scalars(select(Exercise.id).where(Exercise.id.in_(ids), visible_exercises(user))))
    missing = sorted(ids - found)
    if missing:
        raise HTTPException(422, f"El ejercicio «{missing[0]}» no existe. Elige uno del catálogo o crea uno propio.")


def fill_program(db: Session, prog: Program, body: ProgramIn) -> None:
    """Sustituye nombre, semanas y días. La posición es el orden dentro de cada semana."""
    prog.name, prog.weeks = body.name, body.weeks
    prog.days.clear()
    db.flush()  # borra los días viejos antes de insertar los nuevos (misma clave única)
    pos: Counter[int] = Counter()
    for d in sorted(body.days, key=lambda d: d.week):
        day = ProgramDay(week=d.week, key=d.key, position=pos[d.week], weekday=d.weekday, name=d.name, short=d.short,
                         focus=d.focus, color=d.color,
                         slots=[ProgramSlot(position=i, **s.model_dump()) for i, s in enumerate(d.slots)])
        pos[d.week] += 1
        prog.days.append(day)


def _out(db: Session, prog: Program, user: User) -> ProgramOut:
    return program_out(prog, alternatives_map(db), user)


@router.get("", response_model=list[ProgramSummaryOut])
def list_programs(user: CurrentUser, db: DB):
    """Tus planes primero y luego las plantillas."""
    progs = db.scalars(select(Program).where(or_(Program.owner_id.is_(None), Program.owner_id == user.id))
                       .options(selectinload(Program.days)).order_by(Program.owner_id.is_(None), Program.name)).all()
    return [ProgramSummaryOut(id=p.id, name=p.name, weeks=p.weeks, mine=p.owner_id == user.id, active=p.id == user.program_id,
                              days_per_week=max(Counter(d.week for d in p.days).values(), default=0)) for p in progs]


@router.post("", response_model=ProgramOut, status_code=status.HTTP_201_CREATED)
def create_program(body: ProgramIn, user: CurrentUser, db: DB):
    check_exercises(db, user, body)
    prog = Program(id="u:" + uuid.uuid4().hex[:12], owner_id=user.id, name=body.name)
    db.add(prog)
    fill_program(db, prog, body)
    db.commit()
    return _out(db, prog, user)


@router.get("/{program_id}", response_model=ProgramOut)
def get_program(program_id: str, user: CurrentUser, db: DB):
    return _out(db, _visible(db, user, program_id), user)


@router.put("/{program_id}", response_model=ProgramOut)
def update_program(program_id: str, body: ProgramIn, user: CurrentUser, db: DB):
    prog = _own(db, user, program_id)
    check_exercises(db, user, body)
    fill_program(db, prog, body)
    db.commit()
    return _out(db, prog, user)


@router.delete("/{program_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_program(program_id: str, user: CurrentUser, db: DB):
    prog = _own(db, user, program_id)
    if user.program_id == prog.id:
        raise HTTPException(409, "Es tu plan activo. Activa otro antes de borrarlo.")
    db.delete(prog)
    db.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.post("/{program_id}/duplicate", response_model=ProgramOut, status_code=status.HTTP_201_CREATED)
def duplicate_program(program_id: str, user: CurrentUser, db: DB):
    src = _visible(db, user, program_id)
    prog = Program(id="u:" + uuid.uuid4().hex[:12], owner_id=user.id, name=f"{src.name} (copia)"[:120], weeks=src.weeks)
    for d in src.days:
        prog.days.append(ProgramDay(
            week=d.week, key=d.key, position=d.position, weekday=d.weekday, name=d.name, short=d.short, focus=d.focus,
            color=d.color,
            slots=[ProgramSlot(position=s.position, exercise_id=s.exercise_id, sets=s.sets, rep_min=s.rep_min,
                               rep_max=s.rep_max, rest=s.rest, is_core=s.is_core) for s in d.slots]))
    db.add(prog)
    db.commit()
    return _out(db, prog, user)


@router.post("/{program_id}/activate", response_model=UserOut)
def activate_program(program_id: str, body: ActivateIn, user: CurrentUser, db: DB):
    """Pasa a usar este plan. started_on marca la semana 1."""
    prog = _visible(db, user, program_id)
    user.program_id, user.program_started_on = prog.id, body.started_on
    db.commit()
    return user
