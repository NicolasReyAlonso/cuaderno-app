import uuid
from datetime import date

from fastapi import APIRouter, HTTPException, Query, Response, status
from sqlalchemy import or_, select
from sqlalchemy.orm import selectinload

from ..models import DiaryItem, Dish, DishIngredient, Food
from ..schemas import DiaryDayOut, DiaryItemIn, DiaryItemOut, DishIn, DishOut, FoodIn, FoodOut, IngredientOut
from ..security import DB, CurrentUser

router = APIRouter(tags=["comidas"])


def _f(v) -> float:
    return float(v) if v is not None else 0.0


def _norm(s: str) -> str:
    import unicodedata

    return "".join(c for c in unicodedata.normalize("NFD", s.lower()) if unicodedata.category(c) != "Mn")


def _visible_food(db, user, food_id: str) -> Food:
    f = db.get(Food, food_id)
    if f is None or (f.owner_id is not None and f.owner_id != user.id):
        raise HTTPException(404, "Alimento no encontrado.")
    return f


def _food_out(f: Food, user) -> FoodOut:
    o = FoodOut.model_validate(f)
    o.mine = f.owner_id == user.id
    return o


# ---------------------------------------------------------------- alimentos
@router.get("/foods", response_model=list[FoodOut])
def search_foods(user: CurrentUser, db: DB, q: str = "", limit: int = Query(20, ge=1, le=100)):
    foods = db.scalars(select(Food).where(or_(Food.owner_id.is_(None), Food.owner_id == user.id))).all()
    nq = _norm(q.strip())
    if nq:
        starts = [f for f in foods if _norm(f.name).startswith(nq)]
        has = [f for f in foods if nq in _norm(f.name) and f not in starts]
        foods = starts + has
    else:
        foods = sorted(foods, key=lambda f: (f.owner_id is None, f.name))
    mine_first = sorted(foods, key=lambda f: f.owner_id is None)
    return [_food_out(f, user) for f in mine_first[:limit]]


@router.post("/foods", response_model=FoodOut, status_code=status.HTTP_201_CREATED)
def create_food(body: FoodIn, user: CurrentUser, db: DB):
    f = Food(id="u:" + uuid.uuid4().hex[:12], owner_id=user.id, **body.model_dump())
    db.add(f)
    db.commit()
    return _food_out(f, user)


@router.delete("/foods/{food_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_food(food_id: str, user: CurrentUser, db: DB):
    f = db.get(Food, food_id)
    if f is None or f.owner_id != user.id:
        raise HTTPException(404, "Solo puedes borrar tus propios alimentos.")
    db.delete(f)
    db.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)


# ---------------------------------------------------------------- platos
def dish_out(d: Dish) -> DishOut:
    tk = sum(_f(i.kcal) * _f(i.grams) / 100 for i in d.ingredients)
    tp = sum(_f(i.protein) * _f(i.grams) / 100 for i in d.ingredients)
    tc = sum(_f(i.carbs) * _f(i.grams) / 100 for i in d.ingredients)
    tf = sum(_f(i.fat) * _f(i.grams) / 100 for i in d.ingredients)
    raw = sum(_f(i.grams) for i in d.ingredients)
    weight = _f(d.cooked_weight_g) or raw or 1
    return DishOut(id=d.id, name=d.name, servings=d.servings, cooked_weight_g=_f(d.cooked_weight_g) or None,
                   ingredients=[IngredientOut(food_id=i.food_id, name=i.name, grams=_f(i.grams), kcal=round(_f(i.kcal) * _f(i.grams) / 100, 1))
                                for i in d.ingredients],
                   total_kcal=round(tk, 1), total_protein=round(tp, 1),
                   per100_kcal=round(tk / weight * 100, 1), per100_protein=round(tp / weight * 100, 2),
                   per100_carbs=round(tc / weight * 100, 2), per100_fat=round(tf / weight * 100, 2),
                   serving_g=round(weight / d.servings))


def _own_dish(db, user, dish_id: uuid.UUID) -> Dish:
    d = db.scalar(select(Dish).where(Dish.id == dish_id).options(selectinload(Dish.ingredients)))
    if d is None or d.owner_id != user.id:
        raise HTTPException(404, "Plato no encontrado.")
    return d


def _fill_dish(db, user, d: Dish, body: DishIn):
    d.name, d.servings, d.cooked_weight_g = body.name, body.servings, body.cooked_weight_g
    d.ingredients.clear()
    for pos, ing in enumerate(body.ingredients):
        f = _visible_food(db, user, ing.food_id)
        d.ingredients.append(DishIngredient(position=pos, food_id=f.id, name=f.name, grams=ing.grams, kcal=f.kcal,
                                            protein=f.protein, carbs=f.carbs, fat=f.fat))


@router.get("/dishes", response_model=list[DishOut])
def list_dishes(user: CurrentUser, db: DB):
    ds = db.scalars(select(Dish).where(Dish.owner_id == user.id).options(selectinload(Dish.ingredients)).order_by(Dish.name))
    return [dish_out(d) for d in ds]


@router.post("/dishes", response_model=DishOut, status_code=status.HTTP_201_CREATED)
def create_dish(body: DishIn, user: CurrentUser, db: DB):
    d = Dish(owner_id=user.id, name=body.name)
    _fill_dish(db, user, d, body)
    db.add(d)
    db.commit()
    return dish_out(d)


@router.put("/dishes/{dish_id}", response_model=DishOut)
def update_dish(dish_id: uuid.UUID, body: DishIn, user: CurrentUser, db: DB):
    d = _own_dish(db, user, dish_id)
    _fill_dish(db, user, d, body)
    db.commit()
    return dish_out(d)


@router.delete("/dishes/{dish_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_dish(dish_id: uuid.UUID, user: CurrentUser, db: DB):
    db.delete(_own_dish(db, user, dish_id))
    db.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)


# ---------------------------------------------------------------- diario
@router.get("/diary/{d}", response_model=DiaryDayOut)
def diary_day(d: date, user: CurrentUser, db: DB):
    items = db.scalars(select(DiaryItem).where(DiaryItem.user_id == user.id, DiaryItem.date == d).order_by(DiaryItem.created_at)).all()
    tot = lambda k: round(sum(_f(getattr(i, k)) for i in items), 1)  # noqa: E731
    return DiaryDayOut(date=d, items=[DiaryItemOut.model_validate(i) for i in items], kcal=tot("kcal"), protein=tot("protein"),
                       carbs=tot("carbs"), fat=tot("fat"), kcal_target=user.kcal_target, protein_target_g=user.protein_target_g)


@router.post("/diary/{d}/items", response_model=DiaryItemOut, status_code=status.HTTP_201_CREATED)
def add_item(d: date, body: DiaryItemIn, user: CurrentUser, db: DB):
    if (body.food_id is None) == (body.dish_id is None):
        raise HTTPException(422, "Indica un alimento o un plato, no los dos.")
    if body.food_id:
        f = _visible_food(db, user, body.food_id)
        name, per = f.name, (_f(f.kcal), _f(f.protein), _f(f.carbs), _f(f.fat))
    else:
        dish = dish_out(_own_dish(db, user, body.dish_id))
        name, per = dish.name, (dish.per100_kcal, dish.per100_protein, dish.per100_carbs, dish.per100_fat)
    k = body.grams / 100
    item = DiaryItem(user_id=user.id, date=d, meal=body.meal, name=name, food_id=body.food_id, dish_id=body.dish_id,
                     grams=body.grams, kcal=round(per[0] * k, 1), protein=round(per[1] * k, 1),
                     carbs=round(per[2] * k, 1), fat=round(per[3] * k, 1))
    db.add(item)
    db.commit()
    return DiaryItemOut.model_validate(item)


@router.delete("/diary/items/{item_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_item(item_id: uuid.UUID, user: CurrentUser, db: DB):
    i = db.get(DiaryItem, item_id)
    if i is None or i.user_id != user.id:
        raise HTTPException(404, "Entrada no encontrada.")
    db.delete(i)
    db.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)
