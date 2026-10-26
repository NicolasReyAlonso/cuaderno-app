import uuid
from datetime import date, datetime, timedelta
from typing import Literal

from pydantic import AwareDatetime, BaseModel, ConfigDict, EmailStr, Field, model_validator
from pydantic_core import PydanticCustomError

Meal = Literal["desayuno", "almuerzo", "merienda", "cena", "picoteo"]


def _invalid(msg: str) -> PydanticCustomError:
    # Sin el prefijo «Value error,» que añade Pydantic a los ValueError: la app muestra msg tal cual
    return PydanticCustomError("invalid", msg)


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
    program_started_on: date | None


class UserPatch(BaseModel):
    name: str | None = None
    start_date: date | None = None
    start_weight_kg: float | None = Field(None, ge=30, le=300)
    start_body_fat_pct: float | None = Field(None, ge=3, le=70)
    kcal_target: int | None = Field(None, ge=800, le=6000)
    protein_target_g: int | None = Field(None, ge=20, le=400)


class DeleteAccountIn(BaseModel):
    password: str = Field(max_length=128)


# ---------------------------------------------------------------- catálogo
class MediaOut(BaseModel):
    id: uuid.UUID
    kind: Literal["image", "video"]
    content_type: str
    size_bytes: int
    url: str  # relativa a la API y con firma temporal: no necesita Authorization


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
    mine: bool = False
    media: list[MediaOut] = []  # solo en los ejercicios propios


class ExerciseIn(BaseModel):
    name: str = Field(min_length=1, max_length=160)
    muscle_group: str = Field(min_length=1, max_length=80)
    cue: str = Field("", max_length=1000)
    unit: Literal["reps", "seconds"] = "reps"
    load_mode: Literal["kg", "extra"] = "kg"
    is_compound: bool = False
    default_rep_min: int | None = Field(None, ge=1, le=600)
    default_rep_max: int | None = Field(None, ge=1, le=600)

    @model_validator(mode="after")
    def _range(self):
        if (self.default_rep_min is None) != (self.default_rep_max is None):
            raise _invalid("Pon el rango completo (mínimo y máximo) o déjalo vacío.")
        if self.default_rep_min is not None and self.default_rep_min > self.default_rep_max:
            raise _invalid("El mínimo del rango no puede ser mayor que el máximo.")
        return self


class SlotOut(BaseModel):
    exercise_id: str
    sets: int
    rep_min: int
    rep_max: int
    rest: str
    is_core: bool
    alternatives: list[str]


class DayOut(BaseModel):
    week: int
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
    weeks: int
    mine: bool  # False = plantilla: no se edita, se duplica
    days: list[DayOut]


class ProgramSummaryOut(BaseModel):
    id: str
    name: str
    weeks: int
    days_per_week: int
    mine: bool
    active: bool


class SlotIn(BaseModel):
    exercise_id: str = Field(min_length=1, max_length=64)
    sets: int = Field(ge=1, le=12)
    rep_min: int = Field(ge=1, le=600)
    rep_max: int = Field(ge=1, le=600)
    rest: str = Field("", max_length=20)
    is_core: bool = False

    @model_validator(mode="after")
    def _range(self):
        if self.rep_min > self.rep_max:
            raise _invalid(f"En «{self.exercise_id}» el mínimo del rango es mayor que el máximo.")
        return self


class DayIn(BaseModel):
    week: int = Field(1, ge=1, le=4)
    key: str = Field(pattern=r"^[A-Za-z0-9_-]{1,40}$")
    weekday: int | None = Field(None, ge=1, le=7)  # 1 = lunes … 7 = domingo
    name: str = Field(min_length=1, max_length=80)
    short: str = Field("", max_length=12)
    focus: str = Field("", max_length=160)
    color: str = Field("grey", max_length=20)
    slots: list[SlotIn] = Field(max_length=20)

    @model_validator(mode="after")
    def _unique_exercises(self):
        seen: set[str] = set()
        for s in self.slots:
            if s.exercise_id in seen:
                raise _invalid(f"«{s.exercise_id}» está dos veces en «{self.name}». Cada ejercicio, una vez por día.")
            seen.add(s.exercise_id)
        return self


class ProgramIn(BaseModel):
    name: str = Field(min_length=1, max_length=120)
    weeks: int = Field(1, ge=1, le=4)
    days: list[DayIn] = Field(default_factory=list, max_length=28)

    @model_validator(mode="after")
    def _days(self):
        keys: set[tuple[int, str]] = set()
        weekdays: set[tuple[int, int]] = set()
        for d in self.days:
            if d.week > self.weeks:
                raise _invalid(f"«{d.name}» está en la semana {d.week}, pero el plan tiene {_weeks(self.weeks)}.")
            if d.key == "today":
                raise _invalid("«today» está reservado. Usa otra clave para el día.")
            if (d.week, d.key) in keys:
                raise _invalid(f"La clave «{d.key}» se repite en la semana {d.week}.")
            keys.add((d.week, d.key))
            if d.weekday is not None:
                if (d.week, d.weekday) in weekdays:
                    raise _invalid(f"En la semana {d.week} hay dos días el mismo día de la semana.")
                weekdays.add((d.week, d.weekday))
        return self


def _weeks(n: int) -> str:
    return "1 semana" if n == 1 else f"{n} semanas"


class ActivateIn(BaseModel):
    started_on: date


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
    program_id: str | None
    week: int
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
    week: int
    saved: bool
    slots: list[PlannedSlot]


class TodayOut(BaseModel):
    date: date
    program_id: str
    program_name: str
    weeks: int
    week: int
    day_key: str | None  # el día con ese día de la semana; None = descanso
    days: list[DayOut]  # los días de esa semana, para elegir otro


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
    weight_from_health: bool = False  # el peso vino de la báscula (Health Connect / Salud)


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
    # Medias de los días con dato de la pulsera
    avg_steps: float | None = None
    avg_active_kcal: float | None = None
    avg_sleep_minutes: float | None = None
    avg_resting_hr: float | None = None


class BodySummaryOut(BaseModel):
    current_weight: float | None
    current_weight_date: date | None
    body_fat_est: float | None
    lean_mass: float | None
    goal_25_weight: float | None
    goal_20_weight: float | None
    weeks: list[WeekOut]
    entries: list[BodyOut]


# ---------------------------------------------------------------- salud (pulsera, báscula)
class HealthDayIn(BaseModel):
    """Resumen de un día. Lo que no se sabe va como null y no borra lo ya guardado."""
    date: date
    steps: int | None = Field(None, ge=0, le=200_000)
    active_kcal: int | None = Field(None, ge=0, le=10_000)
    sleep_minutes: int | None = Field(None, ge=0, le=1440)
    resting_hr: int | None = Field(None, ge=20, le=250)
    hrv_ms: float | None = Field(None, ge=1, le=500)
    weight_kg: float | None = Field(None, ge=30, le=300)


class ActivityIn(BaseModel):
    external_id: str = Field(min_length=1, max_length=120)
    kind: str = Field(min_length=1, max_length=40)
    started_at: AwareDatetime
    ended_at: AwareDatetime
    kcal: int | None = Field(None, ge=0, le=10_000)
    distance_m: int | None = Field(None, ge=0, le=1_000_000)
    source: str = Field("", max_length=80)

    @model_validator(mode="after")
    def _times(self):
        if self.ended_at < self.started_at:
            raise _invalid("Una actividad termina antes de empezar. Revisa la hora del reloj del móvil.")
        if self.ended_at - self.started_at > timedelta(hours=24):
            raise _invalid("Una actividad dura más de 24 horas.")
        return self


class HealthSyncIn(BaseModel):
    days: list[HealthDayIn] = Field(default_factory=list, max_length=120)
    activities: list[ActivityIn] = Field(default_factory=list, max_length=1000)

    @model_validator(mode="after")
    def _unique_days(self):
        if len({d.date for d in self.days}) != len(self.days):
            raise _invalid("Hay dos resúmenes del mismo día.")
        return self


class HealthSyncOut(BaseModel):
    days: int
    activities_new: int
    activities_updated: int
    weights_set: int
    weights_kept_manual: int  # días en los que ya habías apuntado el peso a mano


class HealthDayOut(ORM):
    date: date
    steps: int | None
    active_kcal: int | None
    sleep_minutes: int | None
    resting_hr: int | None
    hrv_ms: float | None


class ActivityOut(ORM):
    id: uuid.UUID
    kind: str
    started_at: datetime
    ended_at: datetime
    kcal: int | None
    distance_m: int | None
    source: str


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
    protein: float


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


# ---------------------------------------------------------------- sincronización (app sin conexión)
class SyncRecord(BaseModel):
    entity: str
    id: str
    version: int
    deleted: bool = False
    data: dict | None = None  # None si está borrado


class PullOut(BaseModel):
    cursor: int  # se manda como «since» en la siguiente llamada
    more: bool  # quedan cambios: volver a llamar con el nuevo cursor
    changes: list[SyncRecord]


class PushChangeIn(BaseModel):
    op_id: uuid.UUID  # lo genera la app: reenviar el mismo cambio no lo aplica dos veces
    entity: str = Field(max_length=30)
    id: str = Field(min_length=1, max_length=80)
    base_version: int = Field(ge=0)  # versión que tenía la app al cambiarlo (0 = nuevo)
    data: dict | None = None
    delete: bool = False


class PushIn(BaseModel):
    changes: list[PushChangeIn] = Field(max_length=500)


class PushResult(BaseModel):
    op_id: uuid.UUID
    status: Literal["applied", "conflict", "rejected"]
    version: int | None = None
    server: SyncRecord | None = None  # en «applied», cómo quedó; en «conflict», lo que hay en el servidor
    detail: str | None = None  # en «rejected», por qué


class PushOut(BaseModel):
    results: list[PushResult]
