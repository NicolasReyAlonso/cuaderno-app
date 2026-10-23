"""Modelo de datos.

Catálogo compartido (ejercicios, programa, alternativas, alimentos base) y
datos por usuario (sesiones, series, medidas, alimentos propios, platos y diario).
"""
import uuid
from datetime import date, datetime, timezone
from decimal import Decimal

from sqlalchemy import (
    JSON,
    Boolean,
    CheckConstraint,
    Date,
    DateTime,
    ForeignKey,
    Integer,
    Numeric,
    String,
    Text,
    UniqueConstraint,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from .db import Base


def now_utc() -> datetime:
    return datetime.now(timezone.utc)


# ---------------------------------------------------------------- usuarios
class User(Base):
    __tablename__ = "users"

    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)
    email: Mapped[str] = mapped_column(String(320), unique=True, index=True)
    password_hash: Mapped[str] = mapped_column(String(255))
    name: Mapped[str] = mapped_column(String(120), default="")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=now_utc)

    # Punto de partida y objetivos de la fase
    start_date: Mapped[date | None] = mapped_column(Date)
    start_weight_kg: Mapped[Decimal | None] = mapped_column(Numeric(5, 1))
    start_body_fat_pct: Mapped[Decimal | None] = mapped_column(Numeric(4, 1))
    kcal_target: Mapped[int] = mapped_column(Integer, default=2000)
    protein_target_g: Mapped[int] = mapped_column(Integer, default=160)
    program_id: Mapped[str | None] = mapped_column(ForeignKey("programs.id"))
    # Día en que empezó el plan activo: semana = (días desde aquí ÷ 7) mód weeks + 1
    program_started_on: Mapped[date | None] = mapped_column(Date)


# ---------------------------------------------------------------- catálogo
class Exercise(Base):
    __tablename__ = "exercises"
    __table_args__ = (
        CheckConstraint("unit in ('reps','seconds')", name="exercise_unit"),
        CheckConstraint("load_mode in ('kg','extra')", name="exercise_load_mode"),
    )

    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    # None = catálogo; con dueño = ejercicio propio (con la figura genérica)
    owner_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    name: Mapped[str] = mapped_column(String(160))
    muscle_group: Mapped[str] = mapped_column(String(80))
    cue: Mapped[str] = mapped_column(Text, default="")
    unit: Mapped[str] = mapped_column(String(10), default="reps")
    # 'kg' = peso de la carga; 'extra' = lastre sobre el peso corporal (0 = sin lastre)
    load_mode: Mapped[str] = mapped_column(String(10), default="kg")
    is_compound: Mapped[bool] = mapped_column(Boolean, default=False)
    # Rango propio cuando cambia la unidad respecto al hueco que sustituye (p. ej. plancha en segundos)
    default_rep_min: Mapped[int | None] = mapped_column(Integer)
    default_rep_max: Mapped[int | None] = mapped_column(Integer)
    # Pose a y b del muñeco animado (mismo formato que el cuaderno web)
    figure: Mapped[dict] = mapped_column(JSON)


class ExerciseAlternative(Base):
    __tablename__ = "exercise_alternatives"

    exercise_id: Mapped[str] = mapped_column(ForeignKey("exercises.id", ondelete="CASCADE"), primary_key=True)
    alternative_id: Mapped[str] = mapped_column(ForeignKey("exercises.id", ondelete="CASCADE"), primary_key=True)
    position: Mapped[int] = mapped_column(Integer, default=0)


class Program(Base):
    __tablename__ = "programs"
    __table_args__ = (CheckConstraint("weeks between 1 and 4", name="program_weeks"),)

    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    name: Mapped[str] = mapped_column(String(120))
    # None = plantilla pública; con dueño = programa personalizado
    owner_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("users.id", ondelete="CASCADE", use_alter=True))
    # Semanas que se repiten en bucle (1 = la misma semana siempre)
    weeks: Mapped[int] = mapped_column(Integer, default=1)
    days: Mapped[list["ProgramDay"]] = relationship(back_populates="program", order_by=lambda: (ProgramDay.week, ProgramDay.position),
                                                    cascade="all, delete-orphan")


class ProgramDay(Base):
    __tablename__ = "program_days"
    __table_args__ = (
        UniqueConstraint("program_id", "week", "key"),
        CheckConstraint("week >= 1", name="program_day_week"),  # el tope (≤ programs.weeks) lo valida la API
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    program_id: Mapped[str] = mapped_column(ForeignKey("programs.id", ondelete="CASCADE"))
    week: Mapped[int] = mapped_column(Integer, default=1)
    key: Mapped[str] = mapped_column(String(40))
    position: Mapped[int] = mapped_column(Integer)
    weekday: Mapped[int | None] = mapped_column(Integer)  # 1 = lunes … 7 = domingo
    name: Mapped[str] = mapped_column(String(80))
    short: Mapped[str] = mapped_column(String(12), default="")
    focus: Mapped[str] = mapped_column(String(160), default="")
    color: Mapped[str] = mapped_column(String(20), default="grey")
    program: Mapped[Program] = relationship(back_populates="days")
    slots: Mapped[list["ProgramSlot"]] = relationship(back_populates="day", order_by="ProgramSlot.position", cascade="all, delete-orphan")


class ProgramSlot(Base):
    """Un hueco del día: el ejercicio original con sus series y rango."""

    __tablename__ = "program_slots"

    id: Mapped[int] = mapped_column(primary_key=True)
    day_id: Mapped[int] = mapped_column(ForeignKey("program_days.id", ondelete="CASCADE"))
    position: Mapped[int] = mapped_column(Integer)
    exercise_id: Mapped[str] = mapped_column(ForeignKey("exercises.id"))
    sets: Mapped[int] = mapped_column(Integer)
    rep_min: Mapped[int] = mapped_column(Integer)
    rep_max: Mapped[int] = mapped_column(Integer)
    rest: Mapped[str] = mapped_column(String(20), default="")
    is_core: Mapped[bool] = mapped_column(Boolean, default=False)
    day: Mapped[ProgramDay] = relationship(back_populates="slots")
    exercise: Mapped[Exercise] = relationship()


# ---------------------------------------------------------------- entreno
class WorkoutSession(Base):
    __tablename__ = "workout_sessions"
    __table_args__ = (UniqueConstraint("user_id", "date", "day_key"),)

    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    date: Mapped[date] = mapped_column(Date, index=True)
    day_key: Mapped[str] = mapped_column(String(40))
    # Plan y semana con los que se hizo; si se borra el plan, el historial se queda
    program_id: Mapped[str | None] = mapped_column(ForeignKey("programs.id", ondelete="SET NULL"))
    week: Mapped[int] = mapped_column(Integer, default=1)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=now_utc, onupdate=now_utc)
    sets: Mapped[list["WorkoutSet"]] = relationship(back_populates="session", order_by="WorkoutSet.id", cascade="all, delete-orphan")


class WorkoutSet(Base):
    __tablename__ = "workout_sets"

    id: Mapped[int] = mapped_column(primary_key=True)
    session_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("workout_sessions.id", ondelete="CASCADE"), index=True)
    # Ejercicio original del hueco y ejercicio realmente hecho (iguales si no hubo cambio)
    slot_exercise_id: Mapped[str] = mapped_column(ForeignKey("exercises.id"))
    exercise_id: Mapped[str] = mapped_column(ForeignKey("exercises.id"), index=True)
    set_index: Mapped[int] = mapped_column(Integer)
    load_kg: Mapped[Decimal | None] = mapped_column(Numeric(6, 2))
    reps: Mapped[int | None] = mapped_column(Integer)
    session: Mapped[WorkoutSession] = relationship(back_populates="sets")


# ---------------------------------------------------------------- cuerpo
class BodyEntry(Base):
    __tablename__ = "body_entries"

    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), primary_key=True)
    date: Mapped[date] = mapped_column(Date, primary_key=True)
    weight_kg: Mapped[Decimal | None] = mapped_column(Numeric(5, 1))
    waist_cm: Mapped[Decimal | None] = mapped_column(Numeric(5, 1))
    # Solo se usan si ese día no hay diario de comidas
    kcal: Mapped[int | None] = mapped_column(Integer)
    protein_g: Mapped[int | None] = mapped_column(Integer)


# ---------------------------------------------------------------- comidas
class Food(Base):
    __tablename__ = "foods"

    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    owner_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    name: Mapped[str] = mapped_column(String(160))
    category: Mapped[str] = mapped_column(String(60), default="")
    kcal: Mapped[Decimal] = mapped_column(Numeric(6, 1))  # por 100 g
    protein: Mapped[Decimal] = mapped_column(Numeric(5, 1))
    carbs: Mapped[Decimal] = mapped_column(Numeric(5, 1), default=0)
    fat: Mapped[Decimal] = mapped_column(Numeric(5, 1), default=0)
    default_portion_g: Mapped[int] = mapped_column(Integer, default=100)


class Dish(Base):
    __tablename__ = "dishes"

    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)
    owner_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    name: Mapped[str] = mapped_column(String(160))
    servings: Mapped[int] = mapped_column(Integer, default=1)
    cooked_weight_g: Mapped[Decimal | None] = mapped_column(Numeric(7, 1))
    ingredients: Mapped[list["DishIngredient"]] = relationship(back_populates="dish", cascade="all, delete-orphan", order_by="DishIngredient.position")


class DishIngredient(Base):
    __tablename__ = "dish_ingredients"

    id: Mapped[int] = mapped_column(primary_key=True)
    dish_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("dishes.id", ondelete="CASCADE"))
    position: Mapped[int] = mapped_column(Integer, default=0)
    food_id: Mapped[str | None] = mapped_column(ForeignKey("foods.id", ondelete="SET NULL"))
    # Copia de los valores por 100 g para que el plato no cambie si se borra el alimento
    name: Mapped[str] = mapped_column(String(160))
    grams: Mapped[Decimal] = mapped_column(Numeric(7, 1))
    kcal: Mapped[Decimal] = mapped_column(Numeric(6, 1))
    protein: Mapped[Decimal] = mapped_column(Numeric(5, 1))
    carbs: Mapped[Decimal] = mapped_column(Numeric(5, 1), default=0)
    fat: Mapped[Decimal] = mapped_column(Numeric(5, 1), default=0)
    dish: Mapped[Dish] = relationship(back_populates="ingredients")


class DiaryItem(Base):
    __tablename__ = "diary_items"
    __table_args__ = (CheckConstraint("meal in ('desayuno','almuerzo','merienda','cena','picoteo')", name="diary_meal"),)

    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    date: Mapped[date] = mapped_column(Date, index=True)
    meal: Mapped[str] = mapped_column(String(12))
    name: Mapped[str] = mapped_column(String(160))
    food_id: Mapped[str | None] = mapped_column(ForeignKey("foods.id", ondelete="SET NULL"))
    dish_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("dishes.id", ondelete="SET NULL"))
    grams: Mapped[Decimal] = mapped_column(Numeric(7, 1))
    # Valores ya calculados para la cantidad apuntada
    kcal: Mapped[Decimal] = mapped_column(Numeric(7, 1))
    protein: Mapped[Decimal] = mapped_column(Numeric(6, 1))
    carbs: Mapped[Decimal] = mapped_column(Numeric(6, 1))
    fat: Mapped[Decimal] = mapped_column(Numeric(6, 1))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=now_utc)
