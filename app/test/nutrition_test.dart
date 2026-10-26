import 'package:cuaderno/features/nutrition/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parseGrams acepta coma decimal y rechaza lo que no son gramos', () {
    expect(parseGrams('120'), 120);
    expect(parseGrams(' 62,5 '), 62.5);
    expect(parseGrams('62.5'), 62.5);
    for (final bad in ['', '0', '-5', 'cien', '5001']) {
      expect(parseGrams(bad), isNull, reason: bad);
    }
  });

  test('mealForHour propone la comida por la hora', () {
    expect([7, 13, 18, 22].map(mealForHour), ['desayuno', 'almuerzo', 'merienda', 'cena']);
  });

  test('Per100.forGrams escala los valores por 100 g', () {
    final v = const Per100(89, 1.1, 23, 0.3).forGrams(120);
    expect(v.kcal, closeTo(106.8, 0.001));
    expect(v.protein, closeTo(1.32, 0.001));
  });

  test('DiaryDay con el formato de la API, agrupado por comida', () {
    final day = DiaryDay.fromJson({
      'date': '2026-10-20',
      'items': [
        {'id': 'a', 'meal': 'almuerzo', 'name': 'Arroz marisco', 'grams': 407, 'kcal': 467.2, 'protein': 30.1, 'carbs': 60, 'fat': 9},
        {'id': 'b', 'meal': 'desayuno', 'name': 'Plátano', 'grams': 120, 'kcal': 106.8, 'protein': 1.3, 'carbs': 27.6, 'fat': 0.4},
        {'id': 'c', 'meal': 'almuerzo', 'name': 'Skyr', 'grams': 150, 'kcal': 94.5, 'protein': 16.5, 'carbs': 6, 'fat': 0},
      ],
      'kcal': 668.5,
      'protein': 47.9,
      'carbs': 93.6,
      'fat': 9.4,
      'kcal_target': 2000,
      'protein_target_g': 160,
    });
    expect(day.itemsOf('almuerzo').map((i) => i.name), ['Arroz marisco', 'Skyr']);
    expect(day.kcalOf('almuerzo'), closeTo(561.7, 0.001));
    expect(day.itemsOf('cena'), isEmpty);
    expect((day.kcalTarget, day.proteinTarget), (2000, 160));
  });

  test('Food y Dish con el formato de la API', () {
    final f = Food.fromJson({
      'id': 'b:skyr', 'name': 'Skyr natural', 'category': 'Lácteos', 'kcal': 63, 'protein': 11, 'carbs': 4, 'fat': 0.2,
      'default_portion_g': 150, 'mine': false,
    });
    expect((f.per100.kcal, f.defaultPortionG, f.mine), (63.0, 150, false));
  });

  test('Dish.fromSync hace las mismas cuentas que dish_out (test_nutrition_flow del backend)', () {
    // Arroz 300 g (350 kcal) + gambas 300 g (109 kcal), 3 raciones, 1200 g cocinado
    final d = Dish.fromSync('x', {
      'name': 'Arroz marisco', 'servings': 3, 'cooked_weight_g': 1200,
      'ingredients': [
        {'food_id': 'b:arroz_crudo', 'name': 'Arroz', 'grams': 300, 'kcal': 350, 'protein': 7, 'carbs': 78, 'fat': 0.6},
        {'food_id': 'b:gambas', 'name': 'Gambas', 'grams': 300, 'kcal': 109, 'protein': 24, 'carbs': 0, 'fat': 1.7},
      ],
    });
    expect((d.totalKcal, d.servingG), (1377.0, 400));
    expect(d.per100.kcal, closeTo(114.8, 0.05));
    expect(d.ingredients.first.per100.carbs, 78);
  });

  test('DishDraft calcula la ración como el backend: peso cocinado o, si no, crudo', () {
    final d = DishDraft(name: 'Arroz marisco', servings: 3, ingredients: [
      IngredientDraft(foodId: 'b:arroz_crudo', name: 'Arroz', kcalPer100: 350, proteinPer100: 7, grams: 300),
      IngredientDraft(foodId: 'b:gambas', name: 'Gambas', kcalPer100: 109, proteinPer100: 24, grams: 300),
    ]);
    expect(d.kcal, closeTo(1377, 0.001));
    expect(d.servingG, 200); // 600 g en crudo ÷ 3
    d.cookedWeightG = 1200;
    expect(d.servingG, 400);
    expect(d.kcalPerServing, closeTo(459, 0.001));
    expect(d.problem(), isNull);
    expect(d.toJson()['ingredients'], [
      {'food_id': 'b:arroz_crudo', 'name': 'Arroz', 'grams': 300.0, 'kcal': 350.0, 'protein': 7.0, 'carbs': 0.0, 'fat': 0.0},
      {'food_id': 'b:gambas', 'name': 'Gambas', 'grams': 300.0, 'kcal': 109.0, 'protein': 24.0, 'carbs': 0.0, 'fat': 0.0},
    ]);
    d.cookedWeightG = -1; // lo que deja un texto no válido
    expect(d.servingG, 200);
    expect(d.problem(), 'Revisa el peso cocinado.');
  });

  test('DishDraft.fromDish conserva los valores por 100 g y la copia de un alimento borrado', () {
    final dish = Dish.fromSync('x', {
      'name': 'Tortilla', 'servings': 2, 'cooked_weight_g': null,
      'ingredients': [
        {'food_id': 'b:huevo', 'name': 'Huevo', 'grams': 200, 'kcal': 143, 'protein': 12.5, 'carbs': 0.7, 'fat': 9.5},
        {'food_id': null, 'name': 'Aceite viejo', 'grams': 5, 'kcal': 900, 'protein': 0, 'carbs': 0, 'fat': 100},
      ],
    });
    final d = DishDraft.fromDish(dish);
    expect((d.ingredients.first.kcalPer100, d.ingredients.last.fatPer100), (143.0, 100.0));
    d.ingredients.first.grams = 100;
    expect(d.ingredients.first.protein, closeTo(12.5, 0.001));
    expect(d.problem(), isNull); // el servidor acepta la copia: el plato se puede seguir editando
    expect(d.toJson()['ingredients'][1]['food_id'], isNull);
  });

  test('búsqueda sin servidor: sin tildes, «empieza por» antes que «contiene» y los tuyos primero', () {
    Food f(String id, String name, {bool mine = false}) =>
        Food(id: id, name: name, category: '', per100: const Per100(1, 1, 1, 1), defaultPortionG: 100, mine: mine);
    final catalog = [f('b:platano', 'Plátano'), f('b:pan', 'Pan integral'), f('b:batido', 'Batido de plátano')];
    final own = [f('u:1', 'Plátano de Canarias', mine: true)];
    expect(searchFoods(own, catalog, 'platano').map((x) => x.id), ['u:1', 'b:platano', 'b:batido']);
    expect(searchFoods(own, catalog, 'PAN').map((x) => x.id), ['b:pan']);
    expect(searchFoods(own, catalog, '').map((x) => x.id), ['u:1', 'b:batido', 'b:pan', 'b:platano']);
    expect(searchFoods(own, catalog, '', limit: 2).length, 2);
  });

  test('una entrada del diario copia los valores para esos gramos, redondeados como el servidor', () {
    expect(const Per100(89, 1.1, 22.8, 0.3).entryValues(120), {'kcal': 106.8, 'protein': 1.3, 'carbs': 27.4, 'fat': 0.4});
    final day = DiaryDay.build(DateTime(2026, 10, 20), [
      DiaryItem(id: 'b', meal: 'cena', name: 'B', grams: 1, kcal: 100.04, protein: 1, carbs: 0, fat: 0, createdAt: DateTime.utc(2026, 10, 20, 20)),
      DiaryItem(id: 'a', meal: 'desayuno', name: 'A', grams: 1, kcal: 200.03, protein: 2, carbs: 0, fat: 0, createdAt: DateTime.utc(2026, 10, 20, 7)),
    ], kcalTarget: 2000, proteinTarget: 160);
    expect(day.items.map((i) => i.id), ['a', 'b']); // en el orden en que se apuntó
    expect(day.kcal, 300.1);
  });

  test('foodInput valida como el backend y acepta coma decimal', () {
    final ok = foodInput(name: ' Skyr ', kcal: '63', protein: '11', carbs: '4,2', fat: '', portion: '150');
    expect(ok.error, isNull);
    expect(ok.json, {'name': 'Skyr', 'kcal': 63.0, 'protein': 11.0, 'carbs': 4.2, 'fat': 0.0, 'default_portion_g': 150});
    String? err({String name = 'X', String kcal = '100', String protein = '10', String carbs = '10', String fat = '1', String portion = '100'}) =>
        foodInput(name: name, kcal: kcal, protein: protein, carbs: carbs, fat: fat, portion: portion).error;
    expect(err(name: ''), 'Ponle un nombre al alimento.');
    expect(err(kcal: ''), contains('kcal'));
    expect(err(kcal: '1000'), contains('kcal'));
    expect(err(protein: 'mucha'), contains('proteína'));
    expect(err(protein: '60', carbs: '50'), contains('suman más de 100'));
    expect(err(portion: '12,5'), contains('entero'));
  });
}
