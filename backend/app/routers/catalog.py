from fastapi import APIRouter, HTTPException
from sqlalchemy import select
from sqlalchemy.orm import Session, selectinload

from ..models import Exercise, ExerciseAlternative, Program, ProgramDay, ProgramSlot
from ..schemas import CatalogOut, DayOut, ExerciseOut, ProgramOut, SlotOut
from ..security import DB, CurrentUser
from ..seed import DEFAULT_PROGRAM

router = APIRouter(tags=["catálogo"])


def alternatives_map(db: Session) -> dict[str, list[str]]:
    out: dict[str, list[str]] = {}
    for a in db.scalars(select(ExerciseAlternative).order_by(ExerciseAlternative.exercise_id, ExerciseAlternative.position)):
        out.setdefault(a.exercise_id, []).append(a.alternative_id)
    return out


def load_program(db: Session, program_id: str) -> Program:
    prog = db.scalar(
        select(Program).where(Program.id == program_id)
        .options(selectinload(Program.days).selectinload(ProgramDay.slots).selectinload(ProgramSlot.exercise))
    )
    if prog is None:
        raise HTTPException(404, "Programa no encontrado.")
    return prog


def program_out(prog: Program, alts: dict[str, list[str]]) -> ProgramOut:
    return ProgramOut(id=prog.id, name=prog.name, days=[
        DayOut(key=d.key, position=d.position, weekday=d.weekday, name=d.name, short=d.short, focus=d.focus, color=d.color,
               slots=[SlotOut(exercise_id=s.exercise_id, sets=s.sets, rep_min=s.rep_min, rep_max=s.rep_max, rest=s.rest,
                              is_core=s.is_core, alternatives=alts.get(s.exercise_id, [])) for s in d.slots])
        for d in prog.days])


@router.get("/catalog", response_model=CatalogOut)
def catalog(user: CurrentUser, db: DB):
    exercises = db.scalars(select(Exercise).order_by(Exercise.id)).all()
    prog = load_program(db, user.program_id or DEFAULT_PROGRAM)
    return CatalogOut(exercises=[ExerciseOut.model_validate(e) for e in exercises],
                      program=program_out(prog, alternatives_map(db)))
