import uuid
from datetime import date
from typing import Literal

from pydantic import BaseModel, ConfigDict, EmailStr, Field

Meal = Literal["desayuno", "almuerzo", "merienda", "cena", "picoteo"]


class ORM(BaseModel):
    model_config = ConfigDict(from_attributes=True)


# ---------------------------------------------------------------- auth
class RegisterIn(BaseModel):
    email: EmailStr
    password: str = Field(min_length=8, max_length=128)
    name: str = ""


class TokenOut(BaseModel):
    access_token: str
    token_type: str = "bearer"


class UserOut(ORM):
    id: uuid.UUID
    email: str
    name: str
    start_date: date | None
    start_weight_kg: float | None
    start_body_fat_pct: float | None
    kcal_target: int
    protein_target_g: int
    program_id: str | None


class UserPatch(BaseModel):
    name: str | None = None
    start_date: date | None = None
    start_weight_kg: float | None = Field(None, ge=30, le=300)
    start_body_fat_pct: float | None = Field(None, ge=3, le=70)
    kcal_target: int | None = Field(None, ge=800, le=6000)
    protein_target_g: int | None = Field(None, ge=20, le=400)
    program_id: str | None = None


# ---------------------------------------------------------------- catálogo
class ExerciseOut(ORM):
    id: str
    name: str
    muscle_group: str
    cue: str
    unit: str
    load_mode: str
    is_compound: bool
    default_rep_min: int | None
    default_rep_max: int | None
    figure: dict


class SlotOut(BaseModel):
    exercise_id: str
    sets: int
    rep_min: int
    rep_max: int
    rest: str
    is_core: bool
    alternatives: list[str]


class DayOut(BaseModel):
    key: str
    position: int
    weekday: int | None
    name: str
    short: str
    focus: str
    color: str
    slots: list[SlotOut]


class ProgramOut(BaseModel):
    id: str
    name: str
    days: list[DayOut]


class CatalogOut(BaseModel):
    exercises: list[ExerciseOut]
    program: ProgramOut


# ---------------------------------------------------------------- entreno
class SetIn(BaseModel):
    load_kg: float | None = Field(None, ge=0, le=500)
    reps: int | None = Field(None, ge=0, le=300)


class SlotLogIn(BaseModel):
    slot_exercise_id: str
    exercise_id: str  # igual al anterior si no hubo cambio
    sets: list[SetIn] = Field(max_length=12)


class SessionIn(BaseModel):
    slots: list[SlotLogIn]


class SetOut(BaseModel):
    load_kg: float | None
    reps: int | None


class SlotLogOut(BaseModel):
    slot_exercise_id: str
    exercise_id: str
    sets: list[SetOut]


class SessionOut(BaseModel):
    date: date
    day_key: str
    slots: list[SlotLogOut]


class LastPerformance(BaseModel):
    date: date
    sets: list[SetOut]


class HintOut(BaseModel):
    kind: str
    text: str


class PlannedSlot(BaseModel):
    slot_exercise_id: str
    exercise_id: str  # el que toca hoy (original o la alternativa que usaste la última vez)
    sets: int
    rep_min: int
    rep_max: int
    rest: str
    is_core: bool
    alternatives: list[str]
    last: LastPerformance | None
    hint: HintOut | None
    logged: list[SetOut]


class DayPlanOut(BaseModel):
    date: date
    day_key: str
    saved: bool
    slots: list[PlannedSlot]


# ---------------------------------------------------------------- cuerpo
class BodyIn(BaseModel):
    weight_kg: float | None = Field(None, ge=30, le=300)
    waist_cm: float | None = Field(None, ge=40, le=250)
    kcal: int | None = Field(None, ge=0, le=10000)
    protein_g: int | None = Field(None, ge=0, le=600)


class BodyOut(BaseModel):
    date: date
    weight_kg: float | None
    waist_cm: float | None
    kcal: float | None
    protein_g: float | None
    from_diary: bool


class WeekOut(BaseModel):
    monday: date
    avg_weight: float | None
    n_weights: int
    avg_kcal: float | None
    avg_protein: float | None
    waist_cm: float | None
    delta_kg: float | None
    delta_pct: float | None
    pace: str | None


class BodySummaryOut(BaseModel):
    current_weight: float | None
    current_weight_date: date | None
    body_fat_est: float | None
    lean_mass: float | None
    goal_25_weight: float | None
    goal_20_weight: float | None
    weeks: list[WeekOut]
    entries: list[BodyOut]


# ---------------------------------------------------------------- comidas
class FoodIn(BaseModel):
    name: str = Field(min_length=1, max_length=160)
    kcal: float = Field(ge=0, le=950)
    protein: float = Field(ge=0, le=100)
    carbs: float = Field(0, ge=0, le=100)
    fat: float = Field(0, ge=0, le=100)
    default_portion_g: int = Field(100, ge=1, le=5000)
    category: str = "Mis alimentos"


class FoodOut(ORM):
    id: str
    name: str
    category: str
    kcal: float
    protein: float
    carbs: float
    fat: float
    default_portion_g: int
    mine: bool = False


class IngredientIn(BaseModel):
    food_id: str
    grams: float = Field(gt=0, le=20000)


class DishIn(BaseModel):
    name: str = Field(min_length=1, max_length=160)
    servings: int = Field(1, ge=1, le=50)
    cooked_weight_g: float | None = Field(None, gt=0, le=50000)
    ingredients: list[IngredientIn] = Field(min_length=1, max_length=60)


class IngredientOut(BaseModel):
    food_id: str | None
    name: str
    grams: float
    kcal: float


class DishOut(BaseModel):
    id: uuid.UUID
    name: str
    servings: int
    cooked_weight_g: float | None
    ingredients: list[IngredientOut]
    total_kcal: float
    total_protein: float
    per100_kcal: float
    per100_protein: float
    per100_carbs: float
    per100_fat: float
    serving_g: int


class DiaryItemIn(BaseModel):
    meal: Meal
    grams: float = Field(gt=0, le=5000)
    food_id: str | None = None
    dish_id: uuid.UUID | None = None


class DiaryItemOut(ORM):
    id: uuid.UUID
    meal: str
    name: str
    grams: float
    kcal: float
    protein: float
    carbs: float
    fat: float


class DiaryDayOut(BaseModel):
    date: date
    items: list[DiaryItemOut]
    kcal: float
    protein: float
    carbs: float
    fat: float
    kcal_target: int
    protein_target_g: int


class ImportReport(BaseModel):
    sessions: int
    sets: int
    body_entries: int
    foods: int
    diary_items: int
    skipped: list[str]
