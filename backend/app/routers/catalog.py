import copy
import uuid

from fastapi import APIRouter, HTTPException, status
from sqlalchemy import or_, select
from sqlalchemy.orm import Session, selectinload

from ..models import Exercise, ExerciseAlternative, Program, ProgramDay, ProgramSlot, User
from ..schemas import CatalogOut, DayOut, ExerciseIn, ExerciseOut, MediaOut, ProgramOut, SlotOut
from ..security import DB, CurrentUser
from ..seed import DEFAULT_PROGRAM
from ..services.media import signed_url

router = APIRouter(tags=["catálogo"])

# Figura de los ejercicios propios: de pie, de frente, brazos de abajo a la altura de los hombros
GENERIC_FIGURE = {
    "front": True,
    "a": {"hip": [100, 84], "t": 90, "hand": [86, 90], "hand2": [114, 90], "foot": [93, 156], "foot2": [107, 156]},
    "b": {"hip": [100, 84], "t": 90, "hand": [44, 42], "hand2": [156, 42], "foot": [93, 156], "foot2": [107, 156]},
    "eb": 1, "eb2": -1, "kb": -1, "kb2": 1,
}


def alternatives_map(db: Session) -> dict[str, list[str]]:
    out: dict[str, list[str]] = {}
    for a in db.scalars(select(ExerciseAlternative).order_by(ExerciseAlternative.exercise_id, ExerciseAlternative.position)):
        out.setdefault(a.exercise_id, []).append(a.alternative_id)
    return out


def visible_exercises(user: User):
    """Condición: ejercicios del catálogo y los propios del usuario."""
    return or_(Exercise.owner_id.is_(None), Exercise.owner_id == user.id)


def load_program(db: Session, program_id: str) -> Program:
    prog = db.scalar(
        select(Program).where(Program.id == program_id)
        .options(selectinload(Program.days).selectinload(ProgramDay.slots).selectinload(ProgramSlot.exercise))
    )
    if prog is None:
        raise HTTPException(404, "Programa no encontrado.")
    return prog


def day_out(d: ProgramDay, alts: dict[str, list[str]]) -> DayOut:
    return DayOut(week=d.week, key=d.key, position=d.position, weekday=d.weekday, name=d.name, short=d.short, focus=d.focus,
                  color=d.color,
                  slots=[SlotOut(exercise_id=s.exercise_id, sets=s.sets, rep_min=s.rep_min, rep_max=s.rep_max, rest=s.rest,
                                 is_core=s.is_core, alternatives=alts.get(s.exercise_id, [])) for s in d.slots])


def program_out(prog: Program, alts: dict[str, list[str]], user: User) -> ProgramOut:
    return ProgramOut(id=prog.id, name=prog.name, weeks=prog.weeks, mine=prog.owner_id == user.id,
                      days=[day_out(d, alts) for d in prog.days])


_EXERCISE_FIELDS = set(ExerciseOut.model_fields) - {"mine", "media"}


def media_out(m) -> MediaOut:
    return MediaOut(id=m.id, kind=m.kind, content_type=m.content_type, size_bytes=m.size_bytes, url=signed_url(m.id))


def exercise_out(e: Exercise, user: User) -> ExerciseOut:
    mine = e.owner_id == user.id
    return ExerciseOut(**{k: getattr(e, k) for k in _EXERCISE_FIELDS}, mine=mine,
                       media=[media_out(m) for m in e.media] if mine else [])


@router.get("/catalog", response_model=CatalogOut)
def catalog(user: CurrentUser, db: DB):
    exercises = db.scalars(select(Exercise).where(visible_exercises(user)).options(selectinload(Exercise.media))
                           .order_by(Exercise.id)).all()
    prog = load_program(db, user.program_id or DEFAULT_PROGRAM)
    return CatalogOut(exercises=[exercise_out(e, user) for e in exercises],
                      program=program_out(prog, alternatives_map(db), user))


@router.post("/exercises", response_model=ExerciseOut, status_code=status.HTTP_201_CREATED)
def create_exercise(body: ExerciseIn, user: CurrentUser, db: DB):
    e = Exercise(id="u:" + uuid.uuid4().hex[:12], owner_id=user.id, figure=copy.deepcopy(GENERIC_FIGURE), **body.model_dump())
    db.add(e)
    db.commit()
    return exercise_out(e, user)
