"""Qué se sincroniza y cómo: cargar, pasar a JSON, validar y guardar cada tipo de registro.

Cada tipo se identifica por un nombre (entity) y un id de texto. El JSON es el mismo
en /sync/pull y en /sync/push. Los de solo lectura (datos de la pulsera) no aceptan push:
llegan por /health/sync.
"""
import uuid
from collections.abc import Callable
from dataclasses import dataclass
from datetime import date
from decimal import Decimal
from typing import Literal

from fastapi import HTTPException
from pydantic import AwareDatetime, BaseModel, Field
from sqlalchemy import select
from sqlalchemy.orm import Session

from ..models import Activity, BodyEntry, DailyMetric, DiaryItem, Dish, DishIngredient, Food, Program, User, now_utc


def _f(v):
    return float(v) if isinstance(v, Decimal) else v


def _d(v: date | None) -> str | None:
    return v.isoformat() if v else None


@dataclass(frozen=True)
class Entity:
    name: str
    load: Callable[[Session, User, str], object | None]
    snapshot: Callable[[Session, User], list]
    to_json: Callable[[object], dict]
    schema: type[BaseModel] | None = None  # None = solo lectura
    apply: Callable[[Session, User, str, BaseModel], object] | None = None
    delete: Callable[[Session, User, object], None] | None = None
    ignore_in_same: tuple[str, ...] = ()  # campos que no cuentan para decidir si es «lo mismo»

    def normalize(self, data: dict) -> BaseModel:
        return self.schema.model_validate(data)

    def same(self, obj, data: BaseModel) -> bool:
        """El registro del servidor ya tiene esos valores: no hay conflicto aunque la versión no cuadre."""
        current = self.to_json(obj)
        return all(current.get(k) == v for k, v in data.model_dump(mode="json").items() if k not in self.ignore_in_same)


def _parse_date(entity_id: str) -> date:
    try:
        return date.fromisoformat(entity_id)
    except ValueError:
        raise HTTPException(422, f"«{entity_id}» no es una fecha (AAAA-MM-DD).")


# ---------------------------------------------------------------- peso y medidas
class BodyEntrySync(BaseModel):
    weight_kg: float | None = Field(None, ge=30, le=300)
    waist_cm: float | None = Field(None, ge=40, le=250)
    kcal: int | None = Field(None, ge=0, le=10000)
    protein_g: int | None = Field(None, ge=0, le=600)


def _body_json(e: BodyEntry) -> dict:
    return {"date": e.date.isoformat(), "weight_kg": _f(e.weight_kg), "waist_cm": _f(e.waist_cm), "kcal": e.kcal,
            "protein_g": e.protein_g, "weight_source": e.weight_source}


def _body_apply(db: Session, user: User, entity_id: str, data: BodyEntrySync) -> BodyEntry:
    d = _parse_date(entity_id)
    e = db.get(BodyEntry, (user.id, d)) or BodyEntry(user_id=user.id, date=d)
    if _f(e.weight_kg) != data.weight_kg:  # el peso que cambias tú pasa a ser manual
        e.weight_source = "manual" if data.weight_kg is not None else None
    e.weight_kg, e.waist_cm, e.kcal, e.protein_g = data.weight_kg, data.waist_cm, data.kcal, data.protein_g
    db.add(e)
    return e


BODY_ENTRY = Entity(
    name="body_entry",
    load=lambda db, user, i: db.get(BodyEntry, (user.id, _parse_date(i))),
    snapshot=lambda db, user: db.scalars(select(BodyEntry).where(BodyEntry.user_id == user.id)).all(),
    to_json=_body_json,
    schema=BodyEntrySync,
    apply=_body_apply,
    delete=lambda db, user, e: db.delete(e),
)


# ---------------------------------------------------------------- perfil y objetivos (id «me»)
class ProfileSync(BaseModel):
    name: str = Field("", max_length=120)
    start_date: date | None = None
    start_weight_kg: float | None = Field(None, ge=30, le=300)
    start_body_fat_pct: float | None = Field(None, ge=3, le=70)
    kcal_target: int = Field(2000, ge=800, le=6000)
    protein_target_g: int = Field(160, ge=20, le=400)
    program_id: str | None = None
    program_started_on: date | None = None


def _profile_json(u: User) -> dict:
    return {"name": u.name, "start_date": _d(u.start_date), "start_weight_kg": _f(u.start_weight_kg),
            "start_body_fat_pct": _f(u.start_body_fat_pct), "kcal_target": u.kcal_target, "protein_target_g": u.protein_target_g,
            "program_id": u.program_id, "program_started_on": _d(u.program_started_on)}


def _profile_apply(db: Session, user: User, entity_id: str, data: ProfileSync) -> User:
    if entity_id != "me":
        raise HTTPException(422, "El perfil se identifica como «me».")
    if data.program_id is not None:
        p = db.get(Program, data.program_id)
        if p is None or p.owner_id not in (None, user.id):
            raise HTTPException(422, "Ese plan no existe. Elige uno de tus planes o una plantilla.")
    for k, v in data.model_dump().items():
        setattr(user, k, v)
    return user


def _no_delete(*_):
    raise HTTPException(422, "El perfil no se puede borrar.")


PROFILE = Entity(
    name="profile",
    load=lambda db, user, i: user if i == "me" else None,
    snapshot=lambda db, user: [user],
    to_json=_profile_json,
    schema=ProfileSync,
    apply=_profile_apply,
    delete=_no_delete,
)


# ---------------------------------------------------------------- pulsera y báscula (solo lectura)
HEALTH_DAY = Entity(
    name="health_day",
    load=lambda db, user, i: db.get(DailyMetric, (user.id, _parse_date(i))),
    snapshot=lambda db, user: db.scalars(select(DailyMetric).where(DailyMetric.user_id == user.id)).all(),
    to_json=lambda m: {"date": m.date.isoformat(), "steps": m.steps, "active_kcal": m.active_kcal, "sleep_minutes": m.sleep_minutes,
                       "resting_hr": m.resting_hr, "hrv_ms": _f(m.hrv_ms)},
)


def _activity(db: Session, user: User, i: str):
    import uuid

    try:
        a = db.get(Activity, uuid.UUID(i))
    except ValueError:
        return None
    return a if a is not None and a.user_id == user.id else None


ACTIVITY = Entity(
    name="activity",
    load=_activity,
    snapshot=lambda db, user: db.scalars(select(Activity).where(Activity.user_id == user.id)).all(),
    to_json=lambda a: {"id": str(a.id), "kind": a.kind, "started_at": a.started_at.isoformat(), "ended_at": a.ended_at.isoformat(),
                       "kcal": a.kcal, "distance_m": a.distance_m, "source": a.source},
)


def _uuid(entity_id: str) -> uuid.UUID:
    try:
        return uuid.UUID(entity_id)
    except ValueError:
        raise HTTPException(422, f"«{entity_id}» no es un identificador válido.")


def _owned(db: Session, model, key, owner_attr: str, user: User):
    """El registro si es del usuario; None si no existe. Si es de otro, como si no existiera para leer,
    pero no se puede crear encima (mismo id)."""
    obj = db.get(model, key)
    if obj is None or getattr(obj, owner_attr) == user.id:
        return obj
    return _FOREIGN


_FOREIGN = object()


def _load_owned(model, owner_attr: str, parse=lambda i: i):
    def load(db: Session, user: User, i: str):
        try:
            obj = _owned(db, model, parse(i), owner_attr, user)
        except HTTPException:
            return None
        return None if obj is _FOREIGN else obj
    return load


def _get_for_write(db: Session, user: User, model, key, owner_attr: str):
    obj = _owned(db, model, key, owner_attr, user)
    if obj is _FOREIGN:
        raise HTTPException(422, "Ese identificador ya está en uso. Vuelve a crearlo.")
    return obj


# ---------------------------------------------------------------- alimentos propios (id «u:…»)
class FoodSync(BaseModel):
    name: str = Field(min_length=1, max_length=160)
    category: str = Field("Mis alimentos", max_length=60)
    kcal: float = Field(ge=0, le=950)
    protein: float = Field(ge=0, le=100)
    carbs: float = Field(0, ge=0, le=100)
    fat: float = Field(0, ge=0, le=100)
    default_portion_g: int = Field(100, ge=1, le=5000)


def _food_json(f: Food) -> dict:
    return {"name": f.name, "category": f.category, "kcal": _f(f.kcal), "protein": _f(f.protein), "carbs": _f(f.carbs),
            "fat": _f(f.fat), "default_portion_g": f.default_portion_g}


def _food_apply(db: Session, user: User, entity_id: str, data: FoodSync) -> Food:
    if not entity_id.startswith("u:") or len(entity_id) > 64:
        raise HTTPException(422, "Los alimentos propios llevan un id que empieza por «u:».")
    f = _get_for_write(db, user, Food, entity_id, "owner_id") or Food(id=entity_id, owner_id=user.id)
    for k, v in data.model_dump().items():
        setattr(f, k, v)
    db.add(f)
    return f


FOOD = Entity(
    name="food",
    load=_load_owned(Food, "owner_id"),
    snapshot=lambda db, user: db.scalars(select(Food).where(Food.owner_id == user.id)).all(),
    to_json=_food_json,
    schema=FoodSync,
    apply=_food_apply,
    delete=lambda db, user, f: db.delete(f),
)


def _visible_food(db: Session, user: User, food_id: str | None) -> Food | None:
    if not food_id:
        return None
    f = db.get(Food, food_id)
    return f if f is not None and f.owner_id in (None, user.id) else None


# ---------------------------------------------------------------- platos (ingredientes dentro, valores por 100 g)
class IngredientSync(BaseModel):
    food_id: str | None = None
    name: str = Field(min_length=1, max_length=160)
    grams: float = Field(gt=0, le=20000)
    kcal: float = Field(0, ge=0, le=950)
    protein: float = Field(0, ge=0, le=100)
    carbs: float = Field(0, ge=0, le=100)
    fat: float = Field(0, ge=0, le=100)


class DishSync(BaseModel):
    name: str = Field(min_length=1, max_length=160)
    servings: int = Field(1, ge=1, le=50)
    cooked_weight_g: float | None = Field(None, gt=0, le=50000)
    ingredients: list[IngredientSync] = Field(min_length=1, max_length=60)


def _dish_json(d: Dish) -> dict:
    return {"name": d.name, "servings": d.servings, "cooked_weight_g": _f(d.cooked_weight_g),
            "ingredients": [{"food_id": i.food_id, "name": i.name, "grams": _f(i.grams), "kcal": _f(i.kcal), "protein": _f(i.protein),
                             "carbs": _f(i.carbs), "fat": _f(i.fat)} for i in d.ingredients]}


def _dish_apply(db: Session, user: User, entity_id: str, data: DishSync) -> Dish:
    key = _uuid(entity_id)
    d = _get_for_write(db, user, Dish, key, "owner_id") or Dish(id=key, owner_id=user.id)
    d.name, d.servings, d.cooked_weight_g = data.name, data.servings, data.cooked_weight_g
    d.ingredients.clear()
    for pos, ing in enumerate(data.ingredients):
        f = _visible_food(db, user, ing.food_id)
        if f is not None:  # el alimento manda: sus valores actuales
            vals = dict(food_id=f.id, name=f.name, kcal=f.kcal, protein=f.protein, carbs=f.carbs, fat=f.fat)
        else:  # ya no existe: se queda la copia que trae el plato
            vals = dict(food_id=None, name=ing.name, kcal=ing.kcal, protein=ing.protein, carbs=ing.carbs, fat=ing.fat)
        d.ingredients.append(DishIngredient(position=pos, grams=ing.grams, **vals))
    db.add(d)
    return d


DISH = Entity(
    name="dish",
    load=_load_owned(Dish, "owner_id", _uuid),
    snapshot=lambda db, user: db.scalars(select(Dish).where(Dish.owner_id == user.id)).all(),
    to_json=_dish_json,
    schema=DishSync,
    apply=_dish_apply,
    delete=lambda db, user, d: db.delete(d),
)


# ---------------------------------------------------------------- diario (valores ya calculados para los gramos)
class DiarySync(BaseModel):
    date: date
    meal: Literal["desayuno", "almuerzo", "merienda", "cena", "picoteo"]
    name: str = Field(min_length=1, max_length=160)
    food_id: str | None = None
    dish_id: str | None = None
    grams: float = Field(gt=0, le=5000)
    kcal: float = Field(ge=0, le=50000)
    protein: float = Field(ge=0, le=5000)
    carbs: float = Field(0, ge=0, le=5000)
    fat: float = Field(0, ge=0, le=5000)
    created_at: AwareDatetime | None = None


def _diary_json(i: DiaryItem) -> dict:
    return {"date": i.date.isoformat(), "meal": i.meal, "name": i.name, "food_id": i.food_id,
            "dish_id": str(i.dish_id) if i.dish_id else None, "grams": _f(i.grams), "kcal": _f(i.kcal), "protein": _f(i.protein),
            "carbs": _f(i.carbs), "fat": _f(i.fat), "created_at": i.created_at.isoformat()}


def _diary_apply(db: Session, user: User, entity_id: str, data: DiarySync) -> DiaryItem:
    key = _uuid(entity_id)
    item = _get_for_write(db, user, DiaryItem, key, "user_id") or DiaryItem(id=key, user_id=user.id)
    food = _visible_food(db, user, data.food_id)
    dish = None
    if data.dish_id:
        try:
            dish = db.get(Dish, uuid.UUID(data.dish_id))
        except ValueError:
            dish = None
        if dish is not None and dish.owner_id != user.id:
            dish = None
    # Los valores los calculó la app con lo que tenía: el diario guarda esa copia (como al apuntar online)
    item.date, item.meal, item.name, item.grams = data.date, data.meal, data.name, data.grams
    item.kcal, item.protein, item.carbs, item.fat = data.kcal, data.protein, data.carbs, data.fat
    item.food_id, item.dish_id = (food.id if food else None), (dish.id if dish else None)
    if item.created_at is None:
        item.created_at = data.created_at or now_utc()
    db.add(item)
    return item


DIARY_ITEM = Entity(
    name="diary_item",
    load=_load_owned(DiaryItem, "user_id", _uuid),
    snapshot=lambda db, user: db.scalars(select(DiaryItem).where(DiaryItem.user_id == user.id)).all(),
    to_json=_diary_json,
    schema=DiarySync,
    apply=_diary_apply,
    delete=lambda db, user, i: db.delete(i),
    ignore_in_same=("created_at",),
)


REGISTRY: dict[str, Entity] = {e.name: e for e in (PROFILE, BODY_ENTRY, HEALTH_DAY, ACTIVITY, FOOD, DISH, DIARY_ITEM)}
