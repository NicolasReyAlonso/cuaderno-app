"""Carga el catálogo (ejercicios, figuras, programa, alternativas, alimentos base).

Idempotente: actualiza lo que existe y añade lo nuevo. No toca datos de usuarios.
    python -m app.seed
"""
import json
from pathlib import Path

from sqlalchemy import delete, select
from sqlalchemy.orm import Session

from .models import Exercise, ExerciseAlternative, Food, Program, ProgramDay, ProgramSlot

CATALOG = Path(__file__).parent / "data" / "catalog.json"
DEFAULT_PROGRAM = "definicion-5d"


def seed(db: Session, path: Path = CATALOG) -> dict:
    data = json.loads(path.read_text(encoding="utf-8"))

    for e in data["exercises"]:
        rmin, rmax = (e.get("default_reps") or [None, None])
        db.merge(Exercise(id=e["id"], name=e["name"], muscle_group=e["muscle_group"], cue=e["cue"],
                          unit=e["unit"], load_mode=e["load_mode"], is_compound=e["is_compound"],
                          default_rep_min=rmin, default_rep_max=rmax, figure=e["figure"]))
    db.flush()

    db.execute(delete(ExerciseAlternative))
    for a in data["alternatives"]:
        db.add(ExerciseAlternative(**a))

    p = data["program"]
    prog = db.get(Program, p["id"])
    if prog is None:
        prog = Program(id=p["id"], name=p["name"])
        db.add(prog)
    prog.name = p["name"]
    prog.days.clear()
    db.flush()
    for d in p["days"]:
        day = ProgramDay(key=d["id"], position=d["position"], weekday=d["weekday"], name=d["name"],
                         short=d["short"], focus=d["focus"], color=d["color"])
        for s in d["slots"]:
            day.slots.append(ProgramSlot(**s))
        prog.days.append(day)

    existing = set(db.scalars(select(Food.id).where(Food.owner_id.is_(None))))
    for f in data["foods"]:
        fid = "b:" + f["id"]
        db.merge(Food(id=fid, owner_id=None, name=f["name"], category=f["category"], kcal=f["kcal"],
                      protein=f["protein"], carbs=f["carbs"], fat=f["fat"], default_portion_g=f["default_portion_g"]))
        existing.discard(fid)
    db.commit()
    return {"exercises": len(data["exercises"]), "alternatives": len(data["alternatives"]),
            "days": len(p["days"]), "foods": len(data["foods"])}


if __name__ == "__main__":
    from .db import SessionLocal

    with SessionLocal() as s:
        print(seed(s))
