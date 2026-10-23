"""Qué semana del plan toca en una fecha.

Las semanas se repiten en bucle desde el día en que se activó el plan:
semana = (días desde el inicio ÷ 7, entero) mód semanas + 1.
"""
from datetime import date


def current_week(started_on: date | None, weeks: int, d: date) -> int:
    if started_on is None or weeks <= 1:
        return 1
    # Con fechas anteriores al inicio, // y % de Python siguen el bucle hacia atrás
    return (d - started_on).days // 7 % weeks + 1
