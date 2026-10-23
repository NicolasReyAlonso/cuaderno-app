"""Peso, grasa estimada y ritmo semanal."""
from dataclasses import dataclass
from datetime import date, timedelta


def lean_mass(start_weight: float, start_bf_pct: float) -> float:
    return start_weight * (1 - start_bf_pct / 100)


def weight_for_bf(lbm: float, bf_pct: float) -> float:
    """Peso al que llegarías a ese % de grasa manteniendo la masa magra."""
    return lbm / (1 - bf_pct / 100)


def bf_at(lbm: float, weight: float) -> float:
    return max(0.0, (1 - lbm / weight) * 100)


def rolling_avg(points: list[tuple[date, float]], end: date, days: int = 7) -> float | None:
    start = end - timedelta(days=days - 1)
    xs = [v for d, v in points if start <= d <= end]
    return sum(xs) / len(xs) if xs else None


def monday(d: date) -> date:
    return d - timedelta(days=d.weekday())


@dataclass
class Week:
    monday: date
    avg_weight: float | None
    n_weights: int
    avg_kcal: float | None
    avg_protein: float | None
    waist_cm: float | None
    delta_kg: float | None = None
    delta_pct: float | None = None
    pace: str | None = None  # 'fast' | 'on_track' | 'slow' | 'stalled'


def classify(pct: float | None) -> str | None:
    if pct is None:
        return None
    if pct <= -1.1:
        return "fast"
    if pct <= -0.4:
        return "on_track"
    if pct <= -0.15:
        return "slow"
    return "stalled"


def weekly(rows: list[dict], start_weight: float | None, start_date: date | None) -> list[Week]:
    """rows: dicts con date, weight, waist, kcal, protein (cualquiera puede ser None)."""
    groups: dict[date, list[dict]] = {}
    for r in sorted(rows, key=lambda r: r["date"]):
        groups.setdefault(monday(r["date"]), []).append(r)

    def avg(rs, key):
        xs = [float(r[key]) for r in rs if r.get(key) is not None]
        return (sum(xs) / len(xs), len(xs)) if xs else (None, 0)

    weeks: list[Week] = []
    for m in sorted(groups):
        rs = groups[m]
        w, n = avg(rs, "weight")
        k, _ = avg(rs, "kcal")
        p, _ = avg(rs, "protein")
        waists = [float(r["waist"]) for r in rs if r.get("waist") is not None]
        weeks.append(Week(m, w, n, k, p, waists[-1] if waists else None))

    prev = None
    for wk in weeks:
        if wk.avg_weight is None:
            continue
        if prev is not None:
            base = prev.avg_weight
        elif start_weight is not None and (start_date is None or monday(start_date) != wk.monday):
            base = start_weight
        else:
            base = None
        if base:
            wk.delta_kg = wk.avg_weight - base
            wk.delta_pct = wk.delta_kg / base * 100
            wk.pace = classify(wk.delta_pct)
        prev = wk
    return weeks
