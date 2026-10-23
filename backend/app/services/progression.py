"""Lógica de progresión: qué ejercicio toca en cada hueco y qué sugerir.

Es la misma regla que el cuaderno web (doble progresión):
- Si en la última sesión hiciste todas las series en el máximo del rango con el
  mismo peso → sube peso (2,5 kg en básicos, 1–2 kg en aislamiento,
  2,5 kg de lastre o +10 s en ejercicios de tiempo).
- Si alguna serie quedó por debajo del mínimo → repite el peso.
- Si no → mismo peso y busca una repetición más.
"""
from dataclasses import dataclass
from decimal import Decimal


@dataclass(frozen=True)
class SetResult:
    load_kg: Decimal | float | None
    reps: int | None


@dataclass(frozen=True)
class Hint:
    kind: str  # 'up' | 'rep' | 'hold' | 'new'
    text: str


def suggest(*, sets_planned: int, rep_min: int, rep_max: int, unit: str, load_mode: str,
            is_compound: bool, last: list[SetResult] | None) -> Hint | None:
    target = f"{rep_max} {'s' if unit == 'seconds' else 'reps'}"
    if not last:
        if load_mode == "extra":
            return Hint("new", f"Primera vez: sin peso extra, busca llegar a {target}")
        return Hint("new", f"Primera vez: elige un peso con el que llegues a {target} dejando 1–2 en reserva")
    done = [s for s in last if s.reps is not None]
    if not done:
        return None
    loads = [float(s.load_kg or 0) for s in done]
    same_load = all(x == loads[0] for x in loads)
    if len(done) >= sets_planned and all(s.reps >= rep_max for s in done) and same_load:
        if unit == "seconds":
            return Hint("up", "Añade 10 s o lastre")
        if load_mode == "extra":
            return Hint("up", "Añade 2,5 kg de lastre")
        return Hint("up", "Sube 2,5 kg" if is_compound else "Sube 1–2 kg")
    if any(s.reps < rep_min for s in done):
        return Hint("hold", "Repite el mismo peso")
    return Hint("rep", "Mismo peso, busca +1 rep")


def effective_range(slot_unit: str, slot_min: int, slot_max: int, ex_unit: str,
                    ex_min: int | None, ex_max: int | None, is_slot_exercise: bool) -> tuple[int, int]:
    """Rango para el ejercicio realmente hecho.

    Una alternativa hereda el rango del hueco salvo que cambie de unidad
    (p. ej. rueda en repeticiones → plancha en segundos) y tenga rango propio.
    """
    if is_slot_exercise or slot_unit == ex_unit or ex_min is None or ex_max is None:
        return slot_min, slot_max
    return ex_min, ex_max
