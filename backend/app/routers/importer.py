"""Importa los datos del cuaderno web (formato cuaderno-definicion-v1).

Es idempotente: volver a importar el mismo fichero reemplaza esas fechas
en lugar de duplicar.
"""
import hashlib
from datetime import date

from fastapi import APIRouter, HTTPException
from sqlalchemy import select

from ..models import BodyEntry, DiaryItem, Dish, DishIngredient, Exercise, Food, WorkoutSession, WorkoutSet
from ..schemas import ImportReport
from ..security import DB, CurrentUser
from ..seed import DEFAULT_PROGRAM
from .catalog import visible_exercises

router = APIRouter(prefix="/import", tags=["importar"])
MEALS = {"desayuno", "almuerzo", "merienda", "cena", "picoteo"}


def _uid(user_id, key: str, prefix: str) -> str:
    return prefix + hashlib.sha1(f"{user_id}:{key}".encode()).hexdigest()[:12]


@router.post("/cuaderno", response_model=ImportReport)
def import_cuaderno(payload: dict, user: CurrentUser, db: DB):
    if payload.get("formato") != "cuaderno-definicion-v1":
        raise HTTPException(422, "El fichero no es una exportación del cuaderno (falta formato cuaderno-definicion-v1).")
    rep = ImportReport(sessions=0, sets=0, body_entries=0, foods=0, diary_items=0, skipped=[])

    ini = payload.get("inicio") or {}
    if ini and user.start_weight_kg is None:
        user.start_date = date.fromisoformat(ini["fecha"])
        user.start_weight_kg = ini["peso"]
        user.start_body_fat_pct = ini["grasa"]

    # --- alimentos propios
    food_map: dict[str, str] = {}
    desp = payload.get("despensa") or {}
    for key, a in (desp.get("alimentos") or {}).items():
        fid = _uid(user.id, key, "u:")
        db.merge(Food(id=fid, owner_id=user.id, name=a["n"], category="Mis alimentos", kcal=a["k"], protein=a["p"],
                      carbs=a.get("c") or 0, fat=a.get("g") or 0, default_portion_g=int(a.get("por") or 100)))
        food_map["m:" + key] = fid
        rep.foods += 1
    db.flush()

    def resolve_food(src: str | None) -> str | None:
        if not src:
            return None
        if src.startswith("m:"):
            return food_map.get(src)
        if src.startswith("b:") and db.get(Food, src) is not None:
            return src
        return None

    # --- platos
    dish_map: dict[str, object] = {}
    for key, p in (desp.get("platos") or {}).items():
        did = db.scalar(select(Dish.id).where(Dish.owner_id == user.id, Dish.name == p["n"]))
        d = db.get(Dish, did) if did else Dish(owner_id=user.id, name=p["n"])
        d.servings, d.cooked_weight_g = int(p.get("rac") or 1), p.get("peso")
        d.ingredients.clear()
        for pos, i in enumerate(p.get("ing") or []):
            d.ingredients.append(DishIngredient(position=pos, food_id=resolve_food(i.get("src")), name=i["n"], grams=i["gr"],
                                                kcal=i["k"], protein=i["p"], carbs=i.get("c") or 0, fat=i.get("g") or 0))
        db.add(d)
        db.flush()
        dish_map["d:" + key] = d.id

    # --- diario
    for ds, day in (payload.get("diario") or {}).items():
        d = date.fromisoformat(ds)
        # Uno a uno: un DELETE masivo no lo vería la sincronización (ver app/sync/tracking.py)
        for old_item in db.scalars(select(DiaryItem).where(DiaryItem.user_id == user.id, DiaryItem.date == d)):
            db.delete(old_item)
        for it in day.get("items") or []:
            meal = it.get("t")
            if meal not in MEALS:
                rep.skipped.append(f"diario {ds}: comida desconocida «{meal}»")
                continue
            src = it.get("src") or ""
            db.add(DiaryItem(user_id=user.id, date=d, meal=meal, name=it["n"], food_id=resolve_food(src),
                             dish_id=dish_map.get(src), grams=it["gr"], kcal=it["k"], protein=it["p"],
                             carbs=it.get("c") or 0, fat=it.get("g") or 0))
            rep.diary_items += 1

    # --- medidas
    for ds, m in (payload.get("medidas") or {}).items():
        d = date.fromisoformat(ds)
        e = db.get(BodyEntry, (user.id, d)) or BodyEntry(user_id=user.id, date=d)
        e.weight_kg, e.waist_cm = m.get("peso"), m.get("cintura")
        e.kcal, e.protein_g = m.get("kcal"), m.get("prot")
        db.add(e)
        rep.body_entries += 1

    # --- sesiones
    known = set(db.scalars(select(Exercise.id).where(visible_exercises(user))))
    for sid, s in (payload.get("sesiones") or {}).items():
        d = date.fromisoformat(s["fecha"])
        day_key = s["dia"]
        slot_of = {ex: slot for slot, ex in (s.get("sust") or {}).items()}
        old = db.scalar(select(WorkoutSession).where(WorkoutSession.user_id == user.id, WorkoutSession.date == d,
                                                     WorkoutSession.day_key == day_key))
        if old is not None:
            db.delete(old)
            db.flush()
        # El cuaderno web solo conoce el programa por defecto, de una semana
        ses = WorkoutSession(user_id=user.id, date=d, day_key=day_key, program_id=DEFAULT_PROGRAM, week=1)
        for ex_id, sets in (s.get("ej") or {}).items():
            if ex_id not in known:
                rep.skipped.append(f"sesión {sid}: ejercicio desconocido «{ex_id}»")
                continue
            for i, st in enumerate(x for x in sets if x.get("kg") is not None or x.get("r") is not None):
                ses.sets.append(WorkoutSet(slot_exercise_id=slot_of.get(ex_id, ex_id), exercise_id=ex_id, set_index=i,
                                           load_kg=st.get("kg"), reps=st.get("r")))
                rep.sets += 1
        db.add(ses)
        rep.sessions += 1

    db.commit()
    return rep
